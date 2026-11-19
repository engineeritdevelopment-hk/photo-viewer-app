#!/usr/bin/env bash
# Publish a GitHub release with update zip for Photo Viewer.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REPO="engineeritdevelopment-hk/photo-viewer-app"
DERIVED="build/xcode"
SKIP_TESTS=0
NOTES_FILE=""

usage() {
  echo "Usage: $0 [--skip-tests] [--notes FILE]"
  echo "Reads MARKETING_VERSION from project.yml; builds Release, zips, tags, and gh release."
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tests) SKIP_TESTS=1; shift ;;
    --notes) NOTES_FILE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

VERSION="$(awk -F'"' '/MARKETING_VERSION:/{print $2; exit}' project.yml)"
if [[ -z "$VERSION" ]]; then
  echo "Could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi

TAG="v${VERSION}"

if [[ "$SKIP_TESTS" -eq 0 ]]; then
  xcodegen generate
  xcodebuild -scheme PhotoViewer -configuration Debug -derivedDataPath "$DERIVED" test
fi

xcodegen generate
xcodebuild -scheme PhotoViewer -configuration Release -derivedDataPath "$DERIVED" build

APP="$DERIVED/Build/Products/Release/Photo Viewer.app"
if [[ ! -d "$APP" ]]; then
  echo "Missing Release app: $APP" >&2
  exit 1
fi

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ "$BUILT_VERSION" != "$VERSION" ]]; then
  echo "Built version ($BUILT_VERSION) != project.yml MARKETING_VERSION ($VERSION). Run xcodegen generate." >&2
  exit 1
fi

ZIP="build/Photo-Viewer-${VERSION}-mac.zip"
mkdir -p build
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists locally; not re-creating." >&2
else
  git tag -a "$TAG" -m "Photo Viewer ${VERSION}"
fi

git push origin "$TAG" || true

NOTES_ARGS=()
if [[ -n "$NOTES_FILE" && -f "$NOTES_FILE" ]]; then
  NOTES_ARGS=(--notes-file "$NOTES_FILE")
else
  NOTES_ARGS=(--notes "Photo Viewer ${VERSION}")
fi

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release $TAG exists; uploading zip asset..."
  gh release upload "$TAG" --repo "$REPO" --clobber "$ZIP"
else
  gh release create "$TAG" --repo "$REPO" --title "Photo Viewer ${VERSION}" \
    "${NOTES_ARGS[@]}" "$ZIP"
fi

echo "Release: https://github.com/${REPO}/releases/tag/${TAG}"
echo "Zip: $ZIP"