extends GutTest

## AUTHORED-SCENE wiring contract for ChipInstallScreen (scenes/ui/chip_install_screen.tscn +
## chip_install_screen.gd), mirroring the heal_screen exemplar. Prefab WIRING tests (the silent-when-broken
## seams): the autoload points at the SCENE, every %node the script binds exists, no text is authored in the
## scene (strings belong to PlayerText / l10n, never a .tscn), and the screen-specific layout discipline
## (PANEL_MARGIN band, twin expanding section scrolls, right-aligned wallet) survives the conversion.
## Behaviour (open/install/buy) is in-tree -> playtest + test_chip_install.gd — with ONE exception, the
## two-stage commit at the bottom of this file, whose whole state machine runs off-tree with no till behind it.
##
## ⭐AND IT PINS CONTROLLER PARITY (the test_atm_screen_scene pair), which this screen shipped without: the
## authored rail selector carried `focus_mode = 0` and _make_row stripped every runtime row to FOCUS_NONE, so
## the card had NO focusable control at all — ui navigation had nowhere to start and a pad player could not
## install, buy, flip the rail, or reach anything. The scene half and the runtime half are pinned separately
## below; the runtime half (and the commit routing / disarm exits) runs a private IN-TREE instance of the scene
## opened for a bare off-tree ChipInstaller + Player (the test_chip_install idiom — no Player._ready runs).

const SCENE := "res://scenes/ui/chip_install_screen.tscn"
const SCREEN_SOURCE := "res://scripts/ui/chip_install_screen.gd"
const PLAYER_PATH := "res://scripts/player/player.gd"

## Every unique name chip_install_screen.gd binds in _bind_ui — a rename in the editor breaks the bind at
## boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "Content", "Title", "MoneyInset", "MoneyPlayer", "RailButton",
	"CarriedInset", "CarriedHeading", "CarriedList", "StockInset", "StockHeading", "StockList"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "ChipInstallScreen", "")), "*" + SCENE,
		"the ChipInstallScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_true(inst.get_script() != null and String(inst.get_script().resource_path) == SCREEN_SOURCE,
		"the root carries chip_install_screen.gd (the script whose _bind_ui reads these names)")
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


func test_authored_chrome_keeps_the_layout_contracts() -> void:
	# The screen-specific discipline survives the scene conversion: the PANEL_MARGIN anchor band, the two
	# stacked full-width sections whose scrolls EXPAND vertically (they share the leftover panel height
	# 50/50), the right-aligned expanding wallet readout, and full-screen root/dim.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open_install")
	# The modal inset band — authored anchors must match the script's PANEL_MARGIN pin.
	var margin: float = load(SCREEN_SOURCE).PANEL_MARGIN
	var panel := (inst.get_node("%Content") as Control).get_parent() as PanelContainer
	assert_not_null(panel, "%Content sits in the anchored PanelContainer band")
	assert_almost_eq(panel.anchor_left, margin, 0.0001, "Panel's left anchor is the shared PANEL_MARGIN inset")
	assert_almost_eq(panel.anchor_top, margin, 0.0001, "Panel's top anchor is the shared PANEL_MARGIN inset")
	assert_almost_eq(panel.anchor_right, 1.0 - margin, 0.0001, "Panel's right anchor mirrors PANEL_MARGIN")
	assert_almost_eq(panel.anchor_bottom, 1.0 - margin, 0.0001, "Panel's bottom anchor mirrors PANEL_MARGIN")
	# Twin sections: each row list lives in a ScrollContainer that expands BOTH ways (the 50/50 height
	# split) with horizontal scrolling disabled (rows shrink to the panel width, never scroll sideways).
	for list_name in ["CarriedList", "StockList"]:
		var list := inst.get_node("%" + list_name) as VBoxContainer
		assert_eq(list.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s rows fill the section width" % list_name)
		var scroll := list.get_parent() as ScrollContainer
		assert_not_null(scroll, "%s lives in its section ScrollContainer" % list_name)
		assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "%s's scroll expands vertically (50/50 height share)" % list_name)
		assert_eq(scroll.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s's scroll expands horizontally" % list_name)
		assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "%s's scroll never scrolls sideways" % list_name)
	# Wallet readout: right-aligned and EXPAND_FILL so the money phrase lands on the price column's edge.
	var money := inst.get_node("%MoneyPlayer") as Label
	assert_eq(money.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT, "the wallet readout right-aligns onto the price column")
	assert_eq(money.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the wallet readout spans the row to reach that edge")
	assert_true(inst.get_node("%MoneyInset") is MarginContainer, "the wallet rides a row-inset MarginContainer (margins applied at runtime from the theme)")
	inst.free()


func test_every_authored_button_is_reachable_by_a_pad() -> void:
	# ⭐THE HALF OF CONTROLLER PARITY THAT LIVES IN THE SCENE (the test_atm_screen_scene pin, same argument): the
	# rail selector is this screen's ONE authored Button, and it shipped `focus_mode = 0` — combined with the
	# focus-stripped runtime rows, the card had no focus owner to navigate FROM. Asserted on the instance rather
	# than by grepping the .tscn, so it reads the value that will actually exist at runtime (Button's own default
	# is FOCUS_ALL — the regression is an authored override).
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var btn := inst.get_node("%RailButton") as Button
	assert_eq(btn.focus_mode, Control.FOCUS_ALL,
		"RailButton must take focus (no `focus_mode = 0` in the .tscn) — a pad reaches this screen's actions through the Buttons alone")
	inst.free()


# ---------------------------------------------------------------------------------------------------
# THE LIVE CARD — a private in-tree instance of the authored scene, opened for real
# ---------------------------------------------------------------------------------------------------

## open_install grabs the mouse and the till reads the shared GameState banking fields; all restored per test.
var _prev_mouse_mode: Input.MouseMode
var _prev_account: float
var _prev_method: String


func before_each() -> void:
	_prev_mouse_mode = Input.mouse_mode
	_prev_account = GameState.account
	_prev_method = GameState.payment_method
	GameState.account = 0.0          # a stale positive account would fund an install the wallet couldn't cover
	GameState.payment_method = "debit"


func after_each() -> void:
	Input.mouse_mode = _prev_mouse_mode
	GameState.account = _prev_account
	GameState.payment_method = _prev_method


## A private screen: the authored scene added to the tree so _ready/_bind_ui run — never the ChipInstallScreen autoload.
func _live_screen() -> Node:
	var screen: Node = (load(SCENE) as PackedScene).instantiate()
	add_child_autofree(screen)
	return screen


## An off-tree mechanic with a hand-built (empty) stock, the test_chip_install idiom.
func _mechanic() -> ChipInstaller:
	var m := ChipInstaller.new()
	m.stock = CharacterInventory.new()
	m.install_mult = 0.5
	m.buy_mult = 1.25
	m.min_fee = 10
	return m


## A bare off-tree Player with a backpack and cash (its _ready never runs).
func _customer(money: float) -> Node:
	var p: Node = load(PLAYER_PATH).new()
	p.set(&"inventory", CharacterInventory.new())
	p.set(&"money", money)
	return p


## A real, installable upgrade chip (the grapple ability resolves through the registry).
func _grapple_chip() -> Item:
	var it := Item.new()
	it.id = &"chip_grapple"
	it.display_name = "Test Chip"
	it.category = Item.Category.MISC
	it.value = 400.0
	it.installs_ability = &"grapple"
	return it


## The row Buttons the LAST rebuild put in `list` (rows queued for deletion belong to an older build).
func _live_rows(list: Node) -> Array:
	return list.get_children().filter(func(c: Node) -> bool: return c is Button and not c.is_queued_for_deletion())


func _close_and_free(screen: Node, m: ChipInstaller, p: Node) -> void:
	if screen.is_open():
		screen.close()  # disconnects the bag / stock / unlock signals before their sources are freed
	m.stock.free()
	m.free()
	(p.get(&"inventory") as Node).free()
	p.free()


func test_the_pad_landing_spot_is_seeded_when_the_card_opens() -> void:
	# The runtime half of parity: _fill/_make_row build the rows FOCUS_ALL and open_install seeds focus on the first
	# one once the card is up. With no focus owner, ui navigation has nowhere to start and a pad cannot install.
	var screen := _live_screen()
	var m := _mechanic()
	var p := _customer(1000.0)
	(p.get(&"inventory") as CharacterInventory).add(_grapple_chip(), 1)
	screen.open_install(m, p)
	assert_true(screen.is_open(), "a real installer serving a player carrying a chip opens")
	var rows := _live_rows(screen.get_node("%CarriedList"))
	assert_eq(rows.size(), 1, "the carried chip gets one install row")
	if rows.size() == 1:
		assert_eq((rows[0] as Button).focus_mode, Control.FOCUS_ALL,
			"install rows must take focus — the rows ARE the pad path, and a control a pad can never land on is not a path")
		assert_eq(screen.get_viewport().gui_get_focus_owner(), rows[0],
			"open_install must SEED focus on the first install row — with no focus owner every control is pad-unreachable")
	_close_and_free(screen, m, p)


func test_an_empty_card_seeds_the_rail_selector_instead() -> void:
	# Nothing carried, nothing stocked: both lists hold hint Labels only, so the one authored Button — the rail
	# selector — must take the seed, or the card opens with no focus owner at all.
	var screen := _live_screen()
	var m := _mechanic()
	var p := _customer(1000.0)
	screen.open_install(m, p)
	assert_true(screen.is_open(), "an installer with nothing to offer still opens")
	assert_eq(_live_rows(screen.get_node("%CarriedList")).size() + _live_rows(screen.get_node("%StockList")).size(), 0,
		"control: the card really has no install rows to seed")
	assert_eq(screen.get_viewport().gui_get_focus_owner(), screen.get_node("%RailButton"),
		"with no rows, the rail selector takes the pad landing spot")
	_close_and_free(screen, m, p)


# ---------------------------------------------------------------------------------------------------
# THE TWO-STAGE COMMIT (chip_install_screen.gd _on_row_pressed / _arm / _disarm_unless / _paint_row)
# ---------------------------------------------------------------------------------------------------
#
# ⭐WHAT THIS SECTION EXISTS FOR: installing is the most irreversible act in the economy — it spends the money
# AND CONSUMES THE CHIP — and it ran off ONE click on a row captioned with nothing but the chip's name. In the
# QA shot that single click stood between 202 zorkmids and 2, with no confirm and no on-screen word about what
# the ability even does. A row now ARMS on its first press and only charges on a second press of that SAME row.
#
# Exercised on a bare `instantiate()` (never added to the tree, so `_ready`/`_bind_ui` never run): the arm state
# machine touches only `_rows`, `_armed_item` and two Labels, and both commit paths bail on the null `_installer`
# — so the whole decision can be driven off-tree while the CHARGE stays unreachable. That is the point: these
# tests can prove a press does NOT spend money precisely because there is no till wired up behind them.

## A bare screen instance with `_ready` unrun — see the block note above.
func _screen() -> Node:
	return (load(SCENE) as PackedScene).instantiate()

## A stand-in chip Item (label() falls back to the id, which is all the row paints).
func _chip(id: StringName) -> Item:
	var it := Item.new()
	it.id = id
	return it

## One row record in the exact shape `_make_row` appends to `_rows`, minus the Button (nothing under test reads
## it). The two Labels are the row's real cells — the caller frees them.
func _row_rec(item: Item, is_buy: bool, charge: float) -> Dictionary:
	return {
		"btn": null, "name": Label.new(), "price": Label.new(),
		"item": item, "is_buy": is_buy, "charge": charge,
		"label": item.label(), "affordable": true,
	}

func _free_rows(recs: Array) -> void:
	for r: Dictionary in recs:
		(r["name"] as Label).free()
		(r["price"] as Label).free()


func test_the_first_press_arms_the_row_and_states_the_price() -> void:
	var s := _screen()
	var chip := _chip(&"takedown")
	var rec := _row_rec(chip, false, 200.0)
	s._rows = [rec]
	s._paint_row(rec)
	assert_eq((rec["name"] as Label).text, chip.label(), "at rest the row is just the chip's name")
	s._on_row_pressed(chip, false)
	assert_eq(s._armed_item, chip, "the FIRST press ARMS the row — it must never reach the till")
	assert_eq((rec["name"] as Label).text, chip.label(),
		"...the NAME stays put — the moment the player is about to spend is the moment the row must still say what it is")
	assert_eq((rec["price"] as Label).text, PlayerText.chip_install_confirm(200.0),
		"...and the PRICE cell becomes the confirm, which states what a second press will actually cost (the money phrase once)")
	_free_rows([rec])
	s.free()

func test_the_second_press_spends_the_arm() -> void:
	# With no installer wired the commit itself is a no-op, which is exactly what makes this pin safe to run: what
	# it proves is that the arm is CONSUMED by the confirm press rather than left standing. A row still armed after
	# a commit (or after a refusal) would charge on the next single click — the very thing this feature prevents.
	var s := _screen()
	var chip := _chip(&"takedown")
	var rec := _row_rec(chip, false, 200.0)
	s._rows = [rec]
	s._on_row_pressed(chip, false)
	assert_eq((rec["price"] as Label).text, PlayerText.chip_install_confirm(200.0),
		"precondition: the armed row's PRICE cell carries the confirm caption, so the repaint below has a caption to take back")
	assert_ne(Zorkmids.money_text(200.0), PlayerText.chip_install_confirm(200.0),
		"control: the resting price and the confirm caption read differently, so the cell text below can tell the two states apart")
	s._on_row_pressed(chip, false)
	assert_null(s._armed_item, "the confirm press spends the arm")
	assert_eq((rec["price"] as Label).text, Zorkmids.money_text(200.0),
		"and the row's PRICE cell repaints back to its resting price — a confirm caption left on a disarmed row is a lie about the next click (with no installer wired this is the REFUSED-commit path, which keeps the same rows)")
	_free_rows([rec])
	s.free()

func test_moving_to_another_row_disarms_the_first() -> void:
	# The hover / pad-focus edge. Without it an arm set on row A could be spent by a click the player believes is
	# landing on row B — the same accident the two-stage commit exists to make impossible.
	var s := _screen()
	var a := _chip(&"takedown")
	var b := _chip(&"airdash")
	var rec_a := _row_rec(a, false, 200.0)
	var rec_b := _row_rec(b, true, 350.0)
	s._rows = [rec_a, rec_b]
	s._on_row_pressed(a, false)
	assert_eq((rec_a["price"] as Label).text, PlayerText.chip_install_confirm(200.0),
		"precondition: row A is armed and its PRICE cell shows the confirm caption")
	s._disarm_unless(b, true)
	assert_null(s._armed_item, "crossing onto another row drops the arm")
	assert_eq((rec_a["price"] as Label).text, Zorkmids.money_text(200.0),
		"and the row that was armed repaints its PRICE cell back to the resting price — a confirm caption left behind would still promise the next click a commit")
	s._on_row_pressed(a, false)
	s._disarm_unless(a, false)
	assert_eq(s._armed_item, a, "staying on the SAME row keeps the arm — a re-hover is not a change of mind")
	_free_rows([rec_a, rec_b])
	s.free()

func test_pressing_a_different_row_moves_the_arm_instead_of_committing() -> void:
	var s := _screen()
	var a := _chip(&"takedown")
	var b := _chip(&"airdash")
	var rec_a := _row_rec(a, false, 200.0)
	var rec_b := _row_rec(b, true, 350.0)
	s._rows = [rec_a, rec_b]
	s._on_row_pressed(a, false)
	s._on_row_pressed(b, true)
	assert_eq(s._armed_item, b, "the press lands on the row it was made on")
	assert_true(s._armed_is_buy, "...including WHICH list that row lives in — carried and stock rows are never confused")
	assert_eq((rec_a["price"] as Label).text, Zorkmids.money_text(float(rec_a["charge"])), "the previously armed row stands down to its price")
	assert_eq((rec_b["price"] as Label).text, PlayerText.chip_install_confirm(350.0), "and the new one arms")
	_free_rows([rec_a, rec_b])
	s.free()

func test_a_row_press_only_arms_and_the_second_press_on_it_installs() -> void:
	# The WIRING half the bare instance above cannot reach: the row Button's own `pressed` must run through the
	# two-stage commit. A row connected straight at _install would spend the money and destroy the chip on ONE click.
	var screen := _live_screen()
	var m := _mechanic()
	var p := _customer(1000.0)
	var chip := _grapple_chip()
	(p.get(&"inventory") as CharacterInventory).add(chip, 1)
	screen.open_install(m, p)
	var rows := _live_rows(screen.get_node("%CarriedList"))
	assert_eq(rows.size(), 1, "the carried chip gets one install row")
	if rows.size() == 1:
		(rows[0] as Button).pressed.emit()
		assert_eq(screen._armed_item, chip, "the first press on the row ARMS it")
		assert_eq(float(p.get(&"money")), 1000.0, "...and charges nothing")
		assert_true((p.get(&"inventory") as CharacterInventory).has(chip), "...and the chip is still in the bag")
		(rows[0] as Button).pressed.emit()
		assert_lt(float(p.get(&"money")), 1000.0, "the second press on the SAME row pays the installer")
		assert_false((p.get(&"inventory") as CharacterInventory).has(chip), "...and consumes the chip")
		assert_true(p.call(&"has_mechanic", &"grapple"), "...and the ability comes online")
		assert_null(screen._armed_item, "the confirm press spends the arm")
	_close_and_free(screen, m, p)


func test_a_rebuild_disarms_so_a_stale_arm_cannot_be_spent_by_one_click() -> void:
	# Every bag / stock / rail change funnels into _rebuild, and the total the armed row was quoting may now be stale.
	# If the arm survived, the rebuilt row for the SAME chip would install on its very next single press.
	var screen := _live_screen()
	var m := _mechanic()
	var p := _customer(1000.0)
	var chip := _grapple_chip()
	var bag := p.get(&"inventory") as CharacterInventory
	bag.add(chip, 1)
	screen.open_install(m, p)
	var rows := _live_rows(screen.get_node("%CarriedList"))
	assert_eq(rows.size(), 1, "the carried chip gets one install row")
	if rows.size() == 1:
		(rows[0] as Button).pressed.emit()
		assert_eq(screen._armed_item, chip, "the row is armed before the bag changes")
		var trinket := Item.new()
		trinket.id = &"test_trinket"
		bag.add(trinket, 1)  # the bag's `changed` is bound -> _rebuild
		assert_null(screen._armed_item, "a rebuild drops the arm")
		var rebuilt := _live_rows(screen.get_node("%CarriedList"))
		assert_eq(rebuilt.size(), 1, "the rebuild re-lists the chip")
		if rebuilt.size() == 1:
			(rebuilt[0] as Button).pressed.emit()
			assert_eq(float(p.get(&"money")), 1000.0, "one press on the rebuilt row only re-arms it — nothing is charged")
			assert_true(bag.has(chip), "...and the chip is not consumed")
	_close_and_free(screen, m, p)


func test_closing_the_card_disarms_the_armed_row() -> void:
	# Walking away from the card IS a cancel: an arm that survived close() is pending money on a screen that is gone.
	var screen := _live_screen()
	var m := _mechanic()
	var p := _customer(1000.0)
	var chip := _grapple_chip()
	(p.get(&"inventory") as CharacterInventory).add(chip, 1)
	screen.open_install(m, p)
	var rows := _live_rows(screen.get_node("%CarriedList"))
	assert_eq(rows.size(), 1, "the carried chip gets one install row")
	if rows.size() == 1:
		(rows[0] as Button).pressed.emit()
		assert_eq(screen._armed_item, chip, "the row is armed before the card closes")
	screen.close()
	assert_false(screen.is_open(), "the card closed")
	assert_null(screen._armed_item, "close() drops the arm")
	assert_eq(float(p.get(&"money")), 1000.0, "closing an armed card charges nothing")
	_close_and_free(screen, m, p)
