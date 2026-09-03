class_name AirMovement

## Pure AIRBORNE horizontal-control math — the air half of what GroundMovement (M13) is for the ground.
## Stateless statics only, never instantiated: `step_horizontal` is PURE Vector2 math (no body, no physics
## space, no GameSettings read), so the whole feel curve is unit-testable off-tree with zero engine errors —
## unlike MovementHelpers.extra_brake_t, whose get_world_3d() probe has to be guarded for exactly that reason.
## `step` is the thin shell player.gd's airborne arm calls: it reads the tuning + the Player's live state and
## writes the two horizontal channels.
##
## THE MODEL IN ONE SENTENCE: in the air you may always change WHERE you are going, and you may only change
## HOW FAST up to the speed you banked on the ground.
##
## ⭐THE INVARIANT THAT MAKES THIS SAFE TO SHIP: step_horizontal NEVER RAISES the horizontal speed it is
## handed. It can rotate it (free), grow it toward the wish speed from BELOW, or settle an over-ceiling launch
## back down at the historical rate — never past max(the speed it was handed, the wish speed). Since the wish
## speed is the ground target scaled by air_speed_mult (<= walk_speed_mult), the airborne speed a player can
## reach is bounded by the speed they already had on the floor: nothing reachable in the air was not already
## reachable on foot. THAT is what leaves every downstream horizontal-speed gate in the regime it is tuned for
## — the wind loop's 6.5 m/s, the bunny-hop look-sensitivity falloff's 6.5, ram damage's 8.0, the pinball
## bounce's 7.0, Slide.try_start's 4.0. Break the invariant and you silently retune all five.
##
## WHAT IT REPLACED, so nobody re-introduces it. The airborne arm used to be two lerps chasing `direction`
## scaled by the frozen `current_speed`, at a tenth of the ground rate. That scalar is written ONLY on grounded
## paths (player.gd's grounded arm, its edge brake, the bhop stamp, and Slide.update_movement — five writers,
## all grounded), so the air target's MAGNITUDE was frozen at whatever you left the floor with. Three faults,
## one cause: (1) a standing jump froze it at ~0, so holding a direction in the air steered you toward the ZERO
## VECTOR — 0.14 m of travel over a whole 0.81 s jump, i.e. no air control at all; (2) with no key held
## `direction` is exactly Vector3.ZERO, so the SAME lerp braked you — 48% of your horizontal speed gone over
## one jump for letting go; (3) a lerp toward a target interpolates the CHORD between two vectors, so any turn
## came out shorter — a held 90 degrees cost 29% of your speed.
## The variable was never wrong; its ROLE was. Frozen at takeoff it is a perfect air speed CEILING — which is
## exactly why a bhop chain (whose whole job is to stamp that scalar up to 12 m/s on the jump frame) has always
## been the one thing in this game that felt like it had air control. So it is READ here as the ceiling and
## still never WRITTEN while airborne: CameraEffects.bob divides it by max_speed for the head-bob amplitude,
## and a mid-air write would land a stale, oversized bob on the touchdown frame.

## Below this horizontal speed there is no meaningful heading to rotate — accelerate builds one first, and
## dividing by a near-zero speed would ask for an absurd turn rate.
const MIN_STEER_SPEED: float = 0.05
## Below this squared length a wish counts as NO input (deadzoned stick, menu-zeroed input, a vertical-only
## wish). Its OWN constant rather than MovementHelpers.EDGE_WISH_EPSILON's: the edge brake and air control are
## unrelated systems that merely both need a deadzone, and sharing one would couple their tuning.
const AIR_WISH_EPSILON: float = 0.000001


## THE TAKE-OFF CONVERSION: the horizontal speed a jump actually leaves the ground with, given the speed being
## carried (`carried`), the speed the GROUND would give you this frame (`ground_target`), and
## PlayerMovementSettings.jump_momentum_boost. Pure, so the hop-chain behaviour is unit-testable.
##
## ⭐⭐THE `carried > ground_target` GATE IS THE WHOLE FUNCTION — without it this is an unbounded free
## bunny-hop. The boost scales the speed you are CARRYING, and a hop chain only spends ONE grounded frame
## between jumps, which bleeds ~1.3% toward the ground target while the jump adds 15%. Net +13.5% per hop,
## COMPOUNDING: 5.75, 6.60, 7.55, 8.63 ... 24 m/s by the twelfth hop. That clears the wind loop (6.5), the
## look-sensitivity falloff (6.5), the pinball bounce (7.0), ram damage (8.0) and the 300 zm Bunny-Hop chip's
## entire 12.0 ceiling — with no implant, no chain skill and no stamina beyond the per-jump cost.
## Gating on "the speed is still GROUND-LEGAL" makes the boost a one-shot CONVERSION of ground momentum
## instead of a multiplier that can bootstrap itself: over the ground target it returns `carried` untouched, so
## a chain oscillates in [ground_target, ground_target x (1 + boost)] and decays back down rather than climbing.
## It also never REDUCES what it is handed — landing a 12 m/s grapple fling and jumping keeps all 12.
static func takeoff_speed(carried: float, ground_target: float, boost: float) -> float:
	if boost <= 0.0 or carried <= 0.0 or carried > ground_target:
		return carried
	return carried * (1.0 + boost)


## ONE airborne physics frame of horizontal motion. PURE — hand it numbers, get numbers back.
##
## `v_h`             current horizontal velocity (x, z).
## `wish_dir`        world-space horizontal steering direction; ZERO = no input.
## `wish_speed`      the speed THIS frame's input may BUILD up to — stick-scaled, so feathering builds slower.
## `air_tier`        the settle FLOOR: the per-airtime high-water of the air tier, latched by the Player while
##                   input is held. Deliberately NOT `wish_speed`: if the settle floor tracked the live stick
##                   then releasing the key, feathering it, scoping, crouching, dropping the Run tier or
##                   opening a modal (which zeroes input_dir) would retroactively collapse the floor and BRAKE
##                   speed already built in the air — fault (2) wearing a new hat. Building is a live decision;
##                   keeping what you built is not.
## `banked_speed`    the speed banked on the ground: Player.current_speed, frozen since takeoff.
## `accel`           m/s^2 of build authority along the wish (PlayerMovementSettings.air_accel).
## `steer_accel`     m/s^2 of LATERAL authority rotating the existing velocity (air_steer_accel).
## `overspeed_ratio` per-reference-frame fraction by which speed ABOVE the ceiling settles back toward it.
## `delta`           the physics step.
## `fps_factor`      delta * smoothing_reference_fps — the house frame-rate normaliser (player.gd's block).
static func step_horizontal(v_h: Vector2, wish_dir: Vector2, wish_speed: float, air_tier: float,
		banked_speed: float, accel: float, steer_accel: float, overspeed_ratio: float, delta: float,
		fps_factor: float) -> Vector2:
	var v := v_h
	# 1) OVER-CEILING SETTLE. The ceiling is whatever you banked on the ground, or the air tier you have asked
	# for at any point this airtime, whichever is higher — the maxf is what protects a bhop chain (banked up to
	# BunnyhopSettings.max_speed 12.0) from
	# ever being dragged back toward walking pace, AND what stops the ledge edge-brake — which lowers the banked
	# speed on the LAST grounded frame of a walk-off — from starving air steering exactly where you most want
	# it. Only the part ABOVE settles, and scale-only so the heading is untouched.
	# This is the one half of the old air lerp that was doing real work: apply_velocity adds `explosion_velocity`
	# for the move and gives back only 1/blast_damp_divisor of it, so `velocity` permanently gains ~10.7% of a
	# live blast every frame — an air dash, a rocket shove, a slide-jump, a ram bounce and the grapple's release
	# fling all LEAK into the controller channel, and the old lerp is what damped them. Same rate, same knob, so
	# launch carry is preserved bit-for-bit instead of silently made ~1.5x longer. At or below the ceiling
	# nothing is touched — that is fault (2) fixed: letting go of the keys no longer costs you anything.
	var settle_cap := maxf(banked_speed, air_tier)
	var speed := v.length()
	if speed > settle_cap and overspeed_ratio > 0.0 and speed > 0.0:
		var keep := pow(1.0 - clampf(overspeed_ratio, 0.0, 1.0), fps_factor)
		var settled := settle_cap + (speed - settle_cap) * keep
		v *= settled / speed
		speed = settled
	if wish_dir.length_squared() < AIR_WISH_EPSILON:
		return v  # no intent: nothing below may touch you. Momentum is yours to keep.
	var wish := wish_dir.normalized()
	# 2) STEER — a PURE ROTATION toward the wish, at steer_accel / speed rad/s. Expressed as a LATERAL
	# ACCELERATION rather than an angular rate so turn authority scales inversely with momentum for free: a
	# 3 m/s drift turns on the spot while a 12 m/s bhop chain has to be planned, from one number and with no
	# special-casing. Magnitude is preserved EXACTLY, which is what lets this be generous without ever touching
	# the speed economy the 300 zm Bunny-Hop chip sells into. This is fault (3) fixed.
	if speed >= MIN_STEER_SPEED and steer_accel > 0.0:
		var to_wish := v.angle_to(wish)  # signed, -PI..PI
		var step_rad := (steer_accel / speed) * delta
		# Clamped to the REMAINING angle: below ~1 m/s the uncapped rate exceeds 600 deg/s and would rotate
		# straight past the wish and back again every frame.
		v = v.rotated(clampf(step_rad, 0.0, absf(to_wish)) * signf(to_wish))
	# 3) ACCELERATE — Quake's PM_AirAccelerate. The add is capped by the wish speed we do NOT already carry along
	# the wish, so it switches itself off the moment you match it: a bhop chain, a grapple slingshot and an air
	# dash all pass through untouched with NO exemption branch. Runs AFTER the steer on purpose — rotating first
	# grows the wish-ward projection, which shrinks this add, so the pair is self-limiting instead of stacking
	# into an overshoot. A wish pointing back down your own travel makes the dot negative and hands you the full
	# step as counter-thrust: killing your own momentum is the one sanctioned deceleration, and it is bounded —
	# reversing a 5 m/s run jump costs most of the flight. This is fault (1) fixed.
	if accel > 0.0:
		var add := clampf(wish_speed - v.dot(wish), 0.0, accel * delta)
		if add > 0.0:
			v += wish * add
	# 4) NO-GAIN CLAMP — re-derived from the LIVE speed every frame and never latched, so a one-frame blast spike
	# cannot raise the ceiling for the rest of the airtime. Above the wish speed it hands the magnitude straight
	# back after the rotation (the lossless turn); below it, it lets the accelerate reach the wish and no
	# further. Together with the additive accelerate this is the ⭐never-raises-speed invariant in the header,
	# and it is what stops a steer-then-accelerate pair quietly manufacturing speed on every turn.
	var ceiling := maxf(speed, wish_speed)
	var after := v.length()
	if after > ceiling and after > 0.0:
		v *= ceiling / after
	return v


## The shell player.gd's airborne arm calls: reads the tuning + the Player's live state and writes the two
## horizontal channels. Vertical is NEVER touched — gravity / jump / wall-climb / grapple own velocity.y, and
## that is what keeps fall damage, the long-fall death timer and the fall-grey warning (all three read
## velocity.y alone) bit-identical to before this existed.
##
## STANDS DOWN while wall-climbing or while the rope is ATTACHED. Both run LATER in the same step (player.gd
## calls WallClimb.tick and then Grapple.apply_pull after this arm) and both do their own read-modify-write on
## `velocity`, and the OLD air lerp was already fighting them: it shoved the player along the wall before the
## grip could correct, and it bled the tangential speed a grapple swing is entirely made of. WallClimb reads
## the SAME WASD vector as climb up/down, so feeding those keys into a horizontal steer would be a miscoded
## intent; the rope is not left without control — GrappleHook's own swing_assist reads the stick directly and
## is tuned as part of the swing's feel.
## ⭐The grapple gate is is_grapple_ATTACHED, deliberately NOT the wider is_grappling() that step assist uses.
## GrappleHook.apply_pull and swing_assist both early-out unless the state is ATTACHED, so a rope merely flying
## out, and the whole RETRACT after a release, have no competing authority — and detach() applies the 12 m/s
## slingshot BEFORE flipping to RETRACTING, so the wide gate would kill air control at the exact instant you
## are flung and most want to aim it. The fling is safe to steer because it arrives ABOVE the ceiling, where
## the never-raises-speed invariant lets it be redirected but never amplified.
## Both gates read LAST frame's latch because this arm precedes both ticks — the same one-frame staleness
## `is_on_floor()` already carries at the branch above, and the answer we want: a held grip reads true.
## ACCEPTED CONSEQUENCE of the climb gate: WallClimb kills only the OUTWARD (wall-normal) component and sets
## velocity.y, so TANGENTIAL along-wall drift is no longer bled while gripping the way the old air lerp bled
## it. Gripping a wall at a sideways run therefore keeps sliding along it. Judged correct — you are holding a
## wall and moving along it — and cheaper than a partial step; if it ever reads wrong, damp it in WallClimb
## where the wall normal is in hand, not by letting air steering fight the grip.
static func step(player: Player, direction: Vector3, target_speed: float, air_tier: float, delta: float,
		fps_factor: float) -> void:
	if player.is_climbing() or player.is_grapple_attached():
		return
	var mv: PlayerMovementSettings = GameSettings.player_movement
	# ANALOG MAGNITUDE. `direction` arrives normalised (player.gd flattens and normalises the raw stick), so a
	# half-deflected stick would otherwise ask for FULL air authority — binary air control on a gamepad, with no
	# way to feather a correction. Input.get_vector already deadzones and clamps to length 1, so this IS the
	# feather: a half stick asks for half the air speed and turns half as hard. Keyboard reads exactly 1.0, so
	# nothing about mouse-and-keyboard feel changes.
	# ...and it scales ALL THREE authority channels, not two: an unscaled accel would hand a 20%-deflected stick
	# the full 0.2 m/s per frame, so a controller could feather its heading but its BRAKE would still be on/off.
	# Scaling accel alongside wish_speed is also Quake's own shape (accelspeed = accel x wishspeed x frametime),
	# and because both scale together the saturation TIME is unchanged at any deflection — the 15-frame figure in
	# air_accel's doc comment stays true on a half stick instead of only on a pinned one.
	var wish_scale := clampf(player.input_dir.length(), 0.0, 1.0)
	var v_h := step_horizontal(
			Vector2(player.velocity.x, player.velocity.z),
			Vector2(direction.x, direction.z),
			target_speed * mv.air_speed_mult * wish_scale,
			air_tier,
			player.current_speed,
			mv.air_accel * wish_scale,
			mv.air_steer_accel * wish_scale,
			mv.smoothing / maxf(mv.air_smoothing_divisor, 0.0001),
			delta, fps_factor)
	player.velocity.x = v_h.x
	player.velocity.z = v_h.y
