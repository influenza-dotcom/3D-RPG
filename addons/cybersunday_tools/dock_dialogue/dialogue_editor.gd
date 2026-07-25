@tool
extends VBoxContainer

## "Dialogue Edit" bottom-panel tab: author a branching DialogueResource (.tres) WITHOUT the raw inspector.
## Pick a conversation from resources/dialogue/, edit its lines top-to-bottom (the order IS the addressing --
## choices jump to a line by INDEX), edit each line's text and its branch choices (label + target-line & fail-target
## OptionButtons + the FULL gate set [stat / flag / faction+reputation / perk / item / quest-state] + the KEY write
## consequence fields [set_flag, complete/advance quest], reorder/add/remove lines and choices, then Save.
## (The remaining write consequences -- give_item_id, give_money, start_quest_on_choice, reward_reputation,
## aggro_speaker -- are NOT surfaced here; author those on the .tres in the raw inspector.)
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
const ContentSaveGuard := preload("res://addons/cybersunday_tools/core/content_save_guard.gd")

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
var _line_reveals_name: CheckBox = null
var _choice_list: ItemList = null
var _choice_box: VBoxContainer = null

# choice field widgets
var _c_text: LineEdit = null
var _c_target: OptionButton = null
var _c_target_on_fail: OptionButton = null
var _c_set_flag: LineEdit = null
var _c_set_flag_value: CheckBox = null
var _c_req_flag: LineEdit = null
var _c_req_flag_value: LineEdit = null
var _c_req_stat: LineEdit = null
var _c_req_value: SpinBox = null
# WR-1/WR-3 gate widgets — the same gate set panel_graph/graph_data.gd:_choice_has_gate enumerates.
var _c_req_faction: LineEdit = null
var _c_req_reputation: SpinBox = null
var _c_req_perk: LineEdit = null
var _c_req_item: LineEdit = null
var _c_req_item_count: SpinBox = null
var _c_req_quest: LineEdit = null
var _c_req_quest_state: OptionButton = null
var _c_complete_quest: LineEdit = null
var _c_advance_quest: LineEdit = null
var _c_advance_objective: LineEdit = null

## Parallel to _picker items: the res:// path for each entry.
var _paths: Array[String] = []
## The loaded conversation being edited (null until a pick loads one).
var _res: DialogueResource = null
## The res:// path _res was loaded FROM. Save targets this, not the (possibly re-sorted) picker index.
var _loaded_path: String = ""
## True while we are pushing model -> widgets, to suppress the widgets' change signals writing back.
var _syncing := false


## PL6: lazy first-reveal latch — the dialogue-folder scan runs on first reveal, not at panel construction.
var _revealed := false


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
	_set_status("Pick a conversation to edit.")
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan the dialogue folder on first reveal, not at panel construction (mirrors content_browser)


## Lazy first-reveal: scan the dialogue folder + fill the picker ONCE, the first time the tab is shown (not at construction).
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_refresh_picker()


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

	# Right: selected line's text, then its choices sub-editor. The choice editor stacks ~19 field rows (~500px),
	# which far exceeds this short bottom panel — so the whole right column lives in a ScrollContainer. Without it the
	# lower choice fields (Fail target, Complete/Advance quest, Advance objective) clip off the bottom edge with no way
	# to reach them (the content_dock.gd / scene_placer.gd pattern). The left lines list keeps the split's full height.
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # fields fill the width; only scroll vertically
	split.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)
	var thdr := Label.new()
	thdr.text = "Line text"
	thdr.add_theme_font_size_override("font_size", 10)
	right.add_child(thdr)
	_line_text = TextEdit.new()
	_line_text.custom_minimum_size = Vector2(0, 44)
	_line_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_line_text.text_changed.connect(_on_line_text_changed)
	right.add_child(_line_text)

	# "Stranger until introduced": tick on the line where the speaker says their name — from then on the NPC shows
	# their real name instead of "Stranger" everywhere (dialogue label, look-at, corpse, ...). See GameState.reveal_name.
	_line_reveals_name = CheckBox.new()
	_line_reveals_name.text = "Reveals speaker's name (introduces them)"
	_line_reveals_name.tooltip_text = "When this line plays, the NPC is no longer a \"Stranger\" — their real display_name shows from here on (persists across saves). No-op on an inanimate speaker."
	_line_reveals_name.toggled.connect(_on_line_reveals_name_toggled)
	right.add_child(_line_reveals_name)

	right.add_child(_build_choices_block())


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

	# The remaining WR-1/WR-3 gates (faction / perk / item / quest) the raw inspector groups under the ungrouped
	# gate exports. Kept contiguous with the flag/stat gates above; the write consequences stay below.
	_c_req_faction = _add_field(_choice_box, "Req faction id", LineEdit.new())
	_c_req_faction.tooltip_text = "Reputation gate: locked unless the player's standing with this faction id is >= Req reputation (blank = no gate)."
	_c_req_faction.text_changed.connect(func(_t): _write_choice())
	_c_req_reputation = SpinBox.new()
	_c_req_reputation.min_value = -9999
	_c_req_reputation.max_value = 9999
	_c_req_reputation.step = 0.01  # reputation is a float standing, so allow fractional / negative thresholds
	_c_req_reputation.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Req reputation", _c_req_reputation)

	_c_req_perk = _add_field(_choice_box, "Req perk id", LineEdit.new())
	_c_req_perk.tooltip_text = "Perk gate: locked unless the player has LEARNED this perk id (blank = no gate)."
	_c_req_perk.text_changed.connect(func(_t): _write_choice())

	_c_req_item = _add_field(_choice_box, "Req item id", LineEdit.new())
	_c_req_item.tooltip_text = "Item gate: locked unless the player CARRIES >= Req item count of this item id (a check, not consumed). Blank = no gate."
	_c_req_item.text_changed.connect(func(_t): _write_choice())
	_c_req_item_count = SpinBox.new()
	_c_req_item_count.min_value = 0
	_c_req_item_count.max_value = 999
	_c_req_item_count.value_changed.connect(func(_v): _write_choice())
	_labelled(_choice_box, "Req item count", _c_req_item_count)

	_c_req_quest = _add_field(_choice_box, "Req quest id", LineEdit.new())
	_c_req_quest.tooltip_text = "Quest gate: locked unless quest id is in Req quest state (blank = no gate)."
	_c_req_quest.text_changed.connect(func(_t): _write_choice())
	_c_req_quest_state = OptionButton.new()
	_c_req_quest_state.tooltip_text = "Which tracked state the quest gate checks: Any (merely known) / Active / Completed / Failed."
	# QuestGate enum (ANY, ACTIVE, COMPLETED, FAILED): item ids ARE the enum values, so read/write map by id, not order.
	_c_req_quest_state.add_item("Any (known)", DialogueChoice.QuestGate.ANY)
	_c_req_quest_state.add_item("Active", DialogueChoice.QuestGate.ACTIVE)
	_c_req_quest_state.add_item("Completed", DialogueChoice.QuestGate.COMPLETED)
	_c_req_quest_state.add_item("Failed", DialogueChoice.QuestGate.FAILED)
	_c_req_quest_state.item_selected.connect(func(_i): _write_choice())
	_labelled(_choice_box, "Req quest state", _c_req_quest_state)

	# A gated choice stays SELECTABLE (FNV-style): a FAILED check branches here. Mirrors `target` exactly
	# (Continue / End sentinels + one entry per line index). Ignored at runtime when the choice has no gate.
	_c_target_on_fail = OptionButton.new()
	_c_target_on_fail.tooltip_text = "Where a FAILED gate check leads. End = finish; Continue = next line; or a specific line. Ignored when the choice has no gate."
	_c_target_on_fail.item_selected.connect(func(_i): _write_choice())
	_labelled(_choice_box, "Fail target", _c_target_on_fail)

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
	else:
		# OptionButton.select() doesn't emit item_selected, so load index 0 ourselves
		# (mirrors quest_editor._rescan_quests / loot_editor._reload_tables). The Refresh button reloads too.
		_picker.select(0)
		_on_pick(0)


func _on_pick(idx: int) -> void:
	if idx < 0 or idx >= _paths.size():
		return
	var r := load(_paths[idx])
	if not (r is DialogueResource):
		_set_status("Not a DialogueResource: %s" % _paths[idx])
		return
	_res = r
	_loaded_path = _paths[idx]
	_rebuild_line_list()
	_select_line(0 if not _res.lines.is_empty() else -1)
	_set_status("Editing %s (%d line(s))." % [_paths[idx], _res.lines.size()])


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
		_line_reveals_name.button_pressed = false
		_rebuild_choice_list()


func _on_line_selected(_i: int) -> void:
	var ln := _selected_line()
	_syncing = true
	_line_text.text = ln.text if ln != null else ""
	_line_reveals_name.button_pressed = ln.reveals_name if ln != null else false
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


## In-memory only (like the line text); the change reaches disk on Save. See DialogueLine.reveals_name.
func _on_line_reveals_name_toggled(pressed: bool) -> void:
	if _syncing:
		return
	var ln := _selected_line()
	if ln != null:
		ln.reveals_name = pressed


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
	_populate_target_options(_c_target)
	_populate_target_options(_c_target_on_fail)
	_syncing = true
	_c_text.text = ch.text
	_select_target(_c_target, ch.target)
	_select_target(_c_target_on_fail, ch.target_on_fail)
	_c_set_flag.text = String(ch.set_flag)
	_c_set_flag_value.button_pressed = ch.set_flag_value
	_c_req_flag.text = String(ch.required_flag)
	_c_req_flag_value.text = ch.required_flag_value
	_c_req_stat.text = String(ch.required_stat)
	_c_req_value.value = ch.required_value
	_c_req_faction.text = ch.required_faction_id
	_c_req_reputation.value = ch.required_reputation
	_c_req_perk.text = String(ch.required_perk_id)
	_c_req_item.text = String(ch.required_item_id)
	_c_req_item_count.value = ch.required_item_count
	_c_req_quest.text = String(ch.required_quest_id)
	_select_option_by_id(_c_req_quest_state, ch.required_quest_state)
	_c_complete_quest.text = String(ch.complete_quest_id)
	_c_advance_quest.text = String(ch.advance_quest_id)
	_c_advance_objective.text = String(ch.advance_objective_id)
	_syncing = false


## Fill a target OptionButton (`target` or `target_on_fail`): Continue / End sentinels, then one entry per real
## line index. Shared by both target dropdowns so the two stay identical.
func _populate_target_options(btn: OptionButton) -> void:
	btn.clear()
	btn.add_item("Continue (next line)", TARGET_CONTINUE)
	btn.add_item("End conversation", TARGET_END)
	if _res != null:
		for i in range(_res.lines.size()):
			btn.add_item("-> line %d" % i, i)


## Select `btn`'s entry whose item-id == `target` (ids are the sentinels / line indices).
func _select_target(btn: OptionButton, target: int) -> void:
	if _select_option_by_id(btn, target):
		return
	# Target points past the current line count (dangling). Add a transient item carrying the REAL id so the
	# next _write_choice() round-trips it back unchanged instead of silently rewriting it to Continue.
	btn.add_item("(dangling -> %d)" % target, target)
	btn.select(btn.item_count - 1)
	_set_status("A choice target -> line %d is out of range (only %d line(s)); preserved -- fix or repoint it." % [target, _res.lines.size() if _res != null else 0])


## Select the OptionButton entry whose item-id == `id`; returns false when no entry carries that id (so the
## caller can decide how to handle it). Used for both the target dropdowns and the QuestGate enum dropdown.
func _select_option_by_id(btn: OptionButton, id: int) -> bool:
	for idx in range(btn.item_count):
		if btn.get_item_id(idx) == id:
			btn.select(idx)
			return true
	return false


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
	var fi := _c_target_on_fail.selected
	if fi >= 0:
		ch.target_on_fail = _c_target_on_fail.get_item_id(fi)
	ch.set_flag = StringName(_c_set_flag.text)
	ch.set_flag_value = _c_set_flag_value.button_pressed
	ch.required_flag = StringName(_c_req_flag.text)
	ch.required_flag_value = _c_req_flag_value.text
	ch.required_stat = StringName(_c_req_stat.text)
	ch.required_value = int(_c_req_value.value)
	ch.required_faction_id = _c_req_faction.text
	ch.required_reputation = _c_req_reputation.value
	ch.required_perk_id = StringName(_c_req_perk.text)
	ch.required_item_id = StringName(_c_req_item.text)
	ch.required_item_count = int(_c_req_item_count.value)
	ch.required_quest_id = StringName(_c_req_quest.text)
	var qi := _c_req_quest_state.selected
	if qi >= 0:
		ch.required_quest_state = _c_req_quest_state.get_item_id(qi)
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
	# Save to the path _res was LOADED from, not the picker index -- a Refresh can re-sort _paths
	# without reloading _res, so _picker.selected may now point at a DIFFERENT .tres.
	var path := _loaded_path
	if path.is_empty():
		path = _res.resource_path
	if path.is_empty():
		_set_status("Cannot save: the resource has no path.")
		return
	var err := ContentSaveGuard.save_with_backup(_res, path)  # PL5: prior bytes -> .tres.bak first, so a mis-save is recoverable
	if err != OK:
		_set_status("FAILED to save %s (err %d) -- change NOT persisted." % [path, err])
		return
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(path)
	_set_status("Saved %s" % path)


func _set_status(msg: String) -> void:
	if _status != null:
		_status.text = msg
