---
status: accepted
---

# Read-only source folders; export is the only write path

The app indexes and displays images from user-added source folders (including external volumes) but never renames, moves, deletes, or edits files there. The only user-initiated write is **Export**, which copies selected album members to a new destination. We chose this so multi-source libraries stay trustworthy on shared or archival disks and so permissions stay minimal under sandboxed folder access.