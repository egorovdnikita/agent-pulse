import Foundation

public struct SessionInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public var source: AgentEvent.Source
    public var context: String?
    public var hostBundleId: String?
    public var phase: Phase
    public var phaseSince: Date
    public var lastEventAt: Date
    /// Ключевые шаги текущей задачи, без повторов подряд.
    public var timeline: [String] = []

    public static let timelineLimit = 20

    public init(id: String, source: AgentEvent.Source, phase: Phase = .idle, at date: Date) {
        self.id = id
        self.source = source
        self.phase = phase
        self.phaseSince = date
        self.lastEventAt = date
    }

    public mutating func set(_ phase: Phase, at date: Date) {
        guard phase != self.phase else { return }
        self.phase = phase
        phaseSince = date
    }

    mutating func appendStep(_ text: String) {
        guard timeline.last != text else { return }
        timeline.append(text)
        if timeline.count > Self.timelineLimit { timeline.removeFirst() }
    }
}

/// Стейт-машина на сессию. Чистая структура — удобно тестировать; `SessionStore` оборачивает её в actor.
public struct SessionTable: Sendable {
    public private(set) var sessions: [String: SessionInfo] = [:]
    private var aggregators: [String: Aggregator] = [:]
    public var clock: PhaseClock

    public init(clock: PhaseClock = PhaseClock()) {
        self.clock = clock
    }

    /// Свежие сессии первыми.
    public var ordered: [SessionInfo] {
        sessions.values.sorted { $0.lastEventAt > $1.lastEventAt }
    }

    public mutating func apply(_ event: AgentEvent) {
        let id = event.sessionId
        if event.kind == .sessionEnded {
            sessions[id] = nil
            aggregators[id] = nil
            return
        }

        var session = sessions[id] ?? SessionInfo(id: id, source: event.source, at: event.ts)
        var aggregator = aggregators[id] ?? Aggregator()
        session.lastEventAt = event.ts
        if let context = event.context { session.context = context }
        if let host = event.hostBundleId { session.hostBundleId = host }

        switch event.kind {
        case .promptSubmitted:
            aggregator.reset()
            session.timeline.removeAll()
            session.set(.received, at: event.ts)
        case .toolStarted:
            let tool = event.tool ?? "unknown"
            let classified = Humanizer.classify(tool: tool)
            let text = aggregator.text(
                for: classified.kind,
                target: classified.target,
                original: event.summary ?? classified.text
            )
            session.set(.working(Activity(tool: tool, kind: classified.kind, target: classified.target, text: text)), at: event.ts)
            session.appendStep(text)
        case .toolFinished:
            // Ошибка инструмента — не провал задачи: агент обычно исправляется сам. `failed` не выставляем.
            session.set(.thinking, at: event.ts)
        case .awaitingUser:
            session.set(.awaitingUser(reason: event.awaitReason ?? .input, message: event.summary ?? ""), at: event.ts)
        case .subtaskDone:
            session.appendStep("Субагент закончил")
        case .stopped:
            session.set(.done(summary: event.summary ?? "Готово"), at: event.ts)
        case .error:
            session.set(.failed(event.summary ?? "Ошибка"), at: event.ts)
        case .sessionEnded:
            break
        }

        sessions[id] = session
        aggregators[id] = aggregator
    }

    public mutating func tick(now: Date) {
        for id in sessions.keys {
            clock.advance(&sessions[id]!, now: now)
        }
    }
}

public actor SessionStore {
    private var table: SessionTable

    public init(clock: PhaseClock = PhaseClock()) {
        table = SessionTable(clock: clock)
    }

    public func apply(_ event: AgentEvent) -> [SessionInfo] {
        table.apply(event)
        return table.ordered
    }

    public func tick(now: Date) -> [SessionInfo] {
        table.tick(now: now)
        return table.ordered
    }
}
