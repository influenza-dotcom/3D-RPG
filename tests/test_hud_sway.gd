extends GutTest

## Diegetic HUD weight (scripts/ui/hud_sway.gd + the ui.gd wiring's knobs): the damped-spring maths
## behind the corner HUD cluster trailing camera turns. Pure state off-tree — target clamping, spring
## convergence, the settle-back-to-zero, the frame-hitch dt clamp, the PROMISES the shipped HudSettings
## "HUD weight" knobs must keep (driven through the real spring, never pinned as literals), and the
## Settings accessibility scale. The last word on feel is still a playtest; these pin its bounds.

## Loaded BY PATH (not the class_name) — the editor class-cache cascade guard.
const SWAY := preload("res://scripts/ui/hud_sway.gd")

## A REFERENCE spring for the maths tests: the ~0.72-ratio under-damped pair HudSettings' docs derive their
## numbers from (the 0.044*v kick-peak law). Deliberately NOT read from HudSettings — the maths must hold for
## this reference whatever a designer retunes. The SHIPPED knobs are exercised by the test_shipped_* tests.
const STIFFNESS := 70.0
const DAMPING := 12.0
const DT := 1.0 / 60.0
## HudSettings.hud_sway_max's documented ceiling: past ~12 px on the 792x444 canvas the panel reads seasick.
const SEASICK_PX := 12.0
## "Went past home at all": far above the semi-implicit integrator's own residue near critical damping (well
## under 0.001 px), so any release excursion past this is a real under-damped overshoot, however small.
const OVERSHOOT_EPS_PX := 0.01
## A second swing back past home smaller than this is not read as wobble: a quarter of a canvas pixel, ~0.6
## screen px after the 792x444 canvas's ~2.4x upscale. Deliberately a VISIBILITY bound, not a band around the
## shipped damping, so a designer can retune the spring's feel without tripping it.
const RINGING_PX := 0.25

var _prev_loaded: bool
var _prev_scale: float

func before_each() -> void:
	# Never let a setter round-trip clobber the real user://settings.cfg (the test_settings.gd idiom).
	_prev_loaded = Settings._loaded
	_prev_scale = Settings.hud_sway_scale
	Settings._loaded = false

func after_each() -> void:
	Settings.hud_sway_scale = _prev_scale
	Settings._loaded = _prev_loaded

# --- target mapping -----------------------------------------------------------------------------------

func test_look_target_zero_rates_is_zero() -> void:
	assert_eq(SWAY.look_target(0.0, 0.0, Vector2(2.6, 2.2), 8.0), Vector2.ZERO,
		"a still camera asks for zero displacement — the panel rests exactly home")

func test_look_target_scales_per_axis_by_gain() -> void:
	var t: Vector2 = SWAY.look_target(1.0, -1.0, Vector2(2.0, 3.0), 100.0)
	assert_almost_eq(t.x, 2.0, 0.0001, "x displacement = yaw rate * gain.x (px per rad/s)")
	assert_almost_eq(t.y, -3.0, 0.0001, "y displacement = pitch rate * gain.y, sign preserved (direction = trail)")

func test_look_target_clamps_a_violent_flick_to_max_px() -> void:
	var t: Vector2 = SWAY.look_target(50.0, 50.0, Vector2(2.6, 2.2), 8.0)
	assert_almost_eq(t.length(), 8.0, 0.001,
		"a flick parks the target on the max_px circle — the sway cap is a hard promise, not a suggestion")

# --- spring behaviour ---------------------------------------------------------------------------------

func test_step_converges_on_a_held_target() -> void:
	var s = SWAY.new()
	var target := Vector2(6.0, 0.0)
	for i in 240:  # 4 simulated seconds at 60 fps
		s.step(target, STIFFNESS, DAMPING, DT)
	assert_almost_eq(s.offset.x, 6.0, 0.25,
		"holding a turn, the panel settles onto the lag target (spring converges, no residual oscillation)")
	s = null

func test_step_settles_back_to_zero_when_the_look_stops() -> void:
	var s = SWAY.new()
	for i in 60:
		s.step(Vector2(8.0, 0.0), STIFFNESS, DAMPING, DT)  # swing out…
	for i in 240:
		s.step(Vector2.ZERO, STIFFNESS, DAMPING, DT)  # …then the camera stops
	assert_lt(s.offset.length(), 0.1,
		"with the target back at zero the panel returns home — the sway never parks off-centre")
	s = null

func test_step_overshoots_once_then_settles_the_mass_read() -> void:
	# The reference pair is deliberately slightly UNDER-damped (~0.72 ratio): releasing a held swing must carry
	# the panel past home ONCE (the settle that sells mass) and then rest — never swing back past home again,
	# which reads as wobble. Tracked the same way as the shipped-knob test: the deepest excursion past home on
	# the far side, then any rebound back over home after it.
	var s = SWAY.new()
	for i in 60:
		s.step(Vector2(8.0, 0.0), STIFFNESS, DAMPING, DT)
	var overshoot := 0.0  # deepest excursion past home, on the far side from the held swing
	var rebound := 0.0    # any swing BACK past home after that overshoot — ringing
	for i in 240:
		var x: float = s.step(Vector2.ZERO, STIFFNESS, DAMPING, DT).x
		if x < 0.0:
			overshoot = minf(overshoot, x)
		elif overshoot < -OVERSHOOT_EPS_PX:
			rebound = maxf(rebound, x)
	assert_lt(overshoot, -0.05, "release carries one visible overshoot past home (under-damped on purpose)")
	assert_lt(rebound, RINGING_PX,
		"...and only ONE: the spring must not swing back past home a second time (%.3f px) — ringing reads as wobble" % rebound)
	assert_lt(s.offset.length(), 0.1, "…and still dies out to rest")
	s = null

func test_step_survives_a_frame_hitch_without_exploding() -> void:
	# A 2-second stall fed raw into Euler integration would overshoot violently; MAX_STEP_DT clamps the
	# integrated slice so a hitch merely under-swings that frame.
	var s = SWAY.new()
	var off: Vector2 = s.step(Vector2(8.0, 0.0), STIFFNESS, DAMPING, 2.0)
	assert_true(is_finite(off.x) and is_finite(off.y), "a hitch-sized dt never produces NaN/inf")
	assert_lt(off.length(), 16.0, "one hitch step stays bounded (clamped dt, no spring explosion)")
	s = null

func test_reset_zeroes_offset_and_velocity() -> void:
	var s = SWAY.new()
	for i in 30:
		s.step(Vector2(8.0, 4.0), STIFFNESS, DAMPING, DT)
	s.reset()
	assert_eq(s.offset, Vector2.ZERO, "reset parks the panel home")
	assert_eq(s.velocity, Vector2.ZERO, "reset kills the spring velocity too (no ghost swing on frame one)")
	s = null

# --- the body-motion lean (velocity channel) ---------------------------------------------------------

func test_velocity_target_leans_against_strafe() -> void:
	# Inertia: strafe RIGHT (+lateral) -> the panel eases LEFT (-x). The sign lives in the formula, not
	# the gain, so a designer's gain stays positive-means-natural.
	var t: Vector2 = SWAY.velocity_target(5.0, 0.0, Vector2(0.45, 0.3))
	assert_almost_eq(t.x, -2.25, 0.0001, "a full-speed right strafe (5 m/s) leans the panel ~2.3 px left")
	assert_almost_eq(t.y, 0.0, 0.0001, "no vertical motion, no vertical lean")

func test_velocity_target_floats_on_a_fall_and_presses_on_a_launch() -> void:
	# The jump arc's read: launch (+vy) presses the panel DOWN (+y), the fall (-vy) FLOATS it up (-y) —
	# and the land kick then thuds it down, so the whole hop is press/float/thud in order.
	var fall: Vector2 = SWAY.velocity_target(0.0, -12.0, Vector2(0.45, 0.3))
	assert_almost_eq(fall.y, -3.6, 0.0001, "a 12 m/s fall floats the panel ~3.6 px UP (weightless read)")
	var launch: Vector2 = SWAY.velocity_target(0.0, 4.5, Vector2(0.45, 0.3))
	assert_almost_eq(launch.y, 1.35, 0.0001, "a jump launch presses it down — mass lags the rise")

func test_velocity_target_is_unclamped_the_caller_caps_the_sum() -> void:
	# Deliberately raw: ui.gd sums look + lean and clamps the TOTAL to hud_sway_max, so the 8 px promise
	# is one budget across channels — a per-channel clamp here would let look 8 + lean 8 = 16 px slip out.
	var t: Vector2 = SWAY.velocity_target(100.0, -100.0, Vector2(0.45, 0.3))
	assert_almost_eq(t.x, -45.0, 0.0001, "no internal clamp on lateral")
	assert_almost_eq(t.y, -30.0, 0.0001, "no internal clamp on vertical — the SUM cap in ui.gd is the promise")

# --- the lens breath (FOV scale channel) -------------------------------------------------------------

func test_fov_scale_target_shrinks_when_the_lens_widens() -> void:
	# A +20% FOV kick (the dash punch: 75 -> 90) shrinks the panel ~2% toward screen centre — the world
	# compresses as the lens widens, and a diegetic panel compresses with it. Narrower swells it back.
	assert_almost_eq(SWAY.fov_scale_target(90.0, 75.0, 0.1, 0.04), -0.02, 0.0001,
		"wider lens -> negative scale delta (panel shrinks with the world)")
	assert_almost_eq(SWAY.fov_scale_target(67.5, 75.0, 0.1, 0.04), 0.01, 0.0001,
		"narrower lens -> the panel swells back toward the eye")
	assert_almost_eq(SWAY.fov_scale_target(75.0, 75.0, 0.1, 0.04), 0.0, 0.0001,
		"at rest FOV the lens-breath asks for nothing")

func test_fov_scale_target_clamps_and_survives_degenerate_rest() -> void:
	# The ADS scope drops fov to ~40 — ui.gd GATES scope out entirely, but if a future caller forgets,
	# the clamp keeps the worst case at the cap (a 4% swell), never a comedy zoom. rest_fov <= 0 (an
	# unprimed camera read) must return 0, not divide by zero.
	assert_almost_eq(SWAY.fov_scale_target(40.0, 75.0, 0.1, 0.04), 0.04, 0.0001,
		"a scope-sized narrow parks at +cap, not +4.7% raw")
	assert_almost_eq(SWAY.fov_scale_target(179.0, 75.0, 0.1, 0.04), -0.04, 0.0001,
		"a wild wide parks at -cap")
	assert_eq(SWAY.fov_scale_target(90.0, 0.0, 0.1, 0.04), 0.0,
		"degenerate rest_fov degrades to zero — never a divide-by-zero")

func test_shipped_motion_channels_lean_naturally_inside_the_one_sway_budget() -> void:
	# The LIVE shipped resource (GameSettings.hud = HudSettings.tres), driven through the real statics. The
	# lean gains are positive-means-natural by contract (the inertia sign lives in velocity_target), and the
	# lean SUMS with the look target under the ONE hud_sway_max cap — so a full-speed strafe on its own must
	# leave the look channel room, or turning while strafing reads dead.
	var h: HudSettings = GameSettings.hud
	assert_gt(h.hud_vel_gain.x, 0.0,
		"hud_vel_gain.x must be positive — the inertia sign is in the formula, so a negative gain leans the panel INTO a strafe")
	assert_gt(h.hud_vel_gain.y, 0.0,
		"hud_vel_gain.y must be positive — a negative gain floats the panel on a jump launch and presses it down on a fall")
	var strafe: Vector2 = SWAY.velocity_target(GameSettings.player_movement.max_speed, 0.0, h.hud_vel_gain)
	assert_gt(strafe.length(), 0.0, "a full-speed strafe must lean the panel at all, or the body channel is dead")
	assert_lt(strafe.length(), h.hud_sway_max,
		"a full-speed strafe alone must lean less than hud_sway_max, or the shared cap leaves the look channel no travel")
	# Lens breath with the shipped gain + cap: the panel belongs to the WORLD, so it shrinks as the lens widens.
	var rest: float = GameSettings.camera.default_fov
	assert_lte(SWAY.fov_scale_target(rest * 1.3, rest, h.hud_fov_scale_gain, h.hud_fov_scale_max), 0.0,
		"a widening lens must never SWELL the panel (a negative hud_fov_scale_gain inverts the lens breath)")
	assert_gte(SWAY.fov_scale_target(rest * 0.7, rest, h.hud_fov_scale_gain, h.hud_fov_scale_max), 0.0,
		"a narrowing lens must never SHRINK the panel")

# --- the discrete impact channel (impulse / kicks) ---------------------------------------------------

func test_impulse_dips_downward_then_settles_home() -> void:
	# A landing kick is +y (canvas DOWN): the panel must move DOWN first — a panel that pops UP on
	# touchdown reads as anti-gravity, not weight — then the under-damped spring must bleed the energy
	# out and park home: the dip is transient by contract, never a resting offset.
	var s = SWAY.new()
	s.impulse(Vector2(0.0, 110.0))
	var first: Vector2 = s.step(Vector2.ZERO, STIFFNESS, DAMPING, DT)  # annotated, not := — s is Variant (preload-by-path idiom)
	assert_gt(first.y, 0.0, "frame one after a landing kick moves the panel DOWN (+y), with the camera dip")
	for i in 240:  # 4 s at 60 fps — far past the ~0.7 s settle envelope
		s.step(Vector2.ZERO, STIFFNESS, DAMPING, DT)
	assert_almost_eq(s.offset.y, 0.0, 0.05, "the dip settles fully home — a kick never leaves a resting offset")
	assert_almost_eq(s.velocity.y, 0.0, 0.5, "...and the spring energy is spent (no perpetual wobble)")
	s = null

func test_impulse_peak_is_subtle_at_the_shipped_kick() -> void:
	# Pin the tuning math documented on HudSettings.hud_land_kick: with the 70/12 reference spring a kick
	# of v peaks at ~0.044*v px in a 60 fps sim — 110 px/s lands ~4.9 px. A regression outside ~4..6.5 px
	# means the integrator changed and the documented derivation no longer holds. (Whether the SHIPPED
	# knobs keep a kick inside the cap is test_shipped_kicks_land_unclipped_and_dip_inside_the_sway_cap.)
	var s = SWAY.new()
	s.impulse(Vector2(0.0, 110.0))
	var peak := 0.0
	for i in 120:
		peak = maxf(peak, s.step(Vector2.ZERO, STIFFNESS, DAMPING, DT).y)
	assert_between(peak, 4.0, 6.5, "a full-slam landing dips ~5 px — subtle is the contract (hud_sway_max ethos)")
	s = null

func test_kick_scaled_caps_before_scaling() -> void:
	# The ORDER is the contract: cap the AUTHORED kick first, then apply the accessibility scale — so
	# 50% sway halves the capped kick (75), not the raw one (100). Scale-then-cap would make the dial
	# do nothing until it dropped below cap/raw, a dead zone on the player's slider.
	var over := Vector2(0.0, 200.0)  # authored hotter than the 150 cap
	assert_almost_eq(SWAY.kick_scaled(over, 150.0, 1.0).y, 150.0, 0.001,
		"an over-authored kick parks at the cap")
	assert_almost_eq(SWAY.kick_scaled(over, 150.0, 0.5).y, 75.0, 0.001,
		"50% accessibility sway halves the CAPPED kick — cap first, scale second")
	assert_eq(SWAY.kick_scaled(over, 150.0, 0.0), Vector2.ZERO,
		"sway scale 0 silences the impact channel entirely")
	assert_almost_eq(SWAY.kick_scaled(over, 150.0, 7.0).y, 150.0, 0.001,
		"a wild scale clamps to 1 — kick_scaled is safe against a bad caller")
	assert_eq(SWAY.kick_scaled(over, -5.0, 1.0), Vector2.ZERO,
		"a negative cap degrades to zero, never to a sign flip")

func test_land_kick_maps_intensity_linearly_and_floors_at_zero() -> void:
	assert_eq(SWAY.land_kick(1.0, 65.0), Vector2(0.0, 65.0),
		"a full-intensity landing kicks the full authored px/s, straight down")
	assert_eq(SWAY.land_kick(0.25, 65.0), Vector2(0.0, 16.25),
		"a soft hop kicks linearly less — the panel nods instead of slamming")
	assert_eq(SWAY.land_kick(0.0, 65.0), Vector2.ZERO, "zero intensity = no kick")
	assert_eq(SWAY.land_kick(-0.5, 65.0), Vector2.ZERO,
		"negative intensity floors at zero (a bad caller can't kick the panel UP)")

func test_shipped_kicks_land_unclipped_and_dip_inside_the_sway_cap() -> void:
	# hud_kick_max is documented as the impulse-channel twin of hud_sway_max: whatever the source or tuning, the
	# hottest kick that survives the cap must dip the panel no further than the continuous channel's own cap.
	# And the cap must not eat the ordinary full-slam landing, or the land knob has a dead band above it.
	var h: HudSettings = GameSettings.hud
	var landing: Vector2 = SWAY.land_kick(1.0, h.hud_land_kick)
	assert_gt(landing.y, 0.0, "a full-slam landing must kick the panel DOWN — no kick means touchdown has no weight")
	assert_almost_eq(SWAY.kick_scaled(landing, h.hud_kick_max, 1.0).y, landing.y, 0.001,
		"hud_kick_max must sit at or above a full landing kick — a cap below it silently flattens every hard landing")
	var s = SWAY.new()
	s.impulse(SWAY.kick_scaled(Vector2(0.0, 1.0e6), h.hud_kick_max, 1.0))  # the hottest kick any source can land
	var peak := 0.0
	for i in 120:  # 2 s at 60 fps — well past the dip's peak
		peak = maxf(peak, s.step(Vector2.ZERO, h.hud_sway_stiffness, h.hud_sway_damping, DT).y)
	assert_gt(peak, 0.0, "a capped kick must still move the panel")
	assert_lte(peak, h.hud_sway_max,
		"the hottest capped kick must dip the panel no further than hud_sway_max (peak %.2f px) — impacts obey the same subtle cap" % peak)
	s = null

# --- shipped knobs + the accessibility scale ---------------------------------------------------------

func test_shipped_sway_is_subtle_and_settles_with_one_overshoot() -> void:
	# What the "HUD weight" group promises, checked on the LIVE knobs by driving the real spring rather than by
	# pinning numbers: gains trail the turn, the cap stays under the seasick line, and releasing a held flick
	# carries ONE small overshoot (slightly under-damped, the "mass" read) that dies without ringing.
	var h: HudSettings = GameSettings.hud
	assert_gt(h.hud_sway_gain.x, 0.0, "yaw gain must be positive — positive trails the turn; negative makes the panel LEAD it")
	assert_gt(h.hud_sway_gain.y, 0.0, "pitch gain must be positive — positive trails the look")
	assert_gt(h.hud_sway_max, 0.0, "a zero sway cap welds the panel static whatever the player's HUD Sway slider says")
	assert_lte(h.hud_sway_max, SEASICK_PX, "hud_sway_max past ~12 px on the 792x444 canvas reads seasick, not weighty")
	var s = SWAY.new()
	var flick: Vector2 = SWAY.look_target(50.0, 0.0, h.hud_sway_gain, h.hud_sway_max)  # a violent yaw flick, held
	var peak := 0.0
	for i in 60:
		peak = maxf(peak, s.step(flick, h.hud_sway_stiffness, h.hud_sway_damping, DT).length())
	assert_lte(peak, SEASICK_PX,
		"a held flick, overshoot included, must never swing the panel past the seasick line (peak %.2f px)" % peak)
	var overshoot := 0.0  # deepest excursion past home, on the far side from the flick
	var rebound := 0.0    # any swing BACK past home after that overshoot — ringing
	for i in 120:  # the camera stops: 2 s of release
		var x: float = s.step(Vector2.ZERO, h.hud_sway_stiffness, h.hud_sway_damping, DT).x
		if x < 0.0:
			overshoot = minf(overshoot, x)
		elif overshoot < -OVERSHOOT_EPS_PX:
			rebound = maxf(rebound, x)
	assert_lt(overshoot, -OVERSHOOT_EPS_PX,
		"release must carry an overshoot past home (the under-damped 'mass' read) — critically damped knobs ease back with no life")
	assert_lt(rebound, RINGING_PX,
		"...and only ONE: the panel must not swing back past home again (%.3f px) — ringing reads as wobble" % rebound)
	assert_lt(s.offset.length(), 0.1, "the panel comes to rest within 2 s of the camera stopping")
	s = null

func test_settings_hud_sway_scale_default_full_and_clamps() -> void:
	# FULL (1.0) by default — the authored sway ships on; a motion-sensitive player dials the
	# Options -> Accessibility slider down (a SCALE like ps1_warp_intensity, not a bool).
	var fresh = load("res://managers/Settings.gd").new()
	assert_almost_eq(fresh.hud_sway_scale, 1.0, 0.0001, "HUD sway defaults to 100% (full authored weight)")
	fresh.free()
	Settings.set_hud_sway_scale(2.0)
	assert_almost_eq(Settings.hud_sway_scale, 1.0, 0.0001, "scale clamps to 100%")
	Settings.set_hud_sway_scale(-1.0)
	assert_almost_eq(Settings.hud_sway_scale, 0.0, 0.0001, "scale clamps to 0% (sway off, panel welded static)")
	Settings.set_hud_sway_scale(0.4)
	assert_almost_eq(Settings.hud_sway_scale, 0.4, 0.0001, "an in-range scale is stored verbatim")
