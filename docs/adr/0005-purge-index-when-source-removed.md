---
status: accepted
---

# Purge catalog rows when a source folder is removed

Removing a source folder from a project deletes its paths from the SQLite index, removes those paths from manual albums, and drops stale analysis rows. Smart albums recompute on the next evaluation so they never reference files outside current sources. Re-adding a folder triggers a fresh or incremental scan rather than resurrecting old rows silently.