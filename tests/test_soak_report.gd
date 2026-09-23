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


func test_leak_detected_compares_the_last_wave_to_the_first() -> void:
	# The documented rule is LAST vs FIRST, not wave-to-wave: a slow creep that never jumps more than the slack in
	# one wave is still a leak once it has accumulated past it, and a transient spike that settled back is not.
	assert_true(SoakReportScript.leak_detected(PackedInt32Array([100, 108, 115]), 10),
		"a creep of +8 then +7 per wave (+15 overall, > slack 10) is a leak even though no single wave grew past the slack")
	assert_false(SoakReportScript.leak_detected(PackedInt32Array([100, 180, 105]), 10),
		"a mid-run spike that settled back to +5 overall is not a leak — only the net growth since the first wave counts")


func test_stranded_threshold_agrees_with_the_npcs_own_stranded_warning() -> void:
	# The soak harness flags an NPC once its _stranded_cycles reaches STRANDED_THRESHOLD; npc.gd's _tick_stranded is
	# what raises the engine's own "looks STRANDED" warning. Drive the real counter on a bare off-tree NPC (no
	# _ready, the test_ranged_behavior idiom) and find the give-up that first reads as stranded: the two must agree,
	# or the soak and the in-game warning would disagree about the same wedged body.
	var npc: Node = load("res://scripts/npc/npc.gd").new()
	var spot := Vector3(5, 1, 5)
	var first_stranded := -1
	for tick in range(1, 11):
		if npc._tick_stranded(spot):
			first_stranded = tick
			break
	assert_gt(first_stranded, 0, "ten same-spot give-ups must eventually read as stranded")
	assert_eq(first_stranded, SoakReportScript.STRANDED_THRESHOLD,
		"SoakReport.STRANDED_THRESHOLD must equal the give-up count at which NPC._tick_stranded first reports STRANDED")
	assert_eq(int(npc.get(&"_stranded_cycles")), SoakReportScript.STRANDED_THRESHOLD,
		"the counter the harness reads (_stranded_cycles) sits exactly at the threshold on that give-up")
	npc.free()


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
