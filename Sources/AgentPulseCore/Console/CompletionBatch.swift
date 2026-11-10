import Foundation

/// Близкие завершения объединяются; разрешения и ошибки всегда идут сразу своим каналом.
public struct CompletionBatch: Sendable {
    public struct Entry: Sendable {
        public let id: String
        public let source: AgentEvent.Source
        public let host: String?
        public let agent: String?
        init(_ event: AgentEvent) { id = event.sessionId; source = event.source; host = event.hostBundleId; agent = event.agent }
    }
    public static let interval: TimeInterval = 2
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var began: Date?
    public init() {}
    public mutating func observe(_ event: AgentEvent) {
        if event.kind == .stopped, !event.isError {
            if entries[event.sessionId] == nil { order.append(event.sessionId) }
            entries[event.sessionId] = Entry(event)
            if began == nil { began = event.ts }
        } else if [.promptSubmitted, .awaitingUser, .error, .sessionEnded, .rateLimited, .stopped].contains(event.kind) {
            entries[event.sessionId] = nil
            order.removeAll { $0 == event.sessionId }
            if entries.isEmpty { began = nil }
        }
    }
    public mutating func takeReady(now: Date, allowed: Bool = true) -> [Entry]? {
        guard allowed, let began, now.timeIntervalSince(began) >= Self.interval else { return nil }
        let result = order.compactMap { entries[$0] }
        entries = [:]; order = []; self.began = nil
        return result.isEmpty ? nil : result
    }
}
