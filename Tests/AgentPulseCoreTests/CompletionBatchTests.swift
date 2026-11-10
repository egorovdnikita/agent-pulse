import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct CompletionBatchTests {
    let now = Date(timeIntervalSince1970: 1000)
    @Test func coalescesDuplicateChannelsAndPreservesArrivalOrder() {
        var batch = CompletionBatch()
        for id in ["first", "second", "first"] { batch.observe(AgentEvent(source: .codex, sessionId: id, kind: .stopped, ts: now)) }
        #expect(batch.takeReady(now: now.addingTimeInterval(1)) == nil)
        #expect(batch.takeReady(now: now.addingTimeInterval(2))?.map(\.id) == ["first", "second"])
        #expect(batch.takeReady(now: now.addingTimeInterval(3)) == nil)
    }
    @Test func waitsBehindImportantEventsAndCancelsObsoleteCompletion() {
        var batch = CompletionBatch()
        batch.observe(AgentEvent(source: .codex, sessionId: "first", kind: .stopped, ts: now))
        #expect(batch.takeReady(now: now.addingTimeInterval(3), allowed: false) == nil)
        batch.observe(AgentEvent(source: .codex, sessionId: "first", kind: .awaitingUser, ts: now))
        #expect(batch.takeReady(now: now.addingTimeInterval(4)) == nil)
        batch.observe(AgentEvent(source: .codex, sessionId: "failed", kind: .stopped, isError: true, ts: now))
        #expect(batch.takeReady(now: now.addingTimeInterval(5)) == nil)
    }
}
