extends GutTest

## Perception's breadcrumb-search ORCHESTRATION (stealth Slice 8.3) — the glue that reads GameSettings.search:
## searching_area() (is the feature dialed on?), search_ring_radius() (seed + growth, clamped), advance_search()
## (next crumb; regenerate a wider ring on wrap), tick_crumb_travel() (skip an unreachable crumb after a timeout).
## All pure (no transform/tree reads), tested on a bare off-tree Perception.new(). These methods read the shared
## GameSettings.search resource, so before_each snapshots the dialed fields and after_each restores them — no test
## leaks non-default search tuning into the rest of the suite (which asserts the inert defaults elsewhere).

var _orig := {}

func before_each() -> void:
	var s = GameSettings.search
	_orig = {
		"max": s.max_search_radius, "min": s.min_search_radius, "n": s.sample_points,
		"grow": s.uncertainty_grow_rate, "timeout": s.crumb_timeout,
	}

func after_each() -> void:
	var s = GameSettings.search
	s.max_search_radius = _orig["max"]
	s.min_search_radius = _orig["min"]
	s.sample_points = _orig["n"]
	s.uncertainty_grow_rate = _orig["grow"]
	s.crumb_timeout = _orig["timeout"]

func test_searching_area_reflects_dialed_settings() -> void:
	var p := Perception.new()
	GameSettings.search.min_search_radius = 0.0
	GameSettings.search.max_search_radius = 0.0
	GameSettings.search.sample_points = 1
	p._search.seed_radius = 5.0  # even a fat seed clamps to 0 while max is 0
	assert_false(p.searching_area(), "max_search_radius 0 -> single-point (not an area sweep), even with a seed")
	GameSettings.search.max_search_radius = 8.0
	GameSettings.search.sample_points = 4
	assert_true(p.searching_area(), "positive ring radius + >1 sample points = an area sweep")
	p.free()

func test_search_ring_radius_grows_with_elapsed() -> void:
	var p := Perception.new()
	GameSettings.search.min_search_radius = 0.0
	GameSettings.search.max_search_radius = 20.0
	GameSettings.search.uncertainty_grow_rate = 2.0
	p._search.seed_radius = 1.0
	p._search.elapsed = 0.0
	assert_almost_eq(p.search_ring_radius(), 1.0, 0.001, "at age 0 the radius is just the seed")
	p._search.elapsed = 4.0
	assert_almost_eq(p.search_ring_radius(), 9.0, 0.001, "radius = seed + grow_rate*elapsed (1 + 2*4)")
	p._search.elapsed = 100.0
	assert_almost_eq(p.search_ring_radius(), 20.0, 0.001, "growth is capped at max_search_radius")
	p.free()

func test_advance_search_wraps_and_regenerates() -> void:
	var p := Perception.new()
	GameSettings.search.min_search_radius = 0.0
	GameSettings.search.max_search_radius = 10.0
	GameSettings.search.sample_points = 3
	GameSettings.search.uncertainty_grow_rate = 0.0
	p.last_known_position = Vector3.ZERO
	p.begin_search(4.0)
	assert_eq(p._search.breadcrumbs.size(), 3, "seeds a 3-crumb ring")
	p.advance_search()
	assert_eq(p._search.crumb_index, 1, "advances within the ring")
	p.advance_search()
	p.advance_search()  # index would pass the last crumb -> exhausted -> regenerate
	assert_eq(p._search.crumb_index, 0, "exhausting the ring regenerates a fresh lap at crumb 0")
	assert_eq(p._search.breadcrumbs.size(), 3, "the fresh lap keeps the sample count")
	p.free()

func test_advance_search_widens_the_ring_as_uncertainty_grows() -> void:
	var p := Perception.new()
	GameSettings.search.min_search_radius = 0.0
	GameSettings.search.max_search_radius = 20.0
	GameSettings.search.sample_points = 4
	GameSettings.search.uncertainty_grow_rate = 2.0
	p.last_known_position = Vector3.ZERO
	p.begin_search(3.0)
	var r0 := _max_crumb_dist(p)
	p._search.elapsed = 5.0  # 5s later the ring radius has grown (3 + 2*5 = 13)
	p._search.crumb_index = p._search.breadcrumbs.size()  # force the next advance to wrap
	p.advance_search()
	var r1 := _max_crumb_dist(p)
	assert_gt(r1, r0, "the regenerated lap is wider — the search area grows as the target could have moved further")
	p.free()

func test_tick_crumb_travel_skips_after_timeout() -> void:
	var p := Perception.new()
	GameSettings.search.min_search_radius = 0.0
	GameSettings.search.max_search_radius = 10.0
	GameSettings.search.sample_points = 4
	GameSettings.search.uncertainty_grow_rate = 0.0
	GameSettings.search.crumb_timeout = 1.0
	p.last_known_position = Vector3.ZERO
	p.begin_search(5.0)
	assert_eq(p._search.crumb_index, 0, "starts on crumb 0")
	p.tick_crumb_travel(0.5)
	assert_eq(p._search.crumb_index, 0, "under the timeout the crumb is not skipped")
	p.tick_crumb_travel(0.6)  # cumulative 1.1 >= 1.0
	assert_eq(p._search.crumb_index, 1, "exceeding crumb_timeout skips to the next crumb (unreachable point)")
	assert_almost_eq(p._search.crumb_travel_t, 0.0, 0.001, "advancing resets the per-crumb travel timer")
	p.free()

func _max_crumb_dist(p: Perception) -> float:
	var m := 0.0
	for c in p._search.breadcrumbs:
		m = maxf(m, p._search.origin.distance_to(c))
	return m
