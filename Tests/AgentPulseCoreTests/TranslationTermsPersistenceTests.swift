import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct TranslationTermsPersistenceTests {
    @Test func onlyTermsPersistWithOwnerPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("terms.json")
        var terms = TranslationTerms(); terms.add("Box UI"); terms.add("C++")
        try terms.save(to: url)
        #expect(TranslationTerms.load(from: url) == terms)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(Set(json.keys) == ["terms"])
        terms.remove("Box UI"); try terms.save(to: url)
        #expect(TranslationTerms.load(from: url).terms == ["C++"])
    }
    @Test func corruptAndOversizeListsAreBounded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("invalid".utf8).write(to: url)
        #expect(TranslationTerms.load(from: url).terms.isEmpty)
        try JSONSerialization.data(withJSONObject: ["terms": (0..<250).map { "Term \($0)" }]).write(to: url)
        #expect(TranslationTerms.load(from: url).terms.count == TranslationTerms.capacity)
    }
}
