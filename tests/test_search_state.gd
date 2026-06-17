extends GutTest

## Off-tree validator for SearchState (stealth Slice 8) — the per-NPC breadcrumb-search scratch held on Perception.
## SearchState is a pure Resource: its ring math takes `origin` as an ARGUMENT and reads no node transform, so every
## test builds it via .new() with NO add_child (CLAUDE.md off-tree rule; sidesteps the GUT-9.6 off-tree-transform
## engine-error trap). Pinned contracts: a fresh state is empty; the two INERT cases (n <= 1 / radius <= 0) collapse
## to the single last-known point (the Slice-8 parity story); regenerate is deterministic + bounded + phase-rotatable;
## current_target/advance/exhausted cycle the trail; clear() wipes it so a re-acquired target inherits no stale ring.

func test_fresh_state_is_empty() -> void:
	var s := SearchState.new()
	assert_eq(s.breadcrumbs.size(), 0, "a fresh SearchState holds no breadcrumbs until regenerate()")
	assert_eq(s.crumb_index, 0, "a fresh SearchState starts at crumb 0")
	assert_eq(s.elapsed, 0.0, "a fresh SearchState has zero elapsed search time")
	assert_eq(s.current_target(), Vector3.ZERO, "with no breadcrumbs current_target falls back to origin (ZERO)")
	s = null

func test_regenerate_single_point_when_one_sample() -> void:
	# sample_points == 1 is the PARITY case: the search is a single breadcrumb AT the last-known spot.
	var s := SearchState.new()
	var origin := Vector3(3, 0, -2)
	s.regenerate(origin, 5.0, 1)
	assert_eq(s.breadcrumbs.size(), 1, "n == 1 yields exactly one breadcrumb (the legacy single-point stare)")
	assert_eq(s.breadcrumbs[0], origin, "the sole breadcrumb is the origin (last-known spot)")
	assert_eq(s.current_target(), origin, "current_target is the origin in the single-point case")
	s = null

func test_regenerate_zero_radius_collapses_to_origin() -> void:
	# radius <= 0 is the OTHER parity case (max_search_radius default 0): even many samples collapse to the point.
	var s := SearchState.new()
	var origin := Vector3(1, 0, 1)
	s.regenerate(origin, 0.0, 5)
	assert_eq(s.breadcrumbs.size(), 1, "radius <= 0 collapses any sample count to a single origin breadcrumb")
	assert_eq(s.breadcrumbs[0], origin, "the collapsed breadcrumb is the origin")
	s = null

func test_regenerate_multi_point_count_and_bounds() -> void:
	var s := SearchState.new()
	var origin := Vector3(10, 0, 10)
	var radius := 6.0
	s.regenerate(origin, radius, 4)
	assert_eq(s.breadcrumbs.size(), 4, "n == 4 with radius > 0 lays four breadcrumbs")
	assert_eq(s.breadcrumbs[0], origin, "crumb 0 is always the origin (re-check the exact spot first)")
	for i in range(s.breadcrumbs.size()):
		var d := origin.distance_to(s.breadcrumbs[i])
		assert_lte(d, radius + 0.001, "breadcrumb %d must sit within the uncertainty radius (got %.2fm)" % [i, d])
	assert_gt(origin.distance_to(s.breadcrumbs[3]), 0.0,
		"outer breadcrumbs must be offset from the origin (the ring fans out, not all stacked on the spot)")
	s = null

func test_regenerate_is_deterministic() -> void:
	# Pure + RNG-free: identical args => byte-identical trail (so behaviour is pinnable and a re-tick doesn't jitter).
	var a := SearchState.new()
	var b := SearchState.new()
	a.regenerate(Vector3(2, 0, 5), 7.0, 5, 0.4)
	b.regenerate(Vector3(2, 0, 5), 7.0, 5, 0.4)
	assert_eq(a.breadcrumbs, b.breadcrumbs, "regenerate is deterministic — identical args produce the identical trail")
	a = null
	b = null

func test_phase_seed_rotates_the_pattern() -> void:
	var a := SearchState.new()
	var b := SearchState.new()
	a.regenerate(Vector3.ZERO, 5.0, 4, 0.0)
	b.regenerate(Vector3.ZERO, 5.0, 4, 1.3)
	assert_ne(a.breadcrumbs[1], b.breadcrumbs[1],
		"a different phase_seed rotates the ring so neighbours hearing the same noise don't sweep identically")
	a = null
	b = null

func test_advance_and_current_target_cycle() -> void:
	var s := SearchState.new()
	s.regenerate(Vector3.ZERO, 5.0, 3)
	assert_eq(s.current_target(), s.breadcrumbs[0], "current_target starts at crumb 0")
	s.advance()
	assert_eq(s.current_target(), s.breadcrumbs[1], "advance moves to crumb 1")
	assert_false(s.exhausted(), "not exhausted while crumbs remain")
	s.advance()
	s.advance()
	assert_true(s.exhausted(), "exhausted once the index passes the last breadcrumb")
	assert_eq(s.current_target(), s.origin, "past the end, current_target falls back to origin (caller regenerates wider)")
	s = null

func test_clear_wipes_the_search() -> void:
	var s := SearchState.new()
	s.regenerate(Vector3(9, 0, 9), 8.0, 5)
	s.elapsed = 2.0
	s.seed_radius = 8.0
	s.crumb_travel_t = 1.5
	s.crumb_dwell_t = 0.8
	s.reached_origin = true
	s.advance()
	s.clear()
	assert_eq(s.breadcrumbs.size(), 0, "clear() empties the breadcrumb trail")
	assert_eq(s.crumb_index, 0, "clear() resets the crumb index")
	assert_eq(s.elapsed, 0.0, "clear() zeroes elapsed search time")
	assert_eq(s.seed_radius, 0.0, "clear() zeroes the uncertainty seed so the next search starts fresh")
	assert_eq(s.crumb_travel_t, 0.0, "clear() zeroes the per-crumb travel timer")
	assert_eq(s.crumb_dwell_t, 0.0, "clear() zeroes the per-crumb dwell timer")
	assert_false(s.reached_origin, "clear() resets reached_origin so the next search re-holds the give-up clock on approach")
	assert_eq(s.origin, Vector3.ZERO, "clear() resets the origin (no stale widened ring leaks into the next investigation)")
	s = null

func test_regenerate_resets_crumb_travel_but_keeps_reached_origin() -> void:
	# A ring regenerate (a fresh lap, wider) restarts the per-crumb timer at index 0 but must NOT reset reached_origin
	# -- the NPC is already AT the search area, so the give-up clock keeps ticking (it must not re-hold and search forever).
	var s := SearchState.new()
	s.reached_origin = true
	s.crumb_travel_t = 2.0
	s.crumb_index = 4
	s.regenerate(Vector3.ZERO, 6.0, 4)
	assert_eq(s.crumb_index, 0, "regenerate restarts at crumb 0")
	assert_eq(s.crumb_travel_t, 0.0, "regenerate resets the per-crumb travel timer")
	assert_true(s.reached_origin, "regenerate (a wider lap) does NOT un-reach the area -- the give-up clock keeps ticking")
	s = null
