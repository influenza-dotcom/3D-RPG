extends GutTest

## GUT tests for the "Movement helpers" subsystem: the small jump/movement state
## machines under res://scripts/player/ — CoyoteTime, JumpBuffer, Bunnyhop, and the
## state-query surface of BulletTime. These are the highest-value pure-logic targets:
## tiny timers and an enum gate that player.gd reads every physics frame to decide
## whether a jump fires, whether a bhop chain accumulates, and whether slow-mo is live.
##
## STRATEGY: drive the state APIs directly (set _timer / _state / chain, then call
## tick/consume/_physics_process/try_engage and assert immediately). The timers are
## driven by hand rather than by waiting frames, because any add_child'd node is ALSO
## ticked once per frame by the engine — asserting right after the manual call keeps an
## extra engine tick from racing the assert (see jump_buffer / bunnyhop window tests).
##
## COVERS (net-new vs test_smoke.gd):
##   - CoyoteTime.consume() zeroes the window and drops can_jump() (no double jump).
##   - CoyoteTime.can_jump() maps exactly to _timer > 0.
##   - CoyoteTime.tick() airborne branch counts the window down and clamps at 0.
##   - JumpBuffer.consume() clears the buffer and drops wants_jump() (no double fire).
##   - JumpBuffer.wants_jump() maps exactly to _timer > 0.
##   - JumpBuffer._physics_process() bleeds the buffer down, clamped at 0.
##   - Bunnyhop._physics_process() airborne window-bleed, and its null-character guard.
##   - Bunnyhop.try_engage() return value + chain growth on an existing chain in-window.
##   - Bunnyhop.get_target_speed() mid-range linear growth (+boost_per_hop/hop) below cap.
##   - BulletTime.is_active() maps to State.ACTIVE only (READY/EXHAUSTED both false).
##   - BulletTime._on_scoped_in(false) disarms _is_scoped and _scope_entered_in_air.
##
## DELIBERATELY SKIPPED (would be fragile or duplicate):
##   - CoyoteTime grounded re-arm and Bunnyhop landing-edge / chain-break branches: a
##     bare CharacterBody3D in a test tree always reports is_on_floor()==false, so the
##     grounded branches need real physics and are unreachable here.
##   - BulletTime._process / Engine.time_scale lerp + ownership: fully covered by smoke
##     (test_bullet_time_*); re-driving _process risks leaving Engine.time_scale dirty,
##     so these tests touch only _state and flags and never call _process.
##   - The tuning constants themselves (coyote_time, jump_buffer_time, land_window,
##     boost_per_hop, max_speed): type-guarded by smoke's test_game_tuning_constants_present.
##     These tests read them for expected values but never mutate the shared singletons.
##   - Crouch entirely: a bare instance's _ready() dereferences unset @export vars
##     (head.position, collision_shape.shape) and its queries need a live physics world.
##
## GameSettings.player_movement / .bunnyhop are mutable shared singletons (preloaded
## .tres). They are only READ here for expected values; mutating them would leak into
## other tests, so nothing in this file writes to them.

const COYOTE_TIME := preload("res://scripts/player/coyote_time.gd")
const JUMP_BUFFER := preload("res://scripts/player/jump_buffer.gd")
const BUNNYHOP := preload("res://scripts/player/bunnyhop.gd")
const BULLET_TIME := preload("res://scripts/player/bullet_time.gd")


# ---------------------------------------------------------------------------
# CoyoteTime — the trailing-edge jump-forgiveness gate player.gd reads.
# ---------------------------------------------------------------------------

func test_coyote_consume_zeroes_window() -> void:
	# Pure: consume() only writes _timer = 0.0, so no node tree is needed.
	var ct := COYOTE_TIME.new()
	ct._timer = 1.0
	ct.consume()
	assert_eq(ct._timer, 0.0,
		"consume() must zero the coyote window so spending a jump can't leave time for a second")
	assert_false(ct.can_jump(),
		"After consume() can_jump() must be false — one ledge-leave grants at most one jump")
	ct.free()


func test_coyote_can_jump_reflects_timer_sign() -> void:
	# can_jump() is the exact gate player.gd ANDs with jump_buffer.wants_jump();
	# it must be true for any positive remaining window and false at exactly zero.
	var ct := COYOTE_TIME.new()
	ct._timer = 0.001
	assert_true(ct.can_jump(),
		"can_jump() must be true while any coyote window remains (_timer > 0)")
	ct._timer = 0.0
	assert_false(ct.can_jump(),
		"can_jump() must be false once the window hits exactly 0 (the boundary, not >=)")
	ct.free()


func test_coyote_tick_airborne_counts_down_and_clamps() -> void:
	# tick() dereferences character.is_on_floor() with NO null guard, so a character
	# MUST be assigned first. A bare CharacterBody3D reports is_on_floor()==false, which
	# is exactly the airborne branch we want: _timer = max(_timer - delta, 0.0).
	var ct := COYOTE_TIME.new()
	add_child_autofree(ct)
	var body := CharacterBody3D.new()
	add_child_autofree(body)
	ct.character = body

	var full: float = GameSettings.player_movement.coyote_time
	ct._timer = full
	ct.tick(0.05)
	assert_lt(ct._timer, full,
		"Airborne tick() must count the coyote window DOWN, not re-arm it")
	assert_gt(ct._timer, 0.0,
		"A small airborne tick must leave window remaining — the jump is still allowed mid-window")

	# A delta larger than the whole window must clamp at 0, never go negative
	# (a negative _timer would silently flip can_jump() logic if compared as >0).
	ct.tick(full + 1.0)
	assert_eq(ct._timer, 0.0,
		"tick() must clamp the window at 0 on a large delta — it can never go negative")
	assert_false(ct.can_jump(),
		"Once the airborne window is fully spent, can_jump() must be false")


# ---------------------------------------------------------------------------
# JumpBuffer — the leading-edge jump-forgiveness flag player.gd polls.
# ---------------------------------------------------------------------------

func test_jump_buffer_consume_clears_buffer() -> void:
	# Pure: consume() only writes _timer = 0.0.
	var jb := JUMP_BUFFER.new()
	jb._timer = 1.0
	jb.consume()
	assert_eq(jb._timer, 0.0,
		"consume() must clear the buffer so a fired buffered jump can't trigger a second time")
	assert_false(jb.wants_jump(),
		"After consume() wants_jump() must be false — the queued press is spent")
	jb.free()


func test_jump_buffer_wants_jump_reflects_timer_sign() -> void:
	var jb := JUMP_BUFFER.new()
	jb._timer = 0.001
	assert_true(jb.wants_jump(),
		"wants_jump() must be true while a recent press is still buffered (_timer > 0)")
	jb._timer = 0.0
	assert_false(jb.wants_jump(),
		"wants_jump() must be false at exactly 0 — the leading-edge forgiveness has lapsed")
	jb.free()


func test_jump_buffer_physics_process_bleeds_and_clamps() -> void:
	# _physics_process touches only _timer (no node/autoload-child deps), so it is safe
	# to drive directly. Assert immediately after the manual call so the engine's own
	# once-per-frame tick on this add_child'd node can't perturb _timer first.
	var jb := JUMP_BUFFER.new()
	add_child_autofree(jb)

	var full: float = GameSettings.player_movement.jump_buffer_time
	jb._timer = full
	jb._physics_process(0.05)
	assert_lt(jb._timer, full,
		"_physics_process must bleed the jump buffer down each frame so it eventually expires")
	assert_gt(jb._timer, 0.0,
		"A small tick must leave buffer remaining — a press just before landing still counts")

	jb._timer = full
	jb._physics_process(full + 1.0)
	assert_eq(jb._timer, 0.0,
		"_physics_process must clamp the buffer at 0 on a large delta — it never underflows")


# ---------------------------------------------------------------------------
# Bunnyhop — the chain/speed skill-expression state machine.
# ---------------------------------------------------------------------------

func test_bunnyhop_physics_airborne_bleeds_land_window() -> void:
	# _physics_process is guarded (if not character: return), so it needs a character to
	# run. A bare CharacterBody3D reports is_on_floor()==false, so on_floor is false and
	# only the else branch (window bleed) runs; the break_chain branch is gated on
	# on_floor so it cannot fire here. _was_on_floor must stay false (set to on_floor).
	var bh := BUNNYHOP.new()
	add_child_autofree(bh)
	var body := CharacterBody3D.new()
	add_child_autofree(body)
	bh.character = body

	var full: float = GameSettings.bunnyhop.land_window
	bh._land_window_timer = full
	bh._was_on_floor = false
	bh._physics_process(0.1)
	assert_lt(bh._land_window_timer, full,
		"Airborne, the post-landing hop window must bleed toward 0 — it only stays open right after a landing")
	assert_false(bh._was_on_floor,
		"A bare body is always airborne, so _physics_process must record _was_on_floor as false")


func test_bunnyhop_physics_noop_without_character() -> void:
	# The `if not character: return` guard must protect the un-wired state: with no
	# character, neither the chain nor the land window may change.
	var bh := BUNNYHOP.new()
	bh.chain = 3
	bh._land_window_timer = 1.0
	bh._physics_process(0.1)
	assert_eq(bh.chain, 3,
		"_physics_process must be a no-op on chain when character is null (early-return guard)")
	assert_eq(bh._land_window_timer, 1.0,
		"_physics_process must not touch the land window when character is null")
	bh.free()


func test_bunnyhop_try_engage_extends_existing_chain_and_returns_true() -> void:
	# Pure: try_engage reads only _land_window_timer / chain. With a positive window and
	# an existing chain, it must BOTH return true (player then applies the boosted speed)
	# and increment the chain (accumulate the hop). Smoke covers chain 2->3 but never
	# asserts the bool, and never an increment past 3.
	var bh := BUNNYHOP.new()
	bh._land_window_timer = GameSettings.bunnyhop.land_window
	bh.chain = 3
	assert_true(bh.try_engage(true),
		"A timed hop with movement input must return true so the player applies chain speed")
	assert_eq(bh.chain, 4,
		"Engaging inside the window must extend the existing chain (3 -> 4), not restart it")
	bh.free()


func test_bunnyhop_target_speed_grows_linearly_below_cap() -> void:
	# Pure: get_target_speed reads chain + the (read-only) tuning. Mid-range growth is
	# uncovered by smoke (which only checks the chain==0 floor and the chain==9999 cap).
	# With max_speed 5.0 + boost_per_hop 1.2 and a 12.0 cap, chains 1 and 2 are both
	# below the cap, so each hop adds exactly boost_per_hop.
	var bh := BUNNYHOP.new()
	bh.chain = 1
	var s1: float = bh.get_target_speed()
	bh.chain = 2
	var s2: float = bh.get_target_speed()
	assert_gt(s2, s1,
		"Each additional hop must raise the target speed (monotonic growth) below the cap")
	assert_gt(s1, GameSettings.player_movement.max_speed,
		"Even a single-hop chain must exceed plain max_speed — that boost is the bhop reward")
	assert_almost_eq(s1,
		GameSettings.player_movement.max_speed + GameSettings.bunnyhop.boost_per_hop, 0.001,
		"A chain of 1 must add exactly one boost_per_hop above max_speed (linear, pre-clamp)")
	bh.free()


# ---------------------------------------------------------------------------
# BulletTime — only its pure state-query / flag surface (NOT _process: smoke
# already drives the Engine.time_scale flow and these tests must leave it alone).
# ---------------------------------------------------------------------------

func test_bullet_time_is_active_maps_to_active_state_only() -> void:
	# is_active() must equal _state == State.ACTIVE and nothing else. Smoke asserts it's
	# false at start and after exhaust, but never the explicit EXHAUSTED!=ACTIVE and
	# ACTIVE==true mapping in isolation. Set _state directly; never call _process so
	# Engine.time_scale is never touched.
	var bt := BULLET_TIME.new()
	bt._state = BULLET_TIME.State.READY
	assert_false(bt.is_active(),
		"is_active() must be false in READY — armed but not yet running slow-mo")
	bt._state = BULLET_TIME.State.EXHAUSTED
	assert_false(bt.is_active(),
		"is_active() must be false in EXHAUSTED — a spent effect is not active")
	bt._state = BULLET_TIME.State.ACTIVE
	assert_true(bt.is_active(),
		"is_active() must be true ONLY in ACTIVE — the one state that sustains slow-mo")
	bt.free()


func test_bullet_time_unscope_clears_arm_flags() -> void:
	# _on_scoped_in(false) is the un-scope branch: it has no character dependency (the
	# elif airborne-arm branch is skipped when _tf is false). It must clear _is_scoped
	# and reset _scope_entered_in_air so a later re-scope is forced to re-arm.
	var bt := BULLET_TIME.new()
	bt._is_scoped = true
	bt._scope_entered_in_air = true
	bt._on_scoped_in(false)
	assert_false(bt._is_scoped,
		"_on_scoped_in(false) must clear _is_scoped so the slow-mo condition no longer holds")
	assert_false(bt._scope_entered_in_air,
		"Un-scoping must reset the airborne-arm flag so a fresh re-scope must re-arm to re-activate")
	bt.free()