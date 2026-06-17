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
		GoapActionSearch.new(),  # pre {state_investigating}  -> {spot_searched}, cost 0.2
		GoapActionFireArmed.new(),    # pre {state_alerted, can_fight_with_gun:true}  -> {target_engaged}, cost 0.5
		GoapActionFireUnarmed.new(),  # pre {state_alerted, can_fight_with_gun:false} -> {target_engaged}, cost 0.6
		GoapActionFlee.new(),         # pre {is_fleeing, threat_noticed} -> {fled}, cost 0.3
		GoapActionHold.new(),         # pre {}                     -> {idle_done},     cost 0.1 (the floor)
	]

func _combat_goals() -> Array:
	return [
		GoapGoal.new(&"Survive", 3.0, {&"fled": true}),
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

func test_fleeing_and_noticed_selects_survive_over_engage() -> void:
	# A fleer (archetype FLEE or a temperament flip) with a noticed threat RUNS, never fights: Survive(3.0)
	# outranks Engage(2.0). Reproduces the FSM FLEE pre-seam preempting the whole combat dispatch.
	var s := _selected({&"is_fleeing": true, &"threat_noticed": true, &"state_alerted": true, &"can_fight_with_gun": true})
	assert_eq(s[&"goal"], &"Survive", "fleeing + noticed -> Survive outranks every combat goal")
	assert_eq(s[&"action"], &"Flee")

func test_fleeing_but_unaware_falls_to_idle_floor() -> void:
	# Fleeing but nothing noticed yet: Flee's threat_noticed precondition fails, so Survive is infeasible and the
	# fleer idles/wanders -- exactly the FSM (the pre-seam only fires when state != UNAWARE).
	var s := _selected({&"is_fleeing": true, &"threat_noticed": false})
	assert_eq(s[&"goal"], &"Idle", "fleeing + UNAWARE -> Survive infeasible -> Idle floor")
	assert_eq(s[&"action"], &"Hold")

func test_not_fleeing_engages_normally() -> void:
	# Survive is gated on is_fleeing, so a fighter never flees: Engage wins in ALERTED.
	var s := _selected({&"is_fleeing": false, &"threat_noticed": true, &"state_alerted": true, &"can_fight_with_gun": true})
	assert_eq(s[&"goal"], &"Engage", "not fleeing -> Survive infeasible -> Engage")
	assert_eq(s[&"action"], &"FireArmed")

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

func test_goal_priority_order_and_absolutes() -> void:
	# Select by NAME, not array index: the previous index-based version silently stopped comparing Engage vs
	# Investigate once Survive took slot 0, so a reorder/retune that flipped combat priority (a fleer fighting,
	# Detect outranking Engage) would still pass. Pins both the absolute authored values and the total order.
	var by_name := {}
	var ws := GoapWorldState.new({&"hp_frac": 1.0})
	for g in _combat_goals():
		by_name[g.name] = g.priority(ws)
	assert_almost_eq(float(by_name[&"Survive"]), 3.0, 0.001, "Survive 3.0")
	assert_almost_eq(float(by_name[&"Engage"]), 2.0, 0.001, "Engage 2.0")
	assert_almost_eq(float(by_name[&"Investigate"]), 0.4, 0.001, "Investigate 0.4")
	assert_almost_eq(float(by_name[&"Detect"]), 0.3, 0.001, "Detect 0.3")
	assert_almost_eq(float(by_name[&"Idle"]), 0.1, 0.001, "Idle 0.1")
	assert_gt(float(by_name[&"Survive"]), float(by_name[&"Engage"]), "Survive > Engage -> a fleer never fights")
	assert_gt(float(by_name[&"Engage"]), float(by_name[&"Investigate"]), "Engage > Investigate")
	assert_gt(float(by_name[&"Investigate"]), float(by_name[&"Detect"]), "Investigate > Detect")
	assert_gt(float(by_name[&"Detect"]), float(by_name[&"Idle"]), "Detect > Idle")

func test_fleeing_and_detecting_selects_survive_not_detect() -> void:
	# Flee's precondition {is_fleeing, threat_noticed} is perception-agnostic, so a fleer bolts in DETECTING too:
	# Survive(3.0) must preempt Detect(0.3). Catches Flee accidentally gaining a state_alerted gate.
	var s := _selected({&"is_fleeing": true, &"threat_noticed": true, &"state_detecting": true})
	assert_eq(s[&"goal"], &"Survive", "fleeing + DETECTING -> Survive, not Detect")
	assert_eq(s[&"action"], &"Flee")
	assert_ne(s[&"action"], &"Detect", "a fleer never runs the Detect arm")

func test_fleeing_and_investigating_selects_survive_not_investigate() -> void:
	var s := _selected({&"is_fleeing": true, &"threat_noticed": true, &"state_investigating": true})
	assert_eq(s[&"goal"], &"Survive", "fleeing + INVESTIGATING -> Survive, not Investigate")
	assert_eq(s[&"action"], &"Flee")
	assert_ne(s[&"action"], &"Investigate", "a fleer never runs the Investigate arm")
