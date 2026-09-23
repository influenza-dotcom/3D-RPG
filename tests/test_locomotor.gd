extends GutTest

## Locomotor (scripts/components/locomotor.gd): the standalone drop-in pathfinder/mover. Attach under a CharacterBody3D,
## call move_to(), and it routes there on the navmesh. ACTUAL path-following is integration/playtest territory (it needs
## a baked NavigationRegion3D + physics ticks — covered by the soak / combat-smoke harnesses), so these pin the
## host-agnostic surface that IS cheaply checkable: the pure traversal gates driven with their default knobs, the
## config warning that steers a designer to a CharacterBody3D parent, and the stair step-up in a tiny physics rig.
## A bare .new() runs no _ready, so it's safe headless.


func test_api_surface_and_inert_defaults() -> void:
	var loco := Locomotor.new()  # not added to a tree -> _ready never runs -> stays fully inert
	assert_true(loco.has_method(&"move_to"), "exposes move_to(target)")
	assert_true(loco.has_method(&"stop"), "exposes stop()")
	assert_true(loco.has_method(&"is_moving"), "exposes is_moving()")
	assert_true(loco.has_signal(&"reached_target"), "emits reached_target on arrival")
	assert_true(loco.has_signal(&"path_blocked"), "emits path_blocked on an unreachable target")
	assert_false(loco.is_moving(), "idle by default (no target)")
	assert_eq(loco.desired_velocity, Vector3.ZERO, "no steering until a target is set")
	loco.move_to(Vector3.ONE)  # off-tree (no nav agent) this must no-op, never crash
	assert_false(loco.is_moving(), "move_to off-tree stays inert (no agent to path with)")
	loco.free()


func test_warns_under_a_non_characterbody_parent() -> void:
	var parent := Node3D.new()  # NOT a CharacterBody3D
	add_child_autofree(parent)
	var loco := Locomotor.new()
	parent.add_child(loco)  # freed with the autofreed parent; _ready sees the wrong parent type and stays inert
	assert_gt(loco._get_configuration_warnings().size(), 0, "warns that its parent must be a CharacterBody3D")


func test_no_warning_under_a_characterbody_parent() -> void:
	var body := CharacterBody3D.new()
	add_child_autofree(body)
	var loco := Locomotor.new()
	body.add_child(loco)  # _ready builds its NavigationAgent3D on the body; freed with the autofreed body
	assert_eq(loco._get_configuration_warnings().size(), 0, "no warning under a CharacterBody3D — the valid host")


# --- Link-ascent gate (NavLink traversal). should_climb_link is the pure gate the link_reached driver uses; unlike the
# combat should_nav_hop it has NO allow_hop parameter — that omission IS the fix: an authored link is an explicit
# "traverse here", so an IDLE NPC climbs it. The launch + real crossing are playtest/soak (need a baked region). ---

func test_should_climb_link_fires_on_a_grounded_upward_link() -> void:
	assert_true(Locomotor.should_climb_link(1.5, true, 0.0, 0.4),
		"a real upward span, grounded, off-cooldown -> climb (no combat/allow_hop gate; idle NPCs traverse links)")


func test_should_climb_link_ignores_a_downward_or_flat_link() -> void:
	assert_false(Locomotor.should_climb_link(-2.0, true, 0.0, 0.4), "a DOWN link needs horizontal commit, not launch")
	assert_false(Locomotor.should_climb_link(0.0, true, 0.0, 0.4), "a level link is not a climb")


func test_should_descend_link_fires_only_for_downward_spans() -> void:
	assert_true(Locomotor.should_descend_link(-1.0), "a downward NavLink should arm the step-off commit")
	assert_false(Locomotor.should_descend_link(0.0), "a level link should keep normal path following")
	assert_false(Locomotor.should_descend_link(1.0), "an upward link is handled by the climb launch")


func test_step_height_links_walk_when_step_up_can_handle_them() -> void:
	assert_true(Locomotor.should_walk_link_as_stairs(false, true, 0.5, 1.0, 0.6),
		"a generated one-riser link should let step-up walk it instead of firing a hop")
	assert_false(Locomotor.should_walk_link_as_stairs(false, true, 1.4, 1.0, 0.6),
		"a taller ledge still needs a launch unless authored as WALK")
	assert_true(Locomotor.should_walk_link_as_stairs(true, false, 2.0, 3.0, 0.6),
		"an explicit WALK stair link suppresses the launch even for a full flight")


func test_link_descent_commit_dir_uses_link_run_then_fallbacks() -> void:
	var along_link := Locomotor.link_descent_commit_dir(
		Vector3(0, 3, 0), Vector3(2, 0, 0), Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 1))
	assert_almost_eq(along_link.x, 1.0, 0.001, "a down link with horizontal run commits toward the exit")
	assert_almost_eq(along_link.z, 0.0, 0.001, "link run direction stays flat")
	var from_intent := Locomotor.link_descent_commit_dir(
		Vector3(0, 3, 0), Vector3(0, 0, 0), Vector3(0, 0, -2), Vector3(1, 0, 0), Vector3(0, 0, 1))
	assert_almost_eq(from_intent.x, 0.0, 0.001, "a near-vertical down link falls back to previous chase intent")
	assert_almost_eq(from_intent.z, -1.0, 0.001, "previous intent fallback keeps the body moving off the lip")


func test_link_commit_time_scales_with_link_run() -> void:
	var short := Locomotor.link_commit_time_for_run(Vector3.ZERO, Vector3(1.5, 2.5, 0.0), 4.0)
	assert_true(short >= Locomotor.LINK_DESCENT_COMMIT_TIME,
		"a generated stair link gets at least the base commit window")
	var long := Locomotor.link_commit_time_for_run(Vector3.ZERO, Vector3(6.0, 2.5, 0.0), 4.0)
	assert_true(long > short, "longer up/stair links keep the forced forward drive active longer")
	assert_true(long <= Locomotor.LINK_ASCENT_COMMIT_MAX_TIME,
		"commit time is capped so a stale link does not hijack steering forever")


func test_drop_commit_state_requires_timer_and_direction() -> void:
	var loco := Locomotor.new()
	assert_false(loco.is_drop_committing(), "idle Locomotor is not in forced ledge-drop movement")
	loco._link_descent_t = 0.25
	assert_false(loco.is_drop_committing(), "a timer with no direction is not enough to force body movement")
	loco._link_descent_dir = Vector3.FORWARD
	assert_true(loco.is_drop_committing(), "active timer plus direction lets the NPC body bypass RVO/accel at the rim")
	loco.free()


func test_lower_path_drop_commit_is_combat_only_and_close_to_the_rim() -> void:
	assert_true(Locomotor.should_force_lower_path_drop(true, -1.0, 1.0),
		"a combat chaser near a lower path point should jump/commit over the rim")
	assert_false(Locomotor.should_force_lower_path_drop(false, -1.0, 1.0),
		"non-combat movement should not force a ledge hop fallback")
	assert_false(Locomotor.should_force_lower_path_drop(true, -1.0, 3.0),
		"far from the lower path point, keep following normal nav")
	assert_false(Locomotor.should_force_lower_path_drop(true, 0.0, 1.0),
		"same-level paths do not use the lower ledge hop")


func test_direct_lower_target_drop_is_combat_only_and_distance_gated() -> void:
	assert_true(Locomotor.should_force_direct_lower_target_drop(true, -1.0, 2.0),
		"a combat chaser close to a lower target should vault directly instead of rim-shuffling")
	assert_false(Locomotor.should_force_direct_lower_target_drop(false, -1.0, 2.0),
		"idle/patrol movement should not force direct lower-target drops")
	assert_false(Locomotor.should_force_direct_lower_target_drop(true, -1.0, 8.0),
		"far lower targets keep normal nav/path behavior until the rim is close")
	assert_false(Locomotor.should_force_direct_lower_target_drop(true, 0.0, 2.0),
		"same-level targets do not use direct drop commits")


func test_should_climb_link_ignores_a_sub_step_span() -> void:
	assert_false(Locomotor.should_climb_link(0.3, true, 0.0, 0.4),
		"a span below climb_min is a step the bake/gravity already handle — don't pogo on it")


func test_should_climb_link_needs_ground_and_cooldown() -> void:
	assert_false(Locomotor.should_climb_link(1.5, false, 0.0, 0.4), "can't launch mid-air")
	assert_false(Locomotor.should_climb_link(1.5, true, 0.5, 0.4), "cooldown active -> no machine-gun re-launch")


func test_default_link_launch_is_on_and_matches_the_npc_base_jump() -> void:
	# An authored link's base pop is the NPC's own jump: a profiled NPC's hop comes from NpcData.jump_velocity (the
	# profile stamps it onto the node unconditionally), so a short link climb pops exactly like the combat hop does.
	var loco := Locomotor.new()  # off-tree, inert
	var profile: Resource = load("res://scripts/npc/npc_data.gd").new()
	var npc_jump: float = profile.get(&"jump_velocity")
	profile = null
	assert_gt(loco.link_climb_velocity, 0.0,
		"ship decision: link ascent is ON by default (0 disables it) -- otherwise idle NPCs stall under every authored ledge link")
	assert_almost_eq(loco.link_climb_velocity, npc_jump, 0.001,
		"the link launch's base pop must match the NPC profile's jump_velocity, or a link climb pops differently from the NPC's own hop")
	assert_gt(loco.link_climb_min, 0.0, "a positive floor so near-flat links don't trigger a launch")
	loco.free()


func test_an_npc_with_step_up_has_a_way_over_every_upward_link_span() -> void:
	# The NPC path (enable_step_up ON) answers an upward link in _on_link_reached with WALK (step-up) first, then a
	# LAUNCH. A span neither gate takes is a link A* happily routes across that the body can never cross -- the NPC
	# stands at its foot, STRANDED. Sweep every climb a TWO_WAY link may have (up to NavLink's jump-height warning
	# budget) with the DEFAULT knobs: one of the two must fire, and a launch must actually carry the body to the exit.
	var loco := Locomotor.new()  # off-tree, inert
	var link := NavLink.new()
	var budget := link.climb_warn_budget
	link.free()
	var g := absf(float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)))
	var stranded: Array = []
	var undershot: Array = []
	for i in range(1, int(round(budget / 0.05)) + 1):
		var climb := i * 0.05
		var walks := Locomotor.should_walk_link_as_stairs(false, true, climb, 2.0, loco.step_up_height)
		var launches := Locomotor.should_climb_link(climb, true, 0.0, loco.link_climb_min)
		if not walks and not launches:
			stranded.append(snappedf(climb, 0.01))
		elif launches and not walks:
			var v := Locomotor.jump_velocity_for_climb(climb, -g, loco.link_climb_velocity)
			if v * v / (2.0 * g) < climb:  # ballistic apex of the launch
				undershot.append(snappedf(climb, 0.01))
	assert_eq(stranded, [],
		"upward link spans (m) with NO traversal -- step_up_height and link_climb_min left a dead band between walking and launching")
	assert_eq(undershot, [], "upward link spans (m) whose default launch apex falls short of the exit")
	assert_gt(budget, loco.link_climb_min, "the sweep reached real launch territory (the budget sits above the launch floor)")
	loco.free()


# --- Unreachable lower targets (ledge pursuit). The real step-off needs a navmesh + physics; this pins the pure
# arrival gate that previously made melee NPCs stop at a rim when the player was below but close in X/Z. ---

func test_unreachable_close_lower_target_does_not_count_as_arrived() -> void:
	assert_false(Locomotor.should_stop_at_unreachable_close_target(-1.0, 0.25),
		"a lower unreachable target must keep the ledge-commit steering instead of stopping at the rim")
	assert_true(Locomotor.should_stop_at_unreachable_close_target(0.0, 0.25),
		"a same-level unreachable target still stops when horizontally close")
	assert_true(Locomotor.should_stop_at_unreachable_close_target(1.0, 0.25),
		"an upward unreachable target still uses the old close-stop/hop behavior")
	assert_false(Locomotor.should_stop_at_unreachable_close_target(0.0, 1.0),
		"far unreachable targets keep steering toward the partial-path endpoint")
	assert_false(Locomotor.should_arrive_on_tiny_flat_steering(-1.0),
		"a lower target with tiny horizontal steering must not hit the generic arrived guard after Y is flattened")
	assert_true(Locomotor.should_arrive_on_tiny_flat_steering(0.0),
		"same-level tiny steering still counts as arrival")
	assert_true(Locomotor.should_commit_from_partial_path_to_lower_target(-1.0, 0.5, false),
		"near the end of an unreachable partial path to a lower target, switch from nav-follow to ledge commit")
	assert_false(Locomotor.should_commit_from_partial_path_to_lower_target(-1.0, 2.0, false),
		"far from the partial path end, keep following the navmesh route toward the rim")
	assert_false(Locomotor.should_commit_from_partial_path_to_lower_target(-1.0, 0.5, true),
		"reachable targets stay normal nav paths, even when lower")
	assert_false(Locomotor.should_commit_from_partial_path_to_lower_target(-1.0, 0.5, true, false),
		"a reachable lower path whose endpoint is already on the lower island should not force a ledge commit")
	assert_true(Locomotor.should_commit_from_partial_path_to_lower_target(-1.0, 0.5, true, true),
		"if the partial path endpoint is still above the lower target, commit even before reachability settles")
	assert_false(Locomotor.should_commit_from_partial_path_to_lower_target(0.0, 0.5, false),
		"same-level unreachable targets do not use the ledge-drop commit")


# --- Stair step-up (try_step_up / try_step_down). The riser climb itself is driven in a tiny in-tree physics rig
# (static floor + riser boxes and a capsule body, stepped a few physics frames so test_move sees them). The rest pin
# the OPT-IN default and the early-return gates that run BEFORE any physics query (so they're safe off-tree — a body
# never in a tree must not reach test_move there). ---

func test_step_up_ships_off_for_a_bare_mob_and_its_knobs_agree() -> void:
	var loco := Locomotor.new()  # off-tree, inert
	assert_false(loco.enable_step_up, "ship decision: step-up is OFF by default -- a bare mob stays cheap; npc.gd opts in")
	assert_gte(loco.step_down_snap, loco.step_up_height, "step_down_snap >= step_up_height so descents stay grounded")
	assert_gt(Locomotor.STEP_MAX_ANGLED_PROBE_EXTRA, Locomotor.STEP_MIN_DELTA,
		"the diagonal into-riser probe is only added when its extra reach beats STEP_MIN_DELTA -- a smaller cap silently disables diagonal stair approaches")
	loco.free()


## A static box spanning x in [x0, x1], y in [bottom_y, top_y], z in [z - 3, z + 3]; freed with the test.
func _static_box(x0: float, x1: float, bottom_y: float, top_y: float, z: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(x1 - x0, top_y - bottom_y, 6.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3((x0 + x1) * 0.5, (bottom_y + top_y) * 0.5, z)
	add_child_autofree(body)
	return body


## A stair rig at `z`: a floor, a riser of `riser_h` whose face is at x = 0.5, and a 0.3 m-radius capsule body
## standing 5 cm short of that face. Returns the body.
func _riser_rig(riser_h: float, z: float) -> CharacterBody3D:
	_static_box(-4.0, 4.0, -1.0, 0.0, z)
	_static_box(0.5, 3.0, 0.0, riser_h, z)
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(shape)
	body.position = Vector3(0.15, 0.01, z)
	add_child_autofree(body)
	return body


func test_default_step_up_climbs_a_brush_riser_and_the_tallest_walkable_step_but_not_a_wall() -> void:
	# Drives the REAL riser climb (test_move in a physics space) with the DEFAULT step_up_height. Requirements:
	#  - a 0.5 m brush stair riser (16 TrenchBroom units at FuncGodot's 32:1) is walked;
	#  - so is the tallest step anything hands to step-up: NavLinkPlanner lays WALK links over risers up to its
	#    step_walk_max, and the combat hop refuses any climb <= HOP_MIN_CLIMB -- a taller floor on either side is a
	#    riser NPCs are routed over but can neither step nor hop;
	#  - a 1.0 m wall is NOT stepped (that is the hop's / a NavLink's job) and the body is left where it stood.
	var tallest_step := maxf(float(NavLinkPlanner.DEFAULT_BUDGET["step_walk_max"]), Locomotor.HOP_MIN_CLIMB)
	var brush := _riser_rig(0.5, 0.0)
	var tallest := _riser_rig(tallest_step, 10.0)
	var wall := _riser_rig(1.0, 20.0)
	await wait_physics_frames(3)  # let the physics server register the bodies before any test_move
	var loco := Locomotor.new()
	loco.enable_step_up = true
	var push := Vector3(4.0, 0.0, 0.0)  # walking into the riser: 0.4 m of probe this frame

	assert_true(loco.try_step_up(brush, brush.global_transform, push, 0.1), "a 0.5 m brush stair riser is stepped")
	assert_almost_eq(brush.global_position.y, 0.5, 0.02, "...and the body now stands on the tread")
	assert_almost_eq(loco.last_step_rise, 0.49, 0.02, "...reporting the rise it applied (the host eases the snap by it)")

	assert_true(loco.try_step_up(tallest, tallest.global_transform, push, 0.1),
		"a %.2f m riser (planner step_walk_max / HOP_MIN_CLIMB) is stepped -- no dead band between step-up and the hop" % tallest_step)
	assert_almost_eq(tallest.global_position.y, tallest_step, 0.02, "...onto its tread")

	var wall_before := wall.global_position
	assert_false(loco.try_step_up(wall, wall.global_transform, push, 0.1), "a 1.0 m wall is not a stair riser")
	assert_eq(wall.global_position, wall_before, "a refused step leaves the body where it stood")
	assert_eq(loco.last_step_rise, 0.0, "a refused step reports no rise")
	loco.free()


func test_step_up_noops_when_disabled_without_touching_physics() -> void:
	# enable_step_up=false returns at the FIRST line, before any test_move — safe on a body that was never in a tree.
	var loco := Locomotor.new()
	var body := CharacterBody3D.new()
	assert_false(loco.try_step_up(body, Transform3D.IDENTITY, Vector3(3, 0, 0), 0.016),
		"disabled step-up no-ops (and never reaches test_move off-tree)")
	loco.free()
	body.free()


func test_step_up_noops_without_horizontal_motion() -> void:
	# enable_step_up=true but zero horizontal velocity returns BEFORE test_move (nothing to step over).
	var loco := Locomotor.new()
	loco.enable_step_up = true
	var body := CharacterBody3D.new()
	assert_false(loco.try_step_up(body, Transform3D.IDENTITY, Vector3(0, -1, 0), 0.016),
		"no horizontal motion -> no step attempt (early return, no physics query)")
	loco.free()
	body.free()


func test_step_probe_motion_keeps_a_minimum_forward_probe() -> void:
	var loco := Locomotor.new()
	var slow := loco._step_probe_motion(Vector3(0.1, 0.0, 0.0), 0.016)
	assert_almost_eq(slow.length(), Locomotor.STEP_MIN_FORWARD_PROBE, 0.001,
		"slow/stalled bodies still probe far enough forward to find the next tread")
	var fast := loco._step_probe_motion(Vector3(10.0, 0.0, 0.0), 0.1)
	assert_almost_eq(fast.length(), 1.0, 0.001,
		"faster bodies use their actual frame motion once it exceeds the minimum stair probe")
	loco.free()


func test_is_holding_and_is_struggling_read_the_giveup_state() -> void:
	# The blocked-state seams GoapActionSearch (is_struggling -> stop refreshing the investigate clock) and
	# PatrolBehavior (is_holding -> wait, don't advance a post) read via the NPC facades. is_holding = the
	# post-give-up HOLD only; is_struggling = accruing net-progress failures OR in that hold.
	var loco := Locomotor.new()
	assert_false(loco.is_holding(), "fresh mover: not holding")
	assert_false(loco.is_struggling(), "fresh mover: not struggling")

	loco._progress_fail_count = 1  # a net-progress window went nowhere (backstop accruing toward give-up)
	assert_false(loco.is_holding(), "a failed progress window is not yet the give-up HOLD")
	assert_true(loco.is_struggling(), "...but it IS struggling -> the investigate clock must stop refreshing")

	loco._progress_fail_count = 0
	loco._stuck_hold_t = Locomotor.CHASE_STUCK_HOLD_TIME  # gave up: standing still for a beat
	assert_true(loco.is_holding(), "in the give-up hold -> holding")
	assert_true(loco.is_struggling(), "the hold also counts as struggling")
	loco.free()
