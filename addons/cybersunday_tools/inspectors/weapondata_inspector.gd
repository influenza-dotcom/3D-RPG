@tool
extends EditorInspectorPlugin

## WeaponData inspector add-on: injects a DERIVED-combat card at the top of a WeaponData's inspector — DPS, burst,
## shots/time-to-kill vs the player (4 HP) and an NPC (10 HP) for body / headshot / sneak / stealth-headshot,
## clip + reload sustain, and a recoil/bloom one-liner — plus amber warnings for half-configured knobs that
## silently no-op (a spreadless shotgun, recoil that never recovers, a caliber with no ammo, …). ALL compute lives
## in InspectorCalc statics (pure, scene-tree-free) so it's unit-tested headless; this card is thin glue.
##
## TUNE-AND-SEE: the key balance fields (damage, attack_speed, pellet_count, headshot/sneak multipliers, ammo,
## reload) are EDITABLE here as SpinBoxes. An edit writes back through EditorInterface.get_editor_undo_redo() (the
## proper persist-and-undoable path to mutate a resource from a custom inspector) and re-renders the derived
## DPS/TTK + warning lines live — so a designer tunes the number and watches the TTK move without leaving the card.

const InspectorCalc := preload("res://addons/cybersunday_tools/inspectors/inspector_calc.gd")
## Ammo-caliber registry (scans resources/items/) — the card resolves the "no matching ammo" warning against it.
const Calibers := preload("res://scripts/items/calibers.gd")

## The editable balance knobs, as [property, label, min, max, step]. Floats use a fractional step; the int field
## (pellet_count, max_ammo) uses step 1. Kept here so the card and the write-back agree on exactly one set.
const FIELDS := [
	["damage", "Damage", 0.0, 9999.0, 0.1],
	["attack_speed", "Attack speed (s/shot)", 0.0, 60.0, 0.01],
	["pellet_count", "Pellets", 1.0, 999.0, 1.0],
	["headshot_multiplier", "Headshot ×", 0.0, 100.0, 0.1],
	["sneak_attack_multiplier", "Sneak ×", 0.0, 100.0, 0.1],
	["max_ammo", "Clip (max ammo)", 0.0, 9999.0, 1.0],
	["reload_time", "Reload (s)", 0.0, 60.0, 0.1],
]
## The integer-typed fields (rendered without a decimal step and written back as ints).
const INT_FIELDS := ["pellet_count", "max_ammo"]


func _can_handle(object: Object) -> bool:
	return object is WeaponData


func _parse_begin(object: Object) -> void:
	if object is WeaponData:
		add_custom_control(_build_card(object as WeaponData))


func _build_card(wd: WeaponData) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(0, 110)
	var head := Label.new()
	head.text = "WeaponData — tune & see (vs %.0f HP player / %.0f HP NPC)" % [InspectorCalc.PLAYER_HP, InspectorCalc.NPC_HP]
	box.add_child(head)

	# Editable balance knobs — each writes back via undo_redo and re-renders the derived lines below.
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for spec in FIELDS:
		var prop: String = spec[0]
		var lbl := Label.new()
		lbl.modulate = Color(1, 1, 1, 0.8)
		lbl.text = spec[1]
		grid.add_child(lbl)
		var sb := SpinBox.new()
		sb.min_value = spec[2]
		sb.max_value = spec[3]
		sb.step = spec[4]
		sb.allow_greater = true  # a designer may push past the soft cap while tuning
		sb.custom_minimum_size = Vector2(110, 0)
		sb.value = float(wd.get(prop))
		sb.value_changed.connect(_on_field_changed.bind(wd, prop, box))
		grid.add_child(sb)

	# Derived readout + warnings live in a child container we clear + rebuild on every edit.
	var readout := VBoxContainer.new()
	readout.name = "Readout"
	box.add_child(readout)
	_render_readout(readout, wd)
	return box


## (Re)build the derived DPS/TTK lines + amber warnings into `readout`, clearing any previous render. Called on
## build and after every field edit so the numbers track the live resource.
func _render_readout(readout: VBoxContainer, wd: WeaponData) -> void:
	for child in readout.get_children():
		child.queue_free()
	for line in InspectorCalc.weapon_lines(wd):
		var l := Label.new()
		l.modulate = Color(1, 1, 1, 0.8)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = line
		readout.add_child(l)
	for warn in InspectorCalc.weapon_warnings(wd, Calibers.ids()):
		var w := Label.new()
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
		w.text = "⚠ " + warn
		readout.add_child(w)


## SpinBox edit -> undoable write-back to the resource, then re-render the readout. Ints are coerced so
## pellet_count / max_ammo persist as integers, not floats.
func _on_field_changed(value: float, wd: WeaponData, prop: String, box: VBoxContainer) -> void:
	var new_value: Variant = int(round(value)) if INT_FIELDS.has(prop) else value
	if wd.get(prop) == new_value:
		return
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Set WeaponData.%s" % prop)
	ur.add_do_property(wd, prop, new_value)
	ur.add_undo_property(wd, prop, wd.get(prop))
	ur.commit_action()
	var readout := box.get_node_or_null("Readout")
	if readout is VBoxContainer:
		_render_readout(readout as VBoxContainer, wd)
