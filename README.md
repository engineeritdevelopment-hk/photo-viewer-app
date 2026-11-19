# Photo Viewer (native macOS)

SwiftUI app for browsing photos from multiple user-selected folders (including external drives). Sources are **read-only**; albums and export are the only write paths.

## Features

- Multiple **projects**, each with multiple **source folders** (security-scoped bookmarks)
- Fast **SQLite catalog**, incremental indexing, thumbnail cache
- **Metadata** (EXIF, GPS), optional **place** reverse geocoding
- On-device **semantic analysis** (Vision OCR/classify, Natural Language, optional Foundation Models)
- Optional **face detection** and people clustering
- **Manual** and **smart** albums, flat-folder **export**
- Loading banners and per-cell thumbnail placeholders

## Requirements

- macOS 15+
- Xcode 26+ (for building)

## Updates

In-app updates use the **public** repo **`engineeritdevelopment-hk/photo-viewer-app`**: on launch, daily while open, and via **Check for Updates…** (⇧⌘U) or the **info** popover.

**Maintainers:** full checklist — [`docs/DEPLOY_AND_UPDATES.md`](docs/DEPLOY_AND_UPDATES.md). Quick path: bump versions in `project.yml`, then `./scripts/release.sh`. Agent context: [`AGENTS.md`](AGENTS.md).

## Build and run

```bash
cd photo-viewer-app
xcodegen generate   # if PhotoViewer.xcodeproj is missing
open PhotoViewer.xcodeproj
```

Run the **Photo Viewer** scheme in Xcode, or:

```bash
xcodebuild -scheme PhotoViewer -configuration Debug -derivedDataPath build/xcode build
open build/xcode/Build/Products/Debug/Photo\ Viewer.app
```

## Data locations

- `~/Library/Application Support/photo_viewer/projects.json` — projects, albums, annotations (compatible with the former Flutter app’s format; legacy `folders` migrate to manual albums)
- `~/Library/Application Support/photo_viewer/indexes/<projectId>.sqlite` — per-project catalog
- `~/Library/Application Support/photo_viewer/thumbnails/` — disk thumbnail cache

## Domain docs

- [`GLOSSARY.md`](GLOSSARY.md)
- [`docs/adr/`](docs/adr/)

## Analysis stack

- **Vision** — scene labels, OCR, face detection, feature-print clustering
- **NaturalLanguage** + **Spotlight** metadata — semantic categories
- **Foundation Models** (when available) — richer folder suggestions

See ADRs for product decisions (read-only sources, sandbox bookmarks, SQLite split).