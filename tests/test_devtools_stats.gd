extends GutTest

## The CYBER SUNDAY Stats dashboard: the PURE reference-collection + membership logic and the WALK POLICY (which
## folders / formats / sizes the reference walk reads) are unit-tested with in-memory text + sets; the project walk
## + counts are editor-verified (they read the disk). The tab itself is constructed OFF-TREE (.new(), never
## add_child) to pin its compile, its head / status / scrolled-body layout, its status contract, its lazy first-reveal
## latch, its Browse-matching group names and its Refs handoff -- each a structural fact a future edit could silently
## break without any test going red.

const Stats := preload("res://addons/cybersunday_tools/dock_stats/content_stats.gd")
const StatsView := preload("res://addons/cybersunday_tools/dock_stats/stats_view.gd")
## The Browse tab's group table -- the Stats count labels must be spelled exactly as Browse spells them.
const ContentBrowser := preload("res://addons/cybersunday_tools/dock_browser/content_browser.gd")
const STATS_VIEW_PATH := "res://addons/cybersunday_tools/dock_stats/stats_view.gd"
const CONTENT_STATS_PATH := "res://addons/cybersunday_tools/dock_stats/content_stats.gd"


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
	assert_eq(v._status.max_lines_visible, 2, "the status Label is clamped to two lines (the tooltip carries the rest)")
	assert_eq(v._status.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the status autowraps by word")
	assert_almost_eq(v._status.modulate.a, 0.75, 0.01, "the status sits at the panel-wide 0.75 alpha")
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
		assert_gte(scroll.custom_minimum_size.y, 90.0, "the body floor is at least 90 px")
		assert_lte(scroll.custom_minimum_size.y, 110.0, "the body floor is at most 110 px (a tall tab leaves the panel tall for every tab after it)")
		assert_eq(scroll.get_child_count(), 1, "the scroll holds exactly the Tree")
		assert_true(scroll.get_child(0) is Tree, "the Tree lives INSIDE the scroll")
		var tree := scroll.get_child(0) as Tree
		if tree != null:
			assert_lte(tree.custom_minimum_size.y, 120.0, "no list floor above 120 px")
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


func test_unused_rows_hand_off_to_refs() -> void:
	assert_eq(StatsView.UNUSED_LABEL, "Unused content (candidates -- check with Refs before deleting)",
		"the section header says candidate, not verdict, and names the tab that checks it")
	assert_true(StatsView.ROW_TIP_HINT.contains("Refs"), "the row tooltip's double-click hint names the Refs tab")
	var src := FileAccess.get_file_as_string(STATS_VIEW_PATH)
	assert_ne(src, "", "stats_view.gd source should be readable")
	assert_true(src.contains("Host.show_tab(self, \"Refs\")"), "double-click hands the file to the Refs tab through core/host.gd, never a get_parent() chain")
	assert_true(src.contains("has_method(\"select_path\")"), "and asks for the select_path seam before calling it (duck-typed; the Inspector is the fallback)")
	assert_true(src.contains("EditorInterface.edit_resource"), "the older open-in-Inspector path survives as the fallback")


func test_stats_view_is_lazy_on_first_reveal() -> void:
	# The same source-scan tests/test_devtools_lazy_reveal.gd runs over its LAZY_DOCKS list; Stats is not in that
	# list, so its latch is pinned here. A Stats tab that scanned at construction would fan a full res:// walk out of
	# every plugin reload for a tab nobody clicked.
	var src := FileAccess.get_file_as_string(STATS_VIEW_PATH)
	assert_ne(src, "", "stats_view.gd source should be readable")
	assert_true(src.contains("var _revealed"), "declares a _revealed first-reveal latch")
	assert_true(src.contains("visibility_changed.connect(_on_visibility_changed)"), "connects visibility_changed to the lazy handler")
	assert_true(src.contains("func _on_visibility_changed"), "defines _on_visibility_changed")
	assert_true(src.contains("is_visible_in_tree() and not _revealed"), "guards the scan on the first in-tree reveal")
	assert_true(src.contains("_revealed = true"), "latches _revealed = true so the scan runs only once")
	assert_true(src.contains("Stats.skips_dir("), "the walk applies the pure skip policy (the addons/ freeze fix)")
	assert_true(src.contains("Stats.fits_size("), "the walk applies the pure size cap BEFORE reading a file")


func test_stats_tab_writes_nothing() -> void:
	# Read-only means read-only (QA Global Gate: Stats is on that list). Neither file may save a resource or open a
	# file for writing; the tab reads and paints.
	for path in [STATS_VIEW_PATH, CONTENT_STATS_PATH]:
		var src := FileAccess.get_file_as_string(String(path))
		assert_ne(src, "", "source should be readable: %s" % String(path))
		assert_false(src.contains("ResourceSaver"), "%s never saves a resource" % String(path))
		assert_false(src.contains("FileAccess.WRITE"), "%s never opens a file for writing" % String(path))
