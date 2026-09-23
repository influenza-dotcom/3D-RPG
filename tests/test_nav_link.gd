extends GutTest

## NavLink drop-in (scripts/components/nav_link.gd): the NavigationLink3D that bridges disconnected navmesh islands so
## NPCs traverse a ledge. These pin the pure, off-tree surface: _apply()'s direction wiring (bidirectional + one-way
## orientation) and the authoring-warning truth table. A bare .new() with NO add_child runs no _ready, so it never
## touches the nav map / physics — safe headless. The endpoint projection (auto_project's one-shot) is driven in-tree on
## a PRIVATE hand-built nav map (the "In-tree projection" section below). Actual path-crossing + the ascent launch are playtest/soak
## territory (they need a baked level region), consistent with test_locomotor.gd.


func test_switching_a_one_way_drop_back_to_two_way_reopens_the_climb() -> void:
	# A designer who tries ONE_WAY_DOWN on a ledge and flips it back to TWO_WAY must get the climb back: the engine
	# default is already bidirectional, so only a link that was one-way first shows the setter re-opening the way up.
	var link := NavLink.new()
	autofree(link)
	link.start_position = Vector3(0, 0, 0)
	link.end_position = Vector3(3, 1, 0)
	link.direction = NavLink.Direction.ONE_WAY_DOWN
	assert_false(link.bidirectional, "precondition: as ONE_WAY_DOWN the link only lets NPCs drop down")
	link.direction = NavLink.Direction.TWO_WAY  # setter -> _apply()
	assert_true(link.bidirectional, "back on TWO_WAY, NPCs may climb up AND drop down again")


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
	# Coincident handles are also a "flat" span, so the redundant-link warning would fire for them too. The designer
	# must be told the handles sit on top of each other (drag them apart), not that the link is redundant (delete it).
	var coincident := NavLink.warnings_for(Vector3.ZERO, Vector3(0.02, 0.0, 0.0), NavLink.Direction.TWO_WAY, 3.0)
	var redundant := NavLink.warnings_for(Vector3.ZERO, Vector3(1.0, 0.2, 0.0), NavLink.Direction.TWO_WAY, 3.0)
	assert_eq(redundant.size(), 1, "control: a real but flat 1 m span gets the one redundant-link warning")
	assert_eq(coincident.size(), 1, "endpoints on top of each other = nothing to bridge -> exactly one warning")
	assert_ne(coincident[0], redundant[0],
		"that warning is the coincident-handles one, not the redundant-link advice a flat real span gets")


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

func test_a_dropped_in_link_is_launched_until_the_designer_opts_into_walk() -> void:
	# WALK is the OPT-IN stair mode. A hand-placed link saved without touching `traversal` (a .tscn omits a default)
	# must stay a ballistic ledge hop, both in play (the Locomotor's crossing decision) and in the editor (the jump
	# ceiling warning), or every existing ledge link would silently try to WALK up a wall.
	var link := NavLink.new()
	autofree(link)
	var loco := Locomotor.new()  # off-tree, inert: only its default step-up knob is read
	autofree(loco)
	# One jump taller than the link's warning budget over a long run: far above any step-up riser, shallow enough to walk.
	var climb := link.climb_warn_budget + 1.0
	var run := 2.0 * climb
	link.start_position = Vector3.ZERO
	link.end_position = Vector3(run, climb, 0.0)
	assert_true(climb > loco.step_up_height, "rig: the span is too tall for a step-up to lift the body on its own")
	assert_false(Locomotor.should_walk_link_as_stairs(link.walk_traversal(), true, climb, run, loco.step_up_height),
		"an untouched link is not walked: the Locomotor falls through to the ascent launch")
	assert_eq(link._get_configuration_warnings().size(), 1,
		"an untouched link taller than a jump warns, because it will be LAUNCHED (the jump ceiling applies)")
	# Control: the same link opted into WALK is walked, and the jump ceiling no longer applies to it.
	link.traversal = NavLink.Traversal.WALK
	assert_true(Locomotor.should_walk_link_as_stairs(link.walk_traversal(), true, climb, run, loco.step_up_height),
		"control: once set to WALK the Locomotor walks the same crossing instead of launching")
	assert_eq(link._get_configuration_warnings().size(), 0,
		"control: the same tall span as a WALK stair link is warning-free")


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


# --- In-tree projection (the one-shot _physics_process, driven on a real nav map) ------------------------------------
# A PRIVATE, active nav map with one 20 x 20 m polygon at y = 0, kept away from the origin so the map's "answered the
# origin" failure can never pass for a real answer. Links are pointed at it with set_navigation_map, so nothing touches
# the World3D's own map. Endpoints are authored as NEAR MISSES (inside project_radius) above the floor, so a projection
# that ran is visible as the endpoint dropping onto y = 0.

const FLOOR_PROBE := Vector3(12.0, 0.0, 12.0)
const NEAR_MISS_START := Vector3(6.0, 0.6, 6.0)
const NEAR_MISS_END := Vector3(16.0, 0.3, 16.0)

var _map := RID()
var _region := RID()
var _links: Array[NavLink] = []


func after_each() -> void:
	for link in _links:
		if is_instance_valid(link):
			link.free()  # BEFORE the map RID goes, so no link is left registered on a freed map
	_links.clear()
	if _region.is_valid():
		NavigationServer3D.free_rid(_region)
	if _map.is_valid():
		NavigationServer3D.free_rid(_map)
	_region = RID()
	_map = RID()
	NavLink._budget_frame = -1  # the shared static ledger + map-answer cache, back to "nothing seen yet"
	NavLink._budget_spent_usec = 0
	NavLink._answers_frame = -1
	NavLink._answers = false


## Build the private floor map and drive physics frames until it answers queries truthfully (capped).
func _synced_floor_map() -> RID:
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_map, true)
	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(_region, _map)
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([
		Vector3(2.0, 0.0, 2.0), Vector3(22.0, 0.0, 2.0), Vector3(22.0, 0.0, 22.0), Vector3(2.0, 0.0, 22.0)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	NavigationServer3D.region_set_navigation_mesh(_region, mesh)
	var frames := 0
	while frames < 120 and not NavigationUtils.map_answers_queries(_map, FLOOR_PROBE):
		await get_tree().physics_frame
		frames += 1
	return _map


## An in-tree NavLink on `map` with near-miss endpoints. auto_project=false keeps the engine from ever running its
## one-shot, so a test can drive _physics_process by hand. Waits (capped) until the map has synced past the link's
## own registration, so a "not yet synced since entering the tree" gate can't be what holds the projection back.
func _near_miss_link(map: RID, auto_project: bool) -> NavLink:
	var link := NavLink.new()
	link.auto_project = auto_project
	link.set_navigation_map(map)
	link.start_position = NEAR_MISS_START
	link.end_position = NEAR_MISS_END
	var entry_iteration := NavigationServer3D.map_get_iteration_id(map)
	add_child(link)
	_links.append(link)
	var frames := 0
	while frames < 120 and NavigationServer3D.map_get_iteration_id(map) <= entry_iteration:
		await get_tree().physics_frame
		frames += 1
	return link


func _assert_projected(link: NavLink, why: String) -> void:
	assert_almost_eq(link.start_position, Vector3(NEAR_MISS_START.x, 0.0, NEAR_MISS_START.z), Vector3.ONE * 0.01,
		"start endpoint snapped straight down onto the floor polygon: " + why)
	assert_almost_eq(link.end_position, Vector3(NEAR_MISS_END.x, 0.0, NEAR_MISS_END.z), Vector3.ONE * 0.01,
		"end endpoint snapped straight down onto the floor polygon: " + why)


func _assert_still_authored(link: NavLink, why: String) -> void:
	assert_eq(link.start_position, NEAR_MISS_START, "start endpoint left exactly as authored: " + why)
	assert_eq(link.end_position, NEAR_MISS_END, "end endpoint left exactly as authored: " + why)


func test_auto_project_snaps_near_miss_endpoints_onto_the_navmesh_once_the_map_answers() -> void:
	var map: RID = await _synced_floor_map()
	assert_true(NavigationUtils.map_answers_queries(map, FLOOR_PROBE), "rig: the private floor map answers queries")
	var link: NavLink = await _near_miss_link(map, true)
	var frames := 0
	while frames < 120 and link.is_physics_processing():
		await get_tree().physics_frame
		frames += 1
	assert_false(link.is_physics_processing(),
		"auto_project is a ONE-shot: it switches itself off once it has projected (still on after %d frames)" % frames)
	_assert_projected(link, "an eyeballed near-miss handle must still connect the link to the navmesh at load")


func test_a_spent_frame_budget_holds_the_projection_for_a_later_frame() -> void:
	var map: RID = await _synced_floor_map()
	var link: NavLink = await _near_miss_link(map, false)
	# Another link already spent THIS physics frame's shared budget.
	NavLink._budget_frame = Engine.get_physics_frames()
	NavLink._budget_spent_usec = NavLink.PROJECT_BUDGET_USEC
	link._physics_process(0.0)
	_assert_still_authored(link, "the frame's projection budget was already spent, so this link must wait (the load-in freeze fix)")
	assert_eq(NavLink._budget_spent_usec, NavLink.PROJECT_BUDGET_USEC, "a held link spends nothing from the frame's ledger")
	# Control: the SAME link, map and frame, with the ledger reset as a new physics frame would -> it projects.
	NavLink._budget_frame = -1
	link._physics_process(0.0)
	_assert_projected(link, "with budget available the held one-shot runs on the next frame")


func test_links_in_one_physics_frame_share_one_map_answer() -> void:
	# The "does the map answer yet?" probe is ONE query per physics frame for EVERY link (449 per step otherwise):
	# once a link has asked this frame, the rest take its answer instead of querying the map again.
	var map: RID = await _synced_floor_map()
	var link: NavLink = await _near_miss_link(map, false)
	NavLink._answers_frame = Engine.get_physics_frames()  # an earlier link this frame was told "not answering yet"
	NavLink._answers = false
	link._physics_process(0.0)
	_assert_still_authored(link, "this frame's shared answer says the map isn't populated, so the one-shot is kept, not spent on a lying map")
	# Control: the same link with no answer cached for this frame asks the (truthful) map itself and projects.
	NavLink._answers_frame = -1
	link._physics_process(0.0)
	_assert_projected(link, "with no cached answer the link probes the map, which answers, and projects")


## A link that (re)enters the tree must not project until the nav map has synced SINCE it entered: before that the map
## still holds the world without this link's level — a streamed chunk's neighbours, or the level GameRoot's level cache
## just swapped out — so an endpoint would measure against the wrong floor (a near-miss snaps onto the wrong chunk; a
## returning level printed 248 bogus "off the navmesh" warnings). Driven on the private floor map: it already answers
## (like a neighbouring chunk's floor), so the only thing that can hold a freshly entered link back is that gate.
func test_projection_waits_for_a_map_sync_after_entering_the_tree() -> void:
	var map: RID = await _synced_floor_map()
	assert_true(NavigationUtils.map_answers_queries(map, FLOOR_PROBE), "rig: the map already answers before the link arrives")
	var link := NavLink.new()
	link.auto_project = false  # the one-shot is driven by hand below, never by the engine
	link.set_navigation_map(map)
	link.start_position = NEAR_MISS_START
	link.end_position = NEAR_MISS_END
	var entry_iteration := NavigationServer3D.map_get_iteration_id(map)
	add_child(link)
	_links.append(link)
	link._physics_process(0.0)  # same step it entered on: the map has not synced since
	_assert_still_authored(link, "the map has not synced since the link entered the tree, so it would measure a stale world")
	# Control: the SAME link once the map has synced past its entry projects on the next pass.
	var frames := 0
	while frames < 120 and NavigationServer3D.map_get_iteration_id(map) <= entry_iteration:
		await get_tree().physics_frame
		frames += 1
	assert_true(NavigationServer3D.map_get_iteration_id(map) > entry_iteration, "rig: the map synced after the link entered")
	link._physics_process(0.0)
	_assert_projected(link, "after a map sync since entering the tree, the held one-shot runs")
