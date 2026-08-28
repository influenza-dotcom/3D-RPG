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
##     floorplan repaint open at frame rate, in a silent room, with nothing drawn — and every other test in
##     this suite still passes. test_residual_ground_speed_snaps_to_exact_silence is the only tripwire.
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
func test_residual_ground_speed_snaps_to_exact_silence() -> void:
	var mm = _mm()
	var p := PlayerStub.new()
	autofree(p)
	# The shape an exponential tail leaves behind: a sliver of leftover velocity turned into a sliver of radius.
	# NoiseEmitter now deadzones the FOOTSTEP channel at footstep_min_horizontal_speed, so the walk tail no longer
	# feeds one — but the snap stays the guard, because noise_radius is a plain var and any writer (a decaying
	# gunfire spike, a re-tuned deadzone) can still hand the ring a radius too small to draw and too big to equal 0.
	p.noise_radius = 0.108
	assert_eq(mm._sample_noise_radius(p), 0.0,
			"a residual noise radius must collapse to EXACTLY 0.0, or the idle gate never shuts again")


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
func test_a_negative_radius_reads_as_silence() -> void:
	var mm = _mm()
	var p := PlayerStub.new()
	autofree(p)
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
## it does not owe the player the opt-out-by-default that a sensor would.
func test_the_channel_ships_on_for_both_owners() -> void:
	var mm = _mm()
	assert_true(mm.ring_noise, "the designer switch ships on")
	var fresh = load("res://managers/Settings.gd").new()
	assert_true(fresh.minimap_show_noise, "and so does the player-facing row")
	fresh.free()  # Settings.gd extends Node — `= null` would leak it (test_minimap.gd:415)


## The ring's tint is the ARTIST's, on the same skin as every other thing this widget inks.
func test_the_ring_reads_its_colour_from_the_hud_skin() -> void:
	var s = load("res://scripts/ui/hud_skin.gd").new()
	assert_true("minimap_noise_color" in s, "HudSkin exposes minimap_noise_color")
	assert_lt(float(s.minimap_noise_color.a), 1.0,
			"it washes over the floorplan rather than burying it — a gunshot ring covers the whole box")
	var src: String = FileAccess.get_file_as_string(MINIMAP_SCRIPT)
	assert_true(src.contains("MenuStyle.hud.minimap_noise_color"), "and the ring paints from that slot")
	s = null


# --- the paint itself -------------------------------------------------------------------------------------

## A SMOKE TEST FOR THE INK, not for its appearance. Every assertion above stops short of the early return in
## _paint_noise_ring, so without this the draw_arc call and the dev layer's draw_string were never once
## executed by the suite. It matters here specifically because GUT 9.6 fails a whole suite on any ENGINE error,
## so "the paint ran and the suite is still green" is a real signal: the arc's argument types, the
## stroke_width call and ThemeDB.fallback_font all held.
##
## Radii chosen to cross the two branches that exist: 12 m is a normal ring, and 28 m is the gunshot that
## overflows a 108 px box and must be CLIPPED rather than crash or clamp.
func test_the_ring_actually_paints_at_every_size() -> void:
	var mm = _idle_minimap()
	await _repaint(mm)
	for r in [0.0, 0.25, 12.0, 28.0, 400.0]:
		mm._noise_r = float(r)
		await _repaint(mm)
		assert_almost_eq(mm._drawn_noise_r, float(r), 0.0001,
				"a paint at %.2f m stamps the radius it drew — the gate's whole contract" % r)
	assert_true(true, "the arc painted at every radius without an engine error")


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
	await _repaint(mm)
	assert_true(loud.is_in_group(Groups.NOISE), "precondition: a NoiseSource joins the shared channel on ready")
	assert_true(true, "the dev layer painted rings + labels over the live channel without an engine error")


## A source freed between the group read and the paint is the realistic hazard here, not a theoretical one:
## NoisePulser parents its burst to the emitter's PARENT precisely so an NPC's death pulse outlives the NPC,
## and these nodes self-free on their own lifetime. The layer must survive one that has already gone.
func test_the_dev_layer_survives_a_freed_source() -> void:
	var mm = _idle_minimap()
	mm.debug_noise = true
	var doomed := NoiseSource.new()
	add_child(doomed)
	doomed.radius = 9.0
	doomed.free()
	await _repaint(mm)
	assert_true(true, "a freed source is skipped rather than crashing the paint")
