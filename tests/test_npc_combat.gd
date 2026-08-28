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


# --- Target leading (NpcCombat.lead_aim_point) ---
# The "stop strafing forever" solve: since enemies never hitscan, every AI round has travel time, and aiming at
# where the target IS let a held strafe walk out of every bullet. These pin the intercept geometry (pure static,
# no tree) plus every degenerate fallback, since ALL of them must return the un-led body point — a bad lead aims
# an enemy at empty floor, which is worse than not leading at all.

func test_lead_aim_point_solves_a_perpendicular_intercept() -> void:
	# The canonical case: shooter at the origin, target 40 m dead ahead strafing across at 4 m/s, round at
	# 40 m/s. The exact intercept satisfies |offset| / target_speed == distance_to_lead_point / round_speed;
	# with a full lead_fraction the returned point must land on that circle, not merely "somewhere ahead".
	var lead := CombatScript.lead_aim_point(
			Vector3.ZERO, Vector3(0.0, 0.0, -40.0), Vector3(4.0, 0.0, 0.0), 40.0, 1.0, 5.0)
	var flight: float = lead.length() / 40.0
	assert_almost_eq(lead.x, 4.0 * flight, 0.001,
		"the lead point is exactly where the target arrives after the round's OWN flight time (a true intercept)")
	assert_almost_eq(lead.z, -40.0, 0.001, "leading moves the aim along the target's motion, not up/down range")
	assert_gt(lead.x, 4.0 * 40.0 / 40.0 - 0.001,
		"and it is at least the naive distance/speed lead (the extra travel to the lead point costs more time)")


func test_lead_aim_point_scales_the_offset_by_the_lead_fraction() -> void:
	# lead_fraction is the marksmanship dial (NPC.aim_lead_fraction), and it scales the resulting OFFSET —
	# half the fraction must leave exactly half the drift uncorrected, which is the residual that keeps a
	# baseline mook's strafing target a coin flip instead of a guaranteed hit.
	var target := Vector3(0.0, 0.0, -40.0)
	var vel := Vector3(4.0, 0.0, 0.0)
	var full := CombatScript.lead_aim_point(Vector3.ZERO, target, vel, 40.0, 1.0, 5.0)
	var half := CombatScript.lead_aim_point(Vector3.ZERO, target, vel, 40.0, 0.5, 5.0)
	assert_almost_eq(half.x, full.x * 0.5, 0.001, "half the lead fraction leads by half the offset")
	assert_eq(CombatScript.lead_aim_point(Vector3.ZERO, target, vel, 40.0, 0.0, 5.0), target,
		"lead_fraction 0 is the old shoot-at-the-navel behaviour, exactly")


func test_lead_aim_point_ignores_vertical_velocity() -> void:
	# A jumping/falling target rides a gravity arc; extrapolating its instantaneous vertical speed linearly
	# would sling the aim over its head. Vertical is deliberately un-led, so hopping still throws aim off.
	var target := Vector3(0.0, 0.0, -40.0)
	var lead := CombatScript.lead_aim_point(
			Vector3.ZERO, target, Vector3(0.0, 6.0, 0.0), 40.0, 1.0, 5.0)
	assert_eq(lead, target, "pure vertical motion is not led at all — the aim stays on the body")
	var mixed := CombatScript.lead_aim_point(
			Vector3.ZERO, target, Vector3(4.0, 6.0, 0.0), 40.0, 1.0, 5.0)
	assert_almost_eq(mixed.y, target.y, 0.001, "a strafing jumper is led sideways only, never upward")
	assert_gt(mixed.x, 0.0, "...but its horizontal strafe is still fully led")


func test_lead_aim_point_clamps_the_predicted_flight_time() -> void:
	# The sanity clamp: a far target with a slow round must not be led metres into a wall. 4 m/s over the
	# 0.25 s cap is 1 m, however long the real flight would have been.
	var lead := CombatScript.lead_aim_point(
			Vector3.ZERO, Vector3(0.0, 0.0, -200.0), Vector3(4.0, 0.0, 0.0), 20.0, 1.0, 0.25)
	assert_almost_eq(lead.x, 1.0, 0.001, "the lead offset is capped at max_lead_time worth of drift")


func test_lead_aim_point_falls_back_to_the_body_on_degenerate_input() -> void:
	var target := Vector3(0.0, 0.0, -40.0)
	var vel := Vector3(4.0, 0.0, 0.0)
	assert_eq(CombatScript.lead_aim_point(Vector3.ZERO, target, vel, 0.0, 1.0, 5.0), target,
		"no round speed (an unauthored projectile_speed): nothing to solve, aim at the body")
	assert_eq(CombatScript.lead_aim_point(Vector3.ZERO, target, vel, 40.0, 1.0, 0.0), target,
		"a zero time cap disables leading rather than producing a zero-length prediction")
	assert_eq(CombatScript.lead_aim_point(Vector3.ZERO, target, Vector3.ZERO, 40.0, 1.0, 5.0), target,
		"a standing target is aimed at directly")
	assert_eq(CombatScript.lead_aim_point(Vector3.ZERO, target, Vector3(0.05, 0.0, 0.0), 40.0, 1.0, 5.0), target,
		"sub-threshold drift (collision jitter, one frame of navmesh wobble) is not movement worth predicting")
	# Target fleeing straight away FASTER than the round flies: no real intercept exists. Inventing one would
	# aim the NPC at a point it can never reach, so it must aim at the body instead.
	assert_eq(CombatScript.lead_aim_point(Vector3.ZERO, target, Vector3(0.0, 0.0, -50.0), 40.0, 1.0, 5.0), target,
		"a target outrunning the round gets no lead (no positive root)")


func test_lead_aim_point_leads_backward_for_a_closing_target() -> void:
	# Charging straight at the shooter shortens the flight, so the intercept sits BEHIND the current
	# position (down-range of the shooter) — the sign has to come out of the solve, not an abs().
	var lead := CombatScript.lead_aim_point(
			Vector3.ZERO, Vector3(0.0, 0.0, -40.0), Vector3(0.0, 0.0, 4.0), 40.0, 1.0, 5.0)
	assert_gt(lead.z, -40.0, "a target closing on the shooter is led toward the shooter, not away")


func test_ai_lead_uses_the_slowed_ai_round_speed() -> void:
	# THE trap this pins: AI rounds fly at npc_projectile_speed_mult of the authored speed (the dodge window),
	# so the lead solve must use ProjectileSpawner.round_speed(w, false). Solving with the PLAYER's faster
	# figure would under-lead by exactly the margin that multiplier was added to create.
	var smg := load("res://resources/weapons/smg.tres") as WeaponData
	assert_lt(smg.npc_projectile_speed_mult, 1.0, "the SMG's AI rounds are slowed on purpose (the dodge window)")
	var target := Vector3(0.0, 0.0, -20.0)
	var vel := Vector3(4.0, 0.0, 0.0)
	var ai_lead := CombatScript.lead_aim_point(
			Vector3.ZERO, target, vel, ProjectileSpawner.round_speed(smg, false), 1.0, 5.0)
	var player_lead := CombatScript.lead_aim_point(
			Vector3.ZERO, target, vel, ProjectileSpawner.round_speed(smg, true), 1.0, 5.0)
	assert_gt(ai_lead.x, player_lead.x,
		"a slower AI round spends longer in flight, so it must be led FURTHER ahead")
	# And the lead has to actually cover a body: a 4 m/s strafe at 20 m was the exact case that made
	# incoming fire infinitely dodgeable.
	assert_gt(ai_lead.x, 0.8, "the SMG's AI lead at 20 m clears a player capsule's width of drift")


func test_npc_exposes_the_lead_seam() -> void:
	# The wiring seam: leading lives on get_aim_direction's helper ONLY. _aim_point must stay un-led — it is
	# also the pathing goal, the ally alert point and the clear-shot LOS ray.
	var npc = load("res://scripts/npc/npc.gd").new()
	assert_true(npc.has_method("_lead_aim_point"), "NPC computes its led aim point for the shot direction")
	assert_true(npc.has_method("aim_lead_fraction"), "NPC exposes the gunplay-scaled lead dial (twin of aim_error_spread)")
	npc.free()
	var src := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
	assert_true(src.contains("_lead_aim_point(origin)"),
		"get_aim_direction aims at the LED point (source pin: leading must not be quietly dropped)")
	assert_string_contains(src, "ShotResolver.ai_fires_live_projectile(w)")


## A moving target for the wiring test below: a CharacterBody3D (like the player and every NPC) whose
## `velocity` the lead solve duck-types off. Never ticked — the value is just read at trigger time.
class _MovingTarget extends CharacterBody3D:
	pass


## Build a bare NPC (NO _ready — the fast suite must not run the real brain) wired with just the handles
## get_aim_direction touches: a muzzle anchor, a target, and a Weapon holding `w`.
func _armed_npc_aiming_at(target: Node3D, w: WeaponData) -> Node:
	var npc = load("res://scripts/npc/npc.gd").new()
	add_child_autofree(npc)
	npc.global_position = Vector3.ZERO
	var muzzle := Marker3D.new()
	npc.add_child(muzzle)
	npc._muzzle = muzzle
	var weapon := Weapon.new()
	var inv := Inventory.new()
	inv.equipped_weapon = w
	weapon.add_child(inv)  # parented so the autofree cascade takes it (Weapon.equipped_weapon reads through it)
	weapon.inventory = inv
	npc.add_child(weapon)
	npc._weapon = weapon
	npc._target = target
	npc._target_body = target
	return npc


func test_get_aim_direction_leads_a_strafing_target() -> void:
	# THE wiring test: the whole point of the feature reaching the actual shot. A target strafing across at
	# 4 m/s 20 m out used to be shot straight at (and walked out of the bullet); the fired direction must now
	# point AHEAD of it, by enough to cover a body.
	var target := _MovingTarget.new()
	add_child_autofree(target)
	target.global_position = Vector3(0.0, 0.0, -20.0)
	target.velocity = Vector3(4.0, 0.0, 0.0)
	var npc = _armed_npc_aiming_at(target, load("res://resources/weapons/smg.tres") as WeaponData)
	var dir: Vector3 = npc.get_aim_direction()
	assert_gt(dir.x, 0.0, "the shot is aimed toward the side the target is strafing to, not straight at it")
	# Project the aim onto the target's depth plane and measure how far ahead of the body it lands.
	var ahead: float = dir.x * (20.0 / absf(dir.z))
	assert_gt(ahead, 0.8, "the lead at 20 m clears a player capsule's width of drift (the old behaviour led 0)")
	assert_almost_eq(dir.y, 0.0, 0.001, "leading stays in the ground plane")


func test_get_aim_direction_does_not_lead_a_standing_target() -> void:
	# Behaviour-preserving half: a stationary target is still shot straight at, exactly as before.
	var target := _MovingTarget.new()
	add_child_autofree(target)
	target.global_position = Vector3(0.0, 0.0, -20.0)
	var npc = _armed_npc_aiming_at(target, load("res://resources/weapons/smg.tres") as WeaponData)
	assert_almost_eq(npc.get_aim_direction().x, 0.0, 0.0001, "a standing target is aimed at dead-on")


func test_get_aim_direction_does_not_lead_a_melee_swing() -> void:
	# The load-bearing carve-out: a knife's damage is an instant 3 m trace, so leading it would swing at the
	# air beside a strafing target and zero out every default-knife NPC. ai_fires_live_projectile gates it.
	var melee := load("res://resources/weapons/melee.tres") as WeaponData
	assert_true(melee.is_melee, "the knife is authored melee — the premise of this carve-out")
	var target := _MovingTarget.new()
	add_child_autofree(target)
	target.global_position = Vector3(0.0, 0.0, -2.0)
	target.velocity = Vector3(4.0, 0.0, 0.0)
	var npc = _armed_npc_aiming_at(target, melee)
	assert_almost_eq(npc.get_aim_direction().x, 0.0, 0.0001, "a melee swing aims at the body, never ahead of it")


func test_aim_lead_fraction_tracks_the_tuned_dial_and_gunplay() -> void:
	var npc = load("res://scripts/npc/npc.gd").new()
	add_child_autofree(npc)
	var tuned: float = GameSettings.npc_ai.aim_lead_fraction
	assert_almost_eq(npc.aim_lead_fraction(), tuned, 0.0001,
		"a sheetless mook leads at the authored base (its baseline sway_mult is 1.0)")
	# A steadier shooter predicts better — the same stat that tightens its aim cone.
	var sharp := CharacterStats.new()
	sharp.gunplay = CharacterStats.BASELINE + 2
	npc.stats = sharp
	assert_gt(npc.aim_lead_fraction(), tuned, "a higher-gunplay NPC leads closer to a perfect intercept")
	assert_lte(npc.aim_lead_fraction(), 1.0, "...but never OVER-leads — aiming past you was never the failure mode")
	# ...and a surgical sheet (gunplay 12.5+ drives sway_mult to 0) clamps to the exact intercept.
	var elite := CharacterStats.new()
	elite.gunplay = CharacterStats.BASELINE + 20
	npc.stats = elite
	assert_eq(npc.aim_lead_fraction(), 1.0, "a sway_mult-0 elite solves the intercept exactly (no divide-by-zero)")


# --- Breathing room between ranged shots (2026-08-26) -------------------------------------------------
# NPC.shot_interval_for is the pure form of NPC._shot_interval: the weapon's authored attack_speed scaled by
# the per-NPC rate_of_fire_factor, then held to GameSettings.npc_ai.min_shot_interval. The floor exists because
# every ranged shot drags the whole telegraph package (charge sting, laser/aim-radial ramp, incoming beep) and
# that package is sized by the cadence — the shipped pistol (0.44 s) and SMG (0.125 s) beeped and re-locked
# faster than the 0.5 s beep_lead_time, so the warning never switched off and stopped meaning anything.

func test_shot_interval_floors_a_fast_ranged_weapon() -> void:
	var floor_s: float = GameSettings.npc_ai.min_shot_interval
	var pistol: WeaponData = load("res://resources/weapons/pistol.tres")
	var smg: WeaponData = load("res://resources/weapons/smg.tres")
	assert_lt(pistol.attack_speed, floor_s,
		"the shipped pistol's authored cadence is FASTER than the floor — it is the case this dial exists for")
	assert_almost_eq(NPC.shot_interval_for(pistol, 1.0, floor_s), floor_s, 0.0001,
		"an NPC pistol paces to the breathing floor, not its raw 0.44 s player cadence")
	assert_almost_eq(NPC.shot_interval_for(smg, 1.0, floor_s), floor_s, 0.0001,
		"the SMG's 0.125 s strobe is paced to the same floor")

func test_shot_interval_leaves_a_slow_ranged_weapon_alone() -> void:
	# A FLOOR, not an offset: a gun already slower than the floor keeps its authored rhythm untouched, so the
	# shotgun/sniper feel exactly as they did before the dial existed.
	var floor_s: float = GameSettings.npc_ai.min_shot_interval
	var shotgun: WeaponData = load("res://resources/weapons/shotgun.tres")
	assert_gt(shotgun.attack_speed, floor_s, "the shotgun is authored slower than the floor")
	assert_almost_eq(NPC.shot_interval_for(shotgun, 1.0, floor_s), shotgun.attack_speed, 0.0001,
		"a weapon slower than the floor is not slowed further")

func test_shot_interval_floor_spares_melee_fists_and_spray_paint() -> void:
	# Keyed off the SAME _weapon_uses_ranged_attack_telegraphs predicate that gates the telegraphs, so the two
	# can never disagree: a swing carries no beep or aim radial, so there is no warning rhythm to give room to.
	var floor_s: float = GameSettings.npc_ai.min_shot_interval
	var melee: WeaponData = load("res://resources/weapons/melee.tres")
	var spray: WeaponData = load("res://resources/weapons/spray_paint.tres")
	assert_lt(melee.attack_speed, floor_s, "the knife swings faster than the floor — it would be caught by a blanket floor")
	assert_almost_eq(NPC.shot_interval_for(melee, 1.0, floor_s), melee.attack_speed, 0.0001,
		"a melee weapon keeps its authored swing cadence")
	assert_almost_eq(NPC.shot_interval_for(NPC.FISTS, 1.0, floor_s), NPC.FISTS.attack_speed, 0.0001,
		"fists keep the punch cadence (the unarmed branch of _shot_interval never reaches the floor at all)")
	assert_almost_eq(NPC.shot_interval_for(spray, 1.0, floor_s), spray.attack_speed, 0.0001,
		"spray paint is not a telegraphed shot, so it is not paced down either")

func test_shot_interval_floor_applies_after_the_rate_of_fire_factor() -> void:
	# The floor is a HARD species-wide ceiling on rate of fire: a profile cannot author its way under it...
	var floor_s: float = GameSettings.npc_ai.min_shot_interval
	var pistol: WeaponData = load("res://resources/weapons/pistol.tres")
	assert_almost_eq(NPC.shot_interval_for(pistol, 0.25, floor_s), floor_s, 0.0001,
		"a rate_of_fire_factor below 1 cannot push an NPC under the breathing floor")
	# ...but it never CAPS a deliberately slow shooter (sniper.tres authors 4.0).
	var sniper: WeaponData = load("res://resources/weapons/sniper_wep.tres")
	assert_almost_eq(NPC.shot_interval_for(sniper, 4.0, floor_s), sniper.attack_speed * 4.0, 0.0001,
		"a slow-firing archetype keeps its authored rate_of_fire_factor cadence")

func test_shot_interval_floor_of_zero_restores_the_raw_cadence() -> void:
	# The documented escape hatch: min_shot_interval 0 = every NPC back to its weapon's raw authored rate.
	var pistol: WeaponData = load("res://resources/weapons/pistol.tres")
	assert_almost_eq(NPC.shot_interval_for(pistol, 1.0, 0.0), pistol.attack_speed, 0.0001,
		"min_shot_interval 0 is the pre-2026-08-26 behaviour, exactly")
	assert_almost_eq(NPC.shot_interval_for(pistol, 1.0, -5.0), pistol.attack_speed, 0.0001,
		"a negative floor is ignored rather than inverting the max")
	assert_gte(NPC.shot_interval_for(null, 1.0, 0.0), 0.05,
		"the charge math divides by this, so it is never zero even with no weapon and no floor")

func test_ranged_floor_leaves_the_incoming_beep_a_silent_gap() -> void:
	# The load-bearing tuning relation: the beep fires beep_lead_time before each shot and re-arms on the shot,
	# so the QUIET between beeps is (cadence - lead). Tune the floor at or under the lead and the warning is a
	# continuous tone again — the exact thing this dial was added to fix.
	var s: NpcAiSettings = GameSettings.npc_ai
	assert_gt(s.min_shot_interval, s.beep_lead_time,
		"min_shot_interval must stay ABOVE beep_lead_time or the incoming beep has no silence to sit in")
