#!/usr/bin/env bash
# Bump MARKETING_VERSION in project.yml and increment CURRENT_PROJECT_VERSION.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PROJECT_YML="$ROOT/project.yml"

usage() {
  echo "Usage: $0 patch|minor|major"
  exit 1
}

[[ $# -eq 1 ]] || usage
PART="$1"
case "$PART" in
  patch|minor|major) ;;
  *) usage ;;
esac

CURRENT="$(awk -F'"' '/MARKETING_VERSION:/{print $2; exit}' "$PROJECT_YML")"
BUILD="$(awk -F'"' '/CURRENT_PROJECT_VERSION:/{print $2; exit}' "$PROJECT_YML")"

[[ -n "$CURRENT" ]] || { echo "MARKETING_VERSION not found in project.yml" >&2; exit 1; }

IFS='.' read -r major minor patch _ <<< "${CURRENT}.."
major="${major:-0}"
minor="${minor:-0}"
patch="${patch:-0}"
# Only semver triple (handles accidental extra segments in project.yml).
major="${major//[^0-9]/}"
minor="${minor//[^0-9]/}"
patch="${patch//[^0-9]/}"
major=$((10#${major:-0}))
minor=$((10#${minor:-0}))
patch=$((10#${patch:-0}))

case "$PART" in
  patch) patch=$((patch + 1)) ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  major) major=$((major + 1)); minor=0; patch=0 ;;
esac

NEW_VERSION="${major}.${minor}.${patch}"
NEW_BUILD=$(( ${BUILD:-0} + 1 ))

if [[ "$(uname)" == Darwin ]]; then
  sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"${NEW_VERSION}\"/" "$PROJECT_YML"
  sed -i '' "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"${NEW_BUILD}\"/" "$PROJECT_YML"
else
  sed -i "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"${NEW_VERSION}\"/" "$PROJECT_YML"
  sed -i "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"${NEW_BUILD}\"/" "$PROJECT_YML"
fi

xcodegen generate
echo "MARKETING_VERSION=${NEW_VERSION} CURRENT_PROJECT_VERSION=${NEW_BUILD}"