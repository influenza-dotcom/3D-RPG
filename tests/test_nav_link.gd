extends GutTest

## NavLink drop-in (scripts/components/nav_link.gd): the NavigationLink3D that bridges disconnected navmesh islands so
## NPCs traverse a ledge. These pin the pure, off-tree surface: _apply()'s direction wiring (bidirectional + one-way
## orientation) and the authoring-warning truth table. A bare .new() with NO add_child runs no _ready, so it never
## touches the nav map / physics — safe headless. Actual path-crossing + the ascent launch are playtest/soak territory
## (they need a baked NavigationRegion3D), consistent with test_locomotor.gd.


func test_two_way_is_bidirectional() -> void:
	var link := NavLink.new()
	link.start_position = Vector3(0, 0, 0)
	link.end_position = Vector3(3, 1, 0)
	link.direction = NavLink.Direction.TWO_WAY  # setter -> _apply()
	assert_true(link.bidirectional, "TWO_WAY links let NPCs climb up AND drop down")
	autofree(link)


func test_one_way_down_orients_start_to_the_higher_end() -> void:
	var link := NavLink.new()
	link.start_position = Vector3(0, 0, 0)      # authored LOW as start
	link.end_position = Vector3(3, 2, 0)        # authored HIGH as end
	link.direction = NavLink.Direction.ONE_WAY_DOWN
	assert_false(link.bidirectional, "ONE_WAY_DOWN is not bidirectional")
	assert_true(link.start_position.y >= link.end_position.y,
		"ONE_WAY_DOWN auto-orients so the START is the higher end (the only legal travel dir, start->end, is downward)")
	autofree(link)


func test_one_way_down_leaves_already_oriented_alone() -> void:
	var link := NavLink.new()
	link.start_position = Vector3(3, 2, 0)      # already HIGH as start
	link.end_position = Vector3(0, 0, 0)
	link.direction = NavLink.Direction.ONE_WAY_DOWN
	assert_almost_eq(link.start_position.y, 2.0, 0.001, "an already-correct one-way link isn't re-swapped (idempotent _apply)")
	autofree(link)


func test_traverse_cost_writes_enter_cost() -> void:
	var link := NavLink.new()
	link.traverse_cost = 5.0  # setter -> _apply()
	assert_almost_eq(link.enter_cost, 5.0, 0.001, "traverse_cost drives the inherited A* enter_cost (bias toward ramps)")
	autofree(link)


func test_warns_on_coincident_endpoints() -> void:
	var w := NavLink.warnings_for(Vector3.ZERO, Vector3(0.02, 0.0, 0.0), NavLink.Direction.TWO_WAY, 3.0)
	assert_gt(w.size(), 0, "endpoints on top of each other = nothing to bridge -> warn")


func test_warns_when_span_is_below_agent_max_climb() -> void:
	var w := NavLink.warnings_for(Vector3.ZERO, Vector3(1.0, 0.2, 0.0), NavLink.Direction.TWO_WAY, 3.0)
	assert_gt(w.size(), 0, "a <0.4 m vertical span the bake already connects = redundant link -> warn")


func test_warns_when_two_way_span_is_taller_than_a_jump() -> void:
	var w := NavLink.warnings_for(Vector3(0, 0, 0), Vector3(1.0, 5.0, 0.0), NavLink.Direction.TWO_WAY, 3.0)
	assert_gt(w.size(), 0, "a TWO_WAY link taller than NPCs can jump would stall them -> warn (steer to ONE_WAY_DOWN)")


func test_no_warning_for_a_valid_climbable_two_way_link() -> void:
	var w := NavLink.warnings_for(Vector3(0, 0, 0), Vector3(1.5, 1.2, 0.0), NavLink.Direction.TWO_WAY, 3.0)
	assert_eq(w.size(), 0, "a real, jumpable ledge link is warning-free")


func test_tall_drop_is_valid_as_one_way_down() -> void:
	# The same tall span that warns for TWO_WAY is fine as a drop-only cliff — the too-tall check is TWO_WAY-only.
	var w := NavLink.warnings_for(Vector3(0, 5, 0), Vector3(1.0, 0.0, 0.0), NavLink.Direction.ONE_WAY_DOWN, 3.0)
	assert_eq(w.size(), 0, "a tall ONE_WAY_DOWN drop is legitimate (NPCs fall, don't climb) — no height warning")


# --- Traversal (LAUNCH vs WALK). WALK links are laid over a staircase so NPCs WALK up (Locomotor step-up on the treads)
# instead of leaping; the Locomotor reads walk_traversal() to suppress the ballistic ascent launch. ---

func test_traversal_defaults_to_launch() -> void:
	var link := NavLink.new()
	assert_eq(link.traversal, NavLink.Traversal.LAUNCH, "default is LAUNCH (a bare ledge hop) — WALK is the opt-in stair mode")
	assert_false(link.walk_traversal(), "a LAUNCH link is not walked — the Locomotor still injects the hop")
	autofree(link)


func test_walk_traversal_flag_reports_walk() -> void:
	var link := NavLink.new()
	link.traversal = NavLink.Traversal.WALK
	assert_true(link.walk_traversal(), "a WALK link tells the Locomotor to suppress the launch and let step-up climb the stairs")
	autofree(link)


func test_walk_link_over_a_tall_flight_skips_the_jump_height_warning() -> void:
	# A whole staircase flight is a TALL TWO_WAY span, but it's WALKED, not jumped — the "taller than a jump" warning
	# (which is about the ballistic launch ceiling) must NOT fire for a WALK link laid along the stair footprint.
	var w := NavLink.warnings_for(Vector3(0, 0, 0), Vector3(4.5, 2.5, 0.0), NavLink.Direction.TWO_WAY, 3.0, NavLink.Traversal.WALK)
	assert_eq(w.size(), 0, "a WALK stair link with a real horizontal run is warning-free even when taller than a jump")


func test_near_vertical_walk_link_warns() -> void:
	# A WALK link with climb > run has no shallow stair under it for step-up to climb — warn the designer.
	var w := NavLink.warnings_for(Vector3(0, 0, 0), Vector3(1.0, 2.5, 0.0), NavLink.Direction.TWO_WAY, 3.0, NavLink.Traversal.WALK)
	assert_gt(w.size(), 0, "a near-vertical WALK link (climb > run) has no stairs to walk — warn to lay it along the footprint")


# --- Projection spread (2026-09-12: the load-in freeze) -------------------------------------------------------------
# Every link in a level reaches "the map answers" on the same physics step, so the endpoint projection used to run for
# the WHOLE link set in one step (449 links x 5 full-navmesh queries = a ~1 s physics frame a second after load). It is
# now spread under a shared per-physics-frame budget (NavLink.PROJECT_BUDGET_USEC, _claim_budget). Off-tree: the ledger
# is static and needs no nav map.


func test_first_budget_claim_of_a_physics_frame_always_proceeds() -> void:
	NavLink._budget_frame = -1  # a fresh frame from the ledger's point of view
	NavLink._budget_spent_usec = 999_999
	assert_true(NavLink._claim_budget(), "the first claimant of a frame resets the ledger and proceeds")
	assert_eq(NavLink._budget_spent_usec, 0, "a new frame starts with nothing spent")
	assert_eq(NavLink._budget_frame, Engine.get_physics_frames(), "the ledger is now stamped with this physics frame")


func test_budget_claims_in_the_same_frame_stop_once_the_spend_reaches_the_budget() -> void:
	NavLink._budget_frame = -1
	assert_true(NavLink._claim_budget())
	NavLink._budget_spent_usec = NavLink.PROJECT_BUDGET_USEC - 1
	assert_true(NavLink._claim_budget(), "still under budget -> a later link in the same frame may project")
	NavLink._budget_spent_usec = NavLink.PROJECT_BUDGET_USEC
	assert_false(NavLink._claim_budget(), "at budget -> the rest of the links keep their one-shot for the next frame")
	NavLink._budget_frame = -1  # leave the ledger clean for whatever runs next


func test_physics_process_claims_the_budget_and_spends_two_queries_per_link() -> void:
	# Source-text ratchet (the test_effect_prewarm idiom): the spread only exists if _physics_process gates on the
	# ledger BEFORE it projects, projects through the single-query _project, and probes the map via the shared cache.
	var src := FileAccess.get_file_as_string("res://scripts/components/nav_link.gd")
	var body_start := src.find("func _physics_process(")
	var body_end := src.find("
func ", body_start + 1)
	var body := src.substr(body_start, body_end - body_start)
	var claim := body.find("_claim_budget(")
	var project := body.find("_project(")
	assert_true(claim >= 0, "_physics_process must claim the shared budget")
	assert_true(project > claim, "the claim must come BEFORE the projection, or the spread gates nothing")
	assert_true(body.find("_map_answers(") >= 0, "the map-answers probe goes through the per-frame cache, not one query per link")
	assert_eq(src.count("map_get_closest_point("), 1, "exactly one closest-point query site: _project (the warn reads its answer)")
