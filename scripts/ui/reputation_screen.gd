extends CanvasLayer
## ReputationScreen — a dedicated, read-only FACTION REPUTATION screen, opened with its own key
## (InputManager.action_reputation, default V). Code-built + registered as an autoload, mirroring StatsScreen.
##
## Like the backpack and the stats screen it does NOT pause the world — you stay vulnerable while reading it.
## It frees the mouse for the UI (restored on close); player control is suppressed via InputManager's overlay
## gate. Lists every faction with the player's standing (a bar over the rep_min..rep_max range) and the
## resulting disposition (Hostile / Neutral / Friendly), colour-coded via the shared CBPalette. Refreshes live
## off Reputation.reputation_changed (a kill that sours a faction updates the bar while it's open).

signal opened
signal closed

const PANEL_MARGIN := 0.12  ## same border as the other inventory-style screens — shared chrome
const Factions := preload("res://scripts/faction/factions.gd")  # registry (no class_name; preloaded where used)
const PlayerMenus := preload("res://scripts/ui/player_menus.gd")  ## tab-group helper (Inventory/Stats/Reputation)
const DISPOSITION_NAME := {
	Disposition.Kind.HOSTILE: "Hostile",
	Disposition.Kind.NEUTRAL: "Neutral",
	Disposition.Kind.FRIENDLY: "Friendly",
}

var _root: Control
var _list: VBoxContainer
var _is_open := false

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
	# Block only the NON-player modals; the sibling player menus (Inventory/Stats) instead SWITCH to us via
	# PlayerMenus.close_others — the three behave as one Deus Ex / Pip-Boy tab group.
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() \
			or LootScreen.is_open() or ShopScreen.is_open() or HealScreen.is_open() or LevelUpScreen.is_open():
		return
	PlayerMenus.enter(self)  # switch off a sibling + free the cursor (preserves cursor position across switches)
	_is_open = true
	if not Reputation.reputation_changed.is_connected(_on_rep_changed):
		Reputation.reputation_changed.connect(_on_rep_changed)
	_rebuild()
	_root.visible = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	if Reputation.reputation_changed.is_connected(_on_rep_changed):
		Reputation.reputation_changed.disconnect(_on_rep_changed)
	PlayerMenus.leave()
	closed.emit()

## A faction's standing changed while we're open (e.g. a kill soured them) — re-render to reflect it live.
func _on_rep_changed(_faction: Faction, _delta: float, _new_total: float) -> void:
	if _is_open:
		_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputManager.action_reputation):
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
	vbox.add_child(PlayerMenus.build_tab_strip("Reputation"))  # [Inventory | Stats | Reputation] — click to switch screens
	vbox.add_child(MenuStyle.make_title("Reputation"))
	vbox.add_child(MenuStyle.make_hint("How each faction feels about you. Good deeds raise it; killing their own sinks it."))

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
	var ids := Factions.ids()
	if ids.is_empty():
		_list.add_child(MenuStyle.make_hint("No factions defined."))
		return
	for id in ids:
		var f: Faction = Factions.by_id(id)
		if f != null:
			_list.add_child(_make_faction_row(f))

## One faction block: a "Name — +standing · Disposition" header in the disposition colour, then a bar showing
## the standing on the rep_min..rep_max scale (tinted the same).
func _make_faction_row(f: Faction) -> Control:
	var standing := Reputation.get_reputation(f)
	var kind := Reputation.disposition_for(f)
	var col: Color = CBPalette.disposition_color(false, kind, MenuStyle.text_color())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var head := Label.new()
	head.text = "%s   —   %+d   ·   %s" % [f.display_name, int(round(standing)), DISPOSITION_NAME.get(kind, "?")]
	head.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)
	head.add_theme_color_override(&"font_color", col)
	box.add_child(head)

	var bar := ProgressBar.new()
	bar.min_value = GameSettings.reputation.rep_min
	bar.max_value = GameSettings.reputation.rep_max
	bar.value = standing
	bar.show_percentage = false
	bar.custom_minimum_size.y = 14
	bar.modulate = col
	box.add_child(bar)
	return box
