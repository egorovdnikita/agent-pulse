import AgentPulseCore
import AppKit

extension ConsoleModel {
    func shelfTargets(from url: URL? = nil) -> [URL] {
        if let url { return shelfSelection.dragged(from: url, order: shelfOrder) }
        return shelfOrder.filter(shelfSelection.contains)
    }

    func openShelfFiles(from url: URL? = nil) {
        for file in shelfTargets(from: url) where FileManager.default.isReadableFile(atPath: file.path) {
            NSWorkspace.shared.open(file)
        }
    }

    func copyShelfPaths(from url: URL? = nil) {
        let urls = shelfTargets(from: url)
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    func copyShelfFiles() {
        let urls = shelfTargets().filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
    }

    func revealShelfFiles(from url: URL? = nil) {
        let urls = shelfTargets(from: url).filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
