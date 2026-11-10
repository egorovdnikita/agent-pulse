import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct TranslatePreferencesTests {
    @Test func remembersPairAndAutomaticSourcePrivately() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "languages.json")
        let chosen = TranslatePreferences(source: nil, target: "fr-CA")
        try chosen.save(to: url)
        #expect(TranslatePreferences.load(from: url) == chosen)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try Data(#"{"source":"../file","target":"ru"}"#.utf8).write(to: url)
        #expect(TranslatePreferences.load(from: url) == TranslatePreferences())
    }
}
