extends GutTest

## GA-4 coordinated group search: an alert distribution hands each ally a different sector phase (TAU*i/n in
## NPC._alert_allies) so a squad sweeps DISTINCT sectors of the shared origin instead of identical breadcrumb
## rings. The breadcrumb-phase math is covered by test_search_state (phase_seed rotates the ring); here we pin
## Perception's sector_phase OVERRIDE seam — begin_search / investigate_point accept it, it drives _search_phase,
## and forget() clears it back to the per-NPC default. The live TAU*i/n distribution is in-tree/playtested.

const PERCEPTION_PATH := "res://scenes/enemies/perception.gd"


func test_default_phase_is_per_npc_not_overridden() -> void:
	var p = load(PERCEPTION_PATH).new()
	assert_true(is_nan(p._sector_phase_override), "no coordinated sector by default")
	assert_false(is_nan(p._search_phase()), "the default search phase is a real per-NPC value (not NAN)")
	p.free()


func test_begin_search_sector_phase_overrides_default() -> void:
	var p = load(PERCEPTION_PATH).new()
	p.begin_search(0.0, 1.5)
	assert_almost_eq(p._search_phase(), 1.5, 0.0001, "a coordinated sector_phase drives the search phase")
	p.free()


func test_investigate_point_forwards_sector_phase() -> void:
	var p = load(PERCEPTION_PATH).new()
	p.investigate_point(Vector3(3.0, 0.0, 4.0), false, 0.0, 2.0)
	assert_almost_eq(p._search_phase(), 2.0, 0.0001, "investigate_point forwards the sector_phase into the search")
	p.free()


func test_nan_sector_phase_keeps_per_npc_default() -> void:
	var p = load(PERCEPTION_PATH).new()
	var default_phase: float = p._search_phase()
	p.begin_search(0.0)  # unspecified sector (NAN) -> no override
	assert_almost_eq(p._search_phase(), default_phase, 0.0001, "an unspecified (NAN) sector keeps the per-NPC default")
	p.free()


func test_solo_search_after_a_squad_sector_reverts_to_per_npc_default() -> void:
	# Regression (adversarial review): a coordinated sector must NOT leak into a later SOLO search on the same NPC.
	# The combat lost-LOS re-search / a fresh noise investigation re-enter begin_search with NAN WITHOUT routing
	# through forget(), so begin_search must itself drop a stale squad sector when a solo (NAN) search begins.
	var p = load(PERCEPTION_PATH).new()
	var default_phase: float = p._search_phase()
	p.begin_search(0.0, 1.5)  # a squad-coordinated sector
	assert_almost_eq(p._search_phase(), 1.5, 0.0001, "the coordinated sector is in effect")
	p.begin_search(0.0)  # a later SOLO search (NAN) — no forget() between them
	assert_almost_eq(p._search_phase(), default_phase, 0.0001, "the solo search reverts to the per-NPC default, not the stale squad sector")
	p.free()


func test_forget_clears_the_sector_override() -> void:
	var p = load(PERCEPTION_PATH).new()
	var default_phase: float = p._search_phase()
	p.begin_search(0.0, 1.5)
	assert_almost_eq(p._search_phase(), 1.5, 0.0001, "override applied")
	p.forget()
	assert_true(is_nan(p._sector_phase_override), "forget() drops the coordinated sector")
	assert_almost_eq(p._search_phase(), default_phase, 0.0001, "...reverting to the per-NPC default")
	p.free()
