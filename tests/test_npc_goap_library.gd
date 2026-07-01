extends GutTest

## NPC GOAP library wiring — pins that _build_goap_actions / _build_goap_goals assemble the FULL migrated combat
## set, the same library the decision-matrix (test_goap_combat_selection) and brain (test_goap_combat_brain)
## tests assert selection over. Guards against an action/goal silently dropping out of the executor build.
##
## Built off-tree via load(...).new() WITHOUT add_child and WITHOUT _ready (per CLAUDE.md — _ready instantiates
## weapon.tscn/nav/audio and mutates shared statics). The builders are pure: they only construct RefCounteds.

const NPC_SCRIPT := "res://scripts/npc/npc.gd"
const GoapLibrary := preload("res://scripts/npc/goap/goap_library.gd")

func _names(items: Array) -> Array:
	var out: Array = []
	for it in items:
		out.append(it.name)
	return out

func test_build_goap_actions_is_the_full_combat_library() -> void:
	var npc = load(NPC_SCRIPT).new()
	var names := _names(npc._build_goap_actions())
	assert_eq(names.size(), 6, "six combat actions wired into the executor")
	assert_has(names, &"Hold", "the UNAWARE-at-seam idle floor")
	assert_has(names, &"Detect", "the DETECTING arm")
	assert_has(names, &"Investigate", "the INVESTIGATING arm")
	assert_has(names, &"FireArmed", "the ALERTED armed arm")
	assert_has(names, &"FireUnarmed", "the ALERTED unarmed arm")
	assert_has(names, &"Flee", "the SURVIVE/flee arm")
	npc.free()

func test_build_goap_goals_is_the_full_combat_set() -> void:
	var npc = load(NPC_SCRIPT).new()
	var names := _names(npc._build_goap_goals())
	assert_eq(names.size(), 5, "five goals wired")
	assert_has(names, &"Survive", "fleeing (highest priority)")
	assert_has(names, &"Engage", "ALERTED")
	assert_has(names, &"Investigate", "INVESTIGATING")
	assert_has(names, &"Detect", "DETECTING")
	assert_has(names, &"Idle", "the always-feasible floor")
	npc.free()

func test_build_goap_goals_priorities_are_pinned() -> void:
	# The SOURCE-OF-TRUTH authored priorities (the matrix/brain tests use local copies that could drift from
	# this). A reorder here flips real combat behavior: Survive must top the order so a fleer runs, and Engage
	# must outrank Investigate/Detect so a fighter fights.
	var npc = load(NPC_SCRIPT).new()
	var ws := GoapWorldState.new({&"hp_frac": 1.0})
	var by_name := {}
	for g in npc._build_goap_goals():
		by_name[g.name] = g.priority(ws)
	assert_almost_eq(float(by_name[&"Survive"]), 3.0, 0.001, "Survive 3.0 (highest)")
	assert_almost_eq(float(by_name[&"Engage"]), 2.0, 0.001, "Engage 2.0")
	assert_almost_eq(float(by_name[&"Investigate"]), 0.4, 0.001, "Investigate 0.4")
	assert_almost_eq(float(by_name[&"Detect"]), 0.3, 0.001, "Detect 0.3")
	assert_almost_eq(float(by_name[&"Idle"]), 0.1, 0.001, "Idle 0.1")
	npc.free()

## Build a GoapGoalPriority / GoapActionCost dropdown row (the override shape that replaced the free-text dicts).
func _gpri(g: String, p: float) -> GoapGoalPriority:
	var r := GoapGoalPriority.new()
	r.goal = g
	r.priority = p
	return r

func _acost(a: String, c: float) -> GoapActionCost:
	var r := GoapActionCost.new()
	r.action = a
	r.cost = c
	return r

func test_goap_profile_overrides_goal_priority_and_action_cost() -> void:
	# Designer-first: a GoapProfile retunes priorities/costs per archetype, no code. Overrides are dropdown ROWS
	# (GoapGoalPriority / GoapActionCost) now, not free-text Dictionary keys -- the row's String name matches the
	# goal/action StringName by value, so there's no String-vs-StringName key-hash footgun to tolerate.
	var npc = load(NPC_SCRIPT).new()
	var prof := GoapProfile.new()
	prof.goal_priorities.assign([_gpri("Survive", 5.0)])        # a coward
	prof.action_cost_overrides.assign([_acost("Flee", 0.05)])   # cheaper flee
	npc.goap_profile = prof
	var ws := GoapWorldState.new({&"hp_frac": 1.0})
	var goal_pri := {}
	for g in npc._build_goap_goals():
		goal_pri[g.name] = g.priority(ws)
	assert_almost_eq(float(goal_pri[&"Survive"]), 5.0, 0.001, "Survive priority overridden via a String key")
	assert_almost_eq(float(goal_pri[&"Engage"]), 2.0, 0.001, "an un-overridden goal keeps its default")
	var flee_cost := -1.0
	for a in npc._build_goap_actions():
		if a.name == &"Flee":
			flee_cost = a.base_cost
	assert_almost_eq(flee_cost, 0.05, 0.001, "Flee cost overridden via a StringName key")
	prof = null
	npc.free()

func test_goap_profile_unknown_override_key_is_ignored() -> void:
	# A typo'd key matches no goal -> the override silently no-ops (validate() surfaces it separately); the
	# defaults must stand, not crash or mis-apply.
	var npc = load(NPC_SCRIPT).new()
	var prof := GoapProfile.new()
	prof.goal_priorities.assign([_gpri("Typoed", 9.0)])
	npc.goap_profile = prof
	var ws := GoapWorldState.new({&"hp_frac": 1.0})
	for g in npc._build_goap_goals():
		if g.name == &"Survive":
			assert_almost_eq(g.priority(ws), 3.0, 0.001, "unknown key ignored -> Survive keeps its default 3.0")
	prof = null
	npc.free()

func test_goap_profile_validate_against_the_real_library() -> void:
	# Bridge GoapProfile.validate() to the ACTUAL library: an override keyed on a real goal/action name passes;
	# a typo fails (validate's whole job -- a typo'd key otherwise silently no-ops). Guards the names validate is
	# given from drifting away from the names the library actually builds.
	var npc = load(NPC_SCRIPT).new()
	var goal_names := PackedStringArray()
	for g in npc._build_goap_goals():
		goal_names.append(String(g.name))
	var action_names := PackedStringArray()
	for a in npc._build_goap_actions():
		action_names.append(String(a.name))
	var prof := GoapProfile.new()
	prof.goal_priorities.assign([_gpri("Survive", 5.0)])       # a real goal
	prof.action_cost_overrides.assign([_acost("Flee", 0.1)])   # a real action
	assert_true(prof.validate(goal_names, action_names), "overrides on real names validate")
	prof.goal_priorities.assign([_gpri("Suvrive", 5.0)])       # typo
	assert_false(prof.validate(goal_names, action_names), "a typo'd goal row fails validation (it would silently no-op)")
	prof = null
	npc.free()

func test_goap_library_names_are_unique() -> void:
	# Two actions (or goals) sharing a name would corrupt selection, the contract pins, and the sentinel pairing.
	var npc = load(NPC_SCRIPT).new()
	var seen_actions := []
	for a in npc._build_goap_actions():
		assert_false(seen_actions.has(a.name), "duplicate action name: %s" % a.name)
		seen_actions.append(a.name)
	var seen_goals := []
	for g in npc._build_goap_goals():
		assert_false(seen_goals.has(g.name), "duplicate goal name: %s" % g.name)
		seen_goals.append(g.name)
	npc.free()

func test_goap_profile_negative_cost_override_is_clamped() -> void:
	# A designer typo'ing a negative cost would make an action always the cheapest and corrupt the A* search; the
	# builder clamps overrides to >= 0 via maxf.
	var npc = load(NPC_SCRIPT).new()
	var prof := GoapProfile.new()
	prof.action_cost_overrides.assign([_acost("Flee", -2.0)])
	npc.goap_profile = prof
	var flee_cost := -99.0
	for a in npc._build_goap_actions():
		if a.name == &"Flee":
			flee_cost = a.base_cost
	assert_almost_eq(flee_cost, 0.0, 0.0001, "negative cost override clamped to 0")
	prof = null
	npc.free()

func test_goap_library_goal_names_match_the_built_library() -> void:
	# GoapProfile's authoring dropdowns populate from GoapLibrary.goal_names(); pin that registry to the goals
	# npc.gd actually builds, so adding/renaming a goal without updating GoapLibrary fails loudly here and the
	# dropdown can never silently drift from the real library (the friction the old hand-kept @export_enum had).
	var npc = load(NPC_SCRIPT).new()
	var built: Array = []
	for g in npc._build_goap_goals():
		built.append(String(g.name))
	built.sort()
	var registered: Array = Array(GoapLibrary.goal_names())
	registered.sort()
	assert_eq(built, registered, "GoapLibrary.goal_names() must match npc._build_goap_goals() -- update the registry when a goal is added/renamed")
	npc.free()

func test_goap_library_action_names_match_the_built_library() -> void:
	var npc = load(NPC_SCRIPT).new()
	var built: Array = []
	for a in npc._build_goap_actions():
		built.append(String(a.name))
	built.sort()
	var registered: Array = Array(GoapLibrary.action_names())
	registered.sort()
	assert_eq(built, registered, "GoapLibrary.action_names() must match npc._build_goap_actions() -- update the registry when an action is added/renamed")
	npc.free()

func test_goap_goals_empty_profile_pursues_full_set() -> void:
	# Empty goals[] = pursue every registered goal (the backward-compatible default; the filter is a no-op).
	var npc = load(NPC_SCRIPT).new()
	var prof := GoapProfile.new()  # goals[] empty
	npc.goap_profile = prof
	var built: Array = []
	for g in npc._build_goap_goals():
		built.append(String(g.name))
	built.sort()
	var registered: Array = Array(GoapLibrary.goal_names())
	registered.sort()
	assert_eq(built, registered, "an empty goals[] pursues the full registered goal set")
	prof = null
	npc.free()

func test_goap_goals_allow_list_prunes_to_subset_plus_idle() -> void:
	# A non-empty goals[] restricts the NPC to the listed goals -- but Idle is ALWAYS kept (the always-feasible
	# floor; without it GoapPlanner.select_goal can return null and idle the whole brain).
	var npc = load(NPC_SCRIPT).new()
	var prof := GoapProfile.new()
	var only: Array[String] = ["Engage"]
	prof.goals = only
	npc.goap_profile = prof
	var built: Array = []
	for g in npc._build_goap_goals():
		built.append(String(g.name))
	built.sort()
	assert_eq(built, ["Engage", "Idle"], "goals=[Engage] pursues only Engage + the always-kept Idle floor")
	prof = null
	npc.free()

func test_goap_goals_idle_floor_survives_when_omitted() -> void:
	# A designer can list a subset that omits Idle; the filter keeps it so the brain never idles to a null goal.
	var npc = load(NPC_SCRIPT).new()
	var prof := GoapProfile.new()
	var no_idle: Array[String] = ["Investigate"]
	prof.goals = no_idle
	npc.goap_profile = prof
	var names: Array = []
	for g in npc._build_goap_goals():
		names.append(String(g.name))
	assert_true(names.has("Idle"), "Idle is retained even when goals[] omits it (select_goal must never return null)")
	assert_true(names.has("Investigate"), "the listed goal is retained")
	assert_eq(names.size(), 2, "only the listed goal + the Idle floor survive the allow-list")
	prof = null
	npc.free()
