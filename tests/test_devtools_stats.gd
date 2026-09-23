extends GutTest

## The CYBER SUNDAY Stats dashboard: the PURE reference-collection + membership logic and the WALK POLICY (which
## folders / formats / sizes the reference walk reads) are unit-tested with in-memory text + sets, and the tab's own
## walk is driven over a throwaway user:// folder tree (never res://, which would read the whole project). The tab is
## built off-tree for its compile, layout, status and Browse-matching group names; its double-click handoff is driven
## under a stand-in panel + Refs tab; its lazy first-reveal latch and its height + width contract are driven IN the
## tree, stopping short of the real project walk.

const Stats := preload("res://addons/cybersunday_tools/dock_stats/content_stats.gd")
const StatsView := preload("res://addons/cybersunday_tools/dock_stats/stats_view.gd")
## The Browse tab's group table -- the Stats count labels must be spelled exactly as Browse spells them.
const ContentBrowser := preload("res://addons/cybersunday_tools/dock_browser/content_browser.gd")
## Masks `#` comments before the read-only lint, so a comment that NAMES what the tab never does can't trip it.
const ScanWiring := preload("res://addons/cybersunday_tools/panel_audit/scan_wiring.gd")
const STATS_VIEW_PATH := "res://addons/cybersunday_tools/dock_stats/stats_view.gd"
const CONTENT_STATS_PATH := "res://addons/cybersunday_tools/dock_stats/content_stats.gd"
## A real resource in an unused-checked folder, for a row the handoff can open (only its existence is read).
const UNUSED_FIXTURE := "res://resources/loot/sample_loot.tres"
## A throwaway folder tree the walk-policy test builds and after_each removes.
const WALK_FIXTURE := "user://__test_devtools_stats_walk"


## Stands in for cyber_panel.gd: Host.find recognises it by the two panel methods, and show_tab answers with the tab
## whose Control name was asked for -- the key the real panel's tab registry uses.
class FakePanel extends Control:
	var asked := PackedStringArray()

	func open_in_editor(_path: String) -> bool:
		return false

	func show_tab(tab_name: String) -> Control:
		asked.append(tab_name)
		return find_child(tab_name, true, false) as Control


## Stands in for the Refs tab's select_path seam: records every file it is handed and answers `accept`.
class FakeRefsTab extends Control:
	var accept := true
	var handed := PackedStringArray()

	func select_path(path: String) -> bool:
		handed.append(path)
		return accept


func after_each() -> void:
	_remove_tree(WALK_FIXTURE)


# ================================================================================================================
# PURE: reference collection + membership
# ================================================================================================================

func test_collect_referenced_pulls_paths_and_uids() -> void:
	var text := "[ext_resource type=\"Resource\" uid=\"uid://abc\" path=\"res://resources/weapons/pistol.tres\" id=\"1\"]\n" \
		+ "\tvar x = load(\"res://scripts/foo.gd\")\n\tpreload(\"res://scenes/a.tscn\")\n"
	var refs := Stats.collect_referenced(text)
	assert_true("res://resources/weapons/pistol.tres" in refs["paths"], "the ext_resource path is collected")
	assert_true("res://scripts/foo.gd" in refs["paths"], "a load() path is collected")
	assert_true("res://scenes/a.tscn" in refs["paths"], "a preload() path is collected")
	assert_true("uid://abc" in refs["uids"], "the ext_resource uid is collected")


func test_collect_referenced_ignores_resource_header_uid() -> void:
	# A .tres's OWN header uid (on a [gd_resource ...] line, not [ext_resource ...]) is a self-id, not a reference.
	var text := "[gd_resource type=\"Resource\" script_class=\"LootTable\" uid=\"uid://selfid\"]\n"
	var refs := Stats.collect_referenced(text)
	assert_false("uid://selfid" in refs["uids"], "the resource's own header uid is NOT treated as a reference")


func test_is_referenced_by_path_or_uid() -> void:
	var rp := {"res://a.tres": true}
	var ru := {"uid://x": true}
	assert_true(Stats.is_referenced("res://a.tres", "", rp, ru), "path in the set -> referenced")
	assert_true(Stats.is_referenced("res://b.tres", "uid://x", rp, ru), "uid in the set -> referenced even if the path is not")
	assert_false(Stats.is_referenced("res://c.tres", "uid://y", rp, ru), "neither path nor uid present -> not referenced (an unused candidate)")
	assert_false(Stats.is_referenced("res://c.tres", "", rp, ru), "empty uid + unreferenced path -> not referenced")


# ================================================================================================================
# PURE: the walk policy (the editor-freeze fix)
# ================================================================================================================

func test_walk_policy_skips_addons_and_derived_folders() -> void:
	# addons/ is the freeze: addons/text_to_speech/voices/ is ~59 MB of binary voice blobs, and project content never
	# lives under addons/. .godot is derived and .git is history; neither holds an authored reference.
	assert_true(Stats.skips_dir("addons"), "addons/ is never entered -- plugin code + assets, never project content")
	assert_true(Stats.skips_dir(".godot"), ".godot is derived and is never entered")
	assert_true(Stats.skips_dir(".git"), ".git is history and is never entered")
	assert_false(Stats.skips_dir("resources"), "resources/ IS walked -- it holds every content .tres")
	assert_false(Stats.skips_dir("scenes"), "scenes/ IS walked -- levels hold the QuestStarter / Talkable references")
	assert_false(Stats.skips_dir("scripts"), "scripts/ IS walked -- a load()/preload() is a reference too")


func test_walk_policy_reads_text_formats_only() -> void:
	assert_true(Stats.scans_ext("res://scenes/a.tscn"), "a scene is a scanned format")
	assert_true(Stats.scans_ext("res://resources/a.tres"), "a text resource is a scanned format")
	assert_true(Stats.scans_ext("res://scripts/a.gd"), "a script is a scanned format (load/preload references)")
	assert_true(Stats.scans_ext("res://x.res"), "a small binary resource is still read -- it can embed a path string")
	assert_true(Stats.scans_ext("res://resources/a.tres.remap"), "an exported build's .remap suffix is trimmed before the extension test")
	assert_false(Stats.scans_ext("res://x.png"), "an image is never opened")
	assert_false(Stats.scans_ext("res://scripts/a.gd.uid"), "a .gd.uid sidecar is never opened")
	assert_false(Stats.scans_ext("res://x.import"), "an .import sidecar is never opened")


func test_walk_policy_size_cap_clears_the_biggest_authored_scene() -> void:
	# THE CAP IS A CORRECTNESS KNOB, NOT A PERFORMANCE ONE. Every file the walk does not read makes the "unused
	# content" list LONGER -- a reference nobody saw is a resource this tab invites the designer to delete. The cap
	# was 512 KB, which is BELOW scenes/props/skeleton.tscn (1.59 MB), scenes/levels/trenchboom_test_level.tscn
	# (1.52 MB -- the level the game boots into) and scenes/props/billboard.tscn (0.68 MB), so anything used only by
	# one of those read as unused. It must clear the biggest authored scene and still refuse the voice blobs
	# (smallest 5.8 MB), and those two bounds are what this pins -- not the round number between them.
	assert_gte(Stats.MAX_FILE_BYTES, 2 * 1024 * 1024,
		"the cap must clear the biggest authored .tscn (1.59 MB today) -- below it, a resource used only by the live level reads as unused")
	assert_lt(Stats.MAX_FILE_BYTES, 5 * 1024 * 1024,
		"and stay under the smallest voice blob (5.8 MB), which is the freeze the cap exists to stop")
	assert_true(Stats.fits_size(0), "an empty file fits")
	assert_true(Stats.fits_size(Stats.MAX_FILE_BYTES), "exactly the cap still reads")
	assert_false(Stats.fits_size(Stats.MAX_FILE_BYTES + 1), "one byte over the cap is skipped")
	assert_true(Stats.scans_file("res://resources/loot/raider.tres", 4 * 1024), "a 4 KB loot table is read")
	assert_true(Stats.scans_file("res://scenes/levels/trenchboom_test_level.tscn", 1_600_000),
		"the 1.5 MB live level IS read -- it holds the references that keep half the content off the unused list")
	assert_false(Stats.scans_file("res://addons/text_to_speech/voices/v.res", 20 * 1024 * 1024),
		"a 20 MB voice blob is refused by SIZE even though .res is a scanned format (belt and braces with the addons skip)")
	assert_false(Stats.scans_file("res://x.png", 10), "a wrong extension is refused regardless of size")


func test_the_tab_walk_applies_the_folder_format_and_size_policy() -> void:
	# The pure policy above is only as good as the walk that applies it: a folder the walk forgets to skip is the
	# editor freeze, and a file it reads past the cap or in a binary format is a stall -- while a file it wrongly
	# skips hides a real reference and lengthens the "unused" list. Driven through the tab's own walk over a
	# throwaway tree, with one reference planted per case.
	_write(WALK_FIXTURE + "/content/uses.tres", "[ext_resource type=\"Resource\" path=\"res://fixture/kept.tres\" id=\"1\"]\n")
	_write(WALK_FIXTURE + "/content/deeper/caller.gd", "var x = load(\"res://fixture/deep.tres\")\n")
	_write(WALK_FIXTURE + "/addons/plugin/plugin_ref.tres", "[ext_resource type=\"Resource\" path=\"res://fixture/addon_only.tres\" id=\"1\"]\n")
	_write(WALK_FIXTURE + "/content/sketch.png", "path=\"res://fixture/png_only.tres\"\n")
	var at_cap := "path=\"res://fixture/at_cap.tres\"\n"
	_write(WALK_FIXTURE + "/content/at_cap.tres", at_cap + " ".repeat(Stats.MAX_FILE_BYTES - at_cap.length()))
	var over_cap := "path=\"res://fixture/over_cap_only.tres\"\n"
	_write(WALK_FIXTURE + "/content/over_cap.tres", over_cap + " ".repeat(Stats.MAX_FILE_BYTES + 1 - over_cap.length()))
	var v = StatsView.new()
	var ref_paths := {}
	var ref_uids := {}
	var read: int = v._collect(WALK_FIXTURE, ref_paths, ref_uids)
	assert_true(ref_paths.has("res://fixture/kept.tres"), "a content .tres is read and its ext_resource path counts as a reference")
	assert_true(ref_paths.has("res://fixture/deep.tres"), "the walk recurses into nested folders, and a script's load() counts")
	assert_true(ref_paths.has("res://fixture/at_cap.tres"), "a file exactly at the size cap is still read")
	assert_false(ref_paths.has("res://fixture/addon_only.tres"), "nothing under an addons/ folder is read -- the editor-freeze fix")
	assert_false(ref_paths.has("res://fixture/over_cap_only.tres"), "a file one byte over the cap is never read")
	assert_false(ref_paths.has("res://fixture/png_only.tres"), "a non-text format is never opened")
	assert_eq(read, 3, "the files-read count the status prints is exactly the three admitted files (uses.tres, caller.gd, at_cap.tres)")
	v.free()


# ================================================================================================================
# THE TAB -- constructed off-tree; the handlers (EditorInterface) are never exercised here
# ================================================================================================================

func test_stats_view_constructs() -> void:
	var v = StatsView.new()
	assert_not_null(v, "the Stats tab constructs (compiles + _init builds UI off-tree)")
	assert_eq(v.name, "Stats")
	assert_false(v._revealed, "off-tree construction is not a reveal, so no project walk ran")
	assert_false(v._scanning, "nothing is scanning after a bare construction")
	assert_eq(v._scan_btn.text, "Scan", "the one verb for a read-only report is Scan (never Refresh / Reload)")
	assert_false(v._scan_btn.disabled, "Scan is enabled at rest -- it needs no open scene and no selection")
	assert_true(v._scan_btn.tooltip_text.ends_with("Read-only."), "the action tooltip ends by saying what it writes: nothing")
	v.free()


func test_stats_view_status_contract() -> void:
	var v = StatsView.new()
	assert_eq(v._status.text, StatsView.MSG_IDLE, "idle status is one imperative next step, not a blank line")
	assert_true(v._status.text.begins_with("Press Scan"), "the idle line names the button")
	assert_eq(v._status.tooltip_text, v._status.text, "the status tooltip mirrors the text from the first write")
	var resting_modulate: Color = v._status.modulate
	v._set_status(StatsView.MSG_SUSPECT, true)
	assert_eq(v._status.tooltip_text, StatsView.MSG_SUSPECT, "EVERY write mirrors onto the tooltip -- the clamped label shows two lines, the tooltip the rest")
	assert_true(v._status.has_theme_color_override("font_color"), "a warning is tinted through a theme colour override")
	assert_eq(v._status.modulate, resting_modulate, "…and keeps the modulate the status rests at")
	v._set_status(StatsView.MSG_IDLE)
	assert_false(v._status.has_theme_color_override("font_color"), "a plain write clears the warning tint")
	v.free()


func test_stats_view_layout_is_head_status_then_scrolled_body() -> void:
	# Head / ONE status / ScrollContainer, in that order, with the Tree INSIDE the scroll. The status is its own
	# full-width row -- not wedged beside the button -- and no Label repeats the tab name as a heading.
	var v = StatsView.new()
	assert_eq(v.get_child_count(), 3, "exactly three rows: button bar, status, scrolled body")
	assert_true(v.get_child(0) is HBoxContainer, "row 0 is the button bar")
	assert_true(v.get_child(1) is Label, "row 1 is the status, on its own full-width row")
	var scroll := v.get_child(2) as ScrollContainer
	assert_not_null(scroll, "row 2 is the ScrollContainer that fences the body height")
	if scroll != null:
		assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "a long row must never widen the bottom panel")
		assert_eq(scroll.custom_minimum_size.y, StatsView.BODY_MIN_HEIGHT, "the scrolled body carries the tab's body floor")
		assert_true(scroll.custom_minimum_size.y <= 120.0, "the body floor stays under the bottom panel's shared 120 px ceiling (test_devtools_layout TALL_FLOOR; reach / refs / saves hold their tabs to it) -- a tall floor leaves the panel tall for every tab after it")
		assert_true(StatsView.TREE_MIN_HEIGHT > 0.0, "the file list keeps a visible floor, so an empty or short scan result never collapses to a zero-height strip")
		assert_eq(scroll.get_child_count(), 1, "the scroll holds exactly the Tree")
		assert_true(scroll.get_child(0) is Tree, "the Tree lives INSIDE the scroll")
		var tree := scroll.get_child(0) as Tree
		if tree != null:
			assert_true(tree.custom_minimum_size.y <= scroll.custom_minimum_size.y, "the Tree's own floor fits inside the body floor, so the outer scroll never engages")
	for c in v.get_children():
		if c is Label:
			assert_ne((c as Label).text, "Stats", "no heading Label repeats the tab name")
	v.free()


func test_stats_view_status_text_leads_with_files_read() -> void:
	# The done line is a pure formatter: the files-read DENOMINATOR first (so a walk that read nothing can never pass
	# for a clean project), then the counts, then the one next step -- which names the Refs tab.
	var v = StatsView.new()
	var line: String = v._status_text(212, 3, 1204)
	assert_true(line.begins_with("Scanned 1204 files"), "the files-read denominator leads: %s" % line)
	assert_true(line.contains("212 content files"), "the content total follows: %s" % line)
	assert_true(line.contains("3 unused candidates"), "the unused count is named as candidates, never a verdict: %s" % line)
	assert_true(line.contains("Refs"), "the next step names the Refs tab: %s" % line)
	var one: String = v._status_text(1, 1, 1)
	assert_true(one.contains("1 file --") and one.contains("1 content file") and one.contains("1 unused candidate."),
		"real singulars, never a hand-rolled (s): %s" % one)
	var clean: String = v._status_text(212, 0, 1204)
	assert_true(clean.contains("nothing unused"), "zero candidates reads as nothing unused: %s" % clean)
	assert_true(clean.contains("Items and factions"), "the clean line says which types are never listed (they load by folder): %s" % clean)
	assert_false(v._is_suspect(1204), "a walk that read files is evidence")
	assert_true(v._is_suspect(0), "a walk that read nothing is a scan problem, not a clean project")
	assert_true(StatsView.MSG_SUSPECT.begins_with("Scan incomplete"), "the suspect line leads with the verdict token phrase")
	v.free()


func test_count_groups_use_the_browse_tab_spellings() -> void:
	# One vocabulary across the Check and Create groups: every Stats count label is a Browse group, spelled the same
	# and counting the same folder. The two that used to differ are pinned by name.
	var roots: Dictionary = ContentBrowser.ROOTS
	assert_gt(StatsView.COUNT_DIRS.size(), 0, "there are count groups")
	for label in StatsView.COUNT_DIRS:
		var l := String(label)
		assert_true(roots.has(l), "Stats group '%s' must be spelled exactly as the Browse tab spells it" % l)
		if roots.has(l):
			assert_eq(String(StatsView.COUNT_DIRS[label]), String(roots[l]), "and count the same folder Browse lists for '%s'" % l)
	assert_true(StatsView.COUNT_DIRS.has("Loot Tables"), "'Loot Tables' (Browse), not 'Loot'")
	assert_true(StatsView.COUNT_DIRS.has("Status Effects"), "'Status Effects' (Browse), not 'Status'")
	assert_false(StatsView.COUNT_DIRS.has("Loot"), "the old 'Loot' spelling is gone")
	assert_false(StatsView.COUNT_DIRS.has("Status"), "the old 'Status' spelling is gone")


func test_stats_view_minimum_size_does_not_grow_with_rows_or_a_long_status() -> void:
	# A TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom splitter keeps whatever size it
	# grew to -- so a tall or wide tab, once shown, deforms the panel for every tab after it. Measured IN the tree (an
	# off-tree Control never recomputes its minimum). The first-reveal walk reads the whole project, so the latch is
	# closed by hand first: this test is about layout, and the latch has its own test below.
	var v = StatsView.new()
	v._revealed = true
	add_child_autofree(v)
	await wait_process_frames(2)
	var idle_min: Vector2 = v.get_combined_minimum_size()
	var idle_status_min: Vector2 = v._status.get_combined_minimum_size()
	var root: TreeItem = v._tree.create_item()
	var head: TreeItem = v._row(root, "%s: 400" % StatsView.UNUSED_LABEL, StatsView.COLOR_WARN)
	for i in 400:
		v._row(head, "unused_%03d_%s.tres" % [i, "z".repeat(120)], StatsView.COLOR_WARN, "res://resources/loot/unused_%03d.tres" % i)
	var verdict: String = StatsView.MSG_SUSPECT + " " + v._status_text(4321, 400, 0) + " " + "w".repeat(200)
	v._set_status(verdict, true)
	await wait_process_frames(2)
	assert_eq(head.get_child_count(), 400, "precondition: 400 long rows are painted")
	assert_eq(v.get_combined_minimum_size(), idle_min, "400 long rows and a long warning leave the tab's minimum size unchanged")
	assert_eq(v._status.get_combined_minimum_size(), idle_status_min, "the status row in particular stays the height it rests at")
	# Controls: the same verdict in a plain Label would have outgrown the tab, and wrapped at the status's own width
	# without the two-line clamp it would be taller -- so the equalities above are held by the tab, not by a short line.
	var unwrapped := Label.new()
	unwrapped.text = verdict
	add_child_autofree(unwrapped)
	var unclamped := Label.new()
	unclamped.autowrap_mode = v._status.autowrap_mode
	unclamped.custom_minimum_size = Vector2(v._status.size.x, 0)
	unclamped.text = verdict
	add_child_autofree(unclamped)
	await wait_process_frames(2)
	assert_gt(unwrapped.get_combined_minimum_size().x, idle_min.x, "control: unwrapped, this warning is wider than the whole idle tab")
	assert_gt(unclamped.get_combined_minimum_size().y, idle_status_min.y, "control: wrapped but unclamped, this warning is taller than the status row")


func test_double_click_on_an_unused_row_hands_that_file_to_refs_once() -> void:
	var h := _stats_in_panel()
	var v = h["view"]
	var panel: FakePanel = h["panel"]
	var refs: FakeRefsTab = h["refs"]
	var file_row: TreeItem = h["file_row"]
	file_row.select(0)
	v._tree.item_activated.emit()
	assert_eq(panel.asked, PackedStringArray(["Refs"]), "one double-click asks the panel for exactly one tab switch, reached through the host lookup from two levels down")
	assert_eq(refs.handed, PackedStringArray([UNUSED_FIXTURE]), "the Refs tab is handed that row's full res:// path, once")
	assert_false(v._status.has_theme_color_override("font_color"), "an accepted handoff is not a warning")
	# The words the designer reads point where the double-click actually goes. Checked by the file name and the tab
	# name (both stable keys), not the sentence around them, so a copy pass can reword it freely.
	var tab := panel.asked[0]
	assert_true(v._status.text.contains(UNUSED_FIXTURE.get_file()), "the status names the file that was handed over: %s" % v._status.text)
	assert_true(v._status.text.contains(tab), "the status names the tab the file opened in, not the Inspector: %s" % v._status.text)
	assert_true(StatsView.UNUSED_LABEL.contains(tab), "the section header tells the designer to check with the tab the double-click opens")
	assert_true(file_row.get_tooltip_text(0).contains(tab), "the row's hover hint names that tab too")
	assert_true(file_row.get_tooltip_text(0).contains(UNUSED_FIXTURE), "and carries the full path the handoff sends")


func test_a_refs_tab_that_refuses_the_file_keeps_the_designer_on_refs() -> void:
	# ONE jump per double-click: once the panel has switched to Refs, a refusal there (a reimport in flight, a search
	# already running) must not fall through to the Inspector as a second, unasked-for jump.
	var h := _stats_in_panel()
	var v = h["view"]
	var panel: FakePanel = h["panel"]
	var refs: FakeRefsTab = h["refs"]
	refs.accept = false
	(h["file_row"] as TreeItem).select(0)
	v._tree.item_activated.emit()
	assert_eq(refs.handed, PackedStringArray([UNUSED_FIXTURE]), "Refs was offered the file")
	assert_eq(panel.asked.size(), 1, "and no second tab switch followed its refusal")
	assert_true(v._status.text.begins_with("Couldn't check sample_loot.tres in Refs yet"), "the status points back at Refs' own reason: %s" % v._status.text)
	assert_false(v._status.text.contains("Inspector"), "the Inspector fallback did not run after Refs answered")
	assert_true(v._status.has_theme_color_override("font_color"), "the refusal is tinted as a warning")


func test_rows_that_name_no_existing_file_never_reach_refs() -> void:
	var h := _stats_in_panel()
	var v = h["view"]
	var panel: FakePanel = h["panel"]
	var refs: FakeRefsTab = h["refs"]
	var head: TreeItem = h["head"]
	v._tree.item_activated.emit()
	assert_eq(v._status.text, StatsView.MSG_IDLE, "a double-click with no row selected does nothing")
	(h["count_row"] as TreeItem).select(0)
	v._tree.item_activated.emit()
	head.select(0)
	v._tree.item_activated.emit()
	var outside: TreeItem = v._row(head, "notes.tres", StatsView.COLOR_WARN, "user://notes.tres")
	outside.select(0)
	v._tree.item_activated.emit()
	assert_eq(panel.asked.size(), 0, "a count row, a section header and a non-res:// row ask for no tab switch")
	assert_eq(v._status.text, StatsView.MSG_IDLE, "…and leave the status alone")
	var gone: TreeItem = v._row(head, "deleted_since_scan.tres", StatsView.COLOR_WARN, "res://resources/loot/__deleted_since_scan.tres")
	gone.select(0)
	v._tree.item_activated.emit()
	assert_eq(panel.asked.size(), 0, "a row whose file is gone since the scan never reaches Refs")
	assert_true(v._status.text.contains("__deleted_since_scan.tres"), "the refusal names the file that is gone: %s" % v._status.text)
	assert_false(v._status.text.contains("Refs"), "…and does not claim it opened in Refs: %s" % v._status.text)
	assert_true(v._status.has_theme_color_override("font_color"), "as a tinted warning")
	# Control: an existing file's row in the same tab DOES reach Refs, so the quiet cases above are the guards.
	(h["file_row"] as TreeItem).select(0)
	v._tree.item_activated.emit()
	assert_eq(refs.handed, PackedStringArray([UNUSED_FIXTURE]), "control: a row for an existing file is handed over")


func test_stats_view_walks_the_project_only_on_its_first_reveal() -> void:
	# cyber_panel builds every tab on each plugin reload; a Stats tab that walked res:// at construction or on every
	# re-show would stall the editor for a tab nobody clicked. The walk itself reads the whole project, so this test
	# stops short of it: a scan announces itself ("Scanning...", Scan greyed) and yields one frame before walking, and
	# the view is freed before that frame -- freeing an object cancels its pending await.
	var v = StatsView.new()
	assert_eq(v._status.text, StatsView.MSG_IDLE, "construction starts no scan")
	v.visible = false
	add_child(v)
	assert_false(v._revealed, "entering the tree hidden is not a reveal")
	assert_eq(v._status.text, StatsView.MSG_IDLE, "…so no scan started")
	v.show()
	assert_true(v._revealed, "the first time the tab is SHOWN the latch closes")
	assert_eq(v._status.text, StatsView.MSG_SCANNING, "…and a scan starts, announcing itself first")
	assert_true(v._scan_btn.disabled, "…with Scan greyed while it runs")
	# Stand in for that walk finishing, so the next reveal is judged by the latch alone.
	v._scanning = false
	v._scan_btn.disabled = false
	v._set_status("first scan done")
	v.hide()
	v.show()
	assert_eq(v._status.text, "first scan done", "showing the tab again does not walk the project again")
	assert_false(v._scanning, "…and leaves no scan pending")
	# Control: the same tab still scans on demand, so the quiet re-show above is the latch, not a tab that can't scan.
	v._scan_btn.pressed.emit()
	assert_eq(v._status.text, StatsView.MSG_SCANNING, "control: Scan starts a walk whenever the designer asks")
	remove_child(v)
	v.free()  # before the yield resumes: the pending walks are cancelled with the object
	# Let the frames the two pending scans were waiting on go by INSIDE this test, so a scan that resumed on a freed
	# tab would raise its error here rather than in whichever test runs next.
	await wait_process_frames(2)
	assert_engine_error_count(0, "freeing the tab mid-yield cancels its pending scans without an error")


func test_stats_tab_writes_nothing() -> void:
	# Read-only means read-only (QA Global Gate: Stats is on that list). Neither file may save a resource or open a
	# file for writing; the tab reads and paints.
	for path in [STATS_VIEW_PATH, CONTENT_STATS_PATH]:
		var src := ScanWiring._mask_comments(FileAccess.get_file_as_string(String(path)))
		assert_ne(src, "", "source should be readable: %s" % String(path))
		assert_false(src.contains("ResourceSaver"), "%s never saves a resource" % String(path))
		assert_false(src.contains("FileAccess.WRITE"), "%s never opens a file for writing" % String(path))


# ================================================================================================================
# helpers
# ================================================================================================================

## A Stats tab nested two levels under a stand-in panel (the job-group depth), beside a Refs tab, with a counts
## section and one unused-content row for UNUSED_FIXTURE painted through the tab's own row builder. The panel is
## autofreed, which frees every tab under it.
func _stats_in_panel() -> Dictionary:
	var panel := FakePanel.new()
	autofree(panel)
	var group := Control.new()
	group.name = "Check"
	panel.add_child(group)
	var refs := FakeRefsTab.new()
	refs.name = "Refs"
	group.add_child(refs)
	var v = StatsView.new()
	group.add_child(v)
	var root: TreeItem = v._tree.create_item()
	var counts: TreeItem = v._row(root, StatsView.COUNTS_LABEL, StatsView.COLOR_HEAD)
	var count_row: TreeItem = v._row(counts, "Loot Tables: 1")
	var head: TreeItem = v._row(root, "%s: 1" % StatsView.UNUSED_LABEL, StatsView.COLOR_WARN)
	var file_row: TreeItem = v._row(head, UNUSED_FIXTURE.get_file(), StatsView.COLOR_WARN, UNUSED_FIXTURE)
	return {"panel": panel, "refs": refs, "view": v, "count_row": count_row, "head": head, "file_row": file_row}


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_true(f != null, "fixture file should be writable at %s" % path)
	if f == null:
		return
	f.store_string(text)
	f.close()


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
