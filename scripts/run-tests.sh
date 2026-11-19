#!/usr/bin/env bash
# Run Photo Viewer unit tests locally (same command as CI should use).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="${DERIVED_DATA_PATH:-$ROOT/build/xcode}"

if [[ ! -d "$ROOT/PhotoViewer.xcodeproj" ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
  else
    echo "PhotoViewer.xcodeproj missing and xcodegen not found." >&2
    exit 1
  fi
fi

xcodebuild \
  -scheme PhotoViewer \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  test \
  -only-testing:PhotoViewerTests \
  "$@"