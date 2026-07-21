extends CanvasLayer
## LevelUpScreen — spend zorkmids to raise a stat. Autoload; PAUSES the world while open (PROCESS_MODE_ALWAYS
## so its buttons work through the pause), frees the mouse — same as ShopScreen / HealScreen. The cost RISES
## with total level (Dark Souls) and is the same for every stat. Opened by LevelUp.start_talk (standalone) or
## the dialogue "Level Up" option (open_level_up).

signal opened
signal closed


const PANEL_MARGIN := 0.12  ## shared modal inset (matches heal/shop/respec chrome) — the short stat list centers vertically and long perk lists scroll (see _build_ui), so no edge-to-edge slab is needed
## Width cap for a row's column group (name | value | +1 | cost). Uncapped, the cost column stretched to the
## panel's full ~570px inner width (792x444, 0.12 margins, 16px panel padding) and floated ~450px from its
## stat name; capped + centered the four columns read as one unit. 76+22+20 fixed columns + 3x6 separation
## leaves ~204px for the right-aligned cost — roomy for "(9,999 zm)".
const COLS_WIDTH := 340.0

## Display order for the CharacterStats. The row TITLES come from StatInfo.title() (the authored StatText), so the
## label text has ONE source and can't drift from the stats screen / character creation.
const STAT_ORDER: Array[StringName] = [&"strength", &"endurance", &"gunplay", &"agility", &"streetwise", &"larceny"]

var _root: Control
var _title: Label
var _header: HBoxContainer  ## level + wallet as TWO Labels (a literal space-run can't align in a variable-width font)
var _level_label: Label
var _money_label: Label     ## the zorkmid half — only it wears the gold tint
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
	if _is_open or DialogueManager.is_active() or InputManager.any_modal_open(self):  # M5: refuse over ANY other menu (incl. QuestJournal + Respec, both omitted before)
		return
	if not is_instance_valid(station):
		return
	_player = player as Player
	if not is_instance_valid(_player):
		return
	_station = station
	_is_open = true
	_prev_mouse_mode = ModalMenu.grab_mouse()
	var station_name_v: Variant = station.get(&"station_name")  # duck-typed: only is_instance_valid was checked, not the type
	var station_nm: String = station_name_v if station_name_v is String else ""
	# Route the re-title through title_text so the skin's uppercase_titles casing applies to RUNTIME titles
	# too, not just make_title's constructor argument.
	_title.text = MenuStyle.title_text(PlayerText.level_up_title(station_nm))
	_rebuild()
	_root.visible = true
	get_tree().paused = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	ModalMenu.restore_mouse(_prev_mouse_mode)
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
	# Cost is FLAT (Dark Souls) — the same for every stat at a given total level — so each row shows the identical
	# next-level price and gates on it. FRACTIONAL throughout so the UI's affordability + display match
	# LevelUp.level_up_stat exactly (a barely-affordable stat mustn't look clickable when the station would refuse it).
	var level: int = _station.total_level(_player)
	_level_label.text = PlayerText.level_label(level)
	_money_label.text = PlayerText.your_zorkmids(_player.money)
	for c in _rows.get_children():
		c.queue_free()
	var s := _player.stats_or_default()
	for stat in STAT_ORDER:
		var cost: float = _station.level_up_cost(_player, stat)  # flat total-level cost (identical for every stat)
		var affordable := _player.money >= cost
		# Aligned columns (name | value | +1 | cost) overlaid on a clickable Button — space-padding can't
		# line up a variable-width font, so each column is its own fixed-width Label. The HBox is capped at
		# COLS_WIDTH and centered by a full-rect CenterContainer so the four columns read as one group; the
		# full-rect Button underneath stays the whole-row hit target (wrapper + labels are ALL mouse-ignore
		# so clicks fall through to it).
		var row := Control.new()
		row.custom_minimum_size.y = _row_height()
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
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE  # MUST ignore: the row Button beneath is the click target
		var cols := HBoxContainer.new()
		cols.custom_minimum_size.x = COLS_WIDTH
		cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cols.add_theme_constant_override("separation", 6)
		cols.modulate.a = 1.0 if affordable else 0.4  # dim the whole row when you can't afford it
		cols.add_child(_stat_col(StatInfo.title(stat), 76, HORIZONTAL_ALIGNMENT_LEFT))    # name (authored StatText title)
		cols.add_child(_stat_col(str(s.get_stat(stat)), 22, HORIZONTAL_ALIGNMENT_LEFT))  # current value
		cols.add_child(_stat_col("+1", 20, HORIZONTAL_ALIGNMENT_LEFT))                   # the increment
		var cost_col := _stat_col("(%s zm)" % Zorkmids.fmt(cost), 0, HORIZONTAL_ALIGNMENT_RIGHT)  # cost fills the group's remainder
		cost_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(cost_col)
		center.add_child(cols)
		row.add_child(center)
		_rows.add_child(row)
	_rebuild_perks()

## ONE row height for stat AND perk rows — they sit in the same scrolled list and must read as one grid
## (they previously drifted: body_size+5 vs body_size+8). Derived from the skin so a reskin scales both.
func _row_height() -> float:
	return float(MenuStyle.skin.body_size + 5)

## One fixed-width column Label for a stat row (mouse-ignore so the click falls through to the button behind).
## clip_text + ellipsis make custom_minimum_size.x a TRUE cap (clip_text drops the Label's own min width to
## ~0), so an unbounded authored stat/perk title or a big cost can't grow its column past its share and shove
## the whole COLS_WIDTH group — which is centered — sideways. The name column then clips with "…", the
## EXPAND_FILL cost column fills the fixed remainder, and the four-column group keeps ONE stable width.
func _stat_col(text: String, min_w: float, align: HorizontalAlignment) -> Label:
	var l := MenuStyle.cap_label(Label.new())
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
	# The stats/perks divider lives INSIDE _perks (rebuilt with the rows) so it appears and disappears WITH
	# the section — a perk-less station previously left this hairline orphaned under the stat list.
	_perks.add_child(MenuStyle.make_separator())
	var pm: PerkManager = _player_perk_manager()
	var points: int = pm.skill_points if pm != null else 0
	var head := Label.new()
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)  # section header, same rank as the level/wallet line
	head.add_theme_color_override(&"font_color", MenuStyle.accent())
	head.text = PlayerText.perks_header(points)
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
	row.custom_minimum_size.y = _row_height()  # same height as a stat row — one grid, one rhythm
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
	# Same COLS_WIDTH + CenterContainer treatment as the stat rows so the perk names left-align with the
	# stat names above them (wrapper + label mouse-ignore; the full-rect Button stays the hit target).
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cols := HBoxContainer.new()
	cols.custom_minimum_size.x = COLS_WIDTH
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_theme_constant_override("separation", 6)
	cols.modulate.a = 1.0 if (pickable or owned) else 0.4
	var label := perk.display_name if perk.display_name != "" else String(perk.id)
	if owned:
		label += "  (owned)"
	var name_col := _stat_col(label, 0, HORIZONTAL_ALIGNMENT_LEFT)
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(name_col)
	center.add_child(cols)
	row.add_child(center)
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
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared panel-screen rhythm (MenuSkin)
	# ALIGNMENT_CENTER: the heal/respec-style centered card. While the expanding scroll below is present this
	# is inert (no leftover height to distribute) — the ACTUAL centering of short content happens inside the
	# scroll viewport (see `body`) — but it keeps the chrome centered if the scroll is ever removed.
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	_title = MenuStyle.make_title("Level Up")
	vbox.add_child(_title)
	vbox.add_child(MenuStyle.make_separator())

	# Level + wallet as two EDGE-PINNED Labels — level hugs the panel's LEFT, wallet its RIGHT (the same header
	# pattern the shop/loot wallet rows use). Each takes half the row via EXPAND_FILL, so neither MOVES as the
	# zorkmid total changes length; a CENTERED pair (the old design) re-centered and slid both labels sideways
	# every time the money string grew or shrank. Ellipsis trims a pathological amount within its half.
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", MenuStyle.skin.content_separation * 2)
	_level_label = Label.new()
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_level_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_level_label.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	_header.add_child(_level_label)
	_money_label = Label.new()
	_money_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_money_label.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	_money_label.add_theme_color_override(&"font_color", MenuStyle.gold())  # zorkmid tint — the wallet half only
	_header.add_child(_money_label)
	vbox.add_child(_header)

	# Stats + perks scroll: available_perks is designer-authored and unbounded, so a long list must scroll
	# instead of overflowing the panel. Centering coexists with scrolling like so: ScrollContainer has no
	# fit-to-content mode in Godot 4 (its min height is 0 when vertical scroll is enabled), so the scroll
	# EXPANDS to all leftover panel height and the centering happens INSIDE it — `body` fills the viewport
	# (SIZE_EXPAND_FILL) with ALIGNMENT_CENTER, so short content (the common six-stat, no-perk case) floats
	# centered while long content exceeds the viewport and scrolls from the top.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # width is anchor-fixed; only length varies
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL  # fill the scroll viewport so ALIGNMENT_CENTER can center short content
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", MenuStyle.skin.content_separation)
	scroll.add_child(body)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	body.add_child(_rows)

	# Perk picker (rank 29): separator + header + one selectable row per available perk, all rebuilt in
	# _rebuild_perks (the divider is added THERE, inside _perks, so it hides with the section). The whole
	# section hides when the station authored no available_perks.
	_perks = VBoxContainer.new()
	_perks.add_theme_constant_override("separation", 2)
	body.add_child(_perks)
