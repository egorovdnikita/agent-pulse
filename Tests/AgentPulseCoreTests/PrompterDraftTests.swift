import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct PrompterDraftTests {
    @Test func draftAndClearSurviveRestartWithPrivatePermissions() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "draft.json")
        let draft = PrompterDraft(text: "  Тестовый доклад\n\nВторой абзац")
        try draft.save(to: url)
        #expect(PrompterDraft.load(from: url) == draft)
        #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try PrompterDraft().save(to: url)
        #expect(PrompterDraft.load(from: url).text.isEmpty)
        try Data("bad json".utf8).write(to: url)
        #expect(PrompterDraft.load(from: url).text.isEmpty)
    }
}
