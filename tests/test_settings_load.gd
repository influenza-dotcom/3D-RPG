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

func test_player_feedback_settings() -> void:
	var r := load("res://resources/tuning/PlayerFeedbackSettings.tres") as PlayerFeedbackSettings
	assert_not_null(r, "PlayerFeedbackSettings.tres must load as a PlayerFeedbackSettings")
	# Strict (0,1): the hurt dip slows time without stopping the engine or speeding it up.
	assert_gt(r.hurt_freeze_scale, 0.0, "player_feedback.hurt_freeze_scale must be > 0")
	assert_lt(r.hurt_freeze_scale, 1.0, "player_feedback.hurt_freeze_scale must be < 1")
	assert_lt(r.hurt_lpf_cutoff, r.hurt_lpf_clear,
		"player_feedback.hurt_lpf_cutoff must be below hurt_lpf_clear so the muffle can sweep back up to clear")
	assert_gt(r.damage_thud_cooldown_ms, 0, "player_feedback.damage_thud_cooldown_ms must be > 0")
	assert_gt(r.death_sequence_time, 0.0, "player_feedback.death_sequence_time must be > 0")
	assert_gt(r.spawn_fade_in_time, 0.0, "player_feedback.spawn_fade_in_time must be > 0")

func test_npc_ai_settings() -> void:
	var r := load("res://resources/tuning/NpcAiSettings.tres") as NpcAiSettings
	assert_not_null(r, "NpcAiSettings.tres must load as an NpcAiSettings")
	assert_gt(r.retarget_interval, 0.0, "npc_ai.retarget_interval must be > 0")
	assert_lt(r.point_blank_range, r.unranged_aim_fallback,
		"npc_ai.point_blank_range must sit inside the fallback engage range (the muzzle-crowding exception, not the norm)")
	# Strict low / inclusive high (0, 1]: a fraction of max HP.
	assert_gt(r.medkit_hp_frac, 0.0, "npc_ai.medkit_hp_frac must be > 0")
	assert_lte(r.medkit_hp_frac, 1.0, "npc_ai.medkit_hp_frac must be <= 1")
	assert_gt(r.starting_clips, 0, "npc_ai.starting_clips must be > 0")
	# Stealth ships ON in this project (the shipped NpcAiSettings.tres baseline; the class @export still defaults
	# OFF so a bare resource stays inert). This test tracks the SHIPPED config, so it asserts the ON values.
	assert_true(r.body_discovery, "npc_ai.body_discovery ships ON — this project makes stealth kills consequential by default")
	assert_true(r.hearing_initiates, "npc_ai.hearing_initiates ships ON — idle NPCs investigate noise / decoys by default")
	assert_true(r.hearing_occlusion, "npc_ai.hearing_occlusion ships ON — walls muffle heard sound by default")
	assert_gte(r.distraction_scan_interval, 0.0, "npc_ai.distraction_scan_interval must be >= 0 (0 = scan every frame)")

func test_npc_bark_settings() -> void:
	var r := load("res://resources/tuning/NpcBarkSettings.tres") as NpcBarkSettings
	assert_not_null(r, "NpcBarkSettings.tres must load as an NpcBarkSettings")
	# PARITY: the bark-cadence tuning ships EXACTLY the npc.gd consts (which stay as the terminal fallback + test
	# anchors), so the resource extraction is byte-identical until a designer tunes it.
	assert_eq(r.bark_distance, NPC.BARK_DISTANCE, "bark_distance mirrors NPC.BARK_DISTANCE")
	assert_eq(r.bark_cooldown_ms, NPC.BARK_COOLDOWN_MS, "bark_cooldown_ms mirrors NPC.BARK_COOLDOWN_MS")
	assert_eq(r.greet_cooldown_ms, NPC.GREET_COOLDOWN_MS, "greet_cooldown_ms mirrors NPC.GREET_COOLDOWN_MS")
	assert_eq(r.death_witness_radius, NPC.DEATH_WITNESS_RADIUS, "death_witness_radius mirrors NPC.DEATH_WITNESS_RADIUS")
	assert_eq(r.hurt_bark_hp_frac, NPC.HURT_BARK_HP_FRAC, "hurt_bark_hp_frac mirrors NPC.HURT_BARK_HP_FRAC")
	assert_eq(r.alert_cooldown_ms, NPC.ALERT_COOLDOWN_MS, "alert_cooldown_ms mirrors NPC.ALERT_COOLDOWN_MS")
	assert_eq(r.aim_cooldown_ms, NPC.AIM_COOLDOWN_MS, "aim_cooldown_ms mirrors NPC.AIM_COOLDOWN_MS")
	assert_eq(r.aim_sfx_delay, NPC.AIM_SFX_DELAY, "aim_sfx_delay mirrors NPC.AIM_SFX_DELAY")
