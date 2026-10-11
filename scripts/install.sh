#!/usr/bin/env bash
# Собирает и ставит Agent Pulse в /Applications (или ~/Applications, если нет прав), перезапускает.
# --login — заодно включить «Запускать при входе».
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/bundle.sh release >/dev/null

TARGET=/Applications
[[ -w "$TARGET" ]] || { TARGET="$HOME/Applications"; mkdir -p "$TARGET"; }
APP="$TARGET/AgentPulse.app"

pkill -x AgentPulse 2>/dev/null || true
sleep 0.5
rm -rf "$APP"
ditto build/AgentPulse.app "$APP"

ARGS=()
[[ "${1:-}" == "--login" ]] && ARGS=(--args --register-login-item)
open "$APP" ${ARGS[@]+"${ARGS[@]}"}
echo "$APP"
