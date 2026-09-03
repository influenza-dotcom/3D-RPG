@tool
extends RefCounted

## Resource BACK-REFERENCE (owners) finder for the Refs tab: given a res:// resource, walk the project and list
## every file that REFERENCES it — by its res:// PATH or its UID (uid://...). The value over Godot's native
## "View Owners" (which tracks only the resource graph): this also catches .gd scripts that load()/preload() the
## path or embed its uid string, so a designer can see what breaks BEFORE deleting / renaming a .tres/.tscn/.gd.
##
## THREE CALLERS share it, so the public statics are a CONTRACT — keep their names, argument order and the
## {file, lines} row shape: the Refs tab (ref_viewer.gd), the "used by" line the Quest / Dialogue tabs print after
## a save (find_referencers(path, root) over ONE folder), and the `refs` verb of scripts/tools/cyber_cmds.gd.
##
## PURE matchers (references / uid_from_header / matching_lines) are unit-tested on in-memory text; find_referencers
## / uid_for do the res:// walk + file reads, and a temp-dir fixture test (tests/test_devtools_refs.gd) walks them
## too. Matching is SUBSTRING-based (the path/uid appears in the text), so it can slightly OVER-report (e.g. a path
## that's a prefix of another) — safe + intended for a "what points here?" check where the user confirms; far
## better to over-list than to miss a reference and break it.
##
## WHAT THE WALK READS, AND WHY THAT IS BOUNDED. Every scanned file is pulled whole into a Godot String (UTF-32, so
## four times its byte size) and substring-searched. A .res IS scanned, because a resource saved in binary form still
## carries its ext_resource paths as plain text — but the tree also holds ~59 MB of *.flitevox.res under
## addons/text_to_speech/voices/ (raw voice data, not a res:// in it), and reading those on every Find froze the
## editor for seconds. Two guards, both load-bearing (a temp-dir test pins each):
##   * SKIP_DIRS names `text_to_speech` — _walk compares the BARE entry name, never the full path — so the voice
##     addon is never entered at all, and
##   * MAX_FILE_BYTES skips a file by its on-disk size BEFORE it is read (see the const for where the line sits and
##     why it is where it is).
## A reference inside a skipped file is therefore MISSED, not over-reported — the ONE direction this scanner
## deliberately errs in, and a MISS is the dangerous direction for the question this tab answers ("is it safe to
## delete?"). So find_referencers also reports how much it read and what it skipped, and the Refs tab prints those
## numbers beside its verdict: "nothing points at it, out of 0 files read" must never look like "out of 900".

## addons CAN reference project content, so addons/ as a whole is NOT skipped; .godot/.git never hold authored
## references (the walker already skips every dot-folder, they are listed for the reader); text_to_speech is the
## voice-blob addon — see the header. Bare folder NAMES: _walk tests each directory entry against this list.
const SKIP_DIRS: Array[String] = [".godot", ".git", "text_to_speech"]
const SCANNED_EXTS: Array[String] = ["tscn", "tres", "gd", "res"]
## Files larger than this (bytes) are skipped unread. The line has to clear the biggest AUTHORED file in the project
## and still refuse the voice blobs, and those two are far apart, so 4 MB sits between them with room either side:
## the largest authored files today are scenes/props/skeleton.tscn (1.59 MB) and scenes/levels/trenchboom_test_level
## .tscn (1.52 MB — the level the game actually boots into), while the SMALLEST *.flitevox.res voice blob is 5.8 MB.
## This was 512 KB, which is BELOW those three scenes: a resource used only by the live level read as "nothing points
## at it", i.e. "safe to delete", which is the one answer this tab must never get wrong. Raise it again if an
## authored scene ever approaches 4 MB; never lower it below the biggest .tscn on disk.
const MAX_FILE_BYTES: int = 4 * 1024 * 1024


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
## Sorted by file. Editor-side (walk + reads); the pure matchers above are what the unit tests pin, and the fixture
## test walks a temp dir. `root` defaults to res:// (the whole project); it's a parameter so the Quest / Dialogue
## "used by" line can walk one folder and a fixture test can walk a temp dir instead.
##
## `out_stats` is the DENOMINATOR, filled in place for a caller that wants it and ignorable by one that does not —
## which is why it is an optional trailing out-parameter and NOT a change to the return value: three callers share
## this signature (ref_viewer.gd, the Quest / Dialogue "used by" line, and the `refs` verb of
## scripts/tools/cyber_cmds.gd) and the {file, lines} Array is their contract. Keys: `read` (files actually opened
## and searched) and `skipped_large` (paths refused by MAX_FILE_BYTES, unread). Both are RESET on every call, so a
## caller that reuses a dictionary — or a shared default — never accumulates a stale count.
static func find_referencers(target_path: String, root: String = "res://", out_stats: Dictionary = {}) -> Array:
	out_stats["read"] = 0
	out_stats["skipped_large"] = []
	var out: Array = []
	if target_path.is_empty():
		return out
	var uid := uid_for(target_path)
	_walk(root, target_path, uid, out, out_stats)
	out.sort_custom(func(a, b): return String(a["file"]) < String(b["file"]))
	return out


## Recursive directory walk. Skips dot-folders and SKIP_DIRS by bare entry name; reads a file only when its extension
## is in SCANNED_EXTS, it is not the target itself, AND its on-disk size is within MAX_FILE_BYTES — the size test
## runs BEFORE the read, which is the whole point (see the header: the read is what froze the editor). Every read and
## every size refusal is counted into `stats`, so the caller can say what the answer was actually built over.
static func _walk(dir: String, target_path: String, uid: String, out: Array, stats: Dictionary) -> void:
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
					_walk(full, target_path, uid, out, stats)
			elif SCANNED_EXTS.has(full.get_extension()) and full != target_path:
				if FileAccess.get_size(full) > MAX_FILE_BYTES:
					(stats["skipped_large"] as Array).append(full)
				else:
					var txt := FileAccess.get_file_as_string(full)
					if not txt.is_empty():
						stats["read"] = int(stats["read"]) + 1
						var lines := matching_lines(txt, target_path, uid)
						if not lines.is_empty():
							out.append({"file": full, "lines": lines})
		e = d.get_next()
	d.list_dir_end()
