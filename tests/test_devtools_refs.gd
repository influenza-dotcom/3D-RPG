extends GutTest

## The CYBER SUNDAY Refs tab: the read-only "what points at this file?" viewer. The PURE matchers in ref_scan.gd
## (references / matching_lines / uid_from_header) are unit-tested with in-memory text; find_referencers is walked
## over a temp-dir fixture (never project content) so its two READ guards -- the skipped voice-addon folder and the
## per-file size cap that stopped the editor freezing on 59 MB of voice blobs -- stay pinned, along with the
## DENOMINATOR the walk reports back (files read, files too big to read). The size cap gets both of its bounds
## asserted, because it is a correctness knob: too low and a resource used only by the 1.5 MB live level reads as
## "safe to delete". The tab itself is constructed bare (.new(), no tree) and checked for its layout contract, its
## button states, the select_path handoff refusals (no disk walk) and the row rendering over synthetic rows; the real
## project walk and every EditorInterface call are editor-verified, like the other dock tests.

const RefScan := preload("res://addons/cybersunday_tools/dock_refs/ref_scan.gd")
const RefViewer := preload("res://addons/cybersunday_tools/dock_refs/ref_viewer.gd")


func test_references_matches_path_or_uid_not_neither() -> void:
	var text := "[ext_resource type=\"Resource\" uid=\"uid://abc123\" path=\"res://resources/items/healthpack.tres\" id=\"1\"]"
	assert_true(RefScan.references(text, "res://resources/items/healthpack.tres", ""), "matches by path")
	assert_true(RefScan.references(text, "res://nope.tres", "uid://abc123"), "matches by uid when the path differs")
	assert_false(RefScan.references(text, "res://nope.tres", "uid://zzz"), "no match -> false")
	assert_false(RefScan.references(text, "", ""), "empty target never matches")


func test_references_ignores_empty_uid() -> void:
	# An empty uid must NOT match (else every file would 'reference' an empty string).
	assert_false(RefScan.references("any text with uid:// in it", "res://x.tres", ""), "empty uid is never used as a needle")


func test_matching_lines_returns_referring_lines_capped() -> void:
	var text := "line one res://a.tres\nunrelated line\nload(\"res://a.tres\")\n\tslot = res://a.tres\n"
	var lines := RefScan.matching_lines(text, "res://a.tres", "")
	assert_eq(lines.size(), 3, "the three lines mentioning the path are returned; the unrelated line is skipped")
	assert_eq(lines[1], "load(\"res://a.tres\")", "lines are trimmed of leading whitespace")
	# Cap: a file mentioning the target many times is capped so it can't flood the view.
	var many := ""
	for i in 20:
		many += "res://a.tres\n"
	assert_eq(RefScan.matching_lines(many, "res://a.tres", "", 8).size(), 8, "capped at the requested limit")


func test_matching_lines_matches_by_uid_too() -> void:
	var text := "ext_resource uid=\"uid://q9\"\nother\n"
	var lines := RefScan.matching_lines(text, "res://unrelated.tres", "uid://q9")
	assert_eq(lines.size(), 1, "a uid-only reference is found")


func test_uid_from_header_extracts_or_empty() -> void:
	assert_eq(RefScan.uid_from_header("[gd_resource type=\"Resource\" script_class=\"LootTable\" load_steps=2 uid=\"uid://cabc\"]"), "uid://cabc", "pulls the uid out of a header")
	assert_eq(RefScan.uid_from_header("[gd_scene format=3]"), "", "no uid -> empty string")


## --- find_referencers() fixture: exercise the real walk against temp files (NOT project content) ---

const TMP := "user://test_refs_fixture"


func after_each() -> void:
	_remove_tree(TMP)


## Recursive cleanup: the fixture now grows a sub-folder (the skipped voice-addon name), and a DirAccess can only
## remove an EMPTY directory -- so files go first, then each sub-folder, then the folder itself.
func _remove_tree(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for e in d.get_files():
		d.remove(e)
	for sub in d.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f = null


## The bare file names of a find_referencers result, for membership asserts.
func _names(refs: Array) -> Array:
	var files := []
	for r in refs:
		var row: Dictionary = r if r is Dictionary else {}
		files.append(String(row.get("file", "")).get_file())
	return files


func test_find_referencers_walks_and_matches_path_and_uid() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	var target := TMP + "/target.tres"
	_write(target, "[gd_resource type=\"Resource\" uid=\"uid://fixtureuid77\"]\n")
	_write(TMP + "/owner_by_path.tscn", "[ext_resource path=\"%s\" id=\"1\"]\n" % target)
	_write(TMP + "/owner_by_uid.tscn", "[ext_resource uid=\"uid://fixtureuid77\" id=\"1\"]\n")
	_write(TMP + "/unrelated.tscn", "[gd_scene format=3]\nnothing to see\n")
	var refs := RefScan.find_referencers(target, TMP)  # no trailing slash -> full path of the target matches for self-exclusion
	var files := _names(refs)
	assert_eq(refs.size(), 2, "two owners found; the unrelated file and the target itself are excluded")
	assert_true("owner_by_path.tscn" in files, "the path reference is found")
	assert_true("owner_by_uid.tscn" in files, "the uid reference is found — uid_for() read the target's header uid")
	assert_false("target.tres" in files, "the target excludes itself")


## Write a file just past MAX_FILE_BYTES without ever holding it whole in memory: a Godot String is UTF-32, so a
## single "x".repeat(cap + 1) at a 4 MB cap is a 16 MB allocation for a fixture nobody reads.
func _write_oversize(path: String, head: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(head)
	var chunk := "x".repeat(64 * 1024)  # pure ASCII, so one character is one byte on disk
	var written := head.length()
	while written <= RefScan.MAX_FILE_BYTES:
		f.store_string(chunk)
		written += chunk.length()
	f = null


func test_size_cap_clears_the_biggest_authored_scene_and_still_refuses_the_voice_blobs() -> void:
	# THE CAP IS A CORRECTNESS KNOB, NOT A PERFORMANCE ONE. A file the walk never reads is a reference it never
	# finds, and a missed reference here reads as "nothing points at it -- safe to delete". The cap was 512 KB, which
	# is BELOW scenes/props/skeleton.tscn (1.59 MB), scenes/levels/trenchboom_test_level.tscn (1.52 MB -- the level
	# the game boots into) and scenes/props/billboard.tscn (0.68 MB), so a resource used only by one of those three
	# was reported deletable. The two bounds are what matters, not the round number between them.
	assert_gte(RefScan.MAX_FILE_BYTES, 2 * 1024 * 1024,
		"the cap must clear the biggest authored .tscn (1.59 MB today) -- below it, a resource used only by the live level reads as safe to delete")
	assert_lt(RefScan.MAX_FILE_BYTES, 5 * 1024 * 1024,
		"and stay under the smallest *.flitevox.res voice blob (5.8 MB), which is the editor freeze the cap exists to stop")


func test_find_referencers_skips_files_over_the_size_cap_unread() -> void:
	# The freeze: ~59 MB of *.flitevox.res voice blobs were read as text on every Find. The guard is BY SIZE, before
	# the read -- so a .res under the cap that mentions the target is still found (the extension IS scanned), while a
	# .res over MAX_FILE_BYTES is skipped even though the target's path sits in its very first line.
	DirAccess.make_dir_recursive_absolute(TMP)
	var target := TMP + "/target.tres"
	_write(target, "[gd_resource type=\"Resource\" uid=\"uid://fixtureuid78\"]\n")
	_write(TMP + "/small_owner.res", "header path=\"%s\" trailer\n" % target)
	var blob_path := TMP + "/voice_blob.res"
	_write_oversize(blob_path, "path=\"%s\"\n" % target)
	assert_gt(FileAccess.get_size(blob_path), RefScan.MAX_FILE_BYTES, "the fixture blob is over the cap (%d bytes)" % RefScan.MAX_FILE_BYTES)
	var stats := {}
	var refs := RefScan.find_referencers(target, TMP, stats)
	var files := _names(refs)
	assert_true("small_owner.res" in files, "a small .res that mentions the target is read and listed")
	assert_false("voice_blob.res" in files, "a .res over MAX_FILE_BYTES is skipped unread even though it names the target")
	assert_eq(refs.size(), 1, "exactly the small owner is listed")
	# A miss is the DANGEROUS direction for "is it safe to delete?", so the skip is reported, never silent.
	assert_eq(int(stats["read"]), 1, "one file was actually read -- the target is skipped before the open, the blob before the read")
	assert_eq((stats["skipped_large"] as Array).size(), 1, "and the one over the cap is named as skipped: %s" % str(stats["skipped_large"]))
	assert_true(String((stats["skipped_large"] as Array)[0]).ends_with("voice_blob.res"), "by its path, so a human can go look at it")


func test_find_referencers_reports_its_denominator_and_resets_it_per_call() -> void:
	# "Found nothing" over 0 files read and over 900 files read are different answers; the tab prints this number
	# beside the verdict so they cannot read the same. Reused dictionaries must not accumulate across calls.
	DirAccess.make_dir_recursive_absolute(TMP)
	var target := TMP + "/target.tres"
	_write(target, "[gd_resource type=\"Resource\"]\n")
	_write(TMP + "/owner.tscn", "path=\"%s\"\n" % target)
	_write(TMP + "/unrelated.tscn", "[gd_scene format=3]\n")
	var stats := {}
	RefScan.find_referencers(target, TMP, stats)
	assert_eq(int(stats["read"]), 2, "every file the walk opened counts toward the denominator, matching or not (the target itself is never opened)")
	assert_true((stats["skipped_large"] as Array).is_empty(), "nothing was too big here")
	RefScan.find_referencers(target, TMP, stats)
	assert_eq(int(stats["read"]), 2, "a second call RESETS the counters instead of doubling them")
	RefScan.find_referencers("", TMP, stats)
	assert_eq(int(stats["read"]), 0, "an empty target reads nothing, and says so rather than leaving the last count standing")


func test_find_referencers_skips_the_voice_addon_folder_by_bare_name() -> void:
	# SKIP_DIRS is matched against the BARE directory entry, so a text_to_speech folder anywhere under the root is
	# never entered; a sibling folder with the same owner file proves the walk itself still descends.
	DirAccess.make_dir_recursive_absolute(TMP + "/text_to_speech/voices")
	DirAccess.make_dir_recursive_absolute(TMP + "/other")
	var target := TMP + "/target.tres"
	_write(target, "[gd_resource type=\"Resource\"]\n")
	_write(TMP + "/text_to_speech/voices/owner.tres", "path=\"%s\"\n" % target)
	_write(TMP + "/other/owner.tres", "path=\"%s\"\n" % target)
	assert_true(RefScan.SKIP_DIRS.has("text_to_speech"), "the voice-blob addon folder is in SKIP_DIRS by bare name")
	var refs := RefScan.find_referencers(target, TMP)
	assert_eq(refs.size(), 1, "only the sibling folder's owner is listed; the voice folder is never entered")
	if refs.size() == 1:
		var row: Dictionary = refs[0]
		assert_true(String(row.get("file", "")).ends_with("/other/owner.tres"), "the listed owner is the one outside text_to_speech")


## --- the tab: bare construction, layout contract, button states, handoff refusals, row rendering ---


func test_ref_viewer_constructs_with_the_layout_contract() -> void:
	var p = RefViewer.new()
	assert_not_null(p, "the Refs tab constructs (compiles + _init builds UI off-tree)")
	assert_eq(p.name, "Refs", "the panel keys the tab title and show_tab routing on this Control name")
	assert_eq(p._status.text, RefViewer.MSG_IDLE, "idle status = one imperative next step")
	assert_eq(p._status.tooltip_text, RefViewer.MSG_IDLE, "the status tooltip mirrors the text on every write")
	assert_eq(p._status.max_lines_visible, 2, "the one status Label shows two lines")
	assert_eq(p._status.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the status wraps")
	assert_true(p._tree.get_parent() is ScrollContainer, "the Tree is fenced by a ScrollContainer")
	var scroll: ScrollContainer = p._tree.get_parent()
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "a long row must never widen the bottom panel")
	assert_lte(scroll.custom_minimum_size.y, 120.0, "the height fence floors at or under 120 px")
	assert_lte(p._tree.custom_minimum_size.y, 120.0, "the Tree's own floor stays small")
	assert_true(p._use_btn.tooltip_text.ends_with("Read-only."), "Use Selected's tooltip ends with the write contract")
	assert_true(RefViewer.FIND_TIP.ends_with("Read-only."), "Find Refs' tooltip ends with the write contract")
	p.free()


func test_find_refs_greys_until_a_path_is_typed() -> void:
	var p = RefViewer.new()
	assert_true(p._find_btn.disabled, "a blank path box greys Find Refs")
	assert_eq(p._find_btn.tooltip_text, RefViewer.MSG_NO_PATH, "the disabled tooltip names what is missing")
	p._target.text = "res://x.tres"
	p._on_target_changed("res://x.tres")  # the text setter does not emit text_changed; call the handler as a keystroke would
	assert_false(p._find_btn.disabled, "a typed path enables Find Refs")
	assert_eq(p._find_btn.tooltip_text, RefViewer.FIND_TIP, "...and restores the real tooltip")
	assert_false(p._use_btn.disabled, "Use Selected stays live outside a scan")
	p.free()


func test_select_path_refuses_blank_folder_and_missing_without_a_walk() -> void:
	var p = RefViewer.new()
	assert_false(p.select_path(""), "a blank path is refused")
	assert_eq(p._status.text, RefViewer.MSG_NO_PATH, "the blank refusal is the guard template")
	assert_false(p.select_path("res://resources/"), "a folder is refused")
	assert_true(p._status.text.begins_with("Couldn't find refs for resources: that is a folder"), "the folder refusal says so plainly -- got %s" % p._status.text)
	assert_false(p.select_path("res://definitely/not/here.tres"), "a path with no file on disk is refused")
	assert_eq(p._target.text, "res://definitely/not/here.tres", "the path box still shows what was handed over, so the designer can fix it")
	assert_true(p._status.text.begins_with("Couldn't find refs for here.tres: there is no file at that path"), "refused grammar: Couldn't <verb> <Name>: <reason> -- got %s" % p._status.text)
	assert_eq(p._status.tooltip_text, p._status.text, "the tooltip mirrors the refusal too")
	assert_false(p._find_btn.disabled, "a filled box keeps Find Refs live for the retry")
	assert_false(p.select_path("nope/missing.tres"), "a path without the project prefix is completed before the disk check")
	assert_true(p._status.text.begins_with("Couldn't find refs for missing.tres:"), "the completed path is what gets checked -- got %s" % p._status.text)
	p.free()


func test_short_line_trims_and_caps_at_line_chars() -> void:
	assert_eq(RefViewer.short_line("   load(\"res://a.tres\")  "), "load(\"res://a.tres\")", "whitespace-trimmed; a short line is otherwise untouched")
	assert_eq(RefViewer.short_line("x".repeat(RefViewer.LINE_CHARS)).length(), RefViewer.LINE_CHARS, "a line exactly at the cap is not cut")
	var cut := RefViewer.short_line("x".repeat(200))
	assert_eq(cut.length(), RefViewer.LINE_CHARS, "a long line is cut to exactly LINE_CHARS including the tail")
	assert_true(cut.ends_with("..."), "the tail marks the cut")
	assert_eq(RefViewer.short_line("abcdefgh", 6), "abc...", "the cap is honoured per call")


func test_render_rows_show_file_name_and_keep_the_full_path_in_the_tooltip() -> void:
	var p = RefViewer.new()
	var target := "res://resources/items/healthpack.tres"
	var long_line := "[ext_resource type=\"Resource\" uid=\"uid://abc\" path=\"res://resources/items/healthpack.tres\" id=\"1_healthpack_with_a_long_id\"]"
	p._render(target, [
		{"file": "res://scenes/levels/Level.tscn", "lines": PackedStringArray([long_line, "slot = ExtResource(\"1\")"])},
		{"file": "res://scripts/shop.gd", "lines": PackedStringArray(["preload(\"res://resources/items/healthpack.tres\")"])},
	])
	var first: TreeItem = p._tree.get_root().get_first_child()
	assert_not_null(first, "a file row per referencing file")
	assert_eq(first.get_text(0), "Level.tscn  (2 places)", "file row = file name + how many places in it point at the target")
	assert_true(first.get_tooltip_text(0).begins_with("res://scenes/levels/Level.tscn"), "the full path lives in the tooltip")
	assert_eq(String(first.get_metadata(0)), "res://scenes/levels/Level.tscn", "metadata = the file a double-click opens")
	var line_row: TreeItem = first.get_first_child()
	assert_not_null(line_row, "the referring lines hang under their file")
	assert_lte(line_row.get_text(0).length(), RefViewer.LINE_CHARS, "a long referring line is cut for the Tree")
	assert_true(line_row.get_text(0).ends_with("..."), "...with the tail that marks the cut")
	assert_true(line_row.get_tooltip_text(0).begins_with(long_line), "the whole line stays in the tooltip")
	assert_eq(String(line_row.get_metadata(0)), "res://scenes/levels/Level.tscn", "a line row opens its file too")
	var second: TreeItem = first.get_next()
	assert_eq(second.get_text(0), "shop.gd", "a file with one referring line is just the file name")
	assert_true(p._status.text.begins_with("Found 2 files that point at healthpack.tres --"), "done grammar: <Past verb> <Name> -- <detail> -- got %s" % p._status.text)
	assert_eq(p._status.tooltip_text, p._status.text, "the tooltip mirrors the verdict")

	p._render(target, [{"file": "res://scripts/shop.gd", "lines": PackedStringArray(["preload(\"res://resources/items/healthpack.tres\")"])}])
	assert_true(p._status.text.begins_with("Found 1 file that points at healthpack.tres --"), "the singular verdict reads correctly -- got %s" % p._status.text)

	p._render(target, [])
	assert_true(p._status.text.begins_with("Found nothing that points at healthpack.tres --"), "a no-references result says so plainly -- got %s" % p._status.text)
	assert_null(p._tree.get_root().get_first_child(), "an empty result clears the rows")
	p.free()


func test_the_verdict_prints_what_the_search_actually_read() -> void:
	# The Check group's rule, applied to Refs: a clean report must say what it looked at. "Found nothing" with no
	# denominator is the failure mode -- 0 findings out of 0 files read and out of 900 files read are different
	# answers to "is it safe to delete?", and only one of them is a clean bill of health. The skipped-file clause
	# matters for the same reason: the size cap errs by MISSING references, which is the dangerous direction here.
	assert_eq(RefViewer.searched_note({}), "", "no stats handed over -> no invented denominator")
	assert_eq(RefViewer.searched_note({"read": 1, "skipped_large": []}), " Searched 1 file.", "singular")
	assert_eq(RefViewer.searched_note({"read": 903, "skipped_large": []}), " Searched 903 files.", "plural -- never a hand-rolled (s)")
	var with_skips := RefViewer.searched_note({"read": 903, "skipped_large": ["res://a.res"]})
	assert_true(with_skips.contains("1 file was too big to search"), "a skipped file is named as a hole in the answer -- got %s" % with_skips)
	assert_true(with_skips.contains("would be missed"), "...and says which direction that error runs -- got %s" % with_skips)

	var p = RefViewer.new()
	p._render("res://resources/items/healthpack.tres", [], {"read": 903, "skipped_large": []})
	assert_true(p._status.text.begins_with("Found nothing that points at healthpack.tres --"), "the verdict still leads -- got %s" % p._status.text)
	assert_true(p._status.text.contains("Searched 903 files."), "and the denominator rides with it -- got %s" % p._status.text)
	assert_eq(p._status.tooltip_text, p._status.text, "the tooltip mirrors the whole line")
	p.free()
