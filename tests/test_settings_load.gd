extends Node
# Test: load every tuning .tres and verify it has its expected exported fields.
# To run: attach this script to a Node3D in a fresh scene, F6.

func _ready() -> void:
	_run()

func _run() -> void:
	print("[test_settings_load] starting...")
	_check_player_movement()
	_check_player_crouch()
	_check_bunnyhop()
	_check_camera()
	_check_screen_shake()
	_check_weapon_general()
	_check_effects()
	_check_audio()
	_check_physics_damage()
	print("[test_settings_load] ALL PASS")

func _expect(condition: bool, label: String) -> void:
	assert(condition, "FAIL: " + label)
	print("PASS: " + label)

func _check_player_movement() -> void:
	var r := load("res://resources/tuning/PlayerMovementSettings.tres") as PlayerMovementSettings
	_expect(r != null, "PlayerMovementSettings loads")
	_expect(r.max_speed > 0.0, "player_movement.max_speed > 0")
	_expect(r.jump_velocity > 0.0, "player_movement.jump_velocity > 0")
	_expect(r.coyote_time >= 0.0, "player_movement.coyote_time >= 0")
	_expect(r.landing_impact_divisor > 0.0, "player_movement.landing_impact_divisor > 0")

func _check_player_crouch() -> void:
	var r := load("res://resources/tuning/PlayerCrouchSettings.tres") as PlayerCrouchSettings
	_expect(r != null, "PlayerCrouchSettings loads")
	_expect(r.height_ratio > 0.0 and r.height_ratio < 1.0, "player_crouch.height_ratio in (0,1)")
	_expect(r.ceiling_clearance >= 0.0, "player_crouch.ceiling_clearance >= 0")

func _check_bunnyhop() -> void:
	var r := load("res://resources/tuning/BunnyhopSettings.tres") as BunnyhopSettings
	_expect(r != null, "BunnyhopSettings loads")
	_expect(r.max_speed > 0.0, "bunnyhop.max_speed > 0")
	_expect(r.input_window > 0.0, "bunnyhop.input_window > 0")

func _check_camera() -> void:
	var r := load("res://resources/tuning/CameraSettings.tres") as CameraSettings
	_expect(r != null, "CameraSettings loads")
	_expect(r.default_fov > 0.0 and r.default_fov <= 179.0, "camera.default_fov in (0, 179]")
	_expect(r.scoped_fov < r.default_fov, "camera.scoped_fov < default_fov")
	_expect(r.mouse_sensitivity > 0.0, "camera.mouse_sensitivity > 0")
	_expect(r.pitch_max_holding_deg <= r.pitch_max_deg, "camera.pitch_max_holding_deg <= pitch_max_deg")

func _check_screen_shake() -> void:
	var r := load("res://resources/tuning/ScreenShakeSettings.tres") as ScreenShakeSettings
	_expect(r != null, "ScreenShakeSettings loads")
	_expect(r.decay_rate > 0.0, "screen_shake.decay_rate > 0")
	_expect(r.explosion_max_trauma > 0.0, "screen_shake.explosion_max_trauma > 0")

func _check_weapon_general() -> void:
	var r := load("res://resources/tuning/WeaponGeneralSettings.tres") as WeaponGeneralSettings
	_expect(r != null, "WeaponGeneralSettings loads")
	_expect(r.swap_time > 0.0, "weapon_general.swap_time > 0")
	_expect(r.bullet_time_scale > 0.0 and r.bullet_time_scale < 1.0, "weapon_general.bullet_time_scale in (0,1)")

func _check_effects() -> void:
	var r := load("res://resources/tuning/EffectsSettings.tres") as EffectsSettings
	_expect(r != null, "EffectsSettings loads")
	_expect(r.decal_fade_rate > 0.0, "effects.decal_fade_rate > 0")
	_expect(r.blood_splatter_min_blobs <= r.blood_splatter_max_blobs, "effects.blood_splatter min <= max")

func _check_audio() -> void:
	var r := load("res://resources/tuning/AudioSettings.tres") as AudioSettings
	_expect(r != null, "AudioSettings loads")
	_expect(r.falling_air_min_fall_speed < r.falling_air_max_fall_speed, "audio.falling_air min < max")
	_expect(r.muzzle_whiz_pitch_min < r.muzzle_whiz_pitch_max, "audio.muzzle_whiz_pitch min < max")

func _check_physics_damage() -> void:
	var r := load("res://resources/tuning/PhysicsDamageSettings.tres") as PhysicsDamageSettings
	_expect(r != null, "PhysicsDamageSettings loads")
	_expect(r.explosion_damage > 0, "physics_damage.explosion_damage > 0")
	_expect(r.pickup_max_hold_distance > 0.0, "physics_damage.pickup_max_hold_distance > 0")
	_expect(r.interactable_max_hp_default > 0, "physics_damage.interactable_max_hp_default > 0")
