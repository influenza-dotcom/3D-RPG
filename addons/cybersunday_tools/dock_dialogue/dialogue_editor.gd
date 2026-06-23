@tool
extends VBoxContainer

## "Dialogue Edit" bottom-panel tab: author a branching DialogueResource (.tres) WITHOUT the raw inspector.
## Pick a conversation from resources/dialogue/, edit its lines top-to-bottom (the order IS the addressing --
## choices jump to a line by INDEX), edit each line's text and its branch choices (label + a target-line
## OptionButton + the key consequence/gate fields), reorder/add/remove lines and choices, then Save.
##
## THIN GLUE by design: all mutation is in the sibling PURE static ops (dialogue_edit_ops.gd) so the logic is
## GUT-tested without any editor API; this file is just widgets + a folder scan + a wrapped ResourceSaver.save
## (mirroring faction_matrix.gd). NO graph-drag -- plain ItemList / LineEdit / OptionButton / SpinBox + buttons.
## The read-only companion (panel_graph/dialogue_graph.gd) visualizes the same .tres; this is the editor for it.
##
## Field/method names verified against scripts/dialogue/{dialogue_resource,dialogue_line,dialogue_choice}.gd.
## A DialogueLine has NO speaker/voice field -- the speaker's name is supplied by the talking character at
## runtime (DialogueManager), so this editor deliberately does not offer one (it would be dead UI).

const Ops := preload("res://addons/cybersunday_tools/dock_dialogue/dialogue_edit_ops.gd")

## Where conversations live -- scanned to fill the picker. Matches dialogue_graph.gd's DIALOGUE_DIR exactly.
const DIALOGUE_DIR := "res://resources/dialogue"

## Target-OptionButton sentinel ids (kept distinct from any real line index, which is >= 0). These mirror the
## DialogueLine constants without a class_name dependency in this @tool file's const space.
const TARGET_CONTINUE := -2  # DialogueLine.CONTINUE: carry on to the NEXT line (the choice default)
const TARGET_END := -1       # DialogueLine.END: finish the conversation

var _picker: OptionButton = null
var _status: Label = null
var _line_list: ItemList = null
var _line_text: TextEdit = null
var _choice_list: ItemList = null
var _choice_box: VBoxContainer = null

# choice field widgets
var _c_text: LineEdit = null
var _c_target: OptionButton = null
var _c_set_flag: LineEdit = null
var _c_set_flag_value: CheckBox = null
var _c_req_flag: LineEdit = null
var _c_req_flag_value: LineEdit = null
var _c_req_stat: LineEdit = null
var _c_req_value: SpinBox = null
var _c_complete_quest: LineEdit = null
var _c_advance_quest: LineEdit = null
var _c_advance_objective: LineEdit = null

## Parallel to _picker items: the res:// path for each entry.
var _paths: Array[String] = []
## The loaded conversation being edited (null until a pick loads one).
var _res: DialogueResource = null
## True while we are pushing model -> widgets, to suppress the widgets' change signals writing back.
var _syncing := false


func _init() -> void:
	name = "Dialogue Edit"
	add_theme_constant_override("separation", 4)
	_build_top_bar()
	add_child(HSeparator.new())
	_build_body()
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 10)
	add_child(_status)
	_refresh_picker()
	_set_status("Pick a conversation to edit.")


# --- top bar: picker + refresh + save --------------------------------------------------------------------------

func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.tooltip_text = "A DialogueResource .tres to edit. Refresh re-scans %s." % DIALOGUE_DIR
	_picker.item_selected.connect(_on_pick)
	bar.add_child(_picker)

	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.tooltip_text = "Re-scan the dialogue folder."
	refresh.pressed.connect(_refresh_picker)
	bar.add_child(refresh)

	var save := Button.new()
	save.text = "Save"
	save.tooltip_text = "Write the conversation back to its .tres."
	save.pressed.connect(_save)
	bar.add_child(save)
	add_child(bar)


# --- body: lines column | (line text + choices) column ---------------------------------------------------------

func _build_body() -> void:
	var split := HBoxContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Small floor so the bottom panel stays compact on a short display (see CLAUDE.md panel policy).
	split.custom_minimum_size = Vector2(0, 110)
	add_child(split)

	# Left: the lines list + its add/remove/up/down.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(150, 0)
	var lhdr := Label.new()
	lhdr.text = "Lines (order = index)"
	lhdr.add_theme_font_size_override("font_size", 10)
	left.add_child(lhdr)
	_line_list = ItemList.new()
	_line_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_line_list.custom_minimum_size = Vector2(150, 80)
	_line_list.item_selected.connect(_on_line_selected)
	left.add_child(_line_list)
	left.add_child(_row_buttons(_add_line, _remove_line, _line_up, _line_down))
	split.add_child(left)

	# Right: selected line's text, then its choices sub-editor.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var thdr := Label.new()
	thdr.text = "Line text"
	thdr.add_theme_font_size_override("font_size", 10)
	right.add_child(thdr)
	_line_text = TextEdit.new()
	_line_text.custom_minimum_size = Vector2(0, 44)
	_line_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_line_text.text_changed.connect(_on_line_text_changed)
	right.add_child(_line_text)

	right.add_child(_build_choices_block())
	split.add_child(right)


func _build_choices_block() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hdr := Label.new()
	hdr.text = "Choices (branch options)"
	hdr.add_theme_font_size_override("font_size", 10)
	box.add_child(hdr)

	_choice_list = ItemList.new()
	_choice_list.custom_minimum_size = Vector2(0, 50)
	_choice_list.item_selected.connect(_on_choice_selected)
	box.add_child(_choice_list)
	box.add_child(_row_buttons(_add_choice, _remove_choice, _choice_up, _choice_down))

	# The per-choice field editors, hidden until a choice is selected.
	_choice_box = VBoxContainer.new()
	_choice_box.visible = false
	_c_text = _add_field(_choice_box, "Label", LineEdit.new())
	_c_text.text_changed.connect(func(_t): _write_choice())

	_c_target = OptionButton.new()
	_c_target.tooltip_text = "Where picking this jumps. Continue = next line; End = finish; or a specific line."
	_c_target.item_selected.connect(func(_i): _write_choice())
	_labelled(_choice_box, "Target", _c_target)

	_c_set_flag = _add_field(_choice_box, "Set flag", LineEdit.new())
	_c_set_flag.tooltip_text = "GameState flag set when picked (blank = none)."
	_c_set_flag.text_changed.connect(func(_t): _write_choice())
	_c_set_flag_value = CheckBox.new()
	_c_set_flag_value.text = "value = true"
	_c_set_flag_value.toggled.connect(func(_b): _write_choice())
	_choice_box.add_child(_c_set_flag_value)

	_c_req_flag = _add_field(_choice_box, "Req flag", LineEdit.new())
	_c_req_flag.tooltip_text = "Choice is locked unless this GameState flag matches Req flag value (blank = no gate)."
	_c_req_flag.text_changed.connect(func(_t): _write_choice())
	_c_req_flag_value = _add_field(_choice_box, "Req flag value", LineEdit.new())
	_c_req_flag_value.text_changed.connect(func(_t): _write_choice())

	_c_req_stat = _add_field(_choice_box, "Req stat", LineEdit.new())
	_c_req_stat.tooltip_text = "Skill check: locked unless the player's stat >= Req value (blank = no check)."
	_c_req_stat.text_changed.connect(func(_t): _write_choice())
	_c_req_value = SpinBox.new()
	_c_req_value.min_value = 0
	_c_req_value.max_value = 999
	_c_req_value.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Req value", _c_req_value)

	_c_complete_quest = _add_field(_choice_box, "Complete quest id", LineEdit.new())
	_c_complete_quest.tooltip_text = "Quest id completed (turned in) when picked (blank = none)."
	_c_complete_quest.text_changed.connect(func(_t): _write_choice())
	_c_advance_quest = _add_field(_choice_box, "Advance quest id", LineEdit.new())
	_c_advance_quest.text_changed.connect(func(_t): _write_choice())
	_c_advance_objective = _add_field(_choice_box, "Advance objective id", LineEdit.new())
	_c_advance_objective.tooltip_text = "Advance objective by one (needs BOTH Advance quest id + objective id)."
	_c_advance_objective.text_changed.connect(func(_t): _write_choice())

	box.add_child(_choice_box)
	return box


# --- small widget helpers --------------------------------------------------------------------------------------

## A horizontal Add / Remove / Up / Down button row wired to the four supplied callables.
func _row_buttons(on_add: Callable, on_remove: Callable, on_up: Callable, on_down: Callable) -> Control:
	var row := HBoxContainer.new()
	for spec in [["+", on_add], ["-", on_remove], ["Up", on_up], ["Dn", on_down]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		row.add_child(b)
	return row


## Add a "Label: <field>" row to `parent` and return the field (a typed LineEdit), for compact field building.
func _add_field(parent: VBoxContainer, label: String, field: LineEdit) -> LineEdit:
	_labelled(parent, label, field)
	return field


## Add a "Label:" + control pair on one line to `parent`.
func _labelled(parent: VBoxContainer, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label + ":"
	l.add_theme_font_size_override("font_size", 10)
	l.custom_minimum_size = Vector2(96, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


# --- picker / load ---------------------------------------------------------------------------------------------

## Recursively collect *.tres / *.res under `dir` (absolute res:// paths). Safe when the folder is missing.
## Copied from dialogue_graph.gd's scan so the two panels list the SAME conversations.
static func _scan_resources(dir: String, out: Array[String] = []) -> Array[String]:
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if fname == "." or fname == "..":
			fname = da.get_next()
			continue
		var full := dir.path_join(fname)
		if da.current_is_dir():
			_scan_resources(full, out)
		elif fname.ends_with(".tres") or fname.ends_with(".res"):
			out.append(full)
		fname = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


func _refresh_picker() -> void:
	_picker.clear()
	_paths.clear()
	for p in _scan_resources(DIALOGUE_DIR):
		var r := load(p)
		# Only list actual DialogueResources (the folder may hold other .tres alongside).
		if r is DialogueResource:
			_picker.add_item(p.get_file())
			_paths.append(p)
	if _paths.is_empty():
		_picker.add_item("(no DialogueResource in %s)" % DIALOGUE_DIR)
		_picker.set_item_disabled(0, true)


func _on_pick(idx: int) -> void:
	if idx < 0 or idx >= _paths.size():
		return
	var r := load(_paths[idx])
	if not (r is DialogueResource):
		_set_status("Not a DialogueResource: %s" % _paths[idx])
		return
	_res = r
	_rebuild_line_list()
	_select_line(0 if not _res.lines.is_empty() else -1)
	_set_status("Editing %s (%d line(s))." % [_paths[idx], _res.lines.size()])


func _current_path() -> String:
	var idx := _picker.selected
	if idx < 0 or idx >= _paths.size():
		return ""
	return _paths[idx]


# --- lines -----------------------------------------------------------------------------------------------------

func _rebuild_line_list() -> void:
	_line_list.clear()
	if _res == null:
		return
	for i in range(_res.lines.size()):
		var ln: DialogueLine = _res.lines[i]
		_line_list.add_item("%d: %s" % [i, _preview(ln)])


## A one-line preview of a DialogueLine for the list (index, trimmed text, choice count).
func _preview(ln: DialogueLine) -> String:
	if ln == null:
		return "<null>"
	var t := ln.text.replace("\n", " ").strip_edges()
	if t.length() > 40:
		t = t.substr(0, 40) + "…"
	if t.is_empty():
		t = "<empty>"
	var nc := ln.choices.size()
	return t + ("  [%d choice(s)]" % nc if nc > 0 else "")


func _selected_line_index() -> int:
	var sel := _line_list.get_selected_items()
	return sel[0] if sel.size() > 0 else -1


func _selected_line() -> DialogueLine:
	var i := _selected_line_index()
	if _res == null or i < 0 or i >= _res.lines.size():
		return null
	return _res.lines[i]


func _select_line(i: int) -> void:
	if _res != null and i >= 0 and i < _res.lines.size():
		_line_list.select(i)
		_on_line_selected(i)
	else:
		_line_text.text = ""
		_rebuild_choice_list()


func _on_line_selected(_i: int) -> void:
	var ln := _selected_line()
	_syncing = true
	_line_text.text = ln.text if ln != null else ""
	_syncing = false
	_rebuild_choice_list()


func _on_line_text_changed() -> void:
	if _syncing:
		return
	var ln := _selected_line()
	if ln == null:
		return
	ln.text = _line_text.text
	# Refresh just this row's preview text without losing the selection.
	var i := _selected_line_index()
	if i >= 0:
		_line_list.set_item_text(i, "%d: %s" % [i, _preview(ln)])


func _add_line() -> void:
	if _res == null:
		_set_status("Pick a conversation first.")
		return
	Ops.add_line(_res)
	_rebuild_line_list()
	_select_line(_res.lines.size() - 1)


func _remove_line() -> void:
	var i := _selected_line_index()
	if Ops.remove_line(_res, i):
		_rebuild_line_list()
		_select_line(mini(i, _res.lines.size() - 1))
	else:
		_set_status("Select a line to remove.")


func _line_up() -> void:
	_move_line(-1)


func _line_down() -> void:
	_move_line(1)


func _move_line(dir: int) -> void:
	var i := _selected_line_index()
	if Ops.move_line(_res, i, dir):
		_rebuild_line_list()
		_select_line(i + dir)


# --- choices ---------------------------------------------------------------------------------------------------

func _rebuild_choice_list() -> void:
	_choice_list.clear()
	_choice_box.visible = false
	var ln := _selected_line()
	if ln == null:
		return
	for j in range(ln.choices.size()):
		var ch: DialogueChoice = ln.choices[j]
		var label := ch.text.strip_edges()
		_choice_list.add_item("%d: %s" % [j, label if not label.is_empty() else "<no label>"])


func _selected_choice_index() -> int:
	var sel := _choice_list.get_selected_items()
	return sel[0] if sel.size() > 0 else -1


func _selected_choice() -> DialogueChoice:
	var ln := _selected_line()
	var j := _selected_choice_index()
	if ln == null or j < 0 or j >= ln.choices.size():
		return null
	return ln.choices[j]


func _on_choice_selected(_j: int) -> void:
	var ch := _selected_choice()
	if ch == null:
		_choice_box.visible = false
		return
	_choice_box.visible = true
	_populate_target_options()
	_syncing = true
	_c_text.text = ch.text
	_select_target(ch.target)
	_c_set_flag.text = String(ch.set_flag)
	_c_set_flag_value.button_pressed = ch.set_flag_value
	_c_req_flag.text = String(ch.required_flag)
	_c_req_flag_value.text = ch.required_flag_value
	_c_req_stat.text = String(ch.required_stat)
	_c_req_value.value = ch.required_value
	_c_complete_quest.text = String(ch.complete_quest_id)
	_c_advance_quest.text = String(ch.advance_quest_id)
	_c_advance_objective.text = String(ch.advance_objective_id)
	_syncing = false


## Fill the target OptionButton: Continue / End sentinels, then one entry per real line index.
func _populate_target_options() -> void:
	_c_target.clear()
	_c_target.add_item("Continue (next line)", TARGET_CONTINUE)
	_c_target.add_item("End conversation", TARGET_END)
	if _res != null:
		for i in range(_res.lines.size()):
			_c_target.add_item("-> line %d" % i, i)


## Select the OptionButton entry whose item-id == `target` (ids are the sentinels / line indices).
func _select_target(target: int) -> void:
	for idx in range(_c_target.item_count):
		if _c_target.get_item_id(idx) == target:
			_c_target.select(idx)
			return
	# Target points past the current line count (dangling) -- leave on Continue and note it.
	_c_target.select(0)


## Push every choice widget back onto the selected DialogueChoice. Guarded by _syncing so model->widget pushes
## (in _on_choice_selected) don't recurse. Refreshes the choice-row + line-row previews after a label change.
func _write_choice() -> void:
	if _syncing:
		return
	var ch := _selected_choice()
	if ch == null:
		return
	ch.text = _c_text.text
	var ti := _c_target.selected
	if ti >= 0:
		ch.target = _c_target.get_item_id(ti)
	ch.set_flag = StringName(_c_set_flag.text)
	ch.set_flag_value = _c_set_flag_value.button_pressed
	ch.required_flag = StringName(_c_req_flag.text)
	ch.required_flag_value = _c_req_flag_value.text
	ch.required_stat = StringName(_c_req_stat.text)
	ch.required_value = int(_c_req_value.value)
	ch.complete_quest_id = StringName(_c_complete_quest.text)
	ch.advance_quest_id = StringName(_c_advance_quest.text)
	ch.advance_objective_id = StringName(_c_advance_objective.text)
	var j := _selected_choice_index()
	if j >= 0:
		var label := ch.text.strip_edges()
		_choice_list.set_item_text(j, "%d: %s" % [j, label if not label.is_empty() else "<no label>"])
	# A line's preview shows its choice count, which is unchanged here, but a label edit is worth reflecting.
	var li := _selected_line_index()
	if li >= 0:
		_line_list.set_item_text(li, "%d: %s" % [li, _preview(_selected_line())])


func _add_choice() -> void:
	var ln := _selected_line()
	if ln == null:
		_set_status("Select a line first.")
		return
	Ops.add_choice(ln)
	_rebuild_choice_list()
	_choice_list.select(ln.choices.size() - 1)
	_on_choice_selected(ln.choices.size() - 1)
	# The line preview gained a choice -- refresh its row.
	var li := _selected_line_index()
	if li >= 0:
		_line_list.set_item_text(li, "%d: %s" % [li, _preview(ln)])


func _remove_choice() -> void:
	var ln := _selected_line()
	var j := _selected_choice_index()
	if Ops.remove_choice(ln, j):
		_rebuild_choice_list()
		var li := _selected_line_index()
		if li >= 0:
			_line_list.set_item_text(li, "%d: %s" % [li, _preview(ln)])
	else:
		_set_status("Select a choice to remove.")


func _choice_up() -> void:
	_move_choice(-1)


func _choice_down() -> void:
	_move_choice(1)


func _move_choice(dir: int) -> void:
	var ln := _selected_line()
	var j := _selected_choice_index()
	if Ops.move_choice(ln, j, dir):
		_rebuild_choice_list()
		_choice_list.select(j + dir)
		_on_choice_selected(j + dir)


# --- save ------------------------------------------------------------------------------------------------------

## Persist the edited conversation to its .tres. Save failure is REPORTED on the status label, never silently
## swallowed (mirrors faction_matrix.gd). Then nudge the editor's FileSystem so it re-imports the change.
func _save() -> void:
	if _res == null:
		_set_status("Nothing to save -- pick a conversation first.")
		return
	var path := _current_path()
	if path.is_empty():
		path = _res.resource_path
	if path.is_empty():
		_set_status("Cannot save: the resource has no path.")
		return
	var err := ResourceSaver.save(_res, path)
	if err != OK:
		_set_status("FAILED to save %s (err %d) -- change NOT persisted." % [path, err])
		return
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(path)
	_set_status("Saved %s" % path)


func _set_status(msg: String) -> void:
	if _status != null:
		_status.text = msg
