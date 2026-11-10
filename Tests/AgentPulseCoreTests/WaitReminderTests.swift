import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct WaitReminderTests {
    @Test func onlySameEpisodeAndOnce() {
        let now = Date()
        var session = SessionInfo(id: "demo", source: .claudeCode, phase: .awaitingUser(reason: .input, message: ""), at: now)
        var reminders = WaitReminder()
        reminders.postpone(session, now: now)
        #expect(reminders.due(sessions: [session], now: now.addingTimeInterval(599)).isEmpty)
        #expect(reminders.due(sessions: [session], now: now.addingTimeInterval(600)).count == 1)
        #expect(reminders.due(sessions: [session], now: now.addingTimeInterval(601)).isEmpty)
        reminders.postpone(session, now: now)
        session.set(.thinking, at: now.addingTimeInterval(5))
        session.set(.awaitingUser(reason: .input, message: "new"), at: now.addingTimeInterval(6))
        #expect(reminders.due(sessions: [session], now: now.addingTimeInterval(700)).isEmpty)
        #expect(reminders.deadlines.isEmpty)
    }
    @Test func quietDefersButStillPrunesFinishedEpisodes() {
        let now = Date()
        let session = SessionInfo(id: "demo", source: .claudeCode, phase: .awaitingUser(reason: .input, message: ""), at: now)
        var reminders = WaitReminder(); reminders.postpone(session, now: now)
        #expect(reminders.due(sessions: [session], now: now.addingTimeInterval(700), deliver: false).isEmpty)
        #expect(reminders.deadlines.count == 1)
        #expect(reminders.due(sessions: [session], now: now.addingTimeInterval(701)).count == 1)
        reminders.postpone(session, now: now)
        #expect(reminders.due(sessions: [], now: now.addingTimeInterval(700), deliver: false).isEmpty)
        #expect(reminders.deadlines.isEmpty)
    }
    @Test func completedSessionCancelsReminder() {
        let now = Date()
        let session = SessionInfo(id: "demo", source: .claudeCode, phase: .awaitingUser(reason: .input, message: ""), at: now)
        var reminders = WaitReminder(); reminders.postpone(session, now: now)
        #expect(reminders.due(sessions: [], now: now.addingTimeInterval(700)).isEmpty)
        #expect(reminders.deadlines.isEmpty)
    }
}
