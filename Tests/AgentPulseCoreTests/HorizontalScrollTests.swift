import Testing
@testable import AgentPulseCore

@Suite struct HorizontalScrollTests {
    @Test func languageRowOwnsWholeGestureInBothDirections() {
        for dx in [-40.0, 40.0] {
            var axis = ScrollAxis()
            axis.begin(overHorizontalList: true)
            #expect(axis.owner == .list)
            #expect(axis.feed(dx: dx, dy: 0) == .list)
            // Уход курсора из строки и изменение направления не отдают текущий жест вкладкам.
            #expect(axis.feed(dx: -dx, dy: 30) == .list)
        }
    }

    @Test func nextGestureOutsideRowCanChangePages() {
        var axis = ScrollAxis()
        axis.begin(overHorizontalList: true)
        #expect(axis.feed(dx: 40, dy: 0) == .list)
        axis.begin()
        #expect(axis.owner == nil)
        #expect(axis.feed(dx: 40, dy: 0) == .pages)
        axis.begin()
        #expect(axis.feed(dx: 0, dy: 40) == .list)
    }
}
