extends GutTest

## Attack.draw_locked — the carry "hands full" gate that stops you taking the gun out while your first-person arms
## are out holding a physics prop. Enforced at the single set_holstered() chokepoint (so it covers the fire-click
## draw, the hold-R holster toggle, AND a weapon swap, which all funnel through set_holstered(false)).
##
## Built off-tree via .new() with NO add_child — set_holstered / toggle_holster don't touch any _ready-built child
## (the colour-picker check null-guards its _spray), so this is pure state logic. Do NOT run Attack._ready in a unit
## test (it instantiates SprayPainter/WeaponAudio and connects inventory signals).

const ATTACK_PATH := "res://scripts/combat/attack.gd"


func test_draw_lock_defaults_off() -> void:
	var a = load(ATTACK_PATH).new()
	assert_false(a.draw_locked, "draw_locked ships OFF — a normal / AI wielder is never lock-gated")
	a.free()


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


func test_lock_does_not_force_holster_by_itself() -> void:
	# Setting the lock while the gun is OUT doesn't yank it away — Player always holsters FIRST, then locks. The lock
	# only refuses future draws; it never changes the current state on its own.
	var a = load(ATTACK_PATH).new()
	assert_false(a.holstered, "starts drawn")
	a.draw_locked = true
	assert_false(a.holstered, "engaging the lock alone leaves the current holster state untouched")
	a.free()


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
