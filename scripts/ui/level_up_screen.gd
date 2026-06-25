extends CanvasLayer
## LevelUpScreen — spend zorkmids to raise a stat. Autoload; PAUSES the world while open (PROCESS_MODE_ALWAYS
## so its buttons work through the pause), frees the mouse — same as ShopScreen / HealScreen. The cost RISES
## with total level (Dark Souls) and is the same for every stat. Opened by LevelUp.start_talk (standalone) or
## the dialogue "Level Up" option (open_level_up).

signal opened
signal closed

const PANEL_MARGIN := 0.06  ## all six stats fit on one screen; a tight inset gives them the room (no scrolling)

## Display order + labels for the CharacterStats.
const STAT_ORDER: Array[StringName] = [&"strength", &"endurance", &"gunplay", &"persuasion", &"streetwise", &"agility"]
const STAT_LABELS := {
	&"strength": "Strength", &"endurance": "Endurance", &"gunplay": "Gunplay",
	&"persuasion": "Persuasion", &"streetwise": "Streetwise", &"agility": "Agility",
}

var _root: Control
var _title: Label
var _header: Label
var _rows: VBoxContainer
var _perks: VBoxContainer  ## rank 29 perk-pick section (hidden when the station authored no available_perks)
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
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() or InventoryScreen.is_open() or LootScreen.is_open() or ShopScreen.is_open() or HealScreen.is_open() or StatsScreen.is_open() or ReputationScreen.is_open():
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
	var station_name_v: Variant = station.get(&"station_name")  # duck-typed: only is_instance_valid was checked, not the type
	var station_nm: String = station_name_v if station_name_v is String else ""
	_title.text = "LEVEL UP — %s" % station_nm if not station_nm.is_empty() else "LEVEL UP"
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
	# Cost is now PER-STAT (PD-5: raising a high stat costs more), so the header drops the single "Next" figure
	# and each row shows + gates on its OWN cost. FRACTIONAL throughout so the UI's affordability + display match
	# LevelUp.level_up_stat exactly (a barely-affordable stat mustn't look clickable when the station would refuse it).
	var level: int = _station.total_level(_player)
	_header.text = "Level %d        Your zorkmids: %s" % [level, Zorkmids.fmt(_player.money)]
	for c in _rows.get_children():
		c.queue_free()
	var s := _player.stats_or_default()
	for stat in STAT_ORDER:
		var cost: float = _station.level_up_cost(_player, stat)  # PD-5: this stat's own (opportunity-scaled) cost
		var affordable := _player.money >= cost
		# Aligned columns (name | value | +1 | cost) overlaid on a clickable Button — space-padding can't
		# line up a variable-width font, so each column is its own fixed-width Label (mouse-ignore so the
		# click falls through to the button beneath).
		var row := Control.new()
		row.custom_minimum_size.y = MenuStyle.skin.body_size + 5
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var btn := Button.new()
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = not affordable
		# Hover a stat to see what it does + its current effect (a disabled, can't-afford row tips too).
		MenuStyle.attach_tip(btn, StatInfo.tooltip(stat, s))
		if affordable:
			btn.pressed.connect(_on_raise.bind(stat))
		row.add_child(btn)
		var cols := HBoxContainer.new()
		cols.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cols.offset_left = 9
		cols.offset_right = -9
		cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cols.add_theme_constant_override("separation", 6)
		cols.modulate.a = 1.0 if affordable else 0.4  # dim the whole row when you can't afford it
		cols.add_child(_stat_col(STAT_LABELS[stat], 76, HORIZONTAL_ALIGNMENT_LEFT))      # name
		cols.add_child(_stat_col(str(s.get_stat(stat)), 22, HORIZONTAL_ALIGNMENT_LEFT))  # current value
		cols.add_child(_stat_col("+1", 20, HORIZONTAL_ALIGNMENT_LEFT))                   # the increment
		var cost_col := _stat_col("(%s zm)" % Zorkmids.fmt(cost), 0, HORIZONTAL_ALIGNMENT_RIGHT)  # cost fills the rest
		cost_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(cost_col)
		row.add_child(cols)
		_rows.add_child(row)
	_rebuild_perks()

## One fixed-width column Label for a stat row (mouse-ignore so the click falls through to the button behind).
func _stat_col(text: String, min_w: float, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size.x = min_w
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

## Rebuild the perk-pick rows: hidden entirely when the station has no available_perks. The header shows unspent
## skill points; each authored perk is one row, disabled when already owned / prereqs unmet / no points left.
func _rebuild_perks() -> void:
	for c in _perks.get_children():
		c.queue_free()
	var raw_perks: Variant = _station.get(&"available_perks")  # duck-typed station: guard the access like station_name (:51) — a station without the property would crash a direct read
	var available: Array = raw_perks if raw_perks is Array else []
	if available.is_empty():
		_perks.visible = false
		return
	_perks.visible = true
	var pm: PerkManager = _player_perk_manager()
	var points: int = pm.skill_points if pm != null else 0
	var head := Label.new()
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_color_override(&"font_color", MenuStyle.accent())
	head.text = "Perks — %d point%s" % [points, "" if points == 1 else "s"]
	_perks.add_child(head)
	for perk in available:
		if perk != null:
			_perks.add_child(_perk_row(perk, pm, points))

## One perk row: a clickable Button hit-target overlaid with the name column (mouse-ignore, like the stat rows).
## Disabled + dimmed when not pickable; the description is a hover tip.
func _perk_row(perk: Perk, pm: PerkManager, points: int) -> Control:
	var owned: bool = pm != null and pm.has_perk(perk.id)
	var pickable: bool = pm != null and points > 0 and pm.can_unlock(perk)
	var row := Control.new()
	row.custom_minimum_size.y = MenuStyle.skin.body_size + 8
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn := Button.new()
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = not pickable
	if perk.description != "":
		MenuStyle.attach_tip(btn, perk.description)
	if pickable:
		btn.pressed.connect(_on_pick_perk.bind(perk))
	row.add_child(btn)
	var cols := HBoxContainer.new()
	cols.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cols.offset_left = 9
	cols.offset_right = -9
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_theme_constant_override("separation", 6)
	cols.modulate.a = 1.0 if (pickable or owned) else 0.4
	var label := perk.display_name if perk.display_name != "" else String(perk.id)
	if owned:
		label += "  (owned)"
	var name_col := _stat_col(label, 0, HORIZONTAL_ALIGNMENT_LEFT)
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(name_col)
	row.add_child(cols)
	return row

## Pick `perk`: the station spends a point + unlocks it, then refresh (point count drops, the row flips to owned).
func _on_pick_perk(perk: Perk) -> void:
	if is_instance_valid(_station) and is_instance_valid(_player):
		_station.unlock_perk(_player, perk)
		_rebuild()

## The player's PerkManager child, or null — for reading skill_points / has_perk in the picker.
func _player_perk_manager() -> PerkManager:
	if not is_instance_valid(_player):
		return null
	for c in _player.get_children():
		if c is PerkManager:
			return c as PerkManager
	return null

# ---------------------------------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	add_child(_root)

	_root.add_child(MenuStyle.make_dim())

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
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_title = MenuStyle.make_title("Level Up")
	vbox.add_child(_title)
	vbox.add_child(MenuStyle.make_separator())

	_header = Label.new()
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	_header.add_theme_color_override(&"font_color", MenuStyle.gold())  # zorkmid tint
	vbox.add_child(_header)

	# Five stats fit on one screen — no ScrollContainer (the panel is sized to hold them; see PANEL_MARGIN).
	_rows = VBoxContainer.new()
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 2)
	vbox.add_child(_rows)

	# Perk picker (rank 29): a separator + a header + one selectable row per available perk, rebuilt in
	# _rebuild_perks (like the stat rows). The whole section hides when the station authored no available_perks.
	vbox.add_child(MenuStyle.make_separator())
	_perks = VBoxContainer.new()
	_perks.add_theme_constant_override("separation", 2)
	vbox.add_child(_perks)
