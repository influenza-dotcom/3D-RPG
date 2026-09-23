extends GutTest

## Contract tests for the fist-strike envelope on BodyModelSwap — shared by the NPC punch
## (scripts/npc/npc_combat.gd) and the PLAYER's unarmed view-model hands (GunMesh.fire -> strike()).
##
## The strike gained four authored knobs (curve / thrust / alternate / off-hand scale) and a second write
## path so an `animate_arms = false` rig can punch WITHOUT switching on the walk swing. Both of those are
## easy to regress invisibly, in opposite directions:
##
##   1. Change a DEFAULT and every NPC punch in the game silently changes shape, because NPCs take the
##      original animated path and rely on those defaults reproducing the old single symmetric flail.
##   2. Re-gate the strike behind `animate_arms` and the player's hands go dead again, with no error.
##
## Built OFF-TREE (.new() without add_child, so _ready never runs) — no model import. The pose tests hang the swap
## under a bare Node3D host with Node3D arm stubs and drive _animate_limbs directly, so the NPC contract is checked
## on the arms it actually writes rather than on the export defaults.

const SWAP_SCRIPT := preload("res://scripts/components/body_model_swap.gd")

func _swap() -> BodyModelSwap:
	return SWAP_SCRIPT.new() as BodyModelSwap

# --- The NPC no-regression contract -----------------------------------------------------------------

## A DEFAULT-tuned swap (every strike knob left alone, which is what enemy.tscn ships) wearing the shipped NPC arm
## placement from enemy.tscn, parented under `host` (a bare Node3D unless the test needs a gun) and given two bare
## Node3D arm stubs — all _animate_limbs needs off-tree. Never an NPC (CLAUDE.md), never in the tree.
func _npc_rig(host: Node3D) -> BodyModelSwap:
	var s := _swap()
	s.arm_scale = 0.35
	s.arm_position = Vector3(-0.27, 0.155, -0.05)
	s.arm_rotation = Vector3(90, 0, 0)
	host.add_child(s)
	for side in ["_arm_left", "_arm_right"]:
		var stub := Node3D.new()
		s.add_child(stub)
		s.set(side, stub)
	return s


## Where the arm's HAND points from its shoulder (the arm model's hand lies down its local +Z).
func _hand_dir(arm: Node3D) -> Vector3:
	return (arm.transform.basis * Vector3(0, 0, 1)).normalized()


## A host whose gun is drawn, so the swap raises the arms onto its hold pose (duck-typed by name).
class _ArmedHost extends Node3D:
	func is_holding_gun() -> bool:
		return true


func test_a_default_rig_throws_one_mirrored_rotation_only_flail_up_toward_the_target() -> void:
	# The NPC no-regression contract, observed on the POSE rather than read off the defaults: every NPC punch is
	# a TWO-FISTED symmetric swing (both arms move as mirror images), ROTATION-ONLY (the shoulders never leave
	# their sockets), thrown UP and toward the side the NPC points its gun (its target) — the whole authored
	# strike pitch at the instant of the punch. A default retuned in the script (off-hand scale, thrust, curve,
	# sign of the pitch) or a strike branch that breaks the mirror silently re-shapes every punching NPC.
	var host := Node3D.new()
	var s := _npc_rig(host)
	var left: Node3D = s._arm_left
	var right: Node3D = s._arm_right
	s._animate_limbs(0.016, false)
	var rest_left := left.transform
	var rest_dir := _hand_dir(left)
	s.strike()
	s._animate_limbs(0.001, false)
	for p in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)]:
		var l: Vector3 = left.transform * p
		var r: Vector3 = right.transform * p
		assert_almost_eq(r.distance_to(Vector3(-l.x, l.y, l.z)), 0.0, 0.0001,
			"the right fist mid-punch must be the exact mirror of the left (probe %s) — one two-fisted flail, not a lead and a lagging off-hand" % p)
	assert_almost_eq(left.transform.origin.distance_to(rest_left.origin), 0.0, 0.0001,
		"the NPC flail is rotation-only: the shoulder stays exactly where it rests while the fist swings")
	var strike_dir := _hand_dir(left)
	assert_almost_eq(rad_to_deg(rest_dir.angle_to(strike_dir)), absf(s.arm_strike_pitch), 0.5,
		"on the frame of the punch the arm has already swung through the whole arm_strike_pitch (no wind-up without a curve)")
	assert_gt(strike_dir.y, rest_dir.y, "the flail swings the fist UP from its hang")
	var armed := _ArmedHost.new()
	var gun_rig := _npc_rig(armed)
	gun_rig._animate_limbs(10.0, false)  # one long frame settles the eased hold pose
	var hold_dir := _hand_dir(gun_rig._arm_left)
	assert_gt(strike_dir.z * hold_dir.z, 0.0,
		"the punch lands on the same side the NPC holds its gun (its target) — never thrown backward over its shoulder")
	host.free()
	armed.free()


func test_a_default_rig_eases_the_flail_home_over_arm_strike_duration() -> void:
	# The legacy envelope an NPC punch rides with no curve authored: strongest the instant it is thrown, then
	# shrinking every frame, still moving three quarters of the way through arm_strike_duration and back on the
	# EXACT rest pose once the duration has elapsed (a residue would leave every NPC's arms a little raised).
	var host := Node3D.new()
	var s := _npc_rig(host)
	var left: Node3D = s._arm_left
	s._animate_limbs(0.016, false)
	var rest := left.transform
	var rest_dir := _hand_dir(left)
	s.strike()
	var swing := []
	var step := s.arm_strike_duration * 0.25
	s._animate_limbs(0.001, false)
	swing.append(rad_to_deg(rest_dir.angle_to(_hand_dir(left))))
	for i in 3:
		s._animate_limbs(step, false)
		swing.append(rad_to_deg(rest_dir.angle_to(_hand_dir(left))))
	for i in range(1, swing.size()):
		assert_lt(swing[i], swing[i - 1],
			"the flail must shrink as it recovers (sample %d: %.2f deg after %.2f deg) — full on the punch, easing home" % [i, swing[i], swing[i - 1]])
	assert_gt(swing[swing.size() - 1], 0.0, "three quarters through arm_strike_duration the arm is still on its way home")
	s._animate_limbs(step, false)
	assert_true(left.transform.is_equal_approx(rest),
		"once arm_strike_duration has elapsed the arm is back on its exact rest pose (got %s, rest %s)" % [left.transform, rest])
	host.free()

func test_the_legacy_envelope_is_unchanged_without_a_curve() -> void:
	# strike_amplitude(t, null) must be exactly the old `smoothstep(0.0, 1.0, _strike_t)` expression.
	assert_almost_eq(SWAP_SCRIPT.strike_amplitude(1.0, null), 1.0, 0.0001,
		"full amplitude at the instant of the punch — the legacy shape has no wind-up")
	assert_almost_eq(SWAP_SCRIPT.strike_amplitude(0.0, null), 0.0, 0.0001,
		"zero at full recovery, so the last frame lands exactly on the rest pose")
	assert_almost_eq(SWAP_SCRIPT.strike_amplitude(0.5, null), 0.5, 0.0001,
		"smoothstep is symmetric about its midpoint")

func test_strike_still_takes_no_arguments() -> void:
	# npc_combat.gd calls it duck-typed by name. Adding a required parameter would break that silently.
	var s := _swap()
	assert_true(s.has_method("strike"), "strike() is the shared entry point for both callers")
	s.strike()  # must not error with zero args
	s.free()

# --- The authored-curve envelope --------------------------------------------------------------------

func test_a_curve_is_sampled_on_ELAPSED_time_not_remaining() -> void:
	# The envelope counts DOWN (1 at the punch, 0 at rest) but a designer authors a curve left-to-right in
	# time. If this inverts, every authored punch plays backwards — recovery first, snap last.
	var c := Curve.new()
	c.min_value = 0.0
	c.max_value = 1.0
	c.add_point(Vector2(0.0, 0.0))  # x=0 is the INSTANT of the punch
	c.add_point(Vector2(1.0, 1.0))  # x=1 is fully recovered
	assert_almost_eq(SWAP_SCRIPT.strike_amplitude(1.0, c), 0.0, 0.02,
		"t=1 is the moment of the punch, so it must sample the curve's LEFT edge (x=0)")
	assert_almost_eq(SWAP_SCRIPT.strike_amplitude(0.0, c), 1.0, 0.02,
		"t=0 is full recovery, so it must sample the curve's RIGHT edge (x=1)")
	c = null

func test_the_shipped_punch_curve_has_a_real_wind_up_and_returns_home() -> void:
	# The whole reason a curve exists: the legacy shape is at FULL amplitude on frame one, which reads as a
	# follow-through rather than a punch. The authored curve must pull back first and settle to exactly rest.
	var c := load("res://resources/tuning/punch_strike_curve.tres") as Curve
	assert_not_null(c, "resources/tuning/punch_strike_curve.tres must load as a Curve")
	assert_lt(SWAP_SCRIPT.strike_amplitude(1.0, c), 0.0,
		"the punch must ANTICIPATE — a negative amplitude at t=1 pulls the fist back before it throws")
	assert_almost_eq(SWAP_SCRIPT.strike_amplitude(0.0, c), 0.0, 0.02,
		"the punch must end exactly at rest, or the hands drift a little further out on every swing")
	c = null

func test_the_shipped_punch_curve_throws_forward_far_further_than_it_pulls_back() -> void:
	# The trap this pins (shipped 2026-08-08, "the fists vibrate when punching"): the authored curve had
	# drifted NET-NEGATIVE — it peaked at +0.064 and dipped to -0.22 twice, so the "punch" was a
	# back-forward-back wobble that spent most of its 0.32 s pulling the fists AWAY from the lens. The
	# knobs it scales (fp_arm_punch_thrust / _pitch) then get cranked to make that 6% peak visible, which
	# multiplies the much larger NEGATIVE lobes too: at the shipped thrust the lead fist swept 1.42 m and
	# left the frame entirely, twice per punch.
	#
	# So a wind-up alone is not the contract — the throw has to DOMINATE it. Sampled on ELAPSED fraction,
	# which is how BodyModelSwap reads the curve.
	var c := load("res://resources/tuning/punch_strike_curve.tres") as Curve
	var peak := -INF
	var dip := INF
	for i in 101:
		var amp: float = c.sample_baked(float(i) / 100.0)
		peak = maxf(peak, amp)
		dip = minf(dip, amp)
	assert_gt(peak, 0.8,
		"the punch must actually THROW — the curve has to reach ~1, or the thrust/pitch knobs get scaled up to compensate")
	assert_lt(absf(dip), peak * 0.5,
		"the anticipation pull-back must stay well under the throw — a curve that pulls back further than it punches reads as a vibration, not a swing")
	c = null

# --- Alternation ------------------------------------------------------------------------------------

func test_alternation_is_opt_in_and_actually_alternates() -> void:
	var s := _swap()
	var start: float = s._strike_side
	s.strike()
	assert_eq(s._strike_side, start, "with alternation OFF the lead fist never changes (NPC two-fisted flail)")
	s.arm_strike_alternate = true
	s.strike()
	var after_one: float = s._strike_side
	assert_ne(after_one, start, "with alternation ON the lead fist swaps each punch")
	s.strike()
	assert_eq(s._strike_side, start, "and swaps back on the next — left, right, left")
	s.free()

func test_a_strike_arms_the_envelope() -> void:
	var s := _swap()
	assert_eq(s._strike_t, 0.0, "a fresh rig is at rest")
	s.strike()
	assert_almost_eq(s._strike_t, 1.0, 0.0001, "strike() arms the envelope at full")
	s.free()
