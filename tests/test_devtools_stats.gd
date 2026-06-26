extends GutTest

## The CYBER SUNDAY Stats dashboard: the PURE reference-collection + membership logic is unit-tested with in-memory
## text + sets; the project walk + counts are editor-verified (they read the disk). Construct check confirms the tab
## compiles off-tree.

const Stats := preload("res://addons/cybersunday_tools/dock_stats/content_stats.gd")
const StatsView := preload("res://addons/cybersunday_tools/dock_stats/stats_view.gd")


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
	assert_false(Stats.is_referenced("res://c.tres", "uid://y", rp, ru), "neither path nor uid present -> not referenced (a straggler)")
	assert_false(Stats.is_referenced("res://c.tres", "", rp, ru), "empty uid + unreferenced path -> not referenced")


func test_stats_view_constructs() -> void:
	var v = StatsView.new()
	assert_not_null(v, "the Stats tab constructs (compiles + _init builds UI off-tree)")
	assert_eq(v.name, "Stats")
	v.free()
