#!/usr/bin/env bash
# Cursor afterFileEdit: debounced Release build and local install when app sources change.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"
TRIGGER_FILE="$HOOK_DIR/.rebuild-trigger"
WORKER="$HOOK_DIR/rebuild-photo-viewer-worker.sh"
LOG_FILE="$HOOK_DIR/rebuild.log"

INPUT="$(cat || true)"

EDITED_PATHS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && EDITED_PATHS+=("$line")
done < <(INPUT_JSON="$INPUT" ROOT_DIR="$ROOT" python3 <<'PY'
import json, os

raw = os.environ.get("INPUT_JSON", "")
root = os.environ.get("ROOT_DIR", "")

paths = []

def add(p):
    if isinstance(p, str) and p:
        paths.append(p)

if raw.strip():
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        data = {}
    if isinstance(data, dict):
        for key in ("file_path", "filePath", "path", "filepath", "file"):
            add(data.get(key))
        for key in ("file_paths", "paths", "files"):
            val = data.get(key)
            if isinstance(val, list):
                for item in val:
                    add(item)
        for nested_key in ("edit", "tool_input", "input"):
            nested = data.get(nested_key)
            if isinstance(nested, dict):
                for key in ("file_path", "filePath", "path"):
                    add(nested.get(key))

for p in paths:
    if root and not os.path.isabs(p):
        p = os.path.join(root, p)
    print(p)
PY
)

should_rebuild=0
for path in "${EDITED_PATHS[@]+"${EDITED_PATHS[@]}"}"; do
  [[ -z "$path" ]] && continue
  case "$path" in
    "$ROOT"/PhotoViewer/*|"$ROOT"/PhotoViewerTests/*|"$ROOT"/project.yml|"$ROOT"/PhotoViewer.xcodeproj/*)
      should_rebuild=1
      break
      ;;
  esac
done

if [[ "$should_rebuild" -ne 1 ]]; then
  exit 0
fi

date +%s >"$TRIGGER_FILE"
chmod +x "$WORKER" 2>/dev/null || true
# Double-fork into a new session so the build survives the hook process exiting.
python3 - "$WORKER" "$LOG_FILE" <<'PY'
import os, sys
worker, log = sys.argv[1], sys.argv[2]
if os.fork() > 0:
    os._exit(0)
os.setsid()
if os.fork() > 0:
    os._exit(0)
fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
os.dup2(fd, 1)
os.dup2(fd, 2)
os.close(fd)
devnull = os.open("/dev/null", os.O_RDONLY)
os.dup2(devnull, 0)
os.close(devnull)
os.execv(worker, [worker])
PY

exit 0
