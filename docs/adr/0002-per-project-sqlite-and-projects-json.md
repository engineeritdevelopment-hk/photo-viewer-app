---
status: accepted
---

# Per-project SQLite index and projects.json for user intent

Each project keeps a large SQLite catalog (`PhotoIndexStore`) under Application Support, keyed by project id, for paths, metadata, analysis fields, and fast group/filter queries. `projects.json` holds portable user intent: project name, source bookmarks, albums, annotations, and person display names. Splitting them avoids loading tens of thousands of rows into memory and keeps JSON small, while SQLite can be rebuilt from sources if needed.