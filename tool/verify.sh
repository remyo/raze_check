#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
DART_BIN="${DART_BIN:-dart}"
"$DART_BIN" format --output=none --set-exit-if-changed lib packages test integration_test tool docs/testing
"$FLUTTER_BIN" analyze --no-pub
(cd packages/raze_check_core && "$DART_BIN" test)
(cd packages/raze_check_local && "$FLUTTER_BIN" test --no-pub --concurrency=2)
(cd packages/raze_check_feature && "$FLUTTER_BIN" test --no-pub --concurrency=2)
"$FLUTTER_BIN" test --no-pub test --concurrency=2
