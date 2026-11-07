#!/usr/bin/env bash
# Скачивает рантайм распознавания (sherpa-onnx и ONNX Runtime, Apache 2.0 и MIT) в Vendor/sherpa-onnx.
# В репозиторий не кладётся: 32 MB бинарей. Контрольная сумма закреплена, другой файл не встанет.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=2.0.1
SHA256=ac5594ad237db56ec4a6c4b3fc48700441b33a07bb71c235f35530a52a93f2e3
NAME="sherpa-onnx-v$VERSION-osx-arm64-shared-no-tts-lib"
TARGET=Vendor/sherpa-onnx

[[ -f "$TARGET/.version" && "$(cat "$TARGET/.version")" == "$VERSION" ]] && exit 0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
curl -fsSL -o "$WORK/runtime.tar.bz2" "https://github.com/k2-fsa/sherpa-onnx/releases/download/v$VERSION/$NAME.tar.bz2"
echo "$SHA256  $WORK/runtime.tar.bz2" | shasum -a 256 -c - >/dev/null
tar -xjf "$WORK/runtime.tar.bz2" -C "$WORK" "$NAME/lib/libsherpa-onnx-c-api.dylib" "$NAME/lib/libonnxruntime.dylib"
mkdir -p "$TARGET"
cp "$WORK/$NAME/lib/"*.dylib "$TARGET/"
chmod 755 "$TARGET/"*.dylib
echo "$VERSION" > "$TARGET/.version"
