---
name: photo-viewer-build-deploy
description: >-
  Build, bump versions, publish GitHub releases, and install Photo Viewer locally.
  Use when the user asks to build, deploy, release, publish, ship, install locally,
  bump version, tag, or manage MARKETING_VERSION for this macOS app.
---

# Photo Viewer — build and deploy

## Version source of truth

Edit **`project.yml`** → PhotoViewer target:

| Key | Meaning |
|-----|---------|
| `MARKETING_VERSION` | User-visible semver (`CFBundleShortVersionString`) |
| `CURRENT_PROJECT_VERSION` | Build number — **increment every release** |

Then run **`xcodegen generate`** before any `xcodebuild`.

### When to bump

| Change | Bump |
|--------|------|
| Bugfix / UI tweak / perf | **Patch** (1.0.1 → 1.0.2) |
| New feature | **Minor** (1.0.x → 1.1.0) |
| Breaking data/API | **Major** (1.x → 2.0.0) |

Use **`scripts/bump-version.sh patch|minor|major`** (runs `xcodegen`).

GitHub release tag must be **`v{MARKETING_VERSION}`** (e.g. `v1.0.2`). In-app update compares tag to marketing version.

## Release repo

- **Public GitHub:** `engineeritdevelopment-hk/photo-viewer-app`
- **`gh`** active account: **`engineeritdevelopment-hk`** (`gh auth switch --user engineeritdevelopment-hk`)
- Every release **must** attach **`Photo-Viewer-{version}-mac.zip`** containing **`Photo Viewer.app`**

Full SOP and failure modes: **[`docs/DEPLOY_AND_UPDATES.md`](../../../docs/DEPLOY_AND_UPDATES.md)**

## Standard deploy (preferred)

User asked to **deploy** / **publish** / **release**:

```
Task Progress:
- [ ] Bump version if not already bumped (`scripts/bump-version.sh`)
- [ ] Commit and push `main` when user wants git updated
- [ ] `./scripts/release.sh` (tests, Release build, zip, tag, `gh release`)
- [ ] Verify API returns new tag + zip (see DEPLOY doc §6)
- [ ] Optional: `./scripts/install-local.sh` for local smoke test
```

**`./scripts/release.sh`** flags: `--skip-tests` (avoid unless user insists), `--notes FILE` for release notes.

Do **not** commit `build/`. Do **not** re-release the same tag without user approval (use new version instead).

## Local build only

```bash
xcodegen generate
xcodebuild -scheme PhotoViewer -configuration Debug -derivedDataPath build/xcode build
# or Release:
xcodebuild -scheme PhotoViewer -configuration Release -derivedDataPath build/xcode build
```

Install to Applications: **`./scripts/install-local.sh`**

## Commit messages

Conventional commits; only commit when the user asks. Example:

```
fix: …

chore(release): 1.0.2
```

## Verification (done = shipped)

1. `gh release view vX.Y.Z --repo engineeritdevelopment-hk/photo-viewer-app` shows zip asset.
2. Plist in built app matches `MARKETING_VERSION`.
3. Tell user release URL and that **older** installs should see an in-app update prompt.

## Guardrails

- Never force-push `main` unless explicitly requested.
- Never change `origin` or create a second GitHub repo without user direction.
- Signing may be ad-hoc; warn if Gatekeeper is likely. Notarization is not automated in-repo.