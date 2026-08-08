extends CanvasLayer
## ReputationScreen — a dedicated, read-only FACTION REPUTATION screen, opened with its own key
## (InputManager.action_reputation, default V). Registered as an autoload, mirroring StatsScreen.
##
## AUTHORED SCENE: the layout lives in scenes/ui/reputation_screen.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and applies the
## skin-driven look (MenuStyle style_* adopters + skin reads) on top, so a designer rearranges the panel
## in the editor and the skin keeps owning colours/fonts/separations. NO text is authored in the scene —
## every string is set here from PlayerText (l10n + the text-debt ratchet own strings, never a .tscn).
## The per-faction rows stay CODE-built into the authored %RepList (rebuilt per open / live rep change),
## and the PlayerMenus tab strip stays CODE-BUILT into the authored %TabSlot (the strip's one-Button-per-tab
## structure is a cross-screen contract owned by player_menus.gd, not this scene).
## tests/test_reputation_screen_scene.gd pins the wiring.
##
## Like the backpack and the stats screen it does NOT pause the world — you stay vulnerable while reading it.
## It frees the mouse for the UI (restored on close); player control is suppressed via InputManager's overlay
## gate. Lists every faction with the player's standing (a bar over the rep_min..rep_max range) and the
## resulting disposition (Hostile / Neutral / Friendly), colour-coded via the shared CBPalette. Refreshes live
## off Reputation.reputation_changed (a kill that sours a faction updates the bar while it's open).

signal opened
signal closed


const PANEL_MARGIN := 0.12  ## same border as the other inventory-style screens — shared chrome (authored on the scene's Panel anchors; tests pin the band)
const Factions := preload("res://scripts/faction/factions.gd")  # registry (no class_name; preloaded where used)
const PlayerMenus := preload("res://scripts/ui/player_menus.gd")  ## tab-group helper (Inventory/Stats/Implants/Reputation/Journal)
## Disposition display words single-sourced from PlayerText's ALIGNMENT_*_WORD consts (the same words the
## HUD's standing-change toast keys its templates on) — a reword can't drift between this screen and the toast.
const DISPOSITION_NAME := {
	Disposition.Kind.HOSTILE: PlayerText.ALIGNMENT_HOSTILE_WORD,
	Disposition.Kind.NEUTRAL: PlayerText.ALIGNMENT_NEUTRAL_WORD,
	Disposition.Kind.FRIENDLY: PlayerText.ALIGNMENT_FRIENDLY_WORD,
}

var _root: Control
var _list: VBoxContainer
var _is_open := false

func _ready() -> void:
	layer = 120                                  # above the HUD, just under OptionsMenu (128)
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep receiving input + rendering; this tab does NOT pause — the world runs real-time beneath it (Pip-Boy tabs are vulnerable by design)
	_bind_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

func toggle() -> void:
	if _is_open:
		close()
	else:
		open()

## Open the reputation screen. Refuses over the non-player modals, mid-death, AND when there is NO human player
## (start menu / character creation) — there's nothing to show then, matching Inventory/Stats' own bail.
func open() -> void:
	# Block only the NON-player modals; the sibling player menus (Inventory/Stats) instead SWITCH to us via
	# PlayerMenus.close_others — the tabs behave as one Deus Ex / Pip-Boy tab group.
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() \
			or LootScreen.is_open() or InputManager.any_pausing_open() \
			or not PlayerMenus.player_alive(get_tree()) \
			or not PlayerMenus.has_player(get_tree()):  # no human player (start menu / char-creation) -> nothing to show, matching Inventory/Stats
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
# UI binding (the layout is AUTHORED in scenes/ui/reputation_screen.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. The scene owns
## STRUCTURE (the full-rect Root/Dim, the PANEL_MARGIN 0.12 anchor band, the tab slot, the faction list's
## scroll slot with horizontal scroll authored OFF, the list's authored 14px row gap); the skin keeps owning
## LOOK — every colour/font/separation below is a MenuStyle/skin read, so reskinning via
## resources/ui/menu_skin.tres restyles this screen with zero scene edits.
func _bind_ui() -> void:
	_root = %Root  # full-rect, MOUSE_FILTER_STOP authored — eats clicks so nothing falls through to gameplay behind
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)

	(%VBox as VBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared menu rhythm — same gap as every panel screen (skin Layout group)
	# The tab strip is the only header (the Inventory convention, adopted across all the tabs so content
	# starts at one height). The strip stays CODE-BUILT by PlayerMenus into the authored %TabSlot: its
	# one-Button-per-tab EXPAND_FILL structure is a cross-screen contract (tests/test_player_menus.gd), so the
	# scene authors only the slot.
	%TabSlot.add_child(PlayerMenus.build_tab_strip(&"reputation"))  # [Inventory | Stats | Implants | Reputation | Journal] — click to switch screens (routing KEY, not the painted label)

	# The faction list scrolls vertically only (horizontal scroll authored OFF on %Scroll, so a runaway-long
	# faction name trims — see _make_faction_row — instead of widening the panel past its anchors). The
	# per-faction rows are DYNAMIC content, rebuilt into %RepList on open / live rep change (_rebuild).
	_list = %RepList

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var ids := Factions.ids()
	if ids.is_empty():
		_list.add_child(MenuStyle.make_hint(PlayerText.REPUTATION_EMPTY))
		return
	for id in ids:
		var f: Faction = Factions.by_id(id)
		if f != null:
			_list.add_child(_make_faction_row(f))

## One faction block: a real three-column header row (name | standing | disposition) in the disposition
## colour, then a themed meter showing the standing on the rep_min..rep_max scale. Fixed-width right-aligned
## value/disposition columns keep the numbers vertically aligned across rows (the old single Label faked
## columns with literal space runs, so the numbers zig-zagged between rows).
func _make_faction_row(f: Faction) -> Control:
	var standing := Reputation.get_reputation(f)
	var kind := Reputation.disposition_for(f)
	var col: Color = CBPalette.disposition_color(false, kind, MenuStyle.text_color())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)

	var head := HBoxContainer.new()
	var name_l := Label.new()
	name_l.text = f.display_name
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Trim, don't widen: horizontal scroll is disabled on the list's ScrollContainer, so a runaway-long
	# faction name would otherwise force its min width onto the panel and push it past its anchors.
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)
	name_l.add_theme_color_override(&"font_color", col)
	head.add_child(name_l)
	var value_l := Label.new()
	value_l.text = PlayerText.reputation_standing(int(round(standing)))
	value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_l.custom_minimum_size.x = float(MenuStyle.skin.rep_value_col_width)  # fixed column so signed values line up down the list — fits ENGLISH "+100"/"-100" at header_size; per-locale skin budget
	value_l.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)
	value_l.add_theme_color_override(&"font_color", col)
	head.add_child(value_l)
	var disp_l := Label.new()
	disp_l.text = DISPOSITION_NAME.get(kind, "?")
	disp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	disp_l.custom_minimum_size.x = float(MenuStyle.skin.disposition_col_width)  # fits the ENGLISH disposition words (the ALIGNMENT_*_WORD trio) without per-row width churn; per-locale skin budget
	disp_l.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)
	disp_l.add_theme_color_override(&"font_color", col)
	head.add_child(disp_l)
	box.add_child(head)

	# Themed meter: neutral track + col-tinted FILL. The old `bar.modulate = col` tinted track, border
	# and fill alike, which collapsed the fill/track contrast the meter exists to show.
	var bar := MenuStyle.make_meter(col)
	bar.min_value = GameSettings.reputation.rep_min
	bar.max_value = GameSettings.reputation.rep_max
	bar.value = standing
	bar.custom_minimum_size.y = 14
	box.add_child(bar)
	return box
