import Testing
@testable import AgentPulseCore

@Suite struct DisplayPositionMemoryTests {
    @Test func migratesOnceAndKeepsDisplaysIndependent() {
        var positions = ["1": [12.0, -8.0], "display-second": [20.0, 30.0]]
        let offset = DisplayPositionMemory.offset(in: &positions, stableID: "display-first", legacyID: "1")
        #expect(offset == [12, -8])
        #expect(positions["1"] == nil)
        #expect(positions["display-second"] == [20, 30])
        // При переподключении числовой ID изменился, постоянный остался.
        let reconnected = DisplayPositionMemory.offset(in: &positions, stableID: "display-first", legacyID: "999")
        #expect(reconnected == [12, -8])
    }
    @Test func rejectsInvalidOffsetsAndDoesNotRemoveFallbackKey() {
        var positions = ["bad": [Double.nan, 0], "same": [2.0, 3.0]]
        let bad = DisplayPositionMemory.offset(in: &positions, stableID: "new", legacyID: "bad")
        #expect(bad == nil)
        let same = DisplayPositionMemory.offset(in: &positions, stableID: "same", legacyID: "same")
        #expect(same == [2, 3])
        #expect(positions["same"] == [2, 3])
    }
}
