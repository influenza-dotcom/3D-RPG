@tool
extends EditorInspectorPlugin

## Perk inspector add-on: injects an authoring-validation card at the top of a Perk's inspector — amber warnings
## for any stat_bonuses key that isn't a real CharacterStats attribute (mirrors Perk.validate), any combat_bonuses
## key outside {damage, crit} (no damage seam reads it), and any requires_perks id that names no Perk .tres on
## disk (a prerequisite that can never be met). The perks folder may be ABSENT — then the prereq check degrades
## gracefully (skipped) so a lone perk doesn't false-alarm. Compute lives in InspectorCalc.perk_warnings (pure ->
## unit-tested); this card only scans the folder + renders.

const InspectorCalc := preload("res://addons/cybersunday_tools/inspectors/inspector_calc.gd")

const PERKS_DIR := "res://resources/perks/"


func _can_handle(object: Object) -> bool:
	return object is Perk


func _parse_begin(object: Object) -> void:
	if object is Perk:
		add_custom_control(_build_card(object as Perk))


func _build_card(perk: Perk) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(0, 90)
	var head := Label.new()
	head.text = "Perk — %s" % (perk.display_name if perk.display_name != "" else (String(perk.id) if String(perk.id) != "" else "(unnamed)"))
	box.add_child(head)
	var folder_present := DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(PERKS_DIR)) or DirAccess.open(PERKS_DIR) != null
	var ids := _scan_perk_ids()
	var warns := InspectorCalc.perk_warnings(perk, CharacterStats.stat_names(), ids, folder_present)
	if warns.is_empty():
		var ok := Label.new()
		ok.modulate = Color(1, 1, 1, 0.8)
		ok.text = "  no authoring issues found." if folder_present else "  no authoring issues (resources/perks/ absent — prereqs unchecked)."
		box.add_child(ok)
	for warn in warns:
		var w := Label.new()
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
		w.text = "⚠ " + warn
		box.add_child(w)
	return box


## The Perk ids authored under resources/perks/ (scan the folder; load each .tres and read its `id`). Returns an
## EMPTY list when the folder is absent — the caller pairs that with folder_present=false to skip the prereq check.
func _scan_perk_ids() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(PERKS_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var res := load(PERKS_DIR.path_join(f))
		if res == null:
			continue
		var pid: Variant = res.get("id")
		if pid != null and String(pid) != "":
			out.append(String(pid))
	return out
