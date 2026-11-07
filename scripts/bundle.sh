#!/usr/bin/env bash
# Собирает «build/Agent Pulse.app» без Xcode: бинари SwiftPM + Info.plist + ad-hoc подпись.
# Использование: scripts/bundle.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

CONFIG="${1:-release}"
swift build "${SWIFT_FLAGS[@]}" -c "$CONFIG"
BIN="$(swift build "${SWIFT_FLAGS[@]}" -c "$CONFIG" --show-bin-path)"

APP="build/Agent Pulse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/AgentPulse" "$BIN/pulse-hook" "$BIN/pulse-statusline" "$BIN/pulse-asr" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Fonts/Geist.ttf Resources/OpenAIBlossom.svg "$APP/Contents/Resources/"
cp -R Extensions/Chrome "$APP/Contents/Resources/ChromeExtension"
cp -R FigmaCompanion "$APP/Contents/Resources/FigmaCompanion"
# Авторы и лицензии чужих материалов: Solar Icons (CC BY 4.0), Lottie (Apache 2.0).
cp -R Resources/Licenses "$APP/Contents/Resources/Licenses"
# Посредник для «Музыки»: фреймворк не линкуется, его загружает системный perl.
mkdir -p "$APP/Contents/Resources/MediaAdapter"
cp Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$APP/Contents/Resources/MediaAdapter/"
scripts/build-media-adapter.sh "$APP/Contents/Resources/MediaAdapter"
# Lottie — готовый фреймворк (lottie-spm): исходники lottie-ios без Xcode не собираются.
mkdir -p "$APP/Contents/Frameworks"
cp -R "$BIN/Lottie.framework" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/AgentPulse" 2>/dev/null || true
# Рантайм диктовки: загружает только помощник и только на время работы.
scripts/fetch-sherpa.sh
cp Vendor/sherpa-onnx/*.dylib "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@loader_path" "$APP/Contents/Frameworks/libsherpa-onnx-c-api.dylib" 2>/dev/null || true

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
codesign --force --sign "$IDENTITY" "$APP/Contents/MacOS/pulse-statusline"
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/Lottie.framework"
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/libonnxruntime.dylib"
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/libsherpa-onnx-c-api.dylib"
codesign --force --sign "$IDENTITY" --options runtime --entitlements Resources/PulseASR.entitlements "$APP/Contents/MacOS/pulse-asr"
codesign --force --sign "$IDENTITY" "$APP/Contents/Resources/MediaAdapter/MediaRemoteAdapter.framework"
# Hardened runtime с entitlements: иначе macOS молча откажет в Календарях, микрофоне и Automation.
codesign --force --sign "$IDENTITY" --options runtime --entitlements Resources/AgentPulse.entitlements "$APP"

echo "$APP"
