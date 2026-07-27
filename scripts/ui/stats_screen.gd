extends CanvasLayer
## StatsScreen — a dedicated, read-only CHARACTER STATS screen, opened with its own key (InputManager.action_stats).
## Code-built and registered as an autoload so ONE instance survives scene changes, mirroring the other menus.
##
## Like the backpack, it does NOT pause the world — you stay vulnerable while reading it (real-time, Deus Ex
## style). It frees the mouse for the UI (restored on close); player CONTROL is suppressed via the is_open()
## gates (move/jump/fire/aim/crouch/grapple) so menu clicks don't drive the character. Shows the
## CharacterStats with their live value + what each does (via StatInfo), the XP level, and the wallet.

signal opened
signal closed


const PANEL_MARGIN := 0.12  ## same border as the inventory/shop/loot screens — shared menu chrome
const STAT_GRID_GAP := 8    ## the ONE gap between stat blocks in the 2x3 grid (both axes) — halves the stack vs one column so the grid lands in/near the ~170px body at 792x444
const STATS: Array[StringName] = [&"strength", &"endurance", &"gunplay", &"agility", &"streetwise", &"larceny"]
const PlayerMenus := preload("res://scripts/ui/player_menus.gd")  ## tab-group helper (Inventory/Stats/Reputation/Journal)

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
			or LootScreen.is_open() or InputManager.any_pausing_open() \
			or not PlayerMenus.player_alive(get_tree()):  # M5: pausing modals via the shared helper; refuse mid-death (PROCESS_MODE_ALWAYS would else re-open over the death cinematic)
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
func _open_inspect() -> void:
	if is_instance_valid(_player):
		CharacterInspectScreen.open()

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
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared per-screen rhythm (skin Layout group)
	panel.add_child(vbox)
	vbox.add_child(PlayerMenus.build_tab_strip(&"stats"))  # [Inventory | Stats | Reputation | Journal] — click to switch screens (routing KEY, not the painted label)
	vbox.add_child(MenuStyle.make_title(PlayerText.STATS_SCREEN_TITLE))

	# The character's name (from creation) directly under the title. Plain accent Label, NOT make_title — keep
	# the name's own casing rather than uppercasing it. Hidden when unnamed (set in _rebuild off the live
	# player). Name + summary live in the OUTER column, not the stat column, so title/name/summary all centre
	# on the SAME axis (the panel's) instead of the header lines drifting right of the STATS title.
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override(&"font_color", MenuStyle.accent())
	_name_label.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)
	vbox.add_child(_name_label)

	_summary = MenuStyle.make_hint("")
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_summary)

	# The body is laid out HORIZONTALLY — the 3D portrait column on the left (1 width share), the stat grid on
	# the right (2 shares). Budget: the 0.12-margin panel is ~602x337 at the REAL 792x444 canvas (~570x305
	# inside the panel's 16px content margin); the tab strip / title / name / summary / footer hint eat ~135px
	# of that, leaving the body ~170px tall — so the six stat blocks go two-abreast below (one column needs
	# roughly double that height and buried half the list behind a scrollbar).
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", MenuStyle.skin.content_separation)
	vbox.add_child(body)

	# A live 3D portrait of the player's chosen appearance (head/body customizer). Head-and-shoulders framing;
	# rendered in its own SubViewport world so it works over any level. Kept INACTIVE while the screen is closed
	# (this is a persistent autoload) — open()/close() toggle it so it isn't rendering off-screen every frame.
	# The AspectRatioContainer keeps the portrait a sane card shape (ratio 0.8, FIT) at ANY canvas: the column
	# takes 1 of the body's 3 width shares and the portrait letterboxes inside it, instead of the old fixed
	# 92px-wide sliver that face-filled whatever height the body happened to have.
	# A column: the portrait card on top, an "Inspect" button under it. The column takes 1 of the body's 3 width
	# shares (the stat grid takes 2), and the portrait letterboxes inside its AspectRatioContainer.
	var portrait_col := VBoxContainer.new()
	portrait_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_col.size_flags_stretch_ratio = 1.0  # 1 share vs the stat column's 2
	portrait_col.add_theme_constant_override("separation", 4)
	body.add_child(portrait_col)

	var portrait_frame := AspectRatioContainer.new()
	portrait_frame.ratio = 0.8
	portrait_frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
	portrait_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_col.add_child(portrait_frame)
	_preview = CharacterPreview.new()
	_preview.auto_start = false        # persistent autoload — don't build the 3D stage until first opened
	_preview.set_head_only(true)
	portrait_frame.add_child(_preview)  # the frame sizes it — no custom_minimum_size / size flags needed

	# "Inspect" hands off to the fullscreen hero view (full body + the equipped weapon in hand, drag to rotate).
	var inspect_btn := Button.new()
	inspect_btn.text = PlayerText.STATS_INSPECT_BUTTON
	inspect_btn.focus_mode = Control.FOCUS_NONE  # mouse-driven; don't steal focus
	inspect_btn.pressed.connect(_open_inspect)
	portrait_col.add_child(inspect_btn)

	# The stat column: six blocks in a 2x3 grid so the whole set lands in/near the ~170px body at 792x444
	# (a single column needed ~390px and showed only ~3). The scroll stays as a SAFETY NET — designer-authored
	# blurbs are unbounded, and the longest current ones wrap to 3 lines in a ~180px cell, which can push a row
	# past the budget; sub-444 canvases shrink the body further.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 2.0  # 2 width shares vs the portrait's 1
	body.add_child(scroll)
	_list = GridContainer.new()
	_list.columns = 2
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", STAT_GRID_GAP)
	_list.add_theme_constant_override("v_separation", STAT_GRID_GAP)
	scroll.add_child(_list)

	vbox.add_child(MenuStyle.make_hint(PlayerText.STATS_SCREEN_HINT))

## Rebuild player identity / portrait, then refresh stat rows from the current live modifier signature.
func _rebuild() -> void:
	_name_label.text = _player.player_name
	_name_label.visible = not _player.player_name.is_empty()  # hide the line entirely for an unnamed character
	_preview.set_appearance(_player.appearance)  # the saved head/body/colours (empty -> the catalog default look)
	_refresh_summary()
	_refresh_stat_rows(true)

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
	box.add_theme_constant_override("separation", 2)      # tight leading INSIDE a block; STAT_GRID_GAP separates blocks
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
