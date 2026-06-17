extends GutTest

## Drift guard for the combat actions' PLANNING CONTRACT — name / base_cost / preconditions / effects, the
## values the planner reads. The decision-matrix + brain tests prove SELECTION over these; this pins the
## numbers themselves so a typo (Investigate 0.2 vs Detect 0.1 transposed, FireUnarmed dropping below FireArmed,
## a precondition fact renamed) is caught here with a clear message instead of silently reordering the planner.
## Pure off-tree: each action is a plain RefCounted whose _init sets the contract (no host, no tree).

## Exact Dictionary equality without relying on Variant `==` container semantics: same size + every expected
## key present with the expected value (so no extra, missing, or wrong-valued keys).
func _assert_dict(got: Dictionary, expected: Dictionary, msg: String) -> void:
	assert_eq(got.size(), expected.size(), "%s — key count" % msg)
	for k in expected:
		assert_eq(got.get(k), expected[k], "%s — [%s]" % [msg, k])

func test_action_costs_are_pinned() -> void:
	# Planning weights. Drift silently changes which action the planner prefers when plans compete.
	assert_almost_eq(GoapActionHold.new().base_cost, 0.1, 0.0001, "Hold = 0.1 (the idle floor)")
	assert_almost_eq(GoapActionDetect.new().base_cost, 0.1, 0.0001, "Detect = 0.1")
	assert_almost_eq(GoapActionSearch.new().base_cost, 0.2, 0.0001, "Investigate = 0.2 (distinct from Detect)")
	assert_almost_eq(GoapActionFlee.new().base_cost, 0.3, 0.0001, "Flee = 0.3")
	assert_almost_eq(GoapActionFireArmed.new().base_cost, 0.5, 0.0001, "FireArmed = 0.5")
	assert_almost_eq(GoapActionFireUnarmed.new().base_cost, 0.6, 0.0001, "FireUnarmed = 0.6 (above FireArmed)")

func test_action_names_are_pinned() -> void:
	# The decision matrix + library wiring assert on these names; pin them at the source.
	assert_eq(GoapActionHold.new().name, &"Hold")
	assert_eq(GoapActionDetect.new().name, &"Detect")
	assert_eq(GoapActionSearch.new().name, &"Investigate")
	assert_eq(GoapActionFlee.new().name, &"Flee")
	assert_eq(GoapActionFireArmed.new().name, &"FireArmed")
	assert_eq(GoapActionFireUnarmed.new().name, &"FireUnarmed")

func test_action_preconditions_are_pinned() -> void:
	# The perception-state / fleeing gates that drive selection. A renamed fact would make a goal infeasible.
	_assert_dict(GoapActionHold.new().preconditions, {}, "Hold pre (always available, the floor)")
	_assert_dict(GoapActionDetect.new().preconditions, {&"state_detecting": true}, "Detect pre")
	_assert_dict(GoapActionSearch.new().preconditions, {&"state_investigating": true}, "Investigate pre")
	_assert_dict(GoapActionFlee.new().preconditions, {&"is_fleeing": true, &"threat_noticed": true}, "Flee pre")
	_assert_dict(GoapActionFireArmed.new().preconditions, {&"state_alerted": true, &"can_fight_with_gun": true}, "FireArmed pre")
	_assert_dict(GoapActionFireUnarmed.new().preconditions, {&"state_alerted": true, &"can_fight_with_gun": false}, "FireUnarmed pre")

func test_action_effects_are_the_sentinel_goal_facts() -> void:
	# Each effect is the sentinel its goal wants (never sensed by _build_world_state), so the goal is reachable
	# but never pre-satisfied. A wrong/missing effect would make plan() return [] and the goal be skipped.
	_assert_dict(GoapActionHold.new().effects, {&"idle_done": true}, "Hold eff -> Idle")
	_assert_dict(GoapActionDetect.new().effects, {&"threat_faced": true}, "Detect eff")
	_assert_dict(GoapActionSearch.new().effects, {&"spot_searched": true}, "Investigate eff")
	_assert_dict(GoapActionFlee.new().effects, {&"fled": true}, "Flee eff -> Survive")
	_assert_dict(GoapActionFireArmed.new().effects, {&"target_engaged": true}, "FireArmed eff -> Engage")
	_assert_dict(GoapActionFireUnarmed.new().effects, {&"target_engaged": true}, "FireUnarmed eff -> Engage (shared)")
