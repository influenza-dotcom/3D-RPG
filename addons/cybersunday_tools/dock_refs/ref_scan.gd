@tool
extends RefCounted

## Resource BACK-REFERENCE (owners) finder for the Refs tab: given a res:// resource, walk the project and list
## every file that REFERENCES it — by its res:// PATH or its UID (uid://...). The value over Godot's native
## "View Owners" (which tracks only the resource graph): this also catches .gd scripts that load()/preload() the
## path or embed its uid string, so a designer can see what breaks BEFORE deleting / renaming a .tres/.tscn/.gd.
##
## PURE matchers (references / uid_from_header) are unit-tested; find_referencers / uid_for do the res:// walk +
## file reads (editor-verified). Matching is SUBSTRING-based (the path/uid appears in the text), so it can slightly
## OVER-report (e.g. a path that's a prefix of another) — safe + intended for a "what points here?" check where the
## user confirms; far better to over-list than to miss a reference and break it. .res (binary) is best-effort.

## addons CAN reference project content, so it is NOT skipped; .godot/.git never hold authored references.
const SKIP_DIRS: Array[String] = [".godot", ".git"]
const SCANNED_EXTS: Array[String] = ["tscn", "tres", "gd", "res"]


## Does `text` reference the target identified by `path` (res://...) and/or `uid` (uid://..., may be "")? Pure.
static func references(text: String, path: String, uid: String) -> bool:
	if not path.is_empty() and path in text:
		return true
	return not uid.is_empty() and uid in text


## Pull a `uid="uid://..."` out of a .tres/.tscn header line. "" when there's none. Pure.
static func uid_from_header(text: String) -> String:
	var re := RegEx.new()
	re.compile("uid=\"(uid://[^\"]+)\"")
	var m := re.search(text)
	return m.get_string(1) if m != null else ""


## The uid of the resource at `path`: a .gd reads its sibling `.gd.uid` sidecar; a .tres/.tscn reads its header
## line (the uid lives in the first `[gd_resource ...]` / `[gd_scene ...]` line). "" when the file has no uid.
static func uid_for(path: String) -> String:
	if path.get_extension() == "gd":
		var side := path + ".uid"
		return FileAccess.get_file_as_string(side).strip_edges() if FileAccess.file_exists(side) else ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return uid_from_header(f.get_line())


## Up to `cap` trimmed lines of `text` that reference the target (by path or uid) — the "property / context" of each
## reference (e.g. an `[ext_resource ... path=...]` row, or a `load("res://...")` call). Capped so a file that
## mentions the target many times doesn't flood the view. Pure.
static func matching_lines(text: String, path: String, uid: String, cap: int = 8) -> PackedStringArray:
	var out := PackedStringArray()
	for line in text.split("\n"):
		if (not path.is_empty() and path in line) or (not uid.is_empty() and uid in line):
			var l := line.strip_edges()
			if not l.is_empty():
				out.append(l)
				if out.size() >= cap:
					break
	return out


## Every project file that references `target_path` (by path OR uid), excluding the target itself. Each entry is
## {file, lines} — `lines` are the referring lines (the "where"), so a delete/rename preview shows file + context.
## Sorted by file. Editor-side (walk + reads); the pure matchers above are what the tests pin.
## `root` defaults to res:// (the whole project); it's a parameter so a fixture test can walk a temp dir instead.
static func find_referencers(target_path: String, root: String = "res://") -> Array:
	var out: Array = []
	if target_path.is_empty():
		return out
	var uid := uid_for(target_path)
	_walk(root, target_path, uid, out)
	out.sort_custom(func(a, b): return String(a["file"]) < String(b["file"]))
	return out


static func _walk(dir: String, target_path: String, uid: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var e := d.get_next()
	while e != "":
		if not e.begins_with("."):
			var full := dir.path_join(e)
			if d.current_is_dir():
				if not SKIP_DIRS.has(e):
					_walk(full, target_path, uid, out)
			elif SCANNED_EXTS.has(full.get_extension()) and full != target_path:
				var txt := FileAccess.get_file_as_string(full)
				if not txt.is_empty():
					var lines := matching_lines(txt, target_path, uid)
					if not lines.is_empty():
						out.append({"file": full, "lines": lines})
		e = d.get_next()
	d.list_dir_end()
