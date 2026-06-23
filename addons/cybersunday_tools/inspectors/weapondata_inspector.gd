@tool
extends EditorInspectorPlugin

## WeaponData inspector add-on: injects a DERIVED-combat card at the top of a WeaponData's inspector — DPS, burst,
## shots/time-to-kill vs the player (4 HP) and an NPC (10 HP) for body / headshot / sneak / stealth-headshot,
## clip + reload sustain, and a recoil/bloom one-liner — plus amber warnings for half-configured knobs that
## silently no-op (a spreadless shotgun, recoil that never recovers, a caliber with no ammo, …). ALL compute lives
## in InspectorCalc statics (pure, scene-tree-free) so it's unit-tested headless; this card is thin glue.

const InspectorCalc := preload("res://addons/cybersunday_tools/inspectors/inspector_calc.gd")
## Ammo-caliber registry (scans resources/items/) — the card resolves the "no matching ammo" warning against it.
const Calibers := preload("res://scripts/items/calibers.gd")


func _can_handle(object: Object) -> bool:
	return object is WeaponData


func _parse_begin(object: Object) -> void:
	if object is WeaponData:
		add_custom_control(_build_card(object as WeaponData))


func _build_card(wd: WeaponData) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(0, 90)
	var head := Label.new()
	head.text = "WeaponData — derived combat (vs %.0f HP player / %.0f HP NPC)" % [InspectorCalc.PLAYER_HP, InspectorCalc.NPC_HP]
	box.add_child(head)
	for line in InspectorCalc.weapon_lines(wd):
		var l := Label.new()
		l.modulate = Color(1, 1, 1, 0.8)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = line
		box.add_child(l)
	for warn in InspectorCalc.weapon_warnings(wd, Calibers.ids()):
		var w := Label.new()
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
		w.text = "⚠ " + warn
		box.add_child(w)
	return box
