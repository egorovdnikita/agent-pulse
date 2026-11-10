import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct PrompterTextFileTests {
    @Test func utf8AndBOM() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("\u{FEFF}Пример\n\nТекст".utf8).write(to: url)
        #expect(try PrompterTextFile.read(url) == "Пример\n\nТекст")
        #expect(!PrompterTextFile.supports(URL(string: "https://example.com/test.txt")!))
    }
    @Test func refusesOversize() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 65, count: PrompterTextFile.maximumBytes + 1).write(to: url)
        #expect(throws: (any Error).self) { try PrompterTextFile.read(url) }
    }
}
