extends Node
# Test: load every .tres in res://resources/weapons/ and verify its WeaponData
# fields exist with the right types.
# To run: attach this script to a Node3D, F6.

const WEAPONS_DIR := "res://resources/weapons/"

func _ready() -> void:
	_run()

func _run() -> void:
	print("[test_weapon_data_completeness] starting...")
	var files := _list_tres()
	assert(files.size() > 0, "FAIL: no weapon .tres files found")
	print("PASS: found %d weapon .tres files" % files.size())
	for path in files:
		_check_weapon(path)
	print("[test_weapon_data_completeness] ALL PASS")

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
	assert(w != null, "FAIL: %s did not load as WeaponData" % path)
	_check_field(w, "damage", TYPE_INT, path)
	_check_field(w, "attack_speed", TYPE_FLOAT, path)
	_check_field(w, "reload_time", TYPE_FLOAT, path)
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
	print("PASS: %s has all required WeaponData fields" % path)

func _check_field(obj: Object, field: String, expected_type: int, src: String) -> void:
	assert(field in obj, "FAIL: %s missing field '%s'" % [src, field])
	var actual_type := typeof(obj.get(field))
	assert(actual_type == expected_type, "FAIL: %s.%s is %d, expected %d" % [src, field, actual_type, expected_type])
