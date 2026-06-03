extends GutTest

## GUT suite for the "Managers + tuning" subsystem. Each test guards a load-bearing
## contract and its assert message states WHY the invariant matters, so this file
## doubles as executable documentation of the manager/tuning surface.
##
## SCOPE — this file deliberately covers only the angles NOT already asserted elsewhere:
##   * AudioManager: the pure DEFAULT_3D_MAX_DISTANCE constant, the two null-guard
##     no-op paths, and the public method surface (has_method). The non-null spawn
##     path is intentionally SKIPPED — it needs a SceneTree (get_tree()) and starts
##     real audio playback; test_audio_manager_spawn.gd already covers it in-tree.
##   * EffectFactory: the seven PackedScene @export slots not covered by
##     test_autoload_order.gd (which only checks blood_decal/explosion_area non-null),
##     the spawn_at(null) graceful-degradation guard, and the by-name wrapper surface.
##     We NEVER call a spawn method with a real scene — that instantiates + add_childs
##     particles into the live tree (a real visual/physics side effect), so only
##     has_method / slot-type checks are made.
##   * GameSettings: the sub-resource accessor CLASS types (is <Class>) — neither
##     test_autoload_order.gd (only != null) nor test_smoke.gd (only per-field typeof)
##     asserts that each slot is the correct resource class, which is the real contract
##     systems rely on. Plus allow_timescale_changes's TYPE (test_smoke asserts its
##     value but not its type).
##   * Each tuning *Settings .gd: instantiated via ClassName.new() and asserted for
##     SCRIPT-DEFAULT value ranges + cross-field-ordering invariants. test_settings_load.gd
##     range-checks the serialized .tres (a different artifact) on a different subset of
##     fields, and test_smoke.gd asserts typeof on yet another subset — the .new()
##     defaults + ordering invariants here do not overlap with either.
##
## TESTABILITY NOTES:
##   * AudioManager / EffectFactory are loaded with load(path).new() and NOT added to the
##     tree: they have no _ready/@onready (AudioManager) and only @export preload(uid://)
##     initializers (EffectFactory, resolved at script-compile time and merely re-bound on
##     .new(), per test_autoload_order.gd), so .new() is side-effect-free and get_tree()
##     stays null — making exactly the pre-get_tree() null-guard branches reachable. Each
##     is .free()'d.
##   * Settings subclasses are plain Resource (no _init/_ready) — built with ClassName.new()
##     and released with .free(), never add_child_autofree (they are not Nodes).
##   * play_sfx / play_2d_sfx are declared `-> void`, so their result must NOT be captured
##     into a variable (that is a GDScript analyzer error). Instead the null-guard tests
##     CALL the no-op (which, per AudioManager.gd, returns before any get_tree()/node
##     creation) and then assert get_child_count()==0 — the guarded path must spawn nothing,
##     and if the guard were removed the bare instance's null get_tree() would error and
##     fail the test, which is exactly the regression we want to catch.
##   * EffectFactory.spawn_at(null, ...) calls push_warning() before returning null — that
##     is a console warning, not a failure; it is expected and called out in the assert
##     message so it isn't mistaken for a real error in GUT output.


# ---------------------------------------------------------------------------
# AudioManager
# ---------------------------------------------------------------------------

func test_audio_manager_default_3d_max_distance() -> void:
	var am = load("res://managers/AudioManager.gd").new()
	assert_eq(typeof(am.DEFAULT_3D_MAX_DISTANCE), TYPE_FLOAT,
		"DEFAULT_3D_MAX_DISTANCE must be a float — it is assigned to AudioStreamPlayer3D.max_distance for every 3D one-shot")
	assert_gt(am.DEFAULT_3D_MAX_DISTANCE, 0.0,
		"DEFAULT_3D_MAX_DISTANCE must be positive or 3D one-shots would be inaudible (zero falloff distance)")
	am.free()


func test_audio_manager_play_sfx_null_stream_is_noop() -> void:
	# play_sfx is `-> void`, so its result must NOT be captured (analyzer error). The
	# `if stream == null: return` guard (AudioManager.gd:22-23) precedes any
	# get_tree()/add_child, so this call is reachable on a bare load().new() with no tree:
	# it must return without touching get_tree() and without spawning a player.
	var am = load("res://managers/AudioManager.gd").new()
	am.play_sfx(Vector3.ZERO, null)
	assert_eq(am.get_child_count(), 0,
		"play_sfx with a null stream must early-return before any get_tree()/node creation and spawn nothing — a missing stream is silently ignored, never a crash (if the guard were removed, the bare instance's null get_tree() would error here)")
	am.free()


func test_audio_manager_play_2d_sfx_null_stream_is_noop() -> void:
	# play_2d_sfx is `-> void`; do not capture its result. The `if stream == null: return`
	# guard (AudioManager.gd:36-37) precedes get_tree(). The non-null spawn+autofree path
	# is covered by test_audio_manager_spawn.gd.
	var am = load("res://managers/AudioManager.gd").new()
	am.play_2d_sfx(null)
	assert_eq(am.get_child_count(), 0,
		"play_2d_sfx with a null stream must be a safe no-op (returns before get_tree(), spawns nothing) so 2D call sites can pass an optional/missing stream without guarding")
	am.free()


func test_audio_manager_public_method_surface() -> void:
	var am = load("res://managers/AudioManager.gd").new()
	assert_true(am.has_method("play_sfx"),
		"play_sfx is a public entry point that 3D one-shot call sites depend on")
	assert_true(am.has_method("play_2d_sfx"),
		"play_2d_sfx is a public entry point that 2D one-shot call sites depend on")
	am.free()


# ---------------------------------------------------------------------------
# EffectFactory
# ---------------------------------------------------------------------------

func test_effect_factory_packed_scene_slots_present() -> void:
	# The seven slots NOT covered by test_autoload_order.gd (which checks blood_decal
	# & explosion_area). .new() re-binds the @export preload(uid://) references, which
	# are resolved at script-compile time per test_autoload_order.gd — so construction is safe.
	var ef = load("res://managers/EffectFactory.gd").new()
	for slot_name in ["blood_particle", "bloody_mess", "blood_drop",
			"bullet_hole_decal", "dust", "dust_large", "gib"]:
		var slot = ef.get(slot_name)
		assert_not_null(slot,
			"EffectFactory.%s must resolve to a PackedScene at construction or spawn_%s would have nothing to instantiate" % [slot_name, slot_name])
		assert_true(slot is PackedScene,
			"EffectFactory.%s must be a PackedScene so spawn_at can .instantiate() it" % slot_name)
	ef.free()


func test_effect_factory_autoload_order_slots_are_packed_scenes() -> void:
	# Complementary to test_autoload_order.gd (which only asserts these two are non-null):
	# assert the CLASS type, not non-null again.
	var ef = load("res://managers/EffectFactory.gd").new()
	assert_true(ef.blood_decal is PackedScene,
		"EffectFactory.blood_decal must be a PackedScene (type contract, complementary to the non-null check in test_autoload_order.gd)")
	assert_true(ef.explosion_area is PackedScene,
		"EffectFactory.explosion_area must be a PackedScene (type contract, complementary to the non-null check in test_autoload_order.gd)")
	ef.free()


func test_effect_factory_spawn_at_null_scene_is_noop() -> void:
	# spawn_at returns Node (not void), so capturing its result is valid. The
	# `if scene == null: ... return null` guard (EffectFactory.gd:29-31) precedes
	# get_tree(), so it is reachable on a bare load().new() with no tree. NOTE: this
	# branch emits push_warning("EffectFactory.spawn_at called with null scene") — an
	# expected console warning, NOT a failure.
	var ef = load("res://managers/EffectFactory.gd").new()
	var result = ef.spawn_at(null, Vector3.ZERO)
	assert_true(result == null,
		"spawn_at with a null scene must return null (graceful degradation) — a missing effect must not crash gameplay; the push_warning it logs is expected, not an error")
	ef.free()


func test_effect_factory_convenience_wrapper_surface() -> void:
	# has_method only — calling any of these with a real scene would instantiate + add_child
	# particles into get_tree().root (a real side effect), so we never invoke them.
	var ef = load("res://managers/EffectFactory.gd").new()
	assert_true(ef.has_method("spawn_at"),
		"spawn_at is the core spawner every convenience wrapper delegates to")
	for wrapper in ["spawn_blood_particle", "spawn_bloody_mess", "spawn_blood_drop",
			"spawn_dust", "spawn_dust_large", "spawn_gib"]:
		assert_true(ef.has_method(wrapper),
			"EffectFactory.%s must exist — by-name wrappers keep effect names out of gameplay strings, so their presence IS the contract" % wrapper)
	ef.free()


# ---------------------------------------------------------------------------
# GameSettings — sub-resource accessor CLASS types
# ---------------------------------------------------------------------------

func test_game_settings_sub_resource_class_types() -> void:
	# The live GameSettings autoload is the contract surface. Asserting each slot is its
	# DECLARED class (not merely != null, and not merely per-field typeof) is what every
	# system implicitly relies on when it reads GameSettings.<group>.<field>.
	assert_true(GameSettings.player_movement is PlayerMovementSettings,
		"GameSettings.player_movement must be a PlayerMovementSettings so player.gd's locomotion reads resolve")
	assert_true(GameSettings.player_crouch is PlayerCrouchSettings,
		"GameSettings.player_crouch must be a PlayerCrouchSettings so Crouch's height/speed reads resolve")
	assert_true(GameSettings.bunnyhop is BunnyhopSettings,
		"GameSettings.bunnyhop must be a BunnyhopSettings so Bunnyhop/MouseInput reads resolve")
	assert_true(GameSettings.camera is CameraSettings,
		"GameSettings.camera must be a CameraSettings so CameraEffects/Head/ScopeIn reads resolve")
	assert_true(GameSettings.screen_shake is ScreenShakeSettings,
		"GameSettings.screen_shake must be a ScreenShakeSettings so ScreenShake/Explosion reads resolve")
	assert_true(GameSettings.weapon_general is WeaponGeneralSettings,
		"GameSettings.weapon_general must be a WeaponGeneralSettings so BulletTime/Attack reads resolve")
	assert_true(GameSettings.effects is EffectsSettings,
		"GameSettings.effects must be an EffectsSettings so the decal/dust/blood/explosion FX reads resolve")
	assert_true(GameSettings.audio is AudioSettings,
		"GameSettings.audio must be an AudioSettings so player/attack/projectile audio reads resolve")
	assert_true(GameSettings.physics_damage is PhysicsDamageSettings,
		"GameSettings.physics_damage must be a PhysicsDamageSettings so explosion/ram/pickup/interactable reads resolve")


func test_game_settings_allow_timescale_changes_type() -> void:
	# test_smoke.gd asserts the VALUE is true; this asserts the TYPE (complementary).
	assert_eq(typeof(GameSettings.allow_timescale_changes), TYPE_BOOL,
		"allow_timescale_changes must be a bool — BulletTime/FreezeFrame branch on it as a flag")


# ---------------------------------------------------------------------------
# Tuning resources — .new() script-default ranges + cross-field ordering
# ---------------------------------------------------------------------------

func test_player_movement_settings_defaults() -> void:
	var s = PlayerMovementSettings.new()
	assert_gt(s.smoothing, 0.0,
		"smoothing must be > 0 — it is a per-frame lerp ratio; 0 would freeze movement interpolation")
	assert_lt(s.smoothing, 1.0,
		"smoothing must be < 1 — a per-frame lerp ratio of 1+ would overshoot/snap instead of easing")
	assert_gt(s.backward_mult, 0.0,
		"backward_mult must be > 0 so walking backward still moves the player")
	assert_lt(s.backward_mult, 1.0,
		"backward_mult must be < 1 so walking backward is slower than forward")
	assert_gt(s.strafe_mult, 0.0,
		"strafe_mult must be > 0 so strafing still moves the player")
	assert_lt(s.strafe_mult, 1.0,
		"strafe_mult must be < 1 so strafing is slower than running straight")
	assert_gt(s.footstep_base_interval, 0.0,
		"footstep_base_interval must be > 0 — it is the footstep cadence period; 0 would divide-by-zero / spam steps")
	assert_gt(s.smoothing_reference_fps, 0.0,
		"smoothing_reference_fps must be > 0 — it is the divisor for frame-rate-independent smoothing; 0 would divide-by-zero")
	assert_gt(s.jump_buffer_time, 0.0,
		"jump_buffer_time must be > 0 so an early jump press is remembered until landing")
	s = null


func test_player_crouch_settings_defaults() -> void:
	var s = PlayerCrouchSettings.new()
	assert_gt(s.lerp_speed, 0.0,
		"lerp_speed must be > 0 so the crouch transition actually progresses in/out")
	assert_gt(s.speed_mult, 0.0,
		"speed_mult must be > 0 so the player can still move while crouched")
	assert_lt(s.speed_mult, 1.0,
		"speed_mult must be < 1 so crouch-walking is a speed penalty, not free movement")
	assert_lt(s.quiet_footstep_db, 0.0,
		"quiet_footstep_db must be negative — it is a dB reduction that makes crouched footsteps quieter")
	s = null


func test_bunnyhop_settings_defaults() -> void:
	var s = BunnyhopSettings.new()
	assert_gt(s.boost_per_hop, 0.0,
		"boost_per_hop must be > 0 so each chained hop actually adds speed")
	assert_gt(s.land_window, 0.0,
		"land_window must be > 0 — it is the time window after landing to continue the chain")
	assert_gt(s.sens_reduction_threshold, 0.0,
		"sens_reduction_threshold must be > 0 — the speed at which look-sensitivity starts dropping")
	assert_gt(s.sens_min_multiplier, 0.0,
		"sens_min_multiplier must be > 0 so look-sensitivity never reaches zero (uncontrollable) at top speed")
	assert_lt(s.sens_min_multiplier, 1.0,
		"sens_min_multiplier must be < 1 so the floor is genuinely a reduction from full sensitivity")
	s = null


func test_camera_settings_defaults() -> void:
	var s = CameraSettings.new()
	assert_gt(s.scope_zoom_speed, 0.0,
		"scope_zoom_speed must be > 0 so ADS zoom actually interpolates the FOV")
	assert_gt(s.bob_speed, 0.0,
		"bob_speed must be > 0 so head-bob oscillates while walking")
	assert_gt(s.bob_amount, 0.0,
		"bob_amount must be > 0 so head-bob is visible")
	assert_gt(s.recovery_speed, 0.0,
		"recovery_speed must be > 0 so the camera eases back after a landing dip")
	assert_gt(s.fov_lerp_speed, 0.0,
		"fov_lerp_speed must be > 0 so dynamic FOV changes interpolate instead of snapping")
	assert_gt(s.tilt_speed, 0.0,
		"tilt_speed must be > 0 so the strafe tilt eases in/out")
	assert_gt(s.fov_punch_decay, 0.0,
		"fov_punch_decay must be > 0 so the air-dash FOV spike eases back to default (higher = snappier)")
	assert_true(s.pitch_soft_ramp_deg <= s.pitch_max_deg,
		"pitch_soft_ramp_deg must start at or below pitch_max_deg — the soft ramp begins before the hard pitch cap")
	s = null


func test_screen_shake_settings_defaults() -> void:
	var s = ScreenShakeSettings.new()
	assert_gt(s.intensity_multiplier, 0.0,
		"intensity_multiplier must be > 0 so trauma actually translates into visible shake")
	assert_gt(s.death_shake_range, 0.0,
		"death_shake_range must be > 0 so nearby deaths can shake the camera")
	assert_gt(s.death_shake_amount, 0.0,
		"death_shake_amount must be > 0 so a nearby death injects nonzero trauma")
	assert_gt(s.explosion_min_shake_radius, 0.0,
		"explosion_min_shake_radius must be > 0 so small explosions still register a shake floor")
	assert_gt(s.explosion_shake_mult, 0.0,
		"explosion_shake_mult must be > 0 so explosion proximity scales into trauma")
	s = null


func test_weapon_general_settings_defaults() -> void:
	var s = WeaponGeneralSettings.new()
	assert_gt(s.muzzle_flash_duration, 0.0,
		"muzzle_flash_duration must be > 0 so the muzzle flash is visible for a frame window")
	assert_gt(s.scope_spread_divisor, 1.0,
		"scope_spread_divisor must be > 1 so aiming down sights TIGHTENS spread (divides it down)")
	assert_gt(s.scope_speed_mult, 0.0,
		"scope_speed_mult must be > 0 so the player can still move while scoped")
	assert_lt(s.scope_speed_mult, 1.0,
		"scope_speed_mult must be < 1 so aiming down sights slows movement")
	assert_gt(s.bullet_time_lerp_speed, 0.0,
		"bullet_time_lerp_speed must be > 0 so the slow-mo ramps in/out instead of snapping")
	assert_gt(s.bullet_time_duration, 0.0,
		"bullet_time_duration must be > 0 so the bullet-time effect lasts a measurable time")
	s = null


func test_effects_settings_defaults() -> void:
	var s = EffectsSettings.new()
	assert_gt(s.decal_fade_min_alpha, 0.0,
		"decal_fade_min_alpha must be > 0 — the alpha floor a decal fades toward")
	assert_lt(s.decal_fade_min_alpha, 1.0,
		"decal_fade_min_alpha must be < 1 so the decal actually fades from full opacity")
	assert_gt(s.decal_normal_offset, 0.0,
		"decal_normal_offset must be > 0 to push the decal off the surface and avoid z-fighting")
	assert_gt(s.decal_probe_distance, 0.0,
		"decal_probe_distance must be > 0 so the surface-finding ray has reach")
	assert_true(s.blood_splatter_min_scale <= s.blood_splatter_max_scale,
		"blood_splatter_min_scale must not exceed max_scale — they bound a randomized blob size range")
	assert_gt(s.blood_splatter_base_size, 0.0,
		"blood_splatter_base_size must be > 0 so blood blobs have a visible base size")
	assert_gt(s.explosion_light_grow_speed, 0.0,
		"explosion_light_grow_speed must be > 0 so the explosion light animates outward")
	assert_gt(s.explosion_flash_speed, 0.0,
		"explosion_flash_speed must be > 0 so the explosion flash animates")
	assert_gt(s.explosion_min_flash_radius, 0.0,
		"explosion_min_flash_radius must be > 0 so even small explosions emit a flash")
	s = null


func test_audio_settings_defaults() -> void:
	var s = AudioSettings.new()
	assert_true(s.falling_air_min_move_speed < s.falling_air_max_move_speed,
		"falling_air_min_move_speed must be < max — the horizontal-speed window over which the wind swell ramps (distinct from the fall-speed window)")
	assert_true(s.falling_air_min_db < s.falling_air_max_db,
		"falling_air_min_db must be < max_db so the wind swells louder as speed increases")
	assert_true(s.impact_pitch_min < s.impact_pitch_max,
		"impact_pitch_min must be < max so the impact-sound randf_range has a valid ascending range")
	assert_gt(s.land_sfx_volume_db_reduction, 0.0,
		"land_sfx_volume_db_reduction must be > 0 — it is a positive dB amount subtracted to soften the landing sound")
	assert_gt(s.land_sfx_pitch_spread, 0.0,
		"land_sfx_pitch_spread must be > 0 so landing sounds get pitch variation instead of being identical")
	assert_gt(s.bullet_whiz_max_distance, 0.0,
		"bullet_whiz_max_distance must be > 0 for the AudioStreamPlayer3D whiz falloff to be audible")
	s = null


func test_physics_damage_settings_defaults() -> void:
	var s = PhysicsDamageSettings.new()
	assert_eq(typeof(s.explosion_damage), TYPE_INT,
		"explosion_damage must be an int — HP is integer, so explosion damage is dealt as an int")
	assert_gt(s.explosion_damage, 0,
		"explosion_damage must be > 0 so an explosion actually hurts")
	assert_eq(typeof(s.ram_damage), TYPE_INT,
		"ram_damage must be an int — it is the integer minimum/reference body-check damage")
	assert_gt(s.ram_damage, 0,
		"ram_damage must be > 0 so a body-check deals at least some damage")
	assert_gt(s.character_push_force, 0.0,
		"character_push_force must be > 0 so characters can shove RigidBody3D interactables they walk into")
	assert_gt(s.blast_grace_timer, 0.0,
		"blast_grace_timer must be > 0 so a blast's full impulse is retained briefly before decaying")
	assert_gt(s.blast_decay_rate, 0.0,
		"blast_decay_rate must be > 0 so blast-launch velocity eventually bleeds off")
	assert_gt(s.blast_min_magnitude, 0.0,
		"blast_min_magnitude must be > 0 — the threshold below which a blast push is ignored as negligible")
	assert_gt(s.enemy_ground_friction, 0.0,
		"enemy_ground_friction must be > 0 so knocked-back enemies decelerate on the ground")
	assert_gt(s.enemy_air_friction, 0.0,
		"enemy_air_friction must be > 0 so airborne knockback still bleeds off")
	assert_eq(typeof(s.pickup_held_collision_layer), TYPE_INT,
		"pickup_held_collision_layer must be an int — it is a physics collision-layer index")
	assert_gt(s.pickup_held_collision_layer, 0,
		"pickup_held_collision_layer must be > 0 to name a valid physics layer for held pickups")
	assert_eq(typeof(s.interactable_max_hp_default), TYPE_INT,
		"interactable_max_hp_default must be an int — interactable HP is integer")
	assert_gt(s.interactable_max_hp_default, 0,
		"interactable_max_hp_default must be > 0 so a default interactable can take at least one hit")
	assert_true(s.interactable_impact_min_velocity < s.interactable_impact_max_velocity,
		"interactable_impact_min_velocity must be < max — they bound the velocity range mapped onto impact-sound volume")
	assert_true(s.interactable_impact_min_db <= s.interactable_impact_max_db,
		"interactable_impact_min_db must be <= max_db so faster impacts are at least as loud as gentle ones")
	assert_gt(s.pickup_throw_impulse, s.pickup_drop_impulse,
		"pickup_throw_impulse must exceed pickup_drop_impulse — throwing must launch an object harder than merely dropping it")
	s = null
