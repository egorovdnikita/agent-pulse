import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct LimitWindowAgePersistenceTests {
    @Test func oldWeekStaysOldAfterSavingAndRestart() throws {
        let now = Date(); let old = now.addingTimeInterval(-3600)
        var book = LimitsBook()
        _ = book.ingest(.init(service: .claude, windows: [.init(kind: .week, usedPercent: 70, resetsAt: nil)], at: old), now: now)
        _ = book.ingest(.init(service: .claude, windows: [.init(kind: .fiveHour, usedPercent: 20, resetsAt: nil)], at: now), now: now)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        book.save(to: url)
        let restored = LimitsBook.load(from: url, now: now)
        #expect(restored.reading(.claude, .week, now: now)?.stale == true)
        #expect(restored.reading(.claude, .fiveHour, now: now)?.stale == false)
        #expect(restored.snapshots[.claude]?.windows.first { $0.kind == .week }?.observedAt == old)
    }
    @Test func legacyWindowUsesSnapshotDate() throws {
        let now = Date(); let old = now.addingTimeInterval(-3600)
        let snapshot = LimitSnapshot(service: .codex, windows: [.init(kind: .fiveHour, usedPercent: 10, resetsAt: nil)], at: old)
        let data = try JSONEncoder().encode([snapshot])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let restored = LimitsBook.load(from: url, now: now)
        #expect(restored.reading(.codex, .fiveHour, now: now)?.stale == true)
        #expect(restored.snapshots[.codex]?.windows.first?.observedAt == old)
    }
}
