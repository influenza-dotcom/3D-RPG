extends GutTest

## BEHAVIOUR for the implant-purchase step (implant_choice.gd) + its StartMenu flow seams. Implants are
## bought ON CREDIT at New Game: any set of chips may be checked (multi-select, no opt-out row — an empty
## cart is the default), the bill is each chip's price for the build being made (Item.value, or its
## stat-conditional discount_value — see Item.value_at), and the profile stamp debits it
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
			# value_at(0), not `value`: a bare screen has presented NO build, so every stat reads the 0
			# baseline and a stat-conditional chip quotes its LIST price. Asking the same accessor the
			# screen asks keeps the two matched even for a chip that discounts at or below baseline.
			out[item.installs_ability] = snappedf(item.value_at(0), Zorkmids.QUANTUM)
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


## The credit the cart still has to spend — _refresh_tally's OWN line, so these tests gate on the exact number
## the screen gates on instead of a re-derivation that could drift off it.
func _credit_left(s: Control) -> float:
	var spendable: float = s._spendable()
	var cost: float = s._total_cost()
	return snappedf(maxf(0.0, spendable - cost), Zorkmids.QUANTUM)


func _count_greyed(s: Control) -> int:
	var rows: Array = s._rows
	var n := 0
	for r in rows:
		if (r as Button).disabled:
			n += 1
	return n


## THE gate contract, asserted across the whole roster at once: a CHECKED row is never disabled (un-checking
## must always be possible), and an UNCHECKED row is disabled exactly when its price no longer fits the credit
## left. Re-asserted at every stage below, because the claim worth pinning is that it survives the cart filling
## up AND emptying again — not that it happens to hold on an untouched screen.
func _assert_gate_holds(s: Control, when: String) -> void:
	var left := _credit_left(s)
	var rows: Array = s._rows
	for r in rows:
		var row := r as Button
		if row.button_pressed:
			assert_false(row.disabled,
				"%s: a CHECKED row stays live even when the credit left no longer covers it" % when)
		else:
			assert_eq(row.disabled, float(row.get_meta("price")) > left,
				"%s: an unchecked row greys exactly when its price no longer fits the credit left" % when)


## Fill the cart the way a player actually can: always the DEAREST row that is still LIVE, until nothing else
## fits. Every check is legal at the moment it is made (the row was enabled, so it was clickable), so the end
## state is one the UI genuinely reaches — which is the whole point of the test below. Bounded by the roster
## size so a row that somehow refuses to latch fails the assertions instead of hanging the suite.
func _fill_the_cart(s: Control) -> Array[Button]:
	var rows: Array = s._rows
	var picked: Array[Button] = []
	for _i in range(rows.size() + 1):
		var best: Button = null
		for r in rows:
			var row := r as Button
			if row.button_pressed or row.disabled:
				continue
			if best == null or float(row.get_meta("price")) > float(best.get_meta("price")):
				best = row
		if best == null:
			break
		best.button_pressed = true  # emits toggled -> _on_row_toggled -> _refresh_tally, exactly as a click does
		picked.append(best)
	return picked


func test_a_checked_row_never_greys_so_it_can_always_come_off_the_bill() -> void:
	# ⭐The shortfall this pins is reached by FILLING THE CART, and that is the only way it can be reached.
	# A standing selection cannot survive a re-present (present_build rebuilds the rows to re-price them, so it
	# clears the cart — pinned by the test below), and a row whose price beat the WHOLE spendable would have
	# shipped disabled and could never have been checked in the first place. So "the credit no longer covers a
	# checked chip" can only ever mean the credit the cart has LEFT: check the dearest chip and the credit left
	# drops by its own price, and it is that self-inflicted shortfall the `continue` in _refresh_tally protects
	# the row from. Without it, the priciest chip in a full cart would grey itself and could never come back off.
	var s := _make_screen()
	var picked := _fill_the_cart(s)
	assert_gt(picked.size(), 0, "precondition: a fresh screen's credit line buys at least one chip")
	var left := _credit_left(s)
	# Both halves have to be non-vacuous. Something in the cart must NO LONGER fit, or the `continue` is
	# shielding a row that was never in danger; and something outside it must have greyed, or the gate is simply
	# not running and "checked rows stay live" is true only because nothing gets disabled at all.
	var stranded := 0
	for row: Button in picked:
		if float(row.get_meta("price")) > left:
			stranded += 1
	assert_gt(stranded, 0,
		"precondition: a full cart strands at least one CHECKED chip costing more than the credit left")
	var greyed := _count_greyed(s)
	assert_gt(greyed, 0,
		"precondition: a full cart greys at least one UNCHECKED row, so the gate is demonstrably live")
	_assert_gate_holds(s, "with the cart full")
	# The round trip. The dearest chip comes back OFF the bill — which the gate above has to have left possible
	# — and its price returns to the pool, re-opening rows the full cart had greyed.
	var dearest := picked[0]
	for row: Button in picked:
		if float(row.get_meta("price")) > float(dearest.get_meta("price")):
			dearest = row
	dearest.button_pressed = false
	assert_false(dearest.disabled,
		"un-checking the dearest chip always leaves it affordable again — its own price is back in the pool")
	_assert_gate_holds(s, "after the dearest chip comes off the bill")
	assert_lt(_count_greyed(s), greyed,
		"…and the refund re-opens rows that the full cart had greyed")


func test_re_presenting_a_build_clears_the_cart_rather_than_billing_stale_stickers() -> void:
	# ⭐The behaviour that makes the shortfall above unreachable any other way, pinned so it cannot drift back.
	# A chip's price can DEPEND on the build (Item.discount_stat — the laser sight halves for anyone who put a
	# point in gunplay), and each row caches its price in a meta that BOTH the tally and the confirmed payload
	# bill from. So a re-present has to rebuild the rows, not just re-tally them, or it would charge the old
	# sticker; rebuilding necessarily empties the cart, which is correct — a build change is exactly when a
	# re-priced cart should be re-decided. (Only tests reach this branch: the real flow presents BEFORE add_child.)
	var s := _make_screen()
	var first := s._rows[0] as Button
	first.button_pressed = true
	var billed: float = s._total_cost()
	assert_gt(billed, 0.0, "precondition: the cart has a chip in it before the build changes")
	s.present_build(_trash_build())
	var after: float = s._total_cost()
	assert_eq(after, 0.0,
		"a live re-present empties the cart — the rows it billed from no longer exist")
	var rows: Array = s._rows
	assert_false(rows.has(first),
		"…and the OLD row objects are gone with it: a reference held across present_build is a discarded row, " +
		"not a live one, and will never be re-gated again")


func test_roster_rows_are_pad_reachable_and_ready_seeds_the_landing_spot() -> void:
	# CONTROLLER PARITY. The rows shipped focus_mode = FOCUS_NONE, which left Back and Begin as the ONLY
	# focusables on New Game's second screen: a pad player could start a run but could never buy a starting
	# implant — on the one screen in the game that sells them. _make_screen add_child's the real scene, so
	# _ready has already run _bind_ui -> _refresh_tally -> _seed_focus by the time we look.
	var s := _make_screen()
	for r in s._rows:
		assert_eq((r as Button).focus_mode, Control.FOCUS_ALL,
			"every roster row is focusable — focus-less rows are unreachable, not merely un-seeded")
	# The seed prefers the first row the Ledger still covers: _refresh_tally disables every unchecked row whose
	# price no longer fits, and a disabled Button is a dead landing spot. A bare instantiation presents no build,
	# which fails OPEN to the full cap, so row 0 is affordable here.
	var want: Button = null
	for r in s._rows:
		if not (r as Button).disabled:
			want = r as Button
			break
	assert_not_null(want, "precondition: the fail-open absent-application limit leaves at least one affordable row")
	assert_eq(s.get_viewport().gui_get_focus_owner(), want,
		"_ready seeded focus on the first affordable row, so ui_up/ui_down have somewhere to start")


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


## The price meta the screen cached on the row offering `ability`, or -1.0 when there is no such row. The rows
## are what the cart BILLS from (_total_cost sums this same meta), so asserting on it is asserting on the charge.
func _row_price(screen: Control, ability: StringName) -> float:
	for r in screen._rows:
		if StringName((r as Button).get_meta("ability_id")) == ability:
			return float((r as Button).get_meta("price"))
	return -1.0


## The shipped stat-conditional chip, or null when it is not on disk.
func _laser_chip() -> Item:
	return load("res://resources/items/chip_laser_sight.tres") as Item


func test_a_chips_price_can_depend_on_the_build_you_just_allocated() -> void:
	# ⭐The shipped case: the laser sight lists at 200 zm but costs 100 zm to anyone who put a point into
	# gunplay (Item.discount_stat). The screen must quote what THIS build pays — and must re-price in BOTH
	# directions when the build is re-presented, which is why present_build rebuilds the rows instead of only
	# re-tallying them.
	var chip := _laser_chip()
	assert_not_null(chip, "the laser-sight chip must be on disk for this test to mean anything")
	if chip == null:
		return
	var s := _make_screen()
	var list_price := snappedf(chip.value, Zorkmids.QUANTUM)
	var cut_price := snappedf(chip.discount_value, Zorkmids.QUANTUM)
	assert_eq(_row_price(s, chip.installs_ability), list_price,
		"with no build presented every stat reads 0, so the row quotes the LIST price")
	s.present_build({&"gunplay": 1})
	assert_eq(_row_price(s, chip.installs_ability), cut_price,
		"one invested point of gunplay re-prices the row to the discounted value")
	s.present_build({&"gunplay": 0, &"larceny": 5})
	assert_eq(_row_price(s, chip.installs_ability), list_price,
		"a build that dropped its gunplay pays list again — re-pricing has to work DOWNWARD too")


func test_the_cart_bills_the_discounted_price_it_showed() -> void:
	# The pickpocket rule at the creation till: whatever the row displayed is what `confirmed` hands StartMenu to
	# debit. A discount that reached the LABEL but not the payload would be a free 100 zm.
	var chip := _laser_chip()
	if chip == null:
		return
	var s := _make_screen()
	s.present_build({&"gunplay": 2})
	var row: Button = null
	for r in s._rows:
		if StringName((r as Button).get_meta("ability_id")) == chip.installs_ability:
			row = r as Button
			break
	assert_not_null(row, "the laser sight must have a roster row")
	if row == null:
		return
	row.button_pressed = true  # emits toggled -> _refresh_tally, exactly as a click would
	assert_eq(s._total_cost(), snappedf(chip.discount_value, Zorkmids.QUANTUM),
		"the cart bills the DISCOUNTED price the row advertised, not the list one")
