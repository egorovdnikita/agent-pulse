import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct NetworkRecoveryTests {
    @Test func initialAndDuplicateOnlineDoNotRefreshButRecoveryRespectsThrottle() {
        let now = Date(timeIntervalSince1970: 1000)
        var recovery = NetworkRecovery()
        #expect(recovery.receive(.networkBack, now: now, lastAttempt: .distantPast) == nil)
        _ = recovery.receive(.networkLost, now: now, lastAttempt: now)
        #expect(recovery.receive(.networkBack, now: now.addingTimeInterval(20), lastAttempt: now) == 40)
        #expect(recovery.receive(.networkBack, now: now.addingTimeInterval(30), lastAttempt: now) == nil)
        _ = recovery.receive(.networkLost, now: now, lastAttempt: now)
        #expect(recovery.receive(.networkBack, now: now.addingTimeInterval(70), lastAttempt: now) == 0)
    }
}
