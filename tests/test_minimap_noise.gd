extends GutTest

## THE NOISE RING (scripts/ui/minimap.gd — _sample_noise_radius / _noise_changed / _paint_noise_ring).
##
## The minimap's fourth painted channel: a circle around the player caret at the radius their own footsteps
## and gunfire currently carry. What is pinned here is everything about it that can rot SILENTLY — the paint
## itself is playtest-verified, as everywhere else on this widget.
##
## Two things carry almost all the risk and both have a test below:
##
##  1. THE QUANTISER (Minimap.NOISE_STEP_M). Ground deceleration is an exponential lerp, so a player who has
##     ever walked keeps a residual ground speed FOREVER and noise_radius never reaches exactly 0.0. Without
##     the snap, the idle gate's float compare mismatches in the last bits every frame and pins a full
##     floorplan repaint open at frame rate, in a silent room, with nothing drawn. The DRAWABILITY FLOOR (a ring
##     no bigger than the caret reads as silence) hides a missing snap at the HUD box's own scale, so
##     test_residual_ground_speed_snaps_to_exact_silence asks at a scale where the residual WOULD be drawable,
##     and test_a_ring_no_bigger_than_the_caret_reads_as_silence pins the floor on its own.
##  2. THE TWO-OWNER GATE being read in ONE place. _sample_noise_radius is the single site that reads
##     `ring_noise and Settings.minimap_show_noise`, which is what lets the idle gate and the paint site ask
##     literally the same question. test_minimap.gd's own
##     "the idle gate asks the same question the paint site does" exists because the NPC channel got this
##     wrong once; these two tests are that lesson applied to this channel.
##
## Loaded BY PATH, not by class_name, for the stale-global-class-cache reason test_minimap.gd documents, and
## every widget here is a bare `.new()` — the same load-bearing contract that file pins.

const MINIMAP_SCRIPT := "res://scripts/ui/minimap.gd"


## The Player surface this channel actually consumes: ONE duck-typed float. Deliberately not an NPC/Player
## instance — Player._ready instantiates weapons, nav and audio and mutates shared statics (the house rule),
## and this channel only ever reads `noise_radius` off it.
class PlayerStub extends Node3D:
	var noise_radius: float = 0.0


func _mm():
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	return mm


## A bare widget with a REAL scale, which a `.new()` alone never has (a zero rect answers 1 px/m at every zoom):
## a 1000 px square over a 1 m world span, so pixels_per_metre() is 1000 x `zoom`. The view goes through the
## widget's own per-instance overrides — the map tab's knobs — never through the Settings rows.
func _zoomed_mm(zoom: float):
	var mm = _mm()
	mm.size = Vector2(1000.0, 1000.0)
	mm.world_span_override = 1.0
	mm.zoom_override = zoom
	return mm


## A widget whose gate can actually be asked, copied from test_minimap.gd's own _idle_minimap: a bare .new()
## answers TRUE on three terms that have nothing to do with this channel — _deck_dirty ships true to force the
## first paint, _drawn_zoom is seeded NAN and _drawn_skin_id 0 so both first compares mismatch by design. The
## paint below is what stamps them; without it every idle assertion here would be measuring the seeds.
func _idle_minimap():
	var mm = load(MINIMAP_SCRIPT).new()
	mm._source_region_id = 0
	mm._deck_dirty = false
	add_child_autofree(mm)
	mm.size = GameSettings.hud.minimap_size
	return mm


## One painted frame — a queued redraw lands at the end of the frame, so two process frames.
func _repaint(mm) -> void:
	mm.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame


# --- the quantiser ----------------------------------------------------------------------------------------

## ⭐THE ONE THAT MATTERS. player.gd decelerates with an EXPONENTIAL lerp
## (`lerpf(velocity.x, ..., 1.0 - pow(1.0 - ground_ratio, fps_factor))`), which asymptotes toward zero and
## never arrives. So a player who stops walking keeps a residual ground speed, NoiseEmitter turns it into a
## residual noise_radius, and a raw compare against the drawn stamp would differ every single frame forever —
## a permanent full-rate repaint of the whole floorplan with an empty box on screen. The snap is what makes
## "silent" reach EXACTLY 0.0 so the gate's equality can shut.
##
## ⭐ASKED ON A ZOOMED-IN WIDGET, or it measures the wrong guard. A bare `.new()` has a zero rect, so it answers
## 1 px/m, and at 1 px/m the caret-sized drawability floor silences 0.108 m whether or not the snap exists. Here
## the widget is given a scale at which a 0.108 m ring would clear the caret (asserted as a precondition), so
## only the quantiser can return the 0.0 — and a one-step radius on the SAME widget still reads, the control
## showing the floor is not what answered.
func test_residual_ground_speed_snaps_to_exact_silence() -> void:
	var mm = _zoomed_mm(1.0)
	var p := PlayerStub.new()
	autofree(p)
	assert_gt(0.108 * float(mm.pixels_per_metre()), float(MenuStyle.hud.minimap_caret_px),
			"precondition: at this scale a 0.108 m ring is bigger than the caret, so the drawability floor cannot hide it")
	# The shape an exponential tail leaves behind: a sliver of leftover velocity turned into a sliver of radius.
	# NoiseEmitter now deadzones the FOOTSTEP channel at footstep_min_horizontal_speed, so the walk tail no longer
	# feeds one — but the snap stays the guard, because noise_radius is a plain var and any writer (a decaying
	# gunfire spike, a re-tuned deadzone) can still hand the ring a radius too small to matter and too big to equal 0.
	p.noise_radius = 0.108
	assert_eq(mm._sample_noise_radius(p), 0.0,
			"a residual noise radius must collapse to EXACTLY 0.0, or the idle gate never shuts again")
	var step := float(mm.NOISE_STEP_M)
	p.noise_radius = step
	assert_almost_eq(mm._sample_noise_radius(p), step, 0.0001,
			"control: one full step reads on the same widget — silence above came from the snap, not from the floor")


## ⭐THE DRAWABILITY FLOOR. A ring no bigger than the caret it surrounds is just a fatter caret, so the sample
## reports it as silence — decided in _sample_noise_radius rather than at the paint site, so the idle gate never
## buys repaints for a ring the paint would decline to draw. The floor is in PIXELS under the widget's OWN view
## (effective zoom, never Settings.minimap_zoom), so the same radius is silent on a zoomed-out widget and reads
## on a zoomed-in one: that pair is the whole contract, and the second half is what proves the map tab's own
## zoom is honoured.
func test_a_ring_no_bigger_than_the_caret_reads_as_silence() -> void:
	var p := PlayerStub.new()
	autofree(p)
	p.noise_radius = 2.0
	var caret := float(MenuStyle.hud.minimap_caret_px)
	var far = _zoomed_mm(0.0005)
	var near = _zoomed_mm(1.0)
	assert_lt(2.0 * float(far.pixels_per_metre()), caret,
			"precondition: zoomed out, a 2 m ring fits inside the caret")
	assert_gt(2.0 * float(near.pixels_per_metre()), caret,
			"precondition: zoomed in, the same 2 m ring clears it")
	assert_eq(far._sample_noise_radius(p), 0.0,
			"a ring hidden under the caret reads as SILENCE, so neither the gate nor the paint spends anything on it")
	assert_almost_eq(near._sample_noise_radius(p), 2.0, 0.0001,
			"...while the same radius on a view zoomed in far enough to show it reads back in full")


## The snap must not eat the signal it is protecting: a real walking/running radius still reads, quantised to
## its step. 0.25 m is 0.68 px at the shipped 2.7 px/m, so the stepping is invisible on the box.
func test_the_snap_keeps_a_real_radius() -> void:
	var mm = _mm()
	var p := PlayerStub.new()
	autofree(p)
	p.noise_radius = 6.03
	assert_almost_eq(mm._sample_noise_radius(p), 6.0, 0.0001, "a running radius survives, snapped to its step")
	p.noise_radius = 28.0
	assert_almost_eq(mm._sample_noise_radius(p), 28.0, 0.0001, "and a full gunshot radius is untouched")


## Negative is not a legal loudness. Floored rather than trusted, because noise_radius is a plain var any
## drop-in can write (the debug console's `notarget` zeroes the Player's noise exports through exactly that seam).
##
## ⭐ASKED ON A ZOOMED-IN WIDGET, for the same reason as the quantiser test above. On a bare `.new()` (1 px/m) a
## 5 m MAGNITUDE is no bigger than the caret (5 px as shipped), so the floor would silence -5 m even if the sample read the
## radius by its size — the regression that turns a bad write into a real 5 m ring. Here 5 m clears the caret
## (precondition) and +5 m reads back in full on the same widget (control), so only the sign can silence -5 m.
func test_a_negative_radius_reads_as_silence() -> void:
	var mm = _zoomed_mm(1.0)
	var p := PlayerStub.new()
	autofree(p)
	assert_gt(5.0 * float(mm.pixels_per_metre()), float(MenuStyle.hud.minimap_caret_px),
			"precondition: at this scale a 5 m ring is bigger than the caret, so the drawability floor cannot hide it")
	p.noise_radius = 5.0
	assert_almost_eq(mm._sample_noise_radius(p), 5.0, 0.0001,
			"control: the same 5 m, positive, reads back in full on this widget")
	p.noise_radius = -5.0
	assert_eq(mm._sample_noise_radius(p), 0.0, "a negative radius is silence, never an inside-out ring")


## Degrades over anything the tree can hand it: this runs every frame against whatever Groups.human_player
## returned, and a node that answers no `noise_radius` must read as silent rather than crash or draw.
func test_a_node_that_answers_nothing_is_silent() -> void:
	var mm = _mm()
	var plain := Node3D.new()
	autofree(plain)
	assert_eq(mm._sample_noise_radius(plain), 0.0, "a prop with no noise_radius is silent")


# --- the two-owner gate -----------------------------------------------------------------------------------

## The designer switch and the player's Options row BOTH have to be on — the dot_npcs / minimap_show_npcs
## idiom. Read in _sample_noise_radius and NOWHERE else, which is what keeps the idle gate and the paint site
## from drifting into asking two different questions.
func test_either_owner_off_silences_the_channel() -> void:
	var mm = _mm()
	var p := PlayerStub.new()
	autofree(p)
	p.noise_radius = 12.0
	var was: bool = Settings.minimap_show_noise
	assert_almost_eq(mm._sample_noise_radius(p), 12.0, 0.0001, "precondition: both owners on, the ring reads")
	Settings.minimap_show_noise = false          # Options -> Accessibility -> "Noise On Minimap"
	assert_eq(mm._sample_noise_radius(p), 0.0, "the PLAYER's row alone switches the channel off")
	Settings.minimap_show_noise = was
	mm.ring_noise = false                        # the designer half, on the widget
	assert_eq(mm._sample_noise_radius(p), 0.0, "and so does the DESIGNER's switch alone")


## Switching the row off is what makes the ring leave the canvas, and it needs NO stamp of its own to do it:
## the sample collapses to 0.0, which mismatches the stamp, which buys the one clearing repaint. This is why
## _options_changed has no _drawn_show_noise term — pinning the mechanism so nobody "fixes" it by adding one.
func test_switching_the_row_off_asks_for_the_clearing_repaint() -> void:
	var mm = _mm()
	var p := PlayerStub.new()
	autofree(p)
	p.noise_radius = 12.0
	var was: bool = Settings.minimap_show_noise
	mm._noise_r = mm._sample_noise_radius(p)
	mm._drawn_noise_r = mm._noise_r
	assert_false(mm._noise_changed(), "precondition: a painted, unchanging ring is idle")
	Settings.minimap_show_noise = false
	mm._noise_r = mm._sample_noise_radius(p)
	assert_true(mm._noise_changed(), "turning the row off must ask for the repaint that CLEARS the ring")
	Settings.minimap_show_noise = was


# --- the idle gate ----------------------------------------------------------------------------------------

## The gate's two edges in one walk: silence is idle, a gunshot opens it, a stamped radius shuts it, and
## silence falling again buys exactly ONE clearing repaint. A CanvasItem repaints only on queue_redraw, so
## without that last edge a fired-then-stopped player's ring would stay on the map until they walked.
func test_the_gate_opens_on_a_gunshot_and_shuts_itself_again() -> void:
	var mm = _idle_minimap()
	await _repaint(mm)
	assert_false(mm._needs_repaint(false), "precondition: a silent, still player on an empty map is idle")

	mm._noise_r = 28.0                       # the shot lands
	assert_true(mm._needs_repaint(false), "a gunshot repaints even though the player has not moved")

	mm._drawn_noise_r = 28.0                 # _draw stamps what it painted
	assert_false(mm._needs_repaint(false), "a painted radius that is not moving costs nothing")

	mm._noise_r = 0.0                        # the spike has decayed away
	assert_true(mm._needs_repaint(false), "silence falling asks for the ONE repaint that clears the ring")

	mm._drawn_noise_r = 0.0                  # ...which re-stamps
	assert_false(mm._needs_repaint(false), "and the gate shuts again — the trailing edge is self-clearing")


## Every intermediate radius during a gunshot's ~0.6 s decay must repaint, or the ring freezes mid-collapse
## for a player standing still. This is the whole animation, and it is driven by world state rather than a clock.
func test_a_decaying_spike_repaints_every_step() -> void:
	var mm = _idle_minimap()
	await _repaint(mm)
	mm._drawn_noise_r = 0.0
	for r in [28.0, 21.0, 14.0, 7.0, 0.25]:
		mm._noise_r = float(r)
		assert_true(mm._needs_repaint(false),
				"the ring must advance at %.2f m — a frozen shockwave is the bug this term prevents" % r)
		mm._drawn_noise_r = mm._noise_r


## The dev layer is the one term here that is deliberately NOT self-clearing: it draws sources that appear and
## free themselves on their own schedule, so nothing this widget stamps could describe them. It ships OFF, and
## switching it off must give the idle map straight back.
func test_the_dev_layer_pins_the_gate_open_and_lets_go() -> void:
	var mm = _idle_minimap()
	await _repaint(mm)
	assert_false(mm.debug_noise, "the dev layer ships OFF")
	assert_false(mm._needs_repaint(false), "precondition: idle")
	mm.debug_noise = true
	assert_true(mm._needs_repaint(false), "a developer who switched it on wants a per-frame repaint")
	mm.debug_noise = false
	assert_false(mm._needs_repaint(false), "and switching it off returns the map to idle")


# --- defaults + the skin slot -----------------------------------------------------------------------------

## Both owners ship ON — this is a readout of your OWN state, not through-wall knowledge of anyone else's, so
## it does not owe the player the opt-out-by-default that a sensor would. A SHIP DECISION, pinned as one: it goes
## red only when somebody flips a default, which is exactly when that decision should be looked at again.
func test_the_channel_ships_on_for_both_owners() -> void:
	var mm = _mm()
	assert_true(mm.ring_noise,
			"SHIP DECISION: the designer switch ships ON — the ring reports the player's own noise, not anyone else's position")
	var fresh = load("res://managers/Settings.gd").new()
	assert_true(fresh.minimap_show_noise,
			"SHIP DECISION: the player's Options row ships ON too — a readout of your own state owes no opt-out-by-default")
	fresh.free()  # Settings.gd extends Node — `= null` would leak it (test_minimap.gd:415)


## The ring's tint is the ARTIST's, on the same skin as every other thing this widget inks — and the SHIPPED skin
## (resources/ui/hud_skin.tres, what MenuStyle.hud boots on) has to paint it in a way the plan survives. A gunshot
## ring covers the whole box for half a second, so both its slots are washes rather than solid ink, and the disc
## under the entire floorplan is quieter than the rim that outlines it. The disc ships ON (alpha > 0), unlike the
## wall glow: at gunshot radii the rim is entirely off the box and the disc is the only thing carrying the event.
##
## Which slot the paint site reads is not asserted: headless GUT never rasterises, and the old source grep for
## the slot name could not tell the ring's paint from the dev layer's (both read it), so it pinned nothing.
func test_the_shipped_noise_ink_washes_over_the_plan_rather_than_burying_it() -> void:
	var s = load("res://resources/ui/hud_skin.tres")
	assert_true("minimap_noise_color" in s, "HudSkin exposes minimap_noise_color, the slot the ring paints from")
	assert_true("minimap_noise_fill_color" in s, "...and minimap_noise_fill_color, the disc inside it")
	var rim: Color = s.minimap_noise_color
	var disc: Color = s.minimap_noise_fill_color
	assert_gt(rim.a, 0.0, "the shipped rim is visible at all — an alpha-0 ring draws nothing on any radius")
	assert_lt(rim.a, 1.0,
			"the rim washes over the floorplan rather than burying it — a gunshot ring covers the whole box")
	assert_gt(disc.a, 0.0,
			"SHIP DECISION: the audible disc ships ON — at gunshot radii the rim is off the box and the disc is the only thing drawn")
	assert_lt(disc.a, rim.a,
			"the disc under the WHOLE floorplan is a quieter wash than the rim that outlines it, or it buries every marker on the plan")


# --- the paint itself -------------------------------------------------------------------------------------

## Counts (and marks handled) the engine's refusals of draw_* calls made OUTSIDE a paint since the last call. The
## engine raises one "Drawing is only allowed inside this node's `_draw()`" error per refused call, before anything
## is drawn, so this is a count of how many draw calls a paint function reached.
func _count_draw_refusals() -> int:
	var n := 0
	for e in get_errors():
		if not e.handled and e.is_engine_error() and e.contains_text("only allowed inside"):
			e.handled = true
			n += 1
	return n


## THE INK, not its appearance. Every assertion above stops short of _paint_noise_ring, so this is the one place
## its draw calls run at all. Headless GUT never rasterises, so the calls are observed two ways:
##
##  1. REACHED. Called directly — outside a paint — every draw call the ring reaches is refused with one engine
##     error (see _count_draw_refusals), so the refusals count the ink. Silence must reach none; a real ring reaches
##     the audible disc and the rim over it (the shipped disc is ON, pinned above); and with the disc's alpha at 0,
##     the documented outline-only switch, the rim alone. An early return, a dropped draw_arc or an ignored alpha
##     sentinel all move the count.
##  2. LEGAL. Inside real paints the same calls run at every size, and GUT 9.6 fails a test on any engine error, so
##     a bad arc argument or a stroke_width call that errors fails here. 12 m is a normal ring, 28 m the gunshot
##     that overflows a 108 px box and must be CLIPPED rather than crash or clamp, 400 m far past it. The stamp is
##     only the precondition that a real paint ran at that radius (_draw writes it before it paints the ring).
##     The view is pinned at zoom 1 (the box's own 2.7 px/m) so the sizes mean the same whatever settings.cfg holds.
func test_the_ring_actually_paints_at_every_size() -> void:
	var mm = _idle_minimap()
	mm.zoom_override = 1.0
	await _repaint(mm)
	var skin = MenuStyle.hud
	var ppm := float(mm.pixels_per_metre())
	var at: Vector2 = mm.size * 0.5
	var shipped_fill: Color = skin.minimap_noise_fill_color
	assert_gt(shipped_fill.a, 0.0, "precondition: the shipped disc is ON, so a real ring inks a disc AND a rim")

	mm._noise_r = 0.0
	mm._paint_noise_ring(skin, ppm, at)
	assert_eq(_count_draw_refusals(), 0, "silence reaches no draw call: nothing is inked for a player making no noise")
	mm._noise_r = 12.0
	mm._paint_noise_ring(skin, ppm, at)
	assert_eq(_count_draw_refusals(), 2, "a real ring reaches both of its draw calls: the audible disc, then the rim")
	skin.minimap_noise_fill_color = Color(shipped_fill.r, shipped_fill.g, shipped_fill.b, 0.0)
	mm._paint_noise_ring(skin, ppm, at)
	skin.minimap_noise_fill_color = shipped_fill
	assert_eq(_count_draw_refusals(), 1,
			"with the disc's alpha at 0 (the artist's outline-only switch) the ring inks its rim alone")

	for r in [0.0, 0.25, 12.0, 28.0, 400.0]:
		mm._noise_r = float(r)
		await _repaint(mm)
		assert_almost_eq(mm._drawn_noise_r, float(r), 0.0001,
				"precondition: a real paint ran at %.2f m — any engine error its ink raised there fails this test" % r)


## The DEV layer over a live Groups.NOISE channel, including the two shapes that actually occur: a source that
## names its emitter (the player's own, an NPC's gunfire) and one that names nobody (a thrown decoy leaves
## `emitter` null). Also covers a SILENT source, which must be skipped rather than drawn as a zero-radius arc.
func test_the_dev_layer_paints_over_live_noise_sources() -> void:
	var mm = _idle_minimap()
	mm.debug_noise = true
	var loud := NoiseSource.new()
	add_child_autofree(loud)
	loud.radius = 18.0
	loud.emitter = mm            # any Node — the layer only reads its name
	var anon := NoiseSource.new()
	add_child_autofree(anon)
	anon.radius = 12.0           # a decoy: nobody in particular, emitter stays null
	var silent := NoiseSource.new()
	add_child_autofree(silent)
	silent.radius = 0.0          # NoiseSource.audible requires a POSITIVE radius — never drawn
	assert_true(loud.is_in_group(Groups.NOISE), "precondition: a NoiseSource joins the shared channel on ready")
	# THE FRAME MUST REALLY PAINT, or the engine-error check is vacuous. _paint_markers runs after the dev layer in
	# the same _draw and opens by re-stamping the `_painted` latch from what it found (nothing, in this scene), so a
	# latch seeded true that reads false after the frame proves this _draw ran with the dev layer ON and carried on
	# to the marker channels (a dev layer that ended _draw early would strand every marker). An ERROR inside the dev
	# layer is not what the latch catches: a GDScript callee error returns to its caller and _draw carries on.
	# GUT 9.6's engine-error check is what fails this test for that.
	assert_true(get_tree().get_nodes_in_group(Groups.MINIMAP).is_empty(),
			"precondition: no POI marker is live, so a marker paint that ran re-stamps the latch to false")
	mm._painted = true
	await _repaint(mm)
	assert_false(mm._painted,
			"the frame painted with the dev layer on and carried on to the marker channels — a dev layer that ended _draw early would leave every marker unpainted")
	# ...and the dev layer is the DEVELOPER's instrument, not the player's declutter row: it keeps the gate open
	# with the player's own ring switched off.
	var was: bool = Settings.minimap_show_noise
	Settings.minimap_show_noise = false
	assert_true(mm._needs_repaint(false),
			"the dev layer ignores the player's Noise On Minimap row — the row hides the player's ring, not the instrument")
	mm.debug_noise = false
	assert_false(mm._needs_repaint(false),
			"control: the same widget with the dev layer off is idle, so the open gate above was the dev layer's doing")
	Settings.minimap_show_noise = was
