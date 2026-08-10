extends CanvasLayer
## StatsScreen — a dedicated, read-only CHARACTER STATS screen, opened with its own key (InputManager.action_stats).
## Registered as an autoload so ONE instance survives scene changes, mirroring the other menus.
##
## AUTHORED SCENE: the layout lives in scenes/ui/stats_screen.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and applies the
## skin-driven look (MenuStyle style_* adopters + skin reads) on top, so a designer rearranges the panel
## in the editor and the skin keeps owning colours/fonts/separations. NO text is authored in the scene —
## every string is set here from PlayerText (l10n + the text-debt ratchet own strings, never a .tscn).
## The six stat blocks stay CODE-built into the authored %StatGrid (rebuilt per open / live-modifier
## change), the CharacterPreview portrait stays CODE-instantiated into %PortraitFrame, and the PlayerMenus
## tab strip stays CODE-BUILT into the authored %TabSlot (the strip's one-Button-per-tab structure is a
## cross-screen contract owned by player_menus.gd, not this scene).
## tests/test_stats_screen_scene.gd pins the wiring.
##
## Like the backpack, it does NOT pause the world — you stay vulnerable while reading it (real-time, Deus Ex
## style). It frees the mouse for the UI (restored on close); player CONTROL is suppressed via the is_open()
## gates (move/jump/fire/aim/crouch/grapple) so menu clicks don't drive the character. Shows the
## CharacterStats with their live value + what each does (via StatInfo), the XP level, and the wallet.

signal opened
signal closed


const PANEL_MARGIN := 0.12  ## same border as the inventory/shop/loot screens — shared menu chrome (authored on the scene's Panel anchors; tests pin the band)
const STATS: Array[StringName] = [&"strength", &"endurance", &"gunplay", &"agility", &"streetwise", &"larceny"]
const PlayerMenus := preload("res://scripts/ui/player_menus.gd")  ## tab-group helper (Inventory/Stats/Implants/Reputation/Journal)

var _root: Control
var _name_label: Label   ## the character's chosen name, shown under the title (hidden when unnamed)
var _preview: CharacterPreview   ## a live 3D head-and-shoulders portrait of the player's chosen appearance
var _summary: Label
var _list: GridContainer   ## the 2-column grid holding the six stat blocks (rebuilt on every open)
var _is_open := false
var _player: Player = null
var _stat_signature := ""

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

func open() -> void:
	# Never stack over a NON-player modal (incl. the station screens — our input is PROCESS_MODE_ALWAYS).
	# The sibling player menus (Inventory/Reputation) are NOT blocked: opening us SWITCHES off an open sibling
	# (PlayerMenus.close_others below), so the tabs act as one Deus Ex / Pip-Boy tab group.
	if _is_open or DialogueManager.is_active() \
			or InputManager.any_tab_blocking_open() \
			or not PlayerMenus.player_alive(get_tree()):  # M5/T1: the whole refusal set (options/loot/stations) comes from the modal registry; refuse mid-death (PROCESS_MODE_ALWAYS would else re-open over the death cinematic)
		return
	_player = _find_real_player() as Player
	if not is_instance_valid(_player):
		return  # no player (e.g. the start menu) -> nothing to show
	PlayerMenus.enter(self)  # switch off a sibling + free the cursor (preserves cursor position across switches)
	_is_open = true
	_rebuild()
	_preview.set_active(true)  # start the portrait's live render + turntable only while the screen is up
	_root.visible = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	_preview.set_active(false)  # stop rendering the portrait off-screen while closed
	PlayerMenus.leave()
	closed.emit()

## Non-pausing, so the wallet and live stat modifiers can change under us while you read.
func _process(_delta: float) -> void:
	if _is_open and is_instance_valid(_player):
		_refresh_summary()
		_refresh_stat_rows()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputManager.action_stats):
		toggle()
		get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed(&"ui_cancel"):
		close()  # Esc closes (consume it so OptionsMenu doesn't also open behind us)
		get_viewport().set_input_as_handled()

## The human player, not a companion (companions join &"Player" for targeting but are NPCs).
func _find_real_player() -> Node:
	return Groups.human_player(get_tree())  # M6: the one non-companion human-player filter lives on Groups (no local NPC dep)

## Hand off to the fullscreen CharacterInspectScreen (a bigger, drag-to-rotate hero showcase with the equipped
## weapon in hand). Its open() closes THIS tab as it takes over, so it's a one-way hand-off, not a stacked modal.
## It routes that takeover through PlayerMenus.enter, which owns the switch cue — hence the muted button in _bind_ui.
func _open_inspect() -> void:
	if is_instance_valid(_player):
		CharacterInspectScreen.open()

# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/stats_screen.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. The scene owns
## STRUCTURE (the PANEL_MARGIN 0.12 anchor band, the tab slot, the portrait column's AspectRatioContainer,
## the stat grid's scroll slot, the 2-column grid with its authored 8px gaps); the skin keeps owning LOOK —
## every colour/font/separation below is a MenuStyle/skin read, so reskinning via resources/ui/menu_skin.tres
## restyles this screen with zero scene edits.
func _bind_ui() -> void:
	_root = %Root  # full-rect, MOUSE_FILTER_STOP authored — eats clicks so nothing falls through to gameplay behind
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)

	var vbox: VBoxContainer = %VBox
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared per-screen rhythm (skin Layout group)
	# The tab strip is the only header — it already labels the screen, so no separate title line (the
	# Inventory convention, adopted across all the tabs so content starts at one height). The strip stays
	# CODE-BUILT by PlayerMenus into the authored %TabSlot: its one-Button-per-tab EXPAND_FILL structure is a
	# cross-screen contract (tests/test_player_menus.gd), so the scene authors only the slot.
	%TabSlot.add_child(PlayerMenus.build_tab_strip(&"stats"))  # [Inventory | Stats | Implants | Reputation | Journal] — click to switch screens (routing KEY, not the painted label)

	# The character's name (from creation) directly under the tab strip. A plain accent Label so the name
	# keeps its own casing (never uppercased). Hidden when unnamed (set in _rebuild off the live player).
	# Name + summary live in the OUTER column, not the stat column, so both centre on the SAME axis (the
	# panel's) instead of the header lines drifting right of it. The scene also authors the label's
	# auto_translate_mode = DISABLED: a player-TYPED name is never a translation msgid (Control-text atr).
	_name_label = %NameLabel
	_name_label.add_theme_color_override(&"font_color", MenuStyle.accent())
	_name_label.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)

	_summary = %Summary
	MenuStyle.style_hint(_summary)  # dim wrap-friendly footnote look (the make_hint twin); centring is authored

	# The body is laid out HORIZONTALLY (authored) — the 3D portrait column on the left (1 width share), the
	# stat grid on the right (2 shares, size_flags_stretch_ratio authored on %Scroll). Budget: the 0.12-margin
	# panel is ~602x337 at the REAL 792x444 canvas (~570x305 inside the panel's 16px content margin); the tab
	# strip / name / summary / footer hint eat ~111px of that, leaving the body ~194px tall — so the six stat
	# blocks go two-abreast below (one column needs roughly double that height and buried half the list behind
	# a scrollbar).
	(%Body as HBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.content_separation)

	# A live 3D portrait of the player's chosen appearance (head/body customizer). Head-and-shoulders framing;
	# rendered in its own SubViewport world so it works over any level. Kept INACTIVE while the screen is closed
	# (this is a persistent autoload) — open()/close() toggle it so it isn't rendering off-screen every frame.
	# The authored AspectRatioContainer keeps the portrait a sane card shape (ratio 0.8, FIT) at ANY canvas:
	# the column takes 1 of the body's 3 width shares and the portrait letterboxes inside it, instead of the
	# old fixed 92px-wide sliver that face-filled whatever height the body happened to have. The preview node
	# itself stays CODE-instantiated (a runtime 3D stage, not chrome a designer lays out).
	_preview = CharacterPreview.new()
	_preview.auto_start = false        # persistent autoload — don't build the 3D stage until first opened
	_preview.set_head_only(true)
	%PortraitFrame.add_child(_preview)  # the frame sizes it — no custom_minimum_size / size flags needed

	# "Inspect" hands off to the fullscreen hero view (full body + the equipped weapon in hand, drag to rotate).
	var inspect_btn: Button = %InspectButton  # focus_mode NONE authored: mouse-driven; don't steal focus
	inspect_btn.text = PlayerText.STATS_INSPECT_BUTTON
	# Mute the generic click: the takeover routes through PlayerMenus.enter (inside CharacterInspectScreen.open),
	# which plays the SIDEWAYS cue for the hand-off — the tab-strip idiom. Unmuted, one press would click AND
	# swipe; muted, a refused open (mid-death, a modal that beat us to the screen) also stays correctly silent.
	MenuStyle.set_button_sound(inspect_btn, &"")
	inspect_btn.pressed.connect(_open_inspect)

	# The stat column: six blocks in a 2x3 grid (columns + the ONE 8px gap on both axes authored on %StatGrid —
	# the gap halves the stack vs one column) so the whole set lands in/near the ~194px body at 792x444
	# (a single column needed ~390px and showed only ~3). The scroll stays as a SAFETY NET — designer-authored
	# blurbs are unbounded, and the longest current ones wrap to 3 lines in a ~180px cell, which can push a row
	# past the budget; sub-444 canvases shrink the body further. Horizontal scroll is authored OFF so long text
	# wraps to the cell instead of widening the grid.
	_list = %StatGrid


## Rebuild player identity / portrait, then refresh stat rows from the current live modifier signature.
func _rebuild() -> void:
	_name_label.text = _player.player_name
	_name_label.visible = not _player.player_name.is_empty()  # hide the line entirely for an unnamed character
	_preview.set_appearance(_player.appearance)  # the saved head/body/colours (empty -> the catalog default look)
	_refresh_summary()
	_refresh_stat_rows(true)

## The top line: the real character LEVEL (XP rank), the live wallet, and any unspent perk points.
func _refresh_summary() -> void:
	_summary.text = PlayerText.stats_summary(_player.level, _player.money, _unspent_points())

## Unspent perk points on the player's PerkManager child (0 if none) — so the "spend points at a Level-Up station"
## hint isn't shown without telling you how many you actually have. Mirrors the level-up screen's child lookup.
func _unspent_points() -> int:
	if not is_instance_valid(_player):
		return 0
	for c in _player.get_children():
		if c is PerkManager:
			return (c as PerkManager).skill_points
	return 0

func _stat_modifier(stat: StringName) -> float:
	if is_instance_valid(_player) and _player.has_method(&"status_stat_modifier"):
		return float(_player.status_stat_modifier(stat))
	return 0.0

func _stat_value_text(base: int, bonus: float) -> String:
	if is_zero_approx(bonus):
		return str(base)
	return "%s (%s)" % [_stat_num(float(base) + bonus), _signed_stat_num(bonus)]

## The bare/half number readout ("4" / "4.5") — TextFormat.num at one decimal, the single copy of the trim idiom
## (this screen's private duplicate is gone; StatInfo/ItemInfo/Zorkmids delegate the same way).
func _stat_num(x: float) -> String:
	return TextFormat.num(x, 1)

func _signed_stat_num(x: float) -> String:
	if is_zero_approx(x):
		return "0"
	return ("+" + _stat_num(x)) if x > 0.0 else _stat_num(x)

func _refresh_stat_rows(force := false) -> void:
	if not is_instance_valid(_player):
		return
	var s: CharacterStats = _player.stats_or_default()
	var sig := _current_stat_signature(s)
	if not force and sig == _stat_signature:
		return
	_stat_signature = sig
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for stat in STATS:
		_list.add_child(_make_stat_row(stat, s))

func _current_stat_signature(s: CharacterStats) -> String:
	var sig := ""
	for stat in STATS:
		sig += "%s:%d:%s|" % [String(stat), s.get_stat(stat), _stat_num(_stat_modifier(stat))]
	return sig

## One stat block (one 2-column-grid cell): a bright "Title — value" header line, then the dim what-it-does
## blurb and the live effect.
func _make_stat_row(stat: StringName, s: CharacterStats) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # each cell claims half the grid's width so the two columns split evenly
	box.add_theme_constant_override("separation", 2)      # tight leading INSIDE a block; the grid's authored 8px gap separates blocks
	var head := MenuStyle.cap_label(Label.new())  # clip+"…": a long authored StatText title can't widen this grid cell past its half-column and force the (disabled) h-scroll
	var bonus := _stat_modifier(stat)
	head.text = PlayerText.stat_header(stat, _stat_value_text(s.get_stat(stat), bonus))
	head.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)
	head.add_theme_color_override(&"font_color", MenuStyle.accent())
	box.add_child(head)
	var blurb_text := StatInfo.blurb(stat)
	if not blurb_text.is_empty():  # an unauthored blurb (StatText prose is optional) adds no blank line
		var blurb := MenuStyle.make_hint(blurb_text)  # make_hint autowraps — long blurbs reflow to the cell width
		box.add_child(blurb)
	var effect := Label.new()
	effect.text = PlayerText.stat_now(StatInfo._effect(stat, s, bonus))
	# Wrap like the blurb: a long two-part effect ("rep gains +10%, penalties -5%") must collapse its min-width
	# to the ~180px grid cell instead of forcing the whole grid wider than the scroll (h-scroll is disabled).
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.add_theme_color_override(&"font_color", MenuStyle.gold())
	box.add_child(effect)
	return box
