extends GutTest

## The CYBER SUNDAY Saves tab: the read-only save-file inspector. The PURE model (known_saves / config_model /
## fmt_value) is tested with an in-memory ConfigFile — no disk; the tab itself is a compile/construct check (its
## UI + disk read are editor-verified, like the other dock construct tests).

const SaveInspect := preload("res://addons/cybersunday_tools/dock_saves/save_inspect.gd")
const SaveInspector := preload("res://addons/cybersunday_tools/dock_saves/save_inspector.gd")


func _section(model: Array, name: String) -> Dictionary:
	for s in model:
		if String(s["section"]) == name:
			return s
	return {}


func test_known_saves_lists_autosave_quicksave_and_slots() -> void:
	var saves := SaveInspect.known_saves()
	assert_eq(saves.size(), 5, "autosave + quicksave + 3 slots")
	assert_eq(String(saves[0]["path"]), "user://gamestate.cfg", "the autosave path mirrors GameState.SAVE_PATH")
	assert_eq(String(saves[1]["path"]), "user://quicksave.cfg", "the quicksave path mirrors GameState.QUICKSAVE_PATH")
	assert_eq(String(saves[4]["path"]), "user://save_slot_3.cfg", "slot 3 mirrors GameState.slot_path(3)")


func test_config_model_flattens_sections_and_keys() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "money", 100)
	cfg.set_value("player", "respawn", Vector3(1, 2, 3))
	cfg.set_value("flags", "intro_done", true)
	var model := SaveInspect.config_model(cfg)
	assert_eq(model.size(), 2, "two sections")
	var player := _section(model, "player")
	assert_false(player.is_empty(), "the player section is present")
	assert_eq((player["rows"] as Array).size(), 2, "money + respawn rows")
	var flags := _section(model, "flags")
	assert_eq(String((flags["rows"] as Array)[0]["value"]), "true", "a bool flag renders as its string")
	cfg = null


func test_config_model_null_is_empty() -> void:
	assert_eq(SaveInspect.config_model(null).size(), 0, "a null ConfigFile yields no rows (fails soft)")


func test_fmt_value_renders_compounds_and_vec3() -> void:
	assert_eq(SaveInspect.fmt_value(Vector3(1, 2, 3)), "(1.00, 2.00, 3.00)", "Vector3 -> compact tuple")
	assert_true(SaveInspect.fmt_value([1, 2, 3]).begins_with("Array(3)"), "an Array is size-prefixed")
	assert_true(SaveInspect.fmt_value({"a": 1}).begins_with("Dict(1)"), "a Dictionary is size-prefixed")
	assert_eq(SaveInspect.fmt_value(42), "42", "a scalar is just str()")


func test_save_inspector_constructs() -> void:
	var p = SaveInspector.new()
	assert_not_null(p, "the Saves tab constructs (compiles + _init builds UI off-tree)")
	assert_eq(p.name, "Saves")
	p.free()
