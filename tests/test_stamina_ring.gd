extends GutTest

## Radial stamina ring (scripts/ui/stamina_ring.gd) + the ring/bar accessibility mode switch in ui.gd.
## Covers the PURE parts off-tree — arc/angle math, the fill->sweep mapping, the low-colour threshold,
## the idle fade target, the shipped HudSettings defaults, the Settings toggle, and the mode routing on
## a bare UI (no _ready, no scene tree). The on-screen look (the ring hugging the live crosshair, the
## annulus fit against the combat arcs) is playtest territory.

## Loaded BY PATH (not the class_name) so the suite parses even before the editor registers the new
## global class — the same cache-cascade guard the runtime wiring uses.
const RING := preload("res://scripts/ui/stamina_ring.gd")

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
	# Exact lerp endpoints (assert_eq(Color) needs exact values — the memory rule): the expected mid-blend
	# is computed with the SAME lerp the implementation uses, so equality is bit-exact.
	assert_eq(RING.ring_color(1.0, fill_col, low_col), fill_col,
		"a full pool wears the pure fill colour (blue end of the gradient)")
	assert_eq(RING.ring_color(0.0, fill_col, low_col), low_col,
		"an empty pool wears the pure low colour (yellow end)")
	assert_eq(RING.ring_color(0.5, fill_col, low_col), low_col.lerp(fill_col, 0.5),
		"half stamina blends halfway — a continuous gradient, no threshold snap (user call)")
	assert_eq(RING.ring_color(2.0, fill_col, low_col), fill_col,
		"overfull clamps to the fill end rather than extrapolating past it")

func test_alpha_target_idles_only_at_full() -> void:
	assert_almost_eq(RING.alpha_target(1.0, 0.25), 0.25, 0.0001,
		"a full pool rests at the faint idle alpha (a full ring is zero-information)")
	assert_almost_eq(RING.alpha_target(0.9, 0.25), 1.0, 0.0001,
		"any spend pops the ring to fully lit")

# --- shipped defaults ---------------------------------------------------------------------------------

func test_outline_span_pads_both_tips_along_the_sweep() -> void:
	# Positive sweep (to > from): the pad extends BELOW from and ABOVE to.
	var p := RING.outline_span(Vector2(1.0, 2.0), 0.1)
	assert_almost_eq(p.x, 0.9, 0.0001, "positive-sweep outline starts a pad early")
	assert_almost_eq(p.y, 2.1, 0.0001, "…and ends a pad late")
	# Negative sweep (to < from, the shipped -180 gauge): the pad flips with the direction.
	var n := RING.outline_span(Vector2(2.0, 1.0), 0.1)
	assert_almost_eq(n.x, 2.1, 0.0001, "negative-sweep outline starts a pad early (the other way)")
	assert_almost_eq(n.y, 0.9, 0.0001, "…and ends a pad late (the other way)")


func test_hud_settings_ring_defaults_fit_the_crosshair_annulus() -> void:
	var h := HudSettings.new()
	assert_almost_eq(h.stamina_ring_radius, 14.0, 0.001,
		"radius 14 hugs the reticle just outside the body hit ticks' ~11px pop (user call: 23 was too big)")
	assert_almost_eq(h.stamina_ring_thickness, 2.0, 0.001, "stroke 2 — ambient status, thinner than the combat arcs")
	assert_almost_eq(h.stamina_ring_start_deg, 180.0, 0.001, "gauge starts at the LEFT (canvas 180 deg)")
	assert_almost_eq(h.stamina_ring_sweep_deg, -180.0, 0.001,
		"signed sweep -180: left -> bottom -> right, a half-ring under the reticle")
	assert_almost_eq(h.stamina_ring_idle_alpha, 0.0, 0.001,
		"a full ring is FULLY INVISIBLE at rest (user call) — the knob can raise a faint ghost ring back")
	assert_gt(h.stamina_ring_fade_speed, 0.0, "the idle fade must actually ease")
	assert_almost_eq(h.stamina_ring_outline_width, 1.0, 0.001, "a 1px contrast outline keeps the thin arc legible over bright scenes")
	assert_eq(h.stamina_ring_outline_color, Color(0.0, 0.0, 0.0, 0.9), "the outline is near-black (user call)")
	h = null

func test_settings_stamina_ring_default_on_and_toggles() -> void:
	# The RING is the shipped default readout; the corner bar is the accessibility OPT-IN. A fresh
	# Settings (var default, no cfg load) must agree.
	var fresh = load("res://managers/Settings.gd").new()
	assert_true(fresh.stamina_ring_enabled, "the crosshair stamina ring is the shipped DEFAULT (bar = opt-in)")
	fresh.free()
	Settings.set_stamina_ring_enabled(false)
	assert_false(Settings.stamina_ring_enabled, "the classic corner bar can be opted back in")
	Settings.set_stamina_ring_enabled(true)
	assert_true(Settings.stamina_ring_enabled, "and the ring re-enabled")

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
