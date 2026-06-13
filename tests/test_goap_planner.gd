extends GutTest

## The pure GOAP core — GoapWorldState / GoapAction / GoapGoal / GoapPlanner / GoapProfile. No Node / tree /
## transform, so it's fully off-tree testable (the whole reason the AI brain is moving to GOAP off the
## manual-playtest-only FSM). Actions/goals/states are plain RefCounteds; the profile is a Resource.

func _ws(facts: Dictionary) -> GoapWorldState:
	return GoapWorldState.new(facts)

func _action(n: StringName, action_cost: float, pre: Dictionary, eff: Dictionary) -> GoapAction:
	return GoapAction.new(n, action_cost, pre, eff)

func _goal(n: StringName, p: float, desired: Dictionary) -> GoapGoal:
	return GoapGoal.new(n, p, desired)

# --- GoapWorldState ---

func test_world_state_matches() -> void:
	var ws := _ws({&"can_see": true, &"has_ammo": true})
	assert_true(ws.matches({&"can_see": true}), "subset match")
	assert_false(ws.matches({&"has_ammo": false}), "value mismatch -> no match")
	assert_false(ws.matches({&"in_cover": true}), "absent fact never matches a required value")

func test_world_state_apply_is_immutable() -> void:
	var ws := _ws({&"has_ammo": false})
	var next := ws.apply({&"has_ammo": true})
	assert_true(next.get_fact(&"has_ammo"), "effect applied in the copy")
	assert_false(ws.get_fact(&"has_ammo"), "original state NOT mutated (the planner relies on this)")

func test_world_state_key_is_order_independent() -> void:
	assert_eq(_ws({&"x": true, &"y": false}).key(), _ws({&"y": false, &"x": true}).key(),
		"same facts -> same canonical key regardless of insertion order (the A* dedup key)")

func test_world_state_key_distinguishes_states() -> void:
	# Order-independence alone would pass even if key() collapsed everything to one string -> A* dedup would
	# discard distinct states and the planner could loop / return a wrong plan. Pin that different facts AND
	# different values yield different keys.
	assert_ne(_ws({&"x": true}).key(), _ws({&"y": true}).key(), "different facts -> different key")
	assert_ne(_ws({&"flag": true}).key(), _ws({&"flag": false}).key(), "same fact, different value -> different key")

# --- GoapGoal ---

func test_goal_satisfied_and_unmet() -> void:
	var g := _goal(&"kill", 1.0, {&"target_dead": true})
	assert_true(g.satisfied_by(_ws({&"target_dead": true})))
	assert_eq(g.unmet_count(_ws({&"target_dead": false})), 1)
	assert_eq(g.unmet_count(_ws({&"target_dead": true})), 0)

func test_goal_priority_scales_with_hp_and_temperament() -> void:
	var survive := _goal(&"survive", 1.0, {&"at_safety": true})
	survive.hp_scale = 4.0
	survive.temperament_scale = 2.0
	assert_almost_eq(survive.priority(_ws({&"hp_frac": 1.0, &"temperament": 0.0})), 1.0, 0.001, "healthy + brave -> base only")
	# Badly hurt + cowardly: 1 + 4*(1-0.25) + 2*1.0 = 6.
	assert_almost_eq(survive.priority(_ws({&"hp_frac": 0.25, &"temperament": 1.0})), 6.0, 0.001, "hurt + cowardly -> Survive spikes")

func test_goal_priority_at_dying_and_with_missing_temperament() -> void:
	# Boundaries the mid-range case misses: hp_frac 0.0 (dying -> max hp penalty) and a world-state with NO
	# temperament fact (priority() must default it to 0.0 via get_fact(_, 0.0), not float(null) and crash/mis-scale).
	var survive := _goal(&"survive", 1.0, {&"at_safety": true})
	survive.hp_scale = 4.0
	survive.temperament_scale = 2.0
	assert_almost_eq(survive.priority(_ws({&"hp_frac": 0.0, &"temperament": 1.0})), 7.0, 0.001, "dying + cowardly: 1 + 4*1 + 2*1 = 7 (max boost)")
	assert_almost_eq(survive.priority(_ws({&"hp_frac": 1.0})), 1.0, 0.001, "no temperament fact -> defaults 0.0 -> base only (no crash)")
	assert_almost_eq(survive.priority(_ws({})), 1.0, 0.001, "empty world-state -> hp_frac defaults 1.0 + temperament 0.0 -> base only")
	survive = null

# --- GoapPlanner.plan ---

func test_already_satisfied_returns_empty_plan() -> void:
	assert_eq(GoapPlanner.plan(_ws({&"target_dead": true}), [], _goal(&"kill", 1.0, {&"target_dead": true})).size(), 0)

func test_single_action_plan() -> void:
	var shoot := _action(&"shoot", 1.0, {&"can_see": true, &"has_ammo": true}, {&"target_dead": true})
	var p := GoapPlanner.plan(_ws({&"can_see": true, &"has_ammo": true}), [shoot], _goal(&"kill", 1.0, {&"target_dead": true}))
	assert_eq(p.size(), 1)
	assert_eq((p[0] as GoapAction).name, &"shoot")

func test_chains_actions_to_meet_preconditions() -> void:
	var reload := _action(&"reload", 1.0, {&"has_ammo": false}, {&"has_ammo": true})
	var shoot := _action(&"shoot", 1.0, {&"can_see": true, &"has_ammo": true}, {&"target_dead": true})
	var p := GoapPlanner.plan(_ws({&"can_see": true, &"has_ammo": false}), [reload, shoot], _goal(&"kill", 1.0, {&"target_dead": true}))
	assert_eq(p.size(), 2, "two-step plan")
	assert_eq((p[0] as GoapAction).name, &"reload", "reload first")
	assert_eq((p[1] as GoapAction).name, &"shoot", "then shoot")

func test_prefers_cheaper_path() -> void:
	var cheap := _action(&"shoot", 1.0, {}, {&"target_dead": true})
	var expensive := _action(&"melee", 5.0, {}, {&"target_dead": true})
	var p := GoapPlanner.plan(_ws({}), [expensive, cheap], _goal(&"kill", 1.0, {&"target_dead": true}))
	assert_eq(p.size(), 1)
	assert_eq((p[0] as GoapAction).name, &"shoot", "lower-cost action regardless of array order")

func test_no_plan_when_unsatisfiable() -> void:
	var move := _action(&"move", 1.0, {}, {&"at_target": true})
	assert_eq(GoapPlanner.plan(_ws({}), [move], _goal(&"kill", 1.0, {&"target_dead": true})).size(), 0, "unreachable -> empty, no hang")

# --- GoapPlanner.select_goal ---

func test_select_goal_picks_highest_priority_feasible() -> void:
	var shoot := _action(&"shoot", 1.0, {&"has_target": true}, {&"target_dead": true})
	var hold := _action(&"hold", 0.1, {}, {&"idle_done": true})  # empty preconditions -> always feasible (the floor)
	var engage := _goal(&"engage", 2.0, {&"target_dead": true})
	var idle := _goal(&"idle", 0.1, {&"idle_done": true})
	var chosen := GoapPlanner.select_goal(_ws({&"has_target": true}), [idle, engage], [shoot, hold])
	assert_eq(chosen.name, &"engage", "highest-priority feasible goal wins")

func test_select_goal_falls_to_idle_floor() -> void:
	var shoot := _action(&"shoot", 1.0, {&"has_target": true}, {&"target_dead": true})
	var hold := _action(&"hold", 0.1, {}, {&"idle_done": true})
	var engage := _goal(&"engage", 2.0, {&"target_dead": true})
	var idle := _goal(&"idle", 0.1, {&"idle_done": true})
	var chosen := GoapPlanner.select_goal(_ws({&"has_target": false}), [idle, engage], [shoot, hold])
	assert_eq(chosen.name, &"idle", "no target -> Engage infeasible -> falls to the guaranteed Idle floor, never null")

func test_escort_does_not_outrank_engage_when_target_present() -> void:
	# Regression guard (plan §3.1 fix #3): a following companion WITH a target must FIGHT, not escort.
	var shoot := _action(&"shoot", 1.0, {&"has_target": true}, {&"target_dead": true})
	var tail := _action(&"tail", 0.05, {&"is_following": true, &"has_target": false}, {&"at_leader": true})
	var engage := _goal(&"engage", 1.0, {&"target_dead": true})
	var escort := _goal(&"escort", 2.0, {&"at_leader": true})  # higher priority, but...
	var chosen := GoapPlanner.select_goal(_ws({&"has_target": true, &"is_following": true}), [escort, engage], [shoot, tail])
	assert_eq(chosen.name, &"engage", "with a target, Escort is infeasible (tail needs has_target:false) so Engage wins")

# --- GoapProfile ---

func test_profile_validate_warns_on_unknown_keys() -> void:
	var prof := GoapProfile.new()
	prof.goal_priorities = {&"Engage": 2.0, &"Typoed": 1.0}
	prof.action_cost_overrides = {&"FireTarget": 0.5}
	assert_false(prof.validate(PackedStringArray(["Engage", "Idle"]), PackedStringArray(["FireTarget", "Reload"])),
		"an unknown goal key -> validate false (a typo'd override would otherwise silently no-op)")
	assert_true(prof.validate(PackedStringArray(["Engage", "Idle", "Typoed"]), PackedStringArray(["FireTarget"])),
		"all keys known -> valid")
	prof = null
