extends GutTest
# Test: load every tuning .tres and verify it has its expected exported fields.
# Each resource gets its own test so a single malformed .tres fails in isolation.

func test_player_movement_settings() -> void:
	var r := load("res://resources/tuning/PlayerMovementSettings.tres") as PlayerMovementSettings
	assert_not_null(r, "PlayerMovementSettings.tres must load as a PlayerMovementSettings")
	assert_gt(r.max_speed, 0.0, "player_movement.max_speed must be > 0")
	assert_gt(r.jump_velocity, 0.0, "player_movement.jump_velocity must be > 0")
	assert_gt(r.fall_gravity_mult, 1.0, "player_movement.fall_gravity_mult must be > 1 for faster descending jumps")
	assert_gte(r.coyote_time, 0.0, "player_movement.coyote_time must be >= 0")
	assert_gt(r.landing_impact_divisor, 0.0, "player_movement.landing_impact_divisor must be > 0")
	assert_gte(r.step_up_height, 0.5,
		"player_movement.step_up_height must cover a 16-unit TrenchBroom stair step at FuncGodot's 32:1 scale")
	assert_gte(r.step_down_snap, r.step_up_height,
		"player_movement.step_down_snap should cover at least the step-up height so descending stairs stay grounded")
	assert_gt(r.step_min_horizontal_speed, 0.0,
		"player_movement.step_min_horizontal_speed must be > 0 so idle wall contacts do not auto-step")
	assert_gt(r.max_stamina, 0.0, "player_movement.max_stamina must be > 0")
	assert_gt(r.stamina_regen_idle, r.stamina_regen_moving,
		"standing still should restore stamina faster than moving")
	assert_gt(r.stamina_regen_moving, r.stamina_regen_active,
		"ordinary movement should restore stamina faster than special movement states")
	assert_gte(r.stamina_regen_delay_after_spend, 0.0,
		"stamina_regen_delay_after_spend must be >= 0")
	assert_gt(r.stamina_regen_delay_after_shot, r.stamina_regen_delay_after_spend,
		"a SHOT must hold recovery longer than a movement verb, or a weapon regenerates between its own shots and firing can never deplete the pool (see tests/test_combat_data.gd for the per-weapon rule)")
	assert_gt(r.stamina_sprint_drain, 0.0,
		"stamina_sprint_drain must be > 0")
	assert_eq(r.stamina_sprint_lockout, 3.0,
		"stamina_sprint_lockout must keep sprint unavailable for the requested full 3 seconds")
	assert_gt(r.stamina_jump_cost, 0.0,
		"stamina_jump_cost must be > 0")
	assert_gt(r.stamina_grapple_fire_cost, 0.0,
		"stamina_grapple_fire_cost must be > 0")
	assert_gt(r.stamina_wall_climb_drain, 0.0,
		"stamina_wall_climb_drain must be > 0")
	assert_gt(r.stamina_melee_attack_cost, 0.0,
		"stamina_melee_attack_cost must be > 0")
	assert_gt(r.stamina_shot_cost, 0.0,
		"stamina_shot_cost must be > 0 — shooting is meant to draw on the same pool as sprinting")
	assert_lt(r.stamina_shot_cost, r.stamina_melee_attack_cost,
		"one shot should cost less than a full melee swing — a gun fires many times per swing")
	assert_lt(r.stamina_shot_cost, r.stamina_sprint_drain,
		"a BASELINE shot must cost less than a second of sprinting, or firing outpaces the sprint budget")
	# The clamp that makes "shooting never costs more per second than running" a theorem rather than a habit.
	# Strictly below 1.0 so the bound stays STRICT: ceiling x sprint_drain < sprint_drain.
	assert_gt(r.stamina_shot_drain_ceiling, 0.0,
		"stamina_shot_drain_ceiling must be > 0 or every shot clamps to free")
	assert_lt(r.stamina_shot_drain_ceiling, 1.0,
		"stamina_shot_drain_ceiling must be < 1 so a clamped weapon still drains strictly less than sprinting")

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
	assert_gt(r.land_window, 0.0, "bunnyhop.land_window must be > 0 — the live chain-extend timing gate")

func test_camera_settings() -> void:
	var r := load("res://resources/tuning/CameraSettings.tres") as CameraSettings
	assert_not_null(r, "CameraSettings.tres must load as a CameraSettings")
	# Strict low / inclusive high (0, 179]: a valid perspective FOV.
	assert_gt(r.default_fov, 0.0, "camera.default_fov must be > 0")
	assert_lte(r.default_fov, 179.0, "camera.default_fov must be <= 179")
	assert_lt(r.scoped_fov, r.default_fov,
		"camera.scoped_fov must be tighter than default_fov so scoping zooms in")
	assert_gt(r.sprint_fov_mult, 0.0,
		"camera.sprint_fov_mult must be > 0 so sprint visibly widens the FOV by default")
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
	# Toast colours moved off player.gd's SNEAK_HIT_COLOR / CRIPPLE_TOAST_COLOR consts (byte-identical defaults).
	assert_eq(r.sneak_toast_color, Color(0.4, 1.0, 0.45), "sneak toast ships green (was SNEAK_HIT_COLOR)")
	assert_eq(r.cripple_toast_color, Color(1.0, 0.42, 0.38), "cripple toast ships red (was CRIPPLE_TOAST_COLOR)")
	# Out-of-combat recovery (2026-08-18): the passive health regen + the low-HP heartbeat duck, both gated on
	# is_out_of_combat(). These are the SHIPPED values, so the bounds guard what a designer can author.
	assert_gte(r.combat_calm_grace, 5.0,
		"player_feedback.combat_calm_grace must not open before GunPose.idle_combat_grace (5.0) has dropped the weapon — the visual tell has to land before the mix softens and HP starts climbing")
	assert_gte(r.health_regen_frac_per_sec, 0.0,
		"player_feedback.health_regen_frac_per_sec cannot be negative — a negative rate reaches Character.heal(), which drains hp with no death check (0 is the documented off-switch)")
	assert_gt(r.health_regen_cap_frac, 0.0,
		"player_feedback.health_regen_cap_frac must be > 0, or the regen ceiling sits at zero HP and the feature is inert in a way no knob reads as 'off'")
	assert_lte(r.health_regen_cap_frac, 1.0,
		"player_feedback.health_regen_cap_frac is a fraction of max HP — above 1.0 it would ask the drip to exceed the cap heal() already clamps to")
	assert_gt(r.heartbeat_calm_duck_db, 0.0,
		"player_feedback.heartbeat_calm_duck_db must be > 0 or 'duck the heartbeat out of combat' does nothing")
	assert_lt(r.heartbeat_calm_duck_db, 12.0,
		"the duck is SLIGHT — past ~12 dB it reads as muting the cue, which is what the Accessibility heartbeat toggle is for")

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
	assert_true(r.music_reactions, "npc_ai.music_reactions ships ON — NPCs react to nearby radios by default")
	# head_look is deliberately NOT pinned here: it ships ON in the .tres, but its head-aim axis/sign can need a
	# per-rig tweak (see NpcAiSettings.gd), so it stays free to flip OFF during a rig playtest without breaking a test.
	assert_gte(r.distraction_scan_interval, 0.0, "npc_ai.distraction_scan_interval must be >= 0 (0 = scan every frame)")

func test_silent_takedown_settings() -> void:
	# The shipped SilentTakedownSettings.tres is the project's ON baseline (the class @export still defaults
	# require_crouch OFF so a bare resource stays inert). Pin the shipped values so the stealth-takedown feel
	# can't silently regress.
	var r := load("res://resources/tuning/SilentTakedownSettings.tres") as SilentTakedownSettings
	assert_not_null(r, "SilentTakedownSettings.tres must load as a SilentTakedownSettings")
	assert_true(r.require_crouch, "takedown.require_crouch ships ON — a silent takedown needs a crouched approach by default")
	assert_gt(r.hold_time, 0.0, "takedown.hold_time must be > 0 (the hold-to-execute window)")
	assert_gt(r.max_range, 0.0, "takedown.max_range must be > 0 (reach behind the target)")

func test_npc_bark_settings() -> void:
	var r := load("res://resources/tuning/NpcBarkSettings.tres") as NpcBarkSettings
	assert_not_null(r, "NpcBarkSettings.tres must load as an NpcBarkSettings")
	# PARITY: the bark-cadence tuning ships EXACTLY the npc.gd consts (which stay as the terminal fallback + test
	# anchors), so the resource extraction is byte-identical until a designer tunes it.
	assert_eq(r.bark_distance, NPC.BARK_DISTANCE, "bark_distance mirrors NPC.BARK_DISTANCE")
	assert_eq(r.bark_cooldown_ms, NPC.BARK_COOLDOWN_MS, "bark_cooldown_ms mirrors NPC.BARK_COOLDOWN_MS")
	assert_gt(r.enemy_bark_cooldown_ms, 0, "enemy_bark_cooldown_ms must be positive")
	assert_lt(r.enemy_bark_cooldown_ms, r.bark_cooldown_ms, "enemy_bark_cooldown_ms makes hostile NPCs bark more often than generic NPC chatter")
	assert_eq(r.greet_cooldown_ms, NPC.GREET_COOLDOWN_MS, "greet_cooldown_ms mirrors NPC.GREET_COOLDOWN_MS")
	assert_eq(r.death_witness_radius, NPC.DEATH_WITNESS_RADIUS, "death_witness_radius mirrors NPC.DEATH_WITNESS_RADIUS")
	assert_eq(r.hurt_bark_hp_frac, NPC.HURT_BARK_HP_FRAC, "hurt_bark_hp_frac mirrors NPC.HURT_BARK_HP_FRAC")
	assert_eq(r.alert_cooldown_ms, NPC.ALERT_COOLDOWN_MS, "alert_cooldown_ms mirrors NPC.ALERT_COOLDOWN_MS")
	assert_eq(r.aim_cooldown_ms, NPC.AIM_COOLDOWN_MS, "aim_cooldown_ms mirrors NPC.AIM_COOLDOWN_MS")
	assert_eq(r.aim_sfx_delay, NPC.AIM_SFX_DELAY, "aim_sfx_delay mirrors NPC.AIM_SFX_DELAY")
