import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct LimitsCacheTests {
    @Test func restartKeepsBothServicesAndFreshness() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "limits.json")
        let received = Date(timeIntervalSince1970: 100_000)
        let now = received.addingTimeInterval(LimitsBook.staleAfter + 1)
        var book = LimitsBook()
        for service in LimitService.allCases {
            _ = book.ingest(LimitSnapshot(service: service, windows: [
                LimitWindow(kind: .fiveHour, usedPercent: 42, resetsAt: now.addingTimeInterval(100)),
                LimitWindow(kind: .week, usedPercent: 67, resetsAt: now.addingTimeInterval(200))
            ], at: received), now: received)
        }
        book.save(to: url)
        let restored = LimitsBook.load(from: url, now: now)
        for service in LimitService.allCases {
            let reading = try #require(restored.reading(service, .fiveHour, now: now))
            #expect(reading.usedPercent == 42)
            #expect(reading.stale)
            #expect(restored.snapshots[service]?.at == received)
            #expect(restored.reading(service, .week, now: now)?.usedPercent == 67)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func restartResetsExpiredWindowAndRejectsOldCache() {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let received = Date(timeIntervalSince1970: 100_000)
        var book = LimitsBook()
        _ = book.ingest(LimitSnapshot(service: .claude, windows: [
            LimitWindow(kind: .fiveHour, usedPercent: 100, resetsAt: received.addingTimeInterval(10))
        ], at: received), now: received)
        book.save(to: url)
        let now = received.addingTimeInterval(20)
        let reading = LimitsBook.load(from: url, now: now).reading(.claude, .fiveHour, now: now)
        #expect(reading?.usedPercent == 0)
        #expect(reading?.zone == .normal)
        #expect(reading?.resetsAt == nil)
        #expect(LimitsBook.load(from: url, now: received.addingTimeInterval(31 * 86400)).snapshots.isEmpty)
    }

    @Test func damagedOrMissingCacheIsEmpty() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(LimitsBook.load(from: url).snapshots.isEmpty)
        try Data("broken".utf8).write(to: url)
        #expect(LimitsBook.load(from: url).snapshots.isEmpty)
    }
}
