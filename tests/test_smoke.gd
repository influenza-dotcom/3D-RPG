extends GutTest

const PLAYER_SCENE = preload("res://scenes/player/Player.tscn")
const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")
const ROCK_WEAPON = preload("res://resources/weapons/rock_weapon.tres")
const PISTOL = preload("res://resources/weapons/pistol.tres")
const SHOTGUN = preload("res://resources/weapons/shotgun.tres")
const SMG = preload("res://resources/weapons/smg.tres")


func test_player_scene_loads() -> void:
	assert_not_null(PLAYER_SCENE, "Player.tscn must preload")
	assert_true(PLAYER_SCENE is PackedScene, "Player.tscn must be a PackedScene")


func test_enemy_instantiates_with_overridden_blast_damp() -> void:
	var enemy: Character = ENEMY_SCENE.instantiate()
	add_child_autofree(enemy)
	assert_eq(enemy.blast_damp_divisor, 1.0,
		"enemy.tscn must override blast_damp_divisor to 1.0 so enemies don't fly off after knockback")


func test_character_default_blast_damp() -> void:
	var character_script: Script = load("res://scripts/player/character.gd")
	var character: Character = character_script.new()
	assert_eq(character.blast_damp_divisor, 1.12,
		"Character.blast_damp_divisor default must be 1.12 (player-style horizontal retention)")
	character.free()


func test_all_weapons_load() -> void:
	for w in [PISTOL, SHOTGUN, SMG, ROCK_WEAPON]:
		assert_not_null(w, "Weapon resource must load")
		assert_true(w is WeaponData, "Weapon resource must be WeaponData")
		assert_gt(w.max_ammo, 0, "Weapon must have positive max_ammo")
		assert_gt(w.attack_speed, 0.0, "Weapon must have positive attack_speed")


func test_rock_weapon_has_projectile_scene() -> void:
	assert_not_null(ROCK_WEAPON.projectile_scene,
		"rock_weapon.tres must have a projectile_scene wired up")


func test_game_tuning_constants_present() -> void:
	assert_eq(typeof(GameTuning.SCOPE_SPEED_MULT), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.BULLET_TIME_SCALE), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.BULLET_TIME_LERP_SPEED), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.COYOTE_TIME), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.JUMP_BUFFER_TIME), TYPE_FLOAT)
	assert_gt(GameTuning.SCOPE_SPEED_MULT, 0.0)
	assert_lt(GameTuning.SCOPE_SPEED_MULT, 1.0)
	assert_gt(GameTuning.BULLET_TIME_SCALE, 0.0)
	assert_lt(GameTuning.BULLET_TIME_SCALE, 1.0)


func test_coyote_time_interface() -> void:
	var ct := CoyoteTime.new()
	add_child_autofree(ct)
	assert_false(ct.can_jump(), "CoyoteTime should not allow jump before any tick")
	assert_true(ct.has_method("tick"))
	assert_true(ct.has_method("consume"))


func test_jump_buffer_interface() -> void:
	var jb := JumpBuffer.new()
	add_child_autofree(jb)
	assert_false(jb.wants_jump(), "JumpBuffer should be empty initially")
	assert_true(jb.has_method("consume"))


func test_bullet_time_interface() -> void:
	var bt := BulletTime.new()
	add_child_autofree(bt)
	assert_true(bt.has_method("_on_scoped_in"),
		"BulletTime must expose _on_scoped_in handler for the scoped_in signal")
