extends GutTest

## Unified Content Browser (plugin "Browse" tab) -- exercises the PURE browse_scan.gd helper: the search filter (over
## in-memory fixtures, no disk) and the grouped scan (against the real resources/* tree). EditorInterface / edit_resource
## / select_file is editor-only and is NOT exercised here (it can't run headless). The @tool Control itself isn't
## instantiated (its _ready builds widgets that want a live tree); the logic under test is all in browse_scan.

const Browse := preload("res://addons/cybersunday_tools/dock_browser/browse_scan.gd")


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
		"Quests": "res://resources/quests/",  # empty / may not exist on disk
	}
	var got := Browse.scan_grouped(roots)
	assert_true(got.has("Weapons"), "scan_grouped keeps the Weapons key")
	assert_true(got.has("Quests"), "scan_grouped keeps an empty group's key (so the Tree can show it)")
	assert_gt((got["Weapons"] as Array).size(), 0, "Weapons resolves to real .tres")
	assert_eq((got["Quests"] as Array).size(), 0, "an empty/absent folder resolves to []")


func test_scan_grouped_finds_known_resource() -> void:
	var roots := { "Factions": "res://resources/factions/" }
	var got := Browse.scan_grouped(roots)
	var paths: Array = got.get("Factions", [])
	var has_raiders := false
	for p in paths:
		if String(p).ends_with("raiders.tres"):
			has_raiders = true
	assert_true(has_raiders, "the grouped scan finds resources/factions/raiders.tres; got %s" % str(paths))
