extends GutTest
# Test: at the time the suite loads, every manager autoload should be
# instantiated AND GameSettings should have populated all its resources.
# This is the most "smoke test" of the bunch — if any autoload fails to load
# or GameSettings has nil resources, this catches it before gameplay runs.

func test_audio_manager_autoload_present() -> void:
	assert_not_null(AudioManager,
		"AudioManager autoload must be loaded — combat code calls play_sfx() on it by name")

func test_effect_factory_autoload_and_scenes_populated() -> void:
	assert_not_null(EffectFactory,
		"EffectFactory autoload must be loaded — effects spawn through it")
	# EffectFactory should have its preloaded PackedScene fields populated.
	assert_not_null(EffectFactory.blood_decal,
		"EffectFactory.blood_decal must be populated (a preloaded scene), not null")
	assert_not_null(EffectFactory.explosion_area,
		"EffectFactory.explosion_area must be populated (a preloaded scene), not null")

func test_input_manager_autoload_and_action_names() -> void:
	assert_not_null(InputManager,
		"InputManager autoload must be loaded — input is queried through it")
	assert_eq(InputManager.action_forward, &"forward",
		"InputManager.action_forward must stay &\"forward\" to match the InputMap")

func test_game_settings_autoload_present() -> void:
	assert_not_null(GameSettings,
		"GameSettings autoload must be loaded — every tuning resource is read off it")

func test_game_settings_all_resource_slots_populated() -> void:
	# All resource slots must be populated (preload fields, not _ready loads); a nil
	# slot means the autoload order / preload wiring is broken.
	assert_not_null(GameSettings.player_movement,
		"GameSettings.player_movement must not be nil — autoload order broken if it is")
	assert_not_null(GameSettings.player_crouch,
		"GameSettings.player_crouch must not be nil")
	assert_not_null(GameSettings.bunnyhop,
		"GameSettings.bunnyhop must not be nil")
	assert_not_null(GameSettings.camera,
		"GameSettings.camera must not be nil")
	assert_not_null(GameSettings.screen_shake,
		"GameSettings.screen_shake must not be nil")
	assert_not_null(GameSettings.weapon_general,
		"GameSettings.weapon_general must not be nil")
	assert_not_null(GameSettings.effects,
		"GameSettings.effects must not be nil")
	assert_not_null(GameSettings.audio,
		"GameSettings.audio must not be nil")
	assert_not_null(GameSettings.physics_damage,
		"GameSettings.physics_damage must not be nil")

func test_game_settings_resource_values_parsed() -> void:
	# Spot-check a couple of values to ensure the resources actually parsed.
	assert_gt(GameSettings.player_movement.max_speed, 0.0,
		"player_movement.max_speed must load as a positive value")
	assert_gt(GameSettings.camera.default_fov, 0.0,
		"camera.default_fov must load as a positive value")

func test_freeze_frame_autoload_present() -> void:
	assert_not_null(FreezeFrame,
		"FreezeFrame autoload must be loaded — hitstop calls FreezeFrame.freeze() by name")
