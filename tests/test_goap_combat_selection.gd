extends GutTest

## The Engage combat DECISION MATRIX — the core GOAP-testability win the FSM never had. Given a perception
## world-state, the planner must select the action that reproduces the (now-removed) FSM `match _perception.state`
## dispatch: DETECTING -> Detect, ALERTED+gun -> FireArmed, ALERTED+no-gun -> FireUnarmed, INVESTIGATING ->
## Investigate, and (valid target but still UNAWARE) -> the Idle floor. This pins the SELECTION/PLANNING layer
## where the design's fatal traps lived (goal self-satisfaction, the armed/unarmed split, sentinel reachability).
##
## Scope: the SELECTION/PLANNING layer over the SHIPPED combat library — GoapLibrary.build_actions/build_goals with
## no profile, i.e. exactly what npc.gd hands its executor. The real action classes' _init planning halves
## (preconditions/effects/costs) and the library's authored goal priorities drive select_goal + plan, so a retune or
## a dropped action in goap_library.gd fails the matrix here. Each action's act()/is_runtime_valid delegation is
## pinned in its own test_goap_action_*.gd; the in-tree tick() stepping is manual-playtest. One case (armed-but-dry)
## senses its facts off an off-tree NPC through GoapExecutor._build_world_state instead, because the split it
## protects lives in that sensor rather than in the planner.

const GoapLibrary := preload("res://scripts/npc/goap/goap_library.gd")
const NPC_PATH := "res://scripts/npc/npc.gd"
const PISTOL := preload("res://resources/weapons/pistol.tres")

# --- The shipped combat library (no GoapProfile = the authored defaults every combatant starts from) ---

func _combat_actions() -> Array:
	return GoapLibrary.build_actions()

func _combat_goals() -> Array:
	return GoapLibrary.build_goals()

## The shipped goal called `goal_name`, or null.
func _shipped_goal(goal_name: StringName) -> GoapGoal:
	for g in _combat_goals():
		if (g as GoapGoal).name == goal_name:
			return g
	return null

## Run the full library through select_goal + plan for a world-state; return the chosen goal + first action names.
func _selected(facts: Dictionary) -> Dictionary:
	return _selected_for(GoapWorldState.new(facts))

## The same selection over a world-state SENSED off a real host by GoapExecutor._build_world_state.
func _selected_from_host(host: Node) -> Dictionary:
	return _selected_for(GoapExecutor.new()._build_world_state(host))

func _selected_for(ws: GoapWorldState) -> Dictionary:
	var ex := GoapExecutor.new()
	ex.setup(_combat_actions(), _combat_goals())
	ex.decide(ws)
	var goal_name: StringName = ex.current_goal.name if ex.current_goal != null else &""
	var action: GoapAction = ex.current_action()
	var action_name: StringName = action.name if action != null else &""
	ex = null
	return {&"goal": goal_name, &"action": action_name}

func test_detecting_selects_detect() -> void:
	var s := _selected({&"state_detecting": true})
	assert_eq(s[&"goal"], &"Detect", "DETECTING -> Detect goal (former FSM DETECTING arm)")
	assert_eq(s[&"action"], &"Detect", "via the Detect action")

func test_alerted_with_gun_selects_fire_armed() -> void:
	var s := _selected({&"state_alerted": true, &"can_fight_with_gun": true})
	assert_eq(s[&"goal"], &"Engage", "ALERTED + can fight with gun -> Engage via the FireArmed action")
	assert_eq(s[&"action"], &"FireArmed")

func test_alerted_without_gun_selects_fire_unarmed() -> void:
	# The FSM unarmed branch keys on _can_fight_with_gun() (ammo OR a spare clip), NOT is_armed — so an
	# armed-but-dry-with-no-clips NPC lands here too, throwing fists.
	var s := _selected({&"state_alerted": true, &"can_fight_with_gun": false})
	assert_eq(s[&"goal"], &"Engage", "ALERTED + cannot fight with gun -> Engage via fists")
	assert_eq(s[&"action"], &"FireUnarmed")

func test_investigating_selects_investigate() -> void:
	var s := _selected({&"state_investigating": true})
	assert_eq(s[&"goal"], &"Investigate", "INVESTIGATING -> Investigate (former FSM INVESTIGATING arm)")
	assert_eq(s[&"action"], &"Investigate")

func test_unaware_with_target_falls_to_idle_floor() -> void:
	# The seam runs with a valid target while perception is still UNAWARE (detection not yet built / decayed): no
	# combat state flag is set, every combat goal is infeasible, and the Idle floor (Hold) wins — reproducing
	# the former FSM UNAWARE arm (scavenge/idle).
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

## An off-tree ALERTED combatant (no _ready — the test_npc_combat._off_tree_armed_npc idiom) still HOLDING a pistol
## whose magazine is empty, with `spare_clips` pistol clips in its backpack. Every read _build_world_state makes is
## the real one: is_armed off the backpack's equipped item, _can_fight_with_gun off the hub's Ammo and that backpack.
func _alerted_dry_pistol_npc(spare_clips: int, target: Node3D) -> Node:
	var npc = load(NPC_PATH).new()
	var bag := CharacterInventory.new()
	npc.add_child(bag)
	npc.inventory = bag
	var gun := ItemDb.make_weapon_item(PISTOL)
	bag.add(gun)
	bag.equip_item(gun)  # marks equipped_item (the equip signal is unwired off-tree; the marker still sets)
	if spare_clips > 0:
		bag.add(ItemDb.ammo_item_for(PISTOL.caliber), spare_clips)
	var hub := Weapon.new()
	var clip := Ammo.new()
	clip.current_weapon = PISTOL
	clip.current_ammo = 0  # the magazine is dry
	clip.character = npc   # the wielder whose backpack a reload would draw from
	hub.add_child(clip)
	hub.ammo = clip
	npc.add_child(hub)
	npc._weapon = hub
	var perception := Perception.new()
	perception.state = Perception.State.ALERTED
	npc.add_child(perception)
	npc._perception = perception
	npc._target = target
	npc.hp = npc.max_hp
	return npc

func test_armed_dry_no_clips_punches_not_idles() -> void:
	# Regression for the Design-3 gap the workflow caught: an NPC still HOLDING its gun but dry with no reload supply
	# must fight with its fists, not keep pulling a dead trigger and not fall through to Idle. The split lives in the
	# SENSOR (_build_world_state's can_fight_with_gun <- NPC._can_fight_with_gun: ammo OR a spare clip), so the facts
	# are sensed off a real NPC here rather than written by hand: sensing is_armed instead would call this NPC able
	# to fight with its gun, plan FireArmed, and leave it clicking an empty pistol while being shot.
	var target := Node3D.new()
	var dry = _alerted_dry_pistol_npc(0, target)
	assert_true(dry.is_armed(), "precondition: the dry NPC still HOLDS its pistol — this is the armed-but-dry case, not a disarm")
	var s := _selected_from_host(dry)
	assert_eq(s[&"goal"], &"Engage", "an ALERTED NPC with a target engages, gun or no gun")
	assert_eq(s[&"action"], &"FireUnarmed", "armed-but-dry with no spare clip -> fists, never the dry gun and never the Idle floor")
	# Control: the same body with ONE spare clip can reload, so the sensor keeps it on the gun. Without this, a sensor
	# that never reported a usable gun at all would pass the case above.
	var reloadable = _alerted_dry_pistol_npc(1, target)
	assert_eq(_selected_from_host(reloadable)[&"action"], &"FireArmed",
		"control: an empty magazine WITH a spare clip in the backpack still fights with the gun (it reloads)")
	dry.free()
	reloadable.free()
	target.free()

func test_engage_goal_never_self_satisfies() -> void:
	# target_engaged is a SENTINEL: set only by FireArmed/FireUnarmed, NEVER sensed by _build_world_state. So the
	# Engage goal is reachable-but-never-pre-satisfied — plan() is non-empty exactly when an Engage action's
	# perception precondition holds, instead of returning [] (the self-satisfaction trap that sinks a goal keyed
	# on an already-true fact like has_target).
	# Uses the SHIPPED Engage goal, and a world-state carrying has_target=true exactly as _build_world_state senses it
	# for an NPC with a target, so a goal re-keyed on that sensed fact fails here instead of silently idling combat.
	var engage := _shipped_goal(&"Engage")
	assert_true(engage != null, "the shipped library must build an Engage goal")
	if engage == null:
		return
	var ws := GoapWorldState.new({&"has_target": true, &"state_alerted": true, &"can_fight_with_gun": true})
	assert_false(engage.satisfied_by(ws), "Engage is never pre-satisfied by sensed facts (target_engaged is a sentinel)")
	var plan := GoapPlanner.plan(ws, _combat_actions(), engage)
	assert_eq(plan.size(), 1, "reachable in exactly one step")
	if plan.size() == 1:
		assert_eq((plan[0] as GoapAction).name, &"FireArmed", "via FireArmed")
	engage = null

func test_every_goal_feasible_at_once_resolves_by_the_shipped_priority_order() -> void:
	# The priority ORDER, driven through select_goal instead of read off the numbers: make every combat goal feasible
	# in one world-state and peel the winners off. A retune that keeps the order stays green; a reorder that flips
	# combat (a fleer fighting, a search outranking a gunfight, the Idle floor beating a noticed threat) fails.
	var all_on := {&"is_fleeing": true, &"threat_noticed": true, &"state_alerted": true,
		&"can_fight_with_gun": true, &"state_investigating": true, &"state_detecting": true}
	assert_eq(_selected(all_on)[&"goal"], &"Survive", "with every goal feasible a fleer RUNS -- Survive tops the order")
	var fighter := all_on.duplicate()
	fighter[&"is_fleeing"] = false
	assert_eq(_selected(fighter)[&"goal"], &"Engage",
		"a non-fleer with a live target FIGHTS -- Engage outranks Investigate/Detect even when those are feasible too")
	var suspicious := fighter.duplicate()
	suspicious[&"state_alerted"] = false
	var searched: StringName = _selected(suspicious)[&"goal"]
	assert_true(searched == &"Investigate" or searched == &"Detect",
		"a suspicious NPC reacts (Investigate/Detect) -- the Idle floor must never outrank a noticed threat, got %s" % searched)

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
