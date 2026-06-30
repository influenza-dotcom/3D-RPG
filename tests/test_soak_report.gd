extends GutTest

## Fast off-tree coverage of the SOAK verdict logic (scripts/tools/soak_report.gd). The heavy in-tree soak that
## fills a SoakReport lives in the opt-in tests_soak/ suite (it boots a level + runs real NPC._ready); THIS pins
## the pure pass/fail math so the harness can't silently drift into calling a leak clean or a strand a pass.
## Preloaded by path (not the global class_name) to match how the harness references it.

const SoakReportScript := preload("res://scripts/tools/soak_report.gd")


func test_leak_detected_flat_series_is_false() -> void:
	assert_false(SoakReportScript.leak_detected(PackedInt32Array([100, 100, 100]), 10),
		"a flat post-wave node count is not a leak")


func test_leak_detected_upward_trend_beyond_slack_is_true() -> void:
	assert_true(SoakReportScript.leak_detected(PackedInt32Array([100, 130, 180]), 10),
		"node count climbing 100->180 across waves (>slack) is a leak")


func test_leak_detected_within_slack_is_false() -> void:
	assert_false(SoakReportScript.leak_detected(PackedInt32Array([100, 105, 108]), 10),
		"small drift within slack (constant headless overhead) must not read as a leak")


func test_leak_detected_needs_two_samples() -> void:
	assert_false(SoakReportScript.leak_detected(PackedInt32Array([100]), 10),
		"one wave can't establish a trend — never a false positive")
	assert_false(SoakReportScript.leak_detected(PackedInt32Array(), 10),
		"no samples is not a leak")


func test_stranded_threshold_matches_npc_convention() -> void:
	# npc.gd's _tick_stranded flags at _stranded_cycles >= 3; the soak MUST use the same number or it would
	# disagree with the engine's own "looks STRANDED" warning. Guards against a silent divergence.
	assert_eq(SoakReportScript.STRANDED_THRESHOLD, 3,
		"SoakReport.STRANDED_THRESHOLD must mirror NPC._tick_stranded's >= 3")


func test_ok_requires_nav_ready() -> void:
	var r := SoakReportScript.new()
	r.nav_ready = false
	r.leak_post_wave_nodes = PackedInt32Array([100, 100])
	assert_false(r.ok(), "a run where the navmesh never synced is INCONCLUSIVE, not a pass")
	r = null


func test_ok_true_when_clean() -> void:
	var r := SoakReportScript.new()
	r.nav_ready = true
	r.leak_post_wave_nodes = PackedInt32Array([100, 100])
	r.leak_slack = 10
	assert_true(r.ok(), "nav-ready + no stranded + no leak == OK")
	r = null


func test_has_stranded_fails_ok() -> void:
	var r := SoakReportScript.new()
	r.nav_ready = true
	r.leak_post_wave_nodes = PackedInt32Array([100, 100])
	r.stranded.append({"name": "Raider", "pos": Vector3.ZERO, "cycles": 4})
	assert_true(r.has_stranded(), "a recorded stranded NPC reads as stranded")
	assert_false(r.ok(), "any stranded NPC fails the run")
	r = null


func test_summary_names_the_stranded_npc() -> void:
	var r := SoakReportScript.new()
	r.nav_ready = true
	r.stranded.append({"name": "RaiderX", "pos": Vector3(1.0, 2.0, 3.0), "cycles": 5})
	var s := r.summary()
	assert_true("RaiderX" in s, "the summary must name the stranded NPC so a designer can find the spot")
	assert_true("STRANDED" in s, "the summary must call out the strand")
	r = null
