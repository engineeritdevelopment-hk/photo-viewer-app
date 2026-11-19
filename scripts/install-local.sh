#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="build/xcode"
APP_SRC="$DERIVED/Build/Products/Release/Photo Viewer.app"
LOCAL="$ROOT/build/Photo Viewer.app"
DEST="/Applications/Photo Viewer.app"

if [[ ! -d "$APP_SRC" ]]; then
  xcodegen generate
  xcodebuild -scheme PhotoViewer -configuration Release -derivedDataPath "$DERIVED" build
fi

rm -rf "$LOCAL"
ditto "$APP_SRC" "$LOCAL"

if [[ -w /Applications ]]; then
  rm -rf "$DEST"
  ditto "$APP_SRC" "$DEST"
  echo "Installed: $DEST"
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$LOCAL/Contents/Info.plist")
echo "Local copy: $LOCAL ($VERSION)"
open "$LOCAL"