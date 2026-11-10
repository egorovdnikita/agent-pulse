import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct TextFragmentTests {
    @Test func unicodeAndGuard() throws {
        let source = "🙂 Hello!"
        let range = (source as NSString).range(of: "Hello")
        let fragment = try #require(TextFragment(source: source, range: range))
        #expect(fragment.text == "Hello")
        #expect(fragment.replacing(with: "Привет", in: source) == "🙂 Привет!")
        #expect(fragment.replacing(with: "Привет", in: source + "x") == nil)
    }
    @Test func invalidRanges() {
        #expect(TextFragment(source: "🙂", range: NSRange(location: 0, length: 1)) == nil)
        #expect(TextFragment(source: "abc", range: NSRange(location: NSNotFound, length: 2)) == nil)
        #expect(TextFragment(source: "   ", range: NSRange(location: 0, length: 3)) == nil)
    }
}
