extends GutTest

## RangedEnemy non-combat behaviour. Covers the wander-point sampler (pure math), the stranded counter, the
## charge-sting scheduling, and that a plain NPC with untouched Behavior exports is today's enemy (fights, holds
## its post) so existing enemies are unchanged. Built off-tree via load().new() so _ready (weapon / perception /
## nav spawn + group-add) never runs. The wander/flee MOVEMENT itself is time- + navmesh-dependent, so it's
## verified in-engine during manual check, not here.

const RANGED_PATH := "res://scripts/npc/npc.gd"

## GameSettings.npc_bark knobs the aim tests retune, restored after every test (the autoload's resource is shared).
var _saved_aim_sfx_delay: float
var _saved_aim_cooldown_ms: int

func before_each() -> void:
	_saved_aim_sfx_delay = GameSettings.npc_bark.aim_sfx_delay
	_saved_aim_cooldown_ms = GameSettings.npc_bark.aim_cooldown_ms

func after_each() -> void:
	GameSettings.npc_bark.aim_sfx_delay = _saved_aim_sfx_delay
	GameSettings.npc_bark.aim_cooldown_ms = _saved_aim_cooldown_ms

func test_a_plain_npc_fights_back_and_holds_its_post() -> void:
	# Ship decision: an NPC dropped into a level with its Behavior exports untouched is TODAY'S ENEMY. Read through
	# the accessors the AI consults rather than the raw enum: is_fleeing() is the GOAP Survive gate, and a fleer's
	# _on_aim refuses to charge a shot -- so a default that flipped to FLEE would make every placed enemy run.
	var e: NPC = load(RANGED_PATH).new()
	assert_false(e.is_fleeing(),
		"a plain NPC must not be a fleer -- is_fleeing() gates the Survive goal, so every placed enemy would run from you")
	e._last_aim_msec = -10000
	e._on_aim()
	assert_true(e._aim_sfx_delay >= 0.0, "a plain NPC charges its shots (the sniper sting is scheduled), i.e. it fights")
	assert_false(e.wanders, "ship decision: wandering is opt-in; a plain enemy holds its post unless a designer enables it")
	e.free()

func test_wander_point_stays_within_radius_of_spawn() -> void:
	var e: NPC = load(RANGED_PATH).new()
	e._spawn_position = Vector3(10.0, 3.0, -4.0)
	e.wander_radius = 6.0
	# Sample the disc heavily: every point must sit within wander_radius of spawn, on the spawn plane.
	for i in 200:
		var p: Vector3 = e._pick_wander_point()
		var flat := Vector2(p.x - e._spawn_position.x, p.z - e._spawn_position.z)
		assert_true(flat.length() <= e.wander_radius + 0.001,
			"wander point must stay within wander_radius of spawn (got %.3f)" % flat.length())
		assert_eq(p.y, e._spawn_position.y, "wander stays on the spawn plane (no vertical drift)")
	e.free()

func test_zero_radius_wander_pins_to_spawn() -> void:
	# Degenerate radius: a stationary "idler" that technically wanders never leaves its spot.
	var e: NPC = load(RANGED_PATH).new()
	e._spawn_position = Vector3(2.0, 0.0, 2.0)
	e.wander_radius = 0.0
	assert_eq(e._pick_wander_point(), e._spawn_position, "radius 0 must return spawn exactly")
	e.free()

func test_stranded_counter_accumulates_same_spot_resets_on_move() -> void:
	# The stranded-NPC diagnostic: give-ups in the SAME spot accumulate to the threshold (then warn once); a give-up
	# far from the last resets the run. Pure counter, tested off-tree (no global_position / no _ready).
	var e: NPC = load(RANGED_PATH).new()
	assert_false(e._tick_stranded(Vector3(5, 1, 5)), "first give-up -> not yet stranded")
	assert_false(e._tick_stranded(Vector3(5, 1, 5)), "second same-spot give-up -> still under threshold")
	assert_true(e._tick_stranded(Vector3(5, 1, 5)), "third same-spot give-up -> stranded")
	assert_false(e._tick_stranded(Vector3(50, 1, 50)), "a give-up far from the last resets the run")
	e.free()

func test_snap_to_navmesh_is_identity_offtree() -> void:
	# The shared snap helper (wander / flee / return-to-post) must no-op off-tree (no agent / no map), so the
	# pure-math destination logic stays deterministic in unit tests and only snaps when a real navmesh exists.
	var e: NPC = load(RANGED_PATH).new()
	var p := Vector3(7.0, 1.0, -3.0)
	assert_eq(e._snap_to_navmesh(p, 4.0), p, "off-tree -> returns the input point unchanged")
	e.free()

func test_on_aim_schedules_the_charge_sting_a_tuned_beat_after_the_shot() -> void:
	# The charge sting must be SCHEDULED a short beat out (not played instantly the same frame as the
	# shot), so the gunshot and the charge-up don't blur together -- and the beat is the designer's knob.
	assert_gt(_saved_aim_sfx_delay, 0.0,
		"shipped NpcBarkSettings.aim_sfx_delay must be > 0 -- a zero beat plays the charge sting on the gunshot's frame and the two blur together")
	GameSettings.npc_bark.aim_sfx_delay = 0.37  # a distinctive retune, so a hardcoded delay cannot pass
	var e: NPC = load(RANGED_PATH).new()
	e._last_aim_msec = -10000  # force off the per-shot aim cooldown so _on_aim runs
	assert_lt(e._aim_sfx_delay, 0.0, "precondition: no sting pending on a fresh NPC")
	e._on_aim()
	assert_almost_eq(e._aim_sfx_delay, 0.37, 0.0001,
		"_on_aim must arm the sting countdown at GameSettings.npc_bark.aim_sfx_delay, not play it now or ignore the knob")
	e.free()

func test_on_aim_is_refused_for_a_fleer_and_inside_the_aim_cooldown() -> void:
	# Two guards, each with the same NPC setup as a control: a fleer never charges a shot, and a second lock-on
	# inside aim_cooldown_ms is de-duplicated so a lock + an immediate first shot sting once, not twice.
	GameSettings.npc_bark.aim_cooldown_ms = 60000  # the whole test runs inside one cooldown window
	var fleer: NPC = load(RANGED_PATH).new()
	fleer.threat_response = NPC.ThreatResponse.FLEE
	fleer._last_aim_msec = -1000000
	fleer._on_aim()
	assert_lt(fleer._aim_sfx_delay, 0.0, "a FLEE NPC never aims, so no sniper-charge sting is scheduled for it")
	fleer.free()
	var e: NPC = load(RANGED_PATH).new()
	e._last_aim_msec = -1000000
	e._on_aim()
	assert_true(e._aim_sfx_delay >= 0.0, "control: the same NPC set to FIGHT does schedule the sting")
	e._aim_sfx_delay = -1.0  # the sting played
	e._on_aim()              # re-lock inside the cooldown window
	assert_lt(e._aim_sfx_delay, 0.0, "a re-lock inside aim_cooldown_ms must not schedule a second sting")
	e.free()
