extends Node
# Test: at the time the main scene loads, every manager autoload should be
# instantiated AND GameSettings should have populated all its resources.
# This is the most "smoke test" of the bunch — if any autoload fails to load
# or GameSettings has nil resources, this catches it before gameplay runs.
# To run: attach this script to a Node3D, F6.

func _ready() -> void:
	_run()

func _run() -> void:
	print("[test_autoload_order] starting...")

	assert(AudioManager != null, "FAIL: AudioManager autoload missing")
	print("PASS: AudioManager autoload present")

	assert(EffectFactory != null, "FAIL: EffectFactory autoload missing")
	print("PASS: EffectFactory autoload present")
	# EffectFactory should have its preloaded PackedScene fields populated.
	assert(EffectFactory.blood_decal != null, "FAIL: EffectFactory.blood_decal is null")
	assert(EffectFactory.explosion_area != null, "FAIL: EffectFactory.explosion_area is null")
	print("PASS: EffectFactory exported scenes are populated")

	assert(InputManager != null, "FAIL: InputManager autoload missing")
	assert(InputManager.action_forward == &"forward", "FAIL: InputManager.action_forward unexpected value")
	print("PASS: InputManager autoload present with expected action names")

	assert(GameSettings != null, "FAIL: GameSettings autoload missing")
	# All resource slots must be populated (preload fields, not _ready loads).
	assert(GameSettings.player_movement != null, "FAIL: GameSettings.player_movement is nil — autoload order broken")
	assert(GameSettings.player_crouch != null, "FAIL: GameSettings.player_crouch is nil")
	assert(GameSettings.bunnyhop != null, "FAIL: GameSettings.bunnyhop is nil")
	assert(GameSettings.camera != null, "FAIL: GameSettings.camera is nil")
	assert(GameSettings.screen_shake != null, "FAIL: GameSettings.screen_shake is nil")
	assert(GameSettings.weapon_general != null, "FAIL: GameSettings.weapon_general is nil")
	assert(GameSettings.effects != null, "FAIL: GameSettings.effects is nil")
	assert(GameSettings.audio != null, "FAIL: GameSettings.audio is nil")
	assert(GameSettings.physics_damage != null, "FAIL: GameSettings.physics_damage is nil")
	print("PASS: GameSettings has all 9 resource slots populated")

	# Spot-check a couple of values to ensure the resources actually parsed.
	assert(GameSettings.player_movement.max_speed > 0.0, "FAIL: player_movement.max_speed not loaded")
	assert(GameSettings.camera.default_fov > 0.0, "FAIL: camera.default_fov not loaded")
	print("PASS: GameSettings resource values look correct")

	assert(FreezeFrame != null, "FAIL: FreezeFrame autoload missing")
	print("PASS: FreezeFrame autoload present")

	print("[test_autoload_order] ALL PASS")
