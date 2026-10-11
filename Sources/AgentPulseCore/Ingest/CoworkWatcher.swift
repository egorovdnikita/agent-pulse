import CoreServices
import Foundation

/// Следит за журналами Cowork через FSEvents: ноль опроса, событие приходит в пределах ~50 ms после записи.
/// При старте только запоминает конец существующих журналов — прошлое не проигрывается.
public final class CoworkWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable ([AgentEvent]) -> Void

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Claude/local-agent-mode-sessions", directoryHint: .isDirectory)
    }

    public static let journalName = "audit.jsonl"

    private let root: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "agentpulse.cowork")
    private var tailer = JSONLTailer()
    private var stream: FSEventStreamRef?
    private var startedAt = Date()

    public init(root: URL = CoworkWatcher.defaultRoot, handler: @escaping Handler) {
        // FSEvents присылает настоящие пути (`/private/var/...`), а `resolvingSymlinksInPath` срезает `/private`.
        self.root = Self.realPath(root.path(percentEncoded: false))
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// `false` — Cowork на этой машине не запускался, следить не за чем.
    @discardableResult
    public func start() -> Bool {
        guard FileManager.default.fileExists(atPath: root) else { return false }
        startedAt = Date()
        queue.sync {
            for path in Self.journals(under: root) { tailer.prime(path) }
        }

        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<CoworkWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self)
            watcher.handle((0..<count).compactMap { list[$0] as? String })
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

    /// Вызывается на `queue`.
    private func handle(_ paths: [String]) {
        var events: [AgentEvent] = []
        for path in Set(paths) where path.hasSuffix("/" + Self.journalName) {
            if !tailer.isTracking(path) {
                guard FileManager.default.fileExists(atPath: path) else { continue }
                // Журнал новой сессии читаем целиком, старый (просто не попался при старте) — с конца.
                let created = (try? FileManager.default.attributesOfItem(atPath: path)[.creationDate] as? Date) ?? .distantPast
                if created >= startedAt { tailer.track(path) } else { tailer.prime(path) }
            }
            let now = Date()
            for line in tailer.readNewLines(path) {
                events += CoworkAudit.parse(line: line, now: now)
            }
        }
        if !events.isEmpty { handler(events) }
    }

    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func journals(under root: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        var result: [String] = []
        while let relative = enumerator.nextObject() as? String {
            if relative.hasSuffix("/outputs") || relative.hasSuffix("/uploads") {
                enumerator.skipDescendants()
            } else if relative.hasSuffix(journalName) {
                result.append(root + "/" + relative)
            }
        }
        return result
    }
}
