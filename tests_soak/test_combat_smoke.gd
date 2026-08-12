extends GutTest

## OPT-IN combat smoke test — lives in tests_soak/ (NOT res://tests) so it never joins the default fast GUT run. It
## boots a real level and runs CombatSmokeHarness, which spawns a REAL armed raider vs an unarmed townsfolk dummy and
## runs full NPC combat (the thing CLAUDE.md forbids in UNIT tests — the rule keeps the fast suite pure, and this is
## the heavy harness where running the real brain over time IS the point). It proves the whole NPC combat chain
## (perceive -> acquire -> plan -> aim -> fire -> hit -> take_damage) works end to end — the widest-coverage gate for
## the Wave 5/6 npc.gd extractions (NpcCombat / NpcOutline).
##
## Run it explicitly:  tests_soak/run_soak.cmd   (godot --headless -s gut_cmdln -gconfig=res://tests_soak/soak.gutconfig.json)
##
## Target is NavSandbox.tscn — the clean-bake baseline (CLAUDE.md), so this committed test is GREEN and proves the
## harness works. Nav-not-synced (a headless reimport in flight) => INCONCLUSIVE (pending), not a failure.
## Preloaded by path (not the class_names) to avoid an editor-cache cascade when this loads headless.

const HarnessScript := preload("res://scripts/tools/combat_smoke_harness.gd")
const LEVEL := preload("res://scenes/levels/NavSandbox.tscn")


func test_armed_npc_engages_and_damages_opposed_dummy() -> void:
	var level := LEVEL.instantiate()
	add_child_autofree(level)  # frees the level + the harness + any leftover NPCs after the test
	# Let the level _ready run and the navmesh register before the harness starts polling for sync.
	await get_tree().process_frame
	await get_tree().process_frame

	var harness := HarnessScript.new()
	level.add_child(harness)

	var report = await harness.run_smoke()
	gut.p(report.summary())  # always surface the numbers, pass or fail

	if not report.nav_ready:
		pending("navmesh never synced (reimport in flight / bad bake) — combat smoke INCONCLUSIVE; re-run:\n%s" % report.summary())
		harness.queue_free()
		return

	assert_true(report.damage_landed(),
		"the armed raider should land damage on the opposed dummy (perceive -> fire -> hit -> take_damage):\n%s" % report.summary())
	assert_true(report.converged(),
		"the combatants should close to engage (net distance decreased):\n%s" % report.summary())
	assert_false(report.leaking(),
		"spawning + freeing the two combatants must not leak orphan nodes:\n%s" % report.summary())

	harness.queue_free()
	report = null
