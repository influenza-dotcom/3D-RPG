extends GutTest

## AirMovement.step_horizontal — the whole airborne feel curve, as pure Vector2 math. Each headline case pins a
## specific pathology of the two-lerp model this replaced, or a specific thing that must NOT change.
## Driving the pure static needs no Player, no _ready and no world access, which sidesteps both GUT traps in
## this area: a bare CharacterBody3D always reports is_on_floor() == false, and an off-tree get_world_3d()
## raises a tracked engine error GUT 9.6 turns into a failure (see MovementHelpers' guarded probe).
## (The shell AirMovement.step's climb/rope stand-down and the bhop-stamp ordering are integration surface,
## held by source-text pins here and in test_player_core.gd plus a playtest — the same split M13 made.)
##
## ⭐THE HELPER MIRRORS THE SHELL ON PURPOSE. `wish_speed` and `wish_dir` collapse together in the real caller
## (both are scaled by the stick magnitude), so a helper that hands step_horizontal a NON-zero wish speed
## beside a ZERO direction tests a pairing the game can never produce — and that exact blind spot is what let
## a released key still brake air-built speed while the momentum test below passed anyway. `_step` derives the
## wish speed from whether a direction is held; `tier` is the separate settle floor the Player latches.

const AIR := preload("res://scripts/player/air_movement.gd")
const AIR_PATH := "res://scripts/player/air_movement.gd"

const DT := 1.0 / 60.0
const FPS := 1.0        ## fps_factor at exactly 60 Hz
const FRAMES := 48      ## one default jump: 4.5/9.8 rise + the 1.75x-gravity fall = 0.806 s
const TAP_FRAMES := 19  ## a jump_cut_factor 0.4 tap: 0.3225 s
const ACCEL := 12.0     ## PlayerMovementSettings.air_accel
const STEER := 22.0     ## PlayerMovementSettings.air_steer_accel
const WISH := 1.75      ## the RUN-tier air wish: max_speed 5.0 x air_speed_mult 0.35 (the walk tier is 1.23)
const BLEED := 0.0135   ## smoothing 0.135 / air_smoothing_divisor 10.0
const OLD_STANDING_TRAVEL := 0.1395  ## what the two-lerp model carried over one whole standing jump, in metres

## Deliberately LITERAL rather than read off GameSettings: these pin the SHAPE of the curve, and a designer
## retuning air_accel must not silently retune what "correct" means. tests/test_managers_tuning.gd is the
## separate ratchet that bounds the shipped values.


## One frame as the shell would drive it: a held direction asks for the full tier, a released one asks for
## nothing — while `tier` (the Player's per-airtime high-water) holds the settle floor either way.
func _step(v: Vector2, wish: Vector2, banked: float, bleed: float = 0.0, tier: float = WISH) -> Vector2:
	var asked: float = tier if wish.length_squared() > 0.0 else 0.0
	return AIR.step_horizontal(v, wish, asked, tier, banked, ACCEL, STEER, bleed, DT, FPS)


func _run(v: Vector2, wish: Vector2, banked: float, frames: int, bleed: float = 0.0, tier: float = WISH) -> Vector2:
	for _i in frames:
		v = _step(v, wish, banked, bleed, tier)
	return v


func test_no_wish_conserves_momentum_exactly() -> void:
	# Fault (2). The old air lerp had NO zero-input guard, so `direction` being Vector3.ZERO made both targets
	# 0.0 and the same lerp braked you toward a dead stop — ~48% of a jump's horizontal speed gone for letting
	# go of the keys. Nothing at or below the ceiling may touch you now.
	assert_eq(_step(Vector2(5.0, 0.0), Vector2.ZERO, 5.0, BLEED), Vector2(5.0, 0.0),
		"releasing every key mid-air must leave velocity EXACTLY untouched — the old air lerp braked you toward a dead stop for free")
	assert_eq(_run(Vector2(5.0, 0.0), Vector2.ZERO, 5.0, FRAMES, BLEED), Vector2(5.0, 0.0),
		"...and it must still be untouched after a WHOLE jump of no input, not merely drifting slowly")


func test_releasing_after_building_keeps_what_you_built() -> void:
	# THE CASE THE FIRST CUT GOT WRONG, and the reason the settle floor is a latched per-airtime HIGH-WATER
	# rather than the live stick-scaled wish. A standing jump banks ~0 on the ground, so if the floor tracked
	# the current frame's input, letting go would collapse it to 0 and bleed everything the air accel had just
	# built — fault (2) wearing a new hat, invisible to the momentum test above because that one starts at a
	# banked speed it never exceeds.
	var built := _run(Vector2.ZERO, Vector2(1.0, 0.0), 0.0, 20)
	assert_almost_eq(built.length(), WISH, 0.0001,
		"precondition: 20 frames of held input saturates the air wish from a standing jump")
	var coasted := _run(built, Vector2.ZERO, 0.0, 28, BLEED)
	assert_almost_eq(coasted.length(), WISH, 0.000001,
		"speed BUILT in the air must survive letting go of the key — building is a live decision, keeping what you built is not. If the settle floor tracks the live wish this bleeds ~27% over the rest of the jump")


func test_dropping_the_ground_tier_mid_air_does_not_brake() -> void:
	# Same root as above, reached the other way: releasing Run, scoping, or crouching mid-flight all LOWER
	# this frame's ground target. The latched floor is what stops that retroactively braking you.
	var built := _run(Vector2.ZERO, Vector2(1.0, 0.0), 0.0, 20)          # built to the 3.0 Run tier
	var after := _run(built, Vector2(1.0, 0.0), 0.0, 28, BLEED, WISH)    # tier stays at the high-water
	assert_almost_eq(after.length(), WISH, 0.0001,
		"letting go of Run (or scoping, or crouching) mid-air must not claw back speed already built — the latch is a high-water, so a lowered ground target only stops you building further")


func test_a_blast_from_a_standstill_still_damps_to_rest() -> void:
	# THE BLAST CONTRACT, and why the high-water is gated on input actually being held. A player launched by a
	# rocket who never presses anything has latched NO tier, so the settle floor is their banked 0 and the
	# excess decays to rest at exactly the historical rate. Latching unconditionally would floor this at the
	# walk tier and leave every knockback in the game coasting at ~2.1 m/s forever.
	var v := _run(Vector2(9.0, 0.0), Vector2.ZERO, 0.0, FRAMES, BLEED, 0.0)
	var old_model := 9.0 * pow(1.0 - BLEED, FRAMES)  # the two-lerp model with current_speed frozen at 0
	assert_almost_eq(v.length(), old_model, 0.000001,
		"a blast that launched a standing player must damp EXACTLY as it always has — apply_velocity re-adds ~10.7% of a live blast every frame and this settle is the only thing that ever removed it")


func test_a_standing_jump_actually_accelerates() -> void:
	# THE HEADLINE REGRESSION. current_speed had already decayed to ~0 while standing, so the old airborne lerp
	# chased direction * ~0.47 — holding a direction after a standing jump steered you toward the ZERO VECTOR.
	assert_almost_eq(_step(Vector2.ZERO, Vector2(1.0, 0.0), 0.0).x, ACCEL * DT, 0.00001,
		"the first airborne frame from a dead stop must add exactly air_accel * delta — the old model added nothing at all because its lerp target was the frozen standing speed")
	assert_almost_eq(_run(Vector2.ZERO, Vector2(1.0, 0.0), 0.0, 9).length(), WISH, 0.0001,
		"air_accel 12.0 must saturate the 1.75 m/s Run-tier air wish in 9 frames (0.15 s) — the first fifth of a jump, or the authority arrives too late to steer with")
	assert_almost_eq(_run(Vector2.ZERO, Vector2(1.0, 0.0), 0.0, FRAMES).length(), WISH, 0.0001,
		"...and it must then HOLD at the wish for the rest of the airtime rather than creeping past it")


func test_a_standing_jump_carries_over_a_metre() -> void:
	# The original complaint, as one number. Integrating the same 48 frames at the Run tier: the old model
	# travelled OLD_STANDING_TRAVEL, this one travels ~1.29 m. Deliberately NOT as far as air control could
	# reach — see test_a_run_up_is_what_buys_distance below: the tier is held low so that ground momentum, not
	# free air build, is what decides how far a jump goes.
	var v := Vector2.ZERO
	var travelled := 0.0
	for _i in FRAMES:
		v = _step(v, Vector2(1.0, 0.0), 0.0)
		travelled += v.x * DT
	assert_gt(travelled, 1.1,
		"a standing jump holding one direction must carry ~1.29 m — the model this replaced carried 0.14 m, which is what 'no air control' actually meant")
	assert_lt(travelled, 1.5,
		"...and no further: a standing jump that approaches a running one is exactly the flat spot that makes a run-up feel unrewarded")
	assert_gt(travelled, OLD_STANDING_TRAVEL * 8.0,
		"...and it must still beat the two-lerp model by nearly an order of magnitude, not by a tuning nudge")


func test_a_run_up_is_what_buys_distance() -> void:
	# THE MOMENTUM CURVE. Air travel is max(takeoff speed, the air tier) x airtime, so the tier is a FLAT SPOT:
	# every ground speed below it lands the same distance and a run-up buys nothing there. Holding the tier low
	# is half of what makes momentum matter (the other half is jump_momentum_boost, which lives on the Player
	# because it fires once at takeoff — pinned in test_player_core.gd).
	var standing := _travel(0.0)
	var walking := _travel(3.5)
	var sprinting := _travel(5.0)
	assert_gt(walking, standing * 2.0,
		"a walking take-off must carry more than TWICE a standing one — at the old 0.6 tier these were 2.80 m and 2.05 m, a 1.4x nothing, because the free air build masked the run-up entirely")
	assert_gt(sprinting, standing * 3.0,
		"and a sprint must carry more than THREE times a standing jump — this ratio IS the feature; raising air_speed_mult flattens it without making the air any more controllable, since steering is a pure rotation and is not scaled by it")
	assert_gt(sprinting, walking,
		"...and the curve must stay monotonic, so every metre per second of run-up is worth something")


## Horizontal distance covered over one full jump taken at `ground` m/s, holding that same direction.
func _travel(ground: float) -> float:
	var v := Vector2(ground, 0.0)
	var d := 0.0
	for _i in FRAMES:
		v = _step(v, Vector2(1.0, 0.0), ground, BLEED)
		d += v.x * DT
	return d


func test_the_takeoff_boost_cannot_bootstrap_a_free_bunnyhop() -> void:
	# THE REGRESSION THAT SHIPPED AND WAS CAUGHT. The boost scales the speed you are CARRYING, and a hop chain
	# spends only ONE grounded frame between jumps — which bleeds ~1.3% toward the ground target while the jump
	# adds 15%. Ungated that is +13.5% per hop, COMPOUNDING past every threshold in the game and past the 300 zm
	# Bunny-Hop chip's own 12.0 ceiling by the sixth hop, for free.
	var target := 5.0
	var boost := 0.15
	var v := target
	for _i in 12:
		# one hop cycle: the grounded arm's velocity lerp toward the ground target, then the take-off boost
		v += (target - v) * 0.135
		v = AIR.takeoff_speed(v, target, boost)
	assert_lte(v, target * (1.0 + boost) + 0.000001,
		"twelve chained hops must never exceed ONE boosted take-off — ungated this reaches 24 m/s, which is twice the paid Bunny-Hop chip's entire ceiling and clears the wind, look-sensitivity, pinball and ram thresholds on the way")
	assert_gte(v, target,
		"...while never decaying BELOW the ground speed the player is actually running at")


func test_the_takeoff_boost_converts_ground_speed_without_ever_reducing_it() -> void:
	assert_almost_eq(AIR.takeoff_speed(5.0, 5.0, 0.15), 5.75, 0.000001,
		"a full-speed run-up must convert at the shipped 15%: this is the whole 'a run-up buys distance' feature")
	assert_almost_eq(AIR.takeoff_speed(3.5, 5.0, 0.15), 4.025, 0.000001,
		"...and it must scale continuously with the run-up, so a walking take-off is rewarded proportionally rather than by a threshold")
	assert_eq(AIR.takeoff_speed(0.0, 5.0, 0.15), 0.0,
		"a standing jump must get exactly nothing — the boost is a fraction OF your momentum, which is what makes it a momentum reward at all")
	assert_eq(AIR.takeoff_speed(12.0, 5.0, 0.15), 12.0,
		"landing a 12 m/s grapple fling or bhop chain and jumping must keep ALL of it — the gate withholds the bonus above the ground target, it never claws speed back")
	assert_eq(AIR.takeoff_speed(5.0, 5.0, 0.0), 5.0,
		"jump_momentum_boost = 0 must be an exact no-op, the documented restore point for the whole momentum-launch feature")


func test_a_tapped_jump_still_buys_useful_authority() -> void:
	# A jump_cut_factor 0.4 TAP is only ~19 physics frames, and a short hop is the most common jump in a
	# shooter. air_accel has to saturate inside it, not merely inside the full 48-frame arc.
	assert_almost_eq(_run(Vector2.ZERO, Vector2(1.0, 0.0), 0.0, TAP_FRAMES).length(), WISH, 0.0001,
		"a tapped jump (~19 frames) must still reach the full air wish — air_accel 12.0 saturates in 15, so a short hop steers too")


func test_a_full_speed_turn_costs_no_speed() -> void:
	# Fault (3). A lerp toward `direction * speed` interpolates the CHORD between two equal-length vectors, so
	# every turn came out shorter — a held 90 degrees cost 29% of your speed. Steering is a pure rotation now.
	assert_almost_eq(_step(Vector2(5.0, 0.0), Vector2(0.0, -1.0), 5.0).length(), 5.0, 0.000001,
		"a mid-air turn must cost NO speed — the old lerp charged 29% for a held 90 degrees, which is why turning in the air felt like braking")
	assert_almost_eq(_run(Vector2(5.0, 0.0), Vector2(0.0, -1.0), 5.0, FRAMES).length(), 5.0, 0.0001,
		"...and it must still cost nothing after a WHOLE jump of hard steering, or the loss is merely slower")


func test_steer_rate_is_exactly_lateral_accel_over_speed() -> void:
	# The documented rate, isolated with accel 0.0 (the accelerate term also redirects, so the two must be
	# pinned apart). 22.0 / 5.0 = 4.4 rad/s = 252 deg/s at a running jump; a 90-degree correction costs 44%
	# of the airtime, which is the judgement call the whole feel rests on.
	var v := AIR.step_horizontal(Vector2(5.0, 0.0), Vector2(0.0, -1.0), WISH, WISH, 5.0, 0.0, STEER, 0.0, DT, FPS)
	assert_almost_eq(absf(Vector2(5.0, 0.0).angle_to(v)), STEER / 5.0 * DT, 0.00001,
		"the turn rate must be exactly air_steer_accel / speed radians per second — expressing authority as a LATERAL ACCELERATION is what makes it scale inversely with momentum from one number")
	assert_almost_eq(v.length(), 5.0, 0.000001,
		"...and the rotation alone must preserve the magnitude exactly")


func test_steer_never_overshoots_the_wish() -> void:
	# At 0.3 m/s the uncapped rate is 22 / 0.3 = 73 rad/s — 1.22 rad in ONE frame, far past a 45-degree wish.
	var wish := Vector2(1.0, 1.0).normalized()
	var v := AIR.step_horizontal(Vector2(0.3, 0.0), wish, WISH, WISH, 0.3, 0.0, STEER, 0.0, DT, FPS)
	assert_almost_eq(v.angle_to(wish), 0.0, 0.000001,
		"a slow drift whose one-frame turn rate exceeds the remaining angle must land exactly ON the wish, never past it — unclamped it would rotate through and back every frame as a visible jitter")
	assert_almost_eq(v.length(), 0.3, 0.000001,
		"...and the clamped rotation must still be magnitude-preserving")


func test_never_raises_horizontal_speed() -> void:
	# THE INVARIANT the whole regression argument rests on. 8.6 m/s is over every downstream gate that reads
	# horizontal speed, so this is the case where a leak would actually retune something.
	var v := Vector2(8.6, 0.0)
	for _i in FRAMES:
		v = _step(v, Vector2(0.0, -1.0), 8.6, BLEED)
		assert_lte(v.length(), 8.6 + 0.000001,
			"AirMovement must never RAISE the speed it was handed above max(that speed, the wish) — this one inequality is what keeps the wind loop's 6.5 m/s, the look-sensitivity falloff's 6.5, ram damage's 8.0, the pinball bounce's 7.0 and Slide.try_start's 4.0 in the regime they are tuned for")


func test_a_bhop_chain_is_never_bled_and_never_amplified() -> void:
	# The 300 zm Bunny-Hop chip's whole product is a 12 m/s chain. It passes through with NO exemption branch:
	# the settle cap floors at the banked speed, and the projection cap goes negative above the wish.
	assert_eq(_run(Vector2(12.0, 0.0), Vector2(1.0, 0.0), 12.0, FRAMES, BLEED), Vector2(12.0, 0.0),
		"a chained hop holding its line must pass through EXACTLY unchanged — assert_eq, not almost_eq: this is an untouched pass-through, not a near miss, and near-misses are how a chip gets quietly devalued")


func test_a_bhop_chain_steers_at_full_chain_speed() -> void:
	var v := _run(Vector2(12.0, 0.0), Vector2(0.0, -1.0), 12.0, FRAMES, BLEED)
	assert_almost_eq(v.length(), 12.0, 0.0001,
		"the chip's ceiling must survive a full airtime of hard steering untouched — steering is a pure rotation, so it can be generous without touching the speed economy")
	var degrees := rad_to_deg(absf(Vector2(12.0, 0.0).angle_to(v)))
	assert_gt(degrees, 80.0,
		"a max chain must still turn ~89 degrees per hop — enough to round a corner, so a chain is no longer a commitment to a straight line")
	assert_lt(degrees, 95.0,
		"...but not so far that a 12 m/s line needs no planning at all, which is what would make the chip trivial to hold")


func test_only_the_speed_above_the_ceiling_settles() -> void:
	# The historical air-lerp rate, reused verbatim on the ONE job it was actually doing. apply_velocity adds
	# explosion_velocity for the move and gives back only 1/blast_damp_divisor, so `velocity` permanently gains
	# ~10.7% of a live blast every frame — the old lerp is what damped that leak.
	var v := _step(Vector2(12.0, 0.0), Vector2.ZERO, 5.0, BLEED)
	assert_almost_eq(v.x, 11.9055, 0.0005,
		"only the OVER-ceiling excess may settle: 5.0 + 7.0 x (1 - 0.0135). Same rate, same knob, so an air dash / rocket jump / slide-jump / grapple fling carries exactly as far as it does today")


func test_a_grapple_fling_is_steerable_but_never_amplified() -> void:
	# GrappleHook's release_launch lands in `velocity`, not the blast channel, so it arrives here directly.
	var v := _step(Vector2(12.0, 0.0), Vector2(0.0, -1.0), 5.0, BLEED)
	assert_lte(v.length(), 12.0 + 0.000001,
		"an over-ceiling launch may be REDIRECTED but never amplified")
	assert_gt(absf(Vector2(12.0, 0.0).angle_to(v)), 0.0,
		"...and it must actually turn — the old air lerp bled this fling and could not steer it, which is why a grapple release felt like it flew you rather than you flying it")


func test_pressing_into_your_own_travel_is_the_one_sanctioned_brake() -> void:
	assert_lt(_step(Vector2(5.0, 0.0), Vector2(-1.0, 0.0), 5.0).length(), 5.0,
		"holding a direction against your own travel is the ONE way air control may slow you — deliberately, because you asked for it")
	var v := _run(Vector2(5.0, 0.0), Vector2(-1.0, 0.0), 5.0, FRAMES)
	assert_lt(v.x, 0.0,
		"a full jump of held counter-input must be able to genuinely reverse a running jump — killing your own momentum has to be possible or a misjudged leap is unrecoverable")
	assert_lte(v.length(), 5.0 + 0.000001,
		"...without ever exceeding the speed it started with, so a reversal is never a free launch")


func test_each_term_is_individually_a_documented_no_op() -> void:
	# THE BISECT PIN. An air-feel regression must bisect to ONE knob instead of a revert.
	assert_eq(AIR.step_horizontal(Vector2(2.0, 0.0), Vector2(1.0, 0.0), WISH, WISH, 5.0, 0.0, 0.0, 0.0, DT, FPS),
		Vector2(2.0, 0.0),
		"air_accel = 0 and air_steer_accel = 0 together must be an exact no-op below the ceiling — these are the documented per-term restore points")
	# Started BELOW the wish (1.0 < 1.75) so the accelerate term has headroom to act at all — above the wish its
	# projection cap goes negative and it correctly does nothing, which would prove neither knob.
	var no_steer := AIR.step_horizontal(Vector2(1.0, 0.0), Vector2(1.0, 0.0), WISH, WISH, 5.0, ACCEL, 0.0, 0.0, DT, FPS)
	assert_almost_eq(no_steer.y, 0.0, 0.000001,
		"air_steer_accel = 0 alone must leave the heading untouched — 'the vector you launch is the vector you land', with building still available")
	assert_almost_eq(no_steer.x, 1.0 + ACCEL * DT, 0.00001,
		"...while air_accel still builds along it, which is what makes the two knobs independently diagnosable")


func test_the_ceiling_floors_at_the_tier_so_the_edge_brake_cannot_starve_it() -> void:
	# player.gd's ledge edge-brake lerps current_speed toward 0 on the LAST grounded frame of a walk-off, so a
	# brake-starved banked speed arrives here exactly where the player most wants control.
	assert_almost_eq(_run(Vector2(0.05, 0.0), Vector2(1.0, 0.0), 0.05, FRAMES).length(), WISH, 0.0001,
		"a banked speed starved by the ledge edge-brake must NOT starve air steering — the maxf floor at the air tier is what stops the game removing control at the exact moment it is needed")


func test_degenerate_inputs_are_safe_no_ops() -> void:
	assert_eq(AIR.step_horizontal(Vector2(5.0, 0.0), Vector2(1.0, 0.0), WISH, WISH, 5.0, ACCEL, STEER, BLEED, 0.0, 0.0),
		Vector2(5.0, 0.0),
		"a zero delta must change nothing — every term scales by delta, and a paused/first frame must not teleport the player")
	assert_eq(AIR.step_horizontal(Vector2(5.0, 0.0), Vector2(1.0, 0.0), 0.0, 0.0, 0.0, ACCEL, STEER, 0.0, DT, FPS),
		Vector2(5.0, 0.0),
		"a zero wish speed with a zero tier and a zero banked speed must not brake — air_speed_mult = 0 degrades to 'redirect what you have', never to the old brake")
	var v := _step(Vector2.ZERO, Vector2.ZERO, 0.0, BLEED)
	assert_false(is_nan(v.x) or is_nan(v.y),
		"a dead-stop body with no input must not produce NAN — every division here is guarded (speed > 0 before the scale, MIN_STEER_SPEED before the rate, after > 0 before the clamp)")


func test_air_movement_never_writes_the_shared_ground_scalar() -> void:
	# TRAP-PROOFING. current_speed being frozen in the air LOOKS like the bug and is actually the fix: it is a
	# GROUND scalar CameraEffects.bob divides by max_speed for the head-bob amplitude.
	var air_src := FileAccess.get_file_as_string(AIR_PATH)
	assert_false(air_src.contains("current_speed ="),
		"AirMovement must READ the banked ground speed and never WRITE it — a mid-air write lands a stale, oversized head-bob on the touchdown frame. This pin is what stops the next pass 'fixing' the freeze")
	assert_true(air_src.contains("player.velocity.x = v_h.x"),
		"the shell must write ONLY the two horizontal channels — velocity.y belongs to gravity / jump / wall-climb / grapple, and fall damage, the long-fall kill and the fall-grey warning all read it alone")
	assert_true(air_src.contains("if player.is_climbing() or player.is_grapple_attached():"),
		"air control must stand down while climbing or while the rope is ATTACHED — and specifically NOT on the wider is_grappling(), which also covers the retract that follows a release: detach() applies the 12 m/s slingshot BEFORE flipping to RETRACTING, so the wide gate kills air control at the exact instant the player is flung")
	assert_true(air_src.contains("var settle_cap := maxf(banked_speed, air_tier)"),
		"the settle floor must read the LATCHED per-airtime tier, never the live stick-scaled wish — if it tracks the current frame's input then releasing the key, feathering a stick, scoping or opening a modal retroactively brakes speed already built in the air")
