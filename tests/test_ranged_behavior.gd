extends GutTest

## RangedEnemy non-combat behaviour. Covers the wander-point sampler (pure math) and that the new
## opt-in behaviour exports default to today's enemy (FIGHT, no wander) so existing enemies are
## unchanged. Built off-tree via load().new() so _ready (weapon / perception / nav spawn + group-add)
## never runs. The wander/flee MOVEMENT itself is time- + navmesh-dependent, so it's verified
## in-engine during manual check, not here.

const RANGED_PATH := "res://scripts/npc/npc.gd"

func test_behavior_exports_default_to_todays_enemy() -> void:
	var e: NPC = load(RANGED_PATH).new()
	assert_eq(e.threat_response, NPC.ThreatResponse.FIGHT,
		"default response must be FIGHT so a plain enemy still engages")
	assert_false(e.wanders, "wandering is opt-in; default off so plain enemies hold their post")
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

func test_on_aim_schedules_the_charge_sting_after_a_delay() -> void:
	# The charge sting must be SCHEDULED a short beat out (not played instantly the same frame as the
	# shot), so the gunshot and the charge-up don't blur together.
	var e: NPC = load(RANGED_PATH).new()
	e._last_aim_msec = -10000  # force off the per-shot aim cooldown so _on_aim runs
	e._on_aim()
	assert_eq(e._aim_sfx_delay, NPC.AIM_SFX_DELAY,
		"_on_aim must schedule the charge sting (a ~0.1s beat after the shot), not fire it immediately")
	e.free()
