extends GutTest
# Test: load every tuning .tres and verify it has its expected exported fields.
# Each resource gets its own test so a single malformed .tres fails in isolation.

func test_player_movement_settings() -> void:
	var r := load("res://resources/tuning/PlayerMovementSettings.tres") as PlayerMovementSettings
	assert_not_null(r, "PlayerMovementSettings.tres must load as a PlayerMovementSettings")
	assert_gt(r.max_speed, 0.0, "player_movement.max_speed must be > 0")
	assert_gt(r.jump_velocity, 0.0, "player_movement.jump_velocity must be > 0")
	assert_gte(r.coyote_time, 0.0, "player_movement.coyote_time must be >= 0")
	assert_gt(r.landing_impact_divisor, 0.0, "player_movement.landing_impact_divisor must be > 0")

func test_player_crouch_settings() -> void:
	var r := load("res://resources/tuning/PlayerCrouchSettings.tres") as PlayerCrouchSettings
	assert_not_null(r, "PlayerCrouchSettings.tres must load as a PlayerCrouchSettings")
	# Strict (0,1): a crouch is shorter than standing but not zero height.
	assert_gt(r.height_ratio, 0.0, "player_crouch.height_ratio must be > 0")
	assert_lt(r.height_ratio, 1.0, "player_crouch.height_ratio must be < 1")
	assert_gte(r.ceiling_clearance, 0.0, "player_crouch.ceiling_clearance must be >= 0")

func test_bunnyhop_settings() -> void:
	var r := load("res://resources/tuning/BunnyhopSettings.tres") as BunnyhopSettings
	assert_not_null(r, "BunnyhopSettings.tres must load as a BunnyhopSettings")
	assert_gt(r.max_speed, 0.0, "bunnyhop.max_speed must be > 0")
	assert_gt(r.input_window, 0.0, "bunnyhop.input_window must be > 0")

func test_camera_settings() -> void:
	var r := load("res://resources/tuning/CameraSettings.tres") as CameraSettings
	assert_not_null(r, "CameraSettings.tres must load as a CameraSettings")
	# Strict low / inclusive high (0, 179]: a valid perspective FOV.
	assert_gt(r.default_fov, 0.0, "camera.default_fov must be > 0")
	assert_lte(r.default_fov, 179.0, "camera.default_fov must be <= 179")
	assert_lt(r.scoped_fov, r.default_fov,
		"camera.scoped_fov must be tighter than default_fov so scoping zooms in")
	assert_gt(r.mouse_sensitivity, 0.0, "camera.mouse_sensitivity must be > 0")
	assert_lte(r.pitch_max_holding_deg, r.pitch_max_deg,
		"camera.pitch_max_holding_deg must not exceed pitch_max_deg")

func test_screen_shake_settings() -> void:
	var r := load("res://resources/tuning/ScreenShakeSettings.tres") as ScreenShakeSettings
	assert_not_null(r, "ScreenShakeSettings.tres must load as a ScreenShakeSettings")
	assert_gt(r.decay_rate, 0.0, "screen_shake.decay_rate must be > 0")
	assert_gt(r.explosion_max_trauma, 0.0, "screen_shake.explosion_max_trauma must be > 0")

func test_weapon_general_settings() -> void:
	var r := load("res://resources/tuning/WeaponGeneralSettings.tres") as WeaponGeneralSettings
	assert_not_null(r, "WeaponGeneralSettings.tres must load as a WeaponGeneralSettings")
	assert_gt(r.swap_time, 0.0, "weapon_general.swap_time must be > 0")
	# Strict (0,1): bullet-time slows but doesn't stop or speed up.
	assert_gt(r.bullet_time_scale, 0.0, "weapon_general.bullet_time_scale must be > 0")
	assert_lt(r.bullet_time_scale, 1.0, "weapon_general.bullet_time_scale must be < 1")

func test_effects_settings() -> void:
	var r := load("res://resources/tuning/EffectsSettings.tres") as EffectsSettings
	assert_not_null(r, "EffectsSettings.tres must load as an EffectsSettings")
	assert_gt(r.decal_fade_rate, 0.0, "effects.decal_fade_rate must be > 0")
	assert_lte(r.blood_splatter_min_blobs, r.blood_splatter_max_blobs,
		"effects.blood_splatter_min_blobs must not exceed max_blobs")

func test_audio_settings() -> void:
	var r := load("res://resources/tuning/AudioSettings.tres") as AudioSettings
	assert_not_null(r, "AudioSettings.tres must load as an AudioSettings")
	assert_lt(r.falling_air_min_fall_speed, r.falling_air_max_fall_speed,
		"audio.falling_air_min_fall_speed must be below max (the fade-in range must be non-empty)")
	assert_lt(r.muzzle_whiz_pitch_min, r.muzzle_whiz_pitch_max,
		"audio.muzzle_whiz_pitch_min must be below max (the random pitch range must be non-empty)")

func test_physics_damage_settings() -> void:
	var r := load("res://resources/tuning/PhysicsDamageSettings.tres") as PhysicsDamageSettings
	assert_not_null(r, "PhysicsDamageSettings.tres must load as a PhysicsDamageSettings")
	assert_gt(r.explosion_damage, 0, "physics_damage.explosion_damage must be > 0")
	assert_gt(r.pickup_max_hold_distance, 0.0, "physics_damage.pickup_max_hold_distance must be > 0")
	assert_gt(r.interactable_max_hp_default, 0, "physics_damage.interactable_max_hp_default must be > 0")
