extends GutTest

## BEHAVIOUR for the implant-purchase step (implant_choice.gd) + its StartMenu flow seams. Implants are
## bought ON CREDIT at New Game: any set of chips may be checked (multi-select, no opt-out row — an empty
## cart is the default), the bill is each chip's authored Item.value, and the profile stamp debits it
## straight from GameState.money — the ONE home of the (negative-capable) balance, read by the Player's
## profile_active wallet branch on every loaded=false boot of a created run. The screen goes IN-TREE via add_child_autofree of the AUTHORED scene (its _ready runs
## _bind_ui + builds the roster; a bare-script .new() would null-deref the %binds — the
## test_character_creation idiom). The StartMenu seams are driven directly on a start_menu instance WITHOUT
## booting: _stamp_new_game_profile is split from _on_implant_confirmed precisely so the reset+stamp is
## testable without _start_game. Scene wiring lives in tests/test_implant_choice_scene.gd.

const SCENE := "res://scenes/ui/implant_choice.tscn"
const START_MENU_SCENE := "res://scenes/start_menu.tscn"
const ABILITY_REGISTRY := "res://scripts/components/abilities/ability_registry.gd"

# _make_menu forces the Settings boot flags, so snapshot/restore them around EVERY test (the
# test_start_menu.gd idiom) — a later suite's save_settings() flush would otherwise persist the forced
# values to the dev's real settings.cfg (recording TOS consent / clearing debug_skip_menu on disk).
var _prev_skip: bool
var _prev_tos: bool

func before_each() -> void:
	_prev_skip = Settings.debug_skip_menu
	_prev_tos = Settings.tos_accepted

func after_each() -> void:
	Settings.debug_skip_menu = _prev_skip
	Settings.tos_accepted = _prev_tos


func _make_screen() -> Control:
	var inst: Control = (load(SCENE) as PackedScene).instantiate()
	add_child_autofree(inst)
	return inst


## The roster the screen SHOULD offer: ability -> its chip's quantized value, recomputed from the same seams
## (ItemDb + AbilityRegistry.can_build + the value>0 fail-closed rule) so a new chip .tres dropped in
## resources/items/ moves both sides of the assertion together.
func _expected_prices() -> Dictionary:
	var reg := load(ABILITY_REGISTRY)
	var out := {}
	for item: Item in ItemDb.all_items():
		if item != null and item.is_upgrade_chip() and item.value > 0.0 \
				and reg.can_build(item.installs_ability) and not out.has(item.installs_ability):
			out[item.installs_ability] = snappedf(item.value, Zorkmids.QUANTUM)
	return out


func test_roster_offers_each_installable_ability_once_at_its_chip_value() -> void:
	var s := _make_screen()
	var expected := _expected_prices()
	assert_gt(expected.size(), 0, "the shipped chip catalog yields a non-empty roster")
	var rows: Array = s._rows
	assert_eq(rows.size(), expected.size(),
		"one row per distinct installable ability — no opt-out row (an empty cart is the default)")
	var offered := {}
	for r in rows:
		var id: StringName = (r as Button).get_meta("ability_id")
		assert_false(offered.has(id), "ability '%s' is offered only once (dedupe by ability id)" % id)
		assert_true(expected.has(id), "row ability '%s' is a real buildable chip ability" % id)
		assert_eq(float((r as Button).get_meta("price")), float(expected[id]),
			"row '%s' is billed at its chip's authored Item.value — the ONE price formula" % id)
		offered[id] = true
	assert_eq(offered.size(), expected.size(), "every buildable chip ability gets a row")


func test_begin_is_never_gated_and_an_empty_cart_confirms_debt_free() -> void:
	var s := _make_screen()
	assert_false((s.get_node("%BeginButton") as Button).disabled,
		"Begin is never gated — buying nothing is the legal debt-free default")
	watch_signals(s)
	s._on_begin()
	assert_signal_emitted_with_parameters(s, "confirmed", [[], 0.0])


func test_checked_rows_confirm_their_ids_and_summed_bill() -> void:
	var s := _make_screen()
	watch_signals(s)
	var a := s._rows[0] as Button
	var b := s._rows[1] as Button
	a.button_pressed = true  # emits toggled -> _refresh_tally
	b.button_pressed = true
	var want_cost: float = snappedf(float(a.get_meta("price")) + float(b.get_meta("price")), Zorkmids.QUANTUM)
	s._on_begin()
	assert_signal_emitted_with_parameters(s, "confirmed",
		[[a.get_meta("ability_id"), b.get_meta("ability_id")], want_cost])


func test_unchecking_a_row_takes_it_off_the_bill() -> void:
	var s := _make_screen()
	var a := s._rows[0] as Button
	var b := s._rows[1] as Button
	a.button_pressed = true
	b.button_pressed = true
	a.button_pressed = false  # independent toggles — no ButtonGroup radio latch
	watch_signals(s)
	s._on_begin()
	assert_signal_emitted_with_parameters(s, "confirmed",
		[[b.get_meta("ability_id")], float(b.get_meta("price"))])


func test_tally_shows_the_bill_and_projected_balance() -> void:
	var s := _make_screen()
	var base: float = GameSettings.economy.player_starting_money
	var tally := s.get_node("%Tally") as Label
	assert_eq(tally.text, PlayerText.implant_choice_tally(0.0, base),
		"the tally boots at a zero bill and the untouched base balance")
	var a := s._rows[0] as Button
	a.button_pressed = true
	var cost: float = float(a.get_meta("price"))
	assert_eq(tally.text, PlayerText.implant_choice_tally(cost, snappedf(base - cost, Zorkmids.QUANTUM)),
		"checking a chip re-tallies: the SAME formula feeds the display and the confirmed payload")


func test_back_emits_cancelled() -> void:
	var s := _make_screen()
	watch_signals(s)
	s._on_back()
	assert_signal_emitted(s, "cancelled", "Back hands control back to StartMenu (which resumes creation)")


# --- StartMenu flow seams (no boot: _start_game is never reached) ------------------------------------------

func _make_menu() -> Node:
	# Isolate from the debug straight-to-game boot + first-launch gates (the test_start_menu idiom).
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true
	var menu: Node = (load(START_MENU_SCENE) as PackedScene).instantiate()
	add_child_autofree(menu)
	return menu


func test_creation_begin_raises_the_implant_step_instead_of_booting() -> void:
	var menu := _make_menu()
	var prior_name: String = GameState.player_name
	menu._on_character_confirmed("Chooms", {&"strength": 2}, {})
	assert_not_null(menu._implant_choice, "Begin on creation raises the implant step")
	assert_false(menu._loading, "the boot is DEFERRED to the implant confirm")
	assert_eq(GameState.player_name, prior_name, "the profile is untouched until the implant confirm")
	menu._on_implant_cancelled()
	assert_null(menu._implant_choice, "Back drops the implant step")


func test_stamp_bills_the_cart_into_debt_after_the_reset() -> void:
	var menu := _make_menu()
	menu._pending_creation = ["Chooms", {&"strength": 2}, {}]
	menu._stamp_new_game_profile([&"air_dash", &"grapple"], 850.0)
	var base: float = GameSettings.economy.player_starting_money
	assert_eq(GameState.player_name, "Chooms", "the stashed name is stamped after the reset")
	assert_true(GameState.unlocks.has(&"air_dash") and GameState.unlocks.has(&"grapple"),
		"every bought implant lands in GameState.unlocks AFTER reset_for_new_game (which clears unlocks)")
	assert_eq(GameState.money, snappedf(base - 850.0, Zorkmids.QUANTUM),
		"the bill is debited from GameState.money — the ONE home of the (negative-capable) balance every loaded=false boot of a created run reads")
	assert_true(GameState.profile_active, "a created character IS an authoritative run (P0-2) — and the flag routes the Player's wallet branch to GameState.money")
	GameState.reset_for_new_game()  # leave the shared autoload clean for the rest of the suite


func test_stamp_with_an_empty_cart_keeps_the_debt_free_zero_ability_start() -> void:
	var menu := _make_menu()
	menu._pending_creation = ["Chooms", {}, {}]
	menu._stamp_new_game_profile([], 0.0)
	assert_true(GameState.unlocks.is_empty(),
		"an empty cart keeps the zero-ability fresh start (P0-1) — nothing is seeded")
	assert_eq(GameState.money, GameSettings.economy.player_starting_money, "…and the wallet stays at the base seed")
	GameState.reset_for_new_game()  # leave the shared autoload clean for the rest of the suite
