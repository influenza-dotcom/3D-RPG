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
	assert_eq(v.name, "Encounter", "the Control name is pinned -- cyber_panel keys tabs by it (the painted title is separate)")
	assert_eq(v._status.text, EncounterView.MSG_IDLE, "the idle status is the one imperative next step")
	assert_eq(v._status.tooltip_text, v._status.text, "the status tooltip mirrors the full text from the first write")
	assert_eq(v._status.max_lines_visible, 2, "the status clamps to two lines (the tooltip carries the rest)")
	assert_eq(v._status.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "and autowraps")
	assert_lte(v._tree.custom_minimum_size.y, 120.0, "the wave list's floor stays small -- one tall tab leaves the shared panel tall")
	v.free()


## The two gates on Preview Selected, and the rule that a greyed button names what is missing. Off-tree there is no
## editor selection at all, so a scene root alone leaves the "select a spawner" gate closed -- which is exactly the
## state to pin: scene first, then selection.
func test_preview_button_is_greyed_with_a_reason_for_each_missing_thing() -> void:
	var v = EncounterView.new()
	assert_true(v._preview_btn.disabled, "no scene known yet -> Preview Selected is greyed")
	assert_eq(v._preview_btn.tooltip_text, EncounterView.MSG_NO_SCENE, "and the tooltip names the missing scene")
	var root := Node.new()
	v.on_scene_changed(root)
	assert_true(v._preview_btn.disabled, "a scene alone is not enough -- nothing is selected")
	assert_eq(v._preview_btn.tooltip_text, EncounterView.MSG_NO_SPAWNER, "the tooltip moves on to the missing selection")
	v.on_scene_changed(null)
	assert_eq(v._preview_btn.tooltip_text, EncounterView.MSG_NO_SCENE, "closing every scene puts the first gate back")
	root.free()
	v.free()


## The post-click fallback: a click that slips past a stale button state must say the SAME sentence the greyed
## button's tooltip does, never fail silently. Read-only either way -- the tree is emptied, nothing is spawned.
func test_preview_refuses_out_loud_with_the_same_words_as_the_tooltip() -> void:
	var v = EncounterView.new()
	v._preview()
	assert_eq(v._status.text, EncounterView.MSG_NO_SCENE, "no scene -> the refusal repeats the tooltip's sentence")
	assert_eq(v._status.tooltip_text, v._status.text, "mirrored onto the tooltip")
	var root := Node.new()
	v.on_scene_changed(root)
	v._preview()
	assert_eq(v._status.text, EncounterView.MSG_NO_SPAWNER, "a scene but no spawner -> the second sentence")
	assert_null(v._tree.get_root().get_first_child(), "a refused preview leaves no rows behind")
	root.free()
	v.free()


# --- pure row / footer wording (pinned off-tree, so the designer's sentences can't drift) --------------------------

func test_row_text_reads_as_a_designer_sentence() -> void:
	var row := {
		"index": 0, "npc": "NPC.tscn", "count": 3, "spawns": true, "radius": 6.0, "delay": 0.5,
		"archetype": "raider.tres", "faction": "", "weapon": "", "aggro": true,
	}
	assert_eq(EncounterView.row_text(row, false),
		"Wave 1: 3 x NPC, scattered within 6 m, 0.5 s apart, archetype: raider, hostile on spawn",
		"waves count from 1, files lose their extension, and an unset override is left out")
	assert_true(EncounterView.row_text(row, true).contains("placed at the markers"),
		"with markers the radius is irrelevant, so the row says where they actually go")
	var quiet := row.duplicate()
	quiet["delay"] = 0.0
	quiet["aggro"] = false
	assert_true(EncounterView.row_text(quiet, false).contains("all at once"), "no stagger reads 'all at once', not '0 s apart'")
	assert_true(EncounterView.row_text(quiet, false).ends_with("unaware until they spot you"), "and the aggro flag is spelled out either way")


func test_row_text_says_so_when_a_wave_would_spawn_nothing() -> void:
	var empty_slot := {"index": 0, "npc": "(empty definition)", "count": 0, "spawns": false}
	assert_eq(EncounterView.row_text(empty_slot, false), "Wave 1: empty slot -- spawns nothing.", "an empty slot is named, not skipped")
	var no_scene := {"index": 1, "npc": "(no NPC scene set)", "count": 2, "spawns": false}
	assert_eq(EncounterView.row_text(no_scene, false), "Wave 2: 2 x (no NPC scene set) -- spawns nothing.",
		"a wave the game would skip says so instead of promising 2 NPCs")
	assert_true(EncounterView.row_tooltip(no_scene).begins_with("Slot 1 under Spawn Definitions"), "the tooltip says where to fix it")


func test_footer_and_placement_wording() -> void:
	assert_eq(EncounterView.footer_text(7, 5, 10, true),
		"Authored total 7 -- difficulty scales it: Easy / Normal / Hard = 5 / 7 / 10 (estimate)",
		"Normal sits in the middle and is the authored count")
	assert_true(EncounterView.footer_text(7, 0, 0, false).contains("no Easy / Hard estimate"),
		"without the presets file the footer says why, rather than claiming an estimate")
	assert_eq(EncounterView.placement_text(0), "Placement: scattered around the spawner, each wave within its own radius.")
	assert_eq(EncounterView.placement_text(1), "Placement: at the spawner's 1 marker, in order.", "a real singular")
	assert_eq(EncounterView.placement_text(3), "Placement: at the spawner's 3 markers, in order.")


## The model's placeholder for a definition with no scene is what the row renders, so it must be designer words --
## never the export's field name.
func test_summarize_placeholder_is_designer_words() -> void:
	var sp := EncounterSpawner.new()
	var no_scene := _def(2)
	no_scene.npc_scene = null
	sp.spawn_definitions = [no_scene]
	var rows: Array = Preview.summarize(sp)["rows"]
	var npc := String(rows[0]["npc"])
	assert_eq(npc, "(no NPC scene set)", "the placeholder reads as a sentence a designer can act on")
	assert_false(npc.contains("npc_scene"), "and never names the export field")
	assert_eq(EncounterView.row_text(rows[0], false), "Wave 1: 2 x (no NPC scene set) -- spawns nothing.",
		"the row and the model say the same words")
	sp.free()
