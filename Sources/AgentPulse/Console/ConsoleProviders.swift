import AgentPulseCore
import AppKit
import QuickLookThumbnailing

/// Миниатюры файлов на полке.
enum ShelfThumbnails {
    /// Превью картинки для плитки; не вышло — плитка покажет лист с меткой.
    static func preview(for url: URL) async -> NSImage? {
        let request = await QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 112, height: 76), scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }

    /// Миниатюра файла; не вышло — иконка файла.
    static func image(for url: URL) async -> NSImage {
        let request = await QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 40, height: 40), scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail
        )
        if let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return thumbnail.nsImage
        }
        return await NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Снимки экрана на полку: следим за папкой снимков, название снимка не важно — система помечает его атрибутом.
@MainActor
final class ScreenshotWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<URL> = []

    static var folder: URL {
        let defaults = UserDefaults.standard.persistentDomain(forName: "com.apple.screencapture")
        if let location = defaults?["location"] as? String {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop", directoryHint: .isDirectory)
    }

    private func screenshots(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { getxattr($0.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0 }
    }

    func start(onNew: @escaping ([URL]) -> Void) {
        stop()
        let folder = Self.folder
        known = Set(screenshots(in: folder))
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                // Система дописывает атрибут чуть позже файла.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        let current = Set(self.screenshots(in: folder))
                        let fresh = current.subtracting(self.known)
                        self.known = current
                        if !fresh.isEmpty { onNew(Array(fresh)) }
                    }
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
