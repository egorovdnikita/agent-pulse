#!/usr/bin/env bash
# Собирает MediaRemoteAdapter.framework без cmake и Xcode. Фреймворк не линкуется с приложением:
# его загружает системный /usr/bin/perl, у которого есть доступ к MediaRemote.
# Использование: scripts/build-media-adapter.sh папка_назначения
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$1/MediaRemoteAdapter.framework"
V=Vendor/mediaremote-adapter
rm -rf "$OUT"
mkdir -p "$OUT/Versions/A/Resources"
clang -dynamiclib -fobjc-arc -fvisibility=default -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -w \
  -I"$V/include" -I"$V/src" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  "$V"/src/adapter/*.m "$V"/src/private/MediaRemote.m "$V"/src/utility/*.m \
  -o "$OUT/Versions/A/MediaRemoteAdapter"
cat > "$OUT/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
<key>CFBundleIdentifier</key><string>io.github.egorovdnikita.agentpulse.mediaremote</string>
<key>CFBundlePackageType</key><string>FMWK</string>
</dict></plist>
PLIST
ln -sfn A "$OUT/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$OUT/MediaRemoteAdapter"
ln -sfn Versions/Current/Resources "$OUT/Resources"
