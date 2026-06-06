extends GutTest
# Test: load every .tres in res://resources/weapons/ and verify its WeaponData
# fields exist with the right types.

const WEAPONS_DIR := "res://resources/weapons/"

func test_all_weapon_tres_have_required_fields() -> void:
	var files := _list_tres()
	assert_gt(files.size(), 0,
		"There must be at least one weapon .tres in %s to validate" % WEAPONS_DIR)
	for path in files:
		_check_weapon(path)

func _list_tres() -> Array:
	var out: Array = []
	var dir := DirAccess.open(WEAPONS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var _name := dir.get_next()
	while _name != "":
		if not dir.current_is_dir() and _name.ends_with(".tres"):
			out.append(WEAPONS_DIR + _name)
		_name = dir.get_next()
	dir.list_dir_end()
	return out

func _check_weapon(path: String) -> void:
	var w := load(path) as WeaponData
	assert_not_null(w, "%s must load as a WeaponData" % path)
	# damage is declared `float = 1.0` in weapon_data.gd — the .tres int-looking
	# literals still parse as floats, so this is TYPE_FLOAT (NOT TYPE_INT).
	_check_field(w, "damage", TYPE_FLOAT, path)
	_check_field(w, "attack_speed", TYPE_FLOAT, path)
	_check_field(w, "reload_time", TYPE_FLOAT, path)
	# max_ammo and pellet_count are genuinely `int` in source (whole rounds /
	# whole pellets), so they stay TYPE_INT.
	_check_field(w, "max_ammo", TYPE_INT, path)
	_check_field(w, "pellet_count", TYPE_INT, path)
	_check_field(w, "pellet_spread", TYPE_FLOAT, path)
	# Phase 4 additions
	_check_field(w, "screen_shake_amount", TYPE_FLOAT, path)
	_check_field(w, "self_knockback", TYPE_FLOAT, path)
	_check_field(w, "enemy_knockback", TYPE_FLOAT, path)
	_check_field(w, "enemy_lift", TYPE_FLOAT, path)
	_check_field(w, "bullet_gravity_scale", TYPE_FLOAT, path)
	_check_field(w, "launch_angle", TYPE_FLOAT, path)
	_check_field(w, "max_explosion_force", TYPE_FLOAT, path)
	_check_field(w, "explosion_radius", TYPE_FLOAT, path)
	_check_field(w, "use_hitscan", TYPE_BOOL, path)

func _check_field(obj: Object, field: String, expected_type: int, src: String) -> void:
	assert_true(field in obj, "%s must have field '%s'" % [src, field])
	var actual_type := typeof(obj.get(field))
	assert_eq(actual_type, expected_type,
		"%s.%s has type %d, expected %d" % [src, field, actual_type, expected_type])

# --- move_speed_multiplier weights ("heavier weapons slow you while drawn") ---
# These pin the per-weapon move_speed_multiplier values set this session. The
# weight comes from weapon_data.gd where `move_speed_multiplier` defaults to 1.0
# (no penalty); heavier guns set it lower. assert_almost_eq tolerates the float
# round-trip through the .tres. Reuses the existing `load(path) as WeaponData` idiom.

# Shotgun is the heaviest — it slows the holder the most (0.82).
func test_shotgun_move_speed_multiplier_is_heaviest() -> void:
	var w := load("res://resources/weapons/shotgun.tres") as WeaponData
	assert_not_null(w, "shotgun.tres must load as a WeaponData")
	assert_almost_eq(w.move_speed_multiplier, 0.82, 0.0001,
		"shotgun is the heaviest weapon and should slow the holder to 0.82")

# Sniper is heavy but lighter than the shotgun (0.85).
func test_sniper_move_speed_multiplier_is_heavy() -> void:
	var w := load("res://resources/weapons/sniper_wep.tres") as WeaponData
	assert_not_null(w, "sniper_wep.tres must load as a WeaponData")
	assert_almost_eq(w.move_speed_multiplier, 0.85, 0.0001,
		"sniper should slow the holder to 0.85")

# SMG carries only a light movement penalty (0.93).
func test_smg_move_speed_multiplier_is_light_penalty() -> void:
	var w := load("res://resources/weapons/smg.tres") as WeaponData
	assert_not_null(w, "smg.tres must load as a WeaponData")
	assert_almost_eq(w.move_speed_multiplier, 0.93, 0.0001,
		"smg should slow the holder only slightly, to 0.93")

# Pistol is light: it leaves move_speed_multiplier at the 1.0 default (no penalty).
func test_pistol_move_speed_multiplier_is_unchanged_default() -> void:
	var w := load("res://resources/weapons/pistol.tres") as WeaponData
	assert_not_null(w, "pistol.tres must load as a WeaponData")
	assert_almost_eq(w.move_speed_multiplier, 1.0, 0.0001,
		"pistol is light and should keep the 1.0 default (no movement penalty)")

# Melee leaves move_speed_multiplier at the 1.0 default (no penalty).
func test_melee_move_speed_multiplier_is_unchanged_default() -> void:
	var w := load("res://resources/weapons/melee.tres") as WeaponData
	assert_not_null(w, "melee.tres must load as a WeaponData")
	assert_almost_eq(w.move_speed_multiplier, 1.0, 0.0001,
		"melee should keep the 1.0 default (no movement penalty)")

# Rock launcher leaves move_speed_multiplier at the 1.0 default (no penalty).
func test_rock_weapon_move_speed_multiplier_is_unchanged_default() -> void:
	var w := load("res://resources/weapons/rock_weapon.tres") as WeaponData
	assert_not_null(w, "rock_weapon.tres must load as a WeaponData")
	assert_almost_eq(w.move_speed_multiplier, 1.0, 0.0001,
		"rock_weapon should keep the 1.0 default (no movement penalty)")

# Spray paint leaves move_speed_multiplier at the 1.0 default (no penalty).
func test_spray_paint_move_speed_multiplier_is_unchanged_default() -> void:
	var w := load("res://resources/weapons/spray_paint.tres") as WeaponData
	assert_not_null(w, "spray_paint.tres must load as a WeaponData")
	assert_almost_eq(w.move_speed_multiplier, 1.0, 0.0001,
		"spray_paint should keep the 1.0 default (no movement penalty)")

# Fists are the unarmed fallback NPCs use with nothing equipped: a weak, short-reach melee.
func test_fists_is_a_weak_short_range_melee() -> void:
	var w := load("res://resources/weapons/fists.tres") as WeaponData
	assert_not_null(w, "fists.tres must load as a WeaponData")
	assert_gt(w.damage, 0.0, "fists must deal some damage")
	assert_lt(w.damage, 10.0, "fists are WEAK — well below a real weapon's damage")
	assert_lt(w.effective_range, 3.0, "fists are melee — a short reach")
	assert_gt(w.attack_speed, 0.0, "fists need a positive swing cooldown")
