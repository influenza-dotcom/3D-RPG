extends GutTest

## NPC GOAP library wiring — pins that _build_goap_actions / _build_goap_goals assemble the FULL migrated combat
## set, the same library the decision-matrix (test_goap_combat_selection) and brain (test_goap_combat_brain)
## tests assert selection over. Guards against an action/goal silently dropping out of the executor build.
##
## Built off-tree via load(...).new() WITHOUT add_child and WITHOUT _ready (per CLAUDE.md — _ready instantiates
## weapon.tscn/nav/audio and mutates shared statics). The builders are pure: they only construct RefCounteds.

const NPC_SCRIPT := "res://scripts/npc/npc.gd"

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
