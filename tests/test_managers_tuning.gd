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
##   * GameSettings: the sub-resource accessor CLASS types (is <Class>) for the FULL
##     tuning-group registry, including the designer-first additions player_aim,
##     economy, player_feedback, npc_ai and station_music — neither test_autoload_order.gd (only
##     != null) nor test_smoke.gd (only per-field typeof) asserts that each slot is the
##     correct resource class, which is the real contract systems rely on.
##     (test_aim_sway.gd spot-checks player_aim's class in passing; the canonical
##     complete roster lives here.) Plus allow_timescale_changes's TYPE (test_smoke
##     asserts its value but not its type).
##   * Each tuning *Settings .gd: instantiated via ClassName.new() and asserted for
##     SCRIPT-DEFAULT value ranges + cross-field-ordering invariants. test_settings_load.gd
##     range-checks the serialized .tres (a different artifact) on a different subset of
##     fields, and test_smoke.gd asserts typeof on yet another subset — the .new()
##     defaults + ordering invariants here do not overlap with either. The groups added /
##     extended by the designer-first refactor follow the same rule with two extra
##     exclusions: EXACT-value pins for player_feedback live in test_player_core.gd and
##     for effects.blood_drop_* in test_effects.gd, so this file adds only the
##     range/ordering bounds those pins don't state (a range assert survives a designer
##     retune; a pin does not), and any bound those files already assert AS a range
##     (hurt_freeze_scale < 1, lpf cutoff < clear, dash_flash_peak_alpha < 1,
##     death_time_scale < 1, death_camera_roll > 0) is NOT repeated here.
##     EconomySettings, NpcAiSettings and the new weapon_general (swap/reload/hitstop/
##     tracer) + effects (gib/blood-drop/thrown-weapon-trail) fields had no prior default
##     coverage in any suite, so their range/ordering asserts land here in full.
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
	# `if stream == null: return` guard (AudioManager.gd:23-24) precedes any
	# get_tree()/add_child, so this call is reachable on a bare load().new() with no tree:
	# it must return without touching get_tree() and without spawning a player.
	var am = load("res://managers/AudioManager.gd").new()
	am.play_sfx(Vector3.ZERO, null)
	assert_eq(am.get_child_count(), 0,
		"play_sfx with a null stream must early-return before any get_tree()/node creation and spawn nothing — a missing stream is silently ignored, never a crash (if the guard were removed, the bare instance's null get_tree() would error here)")
	am.free()


func test_audio_manager_play_2d_sfx_null_stream_is_noop() -> void:
	# play_2d_sfx is `-> void`; do not capture its result. The `if stream == null: return`
	# guard (AudioManager.gd:39-40) precedes get_tree(). The non-null spawn+autofree path
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

func test_effect_factory_autoload_order_slots_are_packed_scenes() -> void:
	# Complementary to test_autoload_order.gd (which only asserts these two are non-null):
	# assert the CLASS type, not non-null again.
	var ef = load("res://managers/EffectFactory.gd").new()
	assert_true(ef.blood_particle is PackedScene,
		"EffectFactory.blood_particle must be a PackedScene (type contract, complementary to the non-null check in test_autoload_order.gd)")
	ef.free()


func test_effect_factory_spawn_at_null_scene_is_noop() -> void:
	# spawn_at returns Node (not void), so capturing its result is valid. The
	# `if scene == null: ... return null` guard (EffectFactory.gd:42-44) precedes
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
		"spawn_at is the core spawner the wrapper delegates to")
	# H3: only the blood-impact wrapper survives — the other 5 were dead (no gameplay caller) and their misleading
	# slots were removed. A by-name wrapper keeps the effect name out of gameplay strings, so its presence IS the contract.
	assert_true(ef.has_method("spawn_blood_particle"),
		"EffectFactory.spawn_blood_particle must exist — the one gameplay effect entry point this factory owns")
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
	assert_true(GameSettings.player_aim is PlayerAimSettings,
		"GameSettings.player_aim must be a PlayerAimSettings so AimSway's wander/sway reads resolve")
	assert_true(GameSettings.economy is EconomySettings,
		"GameSettings.economy must be an EconomySettings so bounty payouts / kill-credit / rep-reward reads resolve")
	assert_true(GameSettings.player_feedback is PlayerFeedbackSettings,
		"GameSettings.player_feedback must be a PlayerFeedbackSettings so the hurt/death/spawn feel reads (player.gd, player_hud.gd, damage_thud.gd) resolve")
	assert_true(GameSettings.npc_ai is NpcAiSettings,
		"GameSettings.npc_ai must be an NpcAiSettings so the shared NPC brain reads (targeting, medkit reflex, follow, scavenge) resolve")
	assert_true(GameSettings.distraction is DistractionSettings,
		"GameSettings.distraction must be a DistractionSettings so the thrown-decoy noise reads (Throwable._emit_decoy_noise) resolve")
	assert_true(GameSettings.dialogue is DialogueSettings,
		"GameSettings.dialogue must be a DialogueSettings so the talk pacing / letterbox / music-duck reads (TalkHelpers/DialogueManager/DialogueView/MusicDucker) resolve")
	assert_true(GameSettings.station_music is StationMusicSettings,
		"GameSettings.station_music must be a StationMusicSettings — the StationMusic autoload reads it LIVE on its very first _process frame, so a missing or mistyped group is a null-deref at boot, not a quiet degrade")
	assert_true(GameSettings.search is SearchSettings,
		"GameSettings.search must be a SearchSettings so the NPC search-feel reads (Perception / GoapActionSearch) resolve")
	assert_true(GameSettings.pickpocket is PickpocketSettings,
		"GameSettings.pickpocket must be a PickpocketSettings so LootScreen's steal-gate + caught roll reads resolve")


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
	assert_lte(s.footstep_slow_volume_db, 0.0,
		"footstep_slow_volume_db must be <= 0 — it is a dB cut making slow/creeping footsteps quieter (0 = off)")
	assert_gt(s.smoothing_reference_fps, 0.0,
		"smoothing_reference_fps must be > 0 — it is the divisor for frame-rate-independent smoothing; 0 would divide-by-zero")
	assert_gt(s.jump_buffer_time, 0.0,
		"jump_buffer_time must be > 0 so an early jump press is remembered until landing")
	assert_gt(s.fall_gravity_mult, 1.0,
		"fall_gravity_mult must be > 1 so descending jumps accelerate faster than the rising arc")
	assert_gt(s.max_continuous_fall_time, 0.0,
		"max_continuous_fall_time must be > 0 so a player falling forever eventually dies")
	assert_gt(s.walk_speed_mult, 0.0,
		"walk_speed_mult must be > 0 so the slow-walk tier still moves the player")
	assert_lt(s.walk_speed_mult, 1.0,
		"walk_speed_mult must be < 1 so walking is slower (and quieter) than running")
	assert_gte(s.step_up_height, 0.5,
		"step_up_height must cover a 16-unit TrenchBroom stair step at FuncGodot's 32:1 scale")
	assert_gte(s.step_down_snap, s.step_up_height,
		"step_down_snap must cover step_up_height so stepped-up/down stairs keep the player grounded")
	assert_gt(s.step_min_horizontal_speed, 0.0,
		"step_min_horizontal_speed must be > 0 so passive collision recovery does not auto-step")
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
	assert_gt(s.pitch_recenter_speed, 0.0,
		"pitch_recenter_speed must be > 0 so the pitch clamp eases back in (0 would freeze the contraction)")
	assert_gt(s.bob_horizontal_ratio, 0.0,
		"bob_horizontal_ratio must be > 0 so the head-bob has its figure-8 side-sway")
	assert_gt(s.bob_min_speed, 0.0,
		"bob_min_speed must be > 0 so a near-still player eases the bob out instead of jittering")
	assert_gt(s.dof_scoped_far_distance, 0.0,
		"dof_scoped_far_distance must be > 0 — the scoped far-blur distance")
	assert_gt(s.scoped_fog_density_factor, 0.0,
		"scoped_fog_density_factor must be > 0 so a crisp scope thins (not kills) the fog")
	assert_lte(s.scope_music_duck_db, 0.0,
		"scope_music_duck_db must be <= 0 — it LOWERS the music while scoped (0 = no duck)")
	assert_gt(s.scope_music_duck_time, 0.0,
		"scope_music_duck_time must be > 0 so the scope music duck fades instead of snapping")
	s = null


func test_dialogue_settings_defaults() -> void:
	var s = DialogueSettings.new()
	assert_gt(s.npc_turn_to_face_duration, 0.0,
		"npc_turn_to_face_duration must be > 0 so the NPC turns to face instead of snapping")
	assert_gt(s.talk_prompt_buffer_duration, 0.0,
		"talk_prompt_buffer_duration must be > 0 so talking PROMPTS a response (a beat) rather than instantly opening the box")
	assert_gt(s.dialogue_intro_delay, 0.0,
		"dialogue_intro_delay must be > 0 so the turn/camera swing plays before the first line opens")
	assert_gt(s.dialogue_speaker_face_duration, 0.0,
		"dialogue_speaker_face_duration must be > 0 so the speaker turns to face as the box opens")
	assert_true(s.dialogue_speaker_face_duration <= s.dialogue_intro_delay,
		"the speaker face-turn must finish within the intro delay beat (it's timed to land before the box opens)")
	assert_gt(s.letterbox_bar_height_fraction, 0.0,
		"letterbox_bar_height_fraction must be > 0 so the cinematic bars are visible")
	assert_lt(s.letterbox_bar_height_fraction, 0.5,
		"letterbox_bar_height_fraction must be < 0.5 so the two bars don't meet and black out the screen")
	assert_gt(s.letterbox_slide_in_duration, 0.0,
		"letterbox_slide_in_duration must be > 0 so the bars slide instead of snapping")
	assert_lte(s.music_duck_amount_db, 0.0,
		"music_duck_amount_db must be <= 0 — it LOWERS the music during a conversation (0 = no duck)")
	assert_gt(s.music_duck_fade_duration, 0.0,
		"music_duck_fade_duration must be > 0 so the music duck fades instead of snapping")
	# Box layout (panel / text / choices / speaker name) — all positive pixel/font sizes; the two proportions
	# (hint opacity, choices scroll cap) stay within 0..1.
	for px in [s.panel_horizontal_margin, s.panel_vertical_margin, s.panel_inner_padding,
			s.panel_vertical_element_spacing, s.dialogue_text_font_size, s.dialogue_text_outline_width,
			s.choice_button_font_size, s.choice_button_spacing, s.dialogue_continue_hint_font_size,
			s.speaker_name_font_size, s.speaker_name_outline_width, s.speaker_name_screen_x_offset,
			s.speaker_name_screen_y_offset]:
		assert_gt(px, 0, "every dialogue-box pixel/font size must be > 0 (got %d)" % px)
	assert_gt(s.dialogue_continue_hint_opacity, 0.0,
		"dialogue_continue_hint_opacity must be > 0 so the continue hint is visible")
	assert_lte(s.dialogue_continue_hint_opacity, 1.0,
		"dialogue_continue_hint_opacity must be <= 1 (it's an alpha)")
	assert_gt(s.choices_scroll_max_height_fraction, 0.0,
		"choices_scroll_max_height_fraction must be > 0 so the choices area has height")
	assert_lt(s.choices_scroll_max_height_fraction, 1.0,
		"choices_scroll_max_height_fraction must be < 1 so a long menu scrolls instead of filling the screen")
	s = null


func test_search_settings_defaults() -> void:
	# Stealth Slice 8 search-feel dials. The PARITY defaults must keep the search INERT (today's single-point stare):
	# max_search_radius == 0 and sample_points == 1 collapse the breadcrumb trail to the last-known spot, and a null
	# intensity_curve reads as flat energy. The seeding scales are sane but only bite once max_search_radius > 0.
	var s = SearchSettings.new()
	assert_eq(s.max_search_radius, 0.0,
		"max_search_radius must default 0 — the master inert switch: 0 forces a single-point search (today's stare)")
	assert_eq(typeof(s.sample_points), TYPE_INT,
		"sample_points must be an int — it is a breadcrumb count")
	assert_eq(s.sample_points, 1,
		"sample_points must default 1 — the legacy single breadcrumb (no multi-point sweep until a designer opts in)")
	assert_null(s.intensity_curve,
		"intensity_curve must default null — read through a null-guard as flat 1.0 (parity); no crash on the common path")
	assert_gte(s.uncertainty_grow_rate, 0.0,
		"uncertainty_grow_rate must be >= 0 — it expands the search area over time; negative would shrink it")
	assert_gte(s.max_search_radius, s.min_search_radius,
		"max_search_radius must be >= min_search_radius or the radius clamp would invert")
	assert_gt(s.noise_radius_scale, 0.0,
		"noise_radius_scale must be > 0 so a heard noise seeds a positive uncertainty area once seeding is on")
	assert_gte(s.corpse_radius_frac, 0.0,
		"corpse_radius_frac must be >= 0 — it is a fraction of the observer's sight_range")
	assert_gte(s.seed_radius, 0.0,
		"seed_radius must be >= 0 — the base combat lost-LOS uncertainty seed")
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


func test_weapon_general_settings_swap_reload_hitstop_tracer_defaults() -> void:
	# Sibling to test_weapon_general_settings_defaults covering the fields the designer-first
	# refactor moved onto WeaponGeneralSettings (swap/reload handling per attack.gd/reload.gd,
	# hitstop scaling per shot_resolver.gd, tracers per damage_trace.gd) — no other suite
	# asserts their defaults.
	var s = WeaponGeneralSettings.new()
	assert_gt(s.swap_raise_duration, 0.0,
		"swap_raise_duration must be > 0 — attack.gd assigns it to the swap Timer's wait_time, and a 0 wait would snap the incoming weapon up instead of raising it")
	assert_gt(s.auto_reload_delay, 0.0,
		"auto_reload_delay must be > 0 — the beat after running dry before attack.gd's auto-reload timer fires")
	assert_gt(s.reload_hold_threshold, 0.0,
		"reload_hold_threshold must be > 0 — reload.gd reloads on a press SHORTER than it and holsters on a hold AT/PAST it; at 0 every tap would holster and nothing could reload")
	assert_gt(s.hitstop_damage_reference, 0.0,
		"hitstop_damage_reference must be > 0 — shot_resolver.gd divides damage by it to scale the hitstop multiple, so 0 would divide-by-zero")
	assert_true(s.hitstop_crit_multiplier >= 1.0,
		"hitstop_crit_multiplier must be >= 1 so a crit never produces a WEAKER hitstop than the same non-crit hit")
	assert_true(s.hitstop_crit_multiplier <= s.hitstop_max_multiplier,
		"hitstop_crit_multiplier must fit under hitstop_max_multiplier or shot_resolver.gd's minf cap would clip every crit to the same value")
	assert_gt(s.tracer_thickness, 0.0,
		"tracer_thickness must be > 0 so tracers have visible width")
	assert_gt(s.tracer_lifetime, 0.0,
		"tracer_lifetime must be > 0 so a tracer persists for a visible window instead of despawning the frame it spawns")
	assert_gt(s.tracer_reference_dist, 0.0,
		"tracer_reference_dist must be > 0 — the perspective-compensation distance at which a tracer reads at its authored thickness; 0 would zero/blow up the scaling ratio")
	assert_gt(s.visual_tracer_fallback_distance, 0.0,
		"visual_tracer_fallback_distance must be > 0 so damage_trace.gd still draws a tracer of some length for a shot that hits nothing")
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
	assert_gt(s.blood_decal_grow_time, 0.0,
		"blood_decal_grow_time must be > 0 so a landed blood decal grows in instead of popping to full size")
	assert_gt(s.blood_decal_fadeout_delay, 0.0,
		"blood_decal_fadeout_delay must be > 0 so blood decals linger before fading")
	assert_gt(s.muzzle_flash_radius, 0.0,
		"muzzle_flash_radius must be > 0 so the spray-can muzzle flash is visible")
	assert_gt(s.hit_spark_backoff, 0.0,
		"hit_spark_backoff must be > 0 so the impact spark sits proud of the surface, not inside it")
	assert_gt(s.hit_spark_speed_to_scale, 0.0,
		"hit_spark_speed_to_scale must be > 0 so a faster impact blooms a bigger spark")
	assert_gt(s.overkill_burst_radius, 0.0,
		"overkill_burst_radius must be > 0 so the pierce-through feedback burst is visible")
	assert_gt(s.gun_holster_animation_time, 0.0,
		"gun_holster_animation_time must be > 0 so the holster/draw swings instead of snapping")
	assert_gte(s.death_freeze_duration, 0.0,
		"death_freeze_duration must be >= 0 — 0 disables the freeze-in-place beat, positive holds the enemy that long before it gores")
	assert_lt(s.death_freeze_duration, 1.0,
		"death_freeze_duration is a 'split-second' juice beat, not a long stall — keep it well under a second")
	assert_lt(s.gun_holster_position_offset.y, 0.0,
		"gun_holster_position_offset must drop the gun BELOW view (negative Y) while holstered")
	assert_ne(s.gun_holster_rotation_offset, Vector3.ZERO,
		"gun_holster_rotation_offset must tilt the gun (barrel down) while holstered")
	# "Gun Reload & Landing (view model)" — the GunMesh reload/land dip + raise knobs. Range/ordering
	# only, per this file's charter: the gun_raise_time EXACT anchor (== GUN_RAISE_MS/1000, the
	# laser-gate coupling) lives in test_effects.gd, and the damage_number_* exact mirrors live in
	# test_damage_number_popup.gd.
	assert_lt(s.gun_reload_dip_position.y, 0.0,
		"gun_reload_dip_position must drop the gun DOWN (negative Y) while a reload/swap plays")
	assert_gt(s.gun_reload_dip_time, 0.0,
		"gun_reload_dip_time must be > 0 so the reload dip swings instead of snapping")
	assert_gt(s.gun_raise_time, 0.0,
		"gun_raise_time must be > 0 — it drives both the post-reload raise tween and the laser-sight gate window")
	assert_lt(s.gun_land_dip, 0.0,
		"gun_land_dip must be negative — the gun absorbs a landing by dipping DOWN")
	assert_gt(s.gun_land_pitch, 0.0,
		"gun_land_pitch must be > 0 so the barrel rises as the gun absorbs the landing")
	assert_gt(s.gun_land_in_time, 0.0,
		"gun_land_in_time must be > 0 so the landing dip animates in instead of teleporting the pose")
	assert_gt(s.gun_land_out_time, 0.0,
		"gun_land_out_time must be > 0 so the gun recovers from the landing dip instead of snapping")
	s = null


func test_effects_settings_gore_defaults() -> void:
	# Sibling to test_effects_settings_defaults covering the gib + world blood-drop fields the
	# designer-first refactor moved onto EffectsSettings (consumed by gore_spawner.gd and
	# blood_drop_emitter.gd). EXACT pins for blood_drop_scatter/vel_min/vel_max live in
	# test_effects.gd (test_blood_drop_emitter_tuning_defaults) — only the range/ordering
	# angles those pins don't state are asserted here.
	var s = EffectsSettings.new()
	assert_eq(typeof(s.gib_count), TYPE_INT,
		"gib_count must be an int — a bloody-mess death bursts into a whole number of gibs")
	assert_gt(s.gib_count, 0,
		"gib_count must be > 0 or a bloody-mess death would burst into nothing")
	assert_true(s.gib_spawn_offset_y_min <= s.gib_spawn_offset_y_max,
		"gib_spawn_offset_y_min must not exceed max — they bound the randomized spawn height around the victim")
	assert_true(s.gib_vel_min < s.gib_vel_max,
		"gib_vel_min must be < gib_vel_max so the launch-speed randf_range is a valid ascending range")
	assert_true(s.gib_up_bias_min <= s.gib_up_bias_max,
		"gib_up_bias_min must not exceed max — they bound the extra upward fling each gib gets")
	assert_gt(s.gib_angular_range, 0.0,
		"gib_angular_range must be > 0 so gibs tumble instead of flying frozen in a fixed orientation")
	assert_eq(typeof(s.gib_hp_min), TYPE_INT,
		"gib_hp_min must be an int — shots-to-pop is counted in whole hits")
	assert_true(s.gib_hp_min >= 1,
		"gib_hp_min must be >= 1 so every gib survives its own spawn and takes at least one shot to pop")
	assert_true(s.gib_hp_min <= s.gib_hp_max,
		"gib_hp_min must not exceed gib_hp_max — they bound the randomized shots-to-pop range")
	assert_eq(typeof(s.gib_max_active), TYPE_INT,
		"gib_max_active must be an int — gore_spawner.gd compares it against the live &\"gib\" group size")
	assert_gt(s.gib_max_active, 0,
		"gib_max_active must be > 0 or gore_spawner.gd's oldest-first reclaim would delete every gib the moment it spawns")
	assert_gt(s.gib_fade_time, 0.0,
		"gib_fade_time must be > 0 so a despawning gib fades out instead of popping away")
	assert_gt(s.gib_lifetime, s.gib_fade_time,
		"gib_lifetime must exceed gib_fade_time so a gib lingers fully visible before its fade-out window begins")
	assert_gt(s.blood_drop_scatter, 0.0,
		"blood_drop_scatter must be > 0 so wound droplets spread around the death origin instead of stacking on one point")
	assert_true(s.blood_drop_vel_min < s.blood_drop_vel_max,
		"blood_drop_vel_min must be < max so the droplet launch-speed randf_range is a valid ascending range")
	s = null


func test_effects_settings_body_part_gib_defaults() -> void:
	# Sibling to test_effects_settings_gore_defaults for the "Body-part gibs" group — the burst that flings
	# the dying character's OWN head/torso/arms/legs (gore_spawner.gd _spawn_body_part_gibs). RELATIONAL
	# assertions only, like its sibling, so retuning the feel never breaks the suite.
	var s = EffectsSettings.new()
	assert_eq(typeof(s.body_part_gibs_enabled), TYPE_BOOL,
		"body_part_gibs_enabled is the master switch gore_spawner.gd reads when an actor has no BodyPartGibs drop-in")
	assert_eq(typeof(s.body_part_gib_meat_count), TYPE_INT,
		"body_part_gib_meat_count must be an int — it feeds a `for i in count` loop")
	assert_gte(s.body_part_gib_meat_count, 0,
		"body_part_gib_meat_count must be >= 0; 0 is the legitimate 'body parts only, no loose gore' setting")
	assert_true(s.body_part_gib_vel_min < s.body_part_gib_vel_max,
		"body_part_gib_vel_min must be < max so the limb launch-speed randf_range is a valid ascending range")
	assert_true(s.body_part_gib_up_bias_min <= s.body_part_gib_up_bias_max,
		"body_part_gib_up_bias_min must not exceed max — they bound the upward pop each limb gets")
	assert_gt(s.body_part_gib_angular_range, 0.0,
		"body_part_gib_angular_range must be > 0 so limbs cartwheel instead of flying frozen")
	assert_gte(s.body_part_gib_spread, 0.0,
		"body_part_gib_spread must be >= 0; 0 means limbs fly exactly outward from the body's centre")
	assert_gte(s.body_part_gib_launch_inherit, 0.0,
		"body_part_gib_launch_inherit must be >= 0 — a negative share would fling the body INTO the blast that killed it")
	assert_eq(typeof(s.body_part_gib_hp_min), TYPE_INT,
		"body_part_gib_hp_min must be an int — shots-to-pop is counted in whole hits")
	assert_gte(s.body_part_gib_hp_min, 1,
		"body_part_gib_hp_min must be >= 1 so a limb survives its own spawn and takes at least one shot to pop")
	assert_lte(s.body_part_gib_hp_min, s.body_part_gib_hp_max,
		"body_part_gib_hp_min must not exceed max — they bound the randomized shots-to-pop range")
	assert_gt(s.body_part_gib_mass, 0.0,
		"body_part_gib_mass must be > 0 — a massless RigidBody3D is invalid to the physics server")
	assert_gt(s.body_part_gib_fade_time, 0.0,
		"body_part_gib_fade_time must be > 0 so a despawning limb fades out instead of popping away")
	assert_gt(s.body_part_gib_lifetime, s.body_part_gib_fade_time,
		"body_part_gib_lifetime must exceed its fade time so a limb lingers fully visible before fading")
	assert_gte(s.gib_max_active, s.body_part_gib_meat_count + 6,
		"gib_max_active must fit ONE death's whole burst (up to 6 body parts + the meat chunks) or a single kill evicts its own gibs — body parts share the &\"gib\" group and its oldest-first cap")
	s = null


func test_effects_settings_throw_trail_defaults() -> void:
	# Sibling to the gore/gib default tests for the "Thrown weapon trail" group — the white streak a thrown weapon
	# drags in flight (scripts/components/throw_trail.gd, stamped onto EVERY weapon drop from WeaponData.thrown_trail,
	# which defaults ON).
	# RANGE + ORDERING only, like its siblings: these are feel knobs a designer retunes, and a value pin would
	# turn "the streak is a little longer now" into a red suite. tests/test_throw_trail.gd covers the behaviour
	# these numbers feed.
	var s = EffectsSettings.new()
	assert_eq(typeof(s.throw_trail_enabled), TYPE_BOOL,
		"throw_trail_enabled is the master switch ThrowTrail reads before it builds anything")
	assert_gt(s.throw_trail_width, 0.0,
		"throw_trail_width must be > 0 or the ribbon has no width and the streak is invisible")
	assert_gt(s.throw_trail_lifetime, 0.0,
		"throw_trail_lifetime must be > 0 — at 0 every sample ages out the frame it is laid, so nothing ever draws")
	assert_gt(s.throw_trail_min_speed, 0.0,
		"throw_trail_min_speed must be > 0 so a prop that has come to rest stops laying streak (this is what ends the effect on landing)")
	assert_gt(s.throw_trail_reference_dist, 0.0,
		"throw_trail_reference_dist must be > 0 — it divides the view distance in the perspective compensation")
	assert_eq(typeof(s.throw_trail_max_points), TYPE_INT,
		"throw_trail_max_points must be an int — it caps a sample COUNT")
	assert_gte(s.throw_trail_max_points, 2,
		"throw_trail_max_points must be >= 2: one sample cannot make a triangle strip, so a lower cap would sample forever and never draw")
	# The one ORDERING pin in this group, and the only cross-resource one: the streak is now on EVERY weapon, and
	# an ordinary weapon leaves the hand at exactly pickup_throw_impulse (PickupRay._release sets it as the
	# velocity outright). A min_speed at or above that floor doesn't disable the effect visibly — it silently
	# reverts it to knife-only, because the knife's 2.5x thrown_impulse_mult is the one thing still clearing the
	# bar. That is the exact bug shape this file exists to catch: two independently-sensible tuning numbers whose
	# PRODUCT breaks a feature, with no single test in either system able to see it.
	var phys = PhysicsDamageSettings.new()
	assert_lt(s.throw_trail_min_speed, phys.pickup_throw_impulse,
		"throw_trail_min_speed must stay UNDER pickup_throw_impulse (the speed an ordinary throw leaves the hand at) or every weapon except the HURLED knife throws bare")
	phys = null
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
		"ram_damage must be an int — it is the integer MINIMUM body-check damage (the floor RamReactor applies under the speed curve)")
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
	assert_eq(typeof(s.pickup_held_collision_layer), TYPE_INT,
		"pickup_held_collision_layer must be an int — it is a physics collision-layer index")
	assert_gt(s.pickup_held_collision_layer, 0,
		"pickup_held_collision_layer must be > 0 to name a valid physics layer for held pickups")
	assert_true(s.interactable_impact_min_velocity < s.interactable_impact_max_velocity,
		"interactable_impact_min_velocity must be < max — they bound the velocity range mapped onto impact-sound volume")
	assert_true(s.interactable_impact_min_db <= s.interactable_impact_max_db,
		"interactable_impact_min_db must be <= max_db so faster impacts are at least as loud as gentle ones")
	assert_gt(s.pickup_throw_impulse, s.pickup_drop_impulse,
		"pickup_throw_impulse must exceed pickup_drop_impulse — throwing must launch an object harder than merely dropping it")
	s = null


func test_economy_settings_defaults() -> void:
	# No other suite covers EconomySettings defaults (tests/ grepped for economy/bounty —
	# nothing), so the whole group's ranges land here. Zorkmids are FRACTIONAL floats by
	# design (EconomySettings.gd doc); only the kill-credit window is an int.
	var s = EconomySettings.new()
	assert_eq(typeof(s.kill_credit_window_ms), TYPE_INT,
		"kill_credit_window_ms must be an int — character.gd compares it against Time.get_ticks_msec() deltas")
	assert_gt(s.kill_credit_window_ms, 0,
		"kill_credit_window_ms must be > 0 or no hit could ever earn its shooter the kill bounty when the victim dies")
	assert_gt(s.save_rep_reward, 0.0,
		"save_rep_reward must be > 0 so killing an NPC's attacker actually buys disposition (the rescue thank-you, npc.gd)")
	assert_true(s.kill_bounty >= 0.0,
		"kill_bounty must be >= 0 — a negative base bounty would FINE whoever downs a character")
	assert_true(s.headshot_kill_bounty >= 0.0,
		"headshot_kill_bounty must be >= 0 — the headshot killing-blow payout can be zeroed by a designer but never negative")
	assert_true(s.all_headshots_kill_bounty >= 0.0,
		"all_headshots_kill_bounty must be >= 0 — the every-point-was-a-headshot 'applause kill' payout can be zeroed but never negative")
	assert_true(s.collateral_bounty >= 0.0,
		"collateral_bounty must be >= 0 — the carried-overkill collateral payout can be zeroed but never negative")
	assert_true(s.collateral_headshot_bounty >= 0.0,
		"collateral_headshot_bounty must be >= 0 — the collateral-headshot payout can be zeroed but never negative")
	assert_true(s.confetti_bounty >= 0.0,
		"confetti_bounty must be >= 0 — the mid-air gib-swat payout can be zeroed but never negative")
	assert_true(s.long_range_min_distance >= 0.0,
		"long_range_min_distance must be >= 0 — a distance threshold is never negative (distance can't be)")
	assert_true(s.long_range_bounty >= 0.0,
		"long_range_bounty must be >= 0 — the flat marksman payout can be zeroed by a designer but never negative")
	assert_true(s.long_range_bounty_per_m >= 0.0,
		"long_range_bounty_per_m must be >= 0 — a negative per-metre slope would SHRINK the reward the farther you shot")
	assert_true(s.long_range_bounty_max >= 0.0,
		"long_range_bounty_max must be >= 0 — the cap on the marksman payout can be zeroed but never negative")
	# The Death group — what happens to the player's purse when they die. It is never destroyed: it goes to the
	# killer, or onto the ground where you fell (Player._bequeath_wallet). These pin the SCRIPT defaults; the
	# behaviour itself is in test_money.gd.
	assert_eq(s.death_purse_loss_fraction, 1.0,
		"death_purse_loss_fraction ships at 1.0 — death takes the WHOLE purse, which is only fair because you can always go and take it back")
	assert_true(s.death_purse_loss_fraction >= 0.0 and s.death_purse_loss_fraction <= 1.0,
		"death_purse_loss_fraction is a FRACTION of the wallet — outside 0..1 it would either pay the player for dying or take money they don't have")
	assert_true(s.death_purse_drops_when_unclaimed,
		"an unclaimed death drops the purse on the ground by default — otherwise a fall would silently destroy your zorkmids, the exact thing this feature exists to stop")
	assert_true(s.death_purse_drop_ground_probe >= 0.0,
		"death_purse_drop_ground_probe is a downward search DISTANCE (m) — negative would flip the probe upward and find ceilings; 0 legitimately disables it")
	assert_true(s.death_purse_drop_to_respawn_in_void,
		"a void death parks the purse at the respawn point by default — the alternative is refusing to drop it at all, which is the harsher stance and should be opt-in")
	s = null


func test_long_range_bonus_curve() -> void:
	# The pure marksman-bounty curve (EconomySettings.long_range_bonus_for) — off-tree, no nodes, in the
	# MoneyBag.size_for mold. This IS the whole gate for the "long-range kill" reward that character.gd's
	# _award_long_range_bonus pays, so the threshold / per-metre / cap behaviour is pinned here.
	# A close (melee-range) kill earns no extra bounty:
	assert_eq(EconomySettings.long_range_bonus_for(5.0, 30.0, 2.0, 0.1, 8.0), 0.0,
		"a kill closer than long_range_min_distance earns no long-range bounty")
	# Exactly at the threshold pays the flat amount (nothing per-metre yet):
	assert_eq(EconomySettings.long_range_bonus_for(30.0, 30.0, 2.0, 0.1, 8.0), 2.0,
		"a kill AT the threshold earns exactly the flat long_range_bounty")
	# Beyond the threshold adds per-metre: 30 m past × 0.1/m = +3 on top of the flat 2 = 5:
	assert_eq(EconomySettings.long_range_bonus_for(60.0, 30.0, 2.0, 0.1, 8.0), 5.0,
		"a kill beyond the threshold adds long_range_bounty_per_m for every metre past it")
	# An extreme cross-map shot is clamped to long_range_bounty_max, not paid raw:
	assert_eq(EconomySettings.long_range_bonus_for(1000.0, 30.0, 2.0, 0.1, 8.0), 8.0,
		"a very long shot is clamped to long_range_bounty_max so it can't pay absurdly")
	# The cap is FLOORED at flat (the maxf(flat, max_bonus) contract, EconomySettings.gd): long_range_bounty and
	# long_range_bounty_max are two independent @export floats with no cross-field validation, so a designer can
	# set the cap BELOW the flat payout — the floor guarantees the marksman reward is never dragged under `flat`.
	# These two pins fail if the clamp is ever regressed to a bare `max_bonus` (both would then pay 2.0, not 5.0):
	assert_eq(EconomySettings.long_range_bonus_for(30.0, 30.0, 5.0, 0.1, 2.0), 5.0,
		"a cap set below the flat payout is floored at flat — an at-threshold kill still pays the full flat reward")
	assert_eq(EconomySettings.long_range_bonus_for(1000.0, 30.0, 5.0, 0.1, 2.0), 5.0,
		"even at extreme distance the floor holds: a too-low cap can't drag the payout below flat")
	# Zeroing the payout knobs disables the reward at ANY distance (the designer's off switch):
	assert_eq(EconomySettings.long_range_bonus_for(500.0, 30.0, 0.0, 0.0, 0.0), 0.0,
		"zeroing long_range_bounty and long_range_bounty_per_m disables the reward at any distance")


# --- The Ledger's underwriting sheet (New Game's implant credit check) --------------------------------------
# The pure rating (EconomySettings.credit_rating_for) — off-tree, no nodes, the long_range_bonus_for mold. It
# rates a creation build on four lines (CAPACITY / VIABILITY / TRADE minus EXPOSURE, off the authored per-stat
# table) and the score sets the implant cart's spending limit. The tests below assert ORDERING and STRUCTURE
# rather than hand-computed magic numbers wherever possible, so a designer may re-price the actuarial table in
# EconomySettings.tres without breaking the suite — only the contracts must hold.

const CREDIT_FLOOR := -5   ## StatBudget.STAT_MIN — the allocator bounds the scorer normalizes against
const CREDIT_CEIL := 10    ## StatBudget.STAT_MAX

## ⭐The economy carrying the AUTHORED actuarial table. A bare EconomySettings.new() ships an EMPTY
## `credit_underwriting` array — a flat credit market where EVERY build rates exactly the baseline — so any
## test about ratings, orderings or reasons MUST use the live resource, which is where the six
## StatUnderwriting rows actually live. (`.new()` is still right for pinning script-default KNOBS, and for
## the deliberate empty-table degrade test.) Never free what this returns: it is the live shared resource,
## and a trailing `= null` in a test only drops the local reference.
func _live_eco() -> EconomySettings:
	return GameSettings.economy

## A throwaway COPY of the live economy — same authored table, safe to mutate one knob on. Resource.duplicate
## is shallow, which is exactly what we want: the StatUnderwriting rows are shared and never written to.
func _eco_copy() -> EconomySettings:
	return GameSettings.economy.duplicate() as EconomySettings

## A full six-key creation sheet (what StatBudget.to_dict always produces), defaulting every unnamed stat to 0.
func _credit_sheet(values: Dictionary) -> Dictionary:
	var out := {}
	for stat in CharacterStats.STAT_NAMES:
		out[stat] = int(values.get(stat, 0))
	return out


func _credit_score(values: Dictionary, eco: EconomySettings) -> int:
	return EconomySettings.credit_score_for(_credit_sheet(values), eco, CREDIT_FLOOR, CREDIT_CEIL)


func test_starting_credit_absent_sheet_and_no_file_sheet_are_different_inputs() -> void:
	# THE distinction the whole model rests on. An EMPTY dict is the ABSENCE of an application (a bare-scene
	# instantiation with no present_build) and fails OPEN to the ceiling — that is what keeps the implant
	# screen's Begin legitimately never-gated. The all-zero SIX-KEY sheet is a filed-but-empty form: a real
	# applicant who allocated nothing, scored normally at the baseline. The retired model conflated the two
	# and handed the do-nothing build the best terms in the game.
	var eco := _live_eco()
	assert_eq(EconomySettings.credit_score_for({}, eco, CREDIT_FLOOR, CREDIT_CEIL), eco.credit_score_max,
		"an ABSENT sheet ({}) fails open to score_max — no application means nothing to decline")
	assert_lt(_credit_score({}, eco), eco.credit_score_max,
		"a FILED but all-zero sheet is a real applicant with no assets — it must NOT rate the ceiling")
	assert_gt(_credit_score({}, eco), eco.credit_score_min,
		"…but allocating nothing is not a crime either: the no-file build still rates above the floor")
	eco = null


func test_starting_credit_committing_to_a_build_always_beats_allocating_nothing() -> void:
	# ⭐THE HEADLINE PIN — the exact inversion this model replaced. Under the retired formula the zero-sum
	# budget made every invested point cost a dumped point, so committing was a flat tax: gun+5/end-5 rated
	# 820 against the do-nothing build's 850. Spending the budget must RAISE the rating, never lower it.
	var eco := _live_eco()
	assert_gt(_credit_score({&"gunplay": 5, &"endurance": -5}, eco), _credit_score({}, eco),
		"a committed build out-rates the sheet that allocated nothing — the whole point of the model")
	eco = null


func test_starting_credit_orders_builds_by_quality() -> void:
	# Ordering, not values: a designer may re-price the table freely, but these relationships are the design.
	var eco := _live_eco()
	var operator := _credit_score({&"gunplay": 10, &"strength": 10, &"endurance": -5, &"agility": -5,
		&"streetwise": -5, &"larceny": -5}, eco)
	var ghost := _credit_score({&"larceny": 8, &"agility": 7, &"strength": -5, &"endurance": -5, &"gunplay": -5}, eco)
	var dabbler := _credit_score({&"strength": 3, &"gunplay": 3, &"agility": 2, &"streetwise": 2,
		&"endurance": -5, &"larceny": -5}, eco)
	var nothing := _credit_score({}, eco)
	var crippled := _credit_score({&"strength": -5, &"endurance": -5, &"gunplay": -5, &"agility": -5,
		&"streetwise": -5, &"larceny": -5}, eco)
	assert_gt(operator, ghost, "a fully committed two-stat specialist out-rates a lighter one")
	assert_gt(ghost, dabbler, "a real specialty out-rates points sprinkled across four stats")
	assert_gt(dabbler, nothing, "even a scattered build out-rates allocating nothing at all")
	assert_gt(nothing, crippled, "…and allocating nothing out-rates actively crippling yourself")
	assert_eq(crippled, eco.credit_score_min, "the all-dumped build bottoms out exactly at score_min")
	eco = null


func test_starting_credit_is_monotone_in_every_stat() -> void:
	# ⭐THE STRUCTURAL PROPERTY. Positives feed only the additive lines and negatives only the subtractive one,
	# so raising any stat can NEVER lower a score and lowering any can NEVER raise it — for any authored table.
	# That is what makes re-creating the retired inverted model impossible rather than merely unlikely. A
	# deterministic sweep stands in for the exhaustive proof (the full space is ~1.7M builds).
	var eco := _live_eco()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260807  # deterministic: the same sheets every run
	var free_lunch := 0
	var spend_penalty := 0
	for i in 200:
		var sheet := {}
		for stat in CharacterStats.STAT_NAMES:
			sheet[stat] = rng.randi_range(CREDIT_FLOOR, CREDIT_CEIL)
		var base := EconomySettings.credit_score_for(sheet, eco, CREDIT_FLOOR, CREDIT_CEIL)
		for stat in CharacterStats.STAT_NAMES:
			if int(sheet[stat]) > CREDIT_FLOOR:
				var lower := sheet.duplicate()
				lower[stat] = int(sheet[stat]) - 1
				if EconomySettings.credit_score_for(lower, eco, CREDIT_FLOOR, CREDIT_CEIL) > base:
					free_lunch += 1
			if int(sheet[stat]) < CREDIT_CEIL:
				var higher := sheet.duplicate()
				higher[stat] = int(sheet[stat]) + 1
				if EconomySettings.credit_score_for(higher, eco, CREDIT_FLOOR, CREDIT_CEIL) < base:
					spend_penalty += 1
	assert_eq(free_lunch, 0,
		"lowering a stat must NEVER raise the score — a free lunch means dumping pays, the retired model's bug")
	assert_eq(spend_penalty, 0,
		"raising a stat must NEVER lower the score — a spend penalty is literally a tax on having a character")
	eco = null


func test_starting_credit_degrades_safely_on_a_bad_table() -> void:
	# Fail-safes, each mirroring an existing convention. None of these may crash or invert the model.
	var eco := _live_eco()
	var build := _credit_sheet({&"gunplay": 10, &"strength": 10, &"endurance": -5, &"agility": -5,
		&"streetwise": -5, &"larceny": -5})
	var shipped := EconomySettings.credit_score_for(build, eco, CREDIT_FLOOR, CREDIT_CEIL)
	# An unrecognised stat key is inert — the bank simply has no row for it (fail-quiet at runtime; the drift
	# test below is where a missing row fails loud).
	var with_junk := build.duplicate()
	with_junk[&"zzz_not_a_stat"] = 10
	assert_eq(EconomySettings.credit_score_for(with_junk, eco, CREDIT_FLOOR, CREDIT_CEIL), shipped,
		"a stat name with no underwriting row neither crashes nor moves the rating")
	# An EMPTY table is a flat credit market at the baseline — never a bank that declines everybody. This is
	# the ONE case that legitimately wants a bare .new(): an unauthored economy is exactly what it models.
	var flat := EconomySettings.new()
	flat.credit_underwriting = []
	var baseline_score := int(roundf(float(flat.credit_score_min)
		+ float(flat.credit_score_max - flat.credit_score_min) * flat.credit_baseline_fraction))
	assert_eq(EconomySettings.credit_score_for(build, flat, CREDIT_FLOOR, CREDIT_CEIL), baseline_score,
		"an unauthored table rates every build at the baseline — a flat market, not a blanket decline")
	# A mis-authored NEGATIVE weight is floored to 0, i.e. it DISABLES that line rather than inverting it.
	# ⭐Note the direction differs by line, which is the whole point of pinning it: zeroing one of the three
	# ADDITIVE lines removes a bonus (the score falls), while zeroing the SUBTRACTIVE exposure line removes a
	# penalty (the score rises). What must never happen is the sign flipping — a negative weight paying score
	# in proportion to the thing it was meant to charge for.
	for knob in ["credit_weight_capacity", "credit_weight_viability", "credit_weight_trade"]:
		var bad := _eco_copy()  # the AUTHORED table with one knob sabotaged — a bare .new() would have no table to distort
		bad.set(knob, -50.0)
		var zeroed := _eco_copy()
		zeroed.set(knob, 0.0)
		assert_eq(EconomySettings.credit_score_for(build, bad, CREDIT_FLOOR, CREDIT_CEIL),
			EconomySettings.credit_score_for(build, zeroed, CREDIT_FLOOR, CREDIT_CEIL),
			"a negative %s behaves exactly like 0 — the line is disabled, never inverted" % knob)
		assert_lte(EconomySettings.credit_score_for(build, bad, CREDIT_FLOOR, CREDIT_CEIL), shipped,
			"…and since %s is an ADDITIVE line, disabling it can only lower this build's rating" % knob)
		bad = null
		zeroed = null
	var no_exposure := _eco_copy()
	no_exposure.credit_weight_exposure = -50.0
	var exposure_off := _eco_copy()
	exposure_off.credit_weight_exposure = 0.0
	assert_eq(EconomySettings.credit_score_for(build, no_exposure, CREDIT_FLOOR, CREDIT_CEIL),
		EconomySettings.credit_score_for(build, exposure_off, CREDIT_FLOOR, CREDIT_CEIL),
		"a negative credit_weight_exposure also behaves exactly like 0 — floored, never inverted")
	assert_gte(EconomySettings.credit_score_for(build, no_exposure, CREDIT_FLOOR, CREDIT_CEIL), shipped,
		"…and because exposure is the SUBTRACTIVE line, disabling it RAISES this dumped build's rating")
	no_exposure = null
	exposure_off = null
	# A null settings object degrades instead of null-dereferencing.
	assert_eq(EconomySettings.credit_score_for(build, null, CREDIT_FLOOR, CREDIT_CEIL), 0,
		"a null EconomySettings degrades to a declined rating rather than crashing the New Game flow")
	eco = null
	flat = null


func test_starting_credit_underwriting_table_covers_every_stat() -> void:
	# DRIFT: a stat added to CharacterStats.STAT_NAMES without a row here is invisible to the bank — it would
	# silently contribute nothing to any rating. Fail-quiet in the score, so it must fail LOUD in CI.
	var eco: EconomySettings = GameSettings.economy
	var priced := {}
	for row in eco.credit_underwriting:
		assert_not_null(row, "no null rows in the shipped actuarial table")
		if row != null:
			assert_false(priced.has(row.stat), "stat '%s' is priced exactly once — a duplicate row double-counts it" % row.stat)
			priced[row.stat] = true
	for stat in CharacterStats.STAT_NAMES:
		assert_true(priced.has(stat),
			"'%s' has a StatUnderwriting row in EconomySettings.tres — an unpriced stat is invisible to the credit check" % stat)


func test_starting_credit_reason_codes_are_actionable() -> void:
	# The filed reason names the underwriting line the build falls furthest under, so the player can read it
	# off their own sheet. These are the four diagnoses the screen can print, plus the two overrides.
	var eco := _live_eco()
	var function_of := func(values: Dictionary) -> StringName:
		return EconomySettings.credit_rating_for(_credit_sheet(values), eco, CREDIT_FLOOR, CREDIT_CEIL)["reason"]
	assert_eq(function_of.call({}), EconomySettings.REASON_NO_FILE,
		"allocating nothing files 'no established identity', not a line-item fault")
	assert_eq(function_of.call({&"gunplay": 4, &"strength": -5, &"endurance": -5}), EconomySettings.REASON_UNSPENT,
		"idle freed points override the line ranking — that IS the player's real problem")
	assert_eq(function_of.call({&"strength": 3, &"gunplay": 3, &"agility": 2, &"streetwise": 2,
		&"endurance": -5, &"larceny": -5}), EconomySettings.REASON_THIN_TRADE,
		"a build with no peak is filed as having no trade of record")
	assert_eq(function_of.call({&"gunplay": 10, &"strength": 10, &"endurance": -5, &"agility": -5,
		&"streetwise": -5, &"larceny": -5}), EconomySettings.REASON_NONE,
		"a near-perfect build is COMMENDED, never scolded — the commendation fraction overrides the ranking")
	eco = null


func test_starting_credit_score_curve() -> void:
	# The shipped rating of the canonical builds — the numbers the design was tuned to, pinned so a re-price
	# of the actuarial table is a DELIBERATE act rather than a silent drift. (Ordering + structure are pinned
	# separately above, so a designer retuning the table only has to revisit this one test.)
	var eco := _live_eco()
	assert_eq(_credit_score({}, eco), 432,
		"the no-file build rates 432 — good for one cheap chip, so allocating nothing is never a lockout")
	assert_eq(_credit_score({&"gunplay": 10, &"strength": 10, &"endurance": -5, &"agility": -5,
		&"streetwise": -5, &"larceny": -5}, eco), 842,
		"the best legal build rates 842 — deliberately just under score_max: the Ledger never quotes its own ceiling")
	assert_eq(_credit_score({&"gunplay": 5, &"endurance": -5}, eco), 600,
		"the headline regression case (which the retired model fined BELOW the do-nothing build) now rates 600")
	assert_eq(_credit_score({&"strength": -5, &"endurance": -5, &"gunplay": -5, &"agility": -5,
		&"streetwise": -5, &"larceny": -5}, eco), 300,
		"the self-crippled build reaches score_min honestly (every line at its worst), not by clamp arithmetic")
	# No cliff off zero: the first traded point must be a smooth step, not a jump.
	var one_step := _credit_score({&"strength": 1, &"endurance": -1}, eco)
	var two_step := _credit_score({&"strength": 2, &"endurance": -2}, eco)
	assert_gt(one_step, _credit_score({}, eco), "the very first traded point already improves the rating")
	assert_gt(two_step, one_step, "…and the second improves it again — a smooth ramp, no cliff off zero")
	eco = null


func test_starting_credit_limit_curve() -> void:
	# The pure limit mapping (EconomySettings.credit_limit_for): score_min..score_max -> 0..limit_max shaped by
	# `curve`, floored to whole steps (banks quote round numbers), quantized to the coin grid. The eight
	# assertions below all omit `curve`, which DEFAULTS to 1.0 = the plain linear map — they are unchanged from
	# before the gamma was added precisely so the new argument can't have altered the existing mapping.
	# A perfect score earns EXACTLY the cap — the "up to 2100 zm" contract:
	assert_eq(EconomySettings.credit_limit_for(850, 300, 850, 2100.0, 50.0), 2100.0,
		"score_max earns exactly limit_max — the cap is reachable, never overshot")
	# A mid score maps linearly then floors to the step: (575-300)/550 = 0.5 -> 1050 (already on-step):
	assert_eq(EconomySettings.credit_limit_for(575, 300, 850, 2100.0, 50.0), 1050.0,
		"the mid-range score earns the linear share of the cap")
	# The step FLOORS, never rounds up: 670 -> 1412.7 raw -> 1400:
	assert_eq(EconomySettings.credit_limit_for(670, 300, 850, 2100.0, 50.0), 1400.0,
		"the limit floors to whole credit_limit_step quotes — the bank never rounds in your favour")
	# Step 0 = unstepped (coin-grid quantized only): 670 -> 1412.73:
	assert_eq(EconomySettings.credit_limit_for(670, 300, 850, 2100.0, 0.0), 1412.73,
		"a zero step disables the round-number flooring — the raw linear limit, coin-quantized")
	# The worst shipped-knob build (score 310) floors all the way to NO credit:
	assert_eq(EconomySettings.credit_limit_for(310, 300, 850, 2100.0, 50.0), 0.0,
		"a floor-adjacent score steps down to zero credit — the bank can decline outright")
	# A score below the range clamps to nothing rather than going negative:
	assert_eq(EconomySettings.credit_limit_for(250, 300, 850, 2100.0, 50.0), 0.0,
		"a score under score_min clamps to zero credit, never negative")
	# The documented OFF-SWITCH: a degenerate score range (min >= max) rates everyone at the cap:
	assert_eq(EconomySettings.credit_limit_for(400, 500, 500, 2100.0, 50.0), 2100.0,
		"score_min == score_max is the credit check's off-switch — every build rates the full cap")
	# The SHIPPED gamma (1.6) is what the game actually quotes — pin the live path too, not just the identity.
	assert_eq(EconomySettings.credit_limit_for(842, 300, 850, 2100.0, 50.0, 1.6), 2050.0,
		"the best legal build (842) is advanced 2050 zm — just under the advertised cap, by design")
	assert_eq(EconomySettings.credit_limit_for(432, 300, 850, 2100.0, 50.0, 1.6), 200.0,
		"the no-file build (432) is still advanced 200 zm — exactly one cheap chip, so nobody is locked out")
	assert_eq(EconomySettings.credit_limit_for(600, 300, 850, 2100.0, 50.0, 1.6), 750.0,
		"a serviceable rating (600) buys 750 zm — the gamma makes a mediocre file buy proportionally less")
	assert_lt(EconomySettings.credit_limit_for(575, 300, 850, 2100.0, 50.0, 1.6),
		EconomySettings.credit_limit_for(575, 300, 850, 2100.0, 50.0, 1.0),
		"a gamma above 1 lends LESS at every score below the ceiling than the linear map did")
	assert_eq(EconomySettings.credit_limit_for(850, 300, 850, 2100.0, 50.0, 1.6), 2100.0,
		"…but the ceiling itself is unmoved: a perfect score still earns the whole cap at any gamma")
	# The shipped knob defaults — the feature's authored contract, incl. the 2100 zm ceiling:
	var s := EconomySettings.new()
	assert_eq(s.credit_limit_max, 2100.0, "credit_limit_max ships at 2100 zm — the specified ceiling")
	assert_eq(s.credit_score_min, 300, "credit_score_min ships at the classic 300 floor")
	assert_eq(s.credit_score_max, 850, "credit_score_max ships at the classic 850 ceiling")
	assert_eq(s.credit_limit_step, 50.0, "credit_limit_step ships at 50 zm round-number quotes")
	assert_eq(s.credit_limit_curve, 1.6, "credit_limit_curve ships at 1.6 (the .tres is knob-default here, so this IS the live gamma)")
	assert_eq(s.credit_baseline_fraction, 0.24, "credit_baseline_fraction ships at 0.24 — where the no-file applicant sits")
	assert_eq(s.credit_weight_capacity, 0.48, "the CAPACITY weight ships at 0.48")
	assert_eq(s.credit_weight_viability, 0.38, "the VIABILITY weight ships at 0.38")
	assert_eq(s.credit_weight_trade, 0.23, "the TRADE weight ships at 0.23")
	assert_eq(s.credit_weight_exposure, 0.30, "the EXPOSURE weight ships at 0.30 — the only subtractive line")
	assert_eq(s.credit_depth_points, 8,
		"credit_depth_points ships at 8 — anchored on the pickpocket equipped-weapon threshold, the game's one real stat breakpoint")
	assert_eq(s.credit_dump_exponent, 1.6, "credit_dump_exponent ships at 1.6 — pledges price superlinearly")
	s = null


func test_player_feedback_settings_defaults() -> void:
	# Range/ordering angles ONLY — EXACT pins for the hurt/dash/respawn/death fields live in
	# test_player_core.gd, and the bounds it already asserts AS ranges (hurt_freeze_scale < 1,
	# lpf cutoff < clear, dash_flash_peak_alpha < 1, death_time_scale < 1,
	# death_camera_roll > 0) are deliberately NOT repeated here.
	var s = PlayerFeedbackSettings.new()
	assert_gt(s.hurt_freeze_scale, 0.0,
		"hurt_freeze_scale must be > 0 — a time_scale of 0 would hard-stop the engine instead of dipping into slow-mo")
	assert_gt(s.hurt_freeze_hold, 0.0,
		"hurt_freeze_hold must be > 0 so the slow-mo dip is actually held for a beat before easing back")
	assert_gt(s.hurt_recovery, 0.0,
		"hurt_recovery must be > 0 so slow-mo + muffle + screen drain ease back over time instead of snapping (a 0 tween duration is degenerate)")
	assert_gt(s.hurt_lpf_cutoff, 0.0,
		"hurt_lpf_cutoff must be > 0 Hz — a 0 low-pass cutoff would silence the master bus entirely at full hurt instead of muffling it")
	assert_gt(s.hurt_flash_peak_alpha, 0.0,
		"hurt_flash_peak_alpha must be > 0 or taking damage would show no red flash at all")
	assert_true(s.hurt_flash_peak_alpha <= 1.0,
		"hurt_flash_peak_alpha must be <= 1 — flash_hurt() writes it straight into the overlay's color.a, which tops out at opaque")
	assert_gt(s.hurt_flash_time, 0.0,
		"hurt_flash_time must be > 0 — it is the flash fade-out tween's duration, so 0 would kill the pulse the frame it starts")
	assert_eq(typeof(s.hurt_flash_color), TYPE_COLOR,
		"hurt_flash_color must be a Color — player_hud.gd build() constructs the overlay tint from it")
	assert_eq(s.hurt_flash_color.a, 1.0,
		"hurt_flash_color must stay authored fully opaque (a == 1) — its alpha is IGNORED at the read site (player_hud.gd build() rebuilds it as Color(rgb, 0.0) and flash_hurt() drives alpha from hurt_flash_peak_alpha), so a designer-authored alpha here would silently do nothing")
	assert_gt(s.dash_flash_peak_alpha, 0.0,
		"dash_flash_peak_alpha must be > 0 or the air-dash recharge cue would be invisible")
	assert_gt(s.dash_flash_time, 0.0,
		"dash_flash_time must be > 0 so the recharge flash fades over a visible window")
	assert_eq(typeof(s.damage_thud_cooldown_ms), TYPE_INT,
		"damage_thud_cooldown_ms must be an int — damage_thud.gd compares it against msec tick deltas")
	assert_gt(s.damage_thud_cooldown_ms, 0,
		"damage_thud_cooldown_ms must be > 0 so a pellet burst plays ONE low body-blow thud, not a drumroll")
	assert_true(s.damage_thud_volume_db <= 0.0,
		"damage_thud_volume_db must be <= 0 dB — the thud sits UNDER the hit sound, never boosted above it")
	assert_gt(s.death_time_scale, 0.0,
		"death_time_scale must be > 0 — the death slow-mo eases the world DOWN, never to a dead stop")
	assert_gt(s.death_sequence_time, 0.0,
		"death_sequence_time must be > 0 so the keel-over/drain/fade cinematic has a duration at all")
	assert_gt(s.respawn_delay, 0.0,
		"respawn_delay must be > 0 so the fully-black death beat is perceptible before the respawn")
	assert_gte(s.death_card_delay, 0.0,
		"death_card_delay cannot be negative — 0 is the old card-on-the-black-frame timing, anything above is the settle beat")
	assert_gt(s.spawn_fade_in_time, 0.0,
		"spawn_fade_in_time must be > 0 so a fresh spawn fades up from black instead of hard-cutting")
	assert_gte(s.respawn_hud_delay, 0.0,
		"respawn_hud_delay cannot be negative — 0 restores the HUD + receipts on the revive's first frame")
	assert_lt(s.respawn_hud_delay, s.spawn_fade_in_time,
		"respawn_hud_delay must end inside the spawn fade-up — a longer quiet window would leave the player playing with no HUD after the world is fully visible")
	assert_eq(typeof(s.sneak_toast_cooldown_ms), TYPE_INT,
		"sneak_toast_cooldown_ms must be an int — player.gd compares it against msec tick deltas")
	assert_gt(s.sneak_toast_cooldown_ms, 0,
		"sneak_toast_cooldown_ms must be > 0 so a multi-pellet sneak shot shows ONE toast line, not a stack")
	# Out-of-combat recovery — the RELATIONAL angle only; the shipped-.tres bounds live in test_settings_load.gd.
	assert_gt(s.combat_calm_grace, 0.0,
		"combat_calm_grace must be > 0 — a 0 grace would call you out of combat on the same frame you fired, and the heartbeat would duck mid-firefight")
	assert_gte(s.health_regen_commit_frac, 0.0,
		"health_regen_commit_frac cannot be negative — 0 is legal and means commit every frame (smoothest bar, one `damaged` emit per frame)")
	assert_lt(s.health_regen_commit_frac, s.health_regen_cap_frac,
		"the commit step must be smaller than the ceiling it climbs toward, or the regen banks a slice it can never pay out")
	s = null


func test_npc_ai_settings_defaults() -> void:
	# The species-wide NPC brain dials (NpcAiSettings.gd) — behaviour suites (test_npc_items.gd,
	# test_hostility.gd, test_npc_inventory.gd) READ some of these fields to drive scenarios but
	# none range-asserts the defaults, so the whole group's ranges land here.
	var s = NpcAiSettings.new()
	assert_gt(s.retarget_interval, 0.0,
		"retarget_interval must be > 0 — a 0 interval would re-run the full target-acquisition scan every frame")
	assert_gt(s.unranged_aim_fallback, 0.0,
		"unranged_aim_fallback must be > 0 so a weapon with no effective_range still has a usable engage range")
	assert_gt(s.fire_grace_range, 0.0,
		"fire_grace_range must be > 0 so a projectile weapon fires into its grace band — at 0 a kiting player can never be hit by a short-range gun (projectiles outfly the hitscan cap; that band is the counter)")
	assert_gt(s.point_blank_range, 0.0,
		"point_blank_range must be > 0 so the self-occluded-LOS fire-anyway carve-out exists at all")
	assert_lt(s.point_blank_range, s.unranged_aim_fallback,
		"point_blank_range must sit INSIDE even the fallback engage range — point-blank is the muzzle-crowding exception, not the normal engagement")
	assert_gt(s.miss_deflect_min_deg, 0.0,
		"miss_deflect_min_deg must be > 0 or a deliberately-missed warning shot could fly dead-on and kill")
	assert_lt(s.miss_deflect_min_deg, s.miss_deflect_max_deg,
		"miss_deflect_min_deg must be < max so the warning-shot deflection randf_range is a valid ascending range")
	assert_gt(s.medkit_hp_frac, 0.0,
		"medkit_hp_frac must be > 0 or no HP level would ever trigger the medkit reflex")
	assert_true(s.medkit_hp_frac <= 1.0,
		"medkit_hp_frac must be <= 1 — it is a fraction of max HP; above 1 an NPC would chug medkits at full health")
	assert_eq(typeof(s.medkit_cooldown_ms), TYPE_INT,
		"medkit_cooldown_ms must be an int — npc.gd compares it against msec tick deltas")
	assert_gt(s.medkit_cooldown_ms, 0,
		"medkit_cooldown_ms must be > 0 so a badly hurt NPC doesn't drain its whole backpack of medkits in one frame")
	assert_gt(s.holster_delay, 0.0,
		"holster_delay must be > 0 so the weapon stays drawn through a beat of calm before re-holstering")
	assert_gt(s.follow_standoff, 0.0,
		"follow_standoff must be > 0 so followers hold formation distance instead of standing inside the leader")
	assert_gt(s.follow_teleport_distance, s.follow_standoff,
		"follow_teleport_distance must exceed follow_standoff or a follower holding normal formation would qualify for the catch-up blink")
	assert_gt(s.follow_teleport_cooldown, 0.0,
		"follow_teleport_cooldown must be > 0 so the catch-up blink can't fire every frame")
	assert_gt(s.seat_return_radius, 0.0,
		"seat_return_radius must be > 0 or a `sitting` NPC could never be close enough to its post to sit at all")
	assert_gte(s.seat_return_radius, 1.0,
		"seat_return_radius must clear the Locomotor's default arrival_distance (1.0) — the return-to-post walk stops within that, so a smaller radius would leave a returned sitter standing at its own chair forever (npc.gd floors it against the live value, but the shipped default should not need the floor)")
	assert_gt(s.scavenge_scan_interval, 0.0,
		"scavenge_scan_interval must be > 0 — a 0 interval would run the raid-a-container scan every frame")
	assert_gt(s.scavenge_scan_radius, 0.0,
		"scavenge_scan_radius must be > 0 or no container would ever be in scavenging reach")
	assert_eq(typeof(s.starting_clips), TYPE_INT,
		"starting_clips must be an int — spare ammo is counted in whole magazines (drives reloads and corpse loot)")
	assert_gt(s.starting_clips, 0,
		"starting_clips must be > 0 so an armed NPC can actually reload and its corpse yields ammo")
	# Stealth group — both consequence features OFF by default (so the no-target idle path stays
	# byte-identical), and a non-negative distraction scan throttle.
	assert_false(s.body_discovery,
		"body_discovery must default OFF — a stealth kill stays free until the designer opts in")
	assert_false(s.hearing_initiates,
		"hearing_initiates must default OFF — noise only matters once an NPC has a target, so idle stays byte-identical")
	assert_gte(s.distraction_scan_interval, 0.0,
		"distraction_scan_interval must be >= 0 (0 = scan the noise/corpse groups every frame)")
	assert_false(s.hearing_occlusion,
		"hearing_occlusion must default OFF -> sound rounds corners exactly as before (behaviour-preserving)")
	assert_gte(s.hearing_wall_attenuation, 0.0, "hearing_wall_attenuation must be >= 0 (a fraction of the radius cut by a wall)")
	assert_lte(s.hearing_wall_attenuation, 1.0, "hearing_wall_attenuation must be <= 1 (at most fully silences a walled-off noise)")
	assert_gt(s.hearing_source_skip, 0.5,
		"hearing_source_skip must exceed the player capsule radius (0.5) so the source's own body never self-occludes a clear line")
	s = null
