---
status: accepted
---

# One catalog row per normalized path

A project may attach multiple source folders whose trees overlap. The catalog deduplicates by normalized filesystem path so each file appears once in the grid, index, and analysis store. Without deduplication, thumbnails and face clusters would double-count the same bytes on disk.