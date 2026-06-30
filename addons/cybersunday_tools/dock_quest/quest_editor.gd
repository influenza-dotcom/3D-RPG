@tool
extends VBoxContainer

## QUEST EDIT dock: edit an authored Quest's headline fields, rewards, chaining, and its ordered objectives list
## WITHOUT the raw inspector. A resource picker (scans resources/quests/) loads a Quest .tres into a set of plain
## widgets; an objectives ItemList + Add/Remove/Up/Down + a per-objective editor (type OptionButton, target_id,
## required_count SpinBox, description) edits the list; Save writes the .tres back (ResourceSaver.save +
## FileSystem.update_file) so it persists.
##
## ALL list mutation lives in quest_edit_ops.gd (pure + GUT-tested); this file is THIN editor glue — read a
## widget, call an op, re-render, and on Save push the in-memory edits onto the Quest and persist. Field/method
## names mirror scripts/quests/quest.gd + quest_objective.gd EXACTLY.

const QuestOps := preload("res://addons/cybersunday_tools/dock_quest/quest_edit_ops.gd")

const QUESTS_DIR := "res://resources/quests/"

## The QuestObjective.Type enum names, in ENUM ORDER, for the type OptionButton. The OptionButton item INDEX is
## the enum int (KILL=0 .. FLAG=5), so selecting item i sets type = i directly. Keep this in sync with
## quest_objective.gd's `enum Type { KILL, TALK, PICKUP, ENTER_AREA, USE_ITEM, FLAG }`.
const TYPE_LABELS := ["KILL", "TALK", "PICKUP", "ENTER_AREA", "USE_ITEM", "FLAG"]

var _quest: Quest = null
var _quest_path: String = ""

var _picker: OptionButton = null
var _title_edit: LineEdit = null
var _desc_edit: TextEdit = null
var _money_spin: SpinBox = null
var _xp_spin: SpinBox = null
var _prereq_edit: LineEdit = null

var _obj_list: ItemList = null
var _obj_type: OptionButton = null
var _obj_target: LineEdit = null
var _obj_count: SpinBox = null
var _obj_desc: LineEdit = null

var _status: Label = null

var _quest_paths: PackedStringArray = PackedStringArray()


func _init() -> void:
	name = "Quest Edit"
	add_theme_constant_override("separation", 4)
	custom_minimum_size = Vector2(0, 110)  # small floor so the panel can shrink on a short display

	var title := Label.new()
	title.text = "Quest Editor"
	add_child(title)

	# --- picker row -------------------------------------------------------------------------------------------
	var picker_row := HBoxContainer.new()
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.item_selected.connect(_on_pick)
	picker_row.add_child(_picker)
	var reload := Button.new()
	reload.text = "Reload"
	reload.pressed.connect(_rescan_quests)
	picker_row.add_child(reload)
	add_child(picker_row)

	add_child(HSeparator.new())

	# --- headline fields --------------------------------------------------------------------------------------
	# Each headline widget writes through to the live Quest on change (mirroring the objective widgets below), so
	# switching quests in the picker or hitting Reload can't silently DISCARD an unsaved headline edit. Save then
	# just persists the already-applied in-memory state.
	_title_edit = _labeled_line("Title")
	_title_edit.text_changed.connect(_on_title_changed)
	add_child(_field_label("Description"))
	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size = Vector2(0, 40)
	_desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desc_edit.text_changed.connect(_on_desc_changed)
	add_child(_desc_edit)

	_money_spin = _labeled_spin("Reward money", 0.0, 1000000.0, 1.0)
	_money_spin.value_changed.connect(_on_money_changed)
	_xp_spin = _labeled_spin("Reward XP", 0.0, 1000000.0, 1.0)
	_xp_spin.value_changed.connect(_on_xp_changed)
	_prereq_edit = _labeled_line("Prereq quest id")
	_prereq_edit.text_changed.connect(_on_prereq_changed)

	add_child(HSeparator.new())

	# --- objectives list + reorder ----------------------------------------------------------------------------
	add_child(_field_label("Objectives"))
	_obj_list = ItemList.new()
	_obj_list.custom_minimum_size = Vector2(0, 80)
	_obj_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_list.item_selected.connect(_on_obj_selected)
	add_child(_obj_list)

	var btn_row := HBoxContainer.new()
	btn_row.add_child(_btn("Add", _on_add))
	btn_row.add_child(_btn("Remove", _on_remove))
	btn_row.add_child(_btn("Up", _on_up))
	btn_row.add_child(_btn("Down", _on_down))
	add_child(btn_row)

	# --- selected-objective editor ----------------------------------------------------------------------------
	_obj_type = OptionButton.new()
	for i in range(TYPE_LABELS.size()):
		_obj_type.add_item(TYPE_LABELS[i], i)
	_obj_type.item_selected.connect(_on_obj_type_changed)
	add_child(_pair("Type", _obj_type))

	_obj_target = LineEdit.new()
	_obj_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_target.text_changed.connect(_on_obj_target_changed)
	add_child(_pair("Target id", _obj_target))

	_obj_count = SpinBox.new()
	_obj_count.min_value = 1
	_obj_count.max_value = 9999
	_obj_count.step = 1
	_obj_count.value_changed.connect(_on_obj_count_changed)
	add_child(_pair("Required count", _obj_count))

	_obj_desc = LineEdit.new()
	_obj_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_desc.text_changed.connect(_on_obj_desc_changed)
	add_child(_pair("Obj. description", _obj_desc))

	# --- save + status ----------------------------------------------------------------------------------------
	add_child(HSeparator.new())
	add_child(_btn("Save Quest", _on_save))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 10)
	add_child(_status)

	_rescan_quests()


# --- widget builders (pure UI) ---------------------------------------------------------------------------------

func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 10)
	return l

## A "Label: control" row; returns the row so it can be added, but callers needing the control build it inline.
func _pair(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(96, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _labeled_line(label_text: String) -> LineEdit:
	var e := LineEdit.new()
	add_child(_pair(label_text, e))
	return e

func _labeled_spin(label_text: String, min_v: float, max_v: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	add_child(_pair(label_text, s))
	return s

func _btn(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


# --- picker / load ---------------------------------------------------------------------------------------------

## Scan resources/quests/ for .tres files and refill the picker. Loads the first quest if any. Safe when the
## folder doesn't exist yet (a fresh project) — the picker just shows an empty hint.
func _rescan_quests() -> void:
	_quest_paths = _scan_quest_paths()
	_picker.clear()
	if _quest_paths.is_empty():
		_picker.add_item("(no quests in %s)" % QUESTS_DIR)
		_picker.disabled = true
		_clear_loaded()
		_set_status("No Quest .tres found. Create one in the Content tab first.")
		return
	_picker.disabled = false
	for p in _quest_paths:
		_picker.add_item(p.get_file())
	_picker.select(0)
	_load_quest(_quest_paths[0])

## The sorted list of .tres paths under QUESTS_DIR (res:// path, files only). Empty if the dir is absent.
func _scan_quest_paths() -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(QUESTS_DIR):
		return out
	var names := DirAccess.get_files_at(QUESTS_DIR)
	for n in names:
		if n.get_extension().to_lower() == "tres":
			out.append(QUESTS_DIR + n)
	out.sort()
	return out


func _on_pick(idx: int) -> void:
	if idx < 0 or idx >= _quest_paths.size():
		return
	_load_quest(_quest_paths[idx])


func _load_quest(path: String) -> void:
	var res := load(path)
	if res == null or not (res is Quest):
		_set_status("Failed to load a Quest from %s" % path)
		_clear_loaded()
		return
	_quest = res
	_quest_path = path
	# Headline fields -> widgets. The spins use set_value_no_signal so loading a quest doesn't fire the
	# write-through handlers (LineEdit/TextEdit .text assignment doesn't emit, so those are inert already).
	_title_edit.text = _quest.title
	_desc_edit.text = _quest.description
	_money_spin.set_value_no_signal(_quest.reward_money)
	_xp_spin.set_value_no_signal(_quest.reward_xp)
	_prereq_edit.text = String(_quest.prereq_quest_id)
	_refresh_obj_list()
	_select_obj(0 if _quest.objectives.size() > 0 else -1)
	_set_status("Loaded %s (%d objective(s))." % [path.get_file(), _quest.objectives.size()])


func _clear_loaded() -> void:
	_quest = null
	_quest_path = ""
	_title_edit.text = ""
	_desc_edit.text = ""
	_money_spin.set_value_no_signal(0.0)
	_xp_spin.set_value_no_signal(0.0)
	_prereq_edit.text = ""
	if _obj_list != null:
		_obj_list.clear()
	_load_obj_editor(null)


# --- headline edit handlers (write back to the live Quest, like the objective handlers) ------------------------
# Guard on _quest == null so a clear/load that touches a widget is a no-op when nothing is loaded.

func _on_title_changed(text: String) -> void:
	if _quest == null:
		return
	_quest.title = text

func _on_desc_changed() -> void:  # TextEdit.text_changed has no argument
	if _quest == null:
		return
	_quest.description = _desc_edit.text

func _on_money_changed(value: float) -> void:
	if _quest == null:
		return
	_quest.reward_money = value

func _on_xp_changed(value: float) -> void:
	if _quest == null:
		return
	_quest.reward_xp = value

func _on_prereq_changed(text: String) -> void:
	if _quest == null:
		return
	_quest.prereq_quest_id = StringName(text.strip_edges())


# --- objectives list -------------------------------------------------------------------------------------------

func _refresh_obj_list() -> void:
	_obj_list.clear()
	if _quest == null:
		return
	for i in range(_quest.objectives.size()):
		var o: QuestObjective = _quest.objectives[i]
		_obj_list.add_item(_obj_summary(i, o))

func _obj_summary(i: int, o: QuestObjective) -> String:
	if o == null:
		return "%d: <null>" % i
	var type_name: String = TYPE_LABELS[o.type] if o.type >= 0 and o.type < TYPE_LABELS.size() else "?"
	var tgt := String(o.target_id)
	return "%d. [%s] %s x%d" % [i + 1, type_name, tgt if not tgt.is_empty() else "(no target)", o.required_count]


func _selected_index() -> int:
	var sel := _obj_list.get_selected_items()
	return sel[0] if sel.size() > 0 else -1

func _select_obj(index: int) -> void:
	if _quest == null or index < 0 or index >= _quest.objectives.size():
		_load_obj_editor(null)
		return
	_obj_list.select(index)
	_load_obj_editor(_quest.objectives[index])


func _on_obj_selected(index: int) -> void:
	if _quest == null or index < 0 or index >= _quest.objectives.size():
		_load_obj_editor(null)
		return
	_load_obj_editor(_quest.objectives[index])


## Mirror an objective's fields into the per-objective editor widgets (or blank + disable on null).
func _load_obj_editor(o: QuestObjective) -> void:
	var has := o != null
	_obj_type.disabled = not has
	_obj_target.editable = has
	_obj_count.editable = has
	_obj_desc.editable = has
	if not has:
		_obj_type.select(-1)
		_obj_target.text = ""
		_obj_count.set_value_no_signal(1)
		_obj_desc.text = ""
		return
	_obj_type.select(o.type)
	_obj_target.text = String(o.target_id)
	_obj_count.set_value_no_signal(o.required_count)
	_obj_desc.text = o.description


# --- objective edit handlers (write back to the live QuestObjective) -------------------------------------------

func _current_obj() -> QuestObjective:
	if _quest == null:
		return null
	var i := _selected_index()
	if i < 0 or i >= _quest.objectives.size():
		return null
	return _quest.objectives[i]

func _on_obj_type_changed(idx: int) -> void:
	var o := _current_obj()
	if o == null or idx < 0 or idx >= TYPE_LABELS.size():
		return
	o.type = idx
	_refresh_summary_for_selected()

func _on_obj_target_changed(text: String) -> void:
	var o := _current_obj()
	if o == null:
		return
	o.target_id = StringName(text)
	_refresh_summary_for_selected()

func _on_obj_count_changed(value: float) -> void:
	var o := _current_obj()
	if o == null:
		return
	o.required_count = int(value)
	_refresh_summary_for_selected()

func _on_obj_desc_changed(text: String) -> void:
	var o := _current_obj()
	if o == null:
		return
	o.description = text

## Update the ItemList row text for the selected objective in place (keeps selection / focus stable while typing).
func _refresh_summary_for_selected() -> void:
	var i := _selected_index()
	if i < 0 or i >= _quest.objectives.size():
		return
	_obj_list.set_item_text(i, _obj_summary(i, _quest.objectives[i]))


# --- list ops (delegate to the pure ops, then re-render) -------------------------------------------------------

func _on_add() -> void:
	if _quest == null:
		_set_status("Load a quest first.")
		return
	if QuestOps.add_objective(_quest):
		_refresh_obj_list()
		_select_obj(_quest.objectives.size() - 1)
		_set_status("Added objective %d." % _quest.objectives.size())

func _on_remove() -> void:
	if _quest == null:
		return
	var i := _selected_index()
	if QuestOps.remove_objective(_quest, i):
		_refresh_obj_list()
		_select_obj(mini(i, _quest.objectives.size() - 1))
		_set_status("Removed objective %d." % (i + 1))

func _on_up() -> void:
	_move(-1)

func _on_down() -> void:
	_move(1)

func _move(dir: int) -> void:
	if _quest == null:
		return
	var i := _selected_index()
	if QuestOps.move_objective(_quest, i, dir):
		_refresh_obj_list()
		_select_obj(i + dir)


# --- save ------------------------------------------------------------------------------------------------------

## Re-sync the headline widgets onto the Quest (a defensive belt-and-suspenders — they already write through on
## edit, like the objective widgets), then ResourceSaver.save the .tres and tell the FileSystem it changed. A save
## failure is REPORTED, never silently swallowed.
func _on_save() -> void:
	if _quest == null or _quest_path.is_empty():
		_set_status("Nothing to save — load a quest first.")
		return
	_quest.title = _title_edit.text
	_quest.description = _desc_edit.text
	_quest.reward_money = _money_spin.value
	_quest.reward_xp = _xp_spin.value
	_quest.prereq_quest_id = StringName(_prereq_edit.text.strip_edges())
	var err := ResourceSaver.save(_quest, _quest_path)
	if err != OK:
		_set_status("FAILED to save %s (err %d) — change NOT persisted." % [_quest_path, err])
		return
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(_quest_path)
	_set_status("Saved %s" % _quest_path)


func _set_status(msg: String) -> void:
	if _status != null:
		_status.text = msg
