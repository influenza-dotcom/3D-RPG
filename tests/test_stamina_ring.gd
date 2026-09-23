extends GutTest

## Radial stamina ring (scripts/ui/stamina_ring.gd) + the ring/bar accessibility mode switch in ui.gd.
## Covers the PURE parts off-tree — arc/angle math, the fill->sweep mapping, the continuous fill->low colour blend (no snap threshold),
## the idle fade target, the relations the shipped HudSettings ring knobs must hold (annulus fit between the hit ticks
## and the aim arcs, under-the-reticle left-to-right shape, invisible-at-rest / outlined ship decisions), the Settings
## toggle, and the mode routing on a bare UI (no _ready, no scene tree). The on-screen look (the ring hugging the
## live crosshair as it is actually painted) is playtest territory.
##
## ALSO the SPEND CHIP (scripts/ui/stamina_chip.gd) — the white shard left behind by stamina you just
## spent, which BOTH readouts paint from one shared tracker: the tracker's hold/slide state machine, and the
## two pure geometry helpers that place it (RING.chip_span for the arc, UI.stamina_chip_band for
## the corner bar's rect).

## Loaded BY PATH (not the class_name) so the suite parses even before the editor registers the new
## global class — the same cache-cascade guard the runtime wiring uses.
const RING := preload("res://scripts/ui/stamina_ring.gd")
const CHIP := preload("res://scripts/ui/stamina_chip.gd")

var _prev_loaded: bool
var _prev_ring_enabled: bool

func before_each() -> void:
	# Never let a setter round-trip clobber the real user://settings.cfg (the test_settings.gd idiom).
	_prev_loaded = Settings._loaded
	_prev_ring_enabled = Settings.stamina_ring_enabled
	Settings._loaded = false

func after_each() -> void:
	Settings.stamina_ring_enabled = _prev_ring_enabled
	Settings._loaded = _prev_loaded

# --- arc math -----------------------------------------------------------------------------------------

func test_arc_angles_empty_fill_collapses_to_the_start_angle() -> void:
	var a: Vector2 = RING.arc_angles(0.0, 180.0, -180.0)
	assert_almost_eq(a.x, deg_to_rad(180.0), 0.0001, "the fill arc always starts at start_deg")
	assert_almost_eq(a.y, deg_to_rad(180.0), 0.0001, "an empty pool spans zero degrees (from == to)")

func test_arc_angles_full_fill_spans_the_whole_signed_sweep() -> void:
	var a: Vector2 = RING.arc_angles(1.0, 180.0, -180.0)
	assert_almost_eq(a.y, deg_to_rad(0.0), 0.0001,
		"a full pool ends at start + sweep (180 + -180 = 0 deg, the right-hand end of the gauge)")

func test_arc_angles_half_fill_of_the_default_gauge_ends_at_the_bottom() -> void:
	# Default knobs: start 180 (left), sweep -180 -> the gauge runs left -> bottom -> right under the
	# reticle. Half fill must therefore end at 90 deg — the BOTTOM in y-down canvas angles.
	var a: Vector2 = RING.arc_angles(0.5, 180.0, -180.0)
	assert_almost_eq(a.y, deg_to_rad(90.0), 0.0001,
		"half fill of the default half-ring ends at 90 deg (canvas bottom) — the sweep is signed, not a span+flag pair")

func test_arc_angles_clamps_overfill_and_underfill() -> void:
	var over: Vector2 = RING.arc_angles(2.0, 180.0, -180.0)
	var full: Vector2 = RING.arc_angles(1.0, 180.0, -180.0)
	assert_almost_eq(over.y, full.y, 0.0001, "fill > 1 draws exactly the full gauge, never past it")
	var under: Vector2 = RING.arc_angles(-1.0, 180.0, -180.0)
	assert_almost_eq(under.y, under.x, 0.0001, "fill < 0 collapses to the start angle, never sweeps backwards")

func test_arc_angles_positive_sweep_grows_the_other_way() -> void:
	var a: Vector2 = RING.arc_angles(0.5, 0.0, 90.0)
	assert_almost_eq(a.y, deg_to_rad(45.0), 0.0001,
		"a positive sweep grows in the positive (screen-clockwise) direction — direction is the sweep's SIGN")

# --- colour + fade ------------------------------------------------------------------------------------

func test_ring_color_blends_continuously_with_the_fill_level() -> void:
	# The exact colour objects matter (assert_eq(Color) needs exact endpoints) — use two sentinels.
	var fill_col := Color(0.18, 0.75, 0.95, 0.92)
	var low_col := Color(0.95, 0.78, 0.25, 1.0)
	assert_eq(RING.ring_color(1.0, fill_col, low_col), fill_col,
		"a full pool wears the pure fill colour (blue end of the gradient)")
	assert_eq(RING.ring_color(0.0, fill_col, low_col), low_col,
		"an empty pool wears the pure low colour (yellow end)")
	# Half stamina sits on the channel-wise MIDPOINT of the two endpoints — spelled out per channel, not
	# re-derived through Color.lerp, so a curved or snapped blend cannot agree with its own oracle.
	var mid: Color = RING.ring_color(0.5, fill_col, low_col)
	assert_almost_eq(mid.r, (fill_col.r + low_col.r) * 0.5, 0.0001, "half stamina blends halfway (red channel)")
	assert_almost_eq(mid.g, (fill_col.g + low_col.g) * 0.5, 0.0001, "half stamina blends halfway (green channel)")
	assert_almost_eq(mid.b, (fill_col.b + low_col.b) * 0.5, 0.0001, "half stamina blends halfway (blue channel)")
	assert_almost_eq(mid.a, (fill_col.a + low_col.a) * 0.5, 0.0001, "half stamina blends halfway (alpha channel)")
	# NO THRESHOLD SNAP (user call): walk the pool up from empty in 1% steps. Every step may move each channel by at
	# most its own 1% share of the endpoint gap — a snap threshold anywhere on the gauge jumps far past that.
	var prev: Color = RING.ring_color(0.0, fill_col, low_col)
	var worst_overshoot := 0.0
	for i in range(1, 101):
		var c: Color = RING.ring_color(float(i) / 100.0, fill_col, low_col)
		worst_overshoot = maxf(worst_overshoot, absf(c.r - prev.r) - absf(fill_col.r - low_col.r) / 100.0)
		worst_overshoot = maxf(worst_overshoot, absf(c.g - prev.g) - absf(fill_col.g - low_col.g) / 100.0)
		worst_overshoot = maxf(worst_overshoot, absf(c.b - prev.b) - absf(fill_col.b - low_col.b) / 100.0)
		worst_overshoot = maxf(worst_overshoot, absf(c.a - prev.a) - absf(fill_col.a - low_col.a) / 100.0)
		prev = c
	assert_lt(worst_overshoot, 0.0001,
		"a 1% change in stamina never jumps the colour further than 1% of the gradient — the blend is continuous, no threshold snap")
	assert_eq(RING.ring_color(2.0, fill_col, low_col), fill_col,
		"overfull clamps to the fill end rather than extrapolating past it")

func test_alpha_target_idles_only_at_full() -> void:
	assert_almost_eq(RING.alpha_target(1.0, 0.25), 0.25, 0.0001,
		"a full pool rests at the faint idle alpha (a full ring is zero-information)")
	assert_almost_eq(RING.alpha_target(0.9, 0.25), 1.0, 0.0001,
		"any spend pops the ring to fully lit")

func test_alpha_target_holds_lit_at_full_while_holding() -> void:
	assert_almost_eq(RING.alpha_target(1.0, 0.25, true), 1.0, 0.0001,
		"a full pool inside the post-refill hold stays fully lit — the fade waits for the hold to expire")
	assert_almost_eq(RING.alpha_target(1.0, 0.25, false), 0.25, 0.0001,
		"once the hold expires a full pool falls back to the idle alpha")

func test_outline_span_pads_both_tips_along_the_sweep() -> void:
	# Positive sweep (to > from): the pad extends BELOW from and ABOVE to.
	var p := RING.outline_span(Vector2(1.0, 2.0), 0.1)
	assert_almost_eq(p.x, 0.9, 0.0001, "positive-sweep outline starts a pad early")
	assert_almost_eq(p.y, 2.1, 0.0001, "…and ends a pad late")
	# Negative sweep (to < from, the shipped -180 gauge): the pad flips with the direction.
	var n := RING.outline_span(Vector2(2.0, 1.0), 0.1)
	assert_almost_eq(n.x, 2.1, 0.0001, "negative-sweep outline starts a pad early (the other way)")
	assert_almost_eq(n.y, 0.9, 0.0001, "…and ends a pad late (the other way)")

# --- shipped defaults (relations to the neighbours + stated ship decisions, not literal pins) -----------

## Both the script defaults (a fresh HudSettings) and the SHIPPED .tres the HUD actually reads, so an
## inspector override on HudSettings.tres is held to the same relations as the code default.
func _ring_knob_sources() -> Array:
	return [HudSettings.new(), GameSettings.hud]

func test_hud_settings_ring_fits_between_the_hit_ticks_and_the_aim_arcs() -> void:
	# The annulus budget stamina_ring.gd's header documents, asserted as RELATIONS to the same-centre
	# neighbours' own knobs (MenuStyle.hud, the HUD skin) rather than as the ring's literal numbers: the whole
	# painted stroke (outline included) must sit OUTSIDE a body hit-tick at full pop and INSIDE the red
	# aim-warning arcs' inner edge. Any retune that keeps that fit passes; one that collides fails.
	var skin = MenuStyle.hud  # untyped on purpose: HudSkin's class_name may not be cached yet (the hitmarker idiom)
	var body_tick_reach: float = skin.hitmarker_gap + skin.hitmarker_pop_px + skin.hitmarker_tick_length
	var aim_arc_inner_edge: float = minf(skin.aim_arc_base_radius, skin.aim_arc_max_radius) - skin.aim_arc_thickness * 0.5
	for src in _ring_knob_sources():
		var h: HudSettings = src
		assert_gt(h.stamina_ring_thickness, 0.0, "the ring has a visible stroke")
		assert_lt(h.stamina_ring_thickness, skin.aim_arc_thickness,
			"the stamina ring draws THINNER than the red aim-warning arcs — the combat cue must out-weigh the resource gauge")
		var half_stroke := h.stamina_ring_thickness * 0.5 + maxf(h.stamina_ring_outline_width, 0.0)
		assert_gt(h.stamina_ring_radius - half_stroke, body_tick_reach,
			"the ring's inner edge (outline included) clears a body hit-tick at full pop — a hit confirm must not paint over the gauge")
		assert_lt(h.stamina_ring_radius + half_stroke, aim_arc_inner_edge,
			"the ring's outer edge (outline included) stays inside the aim-warning arcs — past it the gauge kisses the red 'you're being aimed at' cue")

func test_hud_settings_gauge_is_a_left_to_right_meter_under_the_reticle() -> void:
	# SHIP DECISION (stamina_ring_start_deg / _sweep_deg docs): the gauge hugs the UNDERSIDE of the reticle and
	# fills left-to-right like a meter. Sampled through the real arc math, so any start/sweep pair with that
	# shape passes — only a gauge that climbs over the aim point or fills backwards fails.
	for src in _ring_knob_sources():
		var h: HudSettings = src
		var sweep := h.stamina_ring_sweep_deg
		assert_true(absf(sweep) > 0.0 and absf(sweep) <= 360.0,
			"the sweep spans something and never laps itself (|sweep| %.1f)" % sweep)
		var above := 0
		for i in 11:
			var tip: float = RING.arc_angles(float(i) / 10.0, h.stamina_ring_start_deg, sweep).y
			if sin(tip) < -0.001:  # y-down canvas: negative sine is ABOVE the centre
				above += 1
		assert_eq(above, 0, "no part of the gauge rises above the reticle — it hugs the underside")
		var empty_end: float = RING.arc_angles(0.0, h.stamina_ring_start_deg, sweep).y
		var full_end: float = RING.arc_angles(1.0, h.stamina_ring_start_deg, sweep).y
		assert_lt(cos(empty_end), cos(full_end), "an empty pool sits LEFT of a full one — the gauge fills left to right")

func test_hud_settings_ring_rests_invisible_lingers_and_is_outlined() -> void:
	for src in _ring_knob_sources():
		var h: HudSettings = src
		assert_true(h.stamina_ring_idle_alpha >= 0.0 and h.stamina_ring_idle_alpha <= 0.001,
			"SHIP DECISION (user call): a full ring rests FULLY INVISIBLE — the idle alpha must sit at or under _draw's 0.001 paint cut-off, or a ghost ring stays stamped on the aim point")
		assert_gt(h.stamina_ring_fade_speed, 0.0, "the idle fade must actually ease")
		assert_gt(h.stamina_ring_full_hold, 0.0,
			"SHIP DECISION (user call): a refill LINGERS lit for a split second before fading — 0 would blink the gauge out the instant the last point returns")
		assert_gt(h.stamina_ring_outline_width, 0.0, "SHIP DECISION: the thin arc ships with a contrast outline so it stays legible over bright scenes")
		assert_gt(h.stamina_ring_outline_color.a, 0.0, "the outline is actually painted")
		assert_lt(h.stamina_ring_outline_color.get_luminance(), minf(h.stamina_fill.get_luminance(), h.stamina_low.get_luminance()),
			"the outline is DARKER than both ends of the fill gradient — a rim no darker than the fill gives it no contrast")

func test_settings_ring_ships_on_and_the_options_setter_swaps_the_hud_readout() -> void:
	# SHIP DECISION: the RING is the default readout; the corner bar is the accessibility OPT-IN. A fresh
	# Settings (var default, no cfg load) must agree.
	var fresh = load("res://managers/Settings.gd").new()
	assert_true(fresh.stamina_ring_enabled, "the crosshair stamina ring is the shipped DEFAULT (bar = opt-in)")
	fresh.free()
	# The Options toggle goes through the setter and ui.gd picks it up on its next poll — no rebuild, no restart.
	var ui := _bare_ui_with_both_widgets()
	Settings.stamina_ring_enabled = true  # known start (before_each/after_each restore the real value)
	Settings.set_stamina_ring_enabled(false)
	ui._apply_stamina_mode()
	assert_true(ui._stamina_bar.visible, "switching the ring OFF in Options brings the classic corner bar back on the next HUD poll")
	assert_false(ui._stamina_ring.visible, "…and takes the ring off the crosshair")
	Settings.set_stamina_ring_enabled(true)
	ui._apply_stamina_mode()
	assert_true(ui._stamina_ring.visible, "switching it back ON restores the ring")
	assert_false(ui._stamina_bar.visible, "…and hides the corner bar again")
	ui.free()

# --- the mode switch on a bare UI (off-tree — _ready never runs) -------------------------------------

func _bare_ui_with_both_widgets() -> UI:
	var ui := UI.new()
	ui._stamina_bar = Control.new()
	ui.add_child(ui._stamina_bar)
	ui._stamina_ring = RING.new()
	ui.add_child(ui._stamina_ring)
	return ui

func test_apply_stamina_mode_shows_exactly_one_widget() -> void:
	var ui := _bare_ui_with_both_widgets()
	Settings.stamina_ring_enabled = true
	ui._apply_stamina_mode()
	assert_true(ui._stamina_ring.visible, "ring mode shows the ring")
	assert_false(ui._stamina_bar.visible, "ring mode hides the corner bar — never both")
	Settings.stamina_ring_enabled = false
	ui._apply_stamina_mode()
	assert_false(ui._stamina_ring.visible, "bar mode hides the ring")
	assert_true(ui._stamina_bar.visible, "bar mode shows the corner bar")
	ui.free()

func test_dialogue_hide_wins_over_the_mode_in_both_modes() -> void:
	var ui := _bare_ui_with_both_widgets()
	Settings.stamina_ring_enabled = true
	ui._set_gameplay_hud_visible(false)
	assert_false(ui._stamina_ring.visible, "dialogue hides the ring (gameplay-hidden composes with the mode)")
	assert_false(ui._stamina_bar.visible, "dialogue keeps the inactive bar hidden too")
	ui._set_gameplay_hud_visible(true)
	assert_true(ui._stamina_ring.visible, "dialogue close restores the ACTIVE widget (ring mode)")
	assert_false(ui._stamina_bar.visible, "…and only that one")
	ui.free()

func test_death_freeze_stops_the_mode_poll_resurrecting_widgets() -> void:
	# hide_hud_for_death hides + remembers nodes; the per-frame mode poll must NOT re-show anything
	# while that snapshot is outstanding, or the gauge floats over the death fade.
	var ui := _bare_ui_with_both_widgets()
	Settings.stamina_ring_enabled = true
	ui._stamina_ring.visible = false
	ui._stamina_bar.visible = false
	ui._death_hidden_hud.append(ui._stamina_ring)  # simulate an outstanding death-hide snapshot
	ui._apply_stamina_mode()
	assert_false(ui._stamina_ring.visible, "the death cinematic keeps the ring hidden despite ring mode being on")
	assert_false(ui._stamina_bar.visible, "…and the bar")
	ui._death_hidden_hud.clear()  # the revive path (restore_hud_after_death) clears the snapshot
	ui._apply_stamina_mode()
	assert_true(ui._stamina_ring.visible, "after the revive clears the snapshot, the mode poll resumes")
	ui.free()

# --- the fade PRIMING latch (the respawn-flash regression) -------------------------------------------

## Off-tree, no add_child: _ready never runs, nothing is drawn — we drive _process by hand and assert the
## fade STATE. Free with .free() (Node, not RefCounted). The one ambient dep is the GameSettings.hud
## autoload the ease already reads at runtime, so the asserts compare against alpha_target rather than a
## hardcoded number — a designer retuning stamina_ring_idle_alpha must not fail the suite.
func _offtree_ring():
	return RING.new()

func _idle_alpha() -> float:
	return GameSettings.hud.stamina_ring_idle_alpha

func test_first_visible_frame_adopts_the_target_instead_of_replaying_an_offscreen_change() -> void:
	# THE respawn-flash regression. Reproduces the death->revive seam exactly: the ring is lit (stamina
	# spent), hide_hud_for_death hides it, the pool is refilled OFF-SCREEN by _respawn_at_checkpoint, and
	# restore_hud_after_death shows it again. Before the fix the ring came back owing a full 1.0 -> 0.0
	# dissolve — a bright half-ring at the reticle over the spawn fade-up.
	var ring = _offtree_ring()
	ring.visible = true
	ring.fill = 0.4
	for _i in 30:
		ring._process(1.0 / 60.0)
	assert_almost_eq(ring._alpha_mult, 1.0, 0.001, "a spent pool leaves the ring fully lit — the shipped contract")
	ring.visible = false                     # hide_hud_for_death
	ring._process(1.0 / 60.0)
	assert_false(ring._fade_primed, "hiding the ring un-primes the fade — an unwatched change is never animated")
	ring.fill = 1.0                          # _respawn_at_checkpoint: _set_stamina(stamina_max())
	ring.visible = true                      # restore_hud_after_death
	ring._process(1.0 / 60.0)
	assert_almost_eq(ring._alpha_mult, _idle_alpha(), 0.001,
		"the first visible frame ADOPTS the full-pool target — it must not replay the off-screen refill as a ~0.77 s dissolve (the respawn flash landed this frame at ~0.905)")
	assert_true(ring._fade_primed, "…and the ease is armed again from here on")
	ring.free()

func test_a_fresh_ring_never_fades_in_from_full() -> void:
	# The second face of the same bug: the scene-reload death modes, a new game and every level load build
	# a FRESH ring, whose `fill` and `_alpha_mult` both start at 1.0 — a full alpha-unit from a full pool's
	# resting state, so it used to dissolve on every spawn.
	var ring = _offtree_ring()
	assert_false(ring._fade_primed,
		"a brand-new ring is unprimed — its 1.0 initialiser is a don't-care, never a value to animate away from")
	ring.visible = true
	ring._process(1.0 / 60.0)
	assert_almost_eq(ring._alpha_mult, _idle_alpha(), 0.001,
		"a HUD built with a full pool starts at the idle alpha, not mid-dissolve")
	ring.free()

func test_a_primed_ring_still_eases_rather_than_cutting() -> void:
	# Guards the shipped feel against an over-eager fix: the latch must not turn the fade into a hard cut
	# while the ring is continuously on screen. Bounds, not exact values, so retuning fade_speed is safe.
	var ring = _offtree_ring()
	ring.visible = true
	ring.fill = 1.0
	ring._process(1.0 / 60.0)  # prime at the idle alpha
	ring.fill = 0.5
	ring._process(1.0 / 60.0)
	assert_gt(ring._alpha_mult, _idle_alpha(), "spending stamina starts lighting the ring…")
	assert_lt(ring._alpha_mult, 1.0, "…but EASES there over ~three quarters of a second — the pop is a fast fade, not a cut")
	# 60 more frames = 1.02 s of ease. The exp-lerp needs ~4.6 time constants to fall inside the 0.01 snap
	# window, which at the shipped fade_speed 6 is 47 frames / 0.78 s — the same ~0.77 s dissolve the
	# respawn-flash test above quotes. The old 30-frame budget stopped the clock mid-ease at 1 - exp(-3.1) =
	# 0.955. ⭐The SNAP is still what closes it, not the extra time: after 61 frames the raw asymptote alone
	# would sit exp(-6.1) = 0.0022 short of 1.0, outside this 0.001 tolerance — so deleting the snap still
	# fails this test. Don't stretch past ~69 frames or the ease arrives unaided and the assert goes vacuous.
	for _i in 60:
		ring._process(1.0 / 60.0)
	assert_almost_eq(ring._alpha_mult, 1.0, 0.001, "and it does arrive, exactly (the 0.01 snap closes the asymptote)")
	ring.free()

func test_a_refill_lingers_lit_for_the_hold_then_fades() -> void:
	# The requested feel: after the pool tops back up the ring stays fully lit for stamina_ring_full_hold
	# seconds, THEN fades to the idle alpha — recovery to full registers instead of the gauge blinking out
	# the instant the last point returns. Drive _process by hand at 60 fps.
	var ring = _offtree_ring()
	ring.visible = true
	ring.fill = 0.5
	ring._process(1.0 / 60.0)   # frame 1: prime (adopt lit; the hold timer is cleared on an unprimed frame)
	ring._process(1.0 / 60.0)   # frame 2: PRIMED + draining -> arms the hold for the coming refill
	assert_almost_eq(ring._alpha_mult, 1.0, 0.001, "a draining pool is fully lit")
	# Top the pool up. Through (almost) the whole hold window the ring must stay lit, NOT start fading now —
	# without the hold it would already be easing toward the idle alpha (exp(-6*t) is ~0.11 by here).
	ring.fill = 1.0
	var hold_frames: int = int(GameSettings.hud.stamina_ring_full_hold * 60.0)
	for _i in maxi(1, hold_frames - 2):
		ring._process(1.0 / 60.0)
	assert_almost_eq(ring._alpha_mult, 1.0, 0.001,
		"inside the post-refill hold the ring stays fully lit — the fade is delayed a split second, not immediate")
	# Let the hold expire and the fade run out.
	for _i in 90:
		ring._process(1.0 / 60.0)
	assert_almost_eq(ring._alpha_mult, _idle_alpha(), 0.001,
		"once the hold expires the ring fades to the idle alpha as before")
	ring.free()

func test_an_adopted_full_pool_does_not_linger() -> void:
	# The hold must obey the SAME "watched only" contract as the fade priming: a full pool that appears while
	# the ring was hidden (revive / level load / bar-mode swap) must land straight on the idle alpha with no
	# linger, even if the ring had armed a hold before it was hidden.
	var ring = _offtree_ring()
	ring.visible = true
	ring.fill = 0.5
	ring._process(1.0 / 60.0)
	ring._process(1.0 / 60.0)   # primed + draining -> hold armed
	ring.visible = false
	ring._process(1.0 / 60.0)   # hidden: un-primes
	ring.fill = 1.0             # off-screen refill
	ring.visible = true
	ring._process(1.0 / 60.0)   # first visible frame: adopt, hold cleared -> no linger
	assert_almost_eq(ring._alpha_mult, _idle_alpha(), 0.001,
		"an adopted full pool skips the hold entirely — it never lingers lit over a revive/level load")
	ring.free()

# --- the SPEND CHIP: geometry ------------------------------------------------------------------------

func test_chip_span_covers_the_arc_between_the_fill_tip_and_the_head() -> void:
	# Default gauge (start 180, sweep -180): fill 0.5 ends at the bottom (90 deg), a head of 0.8 ends at
	# 36 deg. The band is exactly the arc between them — it starts where the coloured fill STOPS.
	var s: Vector2 = RING.chip_span(0.5, 0.8, 180.0, -180.0)
	assert_almost_eq(s.x, deg_to_rad(90.0), 0.0001, "the band starts at the live fill's tip")
	assert_almost_eq(s.y, deg_to_rad(36.0), 0.0001, "…and ends where the fill WAS before the spend")

func test_chip_span_collapses_when_nothing_is_owed() -> void:
	var same: Vector2 = RING.chip_span(0.6, 0.6, 180.0, -180.0)
	assert_almost_eq(same.y, same.x, 0.0001, "a head level with the fill spans zero degrees — a rested pool paints no band")
	var stale: Vector2 = RING.chip_span(0.6, 0.2, 180.0, -180.0)
	assert_almost_eq(stale.y, stale.x, 0.0001,
		"a head BELOW the fill (a stale or unstamped value) also collapses — it can never paint a backwards arc")

func test_stamina_chip_band_tiles_the_track_with_the_fill() -> void:
	# The corner bar's half of the same geometry: (x, width) inside a track of the given width.
	var band: Vector2 = UI.stamina_chip_band(100.0, 0.4, 0.9)
	assert_almost_eq(band.x, 40.0, 0.001, "the band starts exactly at the fill's right edge — no gap, no overlap")
	assert_almost_eq(band.y, 50.0, 0.001, "…and is as wide as the spend it represents")
	assert_almost_eq(band.x + band.y, 90.0, 0.001, "fill + band together end at the pre-spend level")

func test_stamina_chip_band_is_empty_when_nothing_is_owed_and_never_overhangs() -> void:
	assert_almost_eq(UI.stamina_chip_band(100.0, 0.5, 0.5).y, 0.0, 0.001, "a rested pool has no band (the hide test)")
	assert_almost_eq(UI.stamina_chip_band(100.0, 0.5, 0.2).y, 0.0, 0.001, "a head below the fill is clamped away, never negative")
	var over: Vector2 = UI.stamina_chip_band(100.0, 0.9, 3.0)
	assert_almost_eq(over.x + over.y, 100.0, 0.001, "an over-unity head is clamped to the track — the band can never overhang it")

# --- the SPEND CHIP: the hold/slide tracker -------------------------------------------------------------

## Shipped-knob driven, at a fixed 60 fps, so a designer retuning the knobs retunes these tests with them.
func _frames(seconds: float) -> int:
	return int(round(seconds * 60.0))

func test_the_shard_holds_at_the_spend_then_slides_down_to_the_live_fill() -> void:
	var t = CHIP.new()
	t.sync(1.0)
	var head: float = t.advance(0.7, 1.0 / 60.0)
	assert_almost_eq(head, 1.0, 0.001,
		"the frame you spend, the head STAYS where the fill was — the shard's length IS what that verb cost")
	assert_true(t.has_chip(0.7), "…so there is a shard to paint")
	for _i in maxi(1, _frames(GameSettings.hud.stamina_chip_delay) - 2):
		t.advance(0.7, 1.0 / 60.0)
	assert_almost_eq(t.value, 1.0, 0.001, "inside the hold the shard does not move — it is a receipt, not an animation")
	# Let the hold expire and the slide run well past the distance it actually has to cover.
	var slide_frames := _frames(1.0 / maxf(GameSettings.hud.stamina_chip_speed, 0.001)) + 10
	for _i in slide_frames:
		t.advance(0.7, 1.0 / 60.0)
	assert_almost_eq(t.value, 0.7, 0.001, "the slide lands EXACTLY on the live fill and stops — never below it, never short of it")
	assert_false(t.has_chip(0.7), "…and there is nothing left to paint")
	t = null

func test_a_continuous_drain_parks_one_shard_instead_of_a_dozen_slivers() -> void:
	# Sprinting drops the pool every frame. Each drop RESTARTS the hold clock (never stacks it), so the head
	# stays at the level the sprint STARTED from and the band grows across the whole run — one block that
	# reads "this is what the sprint cost", rather than 60 slivers each sliding on their own clock.
	var t = CHIP.new()
	t.sync(1.0)
	var f := 1.0
	for _i in 30:
		f -= 0.02
		t.advance(f, 1.0 / 60.0)
	assert_almost_eq(t.value, 1.0, 0.001, "the head is still at the pre-sprint level half a second into the drain")
	assert_almost_eq(t.value - f, 0.6, 0.001, "and the band spans the whole of what the sprint has burned so far")
	t = null

func test_a_refill_swallows_the_shard_from_the_left() -> void:
	# Recovery needs no animation of its own: the fill climbs back INTO the shard and eats it. The moment
	# they meet the chip is over — no leftover white sitting on top of a full pool.
	var t = CHIP.new()
	t.sync(1.0)
	t.advance(0.5, 1.0 / 60.0)
	assert_true(t.has_chip(0.5), "the spend leaves a band")
	assert_almost_eq(t.advance(0.8, 1.0 / 60.0), 1.0, 0.001, "a partial refill shrinks the shard from the left, head unmoved")
	assert_almost_eq(t.advance(1.0, 1.0 / 60.0), 1.0, 0.001, "a full refill meets the head…")
	assert_false(t.has_chip(1.0), "…and ends the chip")
	t = null

func test_sync_adopts_a_pool_that_moved_off_screen() -> void:
	# The same "never animate a change nobody watched" contract as the ring's _fade_primed latch: ui.gd
	# syncs instead of stepping on every frame the readout is hidden (dialogue, the death cinematic), so a
	# drain the player never saw doesn't come back owing a white shard over the fade-up.
	var t = CHIP.new()
	t.sync(1.0)
	t.advance(0.4, 1.0 / 60.0)
	assert_true(t.has_chip(0.4), "a watched spend owes a shard")
	t.sync(0.4)
	assert_almost_eq(t.value, 0.4, 0.001, "sync adopts the live pool outright")
	assert_false(t.has_chip(0.4), "…owing nothing")
	t.advance(0.4, 1.0 / 60.0)
	assert_false(t.has_chip(0.4), "and the frame after a sync is not a DROP — the adoption itself arms nothing")
	t = null

func test_hud_settings_chip_defaults_clear_before_the_pool_starts_refilling() -> void:
	var h := HudSettings.new()
	assert_eq(Color(h.stamina_chip_color, 1.0), Color(1.0, 1.0, 1.0, 1.0),
		"the just-spent shard is WHITE (user call) — it must read as absence, not as another level on the fill gradient")
	assert_gt(h.stamina_chip_delay, 0.0, "the shard must HOLD long enough to be seen at all")
	assert_gt(h.stamina_chip_speed, 0.0, "…and must actually slide away, or it is a permanent second gauge")
	assert_lt(h.stamina_chip_delay, GameSettings.player_movement.stamina_regen_delay_after_spend,
		"the hold ends BEFORE the post-spend regen freeze does, so the shard is already sliding when the pool starts climbing back — two motions in sequence, not fighting each other")
	h = null

func test_a_fresh_tracker_adopts_its_first_frame_instead_of_reading_it_as_a_spend() -> void:
	# The same "1.0 is a don't-care initialiser, not a level anyone had" argument as the ring's
	# _fade_primed latch — and the same failure it prevents: a HUD built over a pool that ISN'T full (a
	# save loaded half-spent, a level load mid-run) used to paint a phantom shard from full down to the
	# real level on its very first frame, for a spend that never happened.
	var c = CHIP.new()
	assert_almost_eq(c.advance(0.35, 1.0 / 60.0), 0.35, 0.001, "the first live frame lands ON the pool, wherever it is")
	assert_false(c.has_chip(0.35), "…owing nothing")
	# …and the frame after is a normal step again, so a REAL spend still registers.
	assert_almost_eq(c.advance(0.2, 1.0 / 60.0), 0.35, 0.001, "the next drop is a real spend and does leave a shard")
	assert_true(c.has_chip(0.2), "…which is there to paint")
	c = null
