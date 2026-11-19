# Photo Viewer

Native macOS app for browsing, grouping, and exporting photos from user-chosen folders without changing originals.

## Language

**Project**:
A saved workspace that owns source folders, albums, annotations, bookmarks, and a dedicated on-disk index.
_Avoid_: Library (as the top-level noun), Workspace

**Library** (view):
The main browse screen inside a project where photos are filtered, grouped, and opened.
_Avoid_: Gallery, Collection (for the whole UI)

**Source folder**:
A user-granted directory whose image files are indexed and displayed; contents are never modified by the app.
_Avoid_: Root folder, Import folder

**Catalog**:
The set of image file paths discovered under all source folders for a project, stored primarily in SQLite; at most one entry per normalized path project-wide.
_Avoid_: Library (as data), Inventory

**Suggested album**:
A dismissible chip after analysis that offers to create a smart album from a high-count label or category; never created without user action.
_Avoid_: Auto album, Smart collection

**Album**:
A named, persisted collection within a project—either manual (explicit members) or smart (rule-defined).
_Avoid_: Virtual folder, Folder, Playlist

**Manual album**:
An album whose membership is an explicit list of file paths the user curates.
_Avoid_: Virtual folder

**Smart album**:
An album defined by rules (metadata, analysis, people, etc.); membership is computed from the index.
_Avoid_: Dynamic folder, Saved search

**Browse grouping**:
Temporary sidebar navigation (by date, location, camera, people, semantic category) that is not saved as an album.
_Avoid_: Album, Smart album

**People**:
A persisted cluster of detected faces across the project, optionally given a display name by the user.
_Avoid_: Person (as the cluster noun—use People for the feature), Contact

**Export**:
Copying album members into a single flat destination folder the user chooses; the only operation that writes new image files.
_Avoid_: Organize, Move, Sync

**Analysis**:
On-device enrichment (OCR, scene labels, semantic category, faces) stored in the index; optional and throttled.
_Avoid_: Scan (use Catalog for discovery), Processing