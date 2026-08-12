extends GutTest

## OPT-IN soak integration test — lives in tests_soak/ (NOT res://tests) so it never joins the default fast GUT
## run. It boots a real level and runs SoakHarness, which spawns REAL wandering NPCs (full NPC._ready). That is
## intentionally the thing CLAUDE.md forbids in UNIT tests; the rule keeps the fast suite pure, and this is the
## heavy harness where running the real brain over time IS the point (it catches nav-grind / stranding / node
## leaks that no off-tree assertion can).
##
## Run it explicitly:  tests_soak/run_soak.cmd   (godot --headless -s gut_cmdln -gconfig=res://tests_soak/soak.gutconfig.json)
##
## Default target is NavSandbox.tscn — the clean-bake baseline (CLAUDE.md), so this committed test is GREEN and
## proves the HARNESS works end to end. To AUDIT a real level for nav health, point LEVEL at it (or bump the
## counts) and re-run: a stranded NPC or a node leak then fails with the offending NPC + spot in the summary.
## Preloaded by path (not the global class_names) to avoid an editor-cache cascade when this loads headless.

const SoakHarnessScript := preload("res://scripts/tools/soak_harness.gd")
const LEVEL := preload("res://scenes/levels/NavSandbox.tscn")


func test_navsandbox_clean_bake_no_stranded_no_leak() -> void:
	var level := LEVEL.instantiate()
	add_child_autofree(level)  # frees the level + the harness + any leftover NPCs after the test
	# Let the level _ready run and the navmesh register before the harness starts polling for sync.
	await get_tree().process_frame
	await get_tree().process_frame

	var harness := SoakHarnessScript.new()
	# Kept modest so the committed baseline runs quickly; an audit run can raise these or swap LEVEL.
	harness.npc_count = 4
	harness.stranded_seconds = 11.0  # > ~10 s so a genuine strand WOULD register on a bad level
	harness.leak_waves = 2
	harness.leak_wave_seconds = 2.5
	level.add_child(harness)

	var report = await harness.run_soak()
	gut.p(report.summary())  # always surface the numbers, pass or fail

	assert_true(report.nav_ready,
		"NavSandbox's clean baked navmesh should sync headless within the timeout — if false, a reimport may be in flight; re-run")
	assert_false(report.has_stranded(),
		"no NPC should strand on the clean NavSandbox bake; a strand here means a bad-bake island:\n%s" % report.summary())
	assert_false(report.is_leaking(),
		"spawning/freeing %d NPCs over %d waves must not grow the node count:\n%s"
			% [harness.npc_count, harness.leak_waves, report.summary()])

	harness.queue_free()
	report = null
