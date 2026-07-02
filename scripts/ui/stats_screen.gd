extends CanvasLayer
## StatsScreen — a dedicated, read-only CHARACTER STATS screen, opened with its own key (InputManager.action_stats).
## Code-built and registered as an autoload so ONE instance survives scene changes, mirroring the other menus.
##
## Like the backpack, it does NOT pause the world — you stay vulnerable while reading it (real-time, Deus Ex
## style). It frees the mouse for the UI (restored on close); player CONTROL is suppressed via the is_open()
## gates (move/jump/fire/aim/crouch/grapple) so menu clicks don't drive the character. Shows the six
## CharacterStats with their live value + what each does (via StatInfo), the XP level, and the wallet.

signal opened
signal closed

const PANEL_MARGIN := 0.12  ## same border as the inventory/shop/loot screens — shared menu chrome
const STATS: Array[StringName] = [&"strength", &"persuasion", &"gunplay", &"endurance", &"streetwise", &"agility"]
const PlayerMenus := preload("res://scripts/ui/player_menus.gd")  ## tab-group helper (Inventory/Stats/Reputation/Journal)

var _root: Control
var _summary: Label
var _list: VBoxContainer
var _is_open := false
var _player: Player = null

func _ready() -> void:
	layer = 120                                  # above the HUD, just under OptionsMenu (128)
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep receiving input + rendering through the pause it causes
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
	# Never stack over a NON-player modal (incl. the pausing shop/heal/level-up — our input is PROCESS_MODE_ALWAYS).
	# The sibling player menus (Inventory/Reputation) are NOT blocked: opening us SWITCHES off an open sibling
	# (PlayerMenus.close_others below), so the four act as one Deus Ex / Pip-Boy tab group.
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() \
			or LootScreen.is_open() or ShopScreen.is_open() or HealScreen.is_open() or LevelUpScreen.is_open() or RespecScreen.is_open():
		return
	_player = _find_real_player() as Player
	if not is_instance_valid(_player):
		return  # no player (e.g. the start menu) -> nothing to show
	PlayerMenus.enter(self)  # switch off a sibling + free the cursor (preserves cursor position across switches)
	_is_open = true
	_rebuild()
	_root.visible = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	PlayerMenus.leave()
	closed.emit()

## Non-pausing, so the wallet can change under us (a kill reward, a sale) while you read — keep the summary live.
## The per-stat rows only change at a Level-Up station (which can't open over us), so they don't need polling.
func _process(_delta: float) -> void:
	if _is_open and is_instance_valid(_player):
		_refresh_summary()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputManager.action_stats):
		toggle()
		get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed(&"ui_cancel"):
		close()  # Esc closes (consume it so OptionsMenu doesn't also open behind us)
		get_viewport().set_input_as_handled()

## The human player, not a companion (companions join &"Player" for targeting but are NPCs).
func _find_real_player() -> Node:
	for p in get_tree().get_nodes_in_group(&"Player"):
		if not (p is NPC):
			return p
	return null

# ---------------------------------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so nothing falls through to gameplay behind
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
	vbox.add_child(PlayerMenus.build_tab_strip("Stats"))  # [Inventory | Stats | Reputation | Journal] — click to switch screens
	vbox.add_child(MenuStyle.make_title("Stats"))

	_summary = MenuStyle.make_hint("")
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_summary)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)

	vbox.add_child(MenuStyle.make_hint("Spend points at a Level-Up station."))

## Rebuild the rows from the player's live sheet. Built on open (the screen pauses, so the values can't change
## while it's up — no per-frame polling needed, unlike the real-time backpack).
func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var s: CharacterStats = _player.stats_or_default()
	_refresh_summary()
	for stat in STATS:
		_list.add_child(_make_stat_row(stat, s))

## The top line: the real character LEVEL (XP rank), the live wallet, and any unspent perk points.
func _refresh_summary() -> void:
	var txt := "Level %d   ·   %s zorkmids" % [_player.level, Zorkmids.fmt(_player.money)]
	var pts := _unspent_points()
	if pts > 0:
		txt += "   ·   %d perk point%s to spend" % [pts, "" if pts == 1 else "s"]
	_summary.text = txt

## Unspent perk points on the player's PerkManager child (0 if none) — so the "spend points at a Level-Up station"
## hint isn't shown without telling you how many you actually have. Mirrors the level-up screen's child lookup.
func _unspent_points() -> int:
	if not is_instance_valid(_player):
		return 0
	for c in _player.get_children():
		if c is PerkManager:
			return (c as PerkManager).skill_points
	return 0

## One stat block: a bright "Title — value" header line, then the dim what-it-does blurb and the live effect.
func _make_stat_row(stat: StringName, s: CharacterStats) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var head := Label.new()
	head.text = "%s   —   %d" % [StatInfo.TITLES.get(stat, str(stat)), s.get_stat(stat)]
	head.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)
	head.add_theme_color_override(&"font_color", MenuStyle.accent())
	box.add_child(head)
	var blurb := MenuStyle.make_hint(StatInfo.BLURB.get(stat, ""))
	box.add_child(blurb)
	var effect := Label.new()
	effect.text = "Now: %s" % StatInfo._effect(stat, s)
	effect.add_theme_color_override(&"font_color", MenuStyle.gold())
	box.add_child(effect)
	return box
