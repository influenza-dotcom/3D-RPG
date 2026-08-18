extends GutTest

## The CYBER SUNDAY Encounter tab: the read-only EncounterSpawner preview. The PURE model (scaled_count / summarize)
## is tested off-tree; scaled_count is pinned against EncounterSpawner._scaled_count's formula so the preview can't
## drift from runtime. The spawner is built with .new() WITHOUT add_child (no _ready), per the no-_ready test rule.

const Preview := preload("res://addons/cybersunday_tools/dock_encounter/encounter_preview.gd")
const EncounterView := preload("res://addons/cybersunday_tools/dock_encounter/encounter_view.gd")


func _def(count: int, radius := 2.0, delay := 0.0) -> SpawnDefinition:
	var d := SpawnDefinition.new()
	d.count = count
	d.spawn_radius = radius
	d.spawn_delay = delay
	d.npc_scene = PackedScene.new()  # a real (if empty) scene so the def actually spawns -> counts toward the total
	return d


func test_scaled_count_mirrors_runtime_formula() -> void:
	# Mirrors EncounterSpawner._scaled_count: base<=0 -> 0; else maxi(1, roundi(base*mult)).
	assert_eq(Preview.scaled_count(0, 2.0), 0, "zero base -> zero (not floored to 1)")
	assert_eq(Preview.scaled_count(4, 1.0), 4, "Normal (x1.0) is the authored count")
	assert_eq(Preview.scaled_count(4, 1.5), 6, "x1.5 rounds 6.0 -> 6")
	assert_eq(Preview.scaled_count(3, 1.5), 5, "x1.5 rounds 4.5 -> 5 (half away from zero)")
	assert_eq(Preview.scaled_count(1, 0.1), 1, "a hit always yields at least 1 (floor)")


func test_summarize_totals_rows_and_placement() -> void:
	var sp := EncounterSpawner.new()  # off-tree, no _ready
	sp.spawn_definitions = [_def(2), _def(3, 4.0, 0.5)]
	var s := Preview.summarize(sp)
	assert_eq(int(s["total"]), 5, "authored total = 2 + 3")
	assert_eq((s["rows"] as Array).size(), 2, "one row per definition")
	assert_eq(String(s["placement"]), "random scatter (per-definition radius)", "no markers -> scatter")
	assert_eq(float((s["rows"] as Array)[1]["delay"]), 0.5, "the second wave's stagger is reported")
	sp.free()


func test_summarize_handles_null_def_and_markers() -> void:
	var sp := EncounterSpawner.new()
	sp.spawn_definitions = [_def(2), null]  # a null definition must surface as a row, not crash
	sp.spawn_points = [NodePath("Marker1"), NodePath("Marker2")]
	var s := Preview.summarize(sp)
	assert_eq((s["rows"] as Array).size(), 2, "the null definition still gets a row")
	assert_eq(int(s["total"]), 2, "the null definition contributes no count")
	assert_eq(int(s["marker_count"]), 2, "spawn_points are counted")
	assert_true(String(s["placement"]).contains("markers (2"), "markers drive placement when present")
	sp.free()


func test_summarize_total_excludes_npc_scene_less_definitions() -> void:
	# Runtime (EncounterSpawner.trigger_spawn_wave) returns early on a null npc_scene, spawning ZERO — so a
	# definition with no npc_scene must NOT inflate the preview total, even though its row stays visible (flagged).
	var sp := EncounterSpawner.new()
	var no_scene := _def(2)
	no_scene.npc_scene = null  # clear it -> runtime would skip this definition (spawns 0)
	var real := _def(3)  # _def gives it a real scene
	sp.spawn_definitions = [no_scene, real]
	var s := Preview.summarize(sp)
	assert_eq(int(s["total"]), 3, "the no-npc_scene definition spawns nothing at runtime, so it's excluded from the total")
	assert_eq((s["rows"] as Array).size(), 2, "both definitions still get a row (the no-scene one is flagged)")
	sp.free()


func test_summarize_null_spawner_is_empty() -> void:
	var s := Preview.summarize(null)
	assert_eq((s["rows"] as Array).size(), 0, "a null spawner yields no rows (fails soft)")
	assert_eq(int(s["total"]), 0)


func test_scaled_total_sums_each_definition_at_difficulty() -> void:
	# Runtime rounds EACH definition's count independently, so the difficulty estimate sums per-def scaled_count.
	var sp := EncounterSpawner.new()
	sp.spawn_definitions = [_def(4), _def(3)]
	var rows: Array = Preview.summarize(sp)["rows"]
	assert_eq(Preview.scaled_total(rows, 1.0), 7, "Normal (x1) equals the authored total (4 + 3)")
	assert_eq(Preview.scaled_total(rows, 1.5), 11, "x1.5 rounds EACH def: roundi(6.0)=6 + roundi(4.5)=5 = 11")
	sp.free()


func test_scaled_total_excludes_non_spawning_rows() -> void:
	var sp := EncounterSpawner.new()
	var no_scene := _def(4)
	no_scene.npc_scene = null  # runtime skips it -> excluded from the estimate too
	sp.spawn_definitions = [no_scene, _def(2)]
	var rows: Array = Preview.summarize(sp)["rows"]
	assert_eq(Preview.scaled_total(rows, 2.0), 4, "only the spawnable _def(2) counts: scaled_count(2, x2) = 4")
	sp.free()


func test_encounter_view_constructs() -> void:
	var v = EncounterView.new()
	assert_not_null(v, "the Encounter tab constructs (compiles + _init builds UI off-tree)")
	assert_eq(v.name, "Encounter")
	v.free()
