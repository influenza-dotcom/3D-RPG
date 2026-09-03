extends GutTest

## HitResolution.award_collateral_kill — the shared post-take_damage collateral payout extracted (M11) from the two
## near-identical inline copies (damage_trace hitscan + projectile pierce). Pins: a non-lethal hit -> false + no pay;
## a lethal FIRST kill -> true + no pay (it only latches); a lethal FOLLOW-UP kill (prior_kill set) -> pays the
## collateral bounty (the headshot variant on a crit); a null attacker never pays; a pierce through an already-dead
## body (hp_before <= 0) -> false. Plus a source-scan pinning the projectile's Vector3.INF position-agnostic apply
## contract that M11 must NOT silently flip to directional.


## A Character we can spy on: record the collateral rewards + toasts award_collateral_kill drives, WITHOUT reward_kill's
## real add_money side effect. Character is @abstract with NO abstract methods, so a concrete subclass instantiates.
class _SpyAttacker extends Character:
	var rewards: Array[float] = []
	var toasts: Array[String] = []
	func reward_kill(amount: float) -> void:
		rewards.append(amount)
	func notify_toast(text: String, _color: Color) -> void:
		toasts.append(text)


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


func test_projectile_apply_stays_position_agnostic() -> void:
	# M11 CONTRACT (projectile.gd:97-99): a fired round carries NO surface point — DamageApplier.apply is called
	# WITHOUT a hit_pos (the Vector3.INF default), a deliberate asymmetry vs the raycast path. The extraction left
	# apply in the caller, so this is preserved by construction; this source-scan pins it against a future silent flip.
	var src := FileAccess.get_file_as_string("res://scripts/projectiles/projectile.gd")
	assert_true(src.contains("DamageApplier.apply(body, dealt, was_crit, shooter)"),
		"projectile applies damage position-agnostically (4-arg apply, no hit_pos) — Vector3.INF contract preserved")


func test_projectile_pierce_gate_refuses_a_corpse_and_the_player() -> void:
	# REGRESSION (the parked/spinning round at the death spot). The pierce gate must refuse TWO victims, and they
	# fail for OPPOSITE reasons — fixing only one leaves the bug standing, which is exactly what happened once.
	#   (a) `hp_before > 0.0` — an ALREADY-DEAD body. `hp` is unclamped, so a corpse reads back a NEGATIVE hp_before;
	#       the _dead latch makes take_damage a no-op so real_loss is 0.0; and `overkill` inflates to dealt + |hp|.
	#       So `real_loss >= hp_before` passes VACUOUSLY (0.0 >= -3.0) and every follow-up round pierces the corpse.
	#   (b) `not body.is_in_group(Groups.PLAYER)` — the round that KILLS you, where (a) does NOT help: you were still
	#       ALIVE, so hp_before is a healthy positive number and every term passes deterministically on EVERY player
	#       death. The round then excepts itself from your corpse, un-consumes, and returns past queue_free().
	# Pin the WHOLE gate expression, not the bare terms: they must sit in THIS condition, and a source-scan for
	# "hp_before > 0.0" alone would be satisfied by any other line — or by the comment that explains it.
	var src := FileAccess.get_file_as_string("res://scripts/projectiles/projectile.gd")
	assert_string_contains(src,
			"var will_penetrate := overkill_penetration and hp_before > 0.0 and not body.is_in_group(Groups.PLAYER) and real_loss >= hp_before and overkill > 0.0")


func test_a_surviving_pierce_is_despun() -> void:
	# REGRESSION: a round's collider is a 5 cm sphere but its mesh is a 2.4 m needle reaching 1.53 m past the pivot
	# (Projectile.tscn scales a radius-0.2 SphereMesh by 6 on Z and offsets it +0.326). Any residual angular_velocity
	# therefore sweeps a ~3 m disc, which reads as a tracer ORBITING whatever the round stopped beside. Contact
	# friction is a torque source with no sink — this assignment is the ONLY line in the project that de-spins a round.
	var src := FileAccess.get_file_as_string("res://scripts/projectiles/projectile.gd")
	assert_string_contains(src, "angular_velocity = Vector3.ZERO")


func test_rounds_lock_rotation_but_rocks_still_tumble() -> void:
	# REGRESSION: the structural guarantee behind the de-spin above — a fired ROUND can never tumble at all, on any
	# code path. Free to set, because the only orientation a round ever gets is the one-shot look_at in
	# Projectile._ready() and nothing in the hierarchy re-orients it in flight (no _physics_process, no
	# _integrate_forces, no custom_integrator). It lives on Bullet, NOT on the Projectile base, because
	# RockProjectile is a lobbed rock that SHOULD tumble — pin that split so a future tidy-up cannot hoist it.
	var bullet_src := FileAccess.get_file_as_string("res://scripts/projectiles/bullet.gd")
	assert_string_contains(bullet_src, "lock_rotation = true")
	var base_src := FileAccess.get_file_as_string("res://scripts/projectiles/projectile.gd")
	assert_false(base_src.contains("lock_rotation"),
			"lock_rotation must stay on Bullet, never the Projectile base — RockProjectile is meant to tumble")
	var rock_src := FileAccess.get_file_as_string("res://scripts/projectiles/rock_projectile.gd")
	assert_false(rock_src.contains("lock_rotation"), "a lobbed rock keeps its tumble")


func test_pierce_restore_survives_a_solver_zeroed_velocity() -> void:
	# REGRESSION (same bug, second half): `last_velocity` is read POST-SOLVE inside body_entered, so a square hit on a
	# heavy/kinematic body comes back ~zero. Restoring THAT on a pierce strands a live round hanging in mid-air, which
	# is the "hover" the player actually sees. A bare `> 0.0001` zero-check is NOT enough — a crawl is not zero, and
	# a 60 Hz gravity step alone carries ~0.018 m/s, nearly 2x that threshold, so it almost never fires. The restore
	# must be a SPEED FLOOR that guarantees the round actually departs the impact point.
	var src := FileAccess.get_file_as_string("res://scripts/projectiles/projectile.gd")
	assert_string_contains(src, "linear_velocity = carry_dir * maxf(last_velocity.length(), speed * 0.5)")


func test_projectile_lifetime_despawn_is_wall_clock() -> void:
	# REGRESSION: the lifetime despawn is a WALL-CLOCK budget. With the bare one-arg create_timer, ignore_time_scale
	# is FALSE and the despawn clock is slowed by the very slow-mo that is already stretching the round on screen —
	# the death cinematic pins Engine.time_scale at 0.3, turning a 10 s round into ~33 s of real time and stopping it
	# self-cleaning while the player is still watching. FreezeFrame spells the same argument list out for the same reason.
	var src := FileAccess.get_file_as_string("res://scripts/projectiles/projectile.gd")
	assert_string_contains(src, "create_timer(life_time, true, false, true)")
