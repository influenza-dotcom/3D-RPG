extends GutTest

## THE DEBIT/CREDIT SELECTOR AT EVERY POINT OF SALE.
##
## The armed rail (`GameState.payment_method`) decides what `Player._split` may draw on, so it moves the
## affordability dim (the all-in quoted total is rail-invariant — the service fee rides the cash shortfall
## whichever rail funds it; test_payment.gd pins that). It used to be reachable ONLY from the ATM screen, which meant a player
## standing at a shop could see a price they couldn't afford under DEBIT and had no way to arm CREDIT without
## walking back to a terminal. `PaymentRailButton` is the shared drop-in that fixes that.
##
## ⭐WHAT THIS PINS is the wiring, because that is what silently rots: the selector is authored into six separate
## menu scenes, and a screen that carries the button but never connects `rail_changed` would toggle the rail while
## leaving its own prices and greyed-out rows stale — a card that lies about what the till will do.
##
## ⭐AND IT PINS THE AFFORDANCE (the second block below), because that rotted too: shipped as a full-width button
## captioned "Paying with: Debit", the control read as a status line and QA never discovered the rail could be
## changed at a till at all. The shape lives in the drop-in so one fix covers all six hosts — which is exactly
## why it needs a test here rather than six scene tests.
##
## GameState is an autoload, so `payment_method` is shared mutable state: snapshot and restore it.

const SCREENS := {
	"shop": "res://scenes/ui/shop_screen.tscn",
	"heal": "res://scenes/ui/heal_screen.tscn",
	"level up": "res://scenes/ui/level_up_screen.tscn",
	"chip install": "res://scenes/ui/chip_install_screen.tscn",
	"respec": "res://scenes/ui/respec_screen.tscn",
	"weapon bench": "res://scenes/ui/weapon_bench_screen.tscn",
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
		"weapon bench": "res://scripts/ui/weapon_bench_screen.gd",
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
	assert_string_contains(b.text, PlayerText.payment_rail_button(Player.PAY_DEBIT))
	GameState.payment_method = Player.PAY_CREDIT
	b.refresh()
	assert_string_contains(b.text, PlayerText.payment_rail_button(Player.PAY_CREDIT))
	assert_ne(PlayerText.payment_rail_button(Player.PAY_DEBIT), PlayerText.payment_rail_button(Player.PAY_CREDIT),
		"the two captions must actually differ, or the button tells the player nothing")
	b.free()

func test_the_caption_shows_that_it_cycles() -> void:
	# ⭐THE DEFECT THIS CONTROL SHIPPED WITH. "Paying with: Debit" is a colon-terminated statement of state, and
	# on a full-width button it reads as a status banner — screenshot QA of the heal / shop / respec / chip-install
	# cards took it for a readout every time and never learned that CREDIT can be armed at a till at all. The
	# caption is now flanked with the skin's cycler step glyphs, this game's existing "you can cycle this" dialect.
	# ⭐Asserted against the SKIN's glyphs, never against a literal "<": the pixel font has no guillemets, so the
	# pair is a designer knob (a locale or an art pass may swap it) and hardcoding one here would outlaw that.
	var b := _button()
	b.refresh()
	var prev: String = MenuStyle.skin.cycler_prev_glyph
	var next: String = MenuStyle.skin.cycler_next_glyph
	assert_true(b.text.begins_with(prev), "the caption opens with the skin's PREV cycler glyph: %s" % b.text)
	assert_true(b.text.ends_with(next), "...and closes with its NEXT twin (the half a clip would eat first): %s" % b.text)
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
	assert_string_contains(b.text, PlayerText.payment_rail_button(Player.PAY_CREDIT))
	b.free()


# --- It must read as a BUTTON, not as the card's banner -------------------------------------------------------

## The selector inside a real menu-themed parent, so the font it measures itself against is the one it will
## actually be painted in. add_child_autofree runs its _ready (and the theme notification) exactly as a host does.
func _mounted_button() -> PaymentRailButton:
	var host := Control.new()
	MenuStyle.apply(host)          # the same call every host screen makes on its %Root before binding chrome
	add_child_autofree(host)
	var b: PaymentRailButton = load(RAIL_SCRIPT).new()
	MenuStyle.cap_button(b)        # hosts all do this — clip_text, which is why the pinned width has to FIT
	host.add_child(b)
	return b

func test_it_stops_filling_the_card() -> void:
	# The authored Button is a plain container child (size flags default to FILL), which on the five VBox cards is
	# the FULL PANEL WIDTH — wider and brighter than the Confirm/Cancel pair below it, which is what made the eye
	# read it as the primary control. It demotes itself to a fixed-width chip instead. Set in the drop-in and not
	# in six .tscn files on purpose: one edit, one shape, every till.
	var b := _mounted_button()
	assert_eq(b.size_flags_horizontal, Control.SIZE_SHRINK_CENTER,
		"the rail selector must shrink to a button-sized chip rather than span its card")
	assert_gte(b.custom_minimum_size.x, float(MenuStyle.skin.dialog_button_min_width),
		"...and still be at least a dialog button wide, so shrinking never turns it into a sliver")

func test_the_pinned_width_never_moves_when_the_rail_flips() -> void:
	# ⭐THE MENUS-MUST-NOT-RESIZE-WITH-TEXT RULE, at the one control whose caption changes under the cursor.
	# "Credit" is a letter wider than "Debit", so a button sized to its LIVE caption would visibly grow and shrink
	# on every flip. The pin is measured over BOTH rails and takes the wider, so the box never moves.
	var b := _mounted_button()
	GameState.payment_method = Player.PAY_DEBIT
	b.refresh()
	var on_debit := b.custom_minimum_size.x
	GameState.payment_method = Player.PAY_CREDIT
	b.refresh()
	assert_eq(b.custom_minimum_size.x, on_debit,
		"the selector must be the same width on both rails — it is measured over the pair, not over what is shown")

func test_the_pinned_width_fits_the_caption_it_paints() -> void:
	# The floor alone is not enough: every host cap_button()s this control, so a caption wider than the pinned box
	# is CLIPPED — and the first thing off the right edge would be the closing chevron, i.e. the whole affordance.
	# Measured with the same font the button paints in (see _mounted_button).
	var b := _mounted_button()
	b.refresh()
	var f: Font = b.get_theme_font(&"font")
	assert_not_null(f, "the mounted button must resolve a font, or this pin measures nothing")
	var text_w := f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, b.get_theme_font_size(&"font_size")).x
	assert_gte(b.custom_minimum_size.x, text_w,
		"the pinned width must fit the caption (%s) or clip_text eats the trailing cycler glyph" % b.text)

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
