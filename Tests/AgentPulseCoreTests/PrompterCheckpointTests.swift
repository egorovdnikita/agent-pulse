import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct PrompterCheckpointTests {
    let now = Date(timeIntervalSince1970: 100000)
    @Test func onlySameUnfinishedScriptCanResume() {
        let checkpoint = PrompterCheckpoint(text: "Один два три четыре", position: 2, now: now)
        #expect(checkpoint.fraction(for: " Один два три четыре\n") == 0.5)
        #expect(checkpoint.fraction(for: "Другой текст") == nil)
        #expect(PrompterCheckpoint(text: "Один два", position: 2).fraction(for: "Один два") == nil)
        #expect(PrompterCheckpoint(text: "Один два", position: .nan).fraction(for: "Один два") == nil)
    }
    @Test func savesPrivatelyExpiresAndErases() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "position.json")
        try PrompterCheckpoint(text: "Один два три", position: 1, now: now).save(to: url)
        #expect(PrompterCheckpoint.load(from: url, now: now)?.position == 1)
        let json = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(!json.contains("Один два три"))
        #expect(PrompterCheckpoint.load(from: url, now: now.addingTimeInterval(31 * 24 * 3600)) == nil)
        PrompterCheckpoint.erase(at: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
