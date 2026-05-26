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
	assert_eq(typeof(GameTuning.BULLET_TIME_DURATION), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.COYOTE_TIME), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.JUMP_BUFFER_TIME), TYPE_FLOAT)
	assert_gt(GameTuning.SCOPE_SPEED_MULT, 0.0)
	assert_lt(GameTuning.SCOPE_SPEED_MULT, 1.0)
	assert_gt(GameTuning.BULLET_TIME_SCALE, 0.0)
	assert_lt(GameTuning.BULLET_TIME_SCALE, 1.0)
	assert_gt(GameTuning.BULLET_TIME_DURATION, 0.0)


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
	assert_true(bt.has_method("_on_fired"),
		"BulletTime must expose _on_fired handler so a shot can exhaust the effect")
	assert_true(bt.has_method("is_active"),
		"BulletTime must expose is_active() for state queries / tests")
	assert_false(bt.is_active(),
		"BulletTime must start in a non-active state (READY)")


func test_bullet_time_is_node3d() -> void:
	var bt := BulletTime.new()
	add_child_autofree(bt)
	assert_true(bt is Node3D,
		"BulletTime must extend Node3D so it can host attached visual effects later")


func test_bullet_time_exhausts_on_fire() -> void:
	var bt := BulletTime.new()
	add_child_autofree(bt)
	bt._state = BulletTime.State.ACTIVE
	bt._on_fired()
	assert_eq(bt._state, BulletTime.State.EXHAUSTED,
		"Firing while ACTIVE must transition to EXHAUSTED")
	assert_false(bt.is_active())


func test_bullet_time_fire_while_ready_is_noop() -> void:
	var bt := BulletTime.new()
	add_child_autofree(bt)
	bt._on_fired()
	assert_eq(bt._state, BulletTime.State.READY,
		"Firing while READY must not transition to EXHAUSTED")


func test_allow_timescale_changes_default_true() -> void:
	assert_true(GameTuning.allow_timescale_changes,
		"GameTuning.allow_timescale_changes must default to true")


func test_bullet_time_respects_global_disable() -> void:
	var prior := Engine.time_scale
	Engine.time_scale = 1.0
	GameTuning.allow_timescale_changes = false
	var bt := BulletTime.new()
	add_child_autofree(bt)
	bt._state = BulletTime.State.ACTIVE
	bt._last_us = Time.get_ticks_usec() - 100_000
	bt._process(0.016)
	assert_eq(Engine.time_scale, 1.0,
		"BulletTime must not write to Engine.time_scale while disabled")
	GameTuning.allow_timescale_changes = true
	Engine.time_scale = prior


func test_freeze_frame_respects_global_disable() -> void:
	var prior := Engine.time_scale
	Engine.time_scale = 1.0
	GameTuning.allow_timescale_changes = false
	FreezeFrame.freeze(0.001, 0.1, 0.05)
	assert_eq(Engine.time_scale, 1.0,
		"FreezeFrame must not write to Engine.time_scale while disabled")
	GameTuning.allow_timescale_changes = true
	Engine.time_scale = prior


func test_bunnyhop_default_chain_zero() -> void:
	var bh := Bunnyhop.new()
	add_child_autofree(bh)
	assert_eq(bh.chain, 0, "Bunnyhop chain must start at 0")
	assert_almost_eq(bh.get_target_speed(), GameTuning.PLAYER_MAX_SPEED, 0.001,
		"With chain=0, target speed must be PLAYER_MAX_SPEED")


func test_bunnyhop_engage_requires_forward_and_recent_crouch() -> void:
	var bh := Bunnyhop.new()
	add_child_autofree(bh)
	assert_false(bh.try_engage(true),
		"try_engage must fail when crouch was not recently pressed")
	bh._crouch_press_timer = GameTuning.BHOP_INPUT_WINDOW
	assert_false(bh.try_engage(false),
		"try_engage must fail without forward input")
	bh._crouch_press_timer = GameTuning.BHOP_INPUT_WINDOW
	assert_true(bh.try_engage(true),
		"try_engage with forward + recent crouch must succeed")
	assert_eq(bh.chain, 1, "First successful engage must set chain to 1")


func test_bunnyhop_chain_grows_inside_land_window() -> void:
	var bh := Bunnyhop.new()
	add_child_autofree(bh)
	bh._crouch_press_timer = GameTuning.BHOP_INPUT_WINDOW
	bh._land_window_timer = GameTuning.BHOP_LAND_WINDOW
	bh.chain = 2
	bh.try_engage(true)
	assert_eq(bh.chain, 3, "Engaging inside land window must increment chain")


func test_bunnyhop_chain_resets_outside_land_window() -> void:
	var bh := Bunnyhop.new()
	add_child_autofree(bh)
	bh._crouch_press_timer = GameTuning.BHOP_INPUT_WINDOW
	bh._land_window_timer = 0.0
	bh.chain = 5
	bh.try_engage(true)
	assert_eq(bh.chain, 1, "Engaging outside land window must reset chain to 1")


func test_bunnyhop_failed_engage_breaks_chain() -> void:
	var bh := Bunnyhop.new()
	add_child_autofree(bh)
	bh.chain = 4
	bh.try_engage(false)
	assert_eq(bh.chain, 0, "Failing to engage must break the chain")


func test_bunnyhop_speed_is_capped() -> void:
	var bh := Bunnyhop.new()
	add_child_autofree(bh)
	bh.chain = 9999
	assert_eq(bh.get_target_speed(), GameTuning.BHOP_MAX_SPEED,
		"Speed must clamp at BHOP_MAX_SPEED no matter how long the chain")


func test_mouse_input_sensitivity_default() -> void:
	var mi := MouseInput.new()
	add_child_autofree(mi)
	assert_almost_eq(mi.speed_sensitivity_multiplier(), 1.0, 0.001,
		"With no player ref, multiplier must be 1.0")


func test_mouse_input_sensitivity_scales_with_speed() -> void:
	var mi := MouseInput.new()
	add_child_autofree(mi)
	var fake_player := CharacterBody3D.new()
	add_child_autofree(fake_player)
	mi.player = fake_player

	fake_player.velocity = Vector3.ZERO
	assert_almost_eq(mi.speed_sensitivity_multiplier(), 1.0, 0.001,
		"Standing still must keep full sensitivity")

	fake_player.velocity = Vector3(GameTuning.BHOP_MAX_SPEED, 0.0, 0.0)
	assert_almost_eq(mi.speed_sensitivity_multiplier(), GameTuning.SENS_MIN_MULTIPLIER, 0.001,
		"At max bhop speed multiplier must hit SENS_MIN_MULTIPLIER")


func test_character_has_spawn_dust() -> void:
	var c := Character.new()
	add_child_autofree(c)
	assert_true(c.has_method("spawn_dust"),
		"Character must expose spawn_dust() so both Player and future enemy AI can call it")


func test_dust_constants_present() -> void:
	assert_eq(typeof(GameTuning.DUST_JUMP_INTENSITY), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.DUST_LAND_BASE_INTENSITY), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.DUST_LAND_IMPACT_BONUS), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.DUST_LAND_MIN_IMPACT_TO_SPAWN), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.DUST_GROUND_PROBE_DISTANCE), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.DUST_GROUND_OFFSET), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.DUST_AMOUNT_RATIO_MIN), TYPE_FLOAT)
	assert_gt(GameTuning.DUST_JUMP_INTENSITY, 0.0)
	assert_gt(GameTuning.DUST_GROUND_PROBE_DISTANCE, 0.0)
	assert_gt(GameTuning.DUST_LAND_MIN_IMPACT_TO_SPAWN, 0.0,
		"Min impact gate must be positive so tiny stutter-landings don't puff dust")
	assert_lt(GameTuning.DUST_LAND_MIN_IMPACT_TO_SPAWN, 1.0,
		"Min impact gate must be below 1.0 so reasonable landings still puff dust")


func test_dust_intensity_curve_matches_thud_dynamic_range() -> void:
	var min_intensity := GameTuning.DUST_LAND_BASE_INTENSITY + GameTuning.DUST_LAND_MIN_IMPACT_TO_SPAWN * GameTuning.DUST_LAND_IMPACT_BONUS
	var max_intensity := GameTuning.DUST_LAND_BASE_INTENSITY + 1.0 * GameTuning.DUST_LAND_IMPACT_BONUS
	assert_lt(min_intensity, max_intensity * 0.5,
		"Light landings should produce noticeably smaller dust than heavy ones (>2x dynamic range)")
	assert_almost_eq(max_intensity, 1.0, 0.01,
		"At full impact, dust intensity should reach 1.0 (max scale)")


func test_falling_air_constants_present() -> void:
	assert_eq(typeof(GameTuning.FALLING_AIR_MIN_FALL_SPEED), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.FALLING_AIR_MAX_FALL_SPEED), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.FALLING_AIR_MIN_DB), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.FALLING_AIR_MAX_DB), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.FALLING_AIR_FADE_RATE), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.FALLING_AIR_AUDIBLE_T), TYPE_FLOAT)
	assert_gt(GameTuning.FALLING_AIR_MAX_FALL_SPEED, GameTuning.FALLING_AIR_MIN_FALL_SPEED,
		"Max fall speed for full volume must be greater than the audible threshold speed")
	assert_gt(GameTuning.FALLING_AIR_MAX_DB, GameTuning.FALLING_AIR_MIN_DB,
		"Max dB must be louder than min dB")


func test_bullet_whiz_constants_present() -> void:
	assert_eq(typeof(GameTuning.BULLET_WHIZ_MAX_DISTANCE), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.BULLET_WHIZ_VOLUME_DB), TYPE_FLOAT)
	assert_gt(GameTuning.BULLET_WHIZ_MAX_DISTANCE, 0.0,
		"Whiz max distance must be positive for AudioStreamPlayer3D falloff")


func test_player_scene_has_falling_air_node() -> void:
	var player_scene := load("res://scenes/player/Player.tscn") as PackedScene
	var state := player_scene.get_state()
	var found := false
	for i in range(state.get_node_count()):
		if state.get_node_name(i) == "FallingAirSFX":
			found = true
			break
	assert_true(found, "Player.tscn must contain a FallingAirSFX node")


func test_projectile_scene_has_whiz_node() -> void:
	for scene_path in ["res://scenes/projectiles/Projectile.tscn",
			"res://scenes/projectiles/sphere_projectile.tscn",
			"res://scenes/projectiles/rock_projectile.tscn"]:
		var ps := load(scene_path) as PackedScene
		var state := ps.get_state()
		var found := false
		for i in range(state.get_node_count()):
			if state.get_node_name(i) == "WhizSFX":
				found = true
				break
		assert_true(found, "%s must contain a WhizSFX child for doppler bullet whiz" % scene_path)


func test_player_camera_has_doppler_tracking() -> void:
	var player_scene := load("res://scenes/player/Player.tscn") as PackedScene
	var instance := player_scene.instantiate()
	add_child_autofree(instance)
	var cam := instance.get_node("Head/ScreenShake/Camera3D") as Camera3D
	assert_not_null(cam, "Player.tscn must have a Camera3D at Head/ScreenShake/Camera3D")
	assert_ne(cam.doppler_tracking, Camera3D.DOPPLER_TRACKING_DISABLED,
		"Player camera must have doppler_tracking enabled so bullet whiz pitch shifts work")


func test_gun_mesh_does_not_cast_shadow() -> void:
	var player_scene := load("res://scenes/player/Player.tscn") as PackedScene
	var instance := player_scene.instantiate()
	add_child_autofree(instance)
	var gun: MeshInstance3D = instance.get_node("Head/ScreenShake/Camera3D/GunMesh")
	assert_not_null(gun, "Player.tscn must have a GunMesh at Head/ScreenShake/Camera3D/GunMesh")
	assert_eq(gun.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"GunMesh must have cast_shadow disabled so the directional light doesn't draw a gun-shaped shadow on the world")


func test_muzzle_whiz_node_present_and_connected() -> void:
	var player_scene := load("res://scenes/player/Player.tscn") as PackedScene
	var instance := player_scene.instantiate()
	add_child_autofree(instance)
	var whiz: AudioStreamPlayer3D = instance.get_node("Head/ScreenShake/Camera3D/GunMesh/Muzzle/MuzzleWhiz")
	assert_not_null(whiz, "Player.tscn must contain a MuzzleWhiz AudioStreamPlayer3D under Muzzle")
	assert_true(whiz.has_method("_on_flash_muzzle"),
		"MuzzleWhiz must have the _on_flash_muzzle handler so flash_muzzle can trigger it")
	var attack: Attack = instance.get_node("Weapon/Attack")
	assert_true(attack.flash_muzzle.is_connected(whiz._on_flash_muzzle),
		"Attack.flash_muzzle must be connected to MuzzleWhiz._on_flash_muzzle")


func test_muzzle_whiz_constants_present() -> void:
	assert_eq(typeof(GameTuning.MUZZLE_WHIZ_PITCH_MIN), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.MUZZLE_WHIZ_PITCH_MAX), TYPE_FLOAT)
	assert_gt(GameTuning.MUZZLE_WHIZ_PITCH_MAX, GameTuning.MUZZLE_WHIZ_PITCH_MIN,
		"Max pitch must be greater than min pitch for the randf_range to make sense")


func _orient_basis_for_normal(normal: Vector3) -> Basis:
	var up := normal
	var ref := Vector3.FORWARD if abs(up.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	var right := ref.slide(up).normalized()
	var back := right.cross(up).normalized()
	return Basis(right, up, back)


func test_decal_orient_floor_is_right_handed() -> void:
	assert_gt(_orient_basis_for_normal(Vector3(0, 1, 0)).determinant(), 0.0,
		"Floor decals must use a right-handed basis (positive determinant)")


func test_decal_orient_ceiling_is_right_handed() -> void:
	assert_gt(_orient_basis_for_normal(Vector3(0, -1, 0)).determinant(), 0.0,
		"Ceiling decals must use a right-handed basis")


func test_decal_orient_east_wall_is_right_handed() -> void:
	assert_gt(_orient_basis_for_normal(Vector3(1, 0, 0)).determinant(), 0.0,
		"East-facing wall decals must use a right-handed basis (this was the bug)")


func test_decal_orient_north_wall_is_right_handed() -> void:
	assert_gt(_orient_basis_for_normal(Vector3(0, 0, -1)).determinant(), 0.0,
		"North-facing wall decals must use a right-handed basis")


func test_decal_orient_diagonal_slope_is_right_handed() -> void:
	var n := Vector3(0.5, 0.5, 0.5).normalized()
	assert_gt(_orient_basis_for_normal(n).determinant(), 0.0,
		"Diagonal slope decals must use a right-handed basis")


func test_decal_orient_y_axis_matches_normal() -> void:
	var n := Vector3(1, 0, 0)
	var basis := _orient_basis_for_normal(n)
	assert_almost_eq(basis.y.x, 1.0, 0.001)
	assert_almost_eq(basis.y.y, 0.0, 0.001)
	assert_almost_eq(basis.y.z, 0.0, 0.001)


func test_blood_splatter_interface() -> void:
	var bs := BloodSplatter.new()
	add_child_autofree(bs)
	assert_true(bs.has_method("splash"),
		"BloodSplatter must expose splash(intensity) so nearby deaths can trigger it")
	assert_true(bs is Control,
		"BloodSplatter must extend Control so it draws as a UI overlay")


func test_blood_splatter_constants_present() -> void:
	assert_eq(typeof(GameTuning.BLOOD_SPLATTER_RANGE), TYPE_FLOAT)
	assert_eq(typeof(GameTuning.BLOOD_SPLATTER_FADE_TIME), TYPE_FLOAT)
	assert_gt(GameTuning.BLOOD_SPLATTER_RANGE, 0.0,
		"Splatter range must be positive so deaths within range trigger it")
	assert_gt(GameTuning.BLOOD_SPLATTER_FADE_TIME, 0.0,
		"Fade time must be positive so blobs eventually disappear")
	assert_true(GameTuning.BLOOD_SPLATTER_MIN_BLOBS <= GameTuning.BLOOD_SPLATTER_MAX_BLOBS,
		"Min blobs must not exceed max blobs")


func test_character_notifies_player_on_gore() -> void:
	var c := Character.new()
	add_child_autofree(c)
	assert_true(c.has_method("_notify_nearby_players_of_death"),
		"Character.gore() must notify nearby players (used by the on-camera blood splatter)")


func test_player_has_on_nearby_death() -> void:
	var player_scene := load("res://scenes/player/Player.tscn") as PackedScene
	var instance := player_scene.instantiate()
	add_child_autofree(instance)
	assert_true(instance.has_method("on_nearby_death"),
		"Player must expose on_nearby_death(intensity) so Character.gore() can splash blood on the camera")
