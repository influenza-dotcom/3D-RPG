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
	assert_eq(p._status.text, SaveInspector.MSG_IDLE, "the idle status is the one imperative next step")
	assert_eq(p._status.tooltip_text, p._status.text, "the status tooltip mirrors the full text on every write")
	assert_eq(p._status.max_lines_visible, 2, "the status clamps to two lines (a long file name or error rides the tooltip)")
	assert_eq(p._status.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "and autowraps")
	assert_false(p._picker.fit_to_longest_item, "the slot picker never sizes the head to its longest row")
	assert_true(p._picker.clip_text, "it clips a long row instead of widening the panel")
	assert_true(p._refresh_btn.tooltip_text.contains("Read-only"), "the one command declares it writes nothing: %s" % p._refresh_btn.tooltip_text)
	assert_false(p._revealed, "no user:// scan at construction -- the first reveal does it")
	p.free()


## Layout contract: the head and the ONE status Label sit OUTSIDE the scroll (a designer must never have to scroll
## to find the verdict), the Tree lives INSIDE it, and the tab's vertical minimum stays small -- a TabContainer's
## minimum is the CURRENT tab's minimum and the editor's bottom splitter keeps whatever height it grew to.
func test_save_inspector_bounds_its_own_height() -> void:
	var p = SaveInspector.new()
	assert_true(p._tree.get_parent() is ScrollContainer, "the Tree lives inside the ScrollContainer")
	assert_eq(p._status.get_parent(), p, "the status Label is a direct child of the tab, outside the scroll")
	assert_eq(p._picker.get_parent().get_parent(), p, "so is the picker's head row")
	assert_lte(SaveInspector.BODY_MIN_HEIGHT, 120.0, "the scrolled body's floor stays small")
	assert_lte(SaveInspector.TREE_MIN_HEIGHT, SaveInspector.BODY_MIN_HEIGHT, "and the Tree never fights that fence")
	p.free()


## A save is named by its SLOT ("Autosave", "Slot 2") in every sentence -- a designer never has to recognise a
## user:// file name to read the status. A path outside the known list degrades to its file name, not to blank.
func test_slot_label_names_the_slot_not_the_file() -> void:
	assert_eq(SaveInspector._slot_label("user://gamestate.cfg"), "Autosave", "the autosave is named, not 'gamestate'")
	assert_eq(SaveInspector._slot_label("user://save_slot_2.cfg"), "Slot 2", "a numbered slot reads as the designer picked it")
	assert_eq(SaveInspector._slot_label("user://something_else.cfg"), "something_else.cfg", "an unknown file still reads as something")
	assert_eq(SaveInspector._count(1, "key", "keys"), "1 key", "a real singular")
	assert_eq(SaveInspector._count(37, "key", "keys"), "37 keys")
