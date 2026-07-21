extends GutTest

## Locomotor (scripts/components/locomotor.gd): the standalone drop-in pathfinder/mover. Attach under a CharacterBody3D,
## call move_to(), and it routes there on the navmesh. ACTUAL movement is integration/playtest territory (it needs a
## baked NavigationRegion3D + physics ticks — covered by the soak / combat-smoke harnesses), so these pin only the
## host-agnostic surface that IS cheaply checkable off-tree: the public API, the inert defaults, and the config warning
## that steers a designer to a CharacterBody3D parent. A bare .new() runs no _ready, so it's safe headless.


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


func test_link_climb_exports_present_and_sane() -> void:
	var loco := Locomotor.new()  # off-tree, inert
	assert_almost_eq(loco.link_climb_velocity, 4.5, 0.001, "default base launch matches the NPC jump_velocity")
	assert_true(loco.link_climb_min > 0.0, "a positive floor so near-flat links don't trigger a launch")
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


# --- Stair step-up (try_step_up / try_step_down). The actual riser-climb needs a physics space + test_move, so it's
# playtest/soak territory; these pin the OPT-IN default and the early-return gates that run BEFORE any physics query
# (so they're safe off-tree — a body never in a tree must not reach test_move here). ---

func test_step_up_is_opt_in_and_tunable() -> void:
	var loco := Locomotor.new()  # off-tree, inert
	assert_false(loco.enable_step_up, "step-up is OFF by default — a bare mob stays cheap; npc.gd opts in")
	assert_almost_eq(loco.step_up_height, 0.6, 0.001, "default riser matches this project's 0.5 m brush stairs + margin")
	assert_true(loco.step_down_snap >= loco.step_up_height, "step_down_snap >= step_up_height so descents stay grounded")
	assert_true(Locomotor.STEP_MAX_ANGLED_PROBE_EXTRA > 0.0, "diagonal stair approaches get a second into-riser probe")
	assert_true(loco.has_method(&"try_step_up") and loco.has_method(&"try_step_down"), "exposes the step API the host calls")
	loco.free()


func test_step_up_noops_when_disabled_without_touching_physics() -> void:
	# enable_step_up=false returns at the FIRST line, before any test_move — safe on a body that was never in a tree.
	var loco := Locomotor.new()
	var body := CharacterBody3D.new()
	assert_false(loco.try_step_up(body, body.global_transform, Vector3(3, 0, 0), 0.016),
		"disabled step-up no-ops (and never reaches test_move off-tree)")
	loco.free()
	body.free()


func test_step_up_noops_without_horizontal_motion() -> void:
	# enable_step_up=true but zero horizontal velocity returns BEFORE test_move (nothing to step over).
	var loco := Locomotor.new()
	loco.enable_step_up = true
	var body := CharacterBody3D.new()
	assert_false(loco.try_step_up(body, body.global_transform, Vector3(0, -1, 0), 0.016),
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
