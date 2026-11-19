---
status: accepted
---

# Security-scoped bookmarks for source folders

Source folders are reached via user-picked URLs stored as security-scoped bookmarks, not via Full Disk Access. Each additional folder is another bookmark; if access expires or a volume is offline, the app prompts to re-select rather than failing silently. Sandboxing keeps the app distributable; the trade-off is re-authorization after moves or permission changes.