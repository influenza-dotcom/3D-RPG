class_name HudSway
extends RefCounted

## Diegetic HUD "weight" (the Borderlands 2 feel): the maths behind the corner HUD cluster lagging a
## beat behind camera turns and settling back, so the UI reads as an instrument panel with mass rather
## than a decal on the glass. PURE STATE + MATH ONLY — no nodes, no autoload reads — so tests pin the
## damping behaviour off-tree. ui.gd owns the wiring: it measures the camera's yaw/pitch rates each
## frame, builds a target via look_target(), steps this spring, and writes the returned offset onto the
## `_weighted` carrier Control — and OPTIONALLY a whisper of the same offset onto the aim cluster (crosshair
## + stamina ring, scaled by hud_sway_aim_scale, which SHIPS AT 0 so the reticle is pinned): one spring, one
## mass. The look-name label and the combat arcs stay pinned; see ui.gd's HUD-weight comment for the rule.
##
## Model: a damped spring (semi-implicit Euler) with TWO input channels feeding one mass:
##   1. CONTINUOUS — a target displacement proportional to the look angular velocity. While the camera
##      turns, the target is pushed opposite the turn (the panel trails); when the turn stops the target
##      snaps to zero and the slightly under-damped spring carries the panel back with one small settle —
##      the "mass" read. Because ui.gd measures the camera's GLOBAL basis (and the camera sits under the
##      ScreenShake node), every ROTATIONAL camera behaviour rides this channel for free: mouse look,
##      trauma shake from weapons/explosions/landings/ram bounces — heavy shake reads as the panel
##      rattling against its mount, with no per-source coupling code.
##   2. DISCRETE — impulse(): a velocity kick for POSITIONAL camera events the basis measurement can't
##      see (the landing dip is a camera-local position punch, not a rotation). A kick is the right
##      physics for a one-frame event: it dips the panel and lets the spring settle it, frame-rate
##      independent — where a one-frame *target* spike would move the spring almost not at all.
## The CONTINUOUS channel's target is a SUM of readings (each a pure static below, all clamped together
## by look_target's caller under the one hud_sway_max promise):
##   - look_target()      — the camera's yaw/pitch rates (turns + every shake source, see above);
##   - velocity_target()  — the BODY's motion: strafe lean + the vertical float/press of jumps and
##     falls. Deliberately LATERAL + VERTICAL only: forward speed has no honest 2D direction on a
##     centre-anchored canvas, and the forward story is already told through FOV (the run/sprint
##     kicks), which the scale channel below picks up instead.
## Plus a SECOND, SCALAR spring (a separate HudSway instance driving .x) for the FOV "lens breath":
##   - fov_scale_target() — dynamic-FOV kicks (fall/rise speed-lines, forward-run, sprint, the dash
##     punch) breathe the lens; a panel that's part of the WORLD shrinks toward screen centre as the
##     lens widens and swells back as it narrows. Scale, not translation: a widening lens pushes ALL
##     corners outward at once, which a single Vector2 offset cannot express. The caller gates this
##     to zero while ADS-scoped or dialogue-zoomed — those own `fov` wholesale and would otherwise
##     park the panel shrunk/grown for their whole duration.
## Stiffness/damping/gain/clamp are HudSettings knobs ("HUD weight" group); the player-facing 0..1
## Settings.hud_sway_scale multiplies the TARGETS and scales every kick (kick_scaled), so accessibility
## scaling changes amplitude without changing the motion's character — and 0 silences every channel.

## One spring step never integrates more than this slice of time: a frame hitch (a 0.5 s stall) fed
## straight into Euler integration would overshoot violently or explode. Clamping dt just makes the
## spring move less that frame — the HUD briefly under-swings after a hitch, which nobody can see.
const MAX_STEP_DT := 1.0 / 30.0

## Current displacement (px, canvas space) — what ui.gd writes onto the carrier each frame.
var offset: Vector2 = Vector2.ZERO
## Current spring velocity (px/s), integrated across frames.
var velocity: Vector2 = Vector2.ZERO

## The displacement target for the current look rates: px = rate (rad/s) * gain (px·s/rad), per axis,
## clamped to `max_px` so a violent flick parks the panel at the subtle cap instead of launching it
## off-screen. Signs: the caller passes signed rates; positive gain trails the turn (yaw right -> panel
## eases left, look up -> panel eases down). Flip a gain component's sign if a rig reads backwards.
static func look_target(yaw_rate: float, pitch_rate: float, gain: Vector2, max_px: float) -> Vector2:
	return Vector2(yaw_rate * gain.x, pitch_rate * gain.y).limit_length(maxf(max_px, 0.0))

## The displacement asked for by the BODY's motion: `lateral` = the velocity component along the
## camera's right axis (m/s, + = moving right), `vertical` = world-Y velocity (+ = rising). The panel
## LEANS AGAINST lateral motion (strafe right -> panel eases left, inertia) and COUNTERS vertical
## motion (jump launch presses it down, a fall floats it up — so the existing land_kick then SLAMS it
## down on touchdown, and the whole jump reads float-then-thud). Unclamped here on purpose: the caller
## sums this with look_target and clamps the TOTAL to hud_sway_max, so the 8 px promise holds across
## channels instead of each channel claiming 8 px of its own. Signs live in the formula (not the gain)
## so a designer's gain stays positive-means-natural; flip a component to invert a read.
static func velocity_target(lateral: float, vertical: float, gain: Vector2) -> Vector2:
	return Vector2(-lateral * gain.x, vertical * gain.y)

## The scale delta asked for by the lens: `fov`/`rest_fov` in degrees, `gain` = scale delta per
## fraction-of-rest FOV change, clamped to ±`max_frac`. WIDER than rest -> NEGATIVE (the panel shrinks
## toward screen centre with the rest of the world); narrower -> swells. Returns 0 for a degenerate
## rest_fov so an unprimed camera read can never divide by zero.
static func fov_scale_target(fov: float, rest_fov: float, gain: float, max_frac: float) -> float:
	if rest_fov <= 0.0:
		return 0.0
	var cap := maxf(max_frac, 0.0)
	return clampf(-gain * (fov - rest_fov) / rest_fov, -cap, cap)

## Clamp-then-scale an impact kick (px/s): the AUTHORED magnitude is capped first (`max_px_s`, so a
## hot-tuned or stacked event parks at the subtle ceiling instead of launching the panel), THEN the
## accessibility scale shrinks what survived — so 50% sway halves the capped kick, and 0 silences it.
## Static + argument-fed (no autoload reads) so tests pin the order off-tree.
static func kick_scaled(kick: Vector2, max_px_s: float, scale: float) -> Vector2:
	return kick.limit_length(maxf(max_px_s, 0.0)) * clampf(scale, 0.0, 1.0)

## The landing kick for a touchdown of `intensity` [0..1] (player.gd's dampened landing impact — already
## fall-speed-normalized and crouch-softened, the SAME signal the camera dip and landing shake use, so
## all three read one event at one strength). Canvas +y is DOWN: the panel dips with the camera, then
## the under-damped spring carries it back up through one small overshoot. Negative intensity = no kick.
static func land_kick(intensity: float, kick_px_s: float) -> Vector2:
	return Vector2(0.0, maxf(intensity, 0.0) * kick_px_s)

## Kick the spring's velocity directly (px/s) — the discrete-event channel (see the header). The caller
## (ui.hud_kick) is responsible for cap + accessibility scale via kick_scaled; this stays raw math.
func impulse(kick: Vector2) -> void:
	velocity += kick

## Advance the spring one frame toward `target` and return the new offset. Semi-implicit Euler:
## acceleration = stiffness * error - damping * velocity. With the shipped knobs (70 / 12) the damping
## ratio is ~0.72 — slightly under-damped on purpose, so release carries ONE small overshoot (the
## "settle" that sells mass) and then rests; ratio >= 1 would ease back with no life at all.
func step(target: Vector2, stiffness: float, damping: float, delta: float) -> Vector2:
	var dt := clampf(delta, 0.0, MAX_STEP_DT)
	velocity += (stiffness * (target - offset) - damping * velocity) * dt
	offset += velocity * dt
	return offset

## Zero the spring (a respawn/reload seam if a caller ever needs a clean panel on frame one).
func reset() -> void:
	offset = Vector2.ZERO
	velocity = Vector2.ZERO
