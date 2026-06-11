extends CanvasLayer
## LevelUpScreen — spend zorkmids to raise a stat. Autoload; PAUSES the world while open (PROCESS_MODE_ALWAYS
## so its buttons work through the pause), frees the mouse — same as ShopScreen / HealScreen. The cost RISES
## with total level (Dark Souls) and is the same for every stat. Opened by LevelUp.start_talk (standalone) or
## the dialogue "Level Up" option (open_level_up).

signal opened
signal closed

const PANEL_MARGIN := 0.22

## Display order + labels for the five CharacterStats.
const STAT_ORDER: Array[StringName] = [&"strength", &"endurance", &"gunplay", &"persuasion", &"streetwise"]
const STAT_LABELS := {
	&"strength": "Strength", &"endurance": "Endurance", &"gunplay": "Gunplay",
	&"persuasion": "Persuasion", &"streetwise": "Streetwise",
}

var _root: Control
var _title: Label
var _header: Label
var _rows: VBoxContainer
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _station: Node = null  ## a LevelUp — typed Node to avoid a LevelUp<->LevelUpScreen class cycle; its API is called dynamically

func _ready() -> void:
	layer = 121                                  # peer of the other modal overlays (loot / inventory / shop / heal)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

## Open the level-up menu for `station`, leveling `player`. Refuses to stack over another modal / dialogue.
func open_level_up(station: Node, player: Node) -> void:
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() or InventoryScreen.is_open() or LootScreen.is_open() or ShopScreen.is_open() or HealScreen.is_open():
		return
	if not is_instance_valid(station):
		return
	_player = player as Player
	if not is_instance_valid(_player):
		return
	_station = station
	_is_open = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_title.text = "LEVEL UP — %s" % station.station_name if not station.station_name.is_empty() else "LEVEL UP"
	_rebuild()
	_root.visible = true
	get_tree().paused = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	Input.mouse_mode = _prev_mouse_mode
	_station = null
	_player = null
	get_tree().paused = false
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	# Close on the SAME Interact key that opens it (the ray consumes the OPENING press — ray_cast.gd skips
	# interacting while we're open), or on Esc.
	if _is_open and (event.is_action_pressed(InputManager.action_pickup) or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

## Raise `stat` (the station charges + applies it), then refresh — the cost rises + buttons disable when broke.
func _on_raise(stat: StringName) -> void:
	if is_instance_valid(_station) and is_instance_valid(_player):
		_station.level_up_stat(_player, stat)
		_rebuild()

## Rebuild the header (level / wallet / next cost) + one button per stat (its value + the +1 cost).
func _rebuild() -> void:
	if not is_instance_valid(_station) or not is_instance_valid(_player):
		return
	var cost: int = _station.level_up_cost(_player)
	var level: int = _station.total_level(_player)
	_header.text = "Level %d        Your zorkmids: %d        Next: %d zm" % [level, _player.money, cost]
	for c in _rows.get_children():
		c.queue_free()
	var s := _player.stats_or_default()
	var affordable := _player.money >= cost
	for stat in STAT_ORDER:
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "%s   %d         +1   (%d zm)" % [STAT_LABELS[stat], s.get_stat(stat), cost]
		btn.disabled = not affordable
		if affordable:
			btn.pressed.connect(_on_raise.bind(stat))
		_rows.add_child(btn)

# ---------------------------------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var theme := Theme.new()
	theme.default_font_size = 15
	_root.theme = theme
	add_child(_root)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.0, 0.0, 0.55)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dimmer)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = PANEL_MARGIN
	panel.anchor_top = PANEL_MARGIN
	panel.anchor_right = 1.0 - PANEL_MARGIN
	panel.anchor_bottom = 1.0 - PANEL_MARGIN
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	_title = Label.new()
	_title.text = "LEVEL UP"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_title)

	_header = Label.new()
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_theme_font_size_override("font_size", 15)
	_header.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.4))  # gold-ish zorkmid tint
	vbox.add_child(_header)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)

	var hint := Label.new()
	hint.text = "Click a stat to raise it.   The cost rises with your level.   Esc to close."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)
