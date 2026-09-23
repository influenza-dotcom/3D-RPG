extends GutTest

## GUT smoke-test suite: a cross-system grab bag. Most tests DRIVE real code (BulletTime's time_scale ownership, the
## Bunnyhop chain, ScreenShakeArea falloff, the on_nearby_death shake/freeze gates, the blast damp, the explosion
## flash, the decal basis, the Settings clamps) and the rest pin authored scene/resource wiring. Every assert message
## says what the PLAYER loses when it breaks. Run via the GUT panel or CLI.

## Concrete stand-in for the now-@abstract Character base, so tests can build one in-tree and drive Character's
## shared code (apply_velocity's blast damp, the gore notify) without a Player's or NPC's _ready.
class _ConcreteCharacter extends Character:
	pass

## A stand-in for anything in the Player group that a death nearby should reach: records every distance it is told.
class _DeathWitness extends Node3D:
	var heard: Array[float] = []

	func on_nearby_death(distance: float) -> void:
		heard.append(distance)

## The slice of the Player a Slide ability reads: the steering input and the stamina purse (always affordable here).
class _SlideHost extends Node:
	var input_dir: Vector2 = Vector2.ZERO

	func spend_stamina(_amount: float) -> bool:
		return true

## The slice of a Player that a Landing touchdown's DUST channel reaches. Off-tree (no prefab, no _ready): it records
## the intensity of every puff it is asked for instead of raycasting a particle into a world it doesn't have, and
## skips the fall-damage bill (test_upgrades drives that half of on_land).
class _DustLedgerPlayer extends Player:
	var puffs: Array[float] = []

	func spawn_dust(intensity: float = 1.0) -> void:
		puffs.append(intensity)

	func _apply_fall_damage(_fall_speed: float) -> void:
		pass

const PLAYER_SCENE = preload("res://scenes/player/Player.tscn")
const ENEMY_SCENE = preload("res://scenes/characters/enemy.tscn")
const ROCK_WEAPON = preload("res://resources/weapons/rock_weapon.tres")
const PISTOL = preload("res://resources/weapons/pistol.tres")
const SHOTGUN = preload("res://resources/weapons/shotgun.tres")
const SMG = preload("res://resources/weapons/smg.tres")
const MELEE = preload("res://resources/weapons/melee.tres")


## ⭐NO TEST IN THIS FILE MAY LEAK Engine.time_scale INTO THE NEXT SCRIPT, and only this file can leak it: it is
## the one place the house rule against running Player._ready() is deliberately broken (the on_nearby_death
## trauma/freeze contract needs a REAL Player), and a real Player in a headless tree falls through the void,
## takes fall damage and dies inside the test that made it. The hurt fires FreezeFrame.freeze(.., 0.15, ..),
## which stamps time_scale synchronously and only eases back on the far side of an await — and the death then
## calls FreezeFrame.cancel(), which by design does NOT restore it (in the game the death ramp re-stamps it
## every frame; here the instance is autofreed before any ramp runs). So the dip is stranded at 0.15 for the
## REST OF THE SUITE, and every later script that steps a component by hand reads a tenfold delta: measured
## 2026-09-03 as three failures with no shared cause on their face — tests/test_throw_trail.gd (a ribbon that
## ages 6.7x too slowly never decays) and two tests/test_wander_music.gd calm-clock waits (which divide their
## delta by time_scale, so half of resume_delay arrived as three times it).
##
## In after_each rather than at the end of each test, and cancel() BEFORE the write: GUT runs after_each even
## when a test fails its assert, and an in-flight recovery tween would otherwise animate over the reset.
func after_each() -> void:
	FreezeFrame.cancel()
	Engine.time_scale = 1.0
	# The slide test holds Crouch through Input; the explosion-flash test retunes a shared GameSettings knob.
	Input.action_release(&"Crouch")
	if _saved_flash_energy_per_radius >= 0.0:
		GameSettings.effects.explosion_flash_energy_per_radius = _saved_flash_energy_per_radius
		_saved_flash_energy_per_radius = -1.0
	if _saved_land_sfx_min_impact >= 0.0:
		GameSettings.audio.land_sfx_min_impact_to_play = _saved_land_sfx_min_impact
		_saved_land_sfx_min_impact = -1.0


## explosion_flash_energy_per_radius as it was before a test retuned it (-1 = untouched), restored in after_each.
var _saved_flash_energy_per_radius: float = -1.0
## land_sfx_min_impact_to_play as it was before the landing-dust test parked it out of reach (-1 = untouched).
var _saved_land_sfx_min_impact: float = -1.0


func test_player_scene_loads() -> void:
	assert_not_null(PLAYER_SCENE, "Player.tscn must preload")
	assert_true(PLAYER_SCENE is PackedScene, "Player.tscn must be a PackedScene")


## Drive Character.apply_velocity for ONE frame of a live blast on an in-tree base Character carrying `divisor` (<= 0 =
## keep the script default) and return the velocity the blast leaves behind. No collision shape and no floor, so the
## slide eats none of it: what remains is exactly what the blast damp let the body keep.
func _velocity_left_by_one_blast_frame(divisor: float = -1.0) -> Vector3:
	var c := _ConcreteCharacter.new()
	if divisor > 0.0:
		c.blast_damp_divisor = divisor
	add_child_autofree(c)
	c.velocity = Vector3.ZERO
	c.explosion_velocity = Vector3(10.0, 0.0, 0.0)
	c.apply_velocity()
	return c.velocity


func test_enemy_scene_keeps_none_of_a_blast_after_the_push_frame() -> void:
	# enemy.tscn overrides Character's blast damp so a knockback SHOVES an NPC on the frame it lands and leaves no carried
	# velocity behind — an enemy that kept a share of every live blast frame would sail off across the map. The divisor
	# is read off the authored scene WITHOUT entering the tree (NPC._ready must not run headless) and driven through the
	# base Character's apply_velocity, which does the same per-frame give-back as npc.gd's.
	var enemy: Character = ENEMY_SCENE.instantiate()
	var enemy_divisor: float = enemy.blast_damp_divisor
	enemy.free()
	var enemy_left := _velocity_left_by_one_blast_frame(enemy_divisor)
	assert_almost_eq(enemy_left.length(), 0.0, 0.001,
		"an enemy built from enemy.tscn must keep NO velocity once a blast frame has moved it (kept %s) — otherwise every live blast frame adds drift and knocked-back enemies fly off" % enemy_left)
	var default_left := _velocity_left_by_one_blast_frame()
	assert_gt(default_left.length(), 0.01,
		"control: the same blast frame on a Character with the script-default damp DOES leave carried velocity, so the enemy's zero comes from its scene override and not from apply_velocity doing nothing")

func test_enemy_body_placeholder_removed_and_mesh_retargeted() -> void:
	# REGRESSION: the vestigial Man.glb "Body" node was removed from enemy.tscn. The root's `mesh` export used to
	# point at "Body"; a bare delete would silently null `mesh`, and Character._setup_overlay_chain no-ops when
	# mesh == null — so the ENTIRE NPC combat outline + damage-flash + per-part hit-flash would silently die (no
	# crash, no error). The fix retargets `mesh` to the BodyModelSwap child. Pin it structurally: no _ready needed,
	# because node_paths (mesh) resolve at instantiate(), and a non-null `mesh` is all _setup_overlay_chain gates on.
	var enemy: Character = ENEMY_SCENE.instantiate()
	assert_null(enemy.get_node_or_null("Body"), "the vestigial Man.glb `Body` placeholder must be gone from enemy.tscn")
	assert_not_null(enemy.mesh, "the `mesh` export must resolve to a surviving node, or _flash_material never builds and the flash/outline chain silently dies")
	assert_eq(str(enemy.mesh.name), "BodyModelSwap", "`mesh` must be retargeted to the BodyModelSwap child (its subtree holds the swapped visible parts)")
	enemy.free()


func test_enemy_scene_wires_hurt_and_death_voice() -> void:
	# The NPC VOICE, both halves, authored in the SCENE: Damage.stream is the hurt grunt damage.gd replays on every
	# damage tick, and Death.death_cry is the last cry death.gd layers over the gore splash. Neither has a code
	# default, and clearing either is SILENT — damage.gd play()s a null stream as a no-op and AudioManager.play_sfx
	# early-outs on null — so an NPC would go mute with no error anywhere to find it by. Everything humanoid
	# (civilian / chip_mechanic / medicine_person) inherits enemy.tscn, so this one pin covers the whole roster.
	# instantiate() only: the wiring is scene data, no _ready required. .get() because get_node_or_null types as Node.
	var enemy: Character = ENEMY_SCENE.instantiate()
	var damage_node := enemy.get_node_or_null("Damage")
	assert_not_null(damage_node, "enemy.tscn must keep the Damage node (damage.gd hurt-SFX player, wired to the damaged signal)")
	assert_not_null(damage_node.get(&"stream"), "Damage.stream must stay authored — damage.gd only plays this node (via AudioManager.play_varied), and a null stream is a silent no-op")
	var death_node := enemy.get_node_or_null("Death")
	assert_not_null(death_node, "enemy.tscn must keep the Death node (death.gd death-SFX player, wired to the died signal)")
	assert_not_null(death_node.get(&"death_cry"), "Death.death_cry must stay authored — it is the dying NPC voice layered over the splash, and null plays nothing without erroring")
	enemy.free()


func test_a_blast_carries_a_default_character_on_by_only_a_fraction() -> void:
	# Character's default damp is the PLAYER-style retention: after the frame a blast moves you, part of the impulse
	# stays in your velocity (you keep flying with the shove) but strictly less than the blast itself, so the carry bleeds
	# off instead of snowballing. A divisor of 1 would keep nothing; below 1 it would fling the body back at the blast.
	var left := _velocity_left_by_one_blast_frame()
	assert_gt(left.x, 0.0,
		"a default Character must keep part of a blast's velocity after the push frame, in the blast's direction (kept %s)" % left)
	assert_lt(left.x, 10.0,
		"...but strictly less than the 10 m/s blast itself, or the carried shove would grow frame over frame (kept %s)" % left)


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


func test_time_scale_juice_ships_enabled_and_freeze_frame_honours_it() -> void:
	# The flag is a runtime var that tests and the debug console clear, so the SHIPPED value is read off a FRESH
	# GameSettings instance (no _ready, nothing loaded beyond its preloads) rather than the live autoload.
	var fresh: Node = load("res://managers/GameSettings.gd").new()
	assert_true(fresh.get(&"allow_timescale_changes") == true,
		"SHIP DECISION: GameSettings ships with allow_timescale_changes ON — off silently deletes every hit-stop and the scoped bullet time from the game")
	fresh.free()
	# Control for test_freeze_frame_respects_global_disable: with the flag at its shipped value (and the player's hitstop
	# accessibility toggle on) the SAME freeze call does stamp Engine.time_scale, so that test cannot pass vacuously.
	var prior_allowed := GameSettings.allow_timescale_changes
	var prior_hitstop: bool = Settings.hitstop_enabled
	GameSettings.allow_timescale_changes = true
	Settings.hitstop_enabled = true
	Engine.time_scale = 1.0
	FreezeFrame.freeze(0.001, 0.1, 0.05)
	var frozen_scale: float = Engine.time_scale
	GameSettings.allow_timescale_changes = prior_allowed
	Settings.hitstop_enabled = prior_hitstop
	assert_almost_eq(frozen_scale, 0.1, 0.0001,
		"with time-scale changes allowed, FreezeFrame.freeze must slam Engine.time_scale to its scale at once — the hit-stop the player feels")


## One BulletTime tick from READY in the state that DOES slow the world: scoped, airborne (a bare in-tree
## CharacterBody3D that never moved reports is_on_floor() == false) and scoped-in WHILE airborne, with a 0.1 s
## wall-clock step. Returns [Engine.time_scale right after the tick, whether the tick went ACTIVE, whether it claimed
## time-scale ownership], with Engine.time_scale and the global flag put back before it returns.
func _bullet_time_airborne_scope_tick(allowed: bool) -> Array:
	var prior_allowed := GameSettings.allow_timescale_changes
	GameSettings.allow_timescale_changes = allowed
	Engine.time_scale = 1.0
	var bt := BulletTime.new()
	add_child_autofree(bt)
	var body := CharacterBody3D.new()
	add_child_autofree(body)
	bt.character = body
	bt._is_scoped = true
	bt._scope_entered_in_air = true
	bt._last_us = Time.get_ticks_usec() - 100_000
	bt._process(0.016)
	var result := [Engine.time_scale, bt.is_active(), bt._managing_time_scale]
	Engine.time_scale = 1.0
	GameSettings.allow_timescale_changes = prior_allowed
	return result


func test_bullet_time_respects_global_disable() -> void:
	# CONTROL first: with time-scale changes allowed, this exact tick goes ACTIVE and pulls Engine.time_scale down, so
	# the disabled half cannot pass merely because nothing would have written time_scale anyway.
	var allowed := _bullet_time_airborne_scope_tick(true)
	assert_true(allowed[1], "precondition: a scoped, airborne, scoped-in-the-air tick must enter ACTIVE")
	assert_lt(allowed[0], 1.0,
		"control: with time-scale changes allowed that tick must slow Engine.time_scale — the slow-mo the player dives for")
	var disabled := _bullet_time_airborne_scope_tick(false)
	assert_true(disabled[1],
		"precondition: with the flag off the same tick must still go ACTIVE and reach the time-scale write, or the asserts below prove nothing")
	assert_eq(disabled[0], 1.0,
		"with GameSettings.allow_timescale_changes off, BulletTime must not write Engine.time_scale at all")
	assert_false(disabled[2],
		"…nor claim time-scale ownership, or once the flag came back it would ease a scale it never lowered back to 1.0 over FreezeFrame's")


func test_freeze_frame_respects_global_disable() -> void:
	var prior := Engine.time_scale
	Engine.time_scale = 1.0
	GameSettings.allow_timescale_changes = false
	FreezeFrame.freeze(0.001, 0.1, 0.05)
	assert_eq(Engine.time_scale, 1.0,
		"FreezeFrame must not write to Engine.time_scale while disabled")
	GameSettings.allow_timescale_changes = true
	Engine.time_scale = prior


func test_preload_manager_tts_prewarm_runs_clean_and_leaks_nothing() -> void:
	# Boot-time warmers that move the first-kill hitch (the Flite voice extraction + process-wide voice cache, and the
	# GPU-particle death shaders) off the combat frame. PreloadManager._ready dispatches both BY NAME
	# (call_deferred(&"_prewarm_tts") / call_deferred(&"_prewarm_gpu_particles")), so a rename still parses and only
	# silently drops the warm-up in a real build: that is what the two name pins guard.
	assert_true(PreloadManager.has_method(&"_prewarm_tts"),
		"PreloadManager must expose _prewarm_tts — _ready call_deferreds it by name for the boot-time Flite voice warm-up")
	assert_true(PreloadManager.has_method(&"_prewarm_gpu_particles"),
		"PreloadManager must expose _prewarm_gpu_particles — _ready call_deferreds it by name for the boot-time death-effect shader warm-up")
	# Driven for real: the headless renderer skips the native engine half, and the pass must leave nothing behind — the
	# throwaway VoiceManager node it builds is freed. (An engine error anywhere in the call also fails this test.)
	# That VoiceManager is built OFF-tree, so a leak shows up as an ORPHAN node: OBJECT_NODE_COUNT only counts nodes
	# inside the SceneTree and would stay flat even if the free were dropped.
	var prior_offloading := VoiceManager._voice_offloading_started
	var orphans_before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	PreloadManager._prewarm_tts()
	var orphans_after := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	VoiceManager._voice_offloading_started = prior_offloading
	assert_eq(orphans_after, orphans_before,
		"the boot TTS prewarm must free the VoiceManager node it builds — otherwise every launch leaks a node nobody can see")


func test_bunnyhop_default_chain_zero() -> void:
	var bh := Bunnyhop.new()
	add_child_autofree(bh)
	assert_eq(bh.chain, 0, "Bunnyhop chain must start at 0")
	assert_almost_eq(bh.get_target_speed(0.0), GameSettings.player_movement.max_speed, 0.001,
		"With chain=0 and nothing carried, target speed must degrade to PLAYER_MAX_SPEED")


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
	# The chain GAINS on the speed carried in, so the ceiling is reached by compounding rather than by the
	# chain COUNT — a carry already at the cap must clamp instead of adding another boost_per_hop.
	var bh := Bunnyhop.new()
	add_child_autofree(bh)
	bh.chain = 9999
	assert_eq(bh.get_target_speed(GameSettings.bunnyhop.max_speed), GameSettings.bunnyhop.max_speed,
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


func test_landing_dust_grows_from_a_small_puff_to_the_full_puff_with_impact() -> void:
	# Driven through the real Landing.on_land on an off-tree host, so the sizes compared are the intensities production
	# hands spawn_dust, never a local copy of the curve. DustSpawner scales the dust prefab by that intensity and clamps
	# its particle amount_ratio at 1.0, so 1.0 is the full authored puff. The land SFX reads global_position (an error
	# off-tree), so its gate is parked above any 0..1 impact for this test and restored in after_each.
	_saved_land_sfx_min_impact = GameSettings.audio.land_sfx_min_impact_to_play
	GameSettings.audio.land_sfx_min_impact_to_play = 2.0
	var divisor: float = GameSettings.player_movement.landing_impact_divisor
	var gate: float = GameSettings.effects.dust_land_min_impact_to_spawn
	var host := _DustLedgerPlayer.new()
	var landing := Landing.new()
	landing.host = host
	var stutter_fall := -gate * 0.5 * divisor  # a step-down at half the dust gate
	landing.on_land(stutter_fall, Vector3(0.0, stutter_fall, 0.0))
	var stutter_puffs := host.puffs.size()
	var light_fall := -gate * 1.01 * divisor  # the lightest landing that clears the gate
	landing.on_land(light_fall, Vector3(0.0, light_fall, 0.0))
	var hard_fall := -2.0 * divisor  # twice the fall speed that already counts as a full-impact landing
	landing.on_land(hard_fall, Vector3(0.0, hard_fall, 0.0))
	var puffs: Array = host.puffs.duplicate()
	landing.free()
	host.free()
	assert_eq(stutter_puffs, 0,
		"a stutter landing under dust_land_min_impact_to_spawn must kick up no dust")
	assert_eq(puffs.size(), 2,
		"the lightest landing past the dust gate and a hard fall must each kick up exactly one puff")
	if puffs.size() == 2:
		assert_lt(puffs[0], puffs[1] * 0.5,
			"a light landing must puff well under half the dust of a hard fall (%.3f vs %.3f) — the puff has to read how far you fell, like the thud does" % [puffs[0], puffs[1]])
		assert_almost_eq(puffs[1], 1.0, 0.01,
			"a full-impact landing must puff the full authored dust (intensity 1.0: the prefab's own scale and the amount_ratio ceiling), no bigger and no smaller")


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
	# (volume is deliberately NOT a global knob — it stays authored per projectile scene; only falloff is global,
	# stamped onto WhizSFX in Projectile._ready)
	assert_eq(typeof(GameSettings.audio.bullet_whiz_max_distance), TYPE_FLOAT)
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


## The barrel-smoke trail is authored INTO the view model (under the same PlayerMuzzle marker as the flash,
## sparks and casing) and wired by GunMesh.setup, so nothing in the firing pipeline knows it exists. That
## makes the scene node + the one signal connection the whole contract — pin both, plus the three emitter
## flags that keep the curl WELDED to the barrel rather than becoming a world-space trail.
func test_muzzle_smoke_node_present_and_connected() -> void:
	var player_scene := load("res://scenes/player/Player.tscn") as PackedScene
	var instance := player_scene.instantiate()
	add_child_autofree(instance)
	var smoke := instance.find_child("MuzzleSmoke", true, false) as GPUParticles3D
	assert_not_null(smoke, "Player.tscn must contain a MuzzleSmoke emitter somewhere under the gun rig")
	if smoke == null:
		return
	assert_true(smoke.has_method("_on_attack_flash_muzzle"),
		"MuzzleSmoke must have the _on_attack_flash_muzzle handler so flash_muzzle can arm the hot-barrel window")
	assert_false(smoke.one_shot,
		"The barrel-smoke emitter must NOT be one_shot — smoke is a CONTINUOUS stream gated by the hot-barrel window, and a one_shot emitter would restart (and so wipe) the trail on every round of a burst")
	assert_true(smoke.local_coords,
		"The barrel-smoke emitter must simulate in LOCAL space — it is welded to the barrel on purpose. World space looks right standing still and loses the whole strand behind the camera the moment you advance, and inherit_velocity_ratio does not rescue it (0.75 still lost it at 3.2 m/s, and back when damping was non-zero it bled even 1.0 straight back off). Note the cost this buys: direction and gravity are then LOCAL vectors, which is why MuzzleSmoke._drive_wave has to re-aim them at true world up every frame")
	assert_almost_eq((smoke.process_material as ParticleProcessMaterial).inherit_velocity_ratio, 0.0, 0.0001,
		"inherit_velocity_ratio must stay 0 while local_coords is on — in local space the emitter's own motion is already accounted for, and inheriting it again double-counts")
	assert_false(smoke.emitting,
		"The barrel-smoke emitter must sit idle in the authored scene — it only ever runs because a shot fired it")
	var attack: Attack = instance.get_node("Weapon/Attack")
	assert_true(attack.flash_muzzle.is_connected(smoke._on_attack_flash_muzzle),
		"Attack.flash_muzzle must be connected to MuzzleSmoke._on_attack_flash_muzzle (wired in GunMesh.setup)")
	assert_not_null(smoke.get("inventory"),
		"GunMesh.setup must hand MuzzleSmoke the player's Inventory — without it the per-weapon muzzle_smoke_scale / has_muzzle_flash gate can never be read")


## Decal orientation: every splat in the game (bullet holes, blood drops, wound + gib splats, the death splat, the
## destroy scorch, paint) takes its basis from Projectile.decal_basis_for_normal, so these call THAT — never a local
## copy of the math, which is how an earlier version of these tests stayed green while production went left-handed.
## A left-handed basis (the cross product flipped) mirrors every stamp; on walls that was the original bug.
func _assert_decal_basis_stands_on(normal: Vector3, surface: String) -> void:
	var b := Projectile.decal_basis_for_normal(normal)
	assert_gt(b.determinant(), 0.0,
		surface + " decals must get a RIGHT-handed basis (determinant > 0) — a left-handed one mirrors the stamp")
	for axis in [b.x, b.y, b.z]:
		assert_almost_eq((axis as Vector3).length(), 1.0, 0.001,
			surface + " decal basis axes must be unit length — a scaled axis stretches the projected stamp")
	assert_almost_eq(b.x.dot(b.y), 0.0, 0.001, surface + " decal basis X and Y must be orthogonal (no shear)")
	assert_almost_eq(b.y.dot(b.z), 0.0, 0.001, surface + " decal basis Y and Z must be orthogonal (no shear)")
	assert_almost_eq(b.z.dot(b.x), 0.0, 0.001, surface + " decal basis Z and X must be orthogonal (no shear)")
	assert_almost_eq(b.y, normal, Vector3.ONE * 0.001,
		surface + " decal basis Y must BE the surface normal — a Decal projects along its -Y, into the surface")


func test_decal_basis_floor() -> void:
	_assert_decal_basis_stands_on(Vector3.UP, "Floor")


func test_decal_basis_ceiling() -> void:
	_assert_decal_basis_stands_on(Vector3.DOWN, "Ceiling")


func test_decal_basis_east_wall() -> void:
	_assert_decal_basis_stands_on(Vector3.RIGHT, "East-facing wall")


func test_decal_basis_north_wall() -> void:
	_assert_decal_basis_stands_on(Vector3.FORWARD, "North-facing wall")


func test_decal_basis_diagonal_slope() -> void:
	_assert_decal_basis_stands_on(Vector3(0.5, 0.5, 0.5).normalized(), "Diagonal slope")


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


## The trauma ONE nearby death at `distance` adds to a calm camera, read synchronously (ScreenShake decays it per frame).
func _death_trauma_at(player: Node, distance: float) -> float:
	var shake: ScreenShake = player.screen_shake
	shake.trauma = 0.0
	player.on_nearby_death(distance)
	return shake.trauma


func test_player_on_nearby_death_decays_with_distance() -> void:
	var player_scene := load("res://scenes/player/Player.tscn") as PackedScene
	var instance := player_scene.instantiate()
	add_child_autofree(instance)
	await wait_physics_frames(2)
	var shake_range: float = GameSettings.screen_shake.death_shake_range
	# Both in-range samples sit at or past the middle of the range, where the shipped death_shake_amount stays under
	# ScreenShake's trauma ceiling, so the falloff is compared on unclamped values and a flat full-strength shake
	# would read as two EQUAL (ceiling) values.
	var mid := _death_trauma_at(instance, shake_range * 0.5)
	var far := _death_trauma_at(instance, shake_range * 0.95)
	var edge := _death_trauma_at(instance, shake_range)
	var beyond := _death_trauma_at(instance, shake_range + 1.0)
	assert_gt(far, 0.0,
		"a death near the edge of death_shake_range must still shake the screen, just gently")
	assert_lt(far, mid,
		"the death shake must fall off with distance: a kill at 95%% of the range (%.3f) must shake less than one at half of it (%.3f)" % [far, mid])
	assert_almost_eq(edge, 0.0, 0.0001,
		"the falloff must reach nothing AT the range edge, so walking across it is not a visible jump in shake")
	assert_eq(beyond, 0.0,
		"beyond death_shake_range the screen must not shake at all")


func test_a_dying_character_tells_players_in_range_how_far_away_it_died() -> void:
	# Character.gore() -> _notify_nearby_players_of_death is how a kill reaches the camera: every Player-group node close
	# enough gets on_nearby_death(distance) (the blood splatter + death shake fall off with that distance), and a player
	# beyond both the splatter and the shake range hears nothing.
	var dying := _ConcreteCharacter.new()
	add_child_autofree(dying)
	dying.global_position = Vector3.ZERO
	var near_d: float = minf(GameSettings.effects.blood_splatter_range, GameSettings.screen_shake.death_shake_range) * 0.5
	var near := _DeathWitness.new()
	add_child_autofree(near)
	near.add_to_group(Groups.PLAYER)
	near.global_position = Vector3(near_d, 0.0, 0.0)
	var far := _DeathWitness.new()
	add_child_autofree(far)
	far.add_to_group(Groups.PLAYER)
	far.global_position = Vector3(0.0, 0.0, GameSettings.effects.blood_splatter_range + GameSettings.screen_shake.death_shake_range + 5.0)
	dying._notify_nearby_players_of_death()
	assert_eq(near.heard.size(), 1,
		"a player inside the splatter/shake range must be told about the death exactly once — otherwise no blood hits the lens and the camera never shakes")
	if near.heard.size() == 1:
		assert_almost_eq(near.heard[0], near_d, 0.001,
			"the player must be handed its real distance to the body, which the splatter and shake fall off with")
	assert_eq(far.heard.size(), 0,
		"a player beyond both the blood-splatter and death-shake ranges must not be told — a kill across the map must not shake your screen")


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


# ScreenShakeArea distance falloff pinned OFF-TREE via the pure shake_multiplier_for() — no Player + explosion
# scene boot. The kept in-tree test above (test_screen_shake_area_center_gives_max_shake) still proves
# _on_body_entered routes this multiplier into the player's ScreenShake, so pure + wiring together cover what the
# three scene-booting falloff tests used to.
const ScreenShakeAreaScript := preload("res://scripts/components/screen_shake_area.gd")


func test_shake_multiplier_is_max_at_center() -> void:
	assert_eq(ScreenShakeAreaScript.shake_multiplier_for(0.0, 5.0), 1.0,
		"at the dead centre (distance 0) the shake multiplier is full strength (1.0)")


func test_shake_multiplier_is_zero_at_edge() -> void:
	assert_almost_eq(ScreenShakeAreaScript.shake_multiplier_for(5.0, 5.0), 0.0, 0.0001,
		"at the sphere edge (distance == radius) the shake fades to 0.0")


func test_shake_multiplier_clamps_beyond_edge_and_bad_radius() -> void:
	assert_eq(ScreenShakeAreaScript.shake_multiplier_for(10.0, 5.0), 0.0,
		"past the edge the multiplier clamps at 0.0 (never negative)")
	assert_eq(ScreenShakeAreaScript.shake_multiplier_for(1.0, 0.0), 0.0,
		"a non-positive radius yields 0.0 — no shake, no divide-by-zero")


func test_shake_multiplier_falloff_is_monotonic() -> void:
	var near_mult := ScreenShakeAreaScript.shake_multiplier_for(5.0 * 0.25, 5.0)
	var far_mult := ScreenShakeAreaScript.shake_multiplier_for(5.0 * 0.75, 5.0)
	assert_gt(near_mult, far_mult,
		"near (25% of radius) must shake MORE than far (75% of radius) — the falloff decreases with distance")


## Spawn explosion_area.tscn in-tree with its radius (and, for `cosmetic`, the light-only spark setup: no push collider,
## no force, no damage) applied BEFORE it enters the tree, because _ready reads them once to size the flash.
func _spawn_explosion(radius: float, cosmetic: bool = false) -> Explosion:
	var blast: Explosion = (load("res://scenes/effects/explosion_area.tscn") as PackedScene).instantiate()
	blast.explosion_radius = radius
	if cosmetic:
		blast.collision_shape = null
		blast.max_explosion_force = 0.0
		blast.deals_damage = false
	add_child_autofree(blast)
	return blast


func test_explosion_light_reaches_the_blast_edge_from_ready() -> void:
	# REGRESSION: the flash light used to be sized only when a body entered the blast, so a rocket into empty air lit the
	# scene with whatever omni_range the prefab happened to be authored with. It is sized the moment the blast exists.
	var floor_r: float = GameSettings.effects.explosion_min_flash_radius
	var light: OmniLight3D = _spawn_explosion(floor_r * 2.0).get_node("OmniLight3D")
	assert_almost_eq(light.omni_range, floor_r * 2.0, 0.001,
		"a real blast's flash must light exactly as far as its explosion_radius, set in _ready before any body enters")
	assert_gt(light.light_energy, 0.0, "a real blast's flash must actually be lit")


func test_a_small_forceful_blast_is_floored_but_a_cosmetic_spark_stays_tiny() -> void:
	var floor_r: float = GameSettings.effects.explosion_min_flash_radius
	var small_light: OmniLight3D = _spawn_explosion(floor_r * 0.25).get_node("OmniLight3D")
	assert_almost_eq(small_light.omni_range, floor_r, 0.001,
		"a forceful blast smaller than explosion_min_flash_radius must still light out to that floor — a small grenade in a dark room has to read")
	var spark_r: float = GameSettings.effects.explosion_spark_radius
	assert_lt(spark_r, floor_r, "precondition: the hit-spark radius sits below the flash floor, or this control proves nothing")
	var spark_light: OmniLight3D = _spawn_explosion(spark_r, true).get_node("OmniLight3D")
	assert_gt(spark_light.omni_range, 0.0, "a cosmetic spark still flashes")
	assert_true(spark_light.omni_range <= spark_r,
		"a cosmetic hit spark / paint splat (no push, no force) must light only its own tiny radius (got %.2f m for a %.2f m spark) — flooring it floods the room on every bullet hit" % [spark_light.omni_range, spark_r])


func test_explosion_flash_brightness_scales_with_reach_and_honours_the_energy_knob() -> void:
	var floor_r: float = GameSettings.effects.explosion_min_flash_radius
	var small_light: OmniLight3D = _spawn_explosion(floor_r * 2.0).get_node("OmniLight3D")
	var big_light: OmniLight3D = _spawn_explosion(floor_r * 4.0).get_node("OmniLight3D")
	assert_gt(big_light.light_energy, small_light.light_energy, "a bigger blast must flash brighter")
	assert_almost_eq(big_light.light_energy / small_light.light_energy, big_light.omni_range / small_light.omni_range, 0.001,
		"flash brightness is authored PER METRE of reach (explosion_flash_energy_per_radius), so twice the reach must be twice the energy")
	_saved_flash_energy_per_radius = GameSettings.effects.explosion_flash_energy_per_radius
	GameSettings.effects.explosion_flash_energy_per_radius = _saved_flash_energy_per_radius * 2.0
	var retuned_light: OmniLight3D = _spawn_explosion(floor_r * 2.0).get_node("OmniLight3D")
	assert_almost_eq(retuned_light.light_energy, small_light.light_energy * 2.0, 0.01,
		"doubling explosion_flash_energy_per_radius must double the same blast's flash — it is the designer's live brightness dial")


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


func test_enemy_scene_signal_wiring_resolves_and_reaches_the_death_and_voice_handlers() -> void:
	# enemy.tscn AUTHORS its damaged/died connections (npc.gd's handlers + the Damage/Death voice nodes); none are made in
	# code. Scene connections exist right after instantiate(), so this reads them without running NPC._ready. Two ways it
	# breaks silently: a handler renamed away (every hit/death then logs an engine error and skips that reaction), and a
	# connection deleted in the Node dock (the enemy still dies, it just stops crediting the kill / crying out).
	var enemy: Character = ENEMY_SCENE.instantiate()
	for sig: StringName in [&"damaged", &"died"]:
		for conn: Dictionary in enemy.get_signal_connection_list(sig):
			var cb: Callable = conn["callable"]
			assert_true(cb.is_valid(),
				"enemy.tscn connects `%s` to %s, which no longer exists — every emit would error and skip that reaction" % [sig, cb])
	assert_true(enemy.died.is_connected(Callable(enemy, &"_on_died")),
		"enemy.tscn must connect died -> _on_died: kill quests, kill XP, witness barks and the death noise all run from it")
	var damage_node := enemy.get_node_or_null("Damage")
	assert_true(damage_node != null and enemy.damaged.is_connected(Callable(damage_node, &"_on_enemy_damaged")),
		"enemy.tscn must connect damaged -> Damage._on_enemy_damaged, or NPCs stop grunting when hit")
	var death_node := enemy.get_node_or_null("Death")
	assert_true(death_node != null and enemy.died.is_connected(Callable(death_node, &"_on_enemy_died")),
		"enemy.tscn must connect died -> Death._on_enemy_died, or NPCs die without their death cry")
	enemy.free()


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
# gating, and slide — the systems added in the latest pass.
# ---------------------------------------------------------------------------

func test_weapon_data_has_behaviour_toggles() -> void:
	for w in [PISTOL, SHOTGUN, SMG, ROCK_WEAPON]:
		assert_eq(typeof(w.auto_fire), TYPE_BOOL, "WeaponData.auto_fire must be a bool")
		assert_eq(typeof(w.has_muzzle_flash), TYPE_BOOL, "WeaponData.has_muzzle_flash must be a bool")
		assert_eq(typeof(w.has_laser_sight), TYPE_BOOL, "WeaponData.has_laser_sight must be a bool")
		assert_eq(typeof(w.spawns_casing), TYPE_BOOL, "WeaponData.spawns_casing must be a bool")
		assert_eq(typeof(w.attack_windup), TYPE_FLOAT, "WeaponData.attack_windup must be a float")


func test_melee_weapon_identity() -> void:
	assert_true(MELEE is WeaponData, "melee.tres must be a WeaponData resource")
	assert_false(MELEE.auto_fire, "Melee must be semi-auto (one swing per click)")
	# Melee no longer launches anything: the dash it used to carry (launch_on_scoped_attack / launch_force /
	# single_air_dash) moved wholesale onto the AirDash ability and its own key.
	assert_eq(MELEE.get(&"launch_on_scoped_attack"), null,
		"the scoped-attack launch is gone from WeaponData — a weapon must never fling the player again")
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


func test_scope_in_has_force_unscope() -> void:
	# Not add_child'd: ScopeIn._process dereferences `camera`, which is null on a bare
	# instance — has_method() works without entering the tree.
	var si := ScopeIn.new()
	assert_true(si.has_method("force_unscope"),
		"ScopeIn.force_unscope() is the hard ADS exit (death / holster / weapon swap use it)")
	si.free()


func test_slide_starts_only_on_a_fast_crouched_coasting_landing() -> void:
	# The Slide ability's trigger, driven off-tree (Player.landing calls try_start with the pre-move velocity). Each
	# refusal below is the SAME fast landing with exactly one condition taken away, and the final start is the control.
	var host := _SlideHost.new()
	var sl := Slide.new()
	sl.setup(host)
	var fast := Vector3(sl.slide_min_speed + 1.0, -6.0, 0.0)
	Input.action_press(&"Crouch")
	sl.try_start(Vector3(sl.slide_min_speed * 0.5, -6.0, 0.0))
	assert_false(sl.is_active(), "a crouched landing slower than slide_min_speed must not slide — a crouch-walk touchdown is not a slide")
	host.input_dir = Vector2(0.0, 1.0)
	sl.try_start(fast)
	assert_false(sl.is_active(), "holding a move key must not start a slide (steering would end it next frame and just click the sfx)")
	host.input_dir = Vector2.ZERO
	Input.action_release(&"Crouch")
	sl.try_start(fast)
	assert_false(sl.is_active(), "a fast landing WITHOUT crouch held must not slide")
	Input.action_press(&"Crouch")
	sl.slide_min_speed = fast.length() * 2.0
	sl.try_start(fast)
	assert_false(sl.is_active(), "slide_min_speed is the designer's live gate: raising it above the landing speed must refuse the slide")
	sl.slide_min_speed = fast.x - 1.0
	sl.try_start(fast)
	assert_true(sl.is_active(), "control: a fast landing with crouch held and no steering must start the slide")
	sl.free()
	host.free()


func test_post_process_shader_has_contrast_uniform() -> void:
	var content := _read_file("res://resources/shaders/post_process.gdshader")
	assert_true("uniform float contrast" in content,
		"post_process.gdshader must declare the contrast uniform driven by player.gd from Settings.contrast")


func test_contrast_setting_defaults_and_clamps() -> void:
	# A bare off-tree Settings instance never ran _ready, so _loaded stays false and save_settings()
	# early-returns — the clamp logic tests safely without touching the user's real settings.cfg.
	var s = load("res://managers/Settings.gd").new()
	assert_eq(s.contrast, 1.0, "contrast defaults to 1.0 — the authored look")
	s.set_contrast(99.0)
	assert_eq(s.contrast, s.CONTRAST_MAX, "contrast clamps to CONTRAST_MAX")
	s.set_contrast(0.0)
	assert_eq(s.contrast, s.CONTRAST_MIN, "contrast clamps to CONTRAST_MIN")
	s.free()


func test_post_process_shader_has_bayer_dither_uniforms() -> void:
	var content := _read_file("res://resources/shaders/post_process.gdshader")
	assert_true("uniform int bayer_order" in content,
		"post_process.gdshader must declare bayer_order (0 off / 1 2x2 / 2 4x4 / 3 8x8), authored per material in ui.tscn")
	assert_true("uniform float dither_strength" in content,
		"post_process.gdshader must declare dither_strength, driven by player.gd from Settings.dither_strength")
	assert_true("float bayer(ivec2" in content,
		"post_process.gdshader must carry the bayer() threshold function the dither reads its threshold from")


func test_post_process_dither_is_folded_into_one_quantisation() -> void:
	# ⭐ THE REGRESSION THIS PINS, and it shipped undetected for a long time: the shader used to posterize
	# FIRST (final_color = floor(c * steps + 0.5) / steps) and add the Bayer threshold in a SECOND pass
	# AFTER. That is a mathematical no-op — the second pass computes floor(k + d) for an already-integral k
	# and d < 1, which is k, every pixel, every colour, every matrix cell. The 4x4 table sitting above it
	# could not change a single output value.
	#
	# The invariant that keeps the dither alive is therefore structural, not cosmetic: there must be exactly
	# ONE quantisation, and the matrix must supply ITS threshold. Two of them means someone re-split the
	# steps and the dither is silently dead again — which no other test in this suite can see, because
	# headless never compiles shaders and no assertion can look at a dither pattern.
	var content := _read_file("res://resources/shaders/post_process.gdshader")
	assert_eq(content.count("floor(final_color * steps"), 1,
		"post_process.gdshader must quantise final_color EXACTLY ONCE — a second quantisation makes the Bayer dither a no-op")
	assert_true("mix(0.5, bayer(" in content,
		"the dither threshold must come from bayer() blended against 0.5 (round-to-nearest), so dither_strength 0 degenerates to a plain posterize")
	assert_false("d / steps" in content,
		"the dead post-posterize dither form (`+ d / steps` applied after quantising) must not come back — that is the no-op this replaced")


func test_the_shaders_own_bayer_recurrence_builds_a_true_dither_matrix() -> void:
	# Headless never compiles shaders, so this lifts the two lines of post_process.gdshader's bayer() that DEFINE the
	# matrix — the per-bit recurrence `v = ...;` and the `return` that turns v into a threshold — out of the shader text
	# and evaluates THEM with Expression over every cell. Only the loop around them (coordinate bits walked LOW to HIGH,
	# as the shader's own loop does) lives here, so an edit to either shader expression changes what is asserted.
	var body := _shader_function_body("res://resources/shaders/post_process.gdshader", "float bayer(ivec2")
	var step_expr := _regex_group(body, "\\n\\s*v\\s*=\\s*([^;]+);")
	var return_expr := _regex_group(body, "\\breturn\\s+([^;]+);")
	assert_ne(step_expr, "", "post_process.gdshader's bayer() must build its value with a `v = ...;` recurrence line")
	assert_ne(return_expr, "", "post_process.gdshader's bayer() must return a threshold")
	if step_expr == "" or return_expr == "":
		return
	assert_eq(_shader_bayer_cells(step_expr, 1), [0, 2, 3, 1],
		"order 1 must be the canonical 2x2 Bayer matrix")
	assert_eq(_shader_bayer_cells(step_expr, 2), [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5],
		"order 2 must reproduce the classic 4x4 table the shader used to spell out by hand")
	for order: int in [1, 2, 3]:
		var size := 1 << order
		var cells := _shader_bayer_cells(step_expr, order)
		var sorted_cells := cells.duplicate()
		sorted_cells.sort()
		assert_eq(sorted_cells, range(size * size),
			"order %d must use every threshold 0..%d exactly once — a duplicate or a gap biases the dither pattern" % [order, size * size - 1])
		var total := 0.0
		var all_inside := true
		for v: int in cells:
			var t: float = _eval_shader_expr(return_expr, ["v", "size"], [v, size])
			total += t
			all_inside = all_inside and t > 0.0 and t < 1.0
		assert_true(all_inside, "order %d thresholds must all sit strictly inside (0, 1)" % order)
		assert_almost_eq(total / float(size * size), 0.5, 0.000001,
			"order %d thresholds must average exactly 0.5 — any offset darkens or lightens every dithered frame" % order)


## The text of the shader function starting at `signature`, up to its closing brace at column 0 ("" when missing).
func _shader_function_body(path: String, signature: String) -> String:
	var src := _read_file(path)
	var start := src.find(signature)
	if start < 0:
		return ""
	var end := src.find("\n}", start)
	return src.substr(start, end - start) if end > start else ""


func _regex_group(text: String, pattern: String) -> String:
	var m := RegEx.create_from_string(pattern).search(text)
	return m.get_string(1).strip_edges() if m != null else ""


## Evaluate one GLSL expression lifted from the shader (int/float arithmetic, `^`, float() casts) with Expression.
func _eval_shader_expr(expr: String, names: Array, values: Array) -> Variant:
	var e := Expression.new()
	var err := e.parse(expr, PackedStringArray(names))
	assert_eq(err, OK, "the shader expression `%s` must evaluate as plain arithmetic: %s" % [expr, e.get_error_text()])
	if err != OK:
		return 0
	return e.execute(values)


## Row-major cells of the order-`order` matrix: the shader's loop (bit k of x and y, LOW to HIGH) around ITS `v = ...` line.
func _shader_bayer_cells(step_expr: String, order: int) -> Array:
	var size := 1 << order
	var cells := []
	for y in size:
		for x in size:
			var v := 0
			for k in order:
				v = int(_eval_shader_expr(step_expr, ["v", "xb", "yb"], [v, (x >> k) & 1, (y >> k) & 1]))
			cells.append(v)
	return cells


func test_dither_strength_setting_defaults_and_clamps() -> void:
	# Bare off-tree instance: _ready never ran, so _loaded stays false and save_settings() early-returns —
	# the clamp tests without touching the user's real settings.cfg (the contrast test's shape).
	var s = load("res://managers/Settings.gd").new()
	assert_eq(s.dither_strength, 1.0, "dither_strength defaults to 1.0 — the authored full-strength matrix")
	s.set_dither_strength(99.0)
	assert_eq(s.dither_strength, 1.0, "dither_strength clamps to 1.0")
	s.set_dither_strength(-5.0)
	assert_eq(s.dither_strength, 0.0, "dither_strength clamps to 0.0 (no dither = plain round-to-nearest banding)")
	s.free()
