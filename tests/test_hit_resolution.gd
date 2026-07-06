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
