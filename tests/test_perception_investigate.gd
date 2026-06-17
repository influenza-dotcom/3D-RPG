extends GutTest

## Perception.investigate_point -- the "go LOOK at this spot" entry point (a softer alert_to that backs stealth
## body-discovery and any future distraction-noise). From UNAWARE/INVESTIGATING it forces INVESTIGATING toward
## the point and re-arms the search clock; from DETECTING/ALERTED it's a no-op (a real, seen target outranks a
## hunch). Fires just_spotted only on the UNAWARE -> aware transition. Pure state machine (no transform/tree
## reads), so it tests on a bare off-tree Perception.

func _perc() -> Perception:
	return Perception.new()

func test_from_unaware_starts_investigating_and_pings() -> void:
	var p := _perc()
	watch_signals(p)
	var spot := Vector3(3.0, 0.0, -2.0)
	p.investigate_point(spot)
	assert_eq(p.state, Perception.State.INVESTIGATING, "UNAWARE + a body/noise -> INVESTIGATING")
	assert_eq(p.last_known_position, spot, "the spot to search is recorded as last_known_position")
	assert_signal_emitted(p, "just_spotted", "first-noticed from UNAWARE fires the '!' sting")
	p.free()

func test_already_investigating_updates_spot_without_repinging() -> void:
	var p := _perc()
	p.investigate_point(Vector3(1.0, 0.0, 0.0))  # UNAWARE -> INVESTIGATING (consumes the one ping)
	watch_signals(p)
	var spot := Vector3(5.0, 0.0, 5.0)
	p.investigate_point(spot)
	assert_eq(p.state, Perception.State.INVESTIGATING, "stays INVESTIGATING")
	assert_eq(p.last_known_position, spot, "a fresher body/noise re-points the search")
	assert_signal_not_emitted(p, "just_spotted", "already aware -> no second '!' sting")
	p.free()

func test_noop_while_detecting() -> void:
	var p := _perc()
	p.state = Perception.State.DETECTING
	p.last_known_position = Vector3.ZERO
	p.investigate_point(Vector3(9.0, 0.0, 9.0))
	assert_eq(p.state, Perception.State.DETECTING, "a body can't downgrade an in-progress sighting")
	assert_eq(p.last_known_position, Vector3.ZERO, "and doesn't steer the last-known spot off the real target")
	p.free()

func test_noop_while_alerted() -> void:
	var p := _perc()
	p.state = Perception.State.ALERTED
	p.investigate_point(Vector3(9.0, 0.0, 9.0))
	assert_eq(p.state, Perception.State.ALERTED, "a locked-on enemy ignores a body on the floor")
	p.free()

func test_non_alerting_investigate_skips_the_spotted_sting() -> void:
	# A seen BODY investigates QUIETLY (alerting=false): it still goes INVESTIGATING toward the spot, but does
	# NOT fire just_spotted -- so it can't masquerade as an enemy "!" sighting or fire the combat detection
	# bark (body-discovery owns its own "Hey -- a body!" line). Noise keeps the default alerting=true sting.
	var p := _perc()
	watch_signals(p)
	var spot := Vector3(2.0, 0.0, 6.0)
	p.investigate_point(spot, false)
	assert_eq(p.state, Perception.State.INVESTIGATING, "still walks over to search the spot")
	assert_eq(p.last_known_position, spot, "still records where to search")
	assert_signal_not_emitted(p, "just_spotted", "a quiet (body) investigation must NOT fire the enemy '!' sting")
	p.free()

# --- Search seam (stealth Slice 8.1, inert) -------------------------------------------------------------------
# The breadcrumb-search scratch (_search) + its query methods, layered onto INVESTIGATING. At the inert
# SearchSettings defaults (max_search_radius 0 / sample_points 1 / intensity_curve null) the search is a single
# point AT the last-known spot with flat energy — today's stare. All off-tree-safe (no transform/tree reads).

func test_investigate_point_entry_seeds_the_search() -> void:
	var p := _perc()
	var spot := Vector3(2.0, 0.0, 6.0)
	p.investigate_point(spot)
	assert_eq(p._search.origin, spot, "entering INVESTIGATING seeds the search origin at the spot")
	assert_eq(p._search.breadcrumbs.size(), 1, "and lays the (inert) single breadcrumb")
	assert_eq(p._search.elapsed, 0.0, "a fresh search starts with zero elapsed age")
	p.free()

func test_begin_search_single_point_at_inert_defaults() -> void:
	var p := _perc()
	var spot := Vector3(4.0, 0.0, -7.0)
	p.last_known_position = spot
	p.begin_search()
	assert_eq(p._search.breadcrumbs.size(), 1, "inert defaults (sample_points 1) lay a single breadcrumb")
	assert_eq(p._search.current_target(), spot, "the single breadcrumb sits AT the last-known spot (parity)")
	p.free()

func test_search_ring_radius_is_zero_at_inert_defaults() -> void:
	var p := _perc()
	p.begin_search(5.0)  # even a non-zero seed clamps to 0 while max_search_radius is 0 (the master inert switch)
	assert_eq(p.search_ring_radius(), 0.0,
		"max_search_radius 0 forces the ring to a point regardless of the seed (today's single-point search)")
	p.free()

func test_forget_clears_the_search() -> void:
	var p := _perc()
	p.investigate_point(Vector3(5.0, 0.0, 5.0))
	p._search.elapsed = 2.0
	p.forget()
	assert_eq(p.state, Perception.State.UNAWARE, "forget drops to UNAWARE")
	assert_eq(p._search.breadcrumbs.size(), 0,
		"forget clears the breadcrumb trail so no stale widened ring leaks into the next investigation")
	assert_eq(p._search.elapsed, 0.0, "forget zeroes the search age")
	p.free()

func test_search_progress_maps_the_give_up_clock() -> void:
	var p := _perc()
	p._investigate_t = p.forget_time  # just (re)armed
	assert_almost_eq(p.search_progress(), 0.0, 0.001, "a freshly-armed search reads progress ~0 (frantic)")
	p._investigate_t = 0.0  # clock run out
	assert_almost_eq(p.search_progress(), 1.0, 0.001, "an exhausted give-up clock reads progress ~1 (giving up)")
	p.free()

func test_search_intensity_is_flat_one_with_null_curve() -> void:
	# The parity default: no intensity_curve -> flat 1.0 (full energy, no falloff), and NO crash on a null .sample().
	var p := _perc()
	p._investigate_t = p.forget_time * 0.5  # mid-search
	assert_eq(p.search_intensity(), 1.0,
		"a null intensity_curve (the default) reads as flat 1.0 — full energy, no falloff, no null-sample crash")
	p.free()
