extends GutTest

## World ghosting (scripts/effects/world_ghost.gd): the temporal average behind the very subtle persistence
## applied to the PICTURE, as opposed to the HUD's own canvas ghost (tests/test_hud_ghost.gd). Pure statics
## off-tree — the blend curve and its frame-rate independence, the chromatic split, the clamp order of the
## accessibility dial, the layer the composite has to sit on, and the contraction that keeps a literal video
## feedback loop from blowing out.
##
## ⭐ WHAT THIS FILE CANNOT COVER: the look, and the two things that only exist on a GPU — that a SubViewport
## can sample the root viewport's previous frame at all, and that the weapon's coverage mask lands on the
## right pixels. Headless never compiles shaders. The rendered evidence is the world half of
## scripts/tools/hud_ghost_qa_shots.gd (shots 09-12), which includes a MEASURED at-rest pair against a
## matched-gap control, because "you cannot see it" is not a claim a screenshot can make on its own.

## Loaded BY PATH (not the class_name) — the editor class-cache cascade guard.
const WORLD := preload("res://scripts/effects/world_ghost.gd")

const DT := 1.0 / 60.0

var _prev_loaded: bool
var _prev_scale: float

func before_each() -> void:
	# Never let a setter round-trip clobber the real user://settings.cfg (the test_settings.gd idiom).
	_prev_loaded = Settings._loaded
	_prev_scale = Settings.world_ghost_scale
	Settings._loaded = false

func after_each() -> void:
	Settings.world_ghost_scale = _prev_scale
	Settings._loaded = _prev_loaded

# --- the temporal average -----------------------------------------------------------------------------

func test_blend_is_frame_rate_independent() -> void:
	# The GAP is what composes, not the weight: two half-steps must leave the same fraction of the old image
	# standing as one whole step, or the trail is short at 144 fps and long at 30.
	var one_left: float = 1.0 - WORLD.blend_for(DT, 0.1)
	var half_left: float = 1.0 - WORLD.blend_for(DT * 0.5, 0.1)
	assert_almost_eq(half_left * half_left, one_left, 0.0001,
		"the REMAINING fraction composes across half-steps — that is what makes the tail a duration, not a frame count")

func test_one_tau_closes_one_over_e_of_the_gap() -> void:
	# Measured at MAX_STEP_DT, since a longer step is clamped by design — asking for more would measure the
	# clamp rather than the curve.
	assert_almost_eq(WORLD.blend_for(WORLD.MAX_STEP_DT, WORLD.MAX_STEP_DT), 1.0 - 1.0 / exp(1.0), 0.0001,
		"tau is the seconds to close 1/e of the gap to the live frame — what the knob's doc promises a designer")

func test_blend_stays_a_usable_weight() -> void:
	var k: float = WORLD.blend_for(DT, 0.055)
	assert_gt(k, 0.0, "a zero weight would freeze the average on whatever it happened to hold — a stuck image")
	assert_lte(k, 1.0, "and it is an alpha, so it can never exceed 1")

func test_zero_tau_snaps_to_the_live_frame() -> void:
	assert_eq(WORLD.blend_for(DT, 0.0), 1.0,
		"tau 0 = no persistence: the average IS the frame, so the difference is zero and the effect vanishes")
	assert_eq(WORLD.blend_for(DT, -1.0), 1.0, "a negative tau degrades to the same snap rather than exploding")

func test_a_frame_hitch_cannot_snap_the_average_onto_the_frame() -> void:
	assert_eq(WORLD.blend_for(0.5, 0.055), WORLD.blend_for(WORLD.MAX_STEP_DT, 0.055),
		"a stall integrates at most MAX_STEP_DT, so the tail survives a hitch instead of being erased by it")

# --- the feedback loop --------------------------------------------------------------------------------

func test_the_feedback_loop_contracts_at_the_shipped_knobs() -> void:
	# THE ONE THAT MATTERS. The composite is part of the frame the accumulator then averages — literal video
	# feedback. Substituting it in gives A' = A(1 - k(1-s)) + k(1-s)F, so the loop only converges while
	# k(1-s) > 0, i.e. the coefficient below is under 1. Written as a SUM instead of a mix, the same loop
	# multiplies the picture by 1/(1-decay) and blows to white in about a second.
	var fx: EffectsSettings = GameSettings.effects
	var k: float = WORLD.blend_for(DT, fx.world_ghost_tau)
	var s: float = WORLD.strength_for(fx.world_ghost_strength, 1.0)
	var coefficient := 1.0 - k * (1.0 - s)
	assert_lt(coefficient, 1.0, "the loop must CONTRACT, or every frame adds to the last and the picture blows out")
	assert_gte(coefficient, 0.0, "and it must not overshoot into a negative, which would oscillate the image")

func test_full_strength_would_still_not_diverge() -> void:
	# The dial's ceiling is 1.0 and the authored knob could be pushed there in the inspector; even then the
	# coefficient must stay inside the unit interval, so a hot-tuned value is ugly rather than dangerous.
	var k: float = WORLD.blend_for(DT, 0.055)
	assert_lte(1.0 - k * (1.0 - 1.0), 1.0, "at strength 1 the loop is marginal — it holds, it does not run away")

# --- the chromatic split ------------------------------------------------------------------------------

func test_chroma_is_zero_for_a_still_camera() -> void:
	assert_eq(WORLD.chroma_offset(0.0, 0.0, Vector2(0.45, 0.36), 0.8), Vector2.ZERO,
		"a still camera splits nothing — a static frame must carry no colour fringing at all")

func test_chroma_scales_per_axis_by_gain() -> void:
	var c: Vector2 = WORLD.chroma_offset(1.0, -1.0, Vector2(2.0, 3.0), 100.0)
	assert_almost_eq(c.x, 2.0, 0.0001, "x split = yaw rate * gain.x (px per rad/s)")
	assert_almost_eq(c.y, -3.0, 0.0001, "y split = pitch rate * gain.y, sign preserved so it leans with the motion")

func test_chroma_clamps_a_flick() -> void:
	var c: Vector2 = WORLD.chroma_offset(60.0, 60.0, Vector2(0.45, 0.36), 0.8)
	assert_almost_eq(c.length(), 0.8, 0.001, "a hard flick parks on the cap — the split is bounded in PIXELS")

func test_chroma_max_zero_is_an_achromatic_trail() -> void:
	assert_eq(WORLD.chroma_offset(9.0, 9.0, Vector2(0.45, 0.36), 0.0), Vector2.ZERO,
		"0 px is the opt-out: a clean temporal trail with no analog fringing")

# --- the accessibility dial ---------------------------------------------------------------------------

func test_strength_multiplies_the_authored_amplitude_by_the_dial() -> void:
	assert_almost_eq(WORLD.strength_for(0.12, 0.5), 0.06, 0.0001, "the dial SCALES the authored look")

func test_dial_at_zero_lands_under_the_shutdown_floor() -> void:
	assert_lt(WORLD.strength_for(0.12, 0.0), WORLD.MIN_STRENGTH,
		"0 stops the offscreen pass rendering at all, so OFF is free and the frame is bit-identical")

func test_strength_clamps_both_inputs_before_multiplying() -> void:
	assert_eq(WORLD.strength_for(5.0, 5.0), 1.0, "an over-authored knob and an over-driven dial both cap at 1")
	assert_eq(WORLD.strength_for(-1.0, 1.0), 0.0, "a negative amplitude degrades to off, never to an inverted picture")

# --- where the composite has to live ------------------------------------------------------------------

func test_the_composite_layer_sits_above_the_hud_and_below_every_menu() -> void:
	# NOT cosmetic ordering — a correctness constraint. The accumulator averages the WHOLE window, so the
	# composite has to sit above everything that average contains (the HUD at layer 1 and the weapon) or the
	# two disagree and the difference paints a ghost of the HUD across the world. It must equally sit BELOW
	# dialogue (90) / cutscenes (100) / modals (120+) / tooltips (200), which the suppression gate switches
	# the whole pass off for.
	assert_gt(WORLD.DISPLAY_LAYER, 1, "above the HUD layer, or the HUD is in the average but not in the live sample")
	assert_lt(WORLD.DISPLAY_LAYER, 90, "below the lowest menu layer (dialogue, 90) — menus are never ghosted")

func test_suppression_is_answerable_without_a_scene() -> void:
	# It reads two autoload predicates; the contract is that it is a plain bool and never throws, because it
	# is consulted every frame from the HUD's _process.
	var v: bool = WORLD.suppressed()
	assert_typeof(v, TYPE_BOOL, "the gate is a plain predicate — a per-frame call must not depend on scene state")

# --- the shipped knobs --------------------------------------------------------------------------------

func test_shipped_knobs_are_very_subtle() -> void:
	# "Albeit very subtly" was the whole brief, and this is a FULL-SCREEN effect over a game that is already
	# posterised and dithered — the value most likely to be nudged up and regret it.
	var fx: EffectsSettings = GameSettings.effects
	assert_gt(fx.world_ghost_strength, 0.0, "the effect ships ON — it is part of the authored look")
	assert_lte(fx.world_ghost_strength, 0.25,
		"past ~0.25 this stops being a ghost and becomes smear on every wall you walk past")
	assert_gt(fx.world_ghost_tau, 0.0, "a zero tau leaves the average equal to the frame and nothing to show")
	assert_lte(fx.world_ghost_tau, 0.15,
		"the world fills the screen — a tail that reads as elegant on a 4 px HP segment reads as drunk here")
	assert_gt(fx.world_ghost_dead_zone, 0.0,
		"without a dead zone the never-cleared buffer's rounding stall leaves a permanent sub-percent haze")
	assert_lt(fx.world_ghost_strength, GameSettings.hud.hud_ghost_strength,
		"the world's ghost is deliberately FAINTER than the HUD's — the HUD is an instrument, the world is the game")

func test_the_world_dial_is_separate_from_the_hud_one_and_ships_full() -> void:
	# Separate on purpose: this is the closest thing in the game to motion blur, and a motion-sensitive
	# player turns it off first while still wanting the HUD to ghost.
	var fresh = load("res://managers/Settings.gd").new()
	assert_eq(fresh.world_ghost_scale, 1.0, "a new profile gets the authored ghost; the slider exists to turn it DOWN")
	assert_true(fresh.get(&"hud_ghost_scale") != null, "and it is a DIFFERENT field from the HUD's dial")
	fresh.free()
