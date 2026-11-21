#!/usr/bin/env bash
# Debounced Release build + install. Invoked in the background from rebuild-photo-viewer.sh.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"
TRIGGER_FILE="$HOOK_DIR/.rebuild-trigger"
LOCK_DIR="$HOOK_DIR/.rebuild.lock"
SCHEME="PhotoViewer"
DERIVED="$ROOT/build/xcode"
APP_PATH="$DERIVED/Build/Products/Release/Photo Viewer.app"

debounce_seconds=5

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] build already running"
  exit 0
fi
cleanup() { rmdir "$LOCK_DIR" 2>/dev/null || true; }
trap cleanup EXIT

while true; do
  stamp_at_start="$(cat "$TRIGGER_FILE" 2>/dev/null || echo 0)"
  sleep "$debounce_seconds"
  stamp_after_sleep="$(cat "$TRIGGER_FILE" 2>/dev/null || echo 0)"
  if [[ "$stamp_at_start" != "$stamp_after_sleep" ]]; then
    echo "[$(date '+%Y-%m-%dT%H:%M:%S')] waiting for edits to settle"
    continue
  fi

  cd "$ROOT"

  if [[ -f project.yml ]] && command -v xcodegen >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%dT%H:%M:%S')] xcodegen generate"
    xcodegen generate
  fi

  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] xcodebuild Release"
  if ! xcodebuild -scheme "$SCHEME" -configuration Release -derivedDataPath "$DERIVED" build; then
    echo "[$(date '+%Y-%m-%dT%H:%M:%S')] build FAILED"
    exit 1
  fi

  if [[ ! -d "$APP_PATH" ]]; then
    echo "[$(date '+%Y-%m-%dT%H:%M:%S')] app bundle missing at $APP_PATH"
    exit 1
  fi

  stamp_after_build="$(cat "$TRIGGER_FILE" 2>/dev/null || echo 0)"
  if [[ "$stamp_after_build" != "$stamp_at_start" ]]; then
    echo "[$(date '+%Y-%m-%dT%H:%M:%S')] edits arrived during build; rebuilding"
    continue
  fi

  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] install Photo Viewer"
  pkill -x "Photo Viewer" 2>/dev/null || true
  sleep 0.4
  ./scripts/install-local.sh
  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] done"
  break
done
