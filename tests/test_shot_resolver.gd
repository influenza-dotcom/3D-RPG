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


func test_scaled_damage_applies_backstab_multiplier_when_behind() -> void:
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 3.0, false, false, 4.0, false), 10.0, 0.0001,
		"behind=false -> no backstab bonus")
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 3.0, false, false, 4.0, true), 40.0, 0.0001,
		"behind -> base * backstab_mult")
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 3.0, true, true, 4.0, true), 240.0, 0.0001,
		"crit * sneak * backstab all stack -> 10 * 2 * 3 * 4")
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 3.0, true, true), 60.0, 0.0001,
		"the old 5-arg call is unchanged -> backstab defaults inert (1.0 / false)")


func test_scaled_damage_applies_shooter_gunplay_stats() -> void:
	# PD-1: the SHOOTER's combat stats scale the hit. null / baseline = a pure no-op (existing balance untouched).
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 3.0, false, false, 1.0, false, null), 10.0, 0.0001,
		"null stats -> no scaling (back-compatible)")
	var baseline := CharacterStats.new()
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 3.0, true, true, 1.0, false, baseline),
		ShotResolver.scaled_damage(10.0, 2.0, 3.0, true, true), 0.0001, "a baseline sheet matches the no-stats result")
	var gunner := CharacterStats.new()
	gunner.gunplay = 4  # weapon_damage_mult 1.2, headshot_damage_bonus 1.2
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 3.0, false, false, 1.0, false, gunner), 12.0, 0.0001,
		"gunplay 4 -> +20% raw damage (10 * 1.2)")
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 3.0, true, false, 1.0, false, gunner), 28.8, 0.0001,
		"a crit gets BOTH the weapon crit mult AND the gunplay headshot bonus: 10 * 2 * 1.2 * 1.2")
	baseline = null
	gunner = null


func test_resolve_damage_threads_shooter_stats() -> void:
	var w := WeaponData.new()
	w.damage = 10.0
	w.headshot_multiplier = 1.0
	w.sneak_attack_multiplier = 1.0
	var gunner := CharacterStats.new()
	gunner.gunplay = 4
	assert_almost_eq(ShotResolver.resolve_damage(w, false, false, -1.0, false, gunner), 12.0, 0.0001,
		"resolve_damage threads the shooter's gunplay damage scale (10 * 1.2)")
	assert_almost_eq(ShotResolver.resolve_damage(w, false, false, 7.0, false, gunner), 7.0, 0.0001,
		"an overkill pierce ignores stats (carries the flat leftover)")
	w = null
	gunner = null


func test_resolve_damage_threads_weapon_backstab_multiplier() -> void:
	var w := WeaponData.new()
	w.damage = 10.0
	w.headshot_multiplier = 1.0
	w.sneak_attack_multiplier = 1.0
	w.backstab_multiplier = 2.5
	assert_almost_eq(ShotResolver.resolve_damage(w, false, false, -1.0, true), 25.0, 0.0001,
		"resolve_damage(behind=true) applies the weapon's backstab_multiplier")
	assert_almost_eq(ShotResolver.resolve_damage(w, false, false, -1.0), 10.0, 0.0001,
		"resolve_damage with behind omitted -> no backstab (behaviour-preserving)")
	w = null


func test_melee_weapon_scales_with_strength_not_gunplay() -> void:
	# The split is driven by the EXPLICIT WeaponData.is_melee flag (NOT effective_range — a hitscan melee weapon
	# keeps a positive reach so its raycast lands). is_melee=true -> STRENGTH scales it, gunplay is ignored; a ranged
	# weapon (is_melee=false, the default) is the reverse. resolve_damage reads the weapon to pick the path.
	var melee := WeaponData.new()
	melee.damage = 10.0
	melee.headshot_multiplier = 1.0
	melee.sneak_attack_multiplier = 1.0
	melee.is_melee = true
	melee.effective_range = 3.0  # a real melee weapon still has positive reach (matches melee.tres / fists.tres)
	var bruiser := CharacterStats.new()
	bruiser.strength = 4   # melee_damage_mult 1.2
	bruiser.gunplay = 10   # must NOT touch a melee swing
	assert_almost_eq(ShotResolver.resolve_damage(melee, false, false, -1.0, false, bruiser), 12.0, 0.0001,
		"melee: strength 4 -> +20% (10 * 1.2), gunplay ignored")

	var gun := WeaponData.new()
	gun.damage = 10.0
	gun.headshot_multiplier = 1.0
	gun.sneak_attack_multiplier = 1.0
	gun.effective_range = 20.0  # ranged, is_melee defaults false
	var gunner := CharacterStats.new()
	gunner.gunplay = 4     # weapon_damage_mult 1.2
	gunner.strength = 10   # must NOT touch a gunshot
	assert_almost_eq(ShotResolver.resolve_damage(gun, false, false, -1.0, false, gunner), 12.0, 0.0001,
		"ranged: gunplay 4 -> +20% (10 * 1.2), strength ignored")
	melee = null
	gun = null
	bruiser = null
	gunner = null


func test_scaled_damage_is_melee_flag_uses_strength_and_skips_gunplay_headshot() -> void:
	var bruiser := CharacterStats.new()
	bruiser.strength = 4  # melee_damage_mult 1.2
	# is_melee is the 10th arg (after gunplay_mod), strength_mod the 11th.
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 1.0, false, false, 1.0, false, bruiser, 0.0, true, 0.0), 12.0, 0.0001,
		"is_melee=true -> strength scales (10 * 1.2)")
	# A melee crit keeps the weapon's crit multiplier but NOT the gunplay headshot bonus (gunplay is guns).
	assert_almost_eq(ShotResolver.scaled_damage(10.0, 2.0, 1.0, true, false, 1.0, false, bruiser, 0.0, true, 0.0), 24.0, 0.0001,
		"melee crit: 10 * weapon crit 2 * strength 1.2 = 24 (no gunplay headshot bonus)")
	bruiser = null


## THE "enemies never hitscan" rule (2026-08-25): ai_fires_live_projectile decides whether an AI wielder's
## shot skips the instant damage trace and rides a LIVE spawned round instead. Pinned against the AUTHORED
## .tres roster (the NpcCombat.attempt_fire_range test idiom) because the carve-outs are load-bearing: the
## knife is the DEFAULT NPC.tscn weapon and its swing damage IS the trace — a blanket skip would zero it.
func test_ai_fires_live_projectile_matrix() -> void:
	assert_false(ShotResolver.ai_fires_live_projectile(null),
		"null weapon -> no live-round path (the trace branch handles the nothing-equipped case)")
	var bare := WeaponData.new()
	assert_false(ShotResolver.ai_fires_live_projectile(bare),
		"a ranged weapon authored with NO projectile_scene falls back to the trace — its damage must stay real")
	bare = null
	var knife := load("res://resources/weapons/melee.tres") as WeaponData
	assert_true(knife.is_melee and knife.projectile_scene == null,
		"premise: melee.tres is the is_melee, no-projectile default NPC weapon this rule must carve out")
	assert_false(ShotResolver.ai_fires_live_projectile(knife),
		"MELEE keeps the hitscan trace — a knife swing's reach IS the trace; skipping it zeroes every default-knife NPC")
	knife = null
	var spray := load("res://resources/weapons/spray_paint.tres") as WeaponData
	assert_false(ShotResolver.ai_fires_live_projectile(spray),
		"spray paint is carved out — its fire path is the damage-free _do_spray_paint short-circuit, and 8 live paint rounds per squeeze would weaponize the graffiti tool")
	spray = null
	var pistol := load("res://resources/weapons/pistol.tres") as WeaponData
	assert_true(ShotResolver.ai_fires_live_projectile(pistol),
		"a ranged gun with a projectile_scene (pistol) ALWAYS fires live rounds for AI — enemies never hitscan")
	pistol = null
	var rock := load("res://resources/weapons/rock_weapon.tres") as WeaponData
	assert_true(rock.effective_range == 0.0 and ShotResolver.ai_fires_live_projectile(rock),
		"the effective_range-0 lob (rock) is ALSO live — unlike the grace band, this rule has no range qualifier: its 0m trace never dealt damage anyway")
	rock = null
