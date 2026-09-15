extends GutTest

## Items & Weapons tab — the derived property form (`dock_item/property_form.gd`) and the dock's off-tree build.
##
## The form is generated from each resource's own exports, so the tests that matter are the ones proving the
## derivation cannot silently hide a knob (`test_fields_cover_every_designer_export_on_a_weapon`) and cannot
## corrupt an authored value on the way into a widget (the range and enum tests). A SpinBox clamps and snaps on
## the way IN as well as out, and an enum's ROW index is not its VALUE — both are quiet data-loss bugs rather
## than crashes, which is why they are pinned here rather than left to a playtest.

const Form := preload("res://addons/cybersunday_tools/dock_item/property_form.gd")
const ItemEditor := preload("res://addons/cybersunday_tools/dock_item/item_editor.gd")


func test_item_dock_constructs_off_tree() -> void:
	var d = ItemEditor.new()
	assert_not_null(d, "items tab should construct off-tree")
	assert_eq(d.name, "Item Edit", "dock tab name -- cyber_panel routes show_tab / open_in_editor by this exact name")
	d.free()


func test_fields_are_read_off_the_resource_with_their_groups() -> void:
	var it := Item.new()
	var fields := Form.fields(it)
	assert_true(fields.size() > 10, "an Item exposes its designer fields, got %d" % fields.size())
	var names: Array = []
	var groups := {}
	for f in fields:
		names.append(String(f["name"]))
		groups[String(f["group"])] = true
	assert_true(names.has("display_name"), "the name a player reads is editable")
	assert_true(names.has("value"), "the price is editable")
	assert_true(names.has("weight"), "the carry weight is editable")
	assert_true(groups.has("Identity & Display"), "fields carry their @export_group so the form can head them")
	it = null


## The whole point of deriving: a knob that exists but is not shown is invisible to a designer, who then never
## learns it is there.
func test_fields_cover_every_designer_export_on_a_weapon() -> void:
	var w := WeaponData.new()
	var fields := Form.fields(w)
	assert_true(fields.size() > 60, "a WeaponData's many balance knobs should all be listed, got %d" % fields.size())
	var editable := 0
	for f in fields:
		if bool(f["editable"]):
			editable += 1
	assert_true(editable > 50, "most weapon knobs are plain numbers and toggles the form can edit, got %d" % editable)
	w = null


## `id` is a primary key every stock list, loot table and save file references by name.
func test_the_id_is_never_offered_for_editing() -> void:
	var it := Item.new()
	for f in Form.fields(it):
		assert_ne(String(f["name"]), "id", "the item id is a key, not a field -- renaming it in a form would break every reference")
		assert_false(String(f["name"]).begins_with("resource_"), "engine bookkeeping is not content")
	it = null


func test_resource_typed_fields_are_listed_but_not_editable() -> void:
	var it := Item.new()
	var seen := false
	for f in Form.fields(it):
		if String(f["name"]) == "icon":
			seen = true
			assert_false(bool(f["editable"]), "a Texture2D field stays the Inspector's job")
	assert_true(seen, "the icon field is still LISTED -- the tab must not pretend a field does not exist")
	it = null


func test_label_of_reads_as_a_setting_not_a_variable() -> void:
	assert_eq(Form.label_of("max_stack"), "Max stack", "snake_case becomes prose")
	assert_eq(Form.label_of("value"), "Value", "a single word is capitalised")


# --- the two quiet data-loss traps ------------------------------------------------------------------------

## A Range clamps and snaps on the way IN. Without the authored range, pushing 12.5 into a default SpinBox would
## rewrite it to 12 just by opening the tab.
func test_range_of_uses_the_authored_range_and_a_fine_step_otherwise() -> void:
	var ranged := {"type": TYPE_INT, "hint": PROPERTY_HINT_RANGE, "hint_string": "1,999"}
	var r := Form.range_of(ranged)
	assert_eq(float(r["min"]), 1.0, "the authored minimum is honoured")
	assert_eq(float(r["max"]), 999.0, "the authored maximum is honoured")
	var stepped := {"type": TYPE_FLOAT, "hint": PROPERTY_HINT_RANGE, "hint_string": "0,10,0.5"}
	assert_eq(float(Form.range_of(stepped)["step"]), 0.5, "the authored step is honoured")
	var bare := {"type": TYPE_FLOAT, "hint": PROPERTY_HINT_NONE, "hint_string": ""}
	var br := Form.range_of(bare)
	assert_true(float(br["step"]) <= 0.001, "an unranged float gets a fine step so an authored decimal is not rounded away")
	assert_true(float(br["min"]) < -1000.0, "and a wide range so an authored value is not clamped")
	var bare_int := Form.range_of({"type": TYPE_INT, "hint": PROPERTY_HINT_NONE, "hint_string": ""})
	assert_eq(float(bare_int["step"]), 1.0, "an unranged int steps by one")


## An enum's hint string carries its real values, which are NOT the row order.
func test_enum_row_index_is_not_the_stored_value() -> void:
	var f := {"type": TYPE_INT, "hint": PROPERTY_HINT_ENUM, "hint_string": "MISC:3,WEAPON:0,AMMO:7"}
	var items := Form.enum_items(f)
	assert_eq(items.size(), 3, "every choice is offered")
	assert_eq(String(items[0]), "MISC", "the label drops the value suffix")
	assert_eq(Form.enum_value(f, 0), 3, "row 0 stores 3, not 0 -- reading the index as the value is the bug")
	assert_eq(Form.enum_value(f, 1), 0, "row 1 stores 0")
	assert_eq(Form.enum_index(f, 7), 2, "and the stored value maps back to its row")


func test_enum_handles_a_plain_list_with_no_explicit_values() -> void:
	var f := {"type": TYPE_INT, "hint": PROPERTY_HINT_ENUM, "hint_string": "LOW,MID,HIGH"}
	assert_eq(Form.enum_value(f, 2), 2, "with no colons the row index IS the value")
	assert_eq(Form.enum_index(f, 1), 1, "and maps back")


func test_enum_items_is_empty_for_a_field_that_is_not_a_choice() -> void:
	assert_eq(Form.enum_items({"type": TYPE_INT, "hint": PROPERTY_HINT_NONE, "hint_string": ""}).size(), 0, "a plain int is not a dropdown")


func test_an_out_of_range_stored_value_points_at_a_real_row() -> void:
	var f := {"type": TYPE_INT, "hint": PROPERTY_HINT_ENUM, "hint_string": "A:0,B:1"}
	assert_eq(Form.enum_index(f, 99), 0, "an unrepresentable value falls back to row 0 rather than -1")


# --- read-only descriptions + reporting -------------------------------------------------------------------

func test_describe_names_a_file_rather_than_printing_an_object() -> void:
	assert_eq(Form.describe(null), "(nothing)", "an empty reference says so in words")
	var it := Item.new()
	assert_true(Form.describe(it).contains("built in"), "an unsaved resource says it has no file, got: %s" % Form.describe(it))
	assert_eq(Form.describe([1, 2, 3]), "3 entries (edit in the Inspector)", "an array says how many and where to edit it")
	assert_eq(Form.describe(4.5), "4.5", "a plain value prints plainly")
	it = null


func test_save_report_names_both_files_when_both_changed() -> void:
	var both := Form.save_report("pistol_item.tres", 3, "pistol.tres", 2)
	assert_true(both.contains("pistol_item.tres"), "the item is named, got: %s" % both)
	assert_true(both.contains("pistol.tres"), "the weapon file is named too, got: %s" % both)
	assert_true(both.contains("3 changes"), "plural changes, got: %s" % both)
	var one := Form.save_report("pistol_item.tres", 1, "", 0)
	assert_true(one.contains("1 change on the item"), "singular change, got: %s" % one)
	assert_false(one.contains(".tres on"), "no weapon clause when the weapon did not change, got: %s" % one)
	var none := Form.save_report("rock_item.tres", 0, "", 0)
	assert_true(none.contains("nothing had changed"), "a no-op save says so, got: %s" % none)


func test_select_path_refuses_off_tree() -> void:
	var d = ItemEditor.new()
	assert_false(d.select_path(""), "a blank path is refused")
	assert_false(d.select_path("res://resources/items/does_not_exist.tres"), "a missing file is refused")
	d.free()


## Every shipped item must survive the form: the derivation runs over real authored data, not just a bare
## `Item.new()`, so a field with an unusual hint on a real file would surface here.
func test_every_shipped_item_yields_a_form() -> void:
	var dir := "res://resources/items"
	var checked := 0
	for n in DirAccess.get_files_at(dir):
		var fname := String(n).trim_suffix(".remap")
		if fname.get_extension().to_lower() != "tres":
			continue
		var res := load(dir.path_join(fname))
		if res == null:
			continue
		var fields := Form.fields(res)
		assert_true(fields.size() > 0, "%s should yield editable fields" % fname)
		checked += 1
	assert_true(checked > 20, "expected the shipped item set, checked %d" % checked)
