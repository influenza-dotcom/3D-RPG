extends GutTest

## OPT-IN NPC-pooling reuse test — lives in tests_soak/ (NOT res://tests) so it never joins the default fast GUT run.
## It boots a real level and runs NpcPoolReuseHarness, which warms a small fleet of REAL armed NPCs into an NpcPool
## and runs acquire -> kill -> re-acquire cycles. It proves the pooling invariants the off-tree unit tests can't:
## the SAME instances come back on reuse, the pool count stays flat (no leak), and NPC.reset_for_reuse (+ every
## component reset) returns a re-acquired body to a pristine post-_ready state. This is the standing gate for the
## reset surface — running the real NPC._ready + a real death is the whole point (CLAUDE.md forbids that in UNIT
## tests, which keeps the fast suite pure; this is the deliberate opt-in exception).
##
## Run it explicitly:  tests_soak\run_soak.cmd   (godot --headless -s gut_cmdln -gconfig=res://tests_soak/soak.gutconfig.json)
##
## Target is NavSandbox.tscn — the clean-bake baseline (CLAUDE.md), so this committed test is GREEN and proves the
## harness works. Nav-not-synced (a headless reimport in flight) => INCONCLUSIVE (pending), not a failure.
## Preloaded by path (not the class_names) to avoid an editor-cache cascade when this loads headless.

const HarnessScript := preload("res://scripts/tools/npc_pool_reuse_harness.gd")
const LEVEL := preload("res://scenes/levels/NavSandbox.tscn")


func test_pooled_npcs_reuse_and_reset_cleanly() -> void:
	var level := LEVEL.instantiate()
	add_child_autofree(level)  # frees the level + the harness + the pool (and its parked bodies) after the test
	await get_tree().process_frame
	await get_tree().process_frame

	var harness := HarnessScript.new()
	level.add_child(harness)

	var report = await harness.run_reuse()
	gut.p(report.summary())  # always surface the numbers, pass or fail

	if not report.nav_ready:
		pending("navmesh never synced (reimport in flight / bad bake) — pool reuse INCONCLUSIVE; re-run:\n%s" % report.summary())
		harness.queue_free()
		return

	assert_true(report.reused_all_same,
		"killing then re-spawning pooled NPCs must hand back the SAME instances (reuse, not re-instancing):\n%s" % report.summary())
	assert_true(report.pool_stable(),
		"the pool must own a constant number of bodies across kill/respawn cycles (no leak, no unbounded growth):\n%s" % report.summary())
	assert_true(report.reset_clean,
		"a re-acquired pooled NPC must be a pristine post-_ready combatant (reset_for_reuse worked):\n%s" % report.summary())

	harness.queue_free()
	report = null
