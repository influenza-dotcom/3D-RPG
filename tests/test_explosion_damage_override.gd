extends GutTest

## M9: blast DAMAGE is per-weapon (WeaponData.explosion_damage) forwarded onto the Explosion, with a -1 sentinel that
## falls back to the global GameSettings.physics_damage.explosion_damage. Force + radius were already per-weapon;
## damage was the last blast field stuck on the global knob, so a rocket and a grenade dealt identical blast damage.

const ExplosionScript := preload("res://scripts/components/explosion_area.gd")


func test_resolve_damage_override_wins_and_negative_falls_back() -> void:
	assert_almost_eq(ExplosionScript.resolve_damage(7.0, 40.0), 7.0, 0.001, "a per-instance override (>= 0) wins over the global")
	assert_almost_eq(ExplosionScript.resolve_damage(0.0, 40.0), 0.0, 0.001, "an override of 0 is a real value (a shove-only blast), not 'unset'")
	assert_almost_eq(ExplosionScript.resolve_damage(-1.0, 40.0), 40.0, 0.001, "-1 falls back to the global explosion_damage")


func test_explosion_default_damage_is_sentinel() -> void:
	# An unconfigured explosion (e.g. an ExplosiveBarrel blast, which never sets explosion_damage) defaults to -1, so
	# it uses the global fallback exactly as before M9. .new() is safe: @onready/_ready don't run off-tree.
	var ex = ExplosionScript.new()
	assert_almost_eq(ex.explosion_damage, -1.0, 0.001, "explosion_damage defaults to the -1 global-fallback sentinel")
	ex.free()


func test_weapon_data_default_explosion_damage_is_sentinel() -> void:
	var w := WeaponData.new()
	assert_almost_eq(w.explosion_damage, -1.0, 0.001, "WeaponData.explosion_damage defaults to -1 (global fallback) — a weapon opts IN to custom blast damage")
	w = null


func test_projectile_spawner_forwards_weapon_explosion_damage() -> void:
	# The forward seam: a weapon's projectile blast must carry the weapon's explosion_damage onto its Explosion node.
	var src := FileAccess.get_file_as_string("res://scripts/projectiles/projectile_spawner.gd")
	assert_true(src.contains("explosion_damage = current_weapon.explosion_damage"), "ProjectileSpawner must forward WeaponData.explosion_damage to the Explosion")


func test_explosion_bridge_has_and_forwards_explosion_damage() -> void:
	# The projectile "Explosion" child is the explosion.gd BRIDGE (a Node3D), NOT the Area3D `class_name Explosion`.
	# So the M9 forward (ProjectileSpawner -> bridge -> spawned Explosion) is DEAD unless the bridge exposes
	# explosion_damage (or the spawner's write is a phantom set that errors) AND the bridge passes it on. .new() is
	# safe: the bridge is a plain Node3D with no _ready.
	var bridge = load("res://scripts/effects/explosion.gd").new()
	assert_almost_eq(bridge.explosion_damage, -1.0, 0.001, "the explosion bridge must expose explosion_damage so ProjectileSpawner's write lands (not a phantom set)")
	bridge.free()
	var src := FileAccess.get_file_as_string("res://scripts/effects/explosion.gd")
	assert_true(src.contains("explosion.explosion_damage = _damage"), "the bridge's _spawn_at must forward explosion_damage onto the spawned Explosion")
	# Anchored WITHOUT the closing paren: _spawn_at grew a trailing deals_damage arg after this pin was written
	# (the exact source-text-pin drift CLAUDE.md warns about), so pin only the pass-through pair itself.
	assert_true(src.contains("explosion_radius, explosion_damage"), "the rock/rocket path must pass explosion_damage into _spawn_at (the spark path stays at the -1 fallback)")


func test_barrel_does_not_override_explosion_damage() -> void:
	# ExplosiveBarrel is an ENVIRONMENTAL blast (no WeaponData) — it must NOT set explosion_damage, so its blast keeps
	# the -1 sentinel and uses the global fallback (it still sets max_explosion_force + explosion_radius).
	var src := FileAccess.get_file_as_string("res://scripts/components/explosive_barrel.gd")
	# Positive anchor FIRST: a moved/renamed file reads as "" and "".contains() is false, so the negative pin
	# below would retire itself in silence (the test_atm_screen_scene rule: an unanchored negative pin is worse
	# than no pin). The barrel DOES set explosion_radius, so this line proves the read landed.
	assert_true(src.contains("explosion_radius"), "explosive_barrel.gd must be readable at this path — an empty read would vacuously pass the negative pin below")
	assert_false(src.contains(".explosion_damage"), "ExplosiveBarrel must leave explosion_damage at the -1 sentinel (environmental blast -> global fallback)")
