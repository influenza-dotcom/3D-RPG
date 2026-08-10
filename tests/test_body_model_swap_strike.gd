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
## Built OFF-TREE (.new() without add_child, so _ready never runs) — no model import, no host, no autoloads.

const SWAP_SCRIPT := preload("res://scripts/components/body_model_swap.gd")

func _swap() -> BodyModelSwap:
	return SWAP_SCRIPT.new() as BodyModelSwap

# --- The NPC no-regression contract -----------------------------------------------------------------

func test_strike_defaults_reproduce_the_original_npc_flail() -> void:
	# Every one of these defaults exists to make the new code path a NO-OP for NPCs. If a default changes,
	# every punching NPC changes with it — which is why they are pinned by value, not by range.
	var s := _swap()
	assert_eq(s.arm_strike_pitch, -120.0, "the NPC flail pitch is the shipped default")
	assert_eq(s.arm_strike_duration, 1.0, "the NPC flail duration is the shipped default")
	assert_null(s.arm_strike_curve, "no curve by default — NPCs keep the legacy smoothstep envelope")
	assert_eq(s.arm_strike_thrust, Vector3.ZERO, "no thrust by default — the NPC flail is rotation-only")
	assert_false(s.arm_strike_alternate, "NPCs punch two-fisted; alternation is opt-in")
	assert_eq(s.arm_strike_offhand_scale, 1.0, "off-hand matches the lead by default — one symmetric flail")
	s.free()

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
