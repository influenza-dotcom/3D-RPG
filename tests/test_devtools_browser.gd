extends GutTest

## Unified Content Browser (plugin "Browse" tab) -- exercises the PURE browse_scan.gd helper: the search filter (over
## in-memory fixtures, no disk) and the grouped scan (against the real resources/* tree). EditorInterface /
## edit_resource / select_file is editor-only and is NOT exercised here (it can't run headless).
##
## The @tool Control IS constructed at the bottom now: every widget is built in _init (nothing waits on a live tree)
## and the editor wiring sits behind Engine.is_editor_hint(), so .new() is safe headless. That buys the ROOTS test --
## the one thing this tab can silently get wrong is listing FEWER folders than the generators write to, and a
## designer then cannot find the file they just made in the one tab whose whole job is "find any content file".

const Browse := preload("res://addons/cybersunday_tools/dock_browser/browse_scan.gd")
const ContentBrowser := preload("res://addons/cybersunday_tools/dock_browser/content_browser.gd")
const CONTENT_DOCK_PATH := "res://addons/cybersunday_tools/dock_content/content_dock.gd"


# --- filter_paths: pure, disk-free ----------------------------------------------------------------------------

func test_filter_empty_needle_returns_all() -> void:
	var paths: Array[String] = ["res://resources/items/medkit.tres", "res://resources/weapons/pistol.tres"]
	var got := Browse.filter_paths(paths, "")
	assert_eq(got.size(), 2, "an empty needle keeps every path; got %s" % str(got))


func test_filter_blank_needle_returns_all() -> void:
	var paths: Array[String] = ["res://a/x.tres", "res://b/y.tres"]
	var got := Browse.filter_paths(paths, "   ")
	assert_eq(got.size(), 2, "a whitespace-only needle is treated as empty; got %s" % str(got))


func test_filter_matches_on_basename() -> void:
	var paths: Array[String] = [
		"res://resources/weapons/pistol.tres",
		"res://resources/weapons/rifle.tres",
		"res://resources/items/ammo_pistol.tres",
	]
	var got := Browse.filter_paths(paths, "pistol")
	assert_eq(got.size(), 2, "'pistol' matches both the weapon and the ammo item; got %s" % str(got))
	assert_true(got.has("res://resources/weapons/pistol.tres"), "the pistol weapon is kept")
	assert_true(got.has("res://resources/items/ammo_pistol.tres"), "the pistol ammo is kept")


func test_filter_is_case_insensitive() -> void:
	var paths: Array[String] = ["res://resources/factions/Raiders.tres"]
	var got := Browse.filter_paths(paths, "raid")
	assert_eq(got.size(), 1, "case-insensitive substring match keeps Raiders.tres for 'raid'; got %s" % str(got))


func test_filter_matches_on_folder_segment() -> void:
	var paths: Array[String] = [
		"res://resources/weapons/pistol.tres",
		"res://resources/items/medkit.tres",
	]
	var got := Browse.filter_paths(paths, "weapons")
	assert_eq(got.size(), 1, "the needle also matches a folder segment of the full path; got %s" % str(got))
	assert_eq(got[0], "res://resources/weapons/pistol.tres", "only the weapons path is kept")


func test_filter_no_match_returns_empty() -> void:
	var paths: Array[String] = ["res://resources/items/medkit.tres"]
	var got := Browse.filter_paths(paths, "zzz_nonexistent")
	assert_eq(got.size(), 0, "a needle that matches nothing yields an empty list; got %s" % str(got))


# --- filter_grouped: pure, disk-free --------------------------------------------------------------------------

func test_filter_grouped_drops_empty_groups() -> void:
	var grouped: Dictionary = {
		"Weapons": ["res://resources/weapons/pistol.tres"],
		"Items": ["res://resources/items/medkit.tres"],
	}
	var got := Browse.filter_grouped(grouped, "pistol")
	assert_true(got.has("Weapons"), "the matching group is kept")
	assert_false(got.has("Items"), "a group with no matches is dropped from the filtered view")
	assert_eq((got["Weapons"] as Array).size(), 1, "the kept group carries only its matching path")


func test_filter_grouped_empty_needle_keeps_all_groups() -> void:
	var grouped: Dictionary = {
		"Weapons": ["res://resources/weapons/pistol.tres"],
		"Items": [],
	}
	var got := Browse.filter_grouped(grouped, "")
	# An empty needle keeps every NON-EMPTY group (filter_paths returns all, but a group that is already empty stays out).
	assert_true(got.has("Weapons"), "non-empty group survives an empty needle")
	assert_false(got.has("Items"), "an already-empty group has nothing to keep even with an empty needle")


# --- scan_folder / scan_grouped: real disk --------------------------------------------------------------------

func test_scan_folder_missing_returns_empty() -> void:
	var got := Browse.scan_folder("res://resources/__definitely_not_a_folder__/")
	assert_eq(got.size(), 0, "scanning a missing folder yields [] (no crash); got %s" % str(got))


func test_scan_folder_returns_sorted_tres_only() -> void:
	# resources/weapons/ has real .tres AND a non-resource (Secret Shop.flac) that must be filtered out.
	var got := Browse.scan_folder("res://resources/weapons/")
	assert_gt(got.size(), 0, "resources/weapons/ should yield at least one .tres")
	for p in got:
		assert_true(p.ends_with(".tres") or p.ends_with(".res"), "every scanned path is a resource file: %s" % p)
		assert_true(FileAccess.file_exists(p), "the scanned path exists on disk: %s" % p)
	# sorted ascending
	var sorted_copy := got.duplicate()
	sorted_copy.sort()
	assert_eq(got, sorted_copy, "scan_folder returns paths sorted ascending")


func test_scan_grouped_preserves_all_group_keys() -> void:
	var roots := {
		"Weapons": "res://resources/weapons/",
		"Missing": "res://resources/__definitely_not_a_folder__/",
	}
	var got := Browse.scan_grouped(roots)
	assert_true(got.has("Weapons"), "scan_grouped keeps the Weapons key")
	assert_true(got.has("Missing"), "scan_grouped keeps an empty/missing group's key (so the Tree can show it)")
	assert_gt((got["Weapons"] as Array).size(), 0, "Weapons resolves to real .tres")
	assert_eq((got["Missing"] as Array).size(), 0, "an empty/absent folder resolves to []")


func test_scan_grouped_finds_known_resource() -> void:
	var roots := { "Factions": "res://resources/factions/" }
	var got := Browse.scan_grouped(roots)
	var paths: Array = got.get("Factions", [])
	var has_raiders := false
	for p in paths:
		if String(p).ends_with("raiders.tres"):
			has_raiders = true
	assert_true(has_raiders, "the grouped scan finds resources/factions/raiders.tres; got %s" % str(paths))


func test_status_effects_scan_uses_status_folder() -> void:
	var got := Browse.scan_folder("res://resources/status/")
	assert_true(got.has("res://resources/status/poison.tres"), "StatusEffects should scan the canonical status folder")
	assert_true(got.has("res://resources/status/adrenaline.tres"), "StatusEffects should include shipped samples")


func test_maps_scan_is_dedicated_to_map_data() -> void:
	var got := Browse.scan_folder("res://resources/maps/")
	assert_true(got.has("res://resources/maps/sample_map.tres"), "Maps should scan the dedicated maps folder")
	for path in got:
		assert_true(load(path) is MapData, "every resource in resources/maps should be MapData: %s" % path)


# --- the tab itself -------------------------------------------------------------------------------------------

## Browse must list EVERY folder the New tab writes into. content_dock names its targets as `*_DIR` constants, so
## read them straight off that script instead of re-typing the list here: a NEW generator pointed at a new folder
## then fails THIS test until Browse grows a group for it, rather than quietly going missing from the browser.
func test_browse_roots_cover_every_generator_folder() -> void:
	var listed: Array = []
	var roots: Dictionary = ContentBrowser.ROOTS
	for label in roots:
		listed.append(String(roots[label]))
	var checked := 0
	# load()ed into a GDScript VALUE, not used as a class name: get_script_constant_map() is an instance method of
	# Script, and calling it on a const-preloaded script identifier reads as a static call on the class.
	var dock_script: GDScript = load(CONTENT_DOCK_PATH)
	assert_not_null(dock_script, "the New tab's script should load")
	var consts: Dictionary = dock_script.get_script_constant_map()
	for key in consts:
		if not String(key).ends_with("_DIR"):
			continue
		var folder: Variant = consts[key]
		if not (folder is String):
			continue
		checked += 1
		assert_true(listed.has(String(folder)),
			"Browse's ROOTS must list the New tab's %s (%s); it lists %s" % [key, folder, str(listed)])
	assert_gt(checked, 10, "the New tab's folder constants should have been found (matched %d of them)" % checked)


## The tab constructs off-tree (GUT and the plugin's headless probe both do exactly this) under its pinned Control
## name, and the host seam refuses cleanly. select_path is what cyber_panel.open_in_editor calls, so a crash -- or a
## stray true for a file that is in no group -- would break the Blueprints / New "open it over there" handoff.
func test_content_browser_constructs_and_refuses_paths_it_cannot_show() -> void:
	var v = ContentBrowser.new()
	assert_not_null(v, "the Browse tab constructs (compiles + _init builds every widget off-tree)")
	assert_eq(v.name, "Browse", "the Control name is pinned -- cyber_panel paints the title and routes by this name")
	assert_false(v.select_path(""), "a blank path is refused without starting a disk walk")
	assert_false(v.select_path("res://resources/quests/zzz_not_a_real_quest.tres"),
		"a file that is in no group is refused (the caller then opens the Inspector itself)")
	v.free()
