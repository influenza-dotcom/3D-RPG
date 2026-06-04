extends GutTest

## GUT smoke-test suite. Each test guards a load-bearing invariant, and its assert
## message states WHY that invariant matters — so this file doubles as executable
## documentation of cross-system contracts (e.g. enemy blast damp, weapon-data shape,
## the on_nearby_death trauma/freeze behaviour). Run via the GUT panel or CLI.

## Concrete stand-in for the now-@abstract Character base, so tests that only probe
## Character's shared API (via has_method) can still instantiate one.
class _ConcreteCharacter extends Character:
	pass

const PLAYER_SCENE = preload("res://scenes/player/Player.tscn")
const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")
const ROCK_WEAPON = preload("res://resources/weapons/rock_weapon.tres")
const PISTOL = preload("res://resources/weapons/pistol.tres")
const SHOTGUN = preload("res://resources/weapons/shotgun.tres")
const SMG = preload("res://resources/weapons/smg.tres")
const MELEE = preload("res://resources/weapons/melee.tres")


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
		# attack.gd reads screen_shake_amount directly (no fallback), so any float is
		# valid — 0.0 = no kick (e.g. the rapid-fire SMG). Just assert it's usable.
		assert_eq(typeof(w.screen_shake_amount), TYPE_FLOAT,
			"Every weapon must declare screen_shake_amount as a float for attack.gd to read")
		assert_true(w.screen_shake_amount >= 0.0,
			"screen_shake_amount must be non-negative (0 = no kick)")


func test_weapon_shake_differentiation() -> void:
	assert_gt(SHOTGUN.screen_shake_amount, PISTOL.screen_shake_amount,
		"Shotgun must kick harder than the pistol")
	assert_gt(PISTOL.screen_shake_amount, SMG.screen_shake_amount,
		"SMG fires rapidly so its per-shot kick must be smaller than the pistol's")
	assert_gt(ROCK_WEAPON.screen_shake_amount, PISTOL.screen_shake_amount,
		"Rock launcher (explosive) must kick harder than the pistol")


func test_rock_weapon_has_projectile_scene() -> void:
	assert_not_null(ROCK_WEAPON.projectile_scene,
		"rock_weapon.tres must have a projectile_scene wired up")


func test_game_tuning_constants_present() -> void:
	assert_eq(typeof(GameSettings.weapon_general.scope_speed_mult), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.weapon_general.bullet_time_scale), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.weapon_general.bullet_time_lerp_speed), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.weapon_general.bullet_time_duration), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.player_movement.coyote_time), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.player_movement.jump_buffer_time), TYPE_FLOAT)
	assert_gt(GameSettings.weapon_general.scope_speed_mult, 0.0)
	assert_lt(GameSettings.weapon_general.scope_speed_mult, 1.0)
	assert_gt(GameSettings.weapon_general.bullet_time_scale, 0.0)
	assert_lt(GameSettings.weapon_general.bullet_time_scale, 1.0)
	assert_gt(GameSettings.weapon_general.bullet_time_duration, 0.0)


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
	assert_true(GameSettings.allow_timescale_changes,
		"GameSettings.allow_timescale_changes must default to true")


func test_bullet_time_respects_global_disable() -> void:
	var prior := Engine.time_scale
	Engine.time_scale = 1.0
	GameSettings.allow_timescale_changes = false
	var bt := BulletTime.new()
	add_child_autofree(bt)
	bt._state = BulletTime.State.ACTIVE
	bt._last_us = Time.get_ticks_usec() - 100_000
	bt._process(0.016)
	assert_eq(Engine.time_scale, 1.0,
		"BulletTime must not write to Engine.time_scale while disabled")
	GameSettings.allow_timescale_changes = true
	Engine.time_scale = prior


func test_freeze_frame_respects_global_disable() -> void:
	var prior := Engine.time_scale
	Engine.time_scale = 1.0
	GameSettings.allow_timescale_changes = false
	FreezeFrame.freeze(0.001, 0.1, 0.05)
	assert_eq(Engine.time_scale, 1.0,
		"FreezeFrame must not write to Engine.time_scale while disabled")
	GameSettings.allow_timescale_changes = true
	Engine.time_scale = prior


func test_bunnyhop_default_chain_zero() -> void:
	var bh := Bunnyhop.new()
	add_child_autofree(bh)
	assert_eq(bh.chain, 0, "Bunnyhop chain must start at 0")
	assert_almost_eq(bh.get_target_speed(), GameSettings.player_movement.max_speed, 0.001,
		"With chain=0, target speed must be PLAYER_MAX_SPEED")


# NOTE: bunnyhop was simplified to "movement input + land-window timing" — the old
# crouch-gated engage (_crouch_press_timer / input_window) no longer exists.
func test_bunnyhop_engage_requires_movement_input() -> void:
	var bh := Bunnyhop.new()
	add_child_autofree(bh)
	assert_false(bh.try_engage(false),
		"try_engage must fail without movement input (a standing jump never chains)")
	assert_true(bh.try_engage(true),
		"try_engage with movement input must succeed")
	assert_eq(bh.chain, 1, "First successful engage (outside the land window) must set chain to 1")


func test_bunnyhop_chain_grows_inside_land_window() -> void:
	var bh := Bunnyhop.new()
	add_child_autofree(bh)
	bh._land_window_timer = GameSettings.bunnyhop.land_window
	bh.chain = 2
	bh.try_engage(true)
	assert_eq(bh.chain, 3, "Engaging inside the land window must increment the chain")


func test_bunnyhop_chain_resets_outside_land_window() -> void:
	var bh := Bunnyhop.new()
	add_child_autofree(bh)
	bh._land_window_timer = 0.0
	bh.chain = 5
	bh.try_engage(true)
	assert_eq(bh.chain, 1, "Engaging outside the land window must reset the chain to 1")


func test_bunnyhop_break_chain_resets() -> void:
	var bh := Bunnyhop.new()
	add_child_autofree(bh)
	bh.chain = 4
	# try_engage(false) just declines (returns false) — it does NOT reset the chain.
	# The chain is broken by break_chain(), called from _physics_process once grounded
	# past the land window.
	assert_false(bh.try_engage(false),
		"A jump with no movement input must not engage the chain")
	assert_eq(bh.chain, 4, "A declined engage leaves the chain untouched")
	bh.break_chain()
	assert_eq(bh.chain, 0, "break_chain() must reset the chain to 0")


func test_bunnyhop_speed_is_capped() -> void:
	var bh := Bunnyhop.new()
	add_child_autofree(bh)
	bh.chain = 9999
	assert_eq(bh.get_target_speed(), GameSettings.bunnyhop.max_speed,
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

	fake_player.velocity = Vector3(GameSettings.bunnyhop.max_speed, 0.0, 0.0)
	assert_almost_eq(mi.speed_sensitivity_multiplier(), GameSettings.bunnyhop.sens_min_multiplier, 0.001,
		"At max bhop speed multiplier must hit SENS_MIN_MULTIPLIER")


func test_character_has_spawn_dust() -> void:
	var c := _ConcreteCharacter.new()
	add_child_autofree(c)
	assert_true(c.has_method("spawn_dust"),
		"Character must expose spawn_dust() so both Player and future enemy AI can call it")


func test_dust_constants_present() -> void:
	assert_eq(typeof(GameSettings.effects.dust_jump_intensity), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.effects.dust_land_base_intensity), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.effects.dust_land_impact_bonus), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.effects.dust_land_min_impact_to_spawn), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.effects.dust_ground_probe_distance), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.effects.dust_ground_offset), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.effects.dust_amount_ratio_min), TYPE_FLOAT)
	assert_gt(GameSettings.effects.dust_jump_intensity, 0.0)
	assert_gt(GameSettings.effects.dust_ground_probe_distance, 0.0)
	assert_gt(GameSettings.effects.dust_land_min_impact_to_spawn, 0.0,
		"Min impact gate must be positive so tiny stutter-landings don't puff dust")
	assert_lt(GameSettings.effects.dust_land_min_impact_to_spawn, 1.0,
		"Min impact gate must be below 1.0 so reasonable landings still puff dust")


func test_dust_intensity_curve_matches_thud_dynamic_range() -> void:
	var min_intensity := GameSettings.effects.dust_land_base_intensity + GameSettings.effects.dust_land_min_impact_to_spawn * GameSettings.effects.dust_land_impact_bonus
	var max_intensity := GameSettings.effects.dust_land_base_intensity + 1.0 * GameSettings.effects.dust_land_impact_bonus
	assert_lt(min_intensity, max_intensity * 0.5,
		"Light landings should produce noticeably smaller dust than heavy ones (>2x dynamic range)")
	assert_almost_eq(max_intensity, 1.0, 0.01,
		"At full impact, dust intensity should reach 1.0 (max scale)")


func test_falling_air_constants_present() -> void:
	assert_eq(typeof(GameSettings.audio.falling_air_min_fall_speed), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.audio.falling_air_max_fall_speed), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.audio.falling_air_min_db), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.audio.falling_air_max_db), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.audio.falling_air_fade_rate), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.audio.falling_air_audible_t), TYPE_FLOAT)
	assert_gt(GameSettings.audio.falling_air_max_fall_speed, GameSettings.audio.falling_air_min_fall_speed,
		"Max fall speed for full volume must be greater than the audible threshold speed")
	assert_gt(GameSettings.audio.falling_air_max_db, GameSettings.audio.falling_air_min_db,
		"Max dB must be louder than min dB")


func test_bullet_whiz_constants_present() -> void:
	assert_eq(typeof(GameSettings.audio.bullet_whiz_max_distance), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.audio.bullet_whiz_volume_db), TYPE_FLOAT)
	assert_gt(GameSettings.audio.bullet_whiz_max_distance, 0.0,
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
	var whiz := instance.find_child("MuzzleWhiz", true, false) as AudioStreamPlayer3D
	assert_not_null(whiz, "Player.tscn must contain a MuzzleWhiz AudioStreamPlayer3D somewhere under the gun rig")
	assert_true(whiz.has_method("_on_flash_muzzle"),
		"MuzzleWhiz must have the _on_flash_muzzle handler so flash_muzzle can trigger it")
	var attack: Attack = instance.get_node("Weapon/Attack")
	assert_true(attack.flash_muzzle.is_connected(whiz._on_flash_muzzle),
		"Attack.flash_muzzle must be connected to MuzzleWhiz._on_flash_muzzle")


func test_muzzle_whiz_constants_present() -> void:
	assert_eq(typeof(GameSettings.audio.muzzle_whiz_pitch_min), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.audio.muzzle_whiz_pitch_max), TYPE_FLOAT)
	assert_gt(GameSettings.audio.muzzle_whiz_pitch_max, GameSettings.audio.muzzle_whiz_pitch_min,
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
	assert_eq(typeof(GameSettings.effects.blood_splatter_range), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.effects.blood_splatter_fade_time), TYPE_FLOAT)
	assert_gt(GameSettings.effects.blood_splatter_range, 0.0,
		"Splatter range must be positive so deaths within range trigger it")
	assert_gt(GameSettings.effects.blood_splatter_fade_time, 0.0,
		"Fade time must be positive so blobs eventually disappear")
	assert_true(GameSettings.effects.blood_splatter_min_blobs <= GameSettings.effects.blood_splatter_max_blobs,
		"Min blobs must not exceed max blobs")


func test_death_shake_constants_present() -> void:
	assert_eq(typeof(GameSettings.screen_shake.death_shake_range), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.screen_shake.death_shake_amount), TYPE_FLOAT)
	assert_gt(GameSettings.screen_shake.death_shake_range, 0.0,
		"Death shake range must be positive")
	assert_gt(GameSettings.screen_shake.death_shake_amount, 0.0,
		"Death shake trauma amount must be positive")
	assert_true(GameSettings.screen_shake.death_shake_range >= GameSettings.effects.blood_splatter_range,
		"Shake should be felt at least as far as splatter is seen")


func test_player_on_nearby_death_shakes_screen() -> void:
	var player_scene := load("res://scenes/player/Player.tscn") as PackedScene
	var instance := player_scene.instantiate()
	add_child_autofree(instance)
	await wait_physics_frames(2)
	var shake: ScreenShake = instance.screen_shake
	assert_not_null(shake, "Player needs a screen_shake reference for the death shake to work")
	shake.trauma = 0.0
	instance.on_nearby_death(0.0)
	assert_gt(shake.trauma, 0.0,
		"on_nearby_death at distance 0 must inject trauma into the player's screen_shake")


func test_player_on_nearby_death_decays_with_distance() -> void:
	var player_scene := load("res://scenes/player/Player.tscn") as PackedScene
	var instance := player_scene.instantiate()
	add_child_autofree(instance)
	await wait_physics_frames(2)
	var shake: ScreenShake = instance.screen_shake
	shake.trauma = 0.0
	instance.on_nearby_death(GameSettings.screen_shake.death_shake_range + 1.0)
	assert_eq(shake.trauma, 0.0,
		"Beyond DEATH_SHAKE_RANGE the screen must not shake at all")


func test_character_notifies_player_on_gore() -> void:
	var c := _ConcreteCharacter.new()
	add_child_autofree(c)
	assert_true(c.has_method("_notify_nearby_players_of_death"),
		"Character.gore() must notify nearby players (used by the on-camera blood splatter)")


func test_player_has_on_nearby_death() -> void:
	var player_scene := load("res://scenes/player/Player.tscn") as PackedScene
	var instance := player_scene.instantiate()
	add_child_autofree(instance)
	assert_true(instance.has_method("on_nearby_death"),
		"Player must expose on_nearby_death(intensity) so Character.gore() can splash blood on the camera")


func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	var s := f.get_as_text()
	f.close()
	return s


func test_screen_shake_area_center_gives_max_shake() -> void:
	# Build the (heavier, post-refactor) player FIRST and let it settle, THEN spawn the explosion and
	# use it right away: explosion_area self-frees on a ~0.2s timer, so holding it across the player
	# setup let it free mid-test once that build got heavier (the "previously freed" error at line 498).
	var player_scene := load("res://scenes/player/Player.tscn") as PackedScene
	var player = player_scene.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(2)
	var ea_scene := load("res://scenes/effects/explosion_area.tscn") as PackedScene
	var ea = ea_scene.instantiate()
	add_child_autofree(ea)
	await wait_physics_frames(2)
	var ssa: Area3D = ea.get_node("ScreenShakeArea")
	ea.global_position = Vector3.ZERO
	player.global_position = Vector3.ZERO
	player.screen_shake.trauma = 0.0
	ssa._on_body_entered(player)
	assert_gt(player.screen_shake.trauma, 0.0,
		"Player at the dead center of an explosion must receive shake (was 0 before the inverted-falloff fix)")


func test_screen_shake_area_edge_gives_no_shake() -> void:
	var ea_scene := load("res://scenes/effects/explosion_area.tscn") as PackedScene
	var ea = ea_scene.instantiate()
	add_child_autofree(ea)
	await wait_physics_frames(2)
	var ssa: Area3D = ea.get_node("ScreenShakeArea")
	var ssa_radius := ((ssa.get_node("CollisionShape3D") as CollisionShape3D).shape as SphereShape3D).radius
	var player_scene := load("res://scenes/player/Player.tscn") as PackedScene
	var player = player_scene.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(2)
	ea.global_position = Vector3.ZERO
	player.global_position = Vector3(ssa_radius, 0.0, 0.0)
	player.screen_shake.trauma = 0.0
	ssa._on_body_entered(player)
	assert_almost_eq(player.screen_shake.trauma, 0.0, 0.001,
		"Player at the outer edge of the shake zone must receive no shake (inverted-falloff fix)")


func test_screen_shake_area_falloff_is_monotonic() -> void:
	var ea_scene := load("res://scenes/effects/explosion_area.tscn") as PackedScene
	var ea = ea_scene.instantiate()
	add_child_autofree(ea)
	await wait_physics_frames(2)
	var ssa: Area3D = ea.get_node("ScreenShakeArea")
	var ssa_radius := ((ssa.get_node("CollisionShape3D") as CollisionShape3D).shape as SphereShape3D).radius
	var player_scene := load("res://scenes/player/Player.tscn") as PackedScene
	var player = player_scene.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(2)
	ea.global_position = Vector3.ZERO

	player.global_position = Vector3(ssa_radius * 0.25, 0.0, 0.0)
	player.screen_shake.trauma = 0.0
	ssa._on_body_entered(player)
	var near_trauma: float = player.screen_shake.trauma

	player.global_position = Vector3(ssa_radius * 0.75, 0.0, 0.0)
	player.screen_shake.trauma = 0.0
	ssa._on_body_entered(player)
	var far_trauma: float = player.screen_shake.trauma

	assert_gt(near_trauma, far_trauma,
		"Near (25%% of radius) must shake MORE than far (75%% of radius); was inverted before fix")


func test_explosion_light_sized_in_ready() -> void:
	var scene := load("res://scenes/effects/explosion_area.tscn") as PackedScene
	var inst = scene.instantiate()
	add_child_autofree(inst)
	await wait_physics_frames(2)
	var light: OmniLight3D = inst.get_node("OmniLight3D")
	assert_not_null(light, "ExplosionArea must have an OmniLight3D child")
	assert_almost_eq(light.omni_range, inst.explosion_radius, 0.001,
		"OmniLight3D.omni_range must equal explosion_radius after _ready (used to only get set on body entry)")
	assert_almost_eq(light.light_energy, inst.explosion_radius * GameSettings.effects.explosion_flash_energy_per_radius, 0.001,
		"OmniLight3D.light_energy must equal explosion_radius * explosion_flash_energy_per_radius after _ready")


func test_bullet_time_does_not_clobber_external_time_scale() -> void:
	var prior_allowed := GameSettings.allow_timescale_changes
	var prior := Engine.time_scale
	GameSettings.allow_timescale_changes = true
	var bt := BulletTime.new()
	add_child_autofree(bt)
	bt._state = BulletTime.State.READY
	bt._managing_time_scale = false
	Engine.time_scale = 0.1
	for i in range(20):
		bt._last_us = Time.get_ticks_usec() - 16_000
		bt._process(0.016)
	assert_almost_eq(Engine.time_scale, 0.1, 0.01,
		"BulletTime in READY without ownership must NOT lerp Engine.time_scale (so FreezeFrame can't be clobbered)")
	Engine.time_scale = prior
	GameSettings.allow_timescale_changes = prior_allowed


func test_bullet_time_claims_ownership_when_active() -> void:
	var prior_allowed := GameSettings.allow_timescale_changes
	var prior := Engine.time_scale
	GameSettings.allow_timescale_changes = true
	Engine.time_scale = 1.0
	var bt := BulletTime.new()
	add_child_autofree(bt)
	var fake_char := CharacterBody3D.new()
	add_child_autofree(fake_char)
	bt.character = fake_char
	bt._is_scoped = true
	# Current BulletTime only activates when the scope was entered WHILE airborne.
	# A bare CharacterBody3D reports is_on_floor()==false, so just arm the flag.
	bt._scope_entered_in_air = true
	bt._state = BulletTime.State.READY
	bt._last_us = Time.get_ticks_usec() - 16_000
	bt._process(0.016)
	assert_eq(bt._state, BulletTime.State.ACTIVE,
		"Scoped + airborne must enter ACTIVE on the next tick")
	for i in range(15):
		bt._last_us = Time.get_ticks_usec() - 16_000
		bt._process(0.016)
	assert_true(bt._managing_time_scale,
		"ACTIVE must claim time_scale ownership")
	assert_lt(Engine.time_scale, 1.0,
		"ACTIVE must pull Engine.time_scale below 1.0")
	Engine.time_scale = prior
	GameSettings.allow_timescale_changes = prior_allowed


func test_bullet_time_releases_ownership_after_recovery() -> void:
	var prior_allowed := GameSettings.allow_timescale_changes
	var prior := Engine.time_scale
	GameSettings.allow_timescale_changes = true
	Engine.time_scale = GameSettings.weapon_general.bullet_time_scale
	var bt := BulletTime.new()
	add_child_autofree(bt)
	bt._state = BulletTime.State.EXHAUSTED
	bt._managing_time_scale = true
	for i in range(200):
		bt._last_us = Time.get_ticks_usec() - 16_000
		bt._process(0.016)
	assert_almost_eq(Engine.time_scale, 1.0, 0.01,
		"BulletTime must lerp Engine.time_scale back to 1.0 after ACTIVE ends")
	assert_false(bt._managing_time_scale,
		"After recovery completes, BulletTime must release ownership so FreezeFrame works again")
	Engine.time_scale = prior
	GameSettings.allow_timescale_changes = prior_allowed


func test_player_freeze_frame_gated_by_distance() -> void:
	var prior_allowed := GameSettings.allow_timescale_changes
	var prior := Engine.time_scale
	GameSettings.allow_timescale_changes = true
	var player_scene := load("res://scenes/player/Player.tscn") as PackedScene
	var instance := player_scene.instantiate()
	add_child_autofree(instance)
	await wait_physics_frames(2)

	Engine.time_scale = 1.0
	instance.on_nearby_death(GameSettings.screen_shake.death_shake_range + 5.0)
	var far_scale: float = Engine.time_scale

	Engine.time_scale = 1.0
	instance.on_nearby_death(0.0)
	var close_scale: float = Engine.time_scale

	assert_almost_eq(far_scale, 1.0, 0.001,
		"on_nearby_death beyond DEATH_SHAKE_RANGE must NOT fire FreezeFrame (was unconditional before fix)")
	assert_lt(close_scale, 1.0,
		"on_nearby_death at distance 0 must still fire FreezeFrame (synchronous Engine.time_scale write)")

	await get_tree().create_timer(0.1, true, true, true).timeout
	Engine.time_scale = prior
	GameSettings.allow_timescale_changes = prior_allowed


func test_flash_light_uses_export_not_relative_path() -> void:
	var content := _read_file("res://scenes/player/flash_light.gd")
	assert_false('"../LightPosition"' in content,
		"flash_light.gd must not contain the brittle ../LightPosition NodePath")
	assert_true("@export var light_position" in content,
		"flash_light.gd must expose light_position as an @export so the scene wires it")


func test_flash_light_uses_delta_based_lerp() -> void:
	var content := _read_file("res://scenes/player/flash_light.gd")
	assert_true("FOLLOW_RATE" in content,
		"flash_light.gd must use a named follow rate constant (exp-based smoothing)")
	assert_true("exp(-FOLLOW_RATE" in content,
		"flash_light.gd must use exp-based frame-rate-independent smoothing")


func test_player_scene_wires_flashlight_light_position() -> void:
	# The camera rig (FlashLight + LightPosition) was extracted into camera_rig.tscn, which
	# Player.tscn instances — so the node_paths wiring lives there now, not inlined in Player.tscn.
	var content := _read_file("res://scenes/player/camera_rig.tscn")
	assert_true('light_position = NodePath("../LightPosition")' in content,
		"camera_rig.tscn must wire FlashLight.light_position to ../LightPosition via node_paths")


func test_enemy_has_hitstop_handlers() -> void:
	var content := _read_file("res://scripts/npc/npc.gd")
	assert_true("func _on_damaged" in content,
		"npc.gd must define _on_damaged (the damaged-signal handler wired in enemy.tscn)")
	assert_true("func _on_died" in content,
		"npc.gd must define _on_died (the kill-beat freeze, wired to the died signal)")


func test_ray_cast_has_no_stale_inline_comments() -> void:
	var content := _read_file("res://scenes/player/ray_cast.gd")
	assert_false("# distance in front of camera" in content,
		"ray_cast.gd must not contain the `# distance in front of camera` comment")
	assert_false("# Connect the joint" in content,
		"ray_cast.gd must not contain the `# Connect the joint` comment")


# File is scripts/combat/Interactable.gd (the old misspelled "Interactible.gd" is gone).
func test_interactable_is_data_driven() -> void:
	var content := _read_file("res://scripts/combat/Interactable.gd")
	assert_true("class_name Interactable" in content,
		"Interactable.gd must declare class_name Interactable")
	assert_true("InteractableData" in content,
		"Interactable.gd must read its config from an InteractableData resource")


func test_inventory_equip_same_weapon_does_not_emit() -> void:
	var inv := Inventory.new()
	add_child_autofree(inv)
	inv.equipped_weapon = PISTOL
	watch_signals(inv)
	inv.equip(PISTOL)
	assert_signal_not_emitted(inv, "weapon_changed",
		"Equipping the same weapon must NOT re-emit weapon_changed (avoids spurious downstream resets)")


func test_inventory_equip_new_weapon_emits() -> void:
	var inv := Inventory.new()
	add_child_autofree(inv)
	inv.equipped_weapon = PISTOL
	watch_signals(inv)
	inv.equip(SHOTGUN)
	assert_signal_emitted(inv, "weapon_changed",
		"Equipping a different weapon must emit weapon_changed exactly once")


# ---------------------------------------------------------------------------
# Per-weapon toggles, melee identity, HP/ammo audio pitch, ram, scope/dash
# gating, slide, and night vision — the systems added in the latest pass.
# ---------------------------------------------------------------------------

func test_weapon_data_has_behaviour_toggles() -> void:
	for w in [PISTOL, SHOTGUN, SMG, ROCK_WEAPON]:
		assert_eq(typeof(w.auto_fire), TYPE_BOOL, "WeaponData.auto_fire must be a bool")
		assert_eq(typeof(w.has_muzzle_flash), TYPE_BOOL, "WeaponData.has_muzzle_flash must be a bool")
		assert_eq(typeof(w.has_laser_sight), TYPE_BOOL, "WeaponData.has_laser_sight must be a bool")
		assert_eq(typeof(w.spawns_casing), TYPE_BOOL, "WeaponData.spawns_casing must be a bool")
		assert_eq(typeof(w.single_air_dash), TYPE_BOOL, "WeaponData.single_air_dash must be a bool")
		assert_eq(typeof(w.launch_on_scoped_attack), TYPE_BOOL, "WeaponData.launch_on_scoped_attack must be a bool")
		assert_eq(typeof(w.use_hitscan), TYPE_BOOL, "WeaponData.use_hitscan must be a bool")
		assert_eq(typeof(w.attack_windup), TYPE_FLOAT, "WeaponData.attack_windup must be a float")


func test_melee_weapon_identity() -> void:
	assert_true(MELEE is WeaponData, "melee.tres must be a WeaponData resource")
	assert_false(MELEE.auto_fire, "Melee must be semi-auto (one swing per click)")
	assert_true(MELEE.use_hitscan, "Melee deals raycast (hitscan) damage")
	assert_true(MELEE.launch_on_scoped_attack, "Melee's scoped attack is the dash launch")
	assert_true(MELEE.single_air_dash, "Melee's dash is limited to one per airtime")
	assert_false(MELEE.has_muzzle_flash, "Melee has no muzzle flash")
	assert_false(MELEE.has_laser_sight, "Melee has no laser sight")
	assert_false(MELEE.spawns_casing, "Melee ejects no shell casing")
	assert_gt(MELEE.attack_windup, 0.0, "Melee has a wind-up before the swing lands")


func test_enemy_hit_pitch_settings_present() -> void:
	assert_eq(typeof(GameSettings.audio.enemy_hit_pitch_full_hp), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.audio.enemy_hit_pitch_low_hp), TYPE_FLOAT)
	assert_lt(GameSettings.audio.enemy_hit_pitch_low_hp, GameSettings.audio.enemy_hit_pitch_full_hp,
		"A near-death enemy must be hit at a LOWER (deeper) pitch than a full-HP one")


func test_fire_pitch_by_ammo_settings_present() -> void:
	assert_eq(typeof(GameSettings.audio.fire_pitch_full_ammo), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.audio.fire_pitch_empty_ammo), TYPE_FLOAT)
	assert_lt(GameSettings.audio.fire_pitch_empty_ammo, GameSettings.audio.fire_pitch_full_ammo,
		"An empty mag must fire at a LOWER (deeper) pitch than a full one (Cruelty-Squad effect)")


func test_ram_settings_present() -> void:
	assert_eq(typeof(GameSettings.physics_damage.ram_min_speed), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.physics_damage.ram_damage_per_speed), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.physics_damage.ram_knockback), TYPE_FLOAT)
	assert_eq(typeof(GameSettings.physics_damage.ram_cooldown), TYPE_FLOAT)
	assert_gt(GameSettings.physics_damage.ram_min_speed, 0.0,
		"Ram requires a positive minimum speed so ordinary movement doesn't body-check enemies")


func test_attack_has_scope_and_dash_gating() -> void:
	var content := _read_file("res://scripts/combat/attack.gd")
	assert_true("func can_enter_scope" in content,
		"Attack.can_enter_scope() gates re-scoping (ScopeIn uses it for the air-dash lockout)")
	assert_true("func _do_launch_attack" in content,
		"Attack._do_launch_attack() is the scoped-attack dash launch")


func test_scope_in_has_force_unscope() -> void:
	# Not add_child'd: ScopeIn._process dereferences `camera`, which is null on a bare
	# instance — has_method() works without entering the tree.
	var si := ScopeIn.new()
	assert_true(si.has_method("force_unscope"),
		"ScopeIn.force_unscope() lets the melee dash exit ADS immediately")
	si.free()


func test_player_has_slide_and_bounce_systems() -> void:
	var content := _read_file("res://scripts/player/player.gd")
	for field in ["slide_min_speed", "slide_friction", "slide_jump_mult",
			"ram_bounce_min_speed", "ram_bounce_factor", "ram_thud_sound"]:
		assert_true("var %s" % field in content,
			"player.gd must declare the %s tuning export" % field)
	assert_true("func _try_start_slide" in content,
		"player.gd must have the slide trigger _try_start_slide")
	assert_true("func _check_bounce" in content,
		"player.gd must have the pinball _check_bounce")


func test_night_vision_action_bound() -> void:
	assert_true(InputMap.has_action("NightVision"),
		"The NightVision toggle action must exist in the input map (bound to N by default)")


func test_post_process_shader_has_night_vision_uniform() -> void:
	var content := _read_file("res://resources/shaders/post_process.gdshader")
	assert_true("uniform float night_vision" in content,
		"post_process.gdshader must declare the night_vision uniform driven by player.gd")
