extends GutTest

## EL-2 RentCollector — a recurring money sink. OFF at the default rent_amount 0; charges the player every
## `period_days` WorldClock dawns; never pushes the wallet into debt (pays min(rent, wallet), payment_missed on
## a shortfall). The day-counter is pure (unit-tested directly); collect() is driven against an off-tree Player
## wallet (the in-tree phase_changed wiring is verified by playtest, per the repo convention).
##
## ⭐The NOTICE half is the reason this component is not just a timer. An armed collector that has never told
## the player what it charges produces exactly one player-visible artefact — a red "you failed to pay" toast —
## and on the shipping clock it produces that artefact 7m30s into a fresh run against a wallet that
## `player_starting_money = 0` guarantees is empty. The grace/notice schedule below is what makes the first
## word about rent a statement of terms instead of an accusation; `_consume_dawn` is the whole schedule in one
## unit-testable call (notice -> grace -> period), driven here off-tree with no WorldClock and no Player.

const PLAYER_PATH := "res://scripts/player/player.gd"


func test_disarmed_by_default_collects_nothing() -> void:
	var rc := RentCollector.new()
	var p = load(PLAYER_PATH).new()
	p.money = 100.0
	rc.collect(p)
	assert_almost_eq(p.money, 100.0, 0.0001, "rent_amount 0 (default) is OFF — no charge")
	rc.free()
	p.free()


func test_collect_charges_the_rent() -> void:
	var rc := RentCollector.new()
	rc.rent_amount = 30.0
	watch_signals(rc)
	var p = load(PLAYER_PATH).new()
	p.money = 100.0
	rc.collect(p)
	assert_almost_eq(p.money, 70.0, 0.0001, "the full rent is taken from the wallet")
	assert_signal_emitted(rc, "rent_paid", "a covered rent emits rent_paid")
	rc.free()
	p.free()


func test_collect_never_goes_into_debt() -> void:
	var rc := RentCollector.new()
	rc.rent_amount = 50.0
	watch_signals(rc)
	var p = load(PLAYER_PATH).new()
	p.money = 20.0
	rc.collect(p)
	assert_almost_eq(p.money, 0.0, 0.0001, "a broke player is taken to zero, never negative")
	assert_signal_emitted(rc, "payment_missed", "an uncovered rent emits payment_missed")
	rc.free()
	p.free()


func test_period_days_counter() -> void:
	var rc := RentCollector.new()
	rc.period_days = 3
	assert_false(rc._advance_day(), "dawn 1 of 3: not due")
	assert_false(rc._advance_day(), "dawn 2 of 3: not due")
	assert_true(rc._advance_day(), "dawn 3 of 3: rent is due")
	assert_false(rc._advance_day(), "the counter resets — dawn 1 of the next cycle")
	rc.free()


func test_period_floored_at_one() -> void:
	var rc := RentCollector.new()
	rc.period_days = 0  # nonsense -> at least daily
	assert_true(rc._advance_day(), "period_days 0 floors to 1 — due every dawn")
	assert_true(rc._advance_day(), "...and again the next dawn")
	rc.free()


func test_paid_message_with_literal_percent_is_safe() -> void:
	# A free-form flavor toast with a literal % must pass through unchanged — substitution is token-REPLACE
	# ({amount} / legacy %s), so the `%` format operator (which would raise "unsupported format character")
	# is never invoked at all.
	var rc := RentCollector.new()
	rc.paid_message = "Rent paid (10% of value)"
	assert_eq(rc._fmt_paid(30.0), "Rent paid (10% of value)", "a literal percent without a token is returned as-is, no format error")
	rc.free()


func test_paid_message_amount_token_substitutes() -> void:
	var rc := RentCollector.new()
	rc.paid_message = "Rent paid: {amount}"
	assert_eq(rc._fmt_paid(30.0), "Rent paid: " + Zorkmids.money_text(30.0), "the {amount} token is replaced with the formatted amount")
	rc.free()


func test_paid_message_with_placeholder_substitutes() -> void:
	var rc := RentCollector.new()
	rc.paid_message = "Rent paid: %s"
	assert_eq(rc._fmt_paid(30.0), "Rent paid: " + Zorkmids.money_text(30.0), "a legacy %s placeholder (pre-{amount} authored scenes) still substitutes")
	rc.free()


func test_paid_message_literal_percent_beside_legacy_placeholder_is_safe() -> void:
	# The retired `%` operator path hard-errored on exactly this shape (the "% o" after "10%" is an invalid
	# format specifier). replace()-based substitution must take it in stride.
	var rc := RentCollector.new()
	rc.paid_message = "10% off — paid %s"
	assert_eq(rc._fmt_paid(30.0), "10% off — paid " + Zorkmids.money_text(30.0), "a literal % beside a legacy %s no longer errors and the amount still lands")
	rc.free()


func test_money_reaches_prose_as_a_whole_phrase_not_a_bare_number() -> void:
	# ⭐The regression this pins: substituting Zorkmids.fmt() renders "Rent collected — 20." — a charge with no
	# currency on it. Money reaches player prose as the whole money_text phrase, so a designer never has to
	# remember to append a unit (and can never author "{amount} zm" into a double unit).
	var rc := RentCollector.new()
	rc.paid_message = "{amount}"
	var rendered := rc._fmt_paid(20.0)
	assert_eq(rendered, Zorkmids.money_text(20.0), "{amount} renders the whole money phrase")
	assert_ne(rendered, Zorkmids.fmt(20.0), "…which is NOT the bare number — a unit-less rent toast is the bug this pins")
	rc.free()


# --- THE NOTICE: the terms are stated before any money moves ------------------------------------------------

func test_missed_message_substitutes_its_tokens() -> void:
	# ⭐This is the defect that produced "Rent unpaid. The shortfall has been noted." — missed_message used to be
	# passed to notify_toast RAW while only paid_message was formatted, so the miss line was structurally
	# incapable of naming a number and degenerated into vague prose. All three tokens must land.
	var rc := RentCollector.new()
	rc.rent_amount = 20.0
	rc.missed_message = "short {shortfall} of {amount}, took {paid}"
	assert_eq(rc._fmt_missed(5.0),
		"short " + Zorkmids.money_text(15.0) + " of " + Zorkmids.money_text(20.0) + ", took " + Zorkmids.money_text(5.0),
		"{shortfall} is the unpaid remainder, {amount} the rent OWED (not the part collected), {paid} what was taken")
	rc.free()


func test_missed_message_shortfall_is_the_whole_rent_when_the_wallet_was_empty() -> void:
	var rc := RentCollector.new()
	rc.rent_amount = 20.0
	rc.missed_message = "{shortfall}"
	assert_eq(rc._fmt_missed(0.0), Zorkmids.money_text(20.0), "a broke player misses the FULL rent — shortfall == rent_amount")
	rc.free()


func test_notice_message_substitutes_amount_and_period() -> void:
	var rc := RentCollector.new()
	rc.rent_amount = 20.0
	rc.period_days = 3
	rc.notice_message = "{amount} every {days}"
	assert_eq(rc._fmt_notice(), Zorkmids.money_text(20.0) + " every 3", "the notice states the charge and its cadence")
	rc.free()


func test_notice_period_token_is_floored_like_the_counter() -> void:
	# A 0 here reads as daily to _advance_day (maxi(1, ...)); the notice must not promise "every 0 days".
	var rc := RentCollector.new()
	rc.rent_amount = 20.0
	rc.period_days = 0
	rc.notice_message = "every {days}"
	assert_eq(rc._fmt_notice(), "every 1", "{days} floors exactly the way _advance_day floors it")
	rc.free()


func test_first_dawn_serves_notice_and_the_grace_day_is_free() -> void:
	var rc := RentCollector.new()
	rc.rent_amount = 20.0
	rc.grace_days = 1
	watch_signals(rc)
	assert_false(rc._consume_dawn(), "dawn 1 serves NOTICE and charges nothing — the player is told the terms first")
	assert_signal_emitted(rc, "notice_served", "the terms were announced on the first dawn")
	assert_true(rc._consume_dawn(), "dawn 2 is the first charge — a full in-game day after the warning")
	rc.free()


func test_notice_is_served_once_only() -> void:
	var rc := RentCollector.new()
	rc.rent_amount = 20.0
	rc.grace_days = 1
	watch_signals(rc)
	for i in 5:
		rc._consume_dawn()
	assert_signal_emit_count(rc, "notice_served", 1, "the notice is a ONE-SHOT statement of terms, not a recurring nag")
	rc.free()


func test_grace_window_delays_the_meter_by_exactly_grace_days() -> void:
	var rc := RentCollector.new()
	rc.rent_amount = 20.0
	rc.grace_days = 3
	assert_false(rc._consume_dawn(), "grace dawn 1 of 3")
	assert_false(rc._consume_dawn(), "grace dawn 2 of 3")
	assert_false(rc._consume_dawn(), "grace dawn 3 of 3 — the meter has still not started")
	assert_true(rc._consume_dawn(), "the dawn AFTER the grace window is the first charge")
	rc.free()


func test_grace_days_zero_preserves_the_pre_notice_behaviour() -> void:
	# Backwards compatibility: the default must leave an already-authored collector charging exactly as before,
	# so adding the notice half cannot silently give any existing level a free day.
	var rc := RentCollector.new()
	rc.rent_amount = 20.0
	assert_eq(rc.grace_days, 0, "grace_days defaults to 0")
	assert_true(rc._consume_dawn(), "with no grace the FIRST dawn still charges, as it always did")
	rc.free()


func test_grace_is_spent_before_the_period_counter_runs() -> void:
	# The two counters compose rather than overlap: grace_days dawns pass, THEN period_days starts counting.
	var rc := RentCollector.new()
	rc.rent_amount = 20.0
	rc.grace_days = 1
	rc.period_days = 2
	assert_false(rc._consume_dawn(), "dawn 1: grace")
	assert_false(rc._consume_dawn(), "dawn 2: period counter 1 of 2")
	assert_true(rc._consume_dawn(), "dawn 3: period counter 2 of 2 — due")
	assert_false(rc._consume_dawn(), "dawn 4: the period counter restarts, grace is NOT re-granted")
	assert_true(rc._consume_dawn(), "dawn 5: due again on the plain period")
	rc.free()


func test_a_disarmed_collector_never_announces_itself() -> void:
	# rent_amount 0 is the documented off-switch, and _on_phase_changed gates on it BEFORE _consume_dawn — an
	# inert drop-in must stay completely silent, not toast terms for a rent it will never charge.
	var rc := RentCollector.new()
	rc.notice_message = "you owe {amount}"
	watch_signals(rc)
	rc._on_phase_changed(WorldClock.Phase.DAY)
	assert_signal_not_emitted(rc, "notice_served", "a disarmed collector serves no notice")
	rc.free()


func test_notice_survives_having_no_player() -> void:
	# _serve_notice runs off-tree in every unit test here and in the real game runs before the toast can matter;
	# it must degrade to "signal only", never fault on the missing Player.
	var rc := RentCollector.new()
	rc.rent_amount = 20.0
	rc.notice_message = "you owe {amount}"
	watch_signals(rc)
	rc._serve_notice()
	assert_signal_emitted(rc, "notice_served", "the signal fires even with no Player to toast at, so a bark/quest flag can carry the beat")
	rc.free()
