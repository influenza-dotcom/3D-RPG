@tool
extends VBoxContainer

## CYBER SUNDAY → Encounter: a READ-ONLY preview of what an EncounterSpawner would spawn. Select an EncounterSpawner
## node in the scene, hit Preview, and it lists each definition (which NPC × how many, scatter radius, stagger,
## archetype/faction/weapon overrides, auto-aggro) plus totals + placement mode. PREVIEW ONLY — it spawns nothing
## and never writes to the scene. Counts are AUTHORED; runtime scales each by difficulty enemy_count_mult, so the
## footer labels the total an estimate. The summary logic lives in encounter_preview.gd.

const Preview := preload("res://addons/cybersunday_tools/dock_encounter/encounter_preview.gd")
const DIFFICULTY_PATH := "res://resources/tuning/DifficultySettings.tres"

const COLOR_WAVE := Color(0.7, 0.9, 0.7)
const COLOR_DETAIL := Color(1, 1, 1, 0.6)
const COLOR_WARN := Color(1.0, 0.82, 0.3)

var _tree: Tree = null
var _summary: Label = null


func _init() -> void:
	name = "Encounter"
	add_theme_constant_override("separation", 4)

	var bar := HBoxContainer.new()
	var preview := Button.new()
	preview.text = "Preview selected"
	preview.tooltip_text = "Summarize the EncounterSpawner selected in the scene (read-only — spawns nothing)."
	preview.pressed.connect(_preview)
	bar.add_child(preview)
	add_child(bar)

	_summary = Label.new()
	_summary.modulate = Color(1, 1, 1, 0.7)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 90)
	add_child(_tree)

	_summary.text = "Select an EncounterSpawner node in the scene, then Preview."


## Read the selected scene node; if it's an EncounterSpawner, render its summary. Selection-safe: a clear message
## (not an error) when nothing suitable is selected.
func _preview() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var spawner: EncounterSpawner = null
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is EncounterSpawner:
			spawner = n
			break
	if spawner == null:
		_summary.text = "Select an EncounterSpawner node in the scene, then Preview."
		return
	var s := Preview.summarize(spawner)
	var rows: Array = s["rows"]
	if rows.is_empty():
		_summary.text = "%s — no spawn_definitions authored yet." % spawner.name
		return
	for r in rows:
		var item := _tree.create_item(root)
		var head := "Wave %d:  %d× %s   (r=%.1fm%s%s)" % [
			int(r["index"]), int(r["count"]), str(r["npc"]), float(r["radius"]),
			"" if float(r["delay"]) <= 0.0 else ", stagger %.2fs" % float(r["delay"]),
			", auto-aggro" if bool(r["aggro"]) else "",
		]
		item.set_text(0, head)
		item.set_custom_color(0, COLOR_WARN if int(r["count"]) <= 0 or str(r["npc"]).begins_with("(") else COLOR_WAVE)
		for key in ["archetype", "faction", "weapon"]:
			if str(r[key]) != "":
				var d := _tree.create_item(item)
				d.set_text(0, "%s override: %s" % [key, str(r[key])])
				d.set_custom_color(0, COLOR_DETAIL)
	var attach_note := "  +%d attach-scene(s) per NPC." % int(s["attach_count"]) if int(s["attach_count"]) > 0 else ""
	# Make the difficulty estimate REAL: at Normal it's the authored total; Easy/Hard apply DifficultySettings'
	# enemy_count_mult presets via the same per-definition rounding runtime uses. Falls back to the Normal-only line
	# if the presets resource is missing (no false "estimate" claim then).
	var diff: DifficultySettings = load(DIFFICULTY_PATH) as DifficultySettings if ResourceLoader.exists(DIFFICULTY_PATH) else null
	if diff != null:
		var easy := Preview.scaled_total(rows, diff.easy_enemy_count_mult)
		var hard := Preview.scaled_total(rows, diff.hard_enemy_count_mult)
		_summary.text = "%s — %d wave(s). Spawns %d NPC(s) at Normal  (Easy %d / Hard %d, est. via difficulty enemy_count_mult). Placement: %s.%s" % [
			spawner.name, rows.size(), int(s["total"]), easy, hard, str(s["placement"]), attach_note]
	else:
		_summary.text = "%s — %d wave(s), %d NPC(s) at Normal (runtime scales by difficulty enemy_count_mult). Placement: %s.%s" % [
			spawner.name, rows.size(), int(s["total"]), str(s["placement"]), attach_note]
