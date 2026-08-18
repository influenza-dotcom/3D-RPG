extends GutTest

## H2 (Wave 5): NpcCombat is the firing-dispatch component extracted off npc.gd — the armed body (act_alerted),
## the unarmed body (act_unarmed), the punch, and the combat dodge. These pin the extraction seam:
## - the GOAP entry points act_alerted/act_unarmed exist on the component;
## - the NPC still exposes the thin _act_alerted/_act_unarmed facades the GOAP actions call, and _punch/_maybe_dodge
##   are GONE from the root (moved here);
## - the combat-dodge bookkeeping behaves (a successful roll opens a burst + re-arms the cooldown; a degenerate roll skips);
## - the GOAP FireArmed/FireUnarmed actions still call the host facades (so the extraction is invisible to the planner).
## The heavyweight per-frame bodies (aim/telegraph/fire) run only in-tree with a live weapon/perception — playtest +
## the tests_soak combat smoke harness (T1) cover those; here we pin the seam + the pure dodge logic.

const CombatScript := preload("res://scripts/npc/npc_combat.gd")


## Minimal host for the dodge path: only the dodge tuning + _desired_velocity NpcCombat._maybe_dodge reads/writes.
class _HostStub extends Node3D:
	var move_speed: float = 5.0
	var dodge_chance: float = 1.0
	var dodge_interval: float = 0.5
	var dodge_duration: float = 0.3
	var dodge_speed_fraction: float = 0.5
	var _desired_velocity: Vector3 = Vector3.ZERO


func test_combat_exposes_the_goap_entry_points() -> void:
	var c = CombatScript.new()
	assert_true(c.has_method("act_alerted"), "NpcCombat.act_alerted is the GOAP FireArmed body (reached via host._act_alerted)")
	assert_true(c.has_method("act_unarmed"), "NpcCombat.act_unarmed is the GOAP FireUnarmed body (reached via host._act_unarmed)")
	assert_null(c.host, "host defaults null (bound by NPC._build_components)")
	c.free()


func test_attempt_fire_range_grants_projectile_grace_only() -> void:
	# The grace band exists because a spawned projectile keeps flying past the hitscan effective_range cap
	# (projectile.gd deals damage "out here, past the raycast's effective_range") — so ONLY a projectile
	# weapon earns it: a kiting player must take shotgun fire in the band, while a pure-hitscan swing that
	# physically cannot reach must not fire guaranteed-miss theater. Pinned against the AUTHORED .tres so a
	# reworked weapon that drops its projectile_scene loses the band with it.
	var shotgun := load("res://resources/weapons/shotgun.tres") as WeaponData
	assert_not_null(shotgun.projectile_scene, "the shotgun spawns physical rounds — the premise of its grace band")
	assert_eq(CombatScript.attempt_fire_range(5.0, shotgun, 8.0), 13.0,
		"a projectile weapon attempts shots through engage + grace (the kiting fix)")
	var melee := load("res://resources/weapons/melee.tres") as WeaponData
	assert_null(melee.projectile_scene, "the melee weapon is pure hitscan (no travelling round)")
	assert_eq(CombatScript.attempt_fire_range(3.0, melee, 8.0), 3.0,
		"a hitscan weapon gets NO grace — beyond effective_range its trace hits nothing")
	assert_eq(CombatScript.attempt_fire_range(5.0, null, 8.0), 5.0, "no weapon: no grace")
	assert_eq(CombatScript.attempt_fire_range(5.0, shotgun, -2.0), 5.0,
		"a negative authored grace clamps to none rather than SHRINKING the fire range")
	# The rock is the projectile weapon that must NOT get the band: effective_range 0 means it engages at the
	# unranged fallback guess (no hitscan cap for its rounds to outfly), and its flat 30 m/s lob grounds inside
	# that fallback — band shots would be guaranteed-miss theater burning its 4 finite grenades.
	var rock := load("res://resources/weapons/rock_weapon.tres") as WeaponData
	assert_not_null(rock.projectile_scene, "the rock spawns projectiles (the reason it needs an explicit carve-out)")
	assert_eq(rock.effective_range, 0.0, "the rock is authored unranged (effective_range 0) — the carve-out's trigger")
	assert_eq(CombatScript.attempt_fire_range(15.0, rock, 8.0), 15.0,
		"an unranged lobbed weapon gets NO grace band — its fallback engage already exceeds its ballistic reach")


func test_alerted_chase_keeps_pressure_when_blocked_or_height_mismatched() -> void:
	assert_true(CombatScript.should_chase_while_alerted(false, 5.0, 30.0, 0.9, 0.0), "blocked LOS keeps pursuing even inside weapon standoff")
	assert_true(CombatScript.should_chase_while_alerted(true, 35.0, 30.0, 0.9, 0.0), "outside standoff keeps the old close-in behavior")
	assert_true(CombatScript.should_chase_while_alerted(true, 5.0, 30.0, 0.9, Locomotor.HOP_MIN_CLIMB + 0.1), "target above a real ledge keeps pursuit/hop pressure")
	assert_true(CombatScript.should_chase_while_alerted(true, 5.0, 30.0, 0.9, -Locomotor.HOP_MIN_CLIMB - 0.1), "target below a real ledge keeps pursuit/hop pressure")
	assert_false(CombatScript.should_chase_while_alerted(true, 5.0, 30.0, 0.9, 0.0), "clear shot inside standoff can hold position and dodge")


func test_npc_keeps_thin_facades_and_dropped_the_moved_bodies() -> void:
	var npc = load("res://scripts/npc/npc.gd").new()
	assert_true(npc.has_method("_act_alerted"), "NPC keeps the _act_alerted facade the GOAP FireArmed action calls")
	assert_true(npc.has_method("_act_unarmed"), "NPC keeps the _act_unarmed facade the GOAP FireUnarmed action calls")
	assert_false(npc.has_method("_punch"), "_punch moved to NpcCombat (no longer on the root)")
	assert_false(npc.has_method("_maybe_dodge"), "_maybe_dodge moved to NpcCombat (no longer on the root)")
	npc.free()


func test_maybe_dodge_opens_a_burst_and_rearms_cooldown() -> void:
	var c = CombatScript.new()
	var host := _HostStub.new()
	add_child_autofree(host)  # in-tree so global_position is valid
	host.global_position = Vector3.ZERO
	c.host = host
	# dodge_chance = 1.0 so the roll always succeeds; the aim is offset so the us->target vector isn't degenerate.
	c._maybe_dodge(0.016, Vector3(5.0, 0.0, 0.0))
	assert_almost_eq(c._dodge_t, host.dodge_duration, 0.001, "a successful roll opens an active strafe burst (_dodge_t = dodge_duration)")
	assert_almost_eq(c._dodge_cd, 2.0, 0.001, "the cooldown re-arms to max(dodge_interval, DODGE_MIN_INTERVAL) = 2.0")
	assert_gt(host._desired_velocity.length(), 0.0, "the burst drives host._desired_velocity sideways")
	c.free()


func test_maybe_dodge_skips_a_degenerate_direction() -> void:
	# Standing ON the target (aim == our position) -> no meaningful lateral -> skip the dodge this cycle (no burst).
	var c = CombatScript.new()
	var host := _HostStub.new()
	add_child_autofree(host)
	host.global_position = Vector3(2.0, 0.0, 2.0)
	c.host = host
	c._maybe_dodge(0.016, Vector3(2.0, 0.0, 2.0))  # aim == position
	assert_eq(c._dodge_t, 0.0, "a degenerate (on-target) roll opens no strafe burst")
	c.free()


func test_goap_fire_actions_call_the_host_facades() -> void:
	# Drift guard: the GOAP FireArmed/FireUnarmed actions must keep calling host._act_alerted / host._act_unarmed so
	# the extraction stays invisible to the planner (the bodies moved to NpcCombat, but the entry points didn't).
	assert_true(FileAccess.get_file_as_string("res://scripts/npc/goap/actions/goap_action_fire_armed.gd").contains("host._act_alerted("), "FireArmed action must call host._act_alerted")
	assert_true(FileAccess.get_file_as_string("res://scripts/npc/goap/actions/goap_action_fire_unarmed.gd").contains("host._act_unarmed("), "FireUnarmed action must call host._act_unarmed")
