#!/usr/bin/env bash
# Debounced build + restart; invoked in background from rebuild-photo-viewer.sh
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"
TRIGGER_FILE="$HOOK_DIR/.rebuild-trigger"
APP_PATH="$ROOT/build/xcode/Build/Products/Debug/Photo Viewer.app"
SCHEME="PhotoViewer"
DERIVED="$ROOT/build/xcode"

debounce_seconds=2

stamp_at_start="$(cat "$TRIGGER_FILE" 2>/dev/null || echo 0)"
sleep "$debounce_seconds"
stamp_after_sleep="$(cat "$TRIGGER_FILE" 2>/dev/null || echo 0)"
if [[ "$stamp_at_start" != "$stamp_after_sleep" ]]; then
  echo "[$(date -Iseconds)] skip build (newer edits)"
  exit 0
fi

cd "$ROOT"

if [[ -f project.yml ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    echo "[$(date -Iseconds)] xcodegen generate"
    xcodegen generate
  else
    echo "[$(date -Iseconds)] warning: xcodegen not on PATH; skipping generate"
  fi
fi

echo "[$(date -Iseconds)] xcodebuild Debug"
if ! xcodebuild -scheme "$SCHEME" -configuration Debug -derivedDataPath "$DERIVED" build; then
  echo "[$(date -Iseconds)] build FAILED"
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "[$(date -Iseconds)] app bundle missing at $APP_PATH"
  exit 1
fi

echo "[$(date -Iseconds)] restart Photo Viewer"
pkill -x "Photo Viewer" 2>/dev/null || true
sleep 0.3
open "$APP_PATH"

echo "[$(date -Iseconds)] done"