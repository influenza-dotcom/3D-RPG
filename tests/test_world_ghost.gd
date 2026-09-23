extends GutTest

## World ghosting (scripts/effects/world_ghost.gd): the temporal average behind the very subtle persistence
## applied to the PICTURE, as opposed to the HUD's own canvas ghost (tests/test_hud_ghost.gd). Mostly pure statics
## off-tree — the blend curve and its frame-rate independence, the chromatic split, the clamp order of the
## accessibility dial, the layer the composite has to sit on, and the contraction that keeps a literal video
## feedback loop from blowing out for ANY knob value. Two tests drive live state: the suppression gate, with each
## screen owner (conversation, name entry, cutscene) seated on its autoload and restored in after_each, and a
## built pass polled in-tree to prove the WORLD dial, not the HUD's, switches it on and off.
##
## ⭐ WHAT THIS FILE CANNOT COVER: the look, and the two things that only exist on a GPU — that a SubViewport
## can sample the root viewport's previous frame at all, and that the weapon's coverage mask lands on the
## right pixels. Headless never compiles shaders. The rendered evidence is the world half of
## scripts/tools/probes/hud_ghost_qa_shots.gd (shots 09-12), which includes a MEASURED at-rest pair against a
## matched-gap control, because "you cannot see it" is not a claim a screenshot can make on its own.

## Loaded BY PATH (not the class_name) — the editor class-cache cascade guard.
const WORLD := preload("res://scripts/effects/world_ghost.gd")

const DT := 1.0 / 60.0

var _prev_loaded: bool
var _prev_scale: float
var _prev_hud_scale: float
var _prev_dialogue: DialogueResource
var _prev_name_entry_open: bool
var _prev_cutscene_active: bool

func before_each() -> void:
	# Never let a setter round-trip clobber the real user://settings.cfg (the test_settings.gd idiom).
	_prev_loaded = Settings._loaded
	_prev_scale = Settings.world_ghost_scale
	_prev_hud_scale = Settings.hud_ghost_scale
	Settings._loaded = false
	# The suppression gate reads three pieces of live autoload state; the gate tests seat each one directly.
	_prev_dialogue = DialogueManager._active
	_prev_name_entry_open = NameEntryDialog._is_open
	_prev_cutscene_active = CutscenePlayer._active

func after_each() -> void:
	Settings.world_ghost_scale = _prev_scale
	Settings.hud_ghost_scale = _prev_hud_scale
	Settings._loaded = _prev_loaded
	DialogueManager._active = _prev_dialogue
	NameEntryDialog._is_open = _prev_name_entry_open
	CutscenePlayer._active = _prev_cutscene_active

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
	# feedback. It converges only because the feed MIXES the finished frame into the buffer at a partial weight k:
	# substituting the composite in gives A' = A(1 - k(1-s)) + k(1-s)F, a contraction while that coefficient is
	# under 1. Drawn as a SUM instead (an additive feed), the same loop multiplies the picture by 1/(1-decay) and
	# blows to white in about a second; at a full weight it REPLACES the buffer each frame and leaves no trail.
	# Driven through build() + poll() at the shipped knobs, so the blend, the weight and the strength checked are
	# the ones the running pass actually set up — the algebra only holds because the blend is asserted a MIX.
	DialogueManager._active = null
	NameEntryDialog._is_open = false
	CutscenePlayer._active = false
	Settings.world_ghost_scale = 1.0
	var host := CanvasLayer.new()
	add_child_autofree(host)
	var ghost = WORLD.new()
	host.add_child(ghost)
	if not ghost.build(host):
		pending("no render size to build the accumulator at — build() degrades to a no-op and there is no loop to check")
		return
	for i in WORLD.WARMUP_FRAMES + 1:
		ghost.poll(DT, 0.0, 0.0)
	assert_true(ghost._display.visible, "setup: past warm-up the composite is live, so the feed below is the running one")
	var feed: TextureRect = ghost._feed
	var feed_mat := feed.material as CanvasItemMaterial
	assert_true(feed.material == null or (feed_mat != null and feed_mat.blend_mode == CanvasItemMaterial.BLEND_MODE_MIX),
		"the feed must draw the finished frame with MIX blending — an additive feed is the SUM that blows the picture out")
	var k: float = feed.modulate.a
	assert_gt(k, 0.0, "the frame is mixed in at a weight above 0, or the average freezes on a stale picture")
	assert_lt(k, 1.0, "…and below 1 at the shipped tau, or the feed replaces the buffer every frame and there is no trail")
	var s: float = ghost._mat.get_shader_parameter(&"strength")
	var coefficient := 1.0 - k * (1.0 - s)
	assert_lt(coefficient, 1.0, "the loop must CONTRACT, or every frame adds to the last and the picture blows out")
	assert_gte(coefficient, 0.0, "and it must not overshoot into a negative, which would oscillate the image")

func test_no_knob_setting_can_make_the_feedback_loop_diverge() -> void:
	# The shipped knobs are one point; a designer can type anything into the inspector and the player dial can be
	# fed anything by a hand-edited settings.cfg. For every frame step and tau, over-authored, over-driven and
	# negative inputs, the per-frame coefficient must stay inside [0, 1]: a hot-tuned value may look ugly, but it
	# must never blow the picture out (> 1) or oscillate it (< 0).
	var bad: PackedStringArray = []
	for tau: float in [-1.0, 0.0, 0.0005, 0.055, 0.15, 3.0]:
		for dt: float in [1.0 / 240.0, DT, WORLD.MAX_STEP_DT, 0.5]:
			var k: float = WORLD.blend_for(dt, tau)
			for pair: Array in [[1.0, 1.0], [5.0, 1.0], [1.0, 5.0], [5.0, 5.0], [-1.0, 1.0], [0.12, -3.0], [0.12, 0.5]]:
				var s: float = WORLD.strength_for(pair[0], pair[1])
				var coefficient := 1.0 - k * (1.0 - s)
				if coefficient > 1.0 or coefficient < 0.0:
					bad.append("tau=%s dt=%s authored=%s dial=%s -> %s" % [tau, dt, pair[0], pair[1], coefficient])
	assert_eq(bad.size(), 0, "the ghost's video-feedback loop left the unit interval (blow-out or oscillation): %s" % [bad])

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
	# The cases that tell the ORDER apart: clamping the product instead would answer 1.0 for both.
	assert_almost_eq(WORLD.strength_for(2.0, 0.5), 0.5, 0.0001,
		"an over-authored knob caps at 1 BEFORE the dial scales it, so half the dial is still half the effect for a motion-sensitive player")
	assert_almost_eq(WORLD.strength_for(0.5, 2.0), 0.5, 0.0001,
		"an over-driven dial caps at 1 BEFORE multiplying, so it can never amplify the ghost past the authored look")
	assert_eq(WORLD.strength_for(0.5, -1.0), 0.0, "a negative dial is off, never an inverted picture")

# --- where the composite has to live ------------------------------------------------------------------

func test_the_composite_layer_sits_above_the_hud_and_below_every_menu() -> void:
	# NOT cosmetic ordering — a correctness constraint. The accumulator averages the WHOLE window, so the
	# composite has to sit above everything that average contains (the HUD at layer 1 and the weapon) or the
	# two disagree and the difference paints a ghost of the HUD across the world. It must equally sit BELOW
	# dialogue (90) / cutscenes (100) / modals (120+) / tooltips (200), which the suppression gate switches
	# the whole pass off for.
	assert_gt(WORLD.DISPLAY_LAYER, 1, "above the HUD layer, or the HUD is in the average but not in the live sample")
	# The dialogue box is the lowest menu layer; read it off a real DialogueView rather than restating 90.
	var view := DialogueView.new()
	add_child_autofree(view)
	view.open()
	assert_lt(WORLD.DISPLAY_LAYER, view._layer.layer,
		"below the dialogue box's live layer (the lowest menu) — a menu drawn under the composite would be ghosted into the world")

func test_a_conversation_a_cutscene_or_a_modal_each_switch_the_pass_off() -> void:
	# The accumulator averages the WHOLE window, so anything drawn above the composite ghosts itself across the
	# world unless the pass is off. Each owner of the screen must trip the gate on its own: a conversation is
	# not a modal (world_frozen), a name-entry prompt is not a conversation (gameplay_suppressed).
	DialogueManager._active = null
	NameEntryDialog._is_open = false
	CutscenePlayer._active = false
	assert_false(WORLD.suppressed(), "setup: with nothing owning the screen the world ghost runs during gameplay")
	DialogueManager._active = DialogueResource.new()
	assert_true(WORLD.suppressed(), "a live conversation switches the world ghost off (the dialogue box sits above the composite)")
	DialogueManager._active = null
	NameEntryDialog._is_open = true
	assert_true(WORLD.suppressed(), "an open name-entry prompt switches the world ghost off")
	NameEntryDialog._is_open = false
	CutscenePlayer._active = true
	assert_true(WORLD.suppressed(), "a playing cutscene switches the world ghost off (its fade and captions sit above the composite)")
	CutscenePlayer._active = false
	assert_false(WORLD.suppressed(), "and the gate reopens once the screen is handed back to gameplay")

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

func test_the_world_dial_ships_full_on_a_new_profile() -> void:
	# SHIP DECISION: the world ghost is part of the authored look, on at full strength for a new profile; the
	# accessibility slider exists to turn it DOWN. A bare instance, not the autoload, which has already loaded
	# this machine's settings.cfg.
	var fresh = load("res://managers/Settings.gd").new()
	assert_eq(fresh.world_ghost_scale, 1.0, "ship decision: a new profile gets the full authored world ghost; the slider only turns it down")
	fresh.free()

func test_the_world_pass_obeys_its_own_dial_not_the_huds() -> void:
	# Separate on purpose: this is the closest thing in the game to motion blur, and a motion-sensitive player
	# turns it off first while still wanting the HUD to ghost. Driven through build() + poll(), the per-frame
	# consumer, so the dial that actually gates the pass is the one under test.
	var fx: EffectsSettings = GameSettings.effects
	assert_gt(WORLD.strength_for(fx.world_ghost_strength, 1.0), WORLD.MIN_STRENGTH,
		"setup: the shipped world ghost is strong enough to run at full dial")
	DialogueManager._active = null
	NameEntryDialog._is_open = false
	CutscenePlayer._active = false
	assert_false(WORLD.suppressed(), "setup: nothing owns the screen, so only the dials decide")
	var host := CanvasLayer.new()
	add_child_autofree(host)
	var ghost = WORLD.new()
	host.add_child(ghost)
	if not ghost.build(host):
		pending("no render size to build the accumulator at — build() degrades to a no-op and there is no pass to gate")
		return
	# HUD dial OFF, world dial ON: the world pass must run.
	Settings.hud_ghost_scale = 0.0
	Settings.world_ghost_scale = 1.0
	for i in WORLD.WARMUP_FRAMES + 1:
		ghost.poll(DT, 0.0, 0.0)
	assert_true(ghost._display.visible,
		"turning the HUD ghost off must not take the world ghost with it — the composite shows once warm-up is over")
	assert_eq(ghost._accum.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "and the accumulator keeps rendering")
	# World dial OFF, HUD dial ON: the world pass must stop, and stop costing a render.
	Settings.hud_ghost_scale = 1.0
	Settings.world_ghost_scale = 0.0
	ghost.poll(DT, 0.0, 0.0)
	assert_false(ghost._display.visible, "the world dial at 0 hides the composite even while the HUD ghost is on full")
	assert_eq(ghost._accum.render_target_update_mode, SubViewport.UPDATE_DISABLED,
		"and OFF is free: the accumulator stops rendering, so a player who turned it off pays nothing for it")
