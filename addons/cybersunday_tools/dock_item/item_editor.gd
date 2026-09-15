@tool
extends VBoxContainer

## ITEMS & WEAPONS — edit an item and, in the same place, the weapon it carries.
##
## Why this tab exists: `Item` and `WeaponData` were the two big content types with NO editor tab
## (`cyber_panel.editor_tab_for` returned "" for both), so a weapon's ~120 balance knobs were edited in the raw
## Inspector, across TWO files — the item that carries it and the weapon card itself — with no backup and no
## search. Balancing one gun meant clicking between two resources and remembering which number lived where.
##
## The form is DERIVED from each resource's exports rather than hand-listed, so a new `@export` appears here with
## no plugin edit and no chance of a knob existing that the tab silently hides. See `property_form.gd`.
##
## WRITE CONTRACT: read-only until **Save Item**. That one press writes the item file and, when its weapon
## changed too, the weapon file — each with a `.tres.bak` first, and the report names both. Switching items with
## unsaved work pops Save / Discard / Cancel.
##
## What stays the Inspector's job, on purpose: `id` (a primary KEY every stock list, loot table and save file
## references by name — renaming it in a form would break those silently), and every Resource-typed field (icon,
## world model, status effects, the weapon mod). Those are listed read-only, naming the file they point at, so the
## tab never pretends a field does not exist.

const ContentSaveGuard := preload("res://addons/cybersunday_tools/core/content_save_guard.gd")
const PickerRows := preload("res://addons/cybersunday_tools/core/picker_rows.gd")
const ItemScan := preload("res://addons/cybersunday_tools/core/item_scan.gd")
const Form := preload("res://addons/cybersunday_tools/dock_item/property_form.gd")

const SAVE_TIP := "Write the changed numbers back to the item, and to its weapon if that changed too. Keeps a .bak of each. Writes: on Save only."
const SAVE_TIP_CLEAN := "Change something first."
const RELOAD_TIP := "Throw away unsaved edits and re-read the item from disk."
const PICKER_TIP := "Which item to edit. Every item in the items folder is listed."
const SEARCH_TIP := "Filter the fields by name."
const MSG_SCANNING := "Scanning..."
const MSG_EMPTY := "No items found. Make one with New, then come back here."
const MSG_PICK := "Pick an item to edit."
const READONLY_NOTE := "Greyed rows are pictures, models and other files -- set those in the Inspector."
const WARN_COLOR := Color(1.0, 0.85, 0.4)
const ERROR_COLOR := Color(1.0, 0.55, 0.5)
const NUM_WIDTH := 130.0
const LABEL_WIDTH := 190.0

var _save_btn: Button
var _reload_btn: Button
var _picker: OptionButton
var _search: LineEdit
var _list_box: VBoxContainer
var _status: Label

var _rows: Array = []
var _paths: PackedStringArray = PackedStringArray()
var _item: Resource = null
var _weapon: Resource = null
var _path := ""
## One per built widget: {"res", "name", "widget", "row", "loaded", "field", "haystack"}. `loaded` is the value as
## read from disk, so dirty is a comparison against the FILE rather than a latched flag.
var _bound: Array = []
var _revealed := false
var _fs_dirty := false
var _status_base := ""
var _status_kind := ""
var _guard: ConfirmationDialog = null
var _guard_then: Callable = Callable()
var _guard_prev_idx := -1


func _init() -> void:
	name = "Item Edit"
	add_theme_constant_override("separation", 4)

	var btn_row := HBoxContainer.new()
	_save_btn = Button.new()
	_save_btn.pressed.connect(_on_save)
	btn_row.add_child(_save_btn)
	_reload_btn = Button.new()
	_reload_btn.text = "Reload"
	_reload_btn.tooltip_text = RELOAD_TIP
	_reload_btn.pressed.connect(_on_reload_pressed)
	btn_row.add_child(_reload_btn)
	_picker = OptionButton.new()
	_picker.tooltip_text = PICKER_TIP
	# The width guards PickerRows.apply also sets. Applied here too because the first fill is lazy, and an empty
	# OptionButton still defaults fit_to_longest_item TRUE, which widens the whole bottom panel through the scroller.
	_picker.fit_to_longest_item = false
	_picker.clip_text = true
	_picker.item_selected.connect(_on_picked)
	btn_row.add_child(_picker)
	_search = LineEdit.new()
	_search.placeholder_text = "Search fields..."
	_search.tooltip_text = SEARCH_TIP
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_on_search_changed)
	btn_row.add_child(_search)
	add_child(btn_row)

	add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 90)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_list_box)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)
	_set_status(MSG_SCANNING)
	_render_dirty()

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan on first reveal, not now


func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_rescan()
	elif is_visible_in_tree() and _revealed and _fs_dirty and not _is_dirty():
		_fs_dirty = false
		_rescan()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if not fs.filesystem_changed.is_connected(_on_filesystem_changed):
			fs.filesystem_changed.connect(_on_filesystem_changed)


func _on_filesystem_changed() -> void:
	_fs_dirty = true


# --- scan -------------------------------------------------------------------------------------------------

## `ItemDb` is a non-@tool autoload and is EMPTY inside the editor, so the folder is scanned through the one
## shared scanner every other plugin surface uses rather than queried from the registry.
func _rescan() -> void:
	_paths = PackedStringArray()
	var labels := PackedStringArray()
	for it in ItemScan.scan():
		if it == null or it.resource_path == "":
			continue
		_paths.append(it.resource_path)
		var shown := String(it.display_name)
		labels.append(it.resource_path.get_file().get_basename() if shown == "" else shown)
	_rows = PickerRows.path_rows(_paths, labels, _path, _item != null)
	PickerRows.apply(_picker, _rows, _path)
	if _paths.is_empty():
		_clear()
		_set_status(MSG_EMPTY, "warn")
		_render_dirty()
		return
	if _path == "":
		_clear()
		_set_status(MSG_PICK)
		_render_dirty()
		return
	_load_path(_path)


# --- load / build -----------------------------------------------------------------------------------------

func _clear() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	_bound.clear()


func _load_path(path: String, replace: bool = false) -> void:
	var mode := ResourceLoader.CACHE_MODE_REPLACE if replace else ResourceLoader.CACHE_MODE_REUSE
	var res := ResourceLoader.load(path, "", mode)
	if res == null:
		_clear()
		_item = null
		_weapon = null
		_set_status("Couldn't open %s: the file didn't load." % path.get_file(), "error")
		_render_dirty()
		return
	_item = res
	_path = path
	_weapon = res.get("weapon") as Resource
	if _weapon != null and replace and _weapon.resource_path != "":
		_weapon = ResourceLoader.load(_weapon.resource_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Resource
	_clear()
	_build_section("Item", _item)
	if _weapon != null:
		var wfile := _weapon.resource_path.get_file()
		_build_section("Weapon -- %s" % (wfile if wfile != "" else "built in"), _weapon)
	_set_status(_summary_line())
	_apply_filter()
	_render_dirty()


func _build_section(title: String, res: Resource) -> void:
	var head := Label.new()
	head.text = title
	_list_box.add_child(head)
	var note := Label.new()
	note.text = READONLY_NOTE
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1, 1, 1, 0.6)
	_list_box.add_child(note)
	var group := ""
	for f in Form.fields(res):
		var g := String(f.get("group", ""))
		if g != group:
			group = g
			if group != "":
				var gh := Label.new()
				gh.text = "  " + group
				gh.modulate = Color(1, 1, 1, 0.8)
				_list_box.add_child(gh)
		_list_box.add_child(_build_row(res, f))


func _build_row(res: Resource, f: Dictionary) -> Control:
	var pname := String(f["name"])
	var value = res.get(pname)
	var multiline: bool = bool(f.get("multiline", false))
	var box := VBoxContainer.new() if multiline else HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl := Label.new()
	lbl.text = Form.label_of(pname)
	lbl.tooltip_text = pname
	if not multiline:
		lbl.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
		lbl.clip_text = true
	box.add_child(lbl)

	var widget: Control = null
	if not bool(f.get("editable", false)):
		var ro := Label.new()
		ro.text = Form.describe(value)
		ro.modulate = Color(1, 1, 1, 0.55)
		ro.clip_text = true
		ro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ro.tooltip_text = "Set this in the Inspector."
		box.add_child(ro)
	else:
		widget = _build_widget(res, pname, f, value)
		box.add_child(widget)

	_bound.append({
		"res": res,
		"name": pname,
		"widget": widget,
		"row": box,
		"loaded": value,
		"field": f,
		"haystack": (pname + " " + Form.label_of(pname)).to_lower(),
	})
	return box


func _build_widget(res: Resource, pname: String, f: Dictionary, value) -> Control:
	var type: int = int(f["type"])
	var choices := Form.enum_items(f)
	if type == TYPE_INT and not choices.is_empty():
		var ob := OptionButton.new()
		for c in choices:
			ob.add_item(String(c))
		ob.fit_to_longest_item = false
		ob.clip_text = true
		ob.custom_minimum_size = Vector2(PickerRows.PICKER_MIN_WIDTH, 0)
		ob.select(Form.enum_index(f, int(value)))
		ob.item_selected.connect(_on_enum_changed.bind(res, pname, f))
		return ob
	if type == TYPE_BOOL:
		var cb := CheckBox.new()
		cb.set_pressed_no_signal(bool(value))
		cb.toggled.connect(_on_bool_changed.bind(res, pname))
		return cb
	if type == TYPE_INT or type == TYPE_FLOAT:
		var sb := SpinBox.new()
		var r := Form.range_of(f)
		# Order matters: min/max BEFORE the value, or a Range clamps the authored number on the way in.
		sb.min_value = float(r["min"])
		sb.max_value = float(r["max"])
		sb.step = float(r["step"])
		sb.allow_greater = true
		sb.allow_lesser = true
		sb.custom_minimum_size = Vector2(NUM_WIDTH, 0)
		sb.set_value_no_signal(float(value))
		sb.value_changed.connect(_on_number_changed.bind(res, pname, type))
		return sb
	if bool(f.get("multiline", false)):
		var te := TextEdit.new()
		te.custom_minimum_size = Vector2(0, 48)
		te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		te.text = String(value)
		te.text_changed.connect(_on_multiline_changed.bind(res, pname, te))
		return te
	var le := LineEdit.new()
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text = String(value)
	le.text_changed.connect(_on_text_changed.bind(res, pname, int(f["type"])))
	return le


# --- write-through ----------------------------------------------------------------------------------------
# Each handler writes only its own field, onto the staged (shared, cached) resource. Nothing reaches disk until
# Save; the dirty marker exists because a Ctrl+S in the Inspector WOULD persist what is staged here.

func _on_enum_changed(index: int, res: Resource, pname: String, f: Dictionary) -> void:
	res.set(pname, Form.enum_value(f, index))
	_after_edit()


func _on_bool_changed(pressed: bool, res: Resource, pname: String) -> void:
	res.set(pname, pressed)
	_after_edit()


func _on_number_changed(value: float, res: Resource, pname: String, type: int) -> void:
	res.set(pname, int(round(value)) if type == TYPE_INT else value)
	_after_edit()


func _on_text_changed(new_text: String, res: Resource, pname: String, type: int) -> void:
	res.set(pname, StringName(new_text) if type == TYPE_STRING_NAME else new_text)
	_after_edit()


func _on_multiline_changed(res: Resource, pname: String, te: TextEdit) -> void:
	res.set(pname, te.text)
	_after_edit()


func _after_edit() -> void:
	_render_dirty()
	_render_status()


# --- dirty ------------------------------------------------------------------------------------------------

func _changed_on(res: Resource) -> int:
	var n := 0
	for b in _bound:
		if b["res"] != res or b["widget"] == null:
			continue
		if res.get(String(b["name"])) != b["loaded"]:
			n += 1
	return n


func _is_dirty() -> bool:
	if _item == null:
		return false
	return _changed_on(_item) > 0 or (_weapon != null and _changed_on(_weapon) > 0)


func _render_dirty() -> void:
	var can := _is_dirty()
	_save_btn.text = "Save Item *" if can else "Save Item"
	_save_btn.disabled = not can
	_save_btn.tooltip_text = SAVE_TIP if can else SAVE_TIP_CLEAN
	_reload_btn.disabled = _item == null


# --- filter -----------------------------------------------------------------------------------------------

func _on_search_changed(_t: String) -> void:
	_apply_filter()


func _apply_filter() -> void:
	var needle := _search.text.strip_edges().to_lower()
	for b in _bound:
		var row: Control = b["row"]
		if row != null:
			row.visible = needle == "" or String(b["haystack"]).contains(needle)


# --- picker + guard ---------------------------------------------------------------------------------------

func _on_picked(idx: int) -> void:
	var intent := PickerRows.resolve_pick(_rows, idx)
	var action := String(intent.get("action", "keep"))
	if action == "keep":
		return
	var target := String(intent.get("value", ""))
	if _is_dirty():
		_ask_unsaved(func() -> void: _apply_pick(action, target))
		return
	_apply_pick(action, target)


func _apply_pick(action: String, target: String) -> void:
	if action == "clear":
		_item = null
		_weapon = null
		_path = ""
		_clear()
		_set_status(MSG_PICK)
		_render_dirty()
		return
	_load_path(target)


func _ask_unsaved(then: Callable) -> void:
	_guard_then = then
	_guard_prev_idx = PickerRows.index_of(_rows, _path)
	if not is_inside_tree():
		_set_status("Save or discard your edits first.", "warn")
		return
	if _guard == null:
		_guard = ConfirmationDialog.new()
		_guard.ok_button_text = "Save"
		_guard.add_button("Discard", true, "discard")
		_guard.confirmed.connect(_on_guard_save)
		_guard.custom_action.connect(_on_guard_custom)
		_guard.canceled.connect(_on_guard_cancel)
		add_child(_guard)
	_guard.dialog_text = "Save changes to %s first?" % _path.get_file()
	_guard.popup_centered()


func _on_guard_save() -> void:
	_on_save()
	_run_guarded()


func _on_guard_custom(action: StringName) -> void:
	if String(action) != "discard":
		return
	if _guard != null:
		_guard.hide()
	_discard()
	_run_guarded()


## Cancel restores the picker BY PATH: an index captured before the popup can point at a different file if the
## filesystem changed while the dialog was up.
func _on_guard_cancel() -> void:
	_guard_then = Callable()
	if _picker != null and _guard_prev_idx >= 0 and _guard_prev_idx < _picker.item_count:
		_picker.select(_guard_prev_idx)


func _run_guarded() -> void:
	var then := _guard_then
	_guard_then = Callable()
	if then.is_valid():
		then.call()


## Discard really discards: the staged values live on the shared cached Resource, so re-reading it with the cache
## REPLACED is the only thing that actually undoes them. Both files, since both may be staged.
func _discard() -> void:
	if _path != "":
		_load_path(_path, true)


func _on_reload_pressed() -> void:
	if _path == "":
		_set_status(MSG_PICK)
		return
	if _is_dirty():
		_ask_unsaved(func() -> void: _discard())
		return
	_discard()


# --- save -------------------------------------------------------------------------------------------------

func _on_save() -> void:
	if _item == null or _path == "":
		_set_status("Nothing open to save.", "warn")
		return
	var item_changes := _changed_on(_item)
	var weapon_changes := 0 if _weapon == null else _changed_on(_weapon)
	var weapon_file := ""
	if weapon_changes > 0:
		var wpath := _weapon.resource_path
		if wpath == "":
			_set_status("Couldn't save the weapon: it has no file of its own. Edit it in the Inspector.", "error")
			return
		var werr := ContentSaveGuard.save_with_backup(_weapon, wpath)
		if werr != OK:
			push_warning("Item Edit: couldn't save %s: %s" % [wpath, error_string(werr)])
			_set_status("Couldn't save %s: %s." % [wpath.get_file(), error_string(werr)], "error")
			return
		weapon_file = wpath.get_file()
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().update_file(wpath)
	if item_changes > 0:
		var err := ContentSaveGuard.save_with_backup(_item, _path)
		if err != OK:
			push_warning("Item Edit: couldn't save %s: %s" % [_path, error_string(err)])
			_set_status("Couldn't save %s: %s." % [_path.get_file(), error_string(err)], "error")
			return
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().update_file(_path)
	for b in _bound:
		if b["widget"] != null:
			b["loaded"] = (b["res"] as Resource).get(String(b["name"]))
	_render_dirty()
	_set_status(Form.save_report(_path.get_file(), item_changes, weapon_file, weapon_changes))


# --- handoff / status -------------------------------------------------------------------------------------

## Duck-typed by `cyber_panel.open_in_editor`. A WeaponData is opened through the item that carries it, because
## the weapon card alone has no name, icon or price — so a designer handed one would be editing half a thing.
func select_path(path: String) -> bool:
	if path == "" or not ResourceLoader.exists(path) or not is_inside_tree():
		return false
	_revealed = true
	var target := path
	var res := ResourceLoader.load(path)
	if res != null and res.get("weapon") == null and not (res is Item):
		target = _item_carrying(path)
		if target == "":
			return false
	_path = target
	_rescan()
	return _item != null


## The item whose `weapon` points at `wpath`, or "" if none does.
func _item_carrying(wpath: String) -> String:
	for it in ItemScan.scan():
		if it == null:
			continue
		var w := it.get("weapon") as Resource
		if w != null and w.resource_path == wpath:
			return it.resource_path
	return ""


func _summary_line() -> String:
	if _item == null:
		return MSG_PICK
	var fields := Form.fields(_item).size()
	if _weapon == null:
		return "%s -- %d fields." % [_path.get_file(), fields]
	var wfile := _weapon.resource_path.get_file()
	return "%s -- %d fields, plus %d on %s." % [
		_path.get_file(), fields, Form.fields(_weapon).size(), wfile if wfile != "" else "its weapon"]


func _set_status(msg: String, kind: String = "") -> void:
	_status_base = msg
	_status_kind = kind
	_render_status()


func _render_status() -> void:
	if _status == null:
		return
	var msg := _status_base
	if _is_dirty():
		msg += " (unsaved changes)"
	_status.text = msg
	_status.tooltip_text = msg
	if _status_kind == "error":
		_status.add_theme_color_override("font_color", ERROR_COLOR)
	elif _status_kind == "warn":
		_status.add_theme_color_override("font_color", WARN_COLOR)
	else:
		_status.remove_theme_color_override("font_color")
