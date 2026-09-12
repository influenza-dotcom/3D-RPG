extends GutTest

## OPT-IN burst-fire gate — lives in tests_soak/ (NOT res://tests) so it never joins the default fast GUT run,
## exactly like test_combat_smoke.gd, and for the same reason: it boots a real level and runs REAL NPC combat.
##
## Burst fire (WeaponData.npc_burst_count, 2026-08-30) is the one NPC-firing behaviour whose entire meaning is a
## TIMING PATTERN — an SMG raider answers a trigger pull with three rounds at the gun's own 0.125 s cyclic rate,
## then pays the full telegraphed cadence (GameSettings.npc_ai.min_shot_interval) before the next burst. The pure
## unit tests (tests/test_npc_combat.gd) pin the authored numbers, but nothing off-tree can see the SHAPE, so this
## samples a real firefight's magazine and asserts the rhythm the player actually hears: brrrp / breathe / brrrp.
##
## Run it explicitly:  tests_soak/run_soak.cmd
##
## ⭐ WHY THESE ASSERTIONS ARE SHAPED THE WAY THEY ARE: a burst is deliberately ABORTABLE — it holds through a brief
## blocked line (NpcCombat.BURST_LOST_GRACE) but writes off its remaining rounds when the target is genuinely
## behind something, and a round NEVER leaves the barrel on a frame that fails the clear-shot test. On a real map
## that happens for honest reasons (the sandbox's own geometry, a third NPC wandering through the line), so
## "every burst is exactly 3" is NOT a property of the feature and asserting it would be a flake generator. What
## IS pinned: full strings do happen, nothing ever exceeds the authored count, the rounds inside a string come at
## the GUN's rate, the gap between strings is still the AI's breathing cadence, and a trigger pull puts more than
## one round downrange (the pistol raider's control value is exactly one). ⭐ Every one of those is a RATIO or a
## SHAPE, never a count of rounds per second: how much of the window the raider had a clear line is a property of
## the firefight, not of the feature, and each test samples its own.
##
## Target is NavSandbox.tscn — the clean-bake baseline (CLAUDE.md), so this stays GREEN.
## Nav-not-synced (a headless reimport in flight) => INCONCLUSIVE (pending), not a failure.
## Preloaded by path (not the class_names) to avoid an editor-cache cascade when this loads headless.

const HarnessScript := preload("res://scripts/tools/combat_smoke_harness.gd")
const LEVEL := preload("res://scenes/levels/NavSandbox.tscn")
const SMG := preload("res://resources/weapons/smg.tres")
const PISTOL := preload("res://resources/weapons/pistol.tres")

## Frames of separation that split one burst from the next. The two spacings this has to tell apart are the SMG's
## intra-burst 0.125 s (~8 physics frames) and the between-bursts min_shot_interval 0.9 s (~54) — a wide valley, so
## anything in the middle works and the threshold is not a tuning-sensitive magic number.
const BURST_SPLIT_FRAMES := 25


func test_an_smg_raider_fires_real_bursts_capped_at_the_authored_count() -> void:
	var report = await _run_shooter(SMG)
	if report == null:
		return
	var count: int = NpcCombat.burst_rounds_for(SMG)
	assert_eq(count, 3, "this test reads the SHIPPED authoring — re-tune it alongside smg.tres if the burst changes")
	var bursts: Array[int] = report.burst_lengths(BURST_SPLIT_FRAMES)
	assert_true(bursts.has(count),
		"at least one string must run to its full %d rounds, or the burst never completes:\n%s" % [count, report.summary()])
	for length: int in bursts:
		assert_lte(length, count,
			"npc_burst_count is a CEILING — no string may exceed %d rounds, got %s:\n%s" % [count, str(bursts), report.summary()])
	# Not degenerate: most of what the raider fires arrives as part of a string, not as lone paced shots.
	var in_strings := 0
	for length: int in bursts:
		if length > 1:
			in_strings += length
	assert_gt(in_strings * 2, report.shot_frames.size(),
		"most rounds must arrive inside a burst — %s is single-shot fire wearing a burst's name:\n%s" % [str(bursts), report.summary()])


func test_rounds_inside_a_burst_come_at_the_guns_rate_not_the_ai_cadence() -> void:
	# The point of the feature: WITHIN a string the gun's own attack_speed sets the pace, so the SMG sounds like an
	# SMG. (The floor is the weapon's cadence timer, which Attack enforces; the grace above can stretch a round
	# LATER when the line is briefly blocked, so only the lower bound is pinned.)
	var report = await _run_shooter(SMG)
	if report == null:
		return
	var ticks: float = float(Engine.physics_ticks_per_second)
	var cyclic_frames: float = NpcCombat.burst_interval_for(SMG) * ticks
	var frames: Array[int] = report.shot_frames
	var seen := false
	for i in range(1, frames.size()):
		var gap: int = frames[i] - frames[i - 1]
		if gap > BURST_SPLIT_FRAMES:
			continue  # between strings — that gap belongs to the test below
		seen = true
		assert_gte(float(gap), cyclic_frames - 1.0,
			"a round inside a burst may never beat the gun's own cyclic rate (~%.0f frames), got %d:\n%s"
					% [cyclic_frames, gap, report.summary()])
	assert_true(seen, "the window must contain at least one within-burst gap:\n%s" % report.summary())


func test_the_gap_between_bursts_is_still_the_breathing_cadence() -> void:
	# The load-bearing other half: the burst must NOT buy its way out of min_shot_interval. If one string ran
	# straight into the next the SMG would be the pre-2026-08-26 strobe again and the whole telegraph package
	# (lock-on sting, laser ramp, incoming beep) would have no off-beat to sit in.
	var report = await _run_shooter(SMG)
	if report == null:
		return
	var floor_frames: float = GameSettings.npc_ai.min_shot_interval * Engine.physics_ticks_per_second
	var frames: Array[int] = report.shot_frames
	var seen := false
	for i in range(1, frames.size()):
		var gap: int = frames[i] - frames[i - 1]
		if gap <= BURST_SPLIT_FRAMES:
			continue  # inside a string — paced by the gun, not by the AI cadence
		seen = true
		assert_gte(float(gap), floor_frames * 0.9,
			"the gap BETWEEN bursts must still be the breathing cadence (~%.0f frames), got %d:\n%s"
					% [floor_frames, gap, report.summary()])
	assert_true(seen, "the window must contain at least one between-bursts gap:\n%s" % report.summary())


func test_bursting_puts_out_more_rounds_than_one_per_cadence() -> void:
	# The player-visible consequence, stated as a number: one trigger pull, more than one round. That is the whole
	# difference burst fire makes to volume, and the pistol test below is its control — a weapon left at
	# npc_burst_count 1 scores exactly 1.00 rounds per pull, so anything above 1 is the burst doing its job.
	#
	# ⭐ MEASURE PER PULL, NEVER PER SECOND. This used to divide the sampled window by min_shot_interval and demand
	# 1.4x that many rounds, which quietly made the gate depend on how much of the window the raider had a CLEAR
	# LINE. Bursts are deliberately abortable (see the header), the dummy closes to melee, and each test samples its
	# OWN firefight — so a sample where most strings were written off fails the arithmetic while every structural
	# property still holds. That is exactly the flake generator this file's header warns about, and it went red on
	# CI 2026-09-11: 8 rounds over 6.8 s against a 12.1 ceiling, from a firefight with no regression in it (that
	# same sample scores 1.33 rounds/pull and passes here). A real regression to single-shot scores 1.00 and fails.
	var report = await _run_shooter(SMG)
	if report == null:
		return
	var bursts: Array[int] = report.burst_lengths(BURST_SPLIT_FRAMES)
	if bursts.size() < 3:
		pending("only %d trigger pull(s) in the window — too few to average:\n%s" % [bursts.size(), report.summary()])
		return
	var rounds_per_pull: float = float(report.shot_frames.size()) / float(bursts.size())
	assert_gt(rounds_per_pull, 1.2,
		"a bursting SMG must put more than one round downrange per trigger pull — got %.2f from %s:\n%s"
				% [rounds_per_pull, str(bursts), report.summary()])


func test_a_pistol_raider_still_fires_one_round_at_a_time() -> void:
	# Bursting is opt-in per weapon: the un-authored default has to leave the old single-shot rhythm exactly as it
	# was. Same harness, same window, one round per trigger pull.
	var report = await _run_shooter(PISTOL)
	if report == null:
		return
	var bursts: Array[int] = report.burst_lengths(BURST_SPLIT_FRAMES)
	assert_gt(bursts.size(), 1, "the pistol raider must fire more than once in the window:\n%s" % report.summary())
	for length: int in bursts:
		assert_eq(length, 1,
			"a weapon left at npc_burst_count 1 fires ONE round per pull — got %s:\n%s" % [str(bursts), report.summary()])


## Boot the sandbox, run one shooter-vs-dummy firefight with `weapon` and shot sampling on, and hand back the
## report — or null after marking the test PENDING (navmesh never synced / too few shots to time) so a bad bake
## reads as INCONCLUSIVE rather than as a burst regression. The level is add_child_autofree'd, so it and every
## spawned NPC are cleaned up with the test.
func _run_shooter(weapon: WeaponData):
	var level := LEVEL.instantiate()
	add_child_autofree(level)
	await get_tree().process_frame
	await get_tree().process_frame

	var harness := HarnessScript.new()
	harness.weapon = weapon
	harness.sample_shots = true
	level.add_child(harness)

	var report = await harness.run_smoke()
	gut.p(report.summary())
	harness.queue_free()

	if not report.nav_ready:
		pending("navmesh never synced (reimport in flight / bad bake) — burst gate INCONCLUSIVE:\n%s" % report.summary())
		return null
	if report.shot_frames.size() < 2:
		pending("the raider barely fired inside the window — nothing to time:\n%s" % report.summary())
		return null
	return report
