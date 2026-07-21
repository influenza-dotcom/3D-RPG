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
	# NPC hand-hold override (lets a view-model whose ROOT bakes a first-person-only pose — the knife — sit
	# right in an NPC's hand; npc.gd _build_weapon_mesh reads these). Off by default so guns are untouched.
	_check_field(w, "npc_hold_override", TYPE_BOOL, path)
	_check_field(w, "npc_hold_position", TYPE_VECTOR3, path)
	_check_field(w, "npc_hold_rotation", TYPE_VECTOR3, path)
	_check_field(w, "npc_hold_scale", TYPE_FLOAT, path)

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

# Fists are the unarmed fallback NPCs use with nothing equipped. The actual values are the designer's to
# tune, so this just pins that it LOADS and is functional — positive damage / reach / cadence (the wind-up
# in _shot_interval divides by attack_speed, and _act_unarmed closes to effective_range).
func test_fists_loads_as_a_usable_melee_weapon() -> void:
	var w := load("res://resources/weapons/fists.tres") as WeaponData
	assert_not_null(w, "fists.tres must load as a WeaponData")
	assert_gt(w.damage, 0.0, "fists must deal some damage")
	assert_gt(w.effective_range, 0.0, "fists need a positive reach (the close-to distance)")
	assert_gt(w.attack_speed, 0.0, "fists need a positive swing cadence (the wind-up divides by it)")

# --- NPC hand-hold (knife) ---
# The knife's view_model (knife.tscn) bakes a first-person-only pose in its ROOT (scale 1.585, a Z-tilt, a
# forward offset for the player's gun camera). An NPC hangs the SAME scene off its hand anchor; without the
# override it inherited that baked scale + offset and only corrected yaw, so the knife floated ~0.45 m off the
# hand, oversized. These pin the authored hand pose that fixes it: override ON, +90° Y so the blade (which
# points -X, the reverse of a gun's +X barrel) faces the NPC's +Z forward, and native size (scale 1.0). See
# npc.gd _build_weapon_mesh.
func test_knife_opts_into_npc_hold_override() -> void:
	var w := load("res://resources/weapons/melee.tres") as WeaponData
	assert_not_null(w, "melee.tres must load as a WeaponData")
	assert_true(w.is_melee, "the knife is a melee weapon")
	assert_true(w.npc_hold_override, "the knife MUST override the NPC hand-hold — its view_model bakes an FP-only root pose")
	# +90° Y (not the guns' -90°): the knife blade points -X, so it needs the opposite yaw to face +Z forward.
	assert_almost_eq(w.npc_hold_rotation.y, 90.0, 0.001, "knife NPC yaw must be +90° so the blade points forward (+Z)")
	assert_almost_eq(w.npc_hold_rotation.x, 0.0, 0.001, "knife NPC hold has no pitch")
	assert_almost_eq(w.npc_hold_rotation.z, 0.0, 0.001, "knife NPC hold has no roll")
	assert_almost_eq(w.npc_hold_scale, 1.0, 0.001, "knife NPC hold keeps the model's native size")

# The override is opt-in: every weapon EXCEPT the knife has a CLEAN view_model root — identity (the AK) or a
# centered uniform scale with no offset/tilt (the pistol's 0.001) — and mounts correctly via the rotation-only
# weapon_mesh_rotation. None may set the override, or the fix would perturb its (working) hold. An accidental
# future override on any of these would silently break that weapon's NPC hold, so pin the whole non-knife roster off.
func test_non_knife_weapons_do_not_override_npc_hold() -> void:
	for wep in ["pistol", "shotgun", "smg", "sniper_wep", "rock_weapon", "spray_paint", "fists"]:
		var path := "res://resources/weapons/%s.tres" % wep
		var w := load(path) as WeaponData
		assert_not_null(w, "%s must load as a WeaponData" % path)
		assert_false(w.npc_hold_override,
			"%s mounts correctly via rotation-only weapon_mesh_rotation — it must NOT set npc_hold_override" % wep)
