extends GutTest

## ShotResolver damage math (Wave 3 #7 — the DamageApplier dedup). The crit/sneak scaling is now SHARED by the
## hitscan path (attack.gd via resolve_damage) and the projectile path (projectile.gd via scaled_damage)
## instead of being hand-synced. Golden values pin the dedup so a pellet and a fired round resolve a first hit
## identically. Pure statics — no tree, no nodes.

func test_scaled_damage_applies_crit_and_sneak_multipliers() -> void:
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 3.0, false, false), 10.0, 0.0001,
		"no crit, no sneak -> base damage unchanged")
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 3.0, true, false), 20.0, 0.0001,
		"crit only -> base * crit_mult")
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 3.0, false, true), 30.0, 0.0001,
		"sneak only -> base * sneak_mult")
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 3.0, true, true), 60.0, 0.0001,
		"crit AND sneak stack -> base * crit_mult * sneak_mult")


func test_resolve_damage_matches_scaled_damage_for_a_first_hit() -> void:
	# A first hit (pierce < 0) must equal scaled_damage from the weapon's fields, so the hitscan path agrees
	# with the projectile path. A penetrating segment (pierce >= 0) carries the flat overkill, no multipliers.
	var w := WeaponData.new()
	w.damage = 12.0
	w.headshot_multiplier = 2.0
	w.sneak_attack_multiplier = 1.5
	assert_almost_eq(ShotResolver.resolve_damage(w, true, true, -1.0),
		ShotResolver.scaled_damage(12.0, 2.0, 1.5, true, true), 0.0001,
		"resolve_damage(first hit) == scaled_damage from the weapon's fields (both paths agree)")
	assert_almost_eq(ShotResolver.resolve_damage(w, false, false, -1.0), 12.0, 0.0001,
		"resolve_damage with no crit/sneak == the weapon's base damage")
	assert_almost_eq(ShotResolver.resolve_damage(w, true, true, 7.0), 7.0, 0.0001,
		"a penetrating segment (pierce >= 0) deals the flat overkill, ignoring crit/sneak")
	w = null
