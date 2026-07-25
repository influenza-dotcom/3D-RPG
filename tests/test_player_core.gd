extends GutTest

## GUT unit suite for the "Player core" subsystem: player.gd, head.gd, grapple_hook.gd,
## player_debug.gd. Every assert guards a load-bearing invariant and its message says WHY.
##
## WHAT THIS COVERS
##  - The inheritance contracts the controllers rely on (Player is Character/CharacterBody3D;
##    Head/GrappleHook/PlayerDebug are Node3D).
##  - Player's exported tuning defaults (slide/climb, ram/thump, noise), read straight off a
##    NON-add_child instance so no _ready/_enter_tree runs, plus the feedback feel DEFAULTS
##    (hurt/dash/respawn/death) — those moved off Player consts onto PlayerFeedbackSettings
##    (the designer-tunable single source of truth GameSettings.player_feedback reads), so the
##    pins assert a bare PlayerFeedbackSettings.new() resource instead.
##  - Player's plain-var initial state (current_speed, noise_radius, _dying/_climbing/_sliding).
##  - The method surface other systems call by name (combat/host hooks, weapon-host aim
##    overrides, inherited Character blast/gore/dust machinery) — has_method ONLY, never invoked.
##  - GrappleHook exported defaults + pure initial state + API surface + hit classification.
##  - Head's get-only camera/screen_shake getters returning null off-tree, + setup API surface.
##  - The "Grapple" input action binding the grapple gates all behaviour on.
##
## WHAT THIS DELIBERATELY SKIPS (and why)
##  - Building Player via add_child / Player.tscn.instantiate(): Player._enter_tree
##    unconditionally dereferences crouch/weapon_system/gun_mesh/coyote_time/bullet_time/
##    bunnyhop/mouse_input (all null on a bare instance) and calls head.setup() — it WILL crash
##    the runner. Full-scene behaviour (on_nearby_death trauma/freeze, scene structure) is
##    already covered in test_smoke.gd; we do not duplicate it.
##  - Calling ANY Player method: take_damage/die drive scene reload + global audio-bus / time-
##    scale side effects (hp defaults to 0.0 pre-_ready, so take_damage runs gore()->get_world_3d()
##    off-tree); _trigger_hurt/_set_hurt_amount/_setup_hurt_lpf mutate the global master bus.
##    We assert these exist, never run them.
##  - Head.setup()/_on_mouse_input_rotate, GrappleHook._ready/_try_attach/apply_pull/_update_rope,
##    PlayerDebug.reset()/_unhandled_input: all need a live tree/rig/Input or reload the scene.
##  - Player._physics_process and its slide/climb/ram/bounce/thump/noise/falling-air helpers:
##    require live Input + a full physics scene; their EXISTENCE is source-grepped in test_smoke.gd.
##
## CONSTRUCTION NOTE: export/const/has_method checks use `var n = load(path).new()` WITHOUT
## add_child so _ready/_enter_tree never run, then n.free(). assert_null is never used in this
## suite (matching test_smoke.gd) — null is asserted via assert_true(x == null, ...).

const PLAYER_SCRIPT_PATH := "res://scripts/player/player.gd"
const HEAD_SCRIPT_PATH := "res://scripts/player/head.gd"
const GRAPPLE_SCRIPT_PATH := "res://scripts/player/grapple_hook.gd"
const PLAYER_DEBUG_SCRIPT_PATH := "res://scripts/player/player_debug.gd"


# --- player.gd -------------------------------------------------------------

func test_player_extends_character_and_characterbody3d() -> void:
	# Build off-tree so _enter_tree/_ready (which deref many un-nullable exports) never run.
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_true(p is Character,
		"Player must extend Character — the whole controller relies on inheriting take_damage/gore/blast/dust")
	assert_true(p is CharacterBody3D,
		"Player must ultimately be a CharacterBody3D so move_and_slide / velocity drive movement")
	p.free()


func test_player_gravity_uses_fall_multiplier_only_while_descending() -> void:
	var content := FileAccess.get_file_as_string(PLAYER_SCRIPT_PATH)
	assert_true("func gravity(delta: float)" in content,
		"Player must override Character.gravity so player-only jump feel can differ from NPC gravity")
	assert_true("fall_gravity_mult" in content and "velocity.y < 0.0" in content,
		"Player.gravity must apply fall_gravity_mult only while descending so the jump rises normally and falls faster")


func test_player_slide_and_climb_export_defaults() -> void:
	# Slide + wall-climb are now drag-drop Ability NODES that own their tuning — assert the defaults THERE (they
	# match the values the Player used to carry, so a node added with no overrides behaves exactly as before).
	var wc := WallClimb.new()
	assert_eq(wc.ability_id(), &"wall_climb", "WallClimb grants the wall_climb mechanic")
	assert_eq(wc.wall_climb_speed, 4.5,
		"wall_climb_speed default 4.5 sets the vertical scale rate when holding jump into a wall")
	assert_eq(wc.wall_grip_stick, 2.0,
		"wall_grip_stick default 2.0 presses into the wall so contact (is_on_wall) holds while you hang")
	assert_eq(wc.climb_hop_up, 5.0,
		"climb_hop_up default 5.0 is the upward pop that clears the lip when you reach a ledge top")
	assert_eq(wc.climb_hop_forward, 3.5,
		"climb_hop_forward default 3.5 nudges you onto the ledge after the climb hop")
	wc.free()
	var sl := Slide.new()
	assert_eq(sl.ability_id(), &"slide", "Slide grants the slide mechanic")
	assert_eq(sl.slide_min_speed, 4.0,
		"slide_min_speed default 4.0 gates slides to fast landings, not a crouch-walk touchdown")
	assert_eq(sl.slide_friction, 4.0,
		"slide_friction default 4.0 (m/s per s) is how fast a slide bleeds off speed")
	assert_eq(sl.slide_end_speed, 2.5,
		"slide_end_speed default 2.5 ends the slide at ~crouch-walk pace")
	assert_eq(sl.slide_max_speed, 6.0,
		"slide_max_speed default 6.0 caps the slide's starting speed so fast bhop landings stay sane")
	assert_eq(sl.slide_boost, 1.0,
		"slide_boost default 1.0 means no extra kick at slide start (pure momentum carry)")
	assert_eq(sl.slide_jump_mult, 1.5,
		"slide_jump_mult default 1.5 scales the slide-jump launch by slide speed at jump time")
	assert_eq(sl.slide_dust_interval, 0.06,
		"slide_dust_interval default 0.06s paces the dust puffs kicked up while sliding")
	assert_eq(sl.slide_dust_intensity, 0.5,
		"slide_dust_intensity default 0.5 sizes each slide dust puff")
	sl.free()


func test_player_ram_and_thump_export_defaults() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	# Pinball rebound (ramming a surface fast bounces you back).
	assert_eq(p.ram_bounce_min_speed, 7.0,
		"ram_bounce_min_speed default 7.0 keeps only real rams (not walking) bouncing off surfaces")
	assert_eq(p.ram_bounce_factor, 0.2,
		"ram_bounce_factor default 0.2 is the rebound bounciness (1.0 would be fully elastic)")
	assert_eq(p.ram_bounce_cooldown, 0.15,
		"ram_bounce_cooldown default 0.15s stops bounce jitter against a single wall")
	assert_eq(p.ram_bounce_shake, 0.15,
		"ram_bounce_shake default 0.15 is the screen-shake punch on a bounce")
	# Air thump (loud impact when slamming into something mid-air).
	assert_eq(p.thump_min_speed_lost, 7.0,
		"thump_min_speed_lost default 7.0 requires a real frame-over-frame decel, not a glancing slide")
	assert_eq(p.thump_volume_db, 6.0,
		"thump_volume_db default 6.0 sets the air-thump loudness")
	assert_eq(p.thump_cooldown, 0.2,
		"thump_cooldown default 0.2s stops the thump machine-gunning on contact")
	p.free()


func test_player_noise_export_defaults() -> void:
	# These gate stealth: enemy Perception.can_hear() reads noise_radius, driven by these.
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_eq(p.noise_move_per_speed, 1.2,
		"noise_move_per_speed default 1.2 m of audible radius per m/s of ground speed drives footstep hearing")
	assert_eq(p.noise_gunfire_radius, 28.0,
		"noise_gunfire_radius default 28.0 m is how far a gunshot is heard before it decays")
	assert_eq(p.noise_gunfire_decay, 45.0,
		"noise_gunfire_decay default 45.0 m/s is how fast the gunshot noise radius shrinks back to silence")
	p.free()


func test_player_hurt_feedback_consts() -> void:
	# "Getting rocked" feel values — moved off Player consts onto the designer-tunable
	# PlayerFeedbackSettings resource (GameSettings.player_feedback reads it); pin the DEFAULTS
	# at that single source of truth. No hurt path is invoked. MASTER_BUS stays an engineering
	# const on the Player (HurtFeedback finds/adds the low-pass on it).
	var fb: PlayerFeedbackSettings = PlayerFeedbackSettings.new()
	assert_eq(fb.hurt_freeze_scale, 0.15,
		"hurt_freeze_scale 0.15 is the brutal slow-mo dip time_scale the instant you're hit")
	assert_eq(fb.hurt_freeze_hold, 0.12,
		"hurt_freeze_hold 0.12s is the real-time hold at the dip before easing back")
	assert_eq(fb.hurt_recovery, 0.55,
		"hurt_recovery 0.55s is the real-time ease back to normal (slow-mo + muffle + drain in lockstep)")
	assert_eq(fb.hurt_lpf_cutoff, 350.0,
		"hurt_lpf_cutoff 350 Hz is the muffled low-pass cutoff at full hurt")
	assert_eq(fb.hurt_lpf_clear, 20500.0,
		"hurt_lpf_clear 20500 Hz is the cutoff when clear (effectively no filtering)")
	assert_eq(fb.hurt_shake, 0.4,
		"hurt_shake 0.4 is the screen-shake punch the instant you're hit")
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_eq(p.MASTER_BUS, 0,
		"MASTER_BUS 0 is the bus the hurt low-pass muffle is added to / found on")
	p.free()
	assert_lt(fb.hurt_freeze_scale, 1.0,
		"hurt_freeze_scale must dip BELOW 1.0 — otherwise there's no slow-mo on a hit")
	assert_gt(fb.hurt_lpf_clear, fb.hurt_lpf_cutoff,
		"The muffle must sweep UPWARD (cutoff -> clear) to un-muffle; clear must exceed the hurt cutoff")
	fb = null


func test_player_misc_consts() -> void:
	# Dash-flash + respawn feel moved onto PlayerFeedbackSettings (designer-tunable defaults pinned
	# there); RAM_BOUNCE_FLOOR_DOT stays an engineering const on the Player.
	var fb: PlayerFeedbackSettings = PlayerFeedbackSettings.new()
	assert_eq(fb.dash_flash_peak_alpha, 0.5,
		"dash_flash_peak_alpha 0.5 is the white-flash opacity at the instant the air-dash recharges")
	assert_eq(fb.dash_flash_time, 0.18,
		"dash_flash_time 0.18s is the recharge flash fade-out duration")
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_eq(p.RAM_BOUNCE_FLOOR_DOT, 0.7,
		"RAM_BOUNCE_FLOOR_DOT 0.7 lets _check_bounce ignore floor-ish normals so fast landings don't pop you up")
	p.free()
	assert_eq(fb.respawn_delay, 1.0,
		"respawn_delay 1.0s is the visible death beat before the scene reloads")
	assert_lt(fb.dash_flash_peak_alpha, 1.0,
		"The recharge flash must not be fully opaque (0.5) — it's a cue, not a screen wipe")
	fb = null


func test_player_death_cinematic_consts() -> void:
	# Death-sequence feel values — defaults pinned on PlayerFeedbackSettings (the source GameSettings.
	# player_feedback reads); the cinematic itself is never invoked.
	var fb: PlayerFeedbackSettings = PlayerFeedbackSettings.new()
	assert_eq(fb.death_sequence_time, 1.6,
		"death_sequence_time 1.6s is the wall-clock keel-over/drain/fade before the post-death beat")
	assert_eq(fb.death_time_scale, 0.3,
		"death_time_scale 0.3 is the slow-mo the world eases into as the player dies")
	assert_lt(fb.death_time_scale, 1.0,
		"death_time_scale must be below 1.0 — death goes into slow-mo")
	assert_gt(fb.death_camera_roll, 0.0,
		"death_camera_roll must roll the camera onto its side (keeling over) by a positive angle")
	assert_eq(fb.death_message_fall, "You hit the ground at [mph] miles per hour.",
		"fall-damage deaths have their own death-card line with an mph token")
	fb = null
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_eq(p._death_cam_base_z, 0.0,
		"_death_cam_base_z starts at 0 — it's captured at the instant death begins")
	p.free()


func test_fall_damage_mph_rounds_for_death_card() -> void:
	assert_eq(FallDamage.mph(20.0), 45,
		"20 m/s impact speed should read as 45 mph on the fall-death card")
	assert_eq(FallDamage.mph(-1.0), 0,
		"fall speed display clamps negative inputs to zero")


func test_player_heartbeat_uses_real_asset_on_any_damage() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_eq(p.heartbeat_start_frac, 1.0,
		"heartbeat_start_frac 1.0 means the heartbeat starts as soon as the player takes ANY damage")
	var hb: AudioStream = p.heartbeat_sound
	assert_not_null(hb, "heartbeat_sound must be assigned (the real heartbeat asset)")
	if hb:
		assert_true(hb.resource_path.ends_with("heartbeat.mp3"),
			"heartbeat_sound must point at the dedicated heartbeat.mp3 asset, not the placeholder thud")
	p.free()


func test_player_health_light_color_tracks_hp_fraction() -> void:
	var full_blue := Color(0.003921569, 1.0, 1.0, 1.0)
	var hurt_red := Color(1.0, 0.05, 0.02, 1.0)
	assert_eq(Player.health_light_color_for(100.0, 100.0, full_blue, hurt_red), full_blue,
		"at full HP, the player light must keep the scene-authored blue shade")
	assert_eq(Player.health_light_color_for(0.0, 100.0, full_blue, hurt_red), hurt_red,
		"at 0 HP, the player light must reach the configured hurt red")
	var half := Player.health_light_color_for(50.0, 100.0, full_blue, hurt_red)
	assert_gt(half.r, full_blue.r,
		"damage should raise the red channel above the full-health blue")
	assert_lt(half.g, full_blue.g,
		"damage should pull green down from the full-health blue")
	assert_lt(half.b, full_blue.b,
		"damage should pull blue down from the full-health blue")
	assert_gt(half.r, half.g,
		"by half HP, the player light should read more red than cyan")


func test_player_per_frame_readouts_are_off_tree_safe() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	var wind := AudioStreamPlayer.new()
	var hud := PlayerHud.new()
	var ui := UI.new()
	wind.stream = AudioStreamGenerator.new()
	p.falling_air_sfx = wind
	p.velocity = Vector3(0.0, GameSettings.audio.falling_air_max_fall_speed + 1.0, 0.0)
	p._update_falling_air(0.016)
	assert_false(wind.playing,
		"detached FallingAirSFX must not try to play before it enters the SceneTree")
	p._hud = hud
	p.ui = ui
	p._update_stealth_hud(0.2)
	p._update_crosshair()
	p._check_aim_remark(0.2)
	p._remark_reckless_fire()
	assert_true(true,
		"per-frame readouts must no-op off-tree before asking the SceneTree/Viewport for world state")
	ui.free()
	hud.free()
	wind.free()
	p.free()


func test_player_toast_and_sneak_api() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_true(p.has_method("notify_toast"),
		"Player must expose notify_toast — the HUD toast entry for sneak/cripple feedback")
	assert_true(p.has_method("show_holster_forgiveness_tutorial"),
		"Player must expose show_holster_forgiveness_tutorial for NPC aggro lessons")
	assert_true(p.has_method("notify_sneak_result"),
		"Player must expose notify_sneak_result — the sneak-attack-or-not toast on a player hit")
	# All safe to call off-tree (no UI built): they must no-op, not crash.
	p.notify_sneak_result(true)
	p.notify_sneak_result(false)
	p._on_head_crippled(null)  # also asserts the new attacker-arg signature is callable
	assert_true(true, "notify_sneak_result / _on_head_crippled must be safe with no UI")
	p.free()


func test_holster_forgiveness_tutorial_text_formats_reload_binding() -> void:
	assert_eq(PlayerText.holster_forgiveness_tutorial("R"),
		"[PH] You provoked them. Hold [R] to holster your weapon and ask for forgiveness.",
		"the holster-forgiveness tutorial names the current Reload binding")


func test_player_look_target_api() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_true(p.has_method("on_look_target_changed"),
		"Player must expose on_look_target_changed — the look-at hover readout driver")
	p.on_look_target_changed(null)  # safe off-tree (no UI built -> no-op clear)
	assert_true(true, "on_look_target_changed(null) must be safe with no UI")
	p.free()


func test_player_drop_item_api() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_true(p.has_method("drop_item"),
		"Player must expose drop_item — the inventory's Drop button calls it")
	# Safe off-tree: inventory is null pre-_ready, so drop_item must early-return, not crash.
	p.drop_item(null, 1)
	assert_true(true, "drop_item must be safe with no backpack / off-tree")
	# A non-weapon item (ammo) now drops as a Throwable (carry/throw with Z) carrying a CanPickUp child (E
	# stashes it) — the SAME throwable behavior as a dropped weapon, just showing a placeholder box instead
	# of a view model. (A weapon drop is covered by test_weapon_drop_has_pickup_hitbox — instancing a real
	# view_model here would pull its asset.)
	var ammo: Item = ItemDb.ammo_item_for(&"pistol")
	var drop = WorldItem.build(ammo, 3)
	assert_true(drop is Throwable,
		"a non-weapon drop is a Throwable so it can be carried/thrown like a dropped weapon")
	var cp: CanPickUp = null
	for c in drop.get_children():
		if c is CanPickUp:
			cp = c
	assert_not_null(cp,
		"the box drop carries a CanPickUp child so E takes it into the inventory")
	if cp != null:
		assert_eq(cp.item, ammo,
			"the pickup carries the dropped item")
		assert_eq(cp.amount, 3,
			"the pickup carries the dropped count")
		var cp_has_shape := false
		for c in cp.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
				cp_has_shape = true
		assert_true(cp_has_shape,
			"the box drop's CanPickUp has its own hitbox, so the look-at ray picks E (stash) over Z (throw)")
	drop.free()
	p.free()


func test_weapon_drop_has_pickup_hitbox() -> void:
	# A dropped weapon is a Throwable carrying a CanPickUp; that CanPickUp MUST have its OWN collision
	# shape on the talk layer, or the look-at ray can't see it and E grabs the weapon instead of stashing.
	var p = load(PLAYER_SCRIPT_PATH).new()
	var w := WeaponData.new()
	var packed := PackedScene.new()
	var proto := Node3D.new()
	packed.pack(proto)
	proto.free()
	w.view_model = packed
	var it := Item.new()
	it.category = Item.Category.WEAPON
	it.weapon = w
	var drop = WorldItem.build(it, 1)
	assert_true(drop is Throwable,
		"a dropped weapon is a Throwable so it can be carried/thrown")
	var cp: CanPickUp = null
	for c in drop.get_children():
		if c is CanPickUp:
			cp = c
	assert_not_null(cp,
		"the dropped weapon carries a CanPickUp for E -> inventory")
	var has_shape := false
	for c in cp.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			has_shape = true
	assert_true(has_shape,
		"the CanPickUp must have a collision shape, or the look-at ray can't see it and E grabs instead of stashing")
	drop.free()
	p.free()
	w = null
	it = null


func test_make_world_renderable_resets_gun_layer() -> void:
	# A dropped weapon's view-model meshes must move off the FP gun layer (4) to the world layer (1), so the
	# WORLD camera depth-tests them against geometry instead of the gun camera drawing them through walls.
	var p = load(PLAYER_SCRIPT_PATH).new()
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.layers = 4  # the FP view-model render layer (drawn on top by the dedicated gun camera)
	root.add_child(mi)
	WorldItem._make_world_renderable(root)
	assert_eq(mi.layers, 1,
		"a dropped weapon renders on the world layer so it's occluded by walls, not drawn over them")
	root.free()
	p.free()


func test_player_plain_var_initial_defaults() -> void:
	# Field initializers (var ... = literal), set at construction, NOT in _ready — safe pre-_ready.
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_eq(p.current_speed, 0.0,
		"current_speed must start at 0.0 — the movement lerp ramps it up from rest")
	assert_eq(p.noise_radius, 0.0,
		"noise_radius must start at 0.0 (silent) so a freshly spawned player isn't 'heard' before moving")
	assert_false(p._dying,
		"_dying must start false so the first take_damage isn't swallowed by the death guard")
	# Climb/slide state moved onto the WallClimb / Slide ability nodes; a bare player has neither node, so the
	# public gates read false (is_climbing/is_sliding null-guard the missing ability).
	assert_false(p.is_climbing(),
		"is_climbing() must start false — no WallClimb ability on a bare player, and it's set only while scaling a wall")
	assert_false(p.is_sliding(),
		"is_sliding() must start false — no Slide ability on a bare player, and a slide begins only on a fast crouched landing")
	assert_false(p.is_grappling(),
		"is_grappling() must start false — no Grapple ability on a bare player, so stamina recovery treats it as idle")
	p.free()


func test_player_stamina_spend_and_drain_helpers() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_almost_eq(p.stamina, GameSettings.player_movement.max_stamina, 0.001,
		"stamina starts full from the movement tuning resource")
	var sheet := CharacterStats.new()
	sheet.endurance = 2
	p.stats = sheet
	p.stamina = p.stamina_max()
	assert_almost_eq(p.stamina_max(), GameSettings.player_movement.max_stamina + 20.0, 0.001,
		"endurance increases the player's max stamina")
	assert_almost_eq(p.stamina, p.stamina_max(), 0.001,
		"setting stamina to stamina_max fills the endurance-boosted pool")
	assert_almost_eq(p.stamina_fraction(), 1.0, 0.001,
		"full stamina reports a full HUD fraction")
	assert_true(p.spend_stamina(10.0),
		"spend_stamina succeeds when enough stamina is available")
	assert_almost_eq(p.stamina, p.stamina_max() - 10.0, 0.001,
		"spend_stamina subtracts the requested one-time cost")
	p.stamina = 5.0
	assert_true(p.drain_stamina(2.0, 1.0),
		"drain_stamina succeeds while some stamina remains")
	assert_almost_eq(p.stamina, 3.0, 0.001,
		"drain_stamina subtracts rate * delta")
	assert_true(p.spend_stamina(10.0),
		"spend_stamina allows a Dark-Souls-style overdraw when any stamina remains")
	assert_almost_eq(p.stamina, -7.0, 0.001,
		"one-time stamina costs can push the internal pool below zero")
	assert_eq(p.stamina_fraction(), 0.0,
		"negative stamina still renders as an empty HUD bar")
	assert_false(p.spend_stamina(1.0),
		"spend_stamina refuses new costs while the pool is already empty or in debt")
	p.stamina = 5.0
	assert_false(p.drain_stamina(100.0, 1.0),
		"drain_stamina returns false when the ongoing drain exhausts the pool")
	assert_almost_eq(p.stamina, -95.0, 0.001,
		"ongoing drains can overdraw on the final tick before the ability stops")
	sheet = null
	p.free()


func test_sprint_stamina_lockout_blocks_partial_recharge() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	p.stamina = 1.0
	assert_false(p._drain_sprint_stamina(1.0),
		"sprint drain returns false on the tick that empties the stamina bar")
	assert_almost_eq(p._sprint_lockout_left, GameSettings.player_movement.stamina_sprint_lockout, 0.001,
		"emptying stamina from sprint starts the full sprint lockout")
	p.stamina = p.stamina_max() * 0.5
	assert_false(p.can_sprint(),
		"partial stamina recharge must not allow sprint during the lockout")
	p._update_sprint_lockout(GameSettings.player_movement.stamina_sprint_lockout - 0.01)
	assert_false(p.can_sprint(),
		"sprint stays locked until the full configured duration has elapsed")
	p._update_sprint_lockout(0.01)
	assert_true(p.can_sprint(),
		"sprint becomes available after the full lockout once stamina has partially recharged")
	p.free()


func test_player_exposes_current_sprint_state_for_camera_fov() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_true(p.has_method(&"is_sprinting"),
		"Player must expose the active sprint state so CameraEffects can widen FOV only during real sprint")
	var src := FileAccess.get_file_as_string(PLAYER_SCRIPT_PATH)
	assert_true(src.contains("return can_sprint() and _wants_sprint(input_dir)"),
		"is_sprinting() must share the same stamina/input/floor gates as sprint drain")
	p.free()


func test_player_jump_path_spends_stamina() -> void:
	var src := FileAccess.get_file_as_string(PLAYER_SCRIPT_PATH)
	assert_true(src.contains("spend_stamina(GameSettings.player_movement.stamina_jump_cost)"),
		"the buffered/coyote jump launch path must spend the configured stamina_jump_cost")


func test_player_apply_velocity_runs_step_assist() -> void:
	var src := FileAccess.get_file_as_string(PLAYER_SCRIPT_PATH)
	assert_true(src.contains("func apply_velocity()"),
		"Player must override Character.apply_velocity so the player controller can add stair step assist")
	assert_true(src.contains("_can_use_step_assist(walk_velocity)"),
		"Player stair assist must not run on upward launch frames, or moving jumps get snapped back to the floor")
	assert_true(src.contains("_step_assist_launch_block_timer"),
		"Player stair assist must ignore the immediate scoped melee launch window")
	assert_true(src.contains("STEP_MAX_BLAST_TO_WALK_RATIO"),
		"Player stair assist must allow small attack shove while blocking blast-dominated motion")
	assert_true(src.contains("_try_step_up(start_transform, walk_velocity"),
		"Player.apply_velocity must probe stair assist from the grounded start pose before relying on slide collisions")
	assert_true(src.contains("Locomotor.compute_step_up(self, start_transform"),
		"Player stair assist must DELEGATE the riser-climb kinematics to the shared Locomotor core (angled riser-aware probes live there), not a duplicated inline copy")
	assert_true(src.contains("Locomotor.compute_step_down(self,"),
		"Player descending-tread snap must delegate to the shared Locomotor core too, so one algorithm serves player + NPC")
	assert_true(src.contains("_try_step_down(walk_velocity)"),
		"Player.apply_velocity must snap down after walking off a stair tread while grounded")
	assert_true(src.contains("GameSettings.player_movement.step_up_height"),
		"Player stair assist must read the designer-tunable step_up_height")


func test_player_step_assist_blocks_live_blast_impulse() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	var walk_speed := GameSettings.player_movement.max_speed
	p.input_dir = Vector2(0.0, -1.0)
	p.explosion_velocity = Vector3.ZERO
	assert_true(p._can_use_step_assist(Vector3(walk_speed, 0.0, 0.0)),
		"ordinary controlled walking can use stair assist")
	p.explosion_velocity = Vector3(2.5, 0.0, 0.0)
	assert_true(p._can_use_step_assist(Vector3(walk_speed, 0.0, 0.0)),
		"a normal melee shove can ride along while the player is really walking")
	p._step_assist_launch_block_timer = 0.2
	assert_false(p._can_use_step_assist(Vector3(walk_speed, 0.0, 0.0)),
		"the immediate scoped hammer launch window must not be treated as stair-walking")
	p._step_assist_launch_block_timer = 0.0
	p.explosion_velocity = Vector3(8.0, 0.0, 0.0)
	assert_false(p._can_use_step_assist(Vector3(GameSettings.player_movement.step_min_horizontal_speed + 0.2, 0.0, 0.0)),
		"blast-dominated horizontal motion still skips stair assist")
	p.input_dir = Vector2.ZERO
	p.explosion_velocity = Vector3(2.5, 0.0, 0.0)
	assert_false(p._can_use_step_assist(Vector3(walk_speed, 0.0, 0.0)),
		"attack shove without movement input is still not stair intent")
	p.explosion_velocity = Vector3.ZERO
	assert_false(p._can_use_step_assist(Vector3(walk_speed, 1.0, 0.0)),
		"upward launch frames still skip stair assist")
	assert_false(p._can_use_step_assist(Vector3(GameSettings.player_movement.step_min_horizontal_speed * 0.5, 0.0, 0.0)),
		"tiny drift below the stair-assist threshold stays inert")
	p.free()


func test_player_combat_and_host_api_exists() -> void:
	# has_method ONLY — these all run real side effects (gore/get_world_3d/scene reload/tween).
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_true(p.has_method("take_damage"),
		"Player.take_damage must exist — the attacker hitscan and Character damage path call it")
	assert_true(p.has_method("die"),
		"Player.die must exist — the death/respawn flow depends on it")
	assert_true(p.has_method("on_nearby_death"),
		"Player.on_nearby_death must exist — Character.gore() notifies nearby players through it")
	assert_true(p.has_method("indicate_damage_from"),
		"Player.indicate_damage_from must exist — attack.gd flashes a directional damage arc via it")
	assert_true(p.has_method("on_dealt_hit"),
		"Player.on_dealt_hit must exist — a landed shot/explosion flashes the hitmarker through it")
	assert_true(p.has_method("get_hit_flash"),
		"Player.get_hit_flash must exist — gore/hit FX fetch the white-flash sprite through it")
	p.free()


func test_player_weapon_host_aim_overrides_exist() -> void:
	# The hosted Weapon reads these so hitscan + spread match the crosshair ray.
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_true(p.has_method("get_aim_origin"),
		"Player.get_aim_origin must override Character's so the hosted Weapon fires from the camera ray")
	assert_true(p.has_method("get_aim_direction"),
		"Player.get_aim_direction must override Character's so hitscan goes where the crosshair points")
	assert_true(p.has_method("get_aim_basis"),
		"Player.get_aim_basis must exist so weapon spread is oriented to the camera basis")
	assert_true(p.has_method("on_weapon_fired"),
		"Player.on_weapon_fired must exist — it applies screen-shake and the gunfire noise spike")
	assert_true(p.has_method("on_weapon_launched"),
		"Player.on_weapon_launched must exist — it applies the launch shake + FOV punch")
	p.free()


func test_player_inherits_character_surface() -> void:
	# Confirms Player still inherits the blast/gore/dust machinery it calls in _physics_process.
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_true(p.has_method("spawn_dust"),
		"Player must inherit Character.spawn_dust — jump/land/slide dust is spawned through it")
	assert_true(p.has_method("heal"),
		"Player must inherit Character.heal — health pickups restore HP through it")
	assert_true(p.has_method("apply_blast"),
		"Player must inherit Character.apply_blast — _physics_process applies the decaying blast impulse via it")
	assert_true(p.has_method("apply_velocity"),
		"Player must inherit Character.apply_velocity — the move-and-slide wrapper it calls each frame")
	assert_true(p.has_method("killed_by_only_crits"),
		"Player must inherit Character.killed_by_only_crits — the crit-only death rule queries it")
	p.free()


func test_player_is_climbing_false_on_fresh_instance() -> void:
	# is_climbing() reads the WallClimb ability node (_wall_climb != null and _wall_climb.is_climbing()). A bare
	# off-tree player ran no _ready, so it has no WallClimb child -> the null-guard returns false safely.
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_false(p.is_climbing(),
		"is_climbing() must be false on a fresh player — no WallClimb ability, so the null-guard short-circuits")
	p.free()


func test_player_is_crouching_tracks_crouch_t() -> void:
	# is_crouching() (read by Talkable.start_talk to gate pickpocketing) just reads crouch.crouch_t past a
	# 0.5 threshold — pure, no tree/Input. Build the Crouch off-tree and set crouch_t directly (its _ready
	# wires the head/collision rig, so we never run it).
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_false(p.is_crouching(),
		"no crouch component yet -> not crouching (off-tree / pre-_ready safe, so stealth checks never crash)")
	var c = load("res://scripts/player/crouch.gd").new()
	p.crouch = c
	assert_false(p.is_crouching(),
		"standing (crouch_t 0.0) is not crouching")
	c.crouch_t = 0.8
	assert_true(p.is_crouching(),
		"past the 0.5 threshold counts as crouched — pickpocketing is allowed")
	c.crouch_t = 0.4
	assert_false(p.is_crouching(),
		"below the 0.5 threshold (still easing down/up) is not yet crouched")
	c.free()
	p.free()


func test_player_seconds_since_combat_zero_right_after_note() -> void:
	# note_combat() stamps Time.get_ticks_msec(); seconds_since_combat() returns elapsed seconds
	# since that stamp. Right after stamping it must be ~0 — assert a small UPPER bound (tolerant,
	# never an exact float), since a few real ms may elapse between the two calls.
	var p = load(PLAYER_SCRIPT_PATH).new()
	p.note_combat()
	assert_lt(p.seconds_since_combat(), 0.5,
		"seconds_since_combat() must be ~0 immediately after note_combat() stamps the combat time")
	p.free()


# --- head.gd ---------------------------------------------------------------

func test_head_extends_node3d() -> void:
	# Head has no _ready, so .new() is safe; keep it off-tree to avoid wiring the rig.
	var h = load(HEAD_SCRIPT_PATH).new()
	assert_true(h is Node3D,
		"Head must extend Node3D — it is the camera-rig root and owns the look-pitch rotation")
	h.free()


func test_head_camera_and_screen_shake_null_off_tree() -> void:
	# camera/screen_shake are get-only properties using get_node_or_null, so off-tree they
	# resolve to null. assert_true(x == null, ...) — the suite never uses assert_null.
	var h = load(HEAD_SCRIPT_PATH).new()
	assert_true(h.camera == null,
		"Head.camera getter must return null off-tree (get_node_or_null finds no Camera3D child yet)")
	assert_true(h.screen_shake == null,
		"Head.screen_shake getter must return null off-tree (get_node_or_null finds no ScreenShake child yet)")
	h.free()


func test_head_setup_api_exists() -> void:
	# has_method ONLY: setup() derefs mouse_input.rotate.connect, and _on_mouse_input_rotate
	# reads GameSettings + mutates rotation — calling either off-rig would crash.
	var h = load(HEAD_SCRIPT_PATH).new()
	assert_true(h.has_method("setup"),
		"Head.setup must exist — the host injects the player + MouseInput into the rig through it")
	assert_true(h.has_method("_on_mouse_input_rotate"),
		"Head._on_mouse_input_rotate must exist — it's the pitch-look handler reconnected in setup()")
	h.free()


# --- grapple_hook.gd -------------------------------------------------------

func test_grapple_hook_extends_node3d_and_export_defaults() -> void:
	# Build WITHOUT add_child so _ready (which reads InputMap + add_childs a rope mesh) never runs.
	var g = load(GRAPPLE_SCRIPT_PATH).new()
	assert_true(g is Node3D,
		"GrappleHook must extend Node3D — it lives under the player and draws the rope mesh")
	assert_eq(g.max_range, 30.0,
		"max_range default 30.0 m is how far the grapple ray reaches for an anchor/target")
	assert_eq(g.swing_assist, 15.0,
		"swing_assist default 15.0 is the tangential WASD push that pumps a tether swing")
	assert_eq(g.reel_speed, 2.0,
		"reel_speed default 2.0 is the climb-toward-anchor rate when holding jump on a tether")
	assert_eq(g.min_rope_length, 2.0,
		"min_rope_length default 2.0 m is the closest you can reel in on a tether")
	assert_eq(g.yank_speed, 14.0,
		"yank_speed default 14.0 is the top reel-in speed of a grabbed body in YANK mode")
	assert_eq(g.yank_accel, 80.0,
		"yank_accel default 80.0 is how hard a yanked body accelerates toward you")
	assert_eq(g.reach_distance, 2.0,
		"reach_distance default 2.0 m is when a yank releases because the body has arrived")
	assert_eq(g.rope_color, Color(1.0, 1.0, 1.0, 1.0),
		"rope_color default is white (the rope material's untinted base)")
	g.free()


func test_grapple_hook_initial_state_and_api() -> void:
	var g = load(GRAPPLE_SCRIPT_PATH).new()
	# is_attached() just returns _attached (var _attached = false) — pure, no tree access.
	assert_false(g.is_attached(),
		"GrappleHook must start detached so no pull is applied before you fire it")
	assert_false(g.is_active(),
		"GrappleHook must start inactive so stamina recovery is idle before the rope is fired")
	assert_true(g.has_method("setup"),
		"GrappleHook.setup must exist — the host wires the body, camera (aim) and muzzle (rope origin) through it")
	assert_true(g.has_method("apply_pull"),
		"GrappleHook.apply_pull must exist — player.gd's _physics_process applies the tether/yank pull via it")
	assert_true(g.has_method("detach"),
		"GrappleHook.detach must exist — releasing the grapple action calls it to drop the rope")
	assert_true(g.has_method("is_attached"),
		"GrappleHook.is_attached must exist for state queries")
	assert_true(g.has_method("is_active"),
		"GrappleHook.is_active must exist so stamina recovery can detect a fired or retracting rope")
	g.free()


func test_grapple_hook_pending_hit_yanks_throwables() -> void:
	var g = load(GRAPPLE_SCRIPT_PATH).new()
	var t := Throwable.new()
	g._set_pending_hit(t)
	assert_eq(g.get("_pending_mode"), GrappleHook.Mode.YANK,
		"Throwable hits must enter YANK mode so releasing the grapple can fling the prop")
	assert_eq(g.get("_pending_yanked"), t,
		"The yanked target must be the Throwable itself")
	assert_eq(g.get("_pending_throwable"), t,
		"The grapple tracks the Throwable for self-damage grace while attached")
	t.free()
	g.free()


func test_grapple_hook_pending_hit_tethers_plain_world_nodes() -> void:
	var g = load(GRAPPLE_SCRIPT_PATH).new()
	var world := Node3D.new()
	g._set_pending_hit(world)
	assert_eq(g.get("_pending_mode"), GrappleHook.Mode.TETHER,
		"Plain world hits stay tether anchors; only enemies and Throwable props are yanked")
	assert_true(g.get("_pending_yanked") == null,
		"A tether hit must not carry a yanked target")
	assert_true(g.get("_pending_throwable") == null,
		"A plain world hit is not tracked as a Throwable")
	world.free()
	g.free()


func test_grapple_action_bound() -> void:
	# _process/_ready gate ALL grapple behaviour on InputMap.has_action(&"Grapple").
	# Verified registered in project.godot [input] (bound to G) — mirrors test_night_vision_action_bound.
	assert_true(InputMap.has_action("Grapple"),
		"The Grapple action must exist in the input map (bound to G) or the grapple never arms")


# --- player_debug.gd -------------------------------------------------------

func test_player_debug_extends_node3d_and_reset_api() -> void:
	# PlayerDebug has no _ready, so .new() is safe; never call reset() (it reloads the scene).
	var d = load(PLAYER_DEBUG_SCRIPT_PATH).new()
	assert_true(d is Node3D,
		"PlayerDebug must extend Node3D so it can sit in the scene and catch the ui_end action")
	assert_true(d.has_method("reset"),
		"PlayerDebug.reset must exist — the End-key dev reload routes to it")
	d.free()
