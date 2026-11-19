# Agent context — Photo Viewer (macOS)

Native **SwiftUI** photo library app. Generated Xcode project via **XcodeGen** (`project.yml` is source of truth for targets and versions).

## When to read what

| Task | Document |
|------|-----------|
| **Build, bump version, deploy release** | [`.cursor/skills/build-and-deploy/SKILL.md`](.cursor/skills/build-and-deploy/SKILL.md) |
| **Ship a version / GitHub release / in-app updates** | [`docs/DEPLOY_AND_UPDATES.md`](docs/DEPLOY_AND_UPDATES.md) |
| Domain terms | [`GLOSSARY.md`](GLOSSARY.md) |
| Product decisions | [`docs/adr/`](docs/adr/) |
| Human build/run | [`README.md`](README.md) |

## Repository and updates

- **GitHub (public):** `engineeritdevelopment-hk/photo-viewer-app`
- **`origin`** should point at that repo. Use **`gh`** with account **`engineeritdevelopment-hk`** for releases (`gh auth switch --user engineeritdevelopment-hk` if needed).
- In-app update feed: `INFOPLIST_KEY_PhotoViewerGitHubRepository` in `project.yml` (must stay in sync with the public release repo).
- Releases must include a **`.zip`** asset containing **`Photo Viewer.app`** or one-click update install fails.

## Project map

| Area | Location |
|------|-----------|
| App entry, menu commands | `PhotoViewer/PhotoViewerApp.swift` |
| Library UI / sidebar | `PhotoViewer/Views/LibraryView.swift` |
| View models | `PhotoViewer/ViewModels/` |
| Catalog / index | `PhotoViewer/Services/PhotoIndexStore.swift`, `PhotoCatalogScanner.swift` |
| Updates | `PhotoViewer/Services/Update/`, `PhotoViewer/ViewModels/AppUpdateModel.swift` |
| Install helper (non-sandboxed tool) | `PhotoViewerInstallHelper/` |
| Unit tests | `PhotoViewerTests/` |

User data (never delete in automation): `~/Library/Application Support/photo_viewer/`.

## Routine commands

```bash
xcodegen generate
xcodebuild -scheme PhotoViewer -configuration Debug -derivedDataPath build/xcode build
xcodebuild -scheme PhotoViewer -configuration Debug -derivedDataPath build/xcode test
```

After editing `project.yml`, always run **`xcodegen generate`** before building.

## Agent guardrails

- **Do not commit** `build/`, `DerivedData/`, secrets, or `.env`.
- **Do not** change git remotes or force-push `main` unless the user explicitly asks.
- **Commits** only when the user asks; use conventional commits (`feat:`, `fix:`, `chore:`).
- Prefer **small, focused diffs**; match existing SwiftUI patterns in neighboring files.
- **Signing:** local Release builds may be ad-hoc signed; document if a release is not notarized.

## Release shortcut

```bash
./scripts/bump-version.sh patch   # optional
./scripts/release.sh
./scripts/install-local.sh      # optional smoke test
```

Agents: read **`.cursor/skills/build-and-deploy/SKILL.md`** when the user mentions build, deploy, release, or version bumps.