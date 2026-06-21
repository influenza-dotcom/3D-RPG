extends GutTest

## EL-2 RentCollector — a recurring money sink. OFF at the default rent_amount 0; charges the player every
## `period_days` WorldClock dawns; never pushes the wallet into debt (pays min(rent, wallet), payment_missed on
## a shortfall). The day-counter is pure (unit-tested directly); collect() is driven against an off-tree Player
## wallet (the in-tree phase_changed wiring is verified by playtest, per the repo convention).

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
