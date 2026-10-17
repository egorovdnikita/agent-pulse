#!/usr/bin/env bash
# Собирает build/AgentPulse.app без Xcode: бинари SwiftPM + Info.plist + ad-hoc подпись.
# Использование: scripts/bundle.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

CONFIG="${1:-release}"
swift build "${SWIFT_FLAGS[@]}" -c "$CONFIG"
BIN="$(swift build "${SWIFT_FLAGS[@]}" -c "$CONFIG" --show-bin-path)"

APP=build/AgentPulse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/AgentPulse" "$BIN/pulse-hook" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Extensions/Chrome "$APP/Contents/Resources/ChromeExtension"
cp -R FigmaCompanion "$APP/Contents/Resources/FigmaCompanion"

# Ad-hoc подпись для локального запуска. Для дистрибуции — Developer ID + нотаризация.
# macOS привязывает «Универсальный доступ» к подписи: с ad-hoc разрешение слетает после каждой сборки.
# Постоянный сертификат: AGENT_PULSE_SIGN_IDENTITY="Имя сертификата" scripts/bundle.sh
# По умолчанию — локальный сертификат «Agent Pulse Local Signing», если он есть в связке ключей.
LOCAL_IDENTITY="Agent Pulse Local Signing"
if [[ -z "${AGENT_PULSE_SIGN_IDENTITY:-}" ]] && security find-identity -p codesigning 2>/dev/null | grep -q "$LOCAL_IDENTITY"; then
    AGENT_PULSE_SIGN_IDENTITY="$LOCAL_IDENTITY"
fi
IDENTITY="${AGENT_PULSE_SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP/Contents/MacOS/pulse-hook"
codesign --force --sign "$IDENTITY" "$APP"

echo "$APP"
