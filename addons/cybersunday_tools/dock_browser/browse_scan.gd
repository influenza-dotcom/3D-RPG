@tool
extends RefCounted

## PURE content-browser scan/filter helpers for the unified Content Browser (content_browser.gd).
## NO EditorInterface, NO scene-tree access here -- so the GUT test can call these directly headless.
##
## Two halves:
##  - scan_grouped(roots): walks each res:// folder recursively and returns { group label -> sorted Array[String]
##    of res:// .tres paths }. Touches disk (DirAccess) but no editor; testable against the real resources/* tree.
##  - filter_paths(paths, needle): a DISK-FREE filter over a pre-scanned path list (case-insensitive substring on the
##    basename OR full path). This is the unit-tested core so the search logic is verified without any folder fixture.
##
## `roots` is { group label : res:// folder } -- the content_browser passes the dock_content DIR consts keyed by their
## designer-facing content-type label (Quests / NPCs / Weapons / ...). The folder layout matches content_dock.gd.


## Recursively list every .tres (and .res) under `root`, returning sorted res:// paths. PURE (DirAccess only, no
## editor). A missing/empty folder yields []. `.remap` suffixes (exported builds) are trimmed before the ext check.
static func scan_folder(root: String) -> Array[String]:
	var out: Array[String] = []
	_scan_into(root, out)
	out.sort()
	return out


## Internal recursive worker: append every resource file under `dir` into `out` (unsorted). DirAccess accepts res://.
static func _scan_into(dir: String, out: Array[String]) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = da.get_next()
			continue
		var path := dir.path_join(entry)
		if da.current_is_dir():
			_scan_into(path, out)
		else:
			var fname := entry.trim_suffix(".remap")  # exported builds may append .remap to packed resources
			if fname.ends_with(".tres") or fname.ends_with(".res"):
				out.append(dir.path_join(fname))
		entry = da.get_next()


## Build the grouped model the Tree renders: { group label -> sorted Array[String] of res:// paths }. PURE (DirAccess
## only). `roots` is { group label : res:// folder }. Every group key is preserved even when its folder is empty/absent
## (so the Tree can show "Quests (0)" rather than silently dropping the section). Iteration order follows `roots`.
static func scan_grouped(roots: Dictionary) -> Dictionary:
	var grouped: Dictionary = {}
	for label in roots:
		var folder := String(roots[label])
		grouped[String(label)] = scan_folder(folder)
	return grouped


## DISK-FREE filter: keep paths whose basename OR full res:// path contains `needle` (case-insensitive). An empty/blank
## needle returns the list unchanged. This is the search core -- unit-tested with an in-memory list, no folder fixture.
static func filter_paths(paths: Array, needle: String) -> Array[String]:
	var out: Array[String] = []
	var n := needle.strip_edges().to_lower()
	for p in paths:
		var path := String(p)
		if n == "":
			out.append(path)
			continue
		var base := path.get_file().to_lower()
		if base.contains(n) or path.to_lower().contains(n):
			out.append(path)
	return out


## Filter a whole grouped model (the scan_grouped output) by `needle`, dropping groups that end up empty AFTER the
## filter (so a search collapses the Tree to only matching sections). PURE + disk-free (operates on the passed model).
static func filter_grouped(grouped: Dictionary, needle: String) -> Dictionary:
	var out: Dictionary = {}
	for label in grouped:
		var kept := filter_paths(grouped[label], needle)
		if not kept.is_empty():
			out[String(label)] = kept
	return out
