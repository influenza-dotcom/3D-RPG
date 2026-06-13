extends GutTest

## The Engage combat DECISION MATRIX — the core GOAP-testability win the FSM never had. Given a perception
## world-state, the planner must select the action that reproduces the FSM's `match _perception.state` dispatch
## (npc.gd:1413): DETECTING -> Detect, ALERTED+gun -> FireArmed, ALERTED+no-gun -> FireUnarmed, INVESTIGATING ->
## Investigate, and (valid target but still UNAWARE) -> the Idle floor. This pins the SELECTION/PLANNING layer
## where the design's fatal traps lived (goal self-satisfaction, the armed/unarmed split, sentinel reachability).
##
## Scope: the SELECTION/PLANNING layer over the REAL combat action classes — their _init planning halves
## (preconditions/effects/costs) drive select_goal + plan. Each action's act()/is_runtime_valid delegation is
## pinned in its own test_goap_action_*.gd; the in-tree tick() stepping is manual-playtest. The goal priorities
## here are the authored spec (the eventual GoapProfile values the combatant archetype carries).

# --- The combat library (real action classes) + the designed goal priorities ---

func _combat_actions() -> Array:
	return [
		GoapActionDetect.new(),       # pre {state_detecting}      -> {threat_faced},  cost 0.1
		GoapActionInvestigate.new(),  # pre {state_investigating}  -> {spot_searched}, cost 0.2
		GoapActionFireArmed.new(),    # pre {state_alerted, can_fight_with_gun:true}  -> {target_engaged}, cost 0.5
		GoapActionFireUnarmed.new(),  # pre {state_alerted, can_fight_with_gun:false} -> {target_engaged}, cost 0.6
		GoapActionHold.new(),         # pre {}                     -> {idle_done},     cost 0.1 (the floor)
	]

func _combat_goals() -> Array:
	return [
		GoapGoal.new(&"Engage", 2.0, {&"target_engaged": true}),
		GoapGoal.new(&"Investigate", 0.4, {&"spot_searched": true}),
		GoapGoal.new(&"Detect", 0.3, {&"threat_faced": true}),
		GoapGoal.new(&"Idle", 0.1, {&"idle_done": true}),
	]

## Run the full library through select_goal + plan for a world-state; return the chosen goal + first action names.
func _selected(facts: Dictionary) -> Dictionary:
	var ex := GoapExecutor.new()
	ex.setup(_combat_actions(), _combat_goals())
	ex.decide(GoapWorldState.new(facts))
	var goal_name: StringName = ex.current_goal.name if ex.current_goal != null else &""
	var action: GoapAction = ex.current_action()
	var action_name: StringName = action.name if action != null else &""
	ex = null
	return {&"goal": goal_name, &"action": action_name}

func test_detecting_selects_detect() -> void:
	var s := _selected({&"state_detecting": true})
	assert_eq(s[&"goal"], &"Detect", "DETECTING -> Detect goal (FSM npc.gd:1420)")
	assert_eq(s[&"action"], &"Detect", "via the Detect action")

func test_alerted_with_gun_selects_fire_armed() -> void:
	var s := _selected({&"state_alerted": true, &"can_fight_with_gun": true})
	assert_eq(s[&"goal"], &"Engage", "ALERTED + can fight with gun -> Engage (FSM _act_alerted, npc.gd:1425-1426)")
	assert_eq(s[&"action"], &"FireArmed")

func test_alerted_without_gun_selects_fire_unarmed() -> void:
	# The FSM unarmed branch keys on _can_fight_with_gun() (ammo OR a spare clip), NOT is_armed — so an
	# armed-but-dry-with-no-clips NPC lands here too (npc.gd:1427-1431), throwing fists.
	var s := _selected({&"state_alerted": true, &"can_fight_with_gun": false})
	assert_eq(s[&"goal"], &"Engage", "ALERTED + cannot fight with gun -> Engage via fists")
	assert_eq(s[&"action"], &"FireUnarmed")

func test_investigating_selects_investigate() -> void:
	var s := _selected({&"state_investigating": true})
	assert_eq(s[&"goal"], &"Investigate", "INVESTIGATING -> Investigate (FSM npc.gd:1432)")
	assert_eq(s[&"action"], &"Investigate")

func test_unaware_with_target_falls_to_idle_floor() -> void:
	# The seam runs with a valid target while perception is still UNAWARE (detection not yet built / decayed): no
	# combat state flag is set, every combat goal is infeasible, and the Idle floor (Hold) wins — reproducing
	# the FSM UNAWARE arm (scavenge/idle, npc.gd:1414-1419).
	var s := _selected({&"has_target": true})
	assert_eq(s[&"goal"], &"Idle", "no perception flag -> only the Idle floor is feasible")
	assert_eq(s[&"action"], &"Hold")

func test_armed_dry_no_clips_punches_not_idles() -> void:
	# Regression for the Design-3 gap the workflow caught: an ARMED NPC that is dry with no reload supply has
	# can_fight_with_gun=false, so it must select FireUnarmed (punch), NOT fall through to Idle. Splitting on
	# is_armed instead of can_fight_with_gun would have idled it while being shot.
	var s := _selected({&"state_alerted": true, &"can_fight_with_gun": false})
	assert_eq(s[&"action"], &"FireUnarmed", "armed-but-dry -> fists, never the Idle floor")
	assert_ne(s[&"action"], &"Hold", "must not idle a combatant that still has a target")

func test_engage_goal_never_self_satisfies() -> void:
	# target_engaged is a SENTINEL: set only by FireArmed/FireUnarmed, NEVER sensed by _build_world_state. So the
	# Engage goal is reachable-but-never-pre-satisfied — plan() is non-empty exactly when an Engage action's
	# perception precondition holds, instead of returning [] (the self-satisfaction trap that sinks a goal keyed
	# on an already-true fact like has_target).
	var engage := GoapGoal.new(&"Engage", 2.0, {&"target_engaged": true})
	var ws := GoapWorldState.new({&"state_alerted": true, &"can_fight_with_gun": true})
	assert_false(engage.satisfied_by(ws), "Engage is never pre-satisfied (target_engaged is never sensed)")
	var plan := GoapPlanner.plan(ws, _combat_actions(), engage)
	assert_eq(plan.size(), 1, "reachable in exactly one step")
	assert_eq((plan[0] as GoapAction).name, &"FireArmed", "via FireArmed")
	engage = null

func test_priority_orders_engage_over_investigate_over_detect_over_idle() -> void:
	# Each combat goal is feasible ONLY in its own perception state, so in normal play exactly one is feasible at
	# a time. Priority only arbitrates the DETECTING->ALERTED meter-fill boundary, where Engage must win the
	# frame the meter hits 1.0 — exactly the FSM. Pin the total order so select_goal stays deterministic.
	var goals := _combat_goals()
	var ws := GoapWorldState.new({&"hp_frac": 1.0})
	assert_gt(goals[0].priority(ws), goals[1].priority(ws), "Engage(2.0) > Investigate(0.4)")
	assert_gt(goals[1].priority(ws), goals[2].priority(ws), "Investigate(0.4) > Detect(0.3)")
	assert_gt(goals[2].priority(ws), goals[3].priority(ws), "Detect(0.3) > Idle(0.1)")
