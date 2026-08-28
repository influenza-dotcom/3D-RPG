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
	# Per-weapon multiplier on the global per-shot stamina cost (GameSettings.player_movement.stamina_shot_cost).
	# Declared `float = 1.0`, so an int-looking .tres literal (`stamina_cost_mult = 2`) still parses as a FLOAT —
	# the same trap damage above documents. The BALANCE of the authored values is swept by test_combat_data.gd.
	_check_field(w, "stamina_cost_mult", TYPE_FLOAT, path)
	# The weapon-side STEALTH lever: multiplies how far this gun's shot carries (player.gd on_weapon_fired ->
	# NoiseEmitter.gunfire(mult)). Declared `float = 1.0`, so an authored `noise_radius_mult = 0` in a .tres
	# would still parse FLOAT — the same int-literal trap damage above documents. A suppressor MULTs it down.
	_check_field(w, "noise_radius_mult", TYPE_FLOAT, path)
	# Does a round from this weapon explode? A pricing/authoring FACT, not a behaviour switch - nothing on
	# WeaponData can otherwise tell an explosive apart (explosion_radius defaults 4.0 on every weapon and
	# max_explosion_force defaults 20.0, so the PISTOL nominally out-blasts the launcher's authored 10.0).
	_check_field(w, "projectile_explodes", TYPE_BOOL, path)
	# Phase 4 additions
	_check_field(w, "screen_shake_amount", TYPE_FLOAT, path)
	_check_field(w, "self_knockback", TYPE_FLOAT, path)
	_check_field(w, "enemy_knockback", TYPE_FLOAT, path)
	_check_field(w, "enemy_lift", TYPE_FLOAT, path)
	_check_field(w, "bullet_gravity_scale", TYPE_FLOAT, path)
	# AI dodge-window dial: multiplies projectile_speed ONLY for an AI wielder's rounds (ProjectileSpawner
	# round_speed) — enemies never hitscan, so this is what makes their fire visibly dodgeable per weapon.
	_check_field(w, "npc_projectile_speed_mult", TYPE_FLOAT, path)
	_check_field(w, "launch_angle", TYPE_FLOAT, path)
	_check_field(w, "max_explosion_force", TYPE_FLOAT, path)
	_check_field(w, "explosion_radius", TYPE_FLOAT, path)
	# NPC hand-hold override (lets a view-model whose ROOT bakes a first-person-only pose — the knife — sit
	# right in an NPC's hand; npc.gd _build_weapon_mesh reads these). Off by default so guns are untouched.
	_check_field(w, "npc_hold_override", TYPE_BOOL, path)
	_check_field(w, "npc_hold_position", TYPE_VECTOR3, path)
	_check_field(w, "npc_hold_rotation", TYPE_VECTOR3, path)
	_check_field(w, "npc_hold_scale", TYPE_FLOAT, path)
	# Held-out readability boost (npc.gd _build_weapon_mesh MULTIPLIES it onto a GUN's surviving baked scale;
	# npc_hold_override weapons keep their authored npc_hold_scale exactly). Display-only: the FP view-model,
	# ground drops, icons, and preview never read it.
	_check_field(w, "npc_held_display_scale", TYPE_FLOAT, path)
	# In-flight streak for a THROWN copy (WorldItem._make_throwable stamps a ThrowTrail child from these; the
	# effect is scripts/components/throw_trail.gd). Off by default — a gun tumbles away without one.
	_check_field(w, "thrown_trail", TYPE_BOOL, path)
	_check_field(w, "thrown_trail_color", TYPE_COLOR, path)
	# The six fitted-mod slot ids (weapon_data.gd @export_group("Modifications")). These are @export_STORAGE:
	# invisible in the inspector, never authored, written only by WeaponBench via WeaponModKit.rebuild — but
	# they are still SCRIPT_VARIABLE, which is precisely what makes ItemDb.weapon_delta_for diff them onto the
	# EXISTING weapon_delta save key with no new save plumbing. Two things are pinned here and nowhere else:
	#   • the declared type stays TYPE_STRING_NAME — it is in ItemDb._is_weapon_delta_type's allow-list, so a
	#     drift to String/int would silently drop every fitted part from the save with no error anywhere;
	#   • a shipped weapon .tres ships BLANK (asserted below) — a stray authored id in a TEMPLATE would give
	#     every instance of that gun a permanent non-empty delta and a mod nobody fitted.
	# Iterating MOD_SLOT_PROPS rather than a second hand-list means a seventh slot stays the three coordinated
	# edits weapon_data.gd promises; the array's own order/length is pinned by tests/test_weapon_mods.gd.
	for prop in WeaponData.MOD_SLOT_PROPS:
		_check_field(w, String(prop), TYPE_STRING_NAME, path)
		assert_eq(StringName(w.get(String(prop))), &"",
			"%s.%s must ship BLANK — mod slots are runtime-owned, never authored into a template" % [path, prop])

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

# The held pose is game-wide too, for the same reason the streak is: a weapon in your HANDS that ignores where you
# are looking reads as a bug, not as flavour. Every weapon must have `held_faces_aim` on, and every weapon whose
# model follows the project's barrel-is-+X convention must carry the matching +90 front correction — the value that
# swings that +X onto the aim's -Z (the NPC hand mount's `weapon_mesh_rotation` default of -90 is the same
# convention mirrored for an NPC's +Z forward). Both are DEFAULTS on WeaponData, so this catches a resource that
# turned one off by hand as much as one authored from a stale template. The knife is the documented exception on
# the rotation only: its blade points -X, so it needs 180 (pinned separately below by its own throw test), and it
# is excluded here rather than special-cased so a NEW weapon that quietly picks 180 gets caught.
func test_every_weapon_is_held_pointing_down_your_aim() -> void:
	for wep in ["melee", "pistol", "shotgun", "smg", "sniper_wep", "rock_weapon", "spray_paint", "fists"]:
		var path := "res://resources/weapons/%s.tres" % wep
		var w := load(path) as WeaponData
		assert_not_null(w, "%s must load as a WeaponData" % path)
		assert_true(w.held_faces_aim,
			"%s must point its business end down your look while carried — held_faces_aim is on for every weapon" % wep)
	for wep in ["pistol", "shotgun", "smg", "sniper_wep", "rock_weapon", "spray_paint", "fists"]:
		var w := load("res://resources/weapons/%s.tres" % wep) as WeaponData
		assert_almost_eq(w.thrown_face_rotation_degrees.y, 90.0, 0.001,
			"%s's barrel points mesh +X, so its front correction must be +90 to lie along the aim's -Z" % wep)
		assert_almost_eq(w.thrown_face_rotation_degrees.x, 0.0, 0.001, "%s's front correction has no pitch" % wep)
		assert_almost_eq(w.thrown_face_rotation_degrees.z, 0.0, 0.001, "%s's front correction has no roll" % wep)

func test_knife_keeps_its_blade_front_correction() -> void:
	var w := load("res://resources/weapons/melee.tres") as WeaponData
	assert_almost_eq(w.thrown_face_rotation_degrees.y, 180.0, 0.001,
		"the knife's blade points mesh -X, which npc_hold_rotation maps to the drop's +Z — the TAIL of the aim — so it needs 180, not the guns' 90")

# The in-flight streak is game-wide: EVERY weapon draws a white tracer through the arc of a real throw, not just
# the blade it shipped for. This pins the whole roster ON — the inverse of what it pinned before — because the
# failure mode is silent and per-resource: a weapon whose `thrown_trail` gets un-ticked (or a NEW weapon .tres
# authored from a stale template) just quietly throws bare, and nothing else in the suite would notice. The one
# WHITE assert covers the colour drifting per weapon, which would break the "every throw looks like a throw" read
# the effect exists for. `fists` is in the roster even though there is no fists Item to drop: it costs nothing,
# and it keeps this list identical to the hold-override roster above rather than subtly different.
func test_every_weapon_streaks_when_thrown() -> void:
	for wep in ["melee", "pistol", "shotgun", "smg", "sniper_wep", "rock_weapon", "spray_paint", "fists"]:
		var path := "res://resources/weapons/%s.tres" % wep
		var w := load(path) as WeaponData
		assert_not_null(w, "%s must load as a WeaponData" % path)
		assert_true(w.thrown_trail, "%s must draw a streak in flight — the tracer is on every thrown weapon" % wep)
		assert_eq(w.thrown_trail_color, Color(1.0, 1.0, 1.0, 1.0),
			"%s's streak is WHITE, like every other weapon's" % wep)
