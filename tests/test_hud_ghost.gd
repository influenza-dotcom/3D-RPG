extends GutTest

## HUD ghosting (scripts/ui/hud_ghost.gd): the maths and the masks behind the CRT phosphor persistence that
## sits behind the HUD. Mostly pure statics off-tree — the decay curve and its frame-rate independence, the
## latency lag, the clamp order of the accessibility dial, and the two visibility-layer bits the capture is
## built on — plus one in-tree pair at the bottom that pins WHERE the display rect is seated in the layer's
## draw order, because that seat is the one thing here a static assertion cannot reach and it has broken once.
##
## ⭐ WHAT THIS FILE CANNOT COVER: the look. Headless never compiles shaders, so both canvas shaders in the
## component load clean whatever they contain, and no assertion can see a trail anyway. The rendered evidence
## is scripts/tools/hud_ghost_qa_shots.gd — a WINDOWED run that shoots the effect off / at rest / mid-turn /
## with each half isolated / overdriven / after the tail should have expired. Change the feel, re-shoot it.

## Loaded BY PATH (not the class_name) — the editor class-cache cascade guard.
const GHOST := preload("res://scripts/ui/hud_ghost.gd")

const DT := 1.0 / 60.0

var _prev_loaded: bool
var _prev_scale: float

func before_each() -> void:
	# Never let a setter round-trip clobber the real user://settings.cfg (the test_settings.gd idiom).
	_prev_loaded = Settings._loaded
	_prev_scale = Settings.hud_ghost_scale
	Settings._loaded = false

func after_each() -> void:
	Settings.hud_ghost_scale = _prev_scale
	Settings._loaded = _prev_loaded

# --- the two capture bits -----------------------------------------------------------------------------

func test_the_capture_and_optout_bits_do_not_overlap() -> void:
	# THE load-bearing invariant. The accumulator's cull mask is CAPTURED_LAYER alone, so an item parked on
	# UNCAPTURED_LAYER must share no bit with it or the opt-out silently does nothing; the WINDOW's mask is
	# every bit, which is why that same item still renders on screen.
	assert_eq(GHOST.CAPTURED_LAYER & GHOST.UNCAPTURED_LAYER, 0,
		"an opted-out HUD element must share no visibility bit with the ghost capture, or it keeps feeding it")
	assert_gt(GHOST.CAPTURED_LAYER, 0, "the capture bit must be a real layer, not 0 (which renders nowhere)")
	assert_gt(GHOST.UNCAPTURED_LAYER, 0, "the opt-out bit must be a real layer — 0 would hide the node outright")

func test_a_fresh_canvasitem_is_captured_by_default() -> void:
	# This is why nothing has to opt IN: a toast, a rebuilt HP segment or a new minimap glyph created at
	# runtime ghosts for free. If Godot ever changed the default, every runtime-built HUD child would go
	# silently un-ghosted — a drift no rendered shot of a static HUD would catch.
	var fresh := ColorRect.new()
	assert_eq(fresh.visibility_layer, GHOST.CAPTURED_LAYER,
		"CanvasItem.visibility_layer defaults to the capture bit — the ghost is opt-OUT, never opt-in")
	fresh.free()

func test_set_ghosted_moves_an_item_between_the_two_bits() -> void:
	var item := ColorRect.new()
	GHOST.set_ghosted(item, false)
	assert_eq(item.visibility_layer, GHOST.UNCAPTURED_LAYER, "opted out = window only, off the capture bit")
	GHOST.set_ghosted(item, true)
	assert_eq(item.visibility_layer, GHOST.CAPTURED_LAYER, "opted back in = the default capture bit")
	item.free()

func test_set_ghosted_is_null_safe() -> void:
	# Callers flag optional overlays (a scope rect, an untyped drop-in) without guarding each one.
	GHOST.set_ghosted(null, false)
	assert_true(true, "flagging a missing overlay is a no-op, not a crash")

# --- persistence decay --------------------------------------------------------------------------------

func test_decay_is_frame_rate_independent() -> void:
	# THE reason the decay is exp(-dt/tau) and not a per-frame constant: two half-frames must leave the
	# buffer exactly where one whole frame would, or the tail is short at 144 fps and long at 30.
	var one: float = GHOST.decay_for(DT, 0.1)
	var half: float = GHOST.decay_for(DT * 0.5, 0.1)
	assert_almost_eq(half * half, one, 0.0001,
		"two half-steps compose to one full step — the tail is the same LENGTH at any frame rate")

func test_decay_of_one_tau_is_one_over_e() -> void:
	# Measured at MAX_STEP_DT, because a step longer than that is clamped by design (see the hitch test) —
	# asking for a whole 0.1 s frame here would be measuring the clamp, not the curve.
	assert_almost_eq(GHOST.decay_for(GHOST.MAX_STEP_DT, GHOST.MAX_STEP_DT), 1.0 / exp(1.0), 0.0001,
		"tau is the seconds to lose 1/e of the buffer — that is what the knob's doc promises a designer")

func test_decay_stays_inside_zero_and_one() -> void:
	assert_lt(GHOST.decay_for(DT, 0.1), 1.0, "a decay of 1 would never fade — the buffer would only ever fill")
	assert_gt(GHOST.decay_for(DT, 0.1), 0.0, "a decay of 0 wipes the buffer every frame — no persistence at all")

func test_zero_tau_wipes_the_buffer_every_frame() -> void:
	assert_eq(GHOST.decay_for(DT, 0.0), 0.0, "tau 0 means no persistence: multiply the buffer out entirely")
	assert_eq(GHOST.decay_for(DT, -1.0), 0.0, "a negative tau degrades to the same wipe rather than exploding")

func test_a_frame_hitch_cannot_wipe_the_tail() -> void:
	# A half-second stall fed straight into exp() would clear the buffer in one frame. Clamping dt just means
	# the tail survives the stall, which nobody can see.
	assert_eq(GHOST.decay_for(0.5, 0.1), GHOST.decay_for(GHOST.MAX_STEP_DT, 0.1),
		"a hitch integrates at most MAX_STEP_DT — the ghost under-fades after a stall instead of blanking")

# --- latency (the half that puts a tail on the screen-locked reticle) ----------------------------------

func test_drag_target_is_zero_for_a_still_camera() -> void:
	assert_eq(GHOST.drag_target(0.0, 0.0, Vector2(1.7, 1.4), 3.0), Vector2.ZERO,
		"standing still = zero offset = the ghost hides exactly behind the live HUD (the whole subtlety promise)")

func test_drag_target_scales_per_axis_by_gain() -> void:
	var t: Vector2 = GHOST.drag_target(1.0, -1.0, Vector2(2.0, 3.0), 100.0)
	assert_almost_eq(t.x, 2.0, 0.0001, "x offset = yaw rate * gain.x (px per rad/s)")
	assert_almost_eq(t.y, -3.0, 0.0001, "y offset = pitch rate * gain.y, sign preserved so the ghost trails the turn")

func test_drag_target_clamps_a_flick_to_max_px() -> void:
	var t: Vector2 = GHOST.drag_target(80.0, 80.0, Vector2(1.7, 1.4), 3.0)
	assert_almost_eq(t.length(), 3.0, 0.001,
		"a violent flick parks on the max circle — 'subtle' is a hard cap, not a hope about mouse speed")

func test_drag_max_zero_is_persistence_only() -> void:
	assert_eq(GHOST.drag_target(9.0, 9.0, Vector2(1.7, 1.4), 0.0), Vector2.ZERO,
		"drag_max 0 leaves the persistence half running with no offset copy at all — the no-double-vision opt-out")

func test_lag_closes_one_over_e_of_the_gap_per_response() -> void:
	var out: Vector2 = GHOST.lag_step(Vector2.ZERO, Vector2(10.0, 0.0), 0.05, 0.05)
	assert_almost_eq(out.x, 10.0 * (1.0 - 1.0 / exp(1.0)), 0.001,
		"response is the seconds to close 1/e of the gap — the same currency as the persistence tau")

func test_lag_never_overshoots_its_target() -> void:
	# A first-order lag, NOT the panel's under-damped spring: an overshoot here reads as the ghost
	# oscillating around a reticle that is standing perfectly still.
	var cur := Vector2.ZERO
	for i in 400:
		cur = GHOST.lag_step(cur, Vector2(3.0, 0.0), 0.045, DT)
		assert_lte(cur.x, 3.0, "the lag approaches the target from below and never rings past it")
	assert_almost_eq(cur.x, 3.0, 0.001, "and it does arrive — a lag that never converges would smear forever")

func test_lag_returns_home_when_the_turn_stops() -> void:
	var cur := Vector2(3.0, 2.0)
	for i in 400:
		cur = GHOST.lag_step(cur, Vector2.ZERO, 0.045, DT)
	assert_almost_eq(cur.length(), 0.0, 0.001,
		"the offset decays to zero, so a settled HUD has its ghost hidden exactly behind it again")

func test_zero_response_snaps_instead_of_dividing_by_zero() -> void:
	assert_eq(GHOST.lag_step(Vector2.ZERO, Vector2(4.0, 0.0), 0.0, DT), Vector2(4.0, 0.0),
		"response 0 is a legitimate authoring choice (no lag smoothing), not a degenerate one")

# --- the accessibility dial ---------------------------------------------------------------------------

func test_strength_multiplies_the_authored_amplitude_by_the_player_dial() -> void:
	assert_almost_eq(GHOST.strength_for(0.32, 0.5), 0.16, 0.0001,
		"the dial SCALES the authored look rather than replacing it — half sway, half ghost, same idiom")

func test_dial_at_zero_silences_the_effect_below_the_shutdown_floor() -> void:
	assert_eq(GHOST.strength_for(0.32, 0.0), 0.0, "0 on the slider is genuinely off, not merely faint")
	assert_lt(GHOST.strength_for(0.32, 0.0), GHOST.MIN_STRENGTH,
		"and it lands under MIN_STRENGTH, which is what stops the offscreen pass rendering at all — OFF is free")

func test_strength_clamps_both_inputs_before_multiplying() -> void:
	assert_eq(GHOST.strength_for(5.0, 5.0), 1.0, "an over-authored knob and an over-driven dial both cap at 1")
	assert_eq(GHOST.strength_for(-1.0, 1.0), 0.0, "a negative amplitude degrades to off, never to an inverted ghost")
	assert_eq(GHOST.strength_for(1.0, -1.0), 0.0, "a negative dial does the same")

# --- the age ramp (what makes the trail a GRADIENT and not a dimmed copy) ------------------------------

func test_a_null_skin_slot_falls_back_to_the_shipped_ramp() -> void:
	# The MenuSkin rule: an unauthored art slot keeps the shipped look rather than painting nothing.
	assert_not_null(GHOST.gradient_for(null), "a null HudSkin.ghost_gradient must fall back, never blank the ghost")
	var mine := Gradient.new()
	assert_eq(GHOST.gradient_for(mine), mine, "an authored gradient is used verbatim — the artist owns the ramp")
	mine = null

func test_the_shipped_ramp_spans_the_whole_age_range() -> void:
	# The shader samples it at UV.x = the trail pixel's age, 0..1. A ramp that stopped short would clamp,
	# so the oldest or freshest slice of every tail would flat-fill one colour.
	var g := GHOST.default_gradient()
	assert_gte(g.offsets.size(), 3, "a two-stop ramp is a tint; the point of the feature is a hue TRAVEL")
	assert_almost_eq(g.offsets[0], 0.0, 0.0001, "offset 0 = the oldest trail pixel, about to vanish")
	assert_almost_eq(g.offsets[g.offsets.size() - 1], 1.0, 0.0001, "offset 1 = the freshest, just off the HUD")

func test_the_ramp_actually_travels_in_HUE() -> void:
	# The whole ask was "a colour gradient, not a more transparent version of the thing it is ghosting".
	# Two ends that differ only in brightness would satisfy every other assertion here and still fail that.
	var g := GHOST.default_gradient()
	var fresh: Color = g.sample(1.0)
	var old: Color = g.sample(0.0)
	assert_gt(absf(fresh.h - old.h), 0.15,
		"the fresh and oldest ends must differ in HUE, not merely in value — otherwise it is a tint, not a ramp")

func test_the_freshest_stop_is_saturated() -> void:
	# THE one that was actually got wrong first time. The freshest pixel is the BRIGHTEST part of any trail,
	# so if it is near-white the whole effect reads as a pale translucent copy no matter how colourful the
	# cold end is — the rest of the ramp is too faint to argue with it. Measured, not eyeballed.
	var fresh: Color = GHOST.default_gradient().sample(1.0)
	assert_gt(fresh.s, 0.5,
		"the fresh end must be a saturated colour; a near-white one makes the trail look like a dimmed copy")

func test_the_skin_ships_with_no_authored_ramp() -> void:
	var skin := HudSkin.new()
	assert_null(skin.ghost_gradient,
		"the slot ships null so the shipped ramp is the default look — an artist opts IN by authoring one")
	skin = null

# --- the shipped knobs --------------------------------------------------------------------------------

func test_shipped_knobs_are_subtle_and_alive() -> void:
	# Mirrors test_hud_sway's shipped-knob pin: these are the values a player actually gets, and "subtle"
	# is a design promise that a stray inspector edit could quietly break.
	var hud: HudSettings = GameSettings.hud
	assert_gt(hud.hud_ghost_strength, 0.0, "the effect ships ON — it is the HUD's authored look, not an opt-in")
	assert_lte(hud.hud_ghost_strength, 0.5,
		"past ~0.5 a moving readout reads as printing twice rather than echoing — that is no longer subtle")
	assert_gt(hud.hud_ghost_tau, 0.0, "a zero tau would leave the latency half with no tail to smear")
	assert_lte(hud.hud_ghost_tau, 0.25, "a long tau smears the corner panel into a comet under screen shake")
	assert_lte(hud.hud_ghost_drag_max, 6.0,
		"the reticle's ghost is capped in the low single-digit pixels; past this it reads as two reticles")
	assert_gt(hud.hud_ghost_residue_floor, 0.0,
		"without a residue floor the 8-bit decay fixed point leaves a permanent smear wherever the HUD has been")
	assert_gt(hud.hud_ghost_tint, 0.5,
		"the ramp has to WIN over the source colour or the trail is just a dimmed copy of the element again")
	assert_lte(hud.hud_ghost_tint, 1.0, "and it is a mix weight, so it cannot exceed 1")
	assert_gt(hud.hud_ghost_tail_lift, 0.0,
		"a zero/negative gamma would blow the tail's alpha to infinity or flatten it — the ramp needs a real curve")
	assert_lt(hud.hud_ghost_tail_lift, 1.0,
		"below 1 LIFTS the old tail, which is the only reason the ramp's cold end is ever visible at all")

func test_the_player_dial_defaults_to_the_full_authored_effect() -> void:
	# A bare instance, not the autoload: the autoload's _ready has already loaded user://settings.cfg and
	# would report whatever this machine last saved rather than the shipped default (test_settings idiom).
	var fresh = load("res://managers/Settings.gd").new()
	assert_eq(fresh.hud_ghost_scale, 1.0,
		"a new profile gets the authored ghost; the slider exists to turn it DOWN (the hud_sway_scale idiom)")
	fresh.free()

# --- where the display rect sits in the draw order --------------------------------------------------------

func test_the_display_rect_is_seated_above_the_screen_space_pass() -> void:
	# ⭐ THE REGRESSION THIS PINS. The display shipped at `z_index -1`: below every readout (right) and below the
	# HUD layer's post-process ColorRect (wrong) — which means it was drawn INTO the screen texture that shader
	# fetches rather than composited over its output. Harmless while that shader was per-pixel; the moment it
	# grew a barrel lens the ghost was bent by a world warp the live HUD never sees, and the echo stood clear of
	# the readout it echoes with the camera dead still. Draw order inside one canvas is z_index FIRST, then child
	# index, so a seat is only safe if BOTH hold — hence two assertions, not one.
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var screen_pass := ColorRect.new()   # stands in for ui.tscn's post-process ColorRect
	screen_pass.name = "ColorRect"
	layer.add_child(screen_pass)
	var readout := Control.new()         # stands in for any HUD readout: added first, must still draw ON TOP
	layer.add_child(readout)
	var ghost = GHOST.new()
	layer.add_child(ghost)               # the driver is a plain Node child of the layer, as ui.gd builds it
	if not ghost.build(layer, screen_pass):
		pending("no viewport to build into — build() degrades to a no-op and there is no seat to pin")
		return
	var display := layer.get_node_or_null(^"HudGhost") as CanvasItem
	assert_not_null(display, "build() adds its display rect to the layer it was handed")
	if display == null:
		return
	assert_gte(display.z_index, screen_pass.z_index,
		"z is read BEFORE index: a lower z draws into the pass's screen fetch however late its index is")
	assert_gt(display.get_index(), screen_pass.get_index(),
		"the ghost must draw AFTER the screen-space pass, or any warp in it drags the echo off its readout")
	assert_lt(display.get_index(), readout.get_index(),
		"and BEFORE every readout — the ghost may never cover the crisp thing it is the echo of")
	assert_eq(display.visibility_layer, GHOST.UNCAPTURED_LAYER,
		"and it stays out of the capture, or the accumulator photographs its own output and runs away to white")


func test_with_no_screen_space_pass_the_display_still_sits_under_every_readout() -> void:
	# The degrade: a HUD layer with no post-process rect at all (and the seam ui.gd would hit if that node were
	# ever renamed). "Below the readouts" is the half that must survive regardless — it is the whole reason the
	# ghost is called an echo rather than an overlay.
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var readout := Control.new()
	layer.add_child(readout)
	var ghost = GHOST.new()
	layer.add_child(ghost)
	if not ghost.build(layer, null):
		pending("no viewport to build into — build() degrades to a no-op and there is no seat to pin")
		return
	var display := layer.get_node_or_null(^"HudGhost") as CanvasItem
	assert_not_null(display, "build() adds its display rect to the layer it was handed")
	if display == null:
		return
	assert_lt(display.get_index(), readout.get_index(),
		"with nothing to seat above, the display goes to the very bottom of the layer")
