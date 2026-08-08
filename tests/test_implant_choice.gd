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
	var spendable: float = s._spendable()  # the bank's limit + the base cash — what the whole cart may bill
	assert_eq(tally.text, PlayerText.implant_choice_tally(0.0, base, spendable),
		"the tally boots at a zero bill, the untouched base balance, and the full credit")
	var a := s._rows[0] as Button
	a.button_pressed = true
	var cost: float = float(a.get_meta("price"))
	assert_eq(tally.text, PlayerText.implant_choice_tally(cost, snappedf(base - cost, Zorkmids.QUANTUM),
			snappedf(spendable - cost, Zorkmids.QUANTUM)),
		"checking a chip re-tallies: the SAME formula feeds the display and the confirmed payload")


# --- The Ledger's credit check (present_build -> rating -> limit -> row gating) ----------------------------

const StatBudgetScript := preload("res://scripts/ui/stat_budget.gd")  ## for the allocator bounds the scorer normalizes against

## Every stat dumped to the creation floor — the worst build the allocator can express (STAT_MIN = -5).
func _trash_build() -> Dictionary:
	var out := {}
	for stat in CharacterStats.STAT_NAMES:
		out[stat] = StatBudgetScript.STAT_MIN
	return out


func _rating(build: Dictionary) -> Dictionary:
	return EconomySettings.credit_rating_for(build, GameSettings.economy,
			StatBudgetScript.STAT_MIN, StatBudgetScript.STAT_MAX)


func test_absent_build_fails_open_to_the_full_cap() -> void:
	# A bare-scene instantiation presents NO build — no application on file, which fails OPEN to the ceiling.
	# (That is deliberately NOT the same as an all-zero sheet, which is a real applicant with nothing to
	# lend against; see test_managers_tuning.) The screen must derive BOTH numbers through the pure
	# EconomySettings curves fed from the live knobs — no private formula, because the verdict it prints IS
	# the number the row-gating enforces.
	var s := _make_screen()
	var eco: EconomySettings = GameSettings.economy
	var want: Dictionary = _rating({})
	assert_eq(s._credit_score, int(want["score"]),
		"the screen rates through EconomySettings.credit_rating_for — the ONE bank formula")
	assert_eq(s._credit_band, want["band"], "…and carries the band KEY it returned, never a display string")
	assert_eq(s._credit_reason, want["reason"], "…and the filed-reason KEY likewise")
	assert_eq(s._credit_limit, EconomySettings.credit_limit_for(int(want["score"]), eco.credit_score_min,
			eco.credit_score_max, eco.credit_limit_max, eco.credit_limit_step, eco.credit_limit_curve),
		"…deriving the limit through credit_limit_for (gamma included), so verdict and row-gating can't disagree")
	assert_eq(s._credit_limit, eco.credit_limit_max,
		"an absent application earns exactly the authored cap (2100 zm shipped) — this is what keeps Begin ungated")
	assert_eq((s.get_node("%Verdict") as Label).text,
		PlayerText.implant_choice_verdict(s._credit_band, s._credit_score, s._credit_limit),
		"the verdict line paints through the ONE composer, selected by the band key")
	assert_eq((s.get_node("%Reason") as Label).text, PlayerText.implant_choice_reason(s._credit_reason),
		"…and the filed reason likewise")
	assert_eq((s.get_node("%Hint") as Label).text, PlayerText.IMPLANT_CHOICE_HINT,
		"the hint stays the STANDING explainer — build-specific numbers live on the verdict line, not here")


func test_a_fully_dumped_build_rates_low_and_greys_rows_that_no_longer_fit() -> void:
	var s := _make_screen()
	s.present_build(_trash_build())  # a live present_build re-rates + re-gates on the spot
	var eco: EconomySettings = GameSettings.economy
	assert_eq(s._credit_score, int(_rating(_trash_build())["score"]),
		"a live present_build re-rates through the same pure curve")
	assert_lt(s._credit_limit, eco.credit_limit_max,
		"an all-dumped build can never rate the full cap — every point pledged is collateral the bank discounts")
	var left: float = s._spendable()  # nothing checked yet, so the whole limit (+ base cash) remains
	for row in s._rows:
		assert_eq((row as Button).disabled, float(row.get_meta("price")) > left,
			"an unchecked row greys exactly when its price no longer fits the remaining credit")


func test_a_checked_row_never_greys_so_it_can_always_come_off_the_bill() -> void:
	var s := _make_screen()
	var a := s._rows[0] as Button
	a.button_pressed = true  # checked while the default clean-build limit still covers it
	s.present_build(_trash_build())  # the limit collapses UNDER the already-checked chip
	assert_gt(float(a.get_meta("price")), s._spendable(),
		"precondition: the collapsed limit no longer covers the checked chip (shipped knobs)")
	assert_false(a.disabled,
		"a CHECKED row stays live even when the limit collapses under it — un-checking must always be possible")
	a.button_pressed = false
	assert_true(a.disabled,
		"…and the moment it comes off the bill it greys like any other unpayable row")


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


func test_creation_begin_hands_the_real_build_to_the_credit_check() -> void:
	# Pins the ONE line that connects the flow (start_menu._on_character_confirmed's present_build call) —
	# with a build that scores BELOW clean. An absent build deliberately scores clean, so a dropped hand-off
	# would leave every other test green while silently rating every real build at the full cap; this build
	# is distinguishable, so losing the hand-off fails HERE.
	var menu := _make_menu()
	var build := {&"strength": -3}  # dumped + underspent: 3 unspent net points AND 3 dumped points
	menu._on_character_confirmed("Chooms", build, {})
	assert_not_null(menu._implant_choice, "Begin on creation raises the implant step")
	var eco: EconomySettings = GameSettings.economy
	assert_eq(menu._implant_choice._credit_score, int(_rating(build)["score"]),
		"the raised screen rated the REAL pending build, not the fail-open absent-application default")
	assert_lt(menu._implant_choice._credit_score, eco.credit_score_max,
		"precondition: the dumped build rates below the ceiling — this pin can actually detect a dropped hand-off")
	menu._on_implant_cancelled()  # drop the step; leave the shared menu state clean


func test_stamp_bills_the_cart_into_debt_after_the_reset() -> void:
	var menu := _make_menu()
	menu._pending_creation = ["Chooms", {&"strength": 2}, {}]
	menu._stamp_new_game_profile([&"air_dash", &"grapple"], 850.0)
	var base: float = GameSettings.economy.player_starting_money
	assert_eq(GameState.player_name, "Chooms", "the stashed name is stamped after the reset")
	assert_true(GameState.unlocks.has(&"air_dash") and GameState.unlocks.has(&"grapple"),
		"every bought implant lands in GameState.unlocks AFTER reset_for_new_game (which clears unlocks)")
	# ⭐The bill rides the LEDGER ACCOUNT, not the wallet. `GameState.account` is ONE SIGNED number (positive
	# savings / negative debt), so the starting debt is repayable at an ATM — depositing against it IS the
	# repayment — while `money` stays CASH-ONLY. That split is also what stops dying (which empties only the
	# wallet) from clearing what you owe, and stops income silently auto-paying the balance.
	assert_eq(GameState.money, base,
		"the wallet is untouched by the bill — cash stays cash, and stays >= 0 for a created run")
	assert_eq(GameState.account, snappedf(-850.0, Zorkmids.QUANTUM),
		"the implant bill lands on GameState.account as DEBT — the one signed balance an ATM can settle")
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
