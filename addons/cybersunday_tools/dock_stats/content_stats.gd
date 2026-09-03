@tool
extends RefCounted

## PURE logic for the Stats dashboard: collect which resources a file REFERENCES, decide if a resource is referenced
## anywhere, and the WALK POLICY (which folders the reference walk enters, which files it reads). The tab unions
## collect_referenced() across the whole project into lookup sets, then asks is_referenced() per resource to surface
## unused content. Everything here is pure + unit-tested; the tab (stats_view.gd) owns the recursive walk + counts.
##
## CAVEAT the tab must honor: lots of content here is loaded by FOLDER SCAN (ItemDb scans resources/items/, factions
## are scanned, abilities by filename) — those are USED without an explicit ref, so the unreferenced check must be
## limited to REFERENCE-used types (a WeaponData used via Item.weapon, a LootTable via NpcData.loot, ...). This file
## just answers "is X referenced by some file"; the tab restricts WHICH folders it flags.

## THE WALK POLICY, kept here (pure) so the tab's recursive walk and the GUT test read the same three facts:
##   * SKIP_DIRS — folders the reference walk never enters. `.godot` is derived, `.git` is history, and `addons/`
##     holds plugin code and plugin assets, never project content: nothing under addons/ points at a resources/
##     file by design, while addons/text_to_speech/voices/ alone is ~59 MB of binary voice blobs. Reading those as
##     Godot Strings (UTF-32 internally) on the editor's main thread is what FROZE the editor on every Stats scan
##     before this skip existed — the same freeze the Refs tab had, fixed the same way.
##   * MAX_FILE_BYTES — a file larger than this is skipped WITHOUT being read (the tab checks the size on the open
##     handle first). The line MUST sit above the biggest AUTHORED file in the project, because every unread file
##     silently makes the "unused content" list LONGER: a reference the walk never saw is a resource the tab invites
##     the designer to delete. It was 512 KB, which is below scenes/props/skeleton.tscn (1.59 MB),
##     scenes/levels/trenchboom_test_level.tscn (1.52 MB — the level the game actually boots into) and
##     scenes/props/billboard.tscn (0.68 MB); anything used only by one of those three read as unused. 4 MB clears
##     all three with room to spare and still refuses every voice blob (the smallest is 5.8 MB), which is what the
##     cap is really for. Raise it if an authored scene ever approaches it; never lower it below the biggest .tscn.
##   * SCANNED_EXTS — the formats a reference can live in. `.res` stays: a SMALL binary resource can still embed a
##     path string, and the size cap is what makes reading it safe.
const SKIP_DIRS: Array[String] = [".godot", ".git", "addons"]
const SCANNED_EXTS: Array[String] = ["gd", "tscn", "tres", "res"]
const MAX_FILE_BYTES := 4 * 1024 * 1024


## Does the walk stay OUT of a folder named `dir_name` (the entry name, not a path)? Pure.
static func skips_dir(dir_name: String) -> bool:
	return SKIP_DIRS.has(dir_name)


## Is `path` a format the walk reads at all? `.remap` (an exported build's suffix) is trimmed before the extension
## test so the two spellings of a packed resource agree. A `.gd.uid` sidecar or a `.png` is refused here, before any
## file is opened. Pure.
static func scans_ext(path: String) -> bool:
	return SCANNED_EXTS.has(path.trim_suffix(".remap").get_extension())


## Is a file of `size_bytes` small enough to read? Exactly MAX_FILE_BYTES still reads; one byte over does not. Pure.
static func fits_size(size_bytes: int) -> bool:
	return size_bytes <= MAX_FILE_BYTES


## The whole policy for one file: a scanned format AND under the cap. The tab calls scans_ext() first (no open for a
## wrong extension) and fits_size() on the opened handle's length; this is the one-call form the test pins. Pure.
static func scans_file(path: String, size_bytes: int) -> bool:
	return scans_ext(path) and fits_size(size_bytes)


## Resources referenced by one file's text: every `path="res://..."` (ext_resource / sub-resource), every
## ext_resource `uid="uid://..."`, and every load()/preload("res://...") call. {paths: Array, uids: Array}. Pure.
## Over-collecting references is the SAFE direction here — it only ever makes the unreferenced list SHORTER.
static func collect_referenced(text: String) -> Dictionary:
	var paths: Array = []
	var uids: Array = []
	var re_path := RegEx.new()
	re_path.compile("path=\"(res://[^\"]+)\"")
	for m in re_path.search_all(text):
		paths.append(m.get_string(1))
	var re_uid := RegEx.new()
	re_uid.compile("ext_resource[^\\]]*uid=\"(uid://[^\"]+)\"")  # ext_resource lines only -> never a .tres's own header uid
	for m in re_uid.search_all(text):
		uids.append(m.get_string(1))
	var re_load := RegEx.new()
	re_load.compile("(?:load|preload)\\(\\s*\"(res://[^\"]+)\"")
	for m in re_load.search_all(text):
		paths.append(m.get_string(1))
	return {"paths": paths, "uids": uids}


## Is the resource at `path` (uid `uid`, may be "") referenced anywhere? `ref_paths` / `ref_uids` are Dictionaries
## used as SETS (key -> true) of everything collected across the project. Pure + O(1) lookups.
static func is_referenced(path: String, uid: String, ref_paths: Dictionary, ref_uids: Dictionary) -> bool:
	return ref_paths.has(path) or (not uid.is_empty() and ref_uids.has(uid))
