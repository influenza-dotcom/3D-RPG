@tool
extends EditorInspectorPlugin

## NpcData inspector add-on: injects a resolved-archetype summary card at the top of an NpcData's inspector and
## flags conflicts inline -- chiefly the faction_id + faction both-set ambiguity -- so an authored NPC profile
## reads at a glance and dual-source mistakes are caught in the inspector. conflicts() is pure -> unit-tested.
##
## TUNE-AND-SEE: the key identity/combat fields are EDITABLE here — display_name (LineEdit), faction_id
## (OptionButton scanning resources/factions/ + a blank "(none)"), weapon_data (a picker dropdown scanning
## resources/weapons/), max_hp / sight_range (SpinBox) and threat_response (OptionButton). Every edit writes back
## through EditorInterface.get_editor_undo_redo() (the proper persist-and-undoable path to mutate a resource from a
## custom inspector) and re-renders the summary + conflict lines live. The pure scan/label helpers live in
## InspectorCalc; this card is thin editor glue.

const InspectorCalc := preload("res://addons/cybersunday_tools/inspectors/inspector_calc.gd")
## Faction registry (scans resources/factions/) — drives the faction_id dropdown, same source as _validate_property.
const Factions := preload("res://scripts/faction/factions.gd")
## The folder the weapon_data picker scans (resources/weapons/*.tres), via InspectorCalc.resource_paths_in.
const WEAPONS_DIR := "res://resources/weapons/"
## threat_response option labels, in enum order — index == the int stored (0 = Fight, 1 = Flee). Mirrors the
## @export_enum on NpcData.threat_response (see npc_data.gd).
const THREAT_LABELS := ["Fight", "Flee"]


func _can_handle(object: Object) -> bool:
	return object is NpcData


func _parse_begin(object: Object) -> void:
	if object is NpcData:
		add_custom_control(_build_card(object as NpcData))


func _build_card(nd: NpcData) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(0, 110)
	var head := Label.new()
	head.text = "NpcData — tune & see"
	box.add_child(head)

	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)

	# display_name — LineEdit
	_label(grid, "Display name")
	var name_edit := LineEdit.new()
	name_edit.text = nd.display_name
	name_edit.custom_minimum_size = Vector2(140, 0)
	name_edit.text_submitted.connect(func(t: String) -> void: _set_prop(nd, "display_name", t, box))
	name_edit.focus_exited.connect(func() -> void: _set_prop(nd, "display_name", name_edit.text, box))
	grid.add_child(name_edit)

	# faction_id — OptionButton over resources/factions/ + a "(none)" blank
	_label(grid, "Faction id")
	var faction_opt := OptionButton.new()
	faction_opt.custom_minimum_size = Vector2(140, 0)
	var faction_ids := Factions.ids()
	faction_opt.add_item("(none)")  # index 0 -> ""
	faction_opt.set_item_metadata(0, "")
	for fid in faction_ids:
		var idx := faction_opt.item_count
		faction_opt.add_item(fid)
		faction_opt.set_item_metadata(idx, fid)
	faction_opt.select(_index_of_metadata(faction_opt, nd.faction_id))
	faction_opt.item_selected.connect(func(i: int) -> void: _set_prop(nd, "faction_id", String(faction_opt.get_item_metadata(i)), box))
	grid.add_child(faction_opt)

	# weapon_data — picker dropdown over resources/weapons/ + a "(none)" blank
	_label(grid, "Weapon")
	var weapon_opt := OptionButton.new()
	weapon_opt.custom_minimum_size = Vector2(140, 0)
	var weapon_paths := InspectorCalc.resource_paths_in(WEAPONS_DIR)
	weapon_opt.add_item("(none)")  # index 0 -> null
	weapon_opt.set_item_metadata(0, "")
	var current_path := nd.weapon_data.resource_path if nd.weapon_data != null else ""
	for path in weapon_paths:
		var widx := weapon_opt.item_count
		weapon_opt.add_item(InspectorCalc.picker_label_for(path))
		weapon_opt.set_item_metadata(widx, path)
	weapon_opt.select(_index_of_metadata(weapon_opt, current_path))
	weapon_opt.item_selected.connect(func(i: int) -> void: _on_weapon_selected(nd, String(weapon_opt.get_item_metadata(i)), box))
	grid.add_child(weapon_opt)

	# max_hp — SpinBox
	_label(grid, "Max HP")
	_add_spin(grid, nd, "max_hp", 1.0, 99999.0, 1.0, box)

	# sight_range — SpinBox
	_label(grid, "Sight range (m)")
	_add_spin(grid, nd, "sight_range", 0.0, 9999.0, 0.5, box)

	# threat_response — OptionButton (Fight / Flee), index == the stored int
	_label(grid, "Threat response")
	var threat_opt := OptionButton.new()
	threat_opt.custom_minimum_size = Vector2(140, 0)
	for i in THREAT_LABELS.size():
		threat_opt.add_item(THREAT_LABELS[i], i)
	threat_opt.select(clampi(nd.threat_response, 0, THREAT_LABELS.size() - 1))
	threat_opt.item_selected.connect(func(i: int) -> void: _set_prop(nd, "threat_response", i, box))
	grid.add_child(threat_opt)

	# Summary + conflicts live in a child container we clear + rebuild on every edit.
	var readout := VBoxContainer.new()
	readout.name = "Readout"
	box.add_child(readout)
	_render_readout(readout, nd)
	return box


## (Re)build the resolved-stats summary + conflict warnings into `readout`, clearing the previous render.
func _render_readout(readout: VBoxContainer, nd: NpcData) -> void:
	for child in readout.get_children():
		child.queue_free()
	var stats := Label.new()
	stats.modulate = Color(1, 1, 1, 0.8)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.text = "  %s   HP %.0f   sight %.0fm   faction: %s   %s   weapon: %s" % [
		nd.display_name if nd.display_name != "" else "(unnamed)",
		nd.max_hp, nd.sight_range, _faction_label(nd),
		THREAT_LABELS[clampi(nd.threat_response, 0, THREAT_LABELS.size() - 1)],
		_weapon_label(nd),
	]
	readout.add_child(stats)
	for w in conflicts(nd):
		var warn := Label.new()
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
		warn.text = "⚠ " + w
		readout.add_child(warn)


## Generic undoable write-back of a plain (non-resource) property, then re-render. No-ops if unchanged.
func _set_prop(nd: NpcData, prop: String, value: Variant, box: VBoxContainer) -> void:
	if nd.get(prop) == value:
		return
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Set NpcData.%s" % prop)
	ur.add_do_property(nd, prop, value)
	ur.add_undo_property(nd, prop, nd.get(prop))
	ur.commit_action()
	_refresh(box, nd)


## weapon_data is a Resource reference — resolve the picked path to a WeaponData (or null for "(none)") and write
## it back undoably. Loading by path is export-safe and cached by the resource loader.
func _on_weapon_selected(nd: NpcData, path: String, box: VBoxContainer) -> void:
	var picked: WeaponData = null
	if path != "" and ResourceLoader.exists(path):
		var res := load(path)
		if res is WeaponData:
			picked = res as WeaponData
	if nd.weapon_data == picked:
		return
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Set NpcData.weapon_data")
	ur.add_do_property(nd, "weapon_data", picked)
	ur.add_undo_property(nd, "weapon_data", nd.weapon_data)
	ur.commit_action()
	_refresh(box, nd)


func _refresh(box: VBoxContainer, nd: NpcData) -> void:
	var readout := box.get_node_or_null("Readout")
	if readout is VBoxContainer:
		_render_readout(readout as VBoxContainer, nd)


func _label(grid: GridContainer, text: String) -> void:
	var l := Label.new()
	l.modulate = Color(1, 1, 1, 0.8)
	l.text = text
	grid.add_child(l)


func _add_spin(grid: GridContainer, nd: NpcData, prop: String, lo: float, hi: float, step: float, box: VBoxContainer) -> void:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.allow_greater = true
	sb.custom_minimum_size = Vector2(110, 0)
	sb.value = float(nd.get(prop))
	sb.value_changed.connect(func(v: float) -> void: _set_prop(nd, prop, v, box))
	grid.add_child(sb)


## The OptionButton index whose item_metadata equals `value`, or 0 (the "(none)" row) if none matches.
func _index_of_metadata(opt: OptionButton, value: String) -> int:
	for i in opt.item_count:
		if String(opt.get_item_metadata(i)) == value:
			return i
	return 0


## Authoring conflicts on an NpcData (pure -> unit-testable). The headline one: both a faction_id string AND a
## faction resource set, which is ambiguous (the runtime usually resolves the resource, silently ignoring the id).
static func conflicts(nd: NpcData) -> PackedStringArray:
	var w := PackedStringArray()
	if nd == null:
		return w
	if nd.faction_id != "" and nd.faction != null:
		w.append("Both faction_id ('%s') and a faction resource are set — pick one to avoid an ambiguous faction." % nd.faction_id)
	return w


static func _faction_label(nd: NpcData) -> String:
	if nd.faction != null:
		var fid: Variant = nd.faction.get("id")
		return str(fid) if (fid != null and str(fid) != "") else "(resource)"
	if nd.faction_id != "":
		return nd.faction_id
	return "(none)"


static func _weapon_label(nd: NpcData) -> String:
	if nd.weapon_data == null:
		return "unarmed"
	return InspectorCalc.picker_label_for(nd.weapon_data.resource_path)
