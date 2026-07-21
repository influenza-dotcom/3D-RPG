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
