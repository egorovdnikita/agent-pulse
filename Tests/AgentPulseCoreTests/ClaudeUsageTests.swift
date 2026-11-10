import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct ClaudeUsageTests {
    func response(_ windows: [String: Any], available: Bool = true, request: String = "pulse-usage") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": "control_response", "response": ["subtype": "success", "request_id": request, "response": ["rate_limits_available": available, "rate_limits": windows]]])
    }
    @Test func parsesNativeCLIWithoutSessionCost() throws {
        let now = Date()
        let data = try response(["five_hour": ["utilization": 31, "resets_at": "2026-11-11T01:50:00.561010+00:00"], "seven_day": ["utilization": 27, "resets_at": "2026-11-16T02:00:00Z"]])
        let result = try #require(ClaudeUsage.parse(data, now: now))
        #expect(result.service == .claude)
        #expect(result.at == now)
        #expect(result.origin == .claudeUsage)
        #expect(result.windows.map(\.usedPercent) == [31, 27])
        #expect(result.windows.allSatisfy { $0.resetsAt != nil })
    }
    @Test func missingOrUnsupportedUsageNeverMarksCacheFresh() throws {
        #expect(ClaudeUsage.parse(try response([:])) == nil)
        #expect(ClaudeUsage.parse(try response(["five_hour": ["utilization": 10]], available: false)) == nil)
        #expect(ClaudeUsage.parse(try response(["five_hour": ["utilization": 10]], request: "pulse-init")) == nil)
        #expect(ClaudeUsage.parse(try response(["five_hour": ["utilization": true]])) == nil)
        #expect(ClaudeUsage.parse(Data("{}".utf8)) == nil)
    }
    @Test func refreshEveryMinuteWhenOpenAndFiveMinutesInBackground() {
        let now = Date(), last = Date().addingTimeInterval(-61)
        #expect(ClaudeUsage.shouldRefresh(lastAttempt: last, now: now, frequent: true, inFlight: false))
        #expect(!ClaudeUsage.shouldRefresh(lastAttempt: last, now: now, frequent: false, inFlight: false))
        #expect(!ClaudeUsage.shouldRefresh(lastAttempt: .distantPast, now: now, frequent: true, inFlight: true))
        #expect(!ClaudeUsage.shouldRefresh(lastAttempt: now, now: now, frequent: true, inFlight: false))
        #expect(ClaudeUsage.shouldRefresh(lastAttempt: now.addingTimeInterval(-300), now: now, frequent: false, inFlight: false))
    }
    @Test func onlyControlRequestsAndNoPromptsOrTools() throws {
        let commands = [ClaudeUsage.initialize, ClaudeUsage.readUsage]
        for command in commands {
            let json = try #require(JSONSerialization.jsonObject(with: Data(command.utf8)) as? [String: Any])
            #expect(json["type"] as? String == "control_request")
            #expect(json["message"] == nil)
        }
        #expect(ClaudeUsage.arguments.contains("--no-session-persistence"))
        #expect(ClaudeUsage.arguments.contains("--disable-slash-commands"))
        #expect(ClaudeUsage.arguments.contains("--strict-mcp-config"))
        #expect(ClaudeUsage.arguments.contains(#"{"disableAllHooks":true}"#))
    }
}
