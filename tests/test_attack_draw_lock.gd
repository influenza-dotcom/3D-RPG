extends GutTest

## Attack.draw_locked — the carry "hands full" gate that stops you taking the gun out while your first-person arms
## are out holding a physics prop. Enforced at the single set_holstered() chokepoint (so it covers the fire-click
## draw, the hold-R holster toggle, AND a weapon swap, which all funnel through set_holstered(false)).
##
## Built off-tree via .new() with NO add_child — set_holstered / toggle_holster don't touch any _ready-built child
## (the colour-picker check null-guards its _spray), so this is pure state logic. Do NOT run Attack._ready in a unit
## test (it instantiates SprayPainter/WeaponAudio and connects inventory signals).

const ATTACK_PATH := "res://scripts/combat/attack.gd"


func test_a_wielder_nobody_carry_locked_holsters_and_draws_freely() -> void:
	# The lock ships OFF: only the player's carry path engages it, so a fresh wielder (every NPC, and the player
	# with empty hands) must be able to put the gun away and bring it back out through every draw vector.
	var a = autofree(load(ATTACK_PATH).new())
	a.set_holstered(true)
	assert_true(a.holstered, "an unlocked wielder can put the gun away")
	a.set_holstered(false)
	assert_false(a.holstered, "a wielder nobody carry-locked draws again through set_holstered(false) (fire-click / swap)")
	a.toggle_holster()
	assert_true(a.holstered, "the hold-R toggle puts an unlocked gun away")
	a.toggle_holster()
	assert_false(a.holstered, "…and the hold-R toggle draws it back out")
	assert_false(a._fire_should_abort(false), "a drawn, unlocked player weapon never drops its queued shot")


func test_locked_refuses_to_draw_but_allows_holstering() -> void:
	var a = load(ATTACK_PATH).new()
	# Simulate a carry: put the weapon away, then lock it away (the order Player._on_carry_changed uses on grab).
	a.set_holstered(true)
	a.draw_locked = true
	assert_true(a.holstered, "putting the weapon away is always allowed, even locked")
	# Every draw vector routes through set_holstered(false) — all must be refused while locked.
	a.set_holstered(false)
	assert_true(a.holstered, "set_holstered(false) is refused while draw_locked — the gun can't come out")
	a.toggle_holster()
	assert_true(a.holstered, "the hold-R holster toggle can't draw the gun while draw_locked either")
	a.free()


func test_unlock_restores_the_draw() -> void:
	var a = load(ATTACK_PATH).new()
	a.set_holstered(true)
	a.draw_locked = true
	a.set_holstered(false)
	assert_true(a.holstered, "still holstered while locked")
	# Dropping the prop (Player clears draw_locked BEFORE restoring the holster state).
	a.draw_locked = false
	a.set_holstered(false)
	assert_false(a.holstered, "once the hands are free the weapon can be drawn again")
	a.free()


func test_a_refused_draw_changes_nothing_and_a_locked_put_away_still_lands() -> void:
	# The lock only REFUSES draws. A draw call that lands while locked with the gun already out (a weapon swap's
	# set_holstered(false) mid-carry) must not yank the gun away or announce a change the view model would act on;
	# and putting the gun away while locked must still go through, announced once.
	var a = autofree(load(ATTACK_PATH).new())
	watch_signals(a)
	a.draw_locked = true
	a.set_holstered(false)
	assert_false(a.holstered, "a refused draw leaves a drawn gun drawn — the lock never holsters on its own")
	assert_signal_not_emitted(a, "holster_changed", "a refused draw emits nothing, so gun_mesh does not hide or re-raise the view model")
	a.set_holstered(true)
	assert_true(a.holstered, "putting the weapon away is allowed even while locked")
	assert_signal_emit_count(a, "holster_changed", 1, "the locked put-away is announced exactly once")
	a.set_holstered(false)
	assert_signal_emit_count(a, "holster_changed", 1, "the refused re-draw adds no second announcement")


func test_fire_should_abort_gates() -> void:
	# T2 (F-T2-3): a shot queued behind a wind-up / hit-flash await re-checks _fire_should_abort after the await, so the
	# world changing mid-await (holster / carry-lock / dialogue / wielder-death) drops the delayed shot. character is
	# null off-tree (death branch skipped) and DialogueManager is inactive under GUT, so we exercise the player-only
	# holster / draw_locked gates and the from_ai bypass.
	var a = load(ATTACK_PATH).new()
	assert_false(a._fire_should_abort(false), "a settled player weapon does not abort by default")
	a.holstered = true
	assert_true(a._fire_should_abort(false), "a holster that landed mid-await aborts the queued player shot")
	assert_false(a._fire_should_abort(true), "an AI wielder ignores the player-only holster gate — the world runs live")
	a.holstered = false
	a.draw_locked = true
	assert_true(a._fire_should_abort(false), "a carry-lock that landed mid-await aborts the queued player shot")
	assert_false(a._fire_should_abort(true), "an AI wielder ignores the player-only carry-lock gate too")
	a.free()
