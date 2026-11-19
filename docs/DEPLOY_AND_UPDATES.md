# Deploy and in-app updates — SOP

Standard procedure for agents and maintainers publishing **Photo Viewer** so the shipped app can **detect**, **download**, and **install** updates from GitHub.

## Prerequisites

- macOS with **Xcode 26+** (see `README.md`)
- **`xcodegen`** on PATH
- **`gh`** authenticated as **`engineeritdevelopment-hk`**
- Repository **`engineeritdevelopment-hk/photo-viewer-app`** is **public** (required for unauthenticated release API)

Verify:

```bash
gh auth status
curl -s -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/engineeritdevelopment-hk/photo-viewer-app/releases/latest" \
  | head -c 200
```

## Version source of truth

Edit **`project.yml`** (PhotoViewer target):

```yaml
MARKETING_VERSION: "1.0.1"      # CFBundleShortVersionString — user-visible
CURRENT_PROJECT_VERSION: "2"    # Build number — bump each release
```

Then:

```bash
xcodegen generate
```

The running app compares **marketing version** to the latest release **tag** (e.g. `v1.0.1` → `1.0.1`). Tags may use a leading `v`.

## Release checklist

Complete **in order**. Do not skip verification.

### 1. Prepare code

- [ ] Tests pass: `xcodebuild -scheme PhotoViewer -configuration Debug -derivedDataPath build/xcode test`
- [ ] `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` bumped in `project.yml`
- [ ] `xcodegen generate`
- [ ] Changes committed and pushed to `main` (when user requested a release commit)

### 2. Build Release app

```bash
cd /path/to/photo-viewer-app
xcodegen generate
xcodebuild -scheme PhotoViewer -configuration Release -derivedDataPath build/xcode build
```

Artifact:

`build/xcode/Build/Products/Release/Photo Viewer.app`

Confirm version:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "build/xcode/Build/Products/Release/Photo Viewer.app/Contents/Info.plist"
```

### 3. Create update zip (required)

The app picks the best **`.zip`** asset on the GitHub release. The archive must contain **`Photo Viewer.app`** (any path inside the zip).

```bash
APP="build/xcode/Build/Products/Release/Photo Viewer.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ZIP="build/Photo-Viewer-${VERSION}-mac.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
```

`build/` is gitignored — upload this file to GitHub only.

### 4. Tag and push

```bash
git tag -a "v${VERSION}" -m "Photo Viewer ${VERSION}"
git push origin "v${VERSION}"
```

Use a **new** tag per release. Do not move an existing tag without explicit user approval.

### 5. Create GitHub release

```bash
gh release create "v${VERSION}" \
  --repo engineeritdevelopment-hk/photo-viewer-app \
  --title "Photo Viewer ${VERSION}" \
  --notes-file - <<EOF
Short release notes for users.
EOF
  "build/Photo-Viewer-${VERSION}-mac.zip"
```

- Publish as **latest** (not draft, not prerelease).
- Attach **exactly one** primary zip (name should include `Photo` / `Viewer` if multiple zips exist).

### 6. Verify API (done criterion)

```bash
curl -s -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/engineeritdevelopment-hk/photo-viewer-app/releases/latest" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('tag',d['tag_name']);print('assets',[a['name'] for a in d['assets']])"
```

Expected: tag matches `v${VERSION}`, assets include `Photo-Viewer-*-mac.zip`.

### 7. Smoke-test updates (recommended)

1. Install an **older** build in `/Applications/Photo Viewer.app`.
2. Launch → update sheet **or** **Check for Updates…** (⇧⌘U) / **info** popover.
3. **Update** → download → quit → relaunch with new version.

Updates replace the **bundle path** of the running app; testing from Xcode output paths is less representative than `/Applications`.

## Automated script

```bash
./scripts/release.sh              # uses MARKETING_VERSION from project.yml
./scripts/release.sh --notes path # custom release notes file
./scripts/release.sh --skip-tests # not recommended
```

## Local install (no GitHub)

```bash
./scripts/install-local.sh
```

Copies Release build to `build/Photo Viewer.app` and `/Applications/Photo Viewer.app`.

## How in-app updates work (reference)

| Component | Role |
|-----------|------|
| `ReleaseUpdateChecker` | `GET .../releases/latest` on public repo |
| `AppUpdateModel` | Check on launch + every 24h while active; manual check |
| `AppUpdateDownloader` | Background zip download |
| `AppUpdateInstaller` + `PhotoViewerInstallHelper` | Quit, replace bundle, reopen |

Config: `PhotoViewerGitHubRepository` in `Info.plist` (from `project.yml`).

## Signing and Gatekeeper

CI/ad-hoc builds use **`codesign -`**. Users may see **unidentified developer** until you ship **Developer ID** signed and **notarized** builds in the zip. Document that in release notes when applicable.

## Failure modes

| Symptom | Likely cause |
|---------|----------------|
| Manual check: “Could not read release information” | Private repo, wrong `PhotoViewerGitHubRepository`, or no `releases/latest` |
| Update sheet but install fails | Release has **no `.zip`** or zip lacks `Photo Viewer.app` |
| No prompt when you expect one | Installed **marketing version** ≥ release tag |
| API 403 rate limit | Rare; retry or authenticate (not needed for public repo) |

## Changing the release repo

1. Create/publish on the new **public** GitHub repo.
2. Update `INFOPLIST_KEY_PhotoViewerGitHubRepository` in `project.yml`.
3. `xcodegen generate` and ship a release from the new repo.
4. Update `AGENTS.md` and this document.