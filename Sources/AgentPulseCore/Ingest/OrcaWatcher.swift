import CoreServices
import Foundation

/// Следит за снимком агентов Orca через FSEvents и превращает смену снимка в события (`OrcaStatus.diff`).
/// При старте прошлое не проигрывается: из снимка берутся только агенты, которые работают прямо сейчас (`OrcaStatus.seed`).
public final class OrcaWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable ([AgentEvent]) -> Void

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/orca/agent-hooks", directoryHint: .isDirectory)
    }

    public static let snapshotName = "last-status.json"

    private let root: String
    private let includeClaude: Bool
    private let includeCodex: Bool
    private let handler: Handler
    private let queue = DispatchQueue(label: "agentpulse.orca")
    private var last: [String: OrcaStatus.Entry] = [:]
    /// Временные сессии агентов с хуками Pulse, взятые из снимка при старте.
    private var provisional: Set<String> = []
    private var stream: FSEventStreamRef?

    /// `includeClaude` — показывать и Claude Code из Orca; нужно, только если хуки Pulse не стоят.
    /// `includeCodex` — то же для Codex: его хуки в `~/.codex/hooks.json` тоже могут звать `pulse-hook`.
    public init(root: URL = OrcaWatcher.defaultRoot, includeClaude: Bool, includeCodex: Bool = true, handler: @escaping Handler) {
        self.root = CoworkWatcher.realPath(root.path(percentEncoded: false))
        self.includeClaude = includeClaude
        self.includeCodex = includeCodex
        self.handler = handler
    }

    deinit {
        stop()
    }

    private var snapshotPath: String { root + "/" + Self.snapshotName }

    /// `false` — Orca на этой машине не запускалась или формат снимка незнакомый.
    @discardableResult
    public func start() -> Bool {
        guard FileManager.default.fileExists(atPath: root) else { return false }
        if let data = FileManager.default.contents(atPath: snapshotPath) {
            guard let snapshot = OrcaStatus.parse(snapshot: data) else { return false }
            let seed = OrcaStatus.seed(snapshot, includeClaude: includeClaude, includeCodex: includeCodex)
            queue.sync {
                last = snapshot
                provisional = seed.provisional
            }
            if !seed.events.isEmpty {
                let handler = handler
                queue.async { handler(seed.events) }
            }
        }

        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<OrcaWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self)
            let changed = (0..<count).contains { (list[$0] as? String)?.hasSuffix("/" + OrcaWatcher.snapshotName) == true }
            if changed { watcher.reload() }
        }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [root] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags
        ) else { return false }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
        return true
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Вызывается на `queue`. Недочитанный или чужой снимок пропускаем: следующая запись его заменит.
    private func reload() {
        guard
            let data = FileManager.default.contents(atPath: snapshotPath),
            let snapshot = OrcaStatus.parse(snapshot: data)
        else { return }
        let events = OrcaStatus.diff(from: last, to: snapshot, includeClaude: includeClaude, includeCodex: includeCodex)
            + OrcaStatus.settle(&provisional, snapshot: snapshot)
        last = snapshot
        if !events.isEmpty { handler(events) }
    }
}
