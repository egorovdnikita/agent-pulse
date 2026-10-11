import Foundation

/// Payload хуков в формате документации Claude Code.
/// TODO(валидация №5): заменить на записанные с реальных сессий.
enum Fixtures {
    static let sessionId = "abc123"

    static func hook(_ name: String, _ extra: String = "") -> Data {
        let tail = extra.isEmpty ? "" : ", \(extra)"
        return Data("""
            {"session_id": "\(sessionId)", "transcript_path": "/Users/me/.claude/projects/x/abc123.jsonl", \
            "cwd": "/Users/me/Projects/agent-pulse", "hook_event_name": "\(name)"\(tail)}
            """.utf8)
    }

    static let promptSubmitted = hook("UserPromptSubmit", #""prompt": "секретный текст промпта""#)

    static let preToolRead = hook("PreToolUse", #""tool_name": "Read", "tool_input": {"file_path": "/Users/me/Projects/agent-pulse/Package.swift"}"#)

    static let preToolBashTests = hook(
        "PreToolUse", #""tool_name": "Bash", "tool_input": {"command": "swift test --parallel", "description": "Run tests"}"#
    )

    static let preToolFigmaWrite = hook(
        "PreToolUse", #""tool_name": "mcp__8ece76e0-4474-4af1-aeee-e1b5e92835c3__use_figma", "tool_input": {"code": "figma.createFrame()"}"#
    )

    static let postToolOk = hook(
        "PostToolUse", #""tool_name": "Bash", "tool_input": {"command": "ls"}, "tool_response": {"stdout": "a\nb", "stderr": "", "interrupted": false}"#
    )

    static let postToolError = hook(
        "PostToolUse", #""tool_name": "Edit", "tool_input": {}, "tool_response": {"is_error": true, "error": "old_string not found"}"#
    )

    static let notificationPermission = hook(
        "Notification", #""message": "Claude needs your permission to use Bash", "notification_type": "permission_prompt""#
    )

    static let notificationIdle = hook(
        "Notification", #""message": "Claude is waiting for your input", "notification_type": "idle_prompt""#
    )

    static let notificationLegacyPermission = hook("Notification", #""message": "Claude needs your permission to use Write""#)

    static let notificationAuth = hook("Notification", #""message": "Signed in", "notification_type": "auth_success""#)

    static let subagentStop = hook("SubagentStop", #""stop_hook_active": false"#)
    static let stop = hook("Stop", #""stop_hook_active": false"#)
    static let sessionEnd = hook("SessionEnd", #""reason": "exit""#)

    static func enveloped(_ payload: Data, bundle: String) -> Data {
        Data("PULSE1 bundle=\(bundle)\n".utf8) + payload
    }
}
