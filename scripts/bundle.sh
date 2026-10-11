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
cp -R Extensions/Chrome "$APP/Contents/Resources/ChromeExtension"
cp -R FigmaCompanion "$APP/Contents/Resources/FigmaCompanion"

# Ad-hoc подпись для локального запуска. Для дистрибуции — Developer ID + нотаризация.
codesign --force --sign - "$APP/Contents/MacOS/pulse-hook"
codesign --force --sign - "$APP"

echo "$APP"
