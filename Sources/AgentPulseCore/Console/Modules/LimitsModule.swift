import Foundation

/// Лимиты: кольца по сервисам, подпись самого тесного окна, вкладка с обоими окнами.
public struct LimitsModule: ConsoleModule {
    public let id = ConsoleModuleID.limits
    public let title = "Лимиты"
    public let accent: UInt32 = 0x34C759
    public var book = LimitsBook()

    public init() {}

    public func priority(now: Date) -> ConsolePriority? {
        if LimitService.allCases.contains(where: { book.isCritical($0, now: now) }) { return .limitCritical }
        return book.snapshots.isEmpty ? nil : .limitsNormal
    }

    public func capsule(now: Date) -> CapsuleContent {
        let rings = LimitService.allCases.filter { book.snapshots[$0] != nil }.map { service in
            let top = book.tightest(service, now: now)
            return CapsuleRing(
                service: service, fraction: top.map { min(1, Double($0.usedPercent) / 100) },
                zone: top?.zone ?? .normal, stale: top?.stale ?? false
            )
        }
        let top = LimitService.allCases.compactMap { book.tightest($0, now: now) }.max { $0.usedPercent < $1.usedPercent }
        return CapsuleContent(rings: rings, label: top.map { LimitText.label($0, now: now) } ?? LimitText.noData, labelService: top?.service)
    }

    public mutating func tick(now: Date) -> [ToolSignal] {
        book.tick(now: now)
    }
}
