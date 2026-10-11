#!/usr/bin/env bash
# Запуск тестов: работает и с Xcode, и с одними Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
swift test "${SWIFT_FLAGS[@]}" ${TEST_FLAGS[@]+"${TEST_FLAGS[@]}"} "$@"
