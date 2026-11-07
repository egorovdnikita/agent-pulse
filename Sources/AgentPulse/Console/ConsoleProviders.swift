import AgentPulseCore
import AppKit
import CoreAudio
import EventKit
import QuickLookThumbnailing

/// Календари: только чтение, события живут в памяти Пульта.
@MainActor
final class CalendarProvider {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var timer: Timer?

    static var authorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Цвет календаря, как в приложении «Календарь».
    private static func hex(_ color: CGColor?) -> UInt32? {
        guard let color = color?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let parts = color.components, parts.count >= 3 else { return nil }
        let byte = { (value: CGFloat) in UInt32(min(255, max(0, (value * 255).rounded()))) }
        return byte(parts[0]) << 16 | byte(parts[1]) << 8 | byte(parts[2])
    }

    static var denied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted
    }

    /// Спрашивает при включении модуля, а не при установке.
    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func start(onChange: @escaping ([MeetingEvent]) -> Void) {
        stop()
        let reload: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            onChange(self.fetch())
        }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { reload() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { reload() }
        }
        reload()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        timer?.invalidate()
        timer = nil
    }

    private func fetch() -> [MeetingEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let from = calendar.date(byAdding: .day, value: -31, to: start),
              let to = calendar.date(byAdding: .day, value: 62, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).filter { event in
            // Отклонённое приглашение — не встреча.
            event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined
        }.map { event in
            MeetingEvent(
                id: "\(event.eventIdentifier ?? "")|\(event.startDate.timeIntervalSince1970)",
                title: event.title ?? "Без названия", start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                link: MeetingLinks.find(url: event.url, location: event.location, notes: event.notes),
                color: event.calendar.flatMap { Self.hex($0.cgColor) }
            )
        }
    }
}

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

/// Источник «что играет». Две реализации за одним протоколом: что не работает, помечается «недоступен».
@MainActor
protocol MediaPlayerSense: AnyObject {
    func start(onUpdate: @escaping @MainActor @Sendable (MediaRemoteStream.Update) -> Void, onFailure: @escaping @MainActor @Sendable () -> Void)
    func stop()
    func send(_ command: MediaCommand)
    func seek(to position: TimeInterval)
}

/// MediaRemote через системный процесс-посредник: прямой доступ закрыт с macOS 15.4, а `/usr/bin/perl` его имеет.
@MainActor
final class AdapterMediaSense: MediaPlayerSense {
    private var process: Process?
    private var failures = 0
    private let script: URL
    private let framework: URL

    init?() {
        guard let resources = Bundle.main.resourceURL?.appending(path: "MediaAdapter", directoryHint: .isDirectory) else { return nil }
        script = resources.appending(path: "mediaremote-adapter.pl")
        framework = resources.appending(path: "MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: script.path), FileManager.default.fileExists(atPath: framework.path) else { return nil }
    }

    private func command(_ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path(percentEncoded: false), framework.path(percentEncoded: false)] + arguments
        process.standardError = FileHandle.nullDevice
        return process
    }

    func start(onUpdate: @escaping @MainActor @Sendable (MediaRemoteStream.Update) -> Void, onFailure: @escaping @MainActor @Sendable () -> Void) {
        let process = command(["stream", "--no-diff", "--allow-missing-title", "--debounce=200"])
        let output = Pipe()
        process.standardOutput = output
        final class LineBuffer: @unchecked Sendable { var data = Data() }
        let buffer = LineBuffer()
        output.fileHandleForReading.readabilityHandler = { handle in
            buffer.data.append(handle.availableData)
            while let newline = buffer.data.firstIndex(of: 0x0A) {
                let line = Data(buffer.data[buffer.data.startIndex..<newline])
                buffer.data = Data(buffer.data[buffer.data.index(after: newline)...])
                guard let update = MediaRemoteStream.parse(line) else { continue }
                DispatchQueue.main.async { MainActor.assumeIsolated { onUpdate(update) } }
            }
        }
        process.terminationHandler = { [weak self] finished in
            output.fileHandleForReading.readabilityHandler = nil
            let failed = finished.terminationReason == .uncaughtSignal ? false : finished.terminationStatus != 0
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.process === finished else { return }
                    self.process = nil
                    self.failures += failed ? 1 : 0
                    // Поток не должен кончаться: перезапускаем, а два сбоя подряд — значит, не работает.
                    if self.failures >= 2 { onFailure() } else { self.start(onUpdate: onUpdate, onFailure: onFailure) }
                }
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            onFailure()
        }
    }

    func stop() {
        let running = process
        process = nil
        running?.terminate()
    }

    func send(_ command: MediaCommand) {
        try? self.command(["send", String(command.rawValue)]).run()
    }

    func seek(to position: TimeInterval) {
        try? command(["seek", String(Int(position * 1_000_000))]).run()
    }
}

/// Запасной путь: AppleScript для «Музыки» и Spotify. Разрешение Automation спрашивается при первом управлении.
@MainActor
final class ScriptMediaSense: MediaPlayerSense {
    private static let apps = ["com.apple.Music": "Music", "com.spotify.client": "Spotify"]
    private var timer: Timer?

    private var running: String? {
        Self.apps.first { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.key).isEmpty }?.value
    }

    /// Запущенное приложение нельзя случайно запустить скриптом: проверяем перед каждым обращением.
    private func run(_ body: String) -> String? {
        guard let app = running else { return nil }
        let source = "tell application \"\(app)\"\n\(body)\nend tell"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result?.stringValue : nil
    }

    func start(onUpdate: @escaping @MainActor @Sendable (MediaRemoteStream.Update) -> Void, onFailure: @escaping @MainActor @Sendable () -> Void) {
        let poll: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            let script = """
                if player state is stopped then return ""
                set t to current track
                return (player state as string) & (ASCII character 10) & (name of t) & (ASCII character 10) & (artist of t) \
                & (ASCII character 10) & (player position as string)
                """
            guard let text = self.run(script), !text.isEmpty else {
                onUpdate(.nothing)
                return
            }
            let parts = text.components(separatedBy: "\n")
            guard parts.count >= 4 else { return }
            onUpdate(.playing(NowPlaying(
                title: parts[1], artist: parts[2], isPlaying: parts[0] == "playing", duration: nil,
                elapsed: Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0, at: Date()
            )))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in MainActor.assumeIsolated { poll() } }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func send(_ command: MediaCommand) {
        switch command {
        case .togglePlayPause: _ = run("playpause")
        case .next: _ = run("next track")
        case .previous: _ = run("previous track")
        }
    }

    func seek(to position: TimeInterval) {
        _ = run("set player position to \(position)")
    }
}

/// Громкость системного выхода.
enum SystemVolume {
    private static func device() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    /// Канал 0 есть не у всех устройств: тогда левый и правый.
    private static func channels(_ device: AudioObjectID) -> [UInt32] {
        var probe = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: 0
        )
        if AudioObjectHasProperty(device, &probe) { return [0] }
        return [1, 2]
    }

    static func get() -> Double? {
        guard let device = device(), let channel = channels(device).first else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: channel
        )
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    static func set(_ volume: Double) {
        guard let device = device() else { return }
        var value = Float32(volume)
        for channel in channels(device) {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: channel
            )
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
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
