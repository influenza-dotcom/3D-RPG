@tool
extends RefCounted

## FOLDER SCAN of the authored items (resources/items/*.tres) for edit-time tools. `ItemDb` (the runtime registry)
## is a NON-@tool autoload, so inside the editor it is a bare Node with an empty index -- every plugin surface that
## needs "all the items" must scan the folder itself. This is the ONE shared scan (the Items placer, the Audit's
## content check and the File -> Run content validator all read it) so a new folder rule lands in one place.
##
## `scan()` is the plain list (folder order, nulls dropped). `scan_report()` also returns the paths that FAILED to
## load, so a tab can say "3 files failed to load" instead of silently showing a shorter list (the mid-reimport /
## broken-script case, which otherwise reads as "my item vanished").

const ITEMS_DIR := "res://resources/items"


static func scan(dir: String = ITEMS_DIR) -> Array[Item]:
	var rep := scan_report(dir)
	var items: Array[Item] = []
	for it in rep["items"]:
		items.append(it)
	return items


## {items: Array[Item], skipped: PackedStringArray (paths that exist but did not load as an Item)}.
static func scan_report(dir: String = ITEMS_DIR) -> Dictionary:
	var items: Array[Item] = []
	var skipped := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return {"items": items, "skipped": skipped}
	for f in d.get_files():
		var fname := f.trim_suffix(".remap")
		if not (fname.ends_with(".tres") or fname.ends_with(".res")):
			continue
		var path := dir.path_join(fname)
		var it := load(path) as Item
		if it != null:
			items.append(it)
		else:
			skipped.append(path)
	return {"items": items, "skipped": skipped}
