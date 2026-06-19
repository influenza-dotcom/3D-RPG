extends CanvasLayer
## QuestJournal — a read-only QUEST LOG screen, opened with its own key (InputManager.action_journal, default J).
## Code-built + registered as an autoload, mirroring StatsScreen / ReputationScreen, and a fourth member of the
## Pip-Boy tab group (Inventory / Stats / Reputation / Journal). Lists ACTIVE quests (title + each objective with
## a checkbox + progress) and COMPLETED ones. Like the other player menus it does NOT pause the world; it frees
## the mouse (restored on close). Refreshes live off GameState.quest_started / objective_advanced / quest_completed.

signal opened
signal closed

const PANEL_MARGIN := 0.12  ## same border as the other inventory-style screens — shared chrome
const PlayerMenus := preload("res://scripts/ui/player_menus.gd")  ## tab-group helper

var _root: Control
var _list: VBoxContainer
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	layer = 120                                  # above the HUD, just under OptionsMenu (128)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

func toggle() -> void:
	if _is_open:
		close()
	else:
		open()

func open() -> void:
	# Block only the NON-player modals; the sibling player menus instead SWITCH to us via close_others.
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() \
			or LootScreen.is_open() or ShopScreen.is_open() or HealScreen.is_open() or LevelUpScreen.is_open():
		return
	PlayerMenus.close_others(self)  # switch off a sibling player menu if one is up
	_is_open = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # free the cursor; the world keeps running (no pause)
	if not GameState.quest_started.is_connected(_on_quests_changed):
		GameState.quest_started.connect(_on_quests_changed)
		GameState.objective_advanced.connect(_on_objective_changed)
		GameState.quest_completed.connect(_on_quests_changed)
	_rebuild()
	_root.visible = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	if GameState.quest_started.is_connected(_on_quests_changed):
		GameState.quest_started.disconnect(_on_quests_changed)
		GameState.objective_advanced.disconnect(_on_objective_changed)
		GameState.quest_completed.disconnect(_on_quests_changed)
	Input.mouse_mode = _prev_mouse_mode
	closed.emit()

func _on_quests_changed(_quest) -> void:
	if _is_open:
		_rebuild()

func _on_objective_changed(_quest, _objective) -> void:
	if _is_open:
		_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputManager.action_journal):
		toggle()
		get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	MenuStyle.apply(_root)
	add_child(_root)
	_root.add_child(MenuStyle.make_dim())

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = PANEL_MARGIN
	panel.anchor_top = PANEL_MARGIN
	panel.anchor_right = 1.0 - PANEL_MARGIN
	panel.anchor_bottom = 1.0 - PANEL_MARGIN
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	vbox.add_child(PlayerMenus.build_tab_strip("Journal"))
	vbox.add_child(MenuStyle.make_title("Journal"))
	vbox.add_child(MenuStyle.make_hint("Your active and completed quests."))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_list)

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var active_ids := GameState.active_quest_ids()
	var completed := GameState.completed_quests()
	if active_ids.is_empty() and completed.is_empty():
		_list.add_child(MenuStyle.make_hint("No quests yet."))
		return
	for qid in active_ids:
		var quest: Quest = GameState.active_quest(qid)
		if quest != null:
			_list.add_child(_make_quest_block(qid, quest, false))
	for quest in completed:
		_list.add_child(_make_quest_block(quest.id, quest, true))

## One quest block: a title header (dimmed when completed) + a line per objective.
func _make_quest_block(quest_id: StringName, quest: Quest, done: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var head := Label.new()
	head.text = ("%s   (done)" % quest.title) if done else quest.title
	head.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)
	head.add_theme_color_override(&"font_color", MenuStyle.skin.text_dim_color if done else MenuStyle.skin.accent_color)
	box.add_child(head)
	for obj in quest.objectives:
		if obj == null:
			continue
		var line := Label.new()
		var od := done or GameState.is_objective_done(quest_id, obj.id)
		line.text = objective_line(obj, od, GameState.objective_progress(quest_id, obj.id))
		line.add_theme_color_override(&"font_color", MenuStyle.skin.text_dim_color if od else MenuStyle.skin.text_color)
		box.add_child(line)
	return box

## The display text for one objective — pure (takes done + progress), so it's unit-testable without GameState.
## e.g. "[x] Kill the boss" or "[ ] Collect parts (2/5)  (optional)".
func objective_line(obj: QuestObjective, done: bool, progress: int) -> String:
	var checkbox := "[x]" if done else "[ ]"
	var desc := obj.description if obj.description != "" else String(obj.id)
	var prog := ""
	if obj.required_count > 1:
		prog = " (%d/%d)" % [progress, obj.required_count]
	var opt := "  (optional)" if obj.optional else ""
	return "%s %s%s%s" % [checkbox, desc, prog, opt]
