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


# --- Aim inertia (2026-08-31) -------------------------------------------------------------------------
# USER: "enemies aim onto your position/projected position instantly. this feels bad." The shot direction used
# to be solved from geometry at the instant the trigger pulled, so an NPC's aim was simply wherever it needed
# to be. It is tracked STATE now: NpcCombat.slew_toward turns it toward the ideal point at a capped angular
# rate (GameSettings.npc_ai.aim_turn_rate_deg) and the intercept is solved against an EASED read of the
# target's velocity (aim_velocity_lag). Both dials are zeroable straight back to the old snap.

func test_slew_toward_caps_the_turn() -> void:
	# THE mechanic: a 90 deg correction cannot be taken in one frame — the aim only travels max_step_rad of it.
	var step := deg_to_rad(10.0)
	var out := CombatScript.slew_toward(Vector3.FORWARD, Vector3.RIGHT, step)
	assert_almost_eq(rad_to_deg(Vector3.FORWARD.angle_to(out)), 10.0, 0.001,
		"the aim turns by exactly the allowed step, not onto the goal")
	assert_almost_eq(rad_to_deg(out.angle_to(Vector3.RIGHT)), 80.0, 0.001,
		"...so 80 of the 90 degrees are still owed after one step")
	assert_almost_eq(out.length(), 1.0, 0.0001, "slew_toward always returns a unit direction")
	assert_almost_eq(out.y, 0.0, 0.0001, "a turn between two horizontal directions stays in the ground plane")


func test_slew_toward_lands_exactly_on_a_goal_within_reach() -> void:
	# LOAD-BEARING: a rate CAP has zero steady-state error, which is what keeps the 2026-08-26 lead fix intact.
	# An NPC tracking an ordinary strafe needs well under the cap, so its aim must sit EXACTLY on the intercept —
	# an exponential ease would leave a permanent lag proportional to lateral speed, i.e. the infinite strafe-dodge
	# handed straight back.
	var goal := Vector3(0.2, 0.0, -1.0).normalized()
	var out := CombatScript.slew_toward(Vector3.FORWARD, goal, deg_to_rad(90.0))
	assert_almost_eq(rad_to_deg(out.angle_to(goal)), 0.0, 0.0001,
		"a correction inside the step budget lands dead on the goal, leaving no residual tracking lag")


func test_slew_toward_snaps_when_uncapped_or_unseeded() -> void:
	# Both zero-cases degrade to the pre-inertia behaviour rather than to a stuck aim.
	assert_almost_eq(rad_to_deg(CombatScript.slew_toward(Vector3.FORWARD, Vector3.RIGHT, 0.0).angle_to(Vector3.RIGHT)),
		0.0, 0.0001, "aim_turn_rate_deg 0 = no cap: the aim snaps onto the goal exactly as it did before")
	assert_almost_eq(rad_to_deg(CombatScript.slew_toward(Vector3.ZERO, Vector3.RIGHT, deg_to_rad(1.0)).angle_to(Vector3.RIGHT)),
		0.0, 0.0001, "an un-seeded aim has nothing to swing FROM, so it snaps rather than dividing by zero")
	assert_eq(CombatScript.slew_toward(Vector3.FORWARD, Vector3.ZERO, deg_to_rad(1.0)), Vector3.FORWARD,
		"no aim point at all: hold what we have")


func test_slew_toward_turns_a_full_about_face() -> void:
	# The degenerate axis: two exactly opposed directions share no unique rotation plane, so the cross product is
	# zero and normalising it would produce NaN. A target dead behind must still cost a real about-face.
	var out := CombatScript.slew_toward(Vector3.FORWARD, Vector3.BACK, deg_to_rad(10.0))
	assert_almost_eq(out.length(), 1.0, 0.0001, "an exact 180 deg flip still returns a usable unit direction")
	assert_almost_eq(rad_to_deg(Vector3.FORWARD.angle_to(out)), 10.0, 0.001,
		"...and only turns by the allowed step, so the swing is actually paid for")
	# ...including when the current aim is itself vertical (the UP fallback axis is degenerate there too).
	var vertical := CombatScript.slew_toward(Vector3.UP, Vector3.DOWN, deg_to_rad(10.0))
	assert_almost_eq(vertical.length(), 1.0, 0.0001, "a straight-up aim flipping to straight-down stays finite")


func test_aim_turn_rate_tracks_the_tuned_dial_and_gunplay() -> void:
	var npc = load("res://scripts/npc/npc.gd").new()
	add_child_autofree(npc)
	var tuned: float = GameSettings.npc_ai.aim_turn_rate_deg
	assert_almost_eq(rad_to_deg(npc.aim_turn_rate()), tuned, 0.0001,
		"a sheetless mook swings at the authored base (its baseline sway_mult is 1.0)")
	var sharp := CharacterStats.new()
	sharp.gunplay = CharacterStats.BASELINE + 2
	npc.stats = sharp
	assert_gt(npc.aim_turn_rate(), deg_to_rad(tuned),
		"a higher-gunplay NPC whips onto a target faster — the same stat that tightens its cone and sharpens its lead")


func test_aim_velocity_lag_tracks_the_tuned_dial_and_gunplay() -> void:
	var npc = load("res://scripts/npc/npc.gd").new()
	add_child_autofree(npc)
	var tuned: float = GameSettings.npc_ai.aim_velocity_lag
	assert_almost_eq(npc.aim_velocity_lag(), tuned, 0.0001, "a sheetless mook reads your motion at the authored lag")
	var sharp := CharacterStats.new()
	sharp.gunplay = CharacterStats.BASELINE + 2
	npc.stats = sharp
	assert_lt(npc.aim_velocity_lag(), tuned, "a steadier shooter reads your velocity SOONER (lag scales down)")
	var elite := CharacterStats.new()
	elite.gunplay = CharacterStats.BASELINE + 20
	npc.stats = elite
	assert_eq(npc.aim_velocity_lag(), 0.0, "a sway_mult-0 elite reads you instantly, matching the other aim dials")


## Give `npc` a Perception that reports it has NOTICED (and optionally can SEE) its target, without running any
## real sensing — _tick_aim_tracking reads only the state + the cached saw_target + last_known_position.
func _sensing_perception(npc: Node, target: Node3D, seen: bool) -> Perception:
	var p := Perception.new()
	npc.add_child(p)
	npc._perception = p
	p.target = target
	p.target_body = target
	p.state = Perception.State.ALERTED
	p.saw_target = seen
	p.last_known_position = target.global_position
	return p


func test_aim_swings_onto_a_target_instead_of_snapping() -> void:
	# THE feature test. An NPC facing +Z with a foe 90 deg off its shoulder must NOT be aimed at it on frame one;
	# it has to turn, at aim_turn_rate_deg, and only then land on the shot.
	var target := _MovingTarget.new()
	add_child_autofree(target)
	target.global_position = Vector3(20.0, 0.0, 0.0)  # 90 deg off the body's +Z facing
	var npc = _armed_npc_aiming_at(target, load("res://resources/weapons/smg.tres") as WeaponData)
	_sensing_perception(npc, target, true)
	var goal := Vector3.RIGHT
	var tuned: float = GameSettings.npc_ai.aim_turn_rate_deg
	npc._tick_aim_tracking(0.05)
	assert_almost_eq(rad_to_deg(npc._body_forward().angle_to(npc._aim_dir)), tuned * 0.05, 0.01,
		"one frame of tracking turns the aim by exactly one frame's worth of the turn rate")
	assert_gt(rad_to_deg(npc._aim_dir.angle_to(goal)), 45.0,
		"...so the aim is still nowhere near the foe — a shot taken now genuinely goes wide")
	# Given time, it arrives EXACTLY: a rate cap leaves no residual lag once the swing is paid.
	for _i in 40:
		npc._tick_aim_tracking(0.05)
	assert_almost_eq(rad_to_deg(npc._aim_dir.angle_to(goal)), 0.0, 0.001,
		"once the swing is paid the aim sits dead on the shot — inertia costs time, not permanent accuracy")
	assert_almost_eq(rad_to_deg(npc.get_aim_direction().angle_to(goal)), 0.0, 0.001,
		"and the SHOT fires down the tracked aim (the wiring seam: get_aim_direction reads _aim_dir)")


func test_aim_starts_on_the_body_facing_not_on_the_target() -> void:
	# The seed rule. Starting the track from the goal would hand a free instant lock to exactly the cases the
	# feature exists for — an NPC alerted by an ally's shout, or one that acquires you already in its cone.
	var target := _MovingTarget.new()
	add_child_autofree(target)
	target.global_position = Vector3(0.0, 0.0, -20.0)  # dead behind the NPC's +Z facing
	var npc = _armed_npc_aiming_at(target, load("res://resources/weapons/smg.tres") as WeaponData)
	_sensing_perception(npc, target, true)
	npc._tick_aim_tracking(0.016)
	assert_gt(npc._aim_dir.z, 0.9,
		"the very first tracked frame is still pointed along the body's own facing, not spun round onto the foe")


func test_aim_holds_the_last_known_spot_while_blind() -> void:
	# Tracking a target THROUGH cover would let an NPC hold a perfect lock the whole time you were hidden and
	# fire the instant you leaned out. With no line of sight the aim covers where it last saw you instead, so
	# re-peeking a DIFFERENT angle costs the full swing.
	var target := _MovingTarget.new()
	add_child_autofree(target)
	target.global_position = Vector3(20.0, 0.0, 0.0)
	var npc = _armed_npc_aiming_at(target, load("res://resources/weapons/smg.tres") as WeaponData)
	var p := _sensing_perception(npc, target, true)
	for _i in 60:
		npc._tick_aim_tracking(0.05)  # settle onto the visible foe
	assert_almost_eq(rad_to_deg(npc._aim_dir.angle_to(Vector3.RIGHT)), 0.0, 0.001, "premise: locked on while seen")
	# Now it ducks behind cover and reappears somewhere else entirely. LOS is gone; the memory is not.
	p.saw_target = false
	target.global_position = Vector3(0.0, 0.0, -20.0)
	for _i in 5:
		npc._tick_aim_tracking(0.05)
	assert_almost_eq(rad_to_deg(npc._aim_dir.angle_to(Vector3.RIGHT)), 0.0, 0.001,
		"a blind NPC keeps covering the last-known spot — it does not follow the target it cannot see")


func test_lead_is_solved_against_an_eased_velocity() -> void:
	# The second half of the complaint ("...or projected position"). The intercept used to jump a body-width
	# ahead of the target in the same frame it started moving, because the solve read this frame's velocity.
	var target := _MovingTarget.new()
	add_child_autofree(target)
	target.global_position = Vector3(0.0, 0.0, -20.0)
	target.velocity = Vector3(4.0, 0.0, 0.0)  # bursts into a strafe from a standstill
	var npc = _armed_npc_aiming_at(target, load("res://resources/weapons/smg.tres") as WeaponData)
	_sensing_perception(npc, target, true)
	npc._tick_aim_tracking(0.05)
	assert_lt(npc._aim_target_vel.length(), target.velocity.length() * 0.5,
		"one frame in, the NPC has barely registered the strafe — the lead it solves is correspondingly short")
	for _i in 60:
		npc._tick_aim_tracking(0.05)
	assert_almost_eq(npc._aim_target_vel.x, target.velocity.x, 0.05,
		"a HELD strafe is fully read within a second or so, so this never becomes a way to dodge forever")
	# ...and out of sight the belief decays: you cannot extrapolate motion you cannot see.
	npc._perception.saw_target = false
	for _i in 60:
		npc._tick_aim_tracking(0.05)
	assert_almost_eq(npc._aim_target_vel.length(), 0.0, 0.05,
		"a shot taken the instant someone re-peeks is barely led at all")


func test_aim_inertia_is_wired_and_per_life() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
	assert_string_contains(src, "_tick_aim_tracking(delta)")
	assert_true(src.contains("_sync_weapon_anchor(delta)\n\t# Swing the AIM onto the target"),
		"aim tracking ticks beside the weapon anchor, ABOVE the AI-LOD gate — on the real delta, never the banked one")
	# Source-pinned rather than called: NPC.reset_for_reuse drives the whole per-life teardown (the Character
	# super, the inventory re-seed, every component's own reset) and needs a real pooled body, which the fast
	# suite deliberately does not build. tests_soak's pool-reuse harness exercises it live; this pins that the
	# two new per-life fields are IN that list.
	var reset := src.substr(src.find("func reset_for_reuse() -> void:"))
	assert_true(reset.contains("_aim_dir = Vector3.ZERO"),
		"NpcPool reuse must drop the tracked aim, or a respawned body comes back already locked on (a free instant kill)")
	assert_true(reset.contains("_aim_target_vel = Vector3.ZERO"), "...and its stale velocity belief goes with it")


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


# --- Burst fire (2026-08-30) --------------------------------------------------------------------------
# WeaponData.npc_burst_count is how many rounds an NPC answers ONE trigger pull with. It exists because
# min_shot_interval paces EVERY NPC's ranged fire to the 0.9 s breathing rhythm the telegraph package needs,
# which turned the SMG — a 0.125 s cyclic-rate gun — into a slow single-shot pistol. NpcCombat.burst_rounds_for
# / burst_interval_for are the pure forms the firing body reads (the attempt_fire_range idiom), so the shipped
# authoring is pinned here without a live NPC.

func test_smg_is_the_weapon_authored_to_burst() -> void:
	var smg: WeaponData = load("res://resources/weapons/smg.tres")
	assert_eq(CombatScript.burst_rounds_for(smg), 3,
		"the shipped SMG answers a trigger pull with a 3-round burst — the gun this feature exists for")
	assert_almost_eq(CombatScript.burst_interval_for(smg), smg.attack_speed, 0.0001,
		"an unauthored npc_burst_interval bursts at the gun's OWN cyclic rate (attack_speed), not the AI cadence")
	# The load-bearing relation: the burst has to FIT inside the between-shots cadence, or the string would still
	# be running when the next trigger pull is due and the brrrp/breathe/brrrp rhythm collapses back to a strobe.
	var burst_time: float = (CombatScript.burst_rounds_for(smg) - 1) * CombatScript.burst_interval_for(smg)
	assert_lt(burst_time, GameSettings.npc_ai.min_shot_interval,
		"a burst must finish inside the breathing cadence it is fired within")

func test_every_other_shipped_weapon_still_fires_one_round_per_pull() -> void:
	# Bursting is opt-in per weapon: the default keeps the fire path byte-identical to before it existed
	# (_burst_left is 0 forever, so act_alerted never enters the burst branch at all).
	for path: String in ["pistol.tres", "sniper_wep.tres", "shotgun.tres", "melee.tres", "rock_weapon.tres",
			"spray_paint.tres", "fists.tres"]:
		var w: WeaponData = load("res://resources/weapons/" + path)
		assert_eq(CombatScript.burst_rounds_for(w), 1,
			"%s is not authored to burst — one aimed shot per trigger pull" % path)

func test_burst_helpers_survive_a_missing_or_nonsense_weapon() -> void:
	assert_eq(CombatScript.burst_rounds_for(null), 1, "no weapon = the single-shot default, never a crash")
	assert_gte(CombatScript.burst_interval_for(null), CombatScript.MIN_BURST_INTERVAL,
		"the gap between burst rounds is floored, so nothing can empty a clip in one frame")
	var junk := WeaponData.new()
	junk.npc_burst_count = -4
	junk.npc_burst_interval = -1.0
	junk.attack_speed = 0.0
	assert_eq(CombatScript.burst_rounds_for(junk), 1, "a negative count floors to the single shot")
	assert_gte(CombatScript.burst_interval_for(junk), CombatScript.MIN_BURST_INTERVAL,
		"a zero attack_speed with no authored interval still leaves a real gap between rounds")

func test_the_burst_window_outlasts_the_string_but_not_the_fight() -> void:
	# The abandonment guard. A burst has no GOAP exit hook (GoapAction.exit is never invoked), so its owed rounds
	# expire on a real-frame deadline instead. The window has to comfortably clear the worst LEGITIMATE stretch —
	# an AI-LOD far-band NPC only thinks every lod_far_interval, so each owed round can cost a whole think.
	var smg: WeaponData = load("res://resources/weapons/smg.tres")
	var ticks: float = float(Engine.physics_ticks_per_second)
	var span: float = (CombatScript.burst_rounds_for(smg) - 1) * CombatScript.burst_interval_for(smg)
	var window: float = CombatScript.burst_window_frames(smg) / ticks
	assert_gt(window, span, "the window must outlast the string it is timing, or no burst ever completes")
	var lod_stretch: float = (CombatScript.burst_rounds_for(smg) - 1) * GameSettings.npc_ai.lod_far_interval
	assert_gt(window, lod_stretch,
		"a far-band NPC walks its burst out one round per think — the window must survive that, not truncate it")
	assert_gte(CombatScript.burst_window_frames(null), 1, "no weapon still yields a legal (non-zero) window")


func test_pool_reuse_drops_a_half_fired_burst() -> void:
	# NPC-pooling reuse (NpcPool -> NpcCombat.reset_for_reuse): a body that died mid-string must NOT owe those
	# rounds on its next life, or it spits them out on its first armed frame ahead of the fresh wind-up
	# NPC.reset_for_reuse just seeded.
	var c = CombatScript.new()
	c._burst_left = 2
	c._burst_gap = 0.1
	c._burst_lost = 0.09
	c._burst_deadline = 999999
	c.reset_for_reuse()
	assert_eq(c._burst_left, 0, "a reused NPC owes no rounds from its previous life")
	assert_eq(c._burst_gap, 0.0, "...and its burst clock starts cold")
	assert_eq(c._burst_lost, 0.0, "...its lost-shot grace starts cold")
	assert_eq(c._burst_deadline, 0, "...and it carries no deadline from the body that died")
	c.free()


# --- AGILITY and the AI's melee clock (2026-09-02) ---------------------------------------------------
# A wielder's AGILITY compresses a MELEE swing at Attack.effective_attack_speed, so NPC._shot_interval passes
# the same Attack.melee_time_scale_for factor into shot_interval_for. The two clocks MUST be scaled by one
# number: Attack silently refuses a shot inside its own cadence (a gate from_ai does not bypass) while
# NpcCombat._fire_round re-arms the AI timer regardless, so a sluggish body whose AI clock ran FASTER than its
# Attack cadence would drop every second swing and land at half the rate its stat sheet asked for.

func test_shot_interval_melee_scale_defaults_to_a_no_op() -> void:
	# The parameter is optional so every pre-existing call site and test reads identically — a baseline sheet
	# produces a 1.0 scale, and 1.0 must be arithmetically invisible.
	var floor_s: float = GameSettings.npc_ai.min_shot_interval
	var pistol: WeaponData = load("res://resources/weapons/pistol.tres")
	var melee: WeaponData = load("res://resources/weapons/melee.tres")
	assert_almost_eq(NPC.shot_interval_for(pistol, 1.136, floor_s),
		NPC.shot_interval_for(pistol, 1.136, floor_s, 1.0), 0.0001,
		"omitting melee_scale is exactly the same as passing 1.0 — a baseline NPC paces as it always did")
	assert_almost_eq(NPC.shot_interval_for(melee, 1.0, floor_s, 1.0), melee.attack_speed, 0.0001,
		"and a baseline melee NPC keeps the knife's authored 0.88 s swing")

func test_shot_interval_melee_scale_moves_the_ai_clock_with_the_weapon() -> void:
	var floor_s: float = GameSettings.npc_ai.min_shot_interval
	var melee: WeaponData = load("res://resources/weapons/melee.tres")
	assert_almost_eq(NPC.shot_interval_for(melee, 1.0, floor_s, 0.8), melee.attack_speed * 0.8, 0.0001,
		"an agility-4 body's AI clock shortens by the same 20% its Attack cadence does")
	assert_almost_eq(NPC.shot_interval_for(melee, 1.0, floor_s, 1.15), melee.attack_speed * 1.15, 0.0001,
		"and a clumsy body's clock lengthens with it instead of asking for swings the weapon will refuse")

func test_ai_melee_clock_never_outruns_the_attack_cadence_at_any_agility() -> void:
	# ⭐ The regression this pairing exists to prevent, checked end to end against the SHIPPED melee NPC:
	# scenes/characters/NPC.tscn wields melee.tres at rate_of_fire_factor 1.136. Before the two clocks shared a
	# scale, agility -3 put the AI interval (0.9997 s) UNDER the Attack cadence (1.012 s) and every second swing
	# request was swallowed. The invariant is simply: the AI never asks faster than the weapon can swing.
	var floor_s: float = GameSettings.npc_ai.min_shot_interval
	var min_cadence: float = GameSettings.weapon_general.min_melee_attack_speed
	var melee: WeaponData = load("res://resources/weapons/melee.tres")
	var rate := 1.136  # scenes/characters/NPC.tscn
	for agi in [0, 4, 10, 13, 20, -3, -10]:
		var sheet := CharacterStats.new()
		sheet.agility = agi
		var scale: float = Attack.melee_time_scale_for(melee, sheet.melee_time_mult(), min_cadence)
		var cadence: float = melee.attack_speed * scale
		var interval: float = NPC.shot_interval_for(melee, rate, floor_s, scale)
		assert_gte(interval, cadence - 0.0001,
			"agility %d: the AI's melee clock (%.4fs) must not run under the weapon's own cadence (%.4fs), or Attack silently eats the swing" % [agi, interval, cadence])
		sheet = null

func test_melee_time_scale_for_is_a_no_op_on_anything_that_is_not_melee() -> void:
	# The scale is applied unconditionally in shot_interval_for, so it has to answer 1.0-shaped for the cases
	# that must not move: a gun, a null weapon, and a weapon with no authored cadence to divide by.
	var min_cadence: float = GameSettings.weapon_general.min_melee_attack_speed
	var pistol: WeaponData = load("res://resources/weapons/pistol.tres")
	assert_almost_eq(Attack.melee_time_scale_for(pistol, 0.5, min_cadence), 0.5, 0.0001,
		"a RANGED weapon passes the multiplier straight through — the floor is a melee bound and must not clamp a gun")
	assert_almost_eq(Attack.melee_time_scale_for(null, 0.5, min_cadence), 0.5, 0.0001,
		"a null weapon has nothing to floor against")
	var no_cadence := WeaponData.new()
	no_cadence.is_melee = true
	no_cadence.attack_speed = 0.0
	assert_almost_eq(Attack.melee_time_scale_for(no_cadence, 0.5, min_cadence), 0.5, 0.0001,
		"a 0 attack_speed is skipped rather than divided by — it is already broken today (test_smoke pins every shipped weapon above 0) and must not become a crash")
	no_cadence = null

func test_melee_time_scale_for_floor_never_slows_an_authored_swing() -> void:
	# Same neutrality trap as Attack._duration_floor: the floor bounds how far agility may COMPRESS a cadence,
	# it does not declare a minimum every melee weapon must take. A knife authored under the floor keeps its rate.
	var min_cadence: float = GameSettings.weapon_general.min_melee_attack_speed
	var fast := WeaponData.new()
	fast.is_melee = true
	fast.attack_speed = min_cadence * 0.5
	assert_almost_eq(Attack.melee_time_scale_for(fast, 1.0, min_cadence), 1.0, 0.0001,
		"a baseline sheet on a weapon authored FASTER than the floor still scales by exactly 1.0 — the floor must never slow anything")
	var slow := WeaponData.new()
	slow.is_melee = true
	slow.attack_speed = 1.0
	assert_almost_eq(Attack.melee_time_scale_for(slow, 0.0, min_cadence), min_cadence, 0.0001,
		"a multiplier of 0 (agility 20) is raised so the 1.0 s cadence lands on the floor, never on zero")
	fast = null
	slow = null
