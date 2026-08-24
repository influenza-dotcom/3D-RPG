extends GutTest

## AiLod — the cadence gate on npc.gd's decision layer (scripts/components/ai_lod.gd).
##
## Everything here drives the PURE surface (`cadence_for` / `stagger_seed` statics) or a bare off-tree
## `.new()`. No NPC is built: per CLAUDE.md an NPC's _ready instantiates weapons/nav/audio and mutates shared
## statics, so the host-side wiring (npc.gd's `_ai_force_full_think`, and `player_distance`'s live
## `Groups.human_player` lookup, which needs a tree) is a playtest concern.
## What IS pinned here is the contract npc.gd depends on: the band table, that a throttled NPC's banked delta
## equals real elapsed time (no slow motion), and that the cast is staggered rather than synchronised.

const AiLodScript := preload("res://scripts/components/ai_lod.gd")

# Band-table defaults mirrored from the @export defaults, so a knob change that breaks the table fails here.
const NEAR := 20.0
const FAR := 45.0
const MID_INTERVAL := 0.1
const FAR_INTERVAL := 0.25


func _cadence(distance: float, force_full: bool = false, is_enabled: bool = true) -> float:
	return AiLodScript.cadence_for(distance, force_full, is_enabled, NEAR, FAR, MID_INTERVAL, FAR_INTERVAL)


# --- the tuning seams npc.gd reads when it auto-builds the component ---------------------------------------

func test_lod_seeds_are_registered_on_game_settings() -> void:
	# npc.gd's _build_components reads these five to seed every auto-built AiLod. A rename here would silently
	# leave the whole cast on the @export defaults instead of the designer's authored .tres values.
	var s := NpcAiSettings.new()
	for field in ["lod_enabled", "lod_near_distance", "lod_far_distance", "lod_mid_interval", "lod_far_interval"]:
		assert_true(field in s, "GameSettings.npc_ai must expose '%s' — npc.gd seeds the AiLod from it" % field)
	s = null


func test_shipped_lod_bands_are_ordered_and_sane() -> void:
	var s := NpcAiSettings.new()
	assert_lt(s.lod_near_distance, s.lod_far_distance,
			"near must be inside far, or the middle band inverts and cadence_for's ordering breaks")
	assert_lte(s.lod_mid_interval, s.lod_far_interval,
			"the FARTHER band must think no more often than the near one, or LOD is upside down")
	assert_gt(s.lod_mid_interval, 0.0, "a zero mid_interval would silently disable the middle band")
	s = null


func test_component_defaults_match_the_shipped_tuning_defaults() -> void:
	# The @export defaults on AiLod and the seeds on NpcAiSettings are two sources for the same numbers (a
	# hand-dropped AiLod uses the former, an auto-built one the latter). They must not drift apart.
	var s := NpcAiSettings.new()
	var lod: Node = AiLodScript.new()
	assert_eq(lod.near_distance, s.lod_near_distance, "near_distance default must match the tuning seed")
	assert_eq(lod.far_distance, s.lod_far_distance, "far_distance default must match the tuning seed")
	assert_eq(lod.mid_interval, s.lod_mid_interval, "mid_interval default must match the tuning seed")
	assert_eq(lod.far_interval, s.lod_far_interval, "far_interval default must match the tuning seed")
	lod.free()
	s = null


# --- the band table -------------------------------------------------------------------------------------

func test_inside_near_distance_thinks_every_tick() -> void:
	assert_eq(_cadence(5.0), 0.0,
			"an NPC 5 m away is in the player's face — 0.0 means no throttling at all")
	assert_eq(_cadence(NEAR), 0.0,
			"the near band is INCLUSIVE of near_distance, so exactly 20 m still thinks every tick")


func test_middle_band_thinks_on_the_mid_interval() -> void:
	assert_eq(_cadence(NEAR + 0.1), MID_INTERVAL,
			"just past near_distance the NPC drops to the middle cadence (10 Hz)")
	assert_eq(_cadence(FAR), MID_INTERVAL,
			"the middle band is INCLUSIVE of far_distance")


func test_far_band_thinks_on_the_far_interval() -> void:
	assert_eq(_cadence(FAR + 0.1), FAR_INTERVAL,
			"past far_distance the NPC is ambient set-dressing — 4 Hz")
	assert_eq(_cadence(10000.0), FAR_INTERVAL,
			"the far band has no upper bound; a whole map away is still just far_interval")


func test_no_player_means_full_rate_not_the_far_band() -> void:
	# tests_soak boots a level with NO player and counts each NPC's own _stranded_cycles to catch nav
	# stranding. Those cycles accrue in the BRAIN, so throttling a playerless level to 4 Hz would make the
	# harness under-report stranding within its time budget. INF must therefore mean full rate.
	assert_eq(_cadence(INF), 0.0,
			"no human player in the tree -> every NPC thinks every tick, so the soak harness measures the "
			+ "same behaviour it did before AI LOD existed")


func test_force_full_beats_every_distance() -> void:
	# The safety net: npc.gd passes true whenever perception is past UNAWARE, the NPC is scripted-investigating,
	# or it is a companion. A fighting NPC must never be throttled, however far away it is.
	assert_eq(_cadence(10000.0, true), 0.0,
			"force_full overrides the far band — an ENGAGED NPC always thinks every tick")


func test_disabled_lod_thinks_every_tick() -> void:
	# `enabled = false` is the designer's per-NPC opt-out AND the global GameSettings.npc_ai.lod_enabled switch.
	assert_eq(_cadence(10000.0, false, false), 0.0,
			"a disabled AiLod is byte-identical to the pre-LOD behaviour: think every tick")


func test_negative_intervals_degrade_to_every_tick_not_to_a_stall() -> void:
	# A designer typing -1 into the inspector must not wedge an NPC forever (accum can never reach a negative
	# threshold... it always can, but clamping keeps the intent obvious and the behaviour safe).
	assert_eq(AiLodScript.cadence_for(100.0, false, true, NEAR, FAR, -5.0, -5.0), 0.0,
			"a negative interval clamps to 0.0 (every tick), never to a frozen NPC")


# --- the accumulator: a throttled NPC reacts less OFTEN, never more SLOWLY ---------------------------------

func test_full_rate_returns_the_tick_delta_unchanged() -> void:
	var lod: Node = AiLodScript.new()
	assert_almost_eq(lod.think_delta(0.016, 5.0, false), 0.016, 0.0001,
			"inside near_distance think_delta is a pass-through — the brain sees a normal frame delta")
	lod.free()


func test_throttled_ticks_bank_time_then_fire_with_the_whole_bank() -> void:
	var lod: Node = AiLodScript.new()
	# 100 m away -> far band -> 0.25 s between thinks. At 120 Hz physics that is 30 ticks.
	# The FIRST think comes early by design (this NPC's stagger slot is a fraction of the first window), so
	# drive past it and measure a STEADY-STATE window — that is where the real-time invariant must hold.
	while lod.think_delta(1.0 / 120.0, 100.0, false) <= 0.0:
		pass
	var fired := 0
	var banked := 0.0
	# 31 ticks, not 30: 30 * (1/120) lands a hair UNDER 0.25 in floating point, so the window closes on 31.
	for i in 31:
		var dt: float = lod.think_delta(1.0 / 120.0, 100.0, false)
		if dt > 0.0:
			fired += 1
			banked = dt
	assert_eq(fired, 1, "over one far-band window the NPC thinks exactly once, not 31 times")
	assert_almost_eq(banked, 0.25, 0.02,
			"THE INVARIANT: the delta handed back is the REAL time elapsed since the last think, so the "
			+ "brain's timers (_fire_timer/_retarget_timer/perception/GOAP) stay in true seconds")
	lod.free()


func test_banked_time_is_conserved_across_a_long_run() -> void:
	# Nothing may be lost or double-counted: sum of the deltas the brain SEES == wall time that passed.
	var lod: Node = AiLodScript.new()
	var total_in := 0.0
	var total_out := 0.0
	for i in 600:
		total_in += 1.0 / 120.0
		total_out += lod.think_delta(1.0 / 120.0, 100.0, false)
	# Only the tail still sitting in the accumulator may be missing.
	assert_almost_eq(total_out, total_in, 0.26,
			"time is conserved to within one unfired window — a throttled NPC never runs in slow motion")
	assert_lte(total_out, total_in,
			"the accumulator can never hand back MORE time than actually elapsed")
	lod.free()


func test_closing_to_near_range_drops_the_bank_instead_of_a_catch_up_spike() -> void:
	var lod: Node = AiLodScript.new()
	for i in 20:
		lod.think_delta(1.0 / 120.0, 100.0, false)  # bank ~0.16 s in the far band
	var first_close: float = lod.think_delta(1.0 / 120.0, 2.0, false)
	assert_almost_eq(first_close, 1.0 / 120.0, 0.0001,
			"walking into near range hands the brain a NORMAL delta — banked far-band time is dropped, or an "
			+ "approaching NPC would get one fat catch-up tick (a visible lurch) the moment you got close")
	lod.free()


# --- staggering ------------------------------------------------------------------------------------------

func test_stagger_seed_is_a_fraction_of_the_window() -> void:
	for id in [1, 2, 3, 1000, 999983, 12345678]:
		var seed_v: float = AiLodScript.stagger_seed(id)
		assert_between(seed_v, 0.0, 1.0,
				"phase is a [0,1) slot scaled by whichever interval is in force (id %d)" % id)


func test_consecutive_instance_ids_do_not_share_a_phase() -> void:
	# Godot hands out consecutive instance ids in spawn order, so a wave of NPCs spawned together is the exact
	# case that would synchronise. Distinct phases are what keep the cost flat instead of spiky.
	var seen := {}
	for i in 40:
		seen[AiLodScript.stagger_seed(1000 + i)] = true
	assert_eq(seen.size(), 40,
			"40 NPCs spawned back-to-back must land on 40 DISTINCT phases — a shared phase converts a steady "
			+ "cost into a periodic frame spike, which looks worse than no LOD at all")


func test_stagger_spreads_across_the_whole_window() -> void:
	# Not just distinct — actually spread. Ten buckets across the window should be broadly occupied by 40 NPCs.
	var buckets := {}
	for i in 40:
		buckets[int(AiLodScript.stagger_seed(1000 + i) * 10.0)] = true
	assert_gte(buckets.size(), 8,
			"40 staggered NPCs should occupy at least 8 of 10 phase buckets; clumping into a few buckets "
			+ "would still spike")


func test_a_bare_instance_staggers_without_ever_entering_the_tree() -> void:
	# The stagger is derived lazily from instance_id, NOT seeded in _ready — because a bare `.new()` never runs
	# _ready, and this project forbids running an NPC's _ready in a unit test. If the phase lived in _ready the
	# whole cast would test as phase 0 and the spread above would be vacuous.
	var a: Node = AiLodScript.new()
	var b: Node = AiLodScript.new()
	assert_ne(a.phase(), b.phase(),
			"two off-tree AiLods must already disagree on phase — otherwise the stagger only exists in-game "
			+ "and nothing here actually pins it")
	a.free()
	b.free()


func test_two_npcs_entering_a_band_together_do_not_fire_on_the_same_tick() -> void:
	# The convoy case the stagger exists for: a cohort that walks out of near range together. Drive two
	# instances with identical inputs and assert their FIRST thinks land on different ticks.
	var a: Node = AiLodScript.new()
	var b: Node = AiLodScript.new()
	var first_a := -1
	var first_b := -1
	for i in 30:
		if a.think_delta(1.0 / 120.0, 100.0, false) > 0.0 and first_a < 0:
			first_a = i
		if b.think_delta(1.0 / 120.0, 100.0, false) > 0.0 and first_b < 0:
			first_b = i
	assert_true(first_a >= 0 and first_b >= 0, "both must think within one far-band window")
	assert_ne(first_a, first_b,
			"two NPCs entering the far band on the same tick must not think on the same tick — that is "
			+ "exactly the periodic spike the stagger exists to prevent")
	a.free()
	b.free()


func test_re_entering_a_throttled_band_re_staggers() -> void:
	# Full rate clears the threshold, so the NEXT entry re-seeds the staggered first wait. Without this a group
	# that walks near and then away again re-forms a convoy (they all zeroed together while close).
	var lod: Node = AiLodScript.new()
	for i in 10:
		lod.think_delta(1.0 / 120.0, 100.0, false)  # throttled, banking
	lod.think_delta(1.0 / 120.0, 2.0, false)        # walks into near range -> full rate, state cleared
	# Back out to the far band: the first think must again wait only our SLICE, not the whole window.
	var ticks := 0
	while lod.think_delta(1.0 / 120.0, 100.0, false) <= 0.0:
		ticks += 1
		assert_lt(ticks, 60, "re-entry must think within one far-band window, not stall")
	var slot: float = 1.0 - lod.phase()
	assert_almost_eq(float(ticks + 1) / 120.0, FAR_INTERVAL * slot, 0.02,
			"re-entry waits this NPC's staggered slice of the window, proving the stagger is re-applied on "
			+ "every band ENTRY rather than once at construction")
	lod.free()


func test_reset_for_reuse_clears_bank_but_keeps_the_stagger_slot() -> void:
	# Pooling contract: a body back from the pool must not inherit last life's banked time, but MUST keep its
	# phase — the slot is what stops a reused wave coming back as a convoy.
	var lod: Node = AiLodScript.new()
	var before: float = lod.phase()
	for i in 20:
		lod.think_delta(1.0 / 120.0, 100.0, false)
	lod.reset_for_reuse()
	assert_eq(lod.phase(), before,
			"the stagger slot is instance-id derived and must SURVIVE pooling")
	assert_almost_eq(lod.think_delta(1.0 / 120.0, 5.0, false), 1.0 / 120.0, 0.0001,
			"after a reuse reset the next near-range tick is a clean pass-through, not a catch-up lurch")
	lod.free()
