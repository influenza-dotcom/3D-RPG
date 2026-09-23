extends GutTest

## What happens to a hit after it lands. Two halves:
##
## HitResolution.award_collateral_kill — the shared post-take_damage collateral payout extracted (M11) from the two
## near-identical inline copies (damage_trace hitscan + projectile pierce). Pins: a non-lethal hit -> false + no pay;
## a lethal FIRST kill -> true + no pay (it only latches); a lethal FOLLOW-UP kill (prior_kill set) -> pays the
## collateral bounty (the headshot variant on a crit); a null attacker never pays; a pierce through an already-dead
## body (hp_before <= 0) -> false.
##
## Projectile._on_body_entered — the fired round's side of the same hit, DRIVEN: a real round (a bare Projectile
## subclass whose two cosmetic hooks do nothing) is put in the tree beside a real in-tree Character and its contact
## callback is called directly, the way the solver would. Pins: a round lands its hit with NO surface point (the
## Vector3.INF sentinel, a deliberate asymmetry vs the raycast path); an overkill round flies on through a living enemy
## it kills, carrying only the excess, and the weapon flag turns that off; it STOPS in a corpse and in the player
## (both regressions parked a live round at the death spot), in an armoured enemy that survives it, and in a body it
## killed with nothing left over; a surviving pierce is de-spun, leaves at a real speed even
## when the solver handed back a crawl or a dead stop, and keeps a pace that was already above that floor; the life
## timer despawns on the wall clock under slow-mo.
##
## HARNESS RULES:
##   - Every round but the life-timer test gets SAFE_LIFE_TIME: Projectile._ready (via _pass_see_through_geometry) awaits a life timer,
##     and resuming it after the round was freed is an engine error GUT 9.6 fails on (tests/test_projectiles.gd).
##   - The round is a test subclass, not Projectile.tscn: everything under test lives on the Projectile BASE, and the
##     Bullet hooks (blood particles, decals, impact SFX clones) are covered by tests/test_projectiles.gd. With no
##     impact SFX wired, _emit_impact returns before it touches the tree root, so nothing leaks out of a test.
##   - Victims are in-tree (is_headshot / to_local need a transform) bare Characters — never an NPC or Player, whose
##     _ready builds weapons and nav. _begin_death is a no-op so a kill leaves the body standing (as the NPC's
##     death-freeze beat does) instead of bursting gore into the world.
##   - The round is unattributed (shooter null, as when the shooter died mid-flight): the shooter-side hooks need an
##     in-tree Player/NPC, and the pierce decision never consults the shooter.
##
## COVERED ELSEWHERE:
##   - A fired round never tumbles (Bullet's rotation lock) while a lobbed rock does:
##     tests/test_projectiles.gd test_a_fired_round_never_tumbles_but_a_lobbed_rock_does.


## A Character we can spy on: record the collateral rewards + toasts award_collateral_kill drives, WITHOUT reward_kill's
## real add_money side effect. Character is @abstract with NO abstract methods, so a concrete subclass instantiates.
class _SpyAttacker extends Character:
	var rewards: Array[float] = []
	var toasts: Array[String] = []
	func reward_kill(amount: float) -> void:
		rewards.append(amount)
	func notify_toast(text: String, _color: Color) -> void:
		toasts.append(text)


## An in-tree victim whose death leaves the body where it fell: the base _begin_death bursts gore into the world and
## frees the node, neither of which this file is about. A corpse that STAYS is exactly what the pierce regression hit.
class _Victim extends Character:
	func _begin_death() -> void:
		pass


## A victim that records the surface point every hit arrived with, then takes the hit for real.
class _HitPosSpy extends _Victim:
	var hit_positions: Array[Vector3] = []
	func take_damage(_amount: float, was_crit: bool = false, attacker: Node = null, hit_pos: Vector3 = Vector3.INF) -> void:
		hit_positions.append(hit_pos)
		super(_amount, was_crit, attacker, hit_pos)


## The smallest concrete round: the Projectile base with its two per-variant cosmetic hooks stubbed out.
class _Round extends Projectile:
	func particles(_body, _last_velocity) -> void:
		pass
	func _spawn_decal(_last_velocity: Vector3) -> void:
		pass


## Far longer than any run: see HARNESS RULES.
const SAFE_LIFE_TIME: float = 600.0
## Far from the origin, so nothing another suite leaves near it is in play. Tests offset their bodies off this point.
const ARENA := Vector3(-160.0, 120.0, 160.0)
## Where the round sits against its victim: level with the victim's origin (below the base head_local_y, so a body
## shot — no crit multiplier) and a hair in front.
const BODY_SHOT := Vector3(0.0, 0.0, 0.3)
## The round's authored launch speed and heading (horizontal: Projectile._ready's look_at errors on a vertical one).
const LAUNCH_SPEED: float = 40.0
const HEADING := Vector3(1.0, 0.0, -1.0) * 0.70710678
const ENEMY_HP: float = 10.0
## Four times ENEMY_HP: lethal with room to spare even at the easiest damage_taken_mult (0.5) on a player victim.
const OVERKILL_DAMAGE: float = 40.0
## What the solver hands body_entered after a square hit on a heavy body: about one 60 Hz gravity step of speed.
const CRAWL_SPEED: float = 0.018
## A deep slow-mo (the death cinematic runs at 0.3), and a life short enough to watch run out.
const SLOW_MO_SCALE: float = 0.1
const SHORT_LIFE: float = 0.25

var _saved_time_scale: float = 1.0


func before_each() -> void:
	_saved_time_scale = Engine.time_scale


func after_each() -> void:
	Engine.time_scale = _saved_time_scale


# --- award_collateral_kill -------------------------------------------------------------------------------------------

func test_non_lethal_hit_returns_false_and_pays_nothing() -> void:
	var atk := _SpyAttacker.new()
	var killed := HitResolution.award_collateral_kill(3.0, 10.0, false, atk, true)  # loss (3) < hp_before (10)
	assert_false(killed, "a non-lethal hit is not a kill")
	assert_eq(atk.rewards.size(), 0, "no collateral for a hit that didn't kill")
	atk.free()


func test_lethal_first_kill_returns_true_but_pays_nothing() -> void:
	# prior_kill = false: the FIRST Character to die to this pellet/round latches (returns true) but pays no
	# collateral — collateral is only for a kill that FOLLOWS a kill.
	var atk := _SpyAttacker.new()
	var killed := HitResolution.award_collateral_kill(10.0, 10.0, false, atk, false)
	assert_true(killed, "a lethal blow on a living victim is a kill")
	assert_eq(atk.rewards.size(), 0, "the first kill of a pellet/round pays no collateral")
	atk.free()


func test_lethal_followup_bodyshot_pays_body_collateral() -> void:
	var atk := _SpyAttacker.new()
	var killed := HitResolution.award_collateral_kill(10.0, 10.0, false, atk, true)  # prior_kill set, not a crit
	assert_true(killed, "lethal follow-up kill")
	assert_eq(atk.rewards.size(), 1, "a follow-up kill pays collateral once")
	assert_eq(atk.rewards[0], GameSettings.economy.collateral_bounty, "a body-shot follow-up pays the body collateral bounty")
	assert_eq(atk.toasts.size(), 1, "and toasts the collateral kill")
	atk.free()


func test_lethal_followup_headshot_pays_headshot_collateral() -> void:
	var atk := _SpyAttacker.new()
	var killed := HitResolution.award_collateral_kill(10.0, 10.0, true, atk, true)  # was_crit -> headshot variant
	assert_true(killed, "lethal follow-up headshot kill")
	assert_eq(atk.rewards[0], GameSettings.economy.collateral_headshot_bounty, "a headshot follow-up pays the headshot collateral bounty")
	atk.free()


func test_null_attacker_never_pays_but_still_reports_the_kill() -> void:
	# An unattributed projectile (its shooter died mid-flight) still reports the kill for the caller's latch, but
	# there is no one to pay — must not crash on the null attacker.
	var killed := HitResolution.award_collateral_kill(10.0, 10.0, false, null, true)
	assert_true(killed, "the kill is still reported for the caller's pierce latch")


func test_pierce_through_dead_body_is_not_a_kill() -> void:
	# hp_before <= 0: a pierce carrying through an already-dead body — not a fresh kill, no collateral.
	var atk := _SpyAttacker.new()
	var killed := HitResolution.award_collateral_kill(5.0, 0.0, false, atk, true)
	assert_false(killed, "a pierce through an already-dead body is not a kill")
	assert_eq(atk.rewards.size(), 0, "and pays no collateral")
	atk.free()


# --- Projectile harness ----------------------------------------------------------------------------------------------

## A real round in the tree at `pos`, flying HEADING at LAUNCH_SPEED, dealing `dmg`, overkill penetration ON.
func _round_at(pos: Vector3, dmg: float, life: float = SAFE_LIFE_TIME) -> _Round:
	var r := _Round.new()
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"  # Projectile's @onready collision_shape_3d
	shape.shape = SphereShape3D.new()
	r.add_child(shape)
	r.life_time = life
	r.gravity_scale = 0.0
	r.speed = LAUNCH_SPEED
	r.direction = HEADING
	r.damage = dmg
	r.overkill_penetration = true
	add_child_autofree(r)
	r.global_position = pos
	return r


## A living in-tree victim at `pos` with `hp` of `hp`, standing still (no gravity drift if a frame passes).
func _victim_at(pos: Vector3, hp: float, victim: _Victim = null) -> _Victim:
	var v: _Victim = victim if victim != null else _Victim.new()
	add_child_autofree(v)
	v.set_physics_process(false)
	v.global_position = pos
	v.max_hp = hp
	v.hp = hp
	return v


## Land `r` on `victim` the way the solver does: `arrival` is the velocity body_entered reads back post-solve.
func _strike(r: Projectile, victim: Node, arrival: Vector3) -> void:
	r.global_position = (victim as Node3D).global_position + BODY_SHOT
	r.linear_velocity = arrival
	r._on_body_entered(victim)


## A round that just killed a living enemy with `arrival` as its post-solve velocity — the pierce every
## velocity test below inspects. Fails loudly if the harness didn't produce a pierce at all.
func _pierce_with_arrival(at: Vector3, arrival: Vector3) -> _Round:
	var enemy := _victim_at(at, ENEMY_HP)
	var r := _round_at(at, OVERKILL_DAMAGE)
	_strike(r, enemy, arrival)
	assert_false(r.is_queued_for_deletion(),
		"harness: an overkill round killing a living enemy must pierce, or the velocity it leaves with is moot")
	return r


# --- Projectile: where the hit lands ---------------------------------------------------------------------------------

func test_a_fired_round_lands_its_hit_with_no_surface_point() -> void:
	# A flying round has never carried a surface point: it lands position-agnostically (hit_pos = Vector3.INF), so its
	# hits never run the located-hit branches (limb damage, crippling) the raycast path's exact ray hit drives.
	var spy := _victim_at(ARENA, 100.0, _HitPosSpy.new()) as _HitPosSpy
	var r := _round_at(ARENA, 5.0)
	_strike(r, spy, HEADING * LAUNCH_SPEED)
	assert_eq(spy.hit_positions.size(), 1, "one round landing on an enemy must deal exactly one hit")
	if spy.hit_positions.size() == 1:
		assert_false(spy.hit_positions[0].is_finite(),
			"a fired round must land its hit with NO surface point (Vector3.INF) — a finite point turns every projectile hit into a located limb hit the raycast path alone is meant to deal")
	# CONTROL: the spy is not blind to a real surface point — the raycast path's form of the same dispatch.
	DamageApplier.apply(spy, 1.0, false, null, spy.global_position)
	assert_eq(spy.hit_positions.size(), 2, "CONTROL: the raycast-path dispatch reaches the same victim")
	if spy.hit_positions.size() == 2:
		assert_true(spy.hit_positions[1].is_finite(),
			"CONTROL: a hit that does carry a surface point arrives finite, so the INF above is the round's doing")


# --- Projectile: the overkill pierce gate ----------------------------------------------------------------------------

func test_an_overkill_kill_on_a_living_enemy_flies_on_carrying_only_the_excess() -> void:
	var enemy := _victim_at(ARENA, ENEMY_HP)
	var r := _round_at(ARENA, OVERKILL_DAMAGE)
	_strike(r, enemy, HEADING * LAUNCH_SPEED)
	assert_false(enemy.is_alive(), "harness: the round must kill the enemy")
	assert_false(r.is_queued_for_deletion(),
		"an overkill round that kills a living enemy must fly on into whoever is behind, not be consumed")
	assert_true(r.get_collision_exceptions().has(enemy),
		"...and ignore the body it just went through, or it re-hits that corpse on the next physics step")
	assert_almost_eq(r.damage, OVERKILL_DAMAGE - ENEMY_HP, 0.001,
		"...carrying only the damage the kill didn't need into the next victim, not the whole round again")

	# CONTROL: the weapon flag is what allows it — the same kill with overkill_penetration off stops in the body.
	var other := _victim_at(ARENA + Vector3(4.0, 0.0, 0.0), ENEMY_HP)
	var plain := _round_at(ARENA + Vector3(4.0, 0.0, 0.0), OVERKILL_DAMAGE)
	plain.overkill_penetration = false
	_strike(plain, other, HEADING * LAUNCH_SPEED)
	assert_false(other.is_alive(), "CONTROL harness: the plain round must kill too")
	assert_true(plain.is_queued_for_deletion(),
		"a weapon without overkill penetration must stop in the enemy it kills, however much damage is left over")


func test_an_overkill_round_stops_in_a_corpse_instead_of_piercing_it() -> void:
	# REGRESSION (the round parked and spinning at the death spot): `hp` is unclamped, so a corpse reads back a
	# NEGATIVE hp; the _dead latch makes take_damage a no-op; so "the hit took at least the HP it had" held VACUOUSLY
	# (0 >= -3) and every follow-up round pierced the corpse and hung there.
	var corpse := _victim_at(ARENA, ENEMY_HP)
	corpse.take_damage(ENEMY_HP + 3.0)  # an earlier round killed it
	assert_true(corpse.hp < 0.0 and not corpse.is_alive(), "harness: the corpse must be dead with a negative hp")
	var r := _round_at(ARENA, OVERKILL_DAMAGE)
	_strike(r, corpse, HEADING * LAUNCH_SPEED)
	assert_true(r.is_queued_for_deletion(),
		"an overkill round hitting an already-dead body must stop in it — piercing a corpse is what parked live rounds at the death spot")
	assert_false(r.get_collision_exceptions().has(corpse),
		"...and must not except itself from the corpse as a pierce would")

	# CONTROL: the same round into a LIVING enemy with the same HP pierces, so the stop above is the corpse's doing.
	var living := _victim_at(ARENA + Vector3(4.0, 0.0, 0.0), ENEMY_HP)
	var control := _round_at(ARENA + Vector3(4.0, 0.0, 0.0), OVERKILL_DAMAGE)
	_strike(control, living, HEADING * LAUNCH_SPEED)
	assert_false(control.is_queued_for_deletion(),
		"CONTROL: the same overkill round must pierce a living enemy it kills")


func test_the_round_that_kills_the_player_stops_in_the_body() -> void:
	# REGRESSION: the corpse guard does not help here — you were still ALIVE when the round landed, so every other term
	# of the pierce gate passes on EVERY player death. The round then excepted itself from your body and flew on past
	# a first-person camera about to spend 1.6 s keeling over next to it. There is nothing behind the player worth
	# carrying overkill into.
	var player := _victim_at(ARENA, ENEMY_HP)
	player.add_to_group(Groups.PLAYER)
	var r := _round_at(ARENA, OVERKILL_DAMAGE)
	_strike(r, player, HEADING * LAUNCH_SPEED)
	var killed := not player.is_alive()
	player.remove_from_group(Groups.PLAYER)
	assert_true(killed, "harness: the round must kill the player, so every other pierce term is satisfied")
	assert_true(r.is_queued_for_deletion(),
		"the round that kills the player must stop in the body, never fly on past the dying first-person camera")
	assert_false(r.get_collision_exceptions().has(player),
		"...and must not except itself from the player's body as a pierce would")

	# CONTROL: the same round, the same HP, a victim NOT in the player group — it pierces.
	var npc := _victim_at(ARENA + Vector3(4.0, 0.0, 0.0), ENEMY_HP)
	var control := _round_at(ARENA + Vector3(4.0, 0.0, 0.0), OVERKILL_DAMAGE)
	_strike(control, npc, HEADING * LAUNCH_SPEED)
	assert_false(control.is_queued_for_deletion(),
		"CONTROL: the same overkill round must pierce a non-player victim it kills")


func test_an_overkill_round_stops_in_an_armoured_enemy_that_survives_it() -> void:
	# CT-2: armour mitigates INSIDE take_damage, so the round's pre-mitigation damage still exceeds the enemy's HP (an
	# "overkill" on paper) while the HP actually lost does not. Piercing on paper sends a round through a LIVING body.
	var tank := _victim_at(ARENA + Vector3(0.0, 0.0, 40.0), ENEMY_HP)
	tank.armor_flat = OVERKILL_DAMAGE - ENEMY_HP * 0.5  # soaks all but half the enemy's HP
	var r := _round_at(tank.global_position, OVERKILL_DAMAGE)
	_strike(r, tank, HEADING * LAUNCH_SPEED)
	assert_true(tank.is_alive() and tank.hp < ENEMY_HP,
		"harness: the armoured enemy must be hurt by the round but survive it")
	assert_true(r.is_queued_for_deletion(),
		"an overkill round that an armoured enemy SURVIVES must stop in it, never pierce through a living body")
	assert_false(r.get_collision_exceptions().has(tank),
		"...and must not except itself from the survivor as a pierce would")

	# CONTROL: the same round into an UNARMOURED enemy with the same HP kills it and pierces, so the stop is the armour's.
	var bare := _victim_at(tank.global_position + Vector3(4.0, 0.0, 0.0), ENEMY_HP)
	var control := _round_at(bare.global_position, OVERKILL_DAMAGE)
	_strike(control, bare, HEADING * LAUNCH_SPEED)
	assert_false(bare.is_alive(), "CONTROL harness: without armour the same round must kill")
	assert_false(control.is_queued_for_deletion(),
		"CONTROL: the same overkill round must pierce an unarmoured enemy it kills")


func test_a_round_that_deals_exactly_the_kill_stops_in_the_body() -> void:
	# A kill with nothing left over has nothing to carry: a round that flew on anyway would be a zero-damage round still
	# shoving and playing impact effects on whoever stands behind the body.
	var enemy := _victim_at(ARENA + Vector3(0.0, 0.0, 48.0), ENEMY_HP)
	var r := _round_at(enemy.global_position, ENEMY_HP)  # unattributed: nothing scales it, so it deals exactly ENEMY_HP
	_strike(r, enemy, HEADING * LAUNCH_SPEED)
	assert_false(enemy.is_alive(), "harness: a round dealing exactly the enemy's HP must kill it")
	assert_true(r.is_queued_for_deletion(),
		"a round that deals exactly the kill has nothing left to carry and must stop in the body")
	assert_false(r.get_collision_exceptions().has(enemy),
		"...and must not except itself from the body as a pierce would")

	# CONTROL: a round with damage to spare into a same-HP enemy pierces, so the stop is the missing excess's doing.
	var other := _victim_at(enemy.global_position + Vector3(4.0, 0.0, 0.0), ENEMY_HP)
	var control := _round_at(other.global_position, OVERKILL_DAMAGE)
	_strike(control, other, HEADING * LAUNCH_SPEED)
	assert_false(other.is_alive(), "CONTROL harness: the overkill round must kill too")
	assert_false(control.is_queued_for_deletion(),
		"CONTROL: a round with damage left over after the kill must pierce")


# --- Projectile: how a pierce leaves -------------------------------------------------------------------------------

func test_a_piercing_round_is_despun() -> void:
	# REGRESSION: the round's collider is a 5 cm sphere but its mesh is a 2.4 m needle, so any spin a contact leaves on
	# a surviving round sweeps a ~3 m disc — a tracer ORBITING whatever it just went through. Contact friction is a
	# torque source with no sink; the pierce must zero it.
	var at := ARENA + Vector3(0.0, 0.0, 8.0)
	var enemy := _victim_at(at, ENEMY_HP)
	var r := _round_at(at, OVERKILL_DAMAGE)
	var spin := Vector3(3.0, 8.0, -2.0)
	r.angular_velocity = spin
	assert_eq(r.angular_velocity, spin, "harness: the contact spin must be on the round before it lands")
	_strike(r, enemy, HEADING * LAUNCH_SPEED)
	assert_false(r.is_queued_for_deletion(), "harness: the round must pierce")
	assert_eq(r.angular_velocity, Vector3.ZERO,
		"a round that survives a pierce must leave with NO spin — any left sweeps its long tracer round the body it went through")


func test_a_pierce_the_solver_slowed_to_a_crawl_still_leaves_the_impact_point() -> void:
	# REGRESSION: body_entered reads velocity POST-SOLVE, so a square hit on a heavy body hands back a crawl — and a
	# crawl is not zero. Restoring it left a live round hanging in the body it pierced (the "hover" the player saw).
	var crawl_dir := Vector3(0.6, -0.1, -0.8).normalized()
	var r := _pierce_with_arrival(ARENA + Vector3(0.0, 0.0, 16.0), crawl_dir * CRAWL_SPEED)
	assert_gt(r.linear_velocity.length(), LAUNCH_SPEED * 0.25,
		"a round that pierces after the solver slowed it to a crawl must leave at a real fraction of its launch speed (the design floor is half), never at the crawl that parks it in the body")
	assert_gt(r.linear_velocity.normalized().dot(crawl_dir), 0.999,
		"...and keep the deflected heading it arrived with")


func test_a_pierce_from_a_dead_stop_leaves_along_the_rounds_own_heading() -> void:
	# A dead stop has no heading to keep: the round flies on along the direction it was fired in.
	var r := _pierce_with_arrival(ARENA + Vector3(0.0, 0.0, 24.0), Vector3.ZERO)
	assert_gt(r.linear_velocity.length(), LAUNCH_SPEED * 0.25,
		"a round the solver stopped dead must still leave a pierce at a real fraction of its launch speed")
	assert_gt(r.linear_velocity.normalized().dot(HEADING), 0.999,
		"...along the heading it was fired in, since a zero velocity has none of its own")


func test_a_pierce_that_kept_its_pace_is_not_slowed_to_the_floor() -> void:
	# The floor only lifts a crawl: a round that went through at speed carries that speed on.
	var arrival := HEADING * (LAUNCH_SPEED * 0.8)
	var r := _pierce_with_arrival(ARENA + Vector3(0.0, 0.0, 32.0), arrival)
	assert_almost_eq(r.linear_velocity.length(), arrival.length(), 0.01,
		"a round that pierces at speed must fly on at the speed it had, not be reset to the slow-hit floor or back to its launch speed")
	assert_gt(r.linear_velocity.normalized().dot(HEADING), 0.999, "...on the same heading")


# --- Projectile: lifetime ------------------------------------------------------------------------------------------

func test_a_rounds_life_timer_runs_on_the_wall_clock_under_slow_mo() -> void:
	# REGRESSION: a round's life is a WALL-CLOCK budget. Counted in game time, the death cinematic's slow-mo stretches a
	# 10 s round to ~33 s of real time and it stops self-cleaning while the player is still watching.
	Engine.time_scale = SLOW_MO_SCALE
	var r := _round_at(ARENA + Vector3(0.0, 0.0, -16.0), 1.0, SHORT_LIFE)
	r.linear_velocity = Vector3.ZERO  # it only has to sit there and expire
	var game_clock := get_tree().create_timer(SHORT_LIFE, true, false, false)
	assert_true(is_instance_valid(r) and not r.is_queued_for_deletion(), "harness: the round must be alive at spawn")
	await get_tree().create_timer(SHORT_LIFE * 3.0, true, false, true).timeout
	assert_gt(game_clock.time_left, 0.0,
		"CONTROL: a game-time timer of the same length must still be running under this slow-mo, or the harness isn't slowing anything")
	# Freed, or queued this very frame: one long frame can expire both timers together, and then the despawn's
	# queue_free has not been flushed yet when this resumes.
	assert_true(not is_instance_valid(r) or r.is_queued_for_deletion(),
		"a round must despawn once its life_time has passed in REAL time even under slow-mo — a game-time life leaves it flying for the whole death cinematic")
