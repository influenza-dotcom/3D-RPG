extends GutTest

## THE DEBIT/CREDIT SELECTOR AT EVERY POINT OF SALE.
##
## The armed rail (`GameState.payment_method`) decides what `Player._split` may draw on, so it changes both the
## quoted total and the affordability dim. It used to be reachable ONLY from the ATM screen, which meant a player
## standing at a shop could see a price they couldn't afford under DEBIT and had no way to arm CREDIT without
## walking back to a terminal. `PaymentRailButton` is the shared drop-in that fixes that.
##
## ⭐WHAT THIS PINS is the wiring, because that is what silently rots: the selector is authored into five separate
## menu scenes, and a screen that carries the button but never connects `rail_changed` would toggle the rail while
## leaving its own prices and greyed-out rows stale — a card that lies about what the till will do.
##
## GameState is an autoload, so `payment_method` is shared mutable state: snapshot and restore it.

const SCREENS := {
	"shop": "res://scenes/ui/shop_screen.tscn",
	"heal": "res://scenes/ui/heal_screen.tscn",
	"level up": "res://scenes/ui/level_up_screen.tscn",
	"chip install": "res://scenes/ui/chip_install_screen.tscn",
	"respec": "res://scenes/ui/respec_screen.tscn",
}

const RAIL_SCRIPT := "res://scripts/ui/payment_rail_button.gd"

var _prev_method: String


func before_each() -> void:
	_prev_method = GameState.payment_method
	GameState.payment_method = Player.PAY_DEBIT


func after_each() -> void:
	GameState.payment_method = _prev_method


## Index of a named node in a SceneState, or -1.
func _node_index(state: SceneState, node_name: String) -> int:
	for i in range(state.get_node_count()):
		if state.get_node_name(i) == node_name:
			return i
	return -1


# --- The wiring, screen by screen -----------------------------------------------------------------------------

func test_every_paid_screen_authors_a_rail_button() -> void:
	# Checked against the PackedScene STATE rather than the live autoload: these screens' _ready builds real
	# chrome, and the point here is what a DESIGNER authored, not what runtime happened to produce.
	for label in SCREENS:
		var ps := load(SCREENS[label]) as PackedScene
		assert_not_null(ps, "%s screen must load" % label)
		var idx := _node_index(ps.get_state(), "RailButton")
		assert_gte(idx, 0,
			"the %s screen must author a RailButton — without it the player can only change rails at an ATM" % label)

func test_every_rail_button_carries_the_shared_script() -> void:
	# One script, five scenes. A hand-rolled copy on any screen would drift from the others (and from the ATM).
	for label in SCREENS:
		var ps := load(SCREENS[label]) as PackedScene
		var state := ps.get_state()
		var idx := _node_index(state, "RailButton")
		assert_gte(idx, 0, "the %s screen needs a RailButton before its script can be checked" % label)
		var found := false
		for p in range(state.get_node_property_count(idx)):
			if state.get_node_property_name(idx, p) == "script":
				var scr: Script = state.get_node_property_value(idx, p)
				found = scr != null and scr.resource_path == RAIL_SCRIPT
		assert_true(found, "the %s screen's RailButton must use the shared PaymentRailButton script" % label)

func test_every_paid_screen_connects_rail_changed() -> void:
	# ⭐THE ONE THAT MATTERS. A screen holding the button but ignoring its signal would flip the rail and leave
	# its own prices and dims stale. Source-grep, because the connection is made in _bind_ui at runtime.
	var sources := {
		"shop": "res://scripts/ui/shop_screen.gd",
		"heal": "res://scripts/ui/heal_screen.gd",
		"level up": "res://scripts/ui/level_up_screen.gd",
		"chip install": "res://scripts/ui/chip_install_screen.gd",
		"respec": "res://scripts/ui/respec_screen.gd",
	}
	for label in sources:
		var src := FileAccess.get_file_as_string(sources[label])
		assert_true("rail_changed.connect(" in src,
			"the %s screen must connect rail_changed to its repaint, or a toggle leaves its prices stale" % label)


# --- The button's own behaviour -------------------------------------------------------------------------------

func _button() -> PaymentRailButton:
	var b: PaymentRailButton = load(RAIL_SCRIPT).new()
	return b

func test_caption_reflects_the_armed_rail() -> void:
	var b := _button()
	GameState.payment_method = Player.PAY_DEBIT
	b.refresh()
	assert_eq(b.text, PlayerText.payment_rail_button(Player.PAY_DEBIT), "DEBIT caption")
	GameState.payment_method = Player.PAY_CREDIT
	b.refresh()
	assert_eq(b.text, PlayerText.payment_rail_button(Player.PAY_CREDIT), "CREDIT caption")
	assert_ne(PlayerText.payment_rail_button(Player.PAY_DEBIT), PlayerText.payment_rail_button(Player.PAY_CREDIT),
		"the two captions must actually differ, or the button tells the player nothing")
	b.free()

func test_press_toggles_the_rail_both_ways() -> void:
	var b := _button()
	GameState.payment_method = Player.PAY_DEBIT
	b._on_pressed()
	assert_eq(GameState.payment_method, Player.PAY_CREDIT, "debit -> credit")
	b._on_pressed()
	assert_eq(GameState.payment_method, Player.PAY_DEBIT, "credit -> debit (it is a toggle, not a one-way arm)")
	b.free()

func test_press_emits_rail_changed() -> void:
	var b := _button()
	watch_signals(b)
	b._on_pressed()
	assert_signal_emitted(b, "rail_changed", "a toggle must tell its host screen to re-price")
	b.free()

func test_toggle_repaints_its_own_caption() -> void:
	var b := _button()
	GameState.payment_method = Player.PAY_DEBIT
	b._on_pressed()
	assert_eq(b.text, PlayerText.payment_rail_button(Player.PAY_CREDIT),
		"the caption must follow the toggle without waiting for the host's refresh")
	b.free()

func test_set_available_false_hides_it() -> void:
	# A cash-only merchant (accepts_ledger off) honours no rail at all, so the selector hides rather than
	# offering a choice that does nothing.
	var b := _button()
	b.set_available(false)
	assert_false(b.visible, "an unavailable rail selector must hide")
	b.refresh()
	assert_false(b.visible, "...and a later refresh must not resurrect it")
	b.set_available(true)
	assert_true(b.visible, "...and it comes back when the vendor does take the ledger")
	b.free()

func test_toggling_actually_moves_what_the_player_can_afford() -> void:
	# End to end: the button writes the rail, and the rail is what the ONE affordability predicate reads. This is
	# the whole reason the control exists — under DEBIT the purchase is refused, under CREDIT it clears.
	var p = load("res://scripts/player/player.gd").new()
	p.money = 10.0
	var sheet := CharacterStats.new()
	sheet.gunplay = 10
	sheet.strength = 10
	p.stats = sheet
	var prev_account := GameState.account
	var prev_profile := GameState.profile_active
	GameState.account = 0.0
	GameState.profile_active = true
	var b := _button()
	GameState.payment_method = Player.PAY_DEBIT
	assert_false(p.can_pay(100.0), "under DEBIT a near-empty wallet can't cover 100")
	b._on_pressed()  # arm CREDIT
	assert_true(p.can_pay(100.0), "arming CREDIT at the till lets the line cover it — the point of the button")
	b.free()
	p.free()
	GameState.account = prev_account
	GameState.profile_active = prev_profile
