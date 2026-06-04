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
