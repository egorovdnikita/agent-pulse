#!/usr/bin/env bash
# Проигрывает типичную задачу Claude Code через pulse-hook — посмотреть маскота без настоящего агента.
# Приложение должно быть запущено. Использование: scripts/demo-events.sh [путь к pulse-hook]
set -euo pipefail
cd "$(dirname "$0")/.."

HOOK="${1:-build/Agent Pulse.app/Contents/MacOS/pulse-hook}"
[[ -x "$HOOK" ]] || HOOK=.build/debug/pulse-hook
[[ -x "$HOOK" ]] || { echo "pulse-hook не найден: соберите scripts/bundle.sh" >&2; exit 1; }

SESSION="demo-$$"
CWD="$PWD"

send() {
    local name="$1" extra="${2:-}"
    [[ -n "$extra" ]] && extra=", $extra"
    printf '{"session_id": "%s", "cwd": "%s", "hook_event_name": "%s"%s}' "$SESSION" "$CWD" "$name" "$extra" | "$HOOK"
    echo "→ $name"
}

tool() {
    send PreToolUse "\"tool_name\": \"$1\", \"tool_input\": $2"
    sleep "$3"
    send PostToolUse "\"tool_name\": \"$1\", \"tool_response\": {}"
    sleep 0.6
}

send UserPromptSubmit '"prompt": "demo"'
sleep 2.5
tool Read '{"file_path": "Package.swift"}' 1.2
tool Grep '{"pattern": "Phase"}' 1
tool Read '{"file_path": "Sources/AgentPulseCore/Core/Phase.swift"}' 2.5
tool Edit '{"file_path": "Sources/AgentPulseCore/Core/Phase.swift"}' 4
tool mcp__figma__use_figma '{}' 4
send PreToolUse '"tool_name": "Bash", "tool_input": {"command": "swift test"}'
sleep 0.5
send Notification '"message": "Claude needs your permission to use Bash", "notification_type": "permission_prompt"'
sleep 7
send PostToolUse '"tool_name": "Bash", "tool_response": {}'
sleep 1.5
send SubagentStop
sleep 1
tool WebSearch '{"query": "NSPanel fullScreenAuxiliary"}' 4
send Stop
sleep 8
send SessionEnd '"reason": "exit"'
