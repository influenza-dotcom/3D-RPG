extends GutTest

## AUTHORED-SCENE wiring contracts for the level-up screen (scenes/ui/level_up_screen.tscn +
## level_up_screen.gd), mirroring the heal-screen exemplar (tests/test_heal_screen_scene.gd). Menus are
## .tscn scenes a designer edits; the script binds chrome by %unique name and applies the skin-driven look
## on top. These pin the silent-when-broken seams: the autoload points at the SCENE, every %node the
## script binds exists, no text is authored in the scene (strings belong to PlayerText / l10n, never a
## .tscn), and the screen-specific layout promises (PANEL_MARGIN border, header halves that hold still as the wallet
## grows, a short stat list centred in its scroll) — MEASURED on an open card, not read off the scene's layout flags.
## Pricing/credit behaviour is tests/test_level_up_credit.gd.
##
## ⭐AND IT PINS CONTROLLER PARITY (the atm_screen must-not-recur rule, both halves): the authored RailButton
## must NOT carry `focus_mode = 0`, and — DRIVEN on a private in-tree instance with a real LevelUp station and a
## detached Player — the code-built stat/perk rows take focus, open_level_up SEEDS focus on the first row once the
## panel is visible, and a rebuild that frees the focused row hands the cursor to the fresh first row. With no focus
## owner, ui navigation has nowhere to start and every row on the panel is pad-unreachable.

const SCENE := "res://scenes/ui/level_up_screen.tscn"
const PLAYER_PATH := "res://scripts/player/player.gd"

## Every unique name level_up_screen.gd binds in _bind_ui — a rename in the editor breaks the bind at boot,
## so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "VBox", "Title", "Header", "LevelLabel", "MoneyLabel", "RailButton", "CreditNotice", "Body", "Rows", "Perks"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "LevelUpScreen", "")), "*" + SCENE,
		"the LevelUpScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries level_up_screen.gd")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (the script binds it in _bind_ui)" % n)
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in PlayerText (the text-debt ratchet + l10n own them) — a caption typed into the .tscn
	# would bypass both and ship unauthored. The scene must hold only structure.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button:
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text (the script sets it from PlayerText)" % n.name)
	inst.free()


## THE CARD'S LAYOUT PROMISES, measured on a laid-out OPEN card (a private in-tree instance, a real LevelUp station, a
## bare Player that never enters the tree) instead of read back off the .tscn's layout flags — so a designer may
## re-author the layout any way that keeps what the player sees:
##  * the dim covers the whole screen and the card floats inside it with an even border on every side, at the
##    PANEL_MARGIN fraction level_up_screen.gd documents for the authored anchors;
##  * the level and wallet readouts own a half of the header each, so a wallet grown to a pathological length is
##    trimmed inside its half and slides NEITHER readout (nor widens the card);
##  * a short stat list floats vertically CENTRED in the scroll's viewport rather than hugging its top.
func test_the_open_card_keeps_its_layout_promises() -> void:
	var screen := _screen()
	var lv := _station(50)
	lv.available_perks = [] as Array[Perk]  # stats only: the short list the centring exists for
	var player: Node = load(PLAYER_PATH).new()
	player.set(&"money", 100.0)
	var root := screen.get_node("%Root") as Control
	assert_false(root.visible, "control: the card is hidden until open_level_up")
	screen.open_level_up(lv, player)
	await wait_process_frames(2)  # containers sort on the frames after the card turns visible
	assert_true(screen.is_open() and root.visible, "a valid station with a live player opens the card")
	# The dim + the inset card.
	var full := Rect2(Vector2.ZERO, screen.get_viewport().get_visible_rect().size)
	assert_eq((screen.get_node("%Dim") as Control).get_global_rect(), full,
		"the dim covers the whole screen, so everything behind the card is dimmed evenly")
	var panel := screen.get_node("%Root/Panel") as Control
	var card: Rect2 = panel.get_global_rect()
	var margin: float = screen.PANEL_MARGIN
	var gaps := {
		"left": card.position.x - full.position.x, "right": full.end.x - card.end.x,
		"top": card.position.y - full.position.y, "bottom": full.end.y - card.end.y,
	}
	for side in gaps:
		var along: float = full.size.x if side == "left" or side == "right" else full.size.y
		assert_almost_eq(float(gaps[side]), along * margin, 1.0,
			"the card keeps a PANEL_MARGIN border on its %s side (card %s on screen %s) — content outgrowing the band would eat it" % [side, card, full])
	# The header halves hold still while the wallet grows.
	var level_label := screen.get_node("%LevelLabel") as Label
	var money_label := screen.get_node("%MoneyLabel") as Label
	var level_rect: Rect2 = level_label.get_global_rect()
	var money_rect: Rect2 = money_label.get_global_rect()
	assert_almost_eq(level_rect.size.x, money_rect.size.x, 1.0, "the level and wallet readouts split the header row into equal halves")
	player.set(&"money", 1.0e40)  # a pathological wallet
	screen._rebuild()  # the re-stamp every raise / rail flip runs
	await wait_process_frames(2)
	var natural: float = money_label.get_theme_font(&"font").get_string_size(
		money_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, money_label.get_theme_font_size(&"font_size")).x
	assert_gt(natural, money_rect.size.x,
		"control: the grown wallet string (%.0f px) is wider than its half (%.0f px), so a label sized to its text WOULD push the row" % [natural, money_rect.size.x])
	assert_eq(level_label.get_global_rect(), level_rect, "the level readout does not slide when the wallet grows")
	assert_eq(money_label.get_global_rect(), money_rect, "the wallet readout keeps its half, trimmed inside it, instead of growing")
	assert_eq(panel.get_global_rect(), card, "...and the card itself does not widen")
	# The short stat list centres in the scroll viewport.
	var scroll := screen.get_node("%VBox").get_node_or_null(^"Scroll") as Control
	var rows := screen.get_node("%Rows") as Control
	assert_true(scroll != null, "precondition: the stat list lives in a scroll inside the chrome VBox")
	if scroll != null:
		var view: Rect2 = scroll.get_global_rect()
		var list: Rect2 = rows.get_global_rect()
		var top_gap: float = list.position.y - view.position.y
		var bottom_gap: float = view.end.y - list.end.y
		assert_gt(top_gap + bottom_gap, 2.0,
			"precondition: six stat rows (%.0f px) are shorter than the scroll viewport (%.0f px), so there is slack to centre" % [list.size.y, view.size.y])
		assert_almost_eq(top_gap, bottom_gap, 1.0,
			"the short stat list floats CENTRED in the scroll viewport (top gap %.1f, bottom gap %.1f), not parked against its top" % [top_gap, bottom_gap])
	screen.close()
	lv.free()
	player.free()


func test_every_authored_button_is_reachable_by_a_pad() -> void:
	# ⭐THE HALF OF CONTROLLER PARITY THAT LIVES IN THE SCENE (the test_atm_screen_scene.gd pin, and the exact
	# regression class that screen once shipped): the one authored Button here — the rail selector — must NOT
	# carry `focus_mode = 0`; Button's own default FOCUS_ALL is what a pad navigates onto, so the regression is
	# always an authored override. Every OTHER action on this panel is a code-built row (_rebuild / _perk_row —
	# the runtime half below pins those), so an unfocusable rail selector would leave the scene authoring zero
	# focusable controls. Asserted on the instance rather than by grepping the .tscn, so it reads the value
	# that will actually exist at runtime.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var btn := inst.get_node("%RailButton") as Button
	assert_eq(btn.focus_mode, Control.FOCUS_ALL,
		"RailButton must take focus (no `focus_mode = 0` in the .tscn) — it is this panel's only authored Button and the pad's fallback landing spot")
	# ...on a station that LENDS. A LevelUp with `accepts_credit` off hides the selector (_rebuild calls
	# set_available(false)) and shows %CreditNotice instead, so on THAT card the fallback is gone — which is
	# why open_level_up's fallback branch also tests `_rail_btn.visible`, and why pad reachability really
	# rests on the code-built stat rows (FOCUS_ALL in _rebuild, seeded into _first_focus). Pinned below.
	assert_false((inst.get_node("%CreditNotice") as Label).visible,
		"CreditNotice ships HIDDEN — _rebuild reveals it only for a station that takes no credit, so a lending station's card is unchanged")
	inst.free()


## open_level_up grabs the mouse (ModalMenu.grab_mouse) and close() hands back what it found; restored here as well so
## a failed assert between the two can never leave the machine's cursor mode changed. GameState.account is read by
## the station's solvency gate (owes_the_ledger), so a balance left by another suite must not dim the card here.
var _prev_mouse_mode: Input.MouseMode
var _prev_account: float


func before_each() -> void:
	_prev_mouse_mode = Input.mouse_mode
	_prev_account = GameState.account
	GameState.account = 0.0


func after_each() -> void:
	Input.mouse_mode = _prev_mouse_mode
	GameState.account = _prev_account


## A private, IN-TREE instance of the authored scene (its own _ready binds the chrome — never the LevelUpScreen
## autoload), with nothing holding focus yet.
func _screen() -> Node:
	var screen: Node = (load(SCENE) as PackedScene).instantiate()
	add_child_autofree(screen)
	screen.get_viewport().gui_release_focus()
	return screen


## A real LevelUp station that never enters the tree (its _ready is not run), pricing every raise at `cost`, with one
## authored perk on offer so the perk rows are built too.
func _station(cost: int) -> LevelUp:
	var lv := LevelUp.new()
	lv.base_cost = cost
	lv.cost_per_level = 0.0
	var perk := Perk.new()
	perk.id = &"test_pad_perk"
	perk.display_name = "Pad Perk"
	lv.available_perks = [perk] as Array[Perk]
	return lv


## The live row Buttons in a %Rows / %Perks container (anything queued for deletion belongs to a stale build).
func _row_buttons(container: Node) -> Array[Button]:
	var out: Array[Button] = []
	for row in container.get_children():
		if row.is_queued_for_deletion():
			continue
		for c in row.get_children():
			if c is Button:
				out.append(c)
	return out


func test_the_pad_landing_spot_is_seeded_when_the_panel_opens() -> void:
	# ⭐THE RUNTIME HALF OF CONTROLLER PARITY, driven: open_level_up on a real station for a bare Player that never
	# enters the tree. The player is BROKE, so every stat row is a disabled can't-afford row — the case that most
	# needs the pad to still land somewhere (a disabled row keeps its focus, so navigation walks the dimmed rungs).
	var screen := _screen()
	var viewport := screen.get_viewport()
	var lv := _station(50)
	var player: Node = load(PLAYER_PATH).new()
	player.set(&"money", 0.0)
	assert_null(viewport.gui_get_focus_owner(), "control: nothing on the hidden card holds focus before it opens")
	screen.open_level_up(lv, player)
	assert_true(screen.is_open(), "a valid station with a live player opens")
	var stat_rows := _row_buttons(screen.get_node("%Rows"))
	assert_eq(stat_rows.size(), screen.STAT_ORDER.size(), "one raise row per stat")
	for b in stat_rows:
		assert_eq(b.focus_mode, Control.FOCUS_ALL,
			"every stat row must take focus — the rows ARE the pad path, and a control a pad can never land on is not a path")
	var perk_rows := _row_buttons(screen.get_node("%Perks"))
	assert_eq(perk_rows.size(), 1, "the station's one authored perk gets a row")
	for b in perk_rows:
		assert_eq(b.focus_mode, Control.FOCUS_ALL, "the perk picks must be pad-reachable too, not just the stat rows")
	if stat_rows.is_empty():
		return
	assert_true(stat_rows[0].disabled, "fixture: a broke player's first row is a can't-afford row")
	assert_eq(viewport.gui_get_focus_owner(), stat_rows[0],
		"open_level_up must SEED focus on the first stat row once the panel is visible — with no focus owner, ui navigation has nowhere to start and every row is unreachable")
	screen.close()
	assert_false(screen.is_open(), "the panel closes again")
	lv.free()
	player.free()


func test_a_rebuild_hands_focus_to_the_fresh_first_row_but_never_steals_it() -> void:
	# Every raise / perk pick / rail flip funnels through _rebuild, which frees the row that HELD focus — a pad left
	# with a dying owner has nowhere to navigate from. Only a dying owner is replaced: a control OUTSIDE the rows
	# keeps its place (the player parked on the rail selector).
	var screen := _screen()
	var viewport := screen.get_viewport()
	var lv := _station(0)   # free raises, so the rows are live
	var player: Node = load(PLAYER_PATH).new()
	screen.open_level_up(lv, player)
	var before := _row_buttons(screen.get_node("%Rows"))
	assert_gt(before.size(), 1, "fixture: the card built its stat rows")
	if before.size() < 2:
		screen.close()
		lv.free()
		player.free()
		return
	before[1].grab_focus()   # the pad moved down a row, then the player raised that stat
	screen._rebuild()
	var after := _row_buttons(screen.get_node("%Rows"))
	var owner := viewport.gui_get_focus_owner()
	assert_false(before.has(owner), "focus must not stay on a row the rebuild just freed")
	assert_eq(owner, after[0] if not after.is_empty() else null,
		"the rebuild re-seats the pad cursor on the fresh first stat row")
	var elsewhere := Button.new()   # any focusable outside %Rows / %Perks
	add_child_autofree(elsewhere)
	elsewhere.grab_focus()
	screen._rebuild()
	assert_eq(viewport.gui_get_focus_owner(), elsewhere,
		"control: a live owner outside the rows keeps focus — the re-seat only replaces a DYING owner")
	screen.close()
	lv.free()
	player.free()
