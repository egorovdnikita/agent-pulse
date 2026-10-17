#!/usr/bin/env bash
# Собирает и ставит Agent Pulse в /Applications (или ~/Applications, если нет прав), перезапускает.
# --login — заодно включить «Запускать при входе».
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/bundle.sh release >/dev/null

TARGET=/Applications
[[ -w "$TARGET" ]] || { TARGET="$HOME/Applications"; mkdir -p "$TARGET"; }
APP="$TARGET/Agent Pulse.app"
# Старое имя бандла без пробела — убрать, чтобы не было двух копий.
rm -rf "$TARGET/AgentPulse.app"

pkill -x AgentPulse 2>/dev/null || true
sleep 0.5
rm -rf "$APP"
ditto "build/Agent Pulse.app" "$APP"
# Сборку из build/ убираем: иначе Spotlight и Launchpad показывают её второй копией приложения.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "build/Agent Pulse.app" 2>/dev/null || true
rm -rf "build/Agent Pulse.app" build/AgentPulse.app

ARGS=()
[[ "${1:-}" == "--login" ]] && ARGS=(--args --register-login-item)
open "$APP" ${ARGS[@]+"${ARGS[@]}"}
echo "$APP"
