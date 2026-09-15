extends GutTest

## Fast off-tree coverage of the COMBAT SMOKE verdict logic (scripts/tools/combat_smoke_report.gd). The heavy
## in-tree smoke that fills a CombatSmokeReport lives in the opt-in tests_soak/ suite (it boots a level and runs
## real NPC._ready); THIS pins the pure verdict math with a fabricated report so the harness can't silently drift
## into calling a miss a hit, a stand-off an engagement, or a leak clean — and so the burst grouper the
## npc_burst_count gate (tests_soak/test_npc_burst_fire.gd) reads stays honest. Preloaded by path (not the
## global class_name) to match how the harness references it.

const ReportScript := preload("res://scripts/tools/combat_smoke_report.gd")


# --- defaults -----------------------------------------------------------------------------------------------

func test_fresh_report_reads_inconclusive_and_clean() -> void:
	var r := ReportScript.new()
	assert_false(r.nav_ready, "nav_ready defaults false — a report nobody filled is INCONCLUSIVE, not a pass")
	assert_false(r.converged(), "min_distance INF vs initial 0 can never read as 'closed the gap'")
	assert_false(r.damage_landed(), "min_dummy_hp INF vs start 0 can never read as 'damage landed'")
	assert_false(r.leaking(), "orphan_final - orphan_baseline = 0 is within slack")
	assert_eq(r.orphan_slack, 8, "the tolerated orphan drift is 8 (constant headless overhead), like SoakReport's leak_slack")
	assert_true(r.shot_frames.is_empty(), "an ordinary smoke run carries no shot timeline")
	assert_true(r.notes.is_empty(), "no notes until the harness adds some")
	r = null


# --- burst_lengths() — the shot timeline grouped into strings ----------------------------------------------

func test_burst_lengths_empty_timeline_is_empty() -> void:
	var r := ReportScript.new()
	var expected: Array[int] = []
	assert_eq(r.burst_lengths(5), expected, "no rounds -> no bursts (never a phantom [0] or [1])")
	r = null


func test_burst_lengths_single_round_is_one_burst_of_one() -> void:
	var r := ReportScript.new()
	r.shot_frames = [42]
	var expected: Array[int] = [1]
	assert_eq(r.burst_lengths(5), expected, "one round is one string of length 1")
	r = null


func test_burst_lengths_groups_close_rounds_and_splits_on_the_gap() -> void:
	var r := ReportScript.new()
	# An SMG-like pattern: 3-round strings 2 frames apart, strings 26+ frames apart, then a lone trailing round.
	r.shot_frames = [10, 12, 14, 40, 42, 44, 80]
	var expected: Array[int] = [3, 3, 1]
	assert_eq(r.burst_lengths(5), expected,
		"consecutive rounds <= gap apart form one string; a larger gap starts a new one — [3, 3, 1] for this timeline")
	r = null


func test_burst_lengths_gap_threshold_is_inclusive() -> void:
	var r := ReportScript.new()
	r.shot_frames = [10, 15]
	var same: Array[int] = [2]
	assert_eq(r.burst_lengths(5), same, "a spacing EXACTLY equal to gap_frames stays inside the string (<=)")
	r.shot_frames = [10, 16]
	var split: Array[int] = [1, 1]
	assert_eq(r.burst_lengths(5), split, "one frame more than gap_frames splits the string")
	r = null


func test_burst_lengths_pistol_cadence_reads_all_ones() -> void:
	var r := ReportScript.new()
	r.shot_frames = [0, 30, 60, 90]
	var expected: Array[int] = [1, 1, 1, 1]
	assert_eq(r.burst_lengths(5), expected, "a paced single-shot weapon reads [1, 1, 1, ...] — the pistol gate's expectation")
	assert_eq(r.burst_lengths(30).size(), 1, "a gap threshold at the cadence itself merges every round into ONE string (the caller must pick a gap in the valley)")
	r = null


# --- converged() --------------------------------------------------------------------------------------------

func test_converged_needs_more_than_half_a_metre_of_closing() -> void:
	var r := ReportScript.new()
	r.initial_distance = 10.0
	r.min_distance = 9.5
	assert_false(r.converged(), "closing by exactly 0.5 m is jitter, not an engagement (strict <)")
	r.min_distance = 9.4
	assert_true(r.converged(), "closing by more than 0.5 m means someone moved to engage")
	r.min_distance = 10.0
	assert_false(r.converged(), "never getting closer than the start is a stand-off")
	r = null


# --- damage_landed() ----------------------------------------------------------------------------------------

func test_damage_landed_on_hp_drop_or_kill() -> void:
	var r := ReportScript.new()
	r.dummy_start_hp = 100.0
	r.min_dummy_hp = 100.0
	assert_false(r.damage_landed(), "hp never below start and no death = no damage")
	r.min_dummy_hp = 99.0
	assert_true(r.damage_landed(), "any hp drop below start is landed damage")
	r.min_dummy_hp = 100.0
	r.dummy_died = true
	assert_true(r.damage_landed(), "a kill inside the window counts even if the hp sample never caught the drop")
	r = null


# --- orphan_delta() / leaking() -----------------------------------------------------------------------------

func test_leaking_only_beyond_the_orphan_slack() -> void:
	var r := ReportScript.new()
	r.orphan_baseline = 100
	r.orphan_final = 108
	assert_eq(r.orphan_delta(), 8, "orphan_delta is final - baseline")
	assert_false(r.leaking(), "drift equal to the slack is tolerated (constant headless overhead)")
	r.orphan_final = 109
	assert_true(r.leaking(), "one orphan over the slack is a leak")
	r.orphan_final = 90
	assert_eq(r.orphan_delta(), -10, "a negative delta (cleanup) is reported as-is")
	assert_false(r.leaking(), "fewer orphans than the baseline is never a leak")
	r = null


# --- summary() ----------------------------------------------------------------------------------------------

func test_summary_carries_every_verdict_and_the_notes() -> void:
	var r := ReportScript.new()
	r.nav_ready = true
	r.initial_distance = 12.0
	r.min_distance = 3.0
	r.dummy_start_hp = 100.0
	r.min_dummy_hp = 40.0
	r.shooter_alive = true
	r.orphan_baseline = 50
	r.orphan_final = 52
	r.notes.append("raider fired 9 rounds")
	r.notes.append("dummy closed to melee")
	var s := r.summary()
	assert_true(s.begins_with("CombatSmoke:"), "the summary is tagged so a strand seen in a log is recognisable")
	assert_true(s.contains("nav_ready=true"), "the summary states nav readiness (INCONCLUSIVE vs a real verdict)")
	assert_true(s.contains("dist 12.0->3.0"), "the summary prints the distance closing as initial->min")
	assert_true(s.contains("converged=true"), "the summary states the converged() verdict")
	assert_true(s.contains("dummy_hp 100->40"), "the summary prints the dummy hp drop as start->min")
	assert_true(s.contains("damage=true"), "the summary states the damage_landed() verdict")
	assert_true(s.contains("shooter_alive=true"), "the summary states whether the shooter survived")
	assert_true(s.contains("orphan_delta=2"), "the summary prints the orphan delta")
	assert_true(s.contains("raider fired 9 rounds"), "every note rides the summary")
	assert_true(s.contains("dummy closed to melee"), "every note rides the summary")
	assert_false(s.contains("shots="), "no shot timeline -> no shots= segment (an ordinary smoke run stays terse)")
	r = null


func test_summary_prints_the_shot_timeline_when_sampled() -> void:
	var r := ReportScript.new()
	r.shot_frames = [3, 5, 7]
	var s := r.summary()
	assert_true(s.contains("shots=3"), "a sampled run prints the round count")
	assert_true(s.contains("frames=[3, 5, 7]"), "a sampled run prints the raw frame indices so a burst failure is diagnosable")
	r = null
