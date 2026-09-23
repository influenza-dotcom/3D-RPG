extends GutTest

## GUT unit suite for the "Player core" subsystem: player.gd (with its StaminaManager / NoiseEmitter components),
## head.gd, grapple_hook.gd, player_debug.gd, and the Slide / WallClimb ability nodes. Tests drive real production
## code wherever the engine allows it, and each assert message says what breaks for the player. The has_method /
## inheritance pins that remain cover methods other systems reach BY NAME whose bodies can't run off-tree
## (take_damage, die, setup, ...) — the surface CLAUDE.md sanctions for a Player that never runs _ready.
##
## HOW THE PLAYER IS DRIVEN WITHOUT ITS _ready
##  - A bare `load(PLAYER_SCRIPT_PATH).new()` is NEVER added to the tree (CLAUDE.md): _enter_tree dereferences a
##    dozen scene-wired nodes and _ready instantiates the weapon rig. Pure statics, component forwarders and the
##    off-tree-safe helpers (stamina, regen, heartbeat beat, step-assist predicate, death settlement, readouts,
##    the fall-death card) are called on that bare instance directly. hp/max_hp are written RAW — never
##    take_damage() off-tree, which reaches gore() -> get_world_3d() and the master bus.
##  - get_gravity() needs the body inside a physics space: the bare body is placed straight into the viewport's
##    space through PhysicsServer3D (no lifecycle callback runs) and taken out again before it is freed.
##  - is_on_floor() is never true for a body that has not run move_and_slide in-tree, so the sprint read is driven
##    through the Player's OWN StaminaManager re-pointed at a small Character stand-in (_TestBody) standing on a
##    real test floor.
##  - Slide / WallClimb type their host as a plain Node, so they run against _AbilityHost, which exposes exactly
##    the host surface they read.
##  - GrappleHook stays off-tree; its player and the yanked body are parked _TestBody stand-ins (physics off).
##
## WHAT STAYS A SOURCE-SCOPED PIN (and why)
##  Player._physics_process and Player.apply_velocity can never run here (the first needs the scene-wired
##  components; the second early-returns off-tree via _has_live_physics_space). The ORDER of their beats — the
##  jump's stamina gate, the stair assist around move_and_slide, the regen beat ahead of the low-HP feedback, and
##  the airborne arm — is pinned by scans scoped to that one function body. Everything those beats CALL is driven
##  for real, here or in test_air_movement.gd.
##
## Globals a test touches (Input actions, CutscenePlayer._active, DialogueManager._active,
## Settings.heartbeat_enabled, GameSettings knobs) are snapshotted in before_each and restored in after_each.
## assert_null is never used (matching test_smoke.gd) — null is asserted via assert_true(x == null, ...).

const PLAYER_SCRIPT_PATH := "res://scripts/player/player.gd"
const STAMINA_SCRIPT_PATH := "res://scripts/player/stamina_manager.gd"
const HEAD_SCRIPT_PATH := "res://scripts/player/head.gd"
const GRAPPLE_SCRIPT_PATH := "res://scripts/player/grapple_hook.gd"
const PLAYER_DEBUG_SCRIPT_PATH := "res://scripts/player/player_debug.gd"
## The shipped Player prefab: read through its SceneState only (never instantiated — that would run _ready).
const PLAYER_SCENE_PATH := "res://scenes/player/Player.tscn"
const GRAPPLE_DEFAULT_CONFIG_PATH := "res://resources/abilities/grapple_default.tres"

## Test floors and parked bodies live far from the origin so no other suite's bodies share their broadphase.
const TEST_FLOOR_ORIGIN := Vector3(4000.0, 0.0, 0.0)
const PARKED_BODY_ORIGIN := Vector3(-4000.0, 0.0, 0.0)

var _saved_cutscene_active: bool
var _saved_dialogue: DialogueResource
var _saved_heartbeat_enabled: bool
var _saved_fall_gravity_mult: float
var _saved_allow_sprint_while_scoped: bool
var _saved_combat_calm_grace: float


## A concrete Character (the base is @abstract) carrying the Player-script surface StaminaManager reads
## dynamically (input_dir / _is_scoped / the climb-slide-grapple triple). Character._ready is side-effect-safe on a
## mesh-less stub (test_character.gd's _Stub precedent); physics processing is switched off right after it enters
## the tree, so nothing moves it but the test.
class _TestBody extends Character:
	var input_dir := Vector2.ZERO
	var _is_scoped := false
	func is_climbing() -> bool:
		return false
	func is_sliding() -> bool:
		return false
	func is_grappling() -> bool:
		return false


## Duck-typed Ability host: exactly the Player surface Slide and WallClimb read (their `host` is typed Node, so every
## access is dynamic). A Node3D so WallClimb's ledge hop can read global_position once it is in the tree; it doubles
## as its own camera_effects sink for the climb bob.
class _AbilityHost extends Node3D:
	var velocity := Vector3.ZERO
	var explosion_velocity := Vector3.ZERO
	var current_speed := 0.0
	var input_dir := Vector2.ZERO
	var on_floor := true
	var on_wall := false
	var wall_normal := Vector3.BACK
	var camera_effects: Object = null
	var jump_sound: AudioStream = null
	var jump_sound_volume_db := 0.0
	var dust_puffs := 0
	func _init() -> void:
		camera_effects = self
	func is_on_floor() -> bool:
		return on_floor
	func is_on_wall() -> bool:
		return on_wall
	func get_wall_normal() -> Vector3:
		return wall_normal
	func is_encumbered() -> bool:
		return false
	func spawn_dust(_intensity: float = 1.0) -> void:
		dust_puffs += 1
	func bob(_velocity: Vector3) -> void:
		pass


func before_each() -> void:
	_saved_cutscene_active = CutscenePlayer._active
	_saved_dialogue = DialogueManager._active
	_saved_heartbeat_enabled = Settings.heartbeat_enabled
	_saved_fall_gravity_mult = GameSettings.player_movement.fall_gravity_mult
	_saved_allow_sprint_while_scoped = GameSettings.weapon_general.allow_sprint_while_scoped
	_saved_combat_calm_grace = GameSettings.player_feedback.combat_calm_grace


func after_each() -> void:
	CutscenePlayer._active = _saved_cutscene_active
	DialogueManager._active = _saved_dialogue
	Settings.heartbeat_enabled = _saved_heartbeat_enabled
	GameSettings.player_movement.fall_gravity_mult = _saved_fall_gravity_mult
	GameSettings.weapon_general.allow_sprint_while_scoped = _saved_allow_sprint_while_scoped
	GameSettings.player_feedback.combat_calm_grace = _saved_combat_calm_grace
	Input.action_release(&"Crouch")
	Input.action_release(&"jump")
	Input.action_release(InputManager.action_run)


## A _TestBody in the tree at `at`, physics processing off (Character._physics_process would apply gravity and slide it).
func _parked_body(at: Vector3) -> _TestBody:
	var body := _TestBody.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	body.add_child(shape)
	body.position = at
	add_child_autofree(body)
	body.set_physics_process(false)
	return body


## A _TestBody standing on a real static slab at `at`: two physics steps so the slab is in the broadphase, then one
## downward move_and_slide, which is the only thing that ever sets is_on_floor().
func _grounded_body(at: Vector3) -> _TestBody:
	var slab := StaticBody3D.new()
	var slab_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 1.0, 10.0)
	slab_shape.shape = box
	slab.add_child(slab_shape)
	slab.position = at + Vector3(0.0, -0.5, 0.0)
	add_child_autofree(slab)
	var body := _parked_body(at + Vector3(0.0, 1.02, 0.0))
	await wait_physics_frames(2)
	body.velocity = Vector3(0.0, -2.0, 0.0)
	body.move_and_slide()
	return body


## The text of ONE player.gd function, from its header to the next top-level `func` ("" when the header is gone),
## so a scan cannot be satisfied by a declaration or a comment somewhere else in the 4,000-line file.
func _player_func_body(header: String) -> String:
	var src := FileAccess.get_file_as_string(PLAYER_SCRIPT_PATH).replace("\r\n", "\n")
	var at := src.find(header)
	if at < 0:
		return ""
	var end := src.find("\nfunc ", at + header.length())
	return src.substr(at) if end < 0 else src.substr(at, end - at)


## The value Player.tscn authors for one of the ROOT Player node's properties, read from the PackedScene's
## SceneState so no Player is instantiated (null when the scene leaves that property at the script default).
func _shipped_player_property(prop: StringName) -> Variant:
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	if packed == null:
		return null
	var state := packed.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == prop:
			return state.get_node_property_value(0, i)
	return null


# --- player.gd -------------------------------------------------------------

func test_player_extends_character_and_characterbody3d() -> void:
	# Build off-tree so _enter_tree/_ready (which deref many un-nullable exports) never run.
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_true(p is Character,
		"Player must extend Character — the whole controller relies on inheriting take_damage/gore/blast/dust")
	assert_true(p is CharacterBody3D,
		"Player must ultimately be a CharacterBody3D so move_and_slide / velocity drive movement")
	p.free()


## Player.gravity() is the player-only jump feel: plain gravity on the way up, fall_gravity_mult on the way down.
## It reads get_gravity(), so the bare body is dropped into the viewport's physics space (see the header).
func test_player_gravity_falls_faster_than_it_rises() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	PhysicsServer3D.body_set_space(p.get_rid(), get_viewport().find_world_3d().space)
	await wait_physics_frames(3)  # the space resolves the body's total gravity on its next steps
	var pull: float = -p.get_gravity().y
	assert_gt(pull, 0.0, "precondition: the test space pulls the body down")
	var mult: float = GameSettings.player_movement.fall_gravity_mult
	const DT := 0.1
	p.velocity = Vector3(0.0, 1.0, 0.0)
	p.gravity(DT)
	var rising_dv: float = 1.0 - p.velocity.y
	p.velocity = Vector3(0.0, -1.0, 0.0)
	p.gravity(DT)
	var falling_dv: float = -1.0 - p.velocity.y
	assert_almost_eq(rising_dv, pull * DT, 0.001,
		"on the way UP the player feels plain gravity — the jump's apex height is authored against it")
	assert_almost_eq(falling_dv, pull * DT * mult, 0.001,
		"on the way DOWN gravity is scaled by fall_gravity_mult, so a jump rises normally and drops snappily")
	GameSettings.player_movement.fall_gravity_mult = -2.0
	p.velocity = Vector3(0.0, -1.0, 0.0)
	p.gravity(DT)
	assert_almost_eq(p.velocity.y, -1.0, 0.001,
		"a mis-authored NEGATIVE fall_gravity_mult clamps to 0 — it may remove the pull, never fling a falling player back UP")
	PhysicsServer3D.body_set_space(p.get_rid(), RID())
	p.free()


# --- Slide / WallClimb ability nodes (the slide + climb tuning lives on them) ---

func test_slide_starts_only_on_a_fast_hands_off_crouched_landing_and_caps_its_launch() -> void:
	var host := _AbilityHost.new()
	var sl := Slide.new()
	assert_eq(sl.ability_id(), &"slide",
		"Slide grants the slide mechanic — has_mechanic and the save's unlock list key on this id")
	sl.host = host
	Input.action_press(&"Crouch")
	sl.try_start(Vector3(sl.slide_min_speed * 0.9, 0.0, 0.0))
	assert_false(sl.is_active(),
		"a crouched landing under slide_min_speed is a crouch-walk touchdown, not a slide")
	# Twice as fast as the cap allows, falling hard: only the HORIZONTAL speed seeds the slide.
	var fast := Vector3(0.0, -8.0, -2.0 * sl.slide_max_speed / maxf(sl.slide_boost, 0.1))
	host.input_dir = Vector2(0.0, -1.0)
	sl.try_start(fast)
	assert_false(sl.is_active(),
		"holding a move key never STARTS a slide — steering would end it next frame and just click the wind sfx")
	host.input_dir = Vector2.ZERO
	Input.action_release(&"Crouch")
	sl.try_start(fast)
	assert_false(sl.is_active(), "no crouch held, no slide")
	Input.action_press(&"Crouch")
	sl.try_start(fast)
	assert_true(sl.is_active(), "a fast, hands-off, crouched landing starts the slide")
	assert_true(sl.jump_launch(), "jumping out of a live slide consumes it as a slide-jump")
	assert_false(sl.is_active(), "the slide-jump ends the slide")
	assert_almost_eq(host.explosion_velocity.length(), sl.slide_max_speed * sl.slide_jump_mult, 0.001,
		"the launch is slide speed x slide_jump_mult with the speed CAPPED at slide_max_speed — a too-fast bhop landing must not fling you twice as far")
	assert_true(host.explosion_velocity.normalized().is_equal_approx(Vector3(0.0, 0.0, -1.0)),
		"the slide-jump flings you along the landing's horizontal direction")
	var kick: Vector3 = host.explosion_velocity
	assert_false(sl.jump_launch(), "a plain jump with no live slide is not a slide-jump")
	assert_eq(host.explosion_velocity, kick, "...and adds no launch impulse")
	sl.free()
	host.free()


func test_slide_bleeds_speed_at_its_friction_and_ends_at_crouch_walk_pace() -> void:
	var host := _AbilityHost.new()
	var sl := Slide.new()
	sl.host = host
	assert_lt(sl.slide_end_speed, sl.slide_min_speed,
		"a slide must end BELOW the speed that starts one, or every slide would end on the frame it began")
	assert_true(sl.slide_min_speed <= sl.slide_max_speed,
		"the starting-speed cap must not sit under the start threshold, or a qualifying landing seeds a slide slower than the one it just qualified for")
	const DT := 0.05
	Input.action_press(&"Crouch")
	sl.try_start(Vector3(0.0, 0.0, sl.slide_max_speed))
	assert_true(sl.is_active(), "precondition: a landing at slide_max_speed starts a slide")
	sl.update_movement(DT, Vector3.ZERO)
	var first: float = host.current_speed
	sl.update_movement(DT, Vector3.ZERO)
	assert_almost_eq(first - host.current_speed, sl.slide_friction * DT, 0.0001,
		"the slide bleeds slide_friction m/s every second")
	assert_almost_eq(Vector2(host.velocity.x, host.velocity.z).length(), host.current_speed, 0.0001,
		"the slide REPLACES ground control: the body's horizontal velocity is the slide speed")
	assert_gt(host.velocity.z, 0.0, "...along the direction the slide started in")
	assert_gt(host.dust_puffs, 0, "sliding kicks up dust")
	var frames := 0
	while sl.is_active() and frames < 1000:
		sl.update_movement(DT, Vector3.ZERO)
		frames += 1
	assert_false(sl.is_active(), "a hands-off slide must end on its own")
	assert_true(host.current_speed <= sl.slide_end_speed + 0.0001,
		"the slide ends once it has decayed to slide_end_speed")
	assert_gt(host.current_speed, sl.slide_end_speed - sl.slide_friction * DT - 0.0001,
		"...on the first step under it, so you come out at crouch-walk pace instead of bleeding to a dead stop")
	sl.try_start(Vector3(0.0, 0.0, sl.slide_max_speed))
	sl.update_movement(DT, Vector3(1.0, 0.0, 0.0))
	assert_false(sl.is_active(), "steering input ends a slide so control returns to the player")
	sl.try_start(Vector3(0.0, 0.0, sl.slide_max_speed))
	host.on_floor = false
	sl.update_movement(DT, Vector3.ZERO)
	assert_false(sl.is_active(), "leaving the ground ends a slide")
	sl.free()
	host.free()


func test_wall_climb_grips_climbs_descends_hangs_and_hops_the_ledge() -> void:
	var host := _AbilityHost.new()
	add_child_autofree(host)  # the ledge hop reads host.global_position
	var wc := WallClimb.new()
	assert_eq(wc.ability_id(), &"wall_climb",
		"WallClimb grants the wall_climb mechanic — has_mechanic and the save's unlock list key on this id")
	wc.host = host
	const DT := 1.0 / 60.0
	var into_wall := Vector3(0.0, 0.0, -1.0)
	host.on_wall = true
	host.wall_normal = Vector3(0.0, 0.0, 1.0)
	Input.action_press(&"jump")
	host.input_dir = Vector2(1.0, 0.0)
	host.velocity = Vector3(3.0, -2.0, 0.0)
	wc.tick(DT, Vector3(1.0, 0.0, 0.0))
	assert_false(wc.is_climbing(), "strafing along a wall with jump held must not stick you to it — a grip starts only by pushing in")
	assert_eq(host.velocity, Vector3(3.0, -2.0, 0.0), "...and a brushed wall leaves your motion alone")
	host.input_dir = Vector2(0.0, -1.0)
	host.velocity = Vector3(1.0, -3.0, 2.0)  # drifting OFF the wall (+z is its outward normal)
	wc.tick(DT, into_wall)
	assert_true(wc.is_climbing(), "W into a wall with jump held grips it")
	assert_almost_eq(host.velocity.y, wc.wall_climb_speed, 0.0001, "pushing in climbs at wall_climb_speed")
	assert_almost_eq(host.velocity.z, -wc.wall_grip_stick, 0.0001,
		"the outward drift is cancelled and the grip presses in by wall_grip_stick, so wall contact holds while you climb")
	assert_almost_eq(host.velocity.x, 1.0, 0.0001, "movement along the wall's face is untouched")
	host.input_dir = Vector2(0.0, 1.0)
	wc.tick(DT, -into_wall)
	assert_true(wc.is_climbing(), "an established grip holds while you back off the wall")
	assert_almost_eq(host.velocity.y, -wc.wall_climb_speed, 0.0001, "holding S climbs DOWN at wall_climb_speed")
	host.input_dir = Vector2.ZERO
	wc.tick(DT, Vector3.ZERO)
	assert_true(wc.is_climbing(), "letting go of the stick keeps the grip")
	assert_almost_eq(host.velocity.y, 0.0, 0.0001, "an idle grip hangs in place instead of sliding down")
	host.on_wall = false
	host.velocity = Vector3(0.0, 1.0, 0.0)
	wc.tick(DT, into_wall)
	assert_false(wc.is_climbing(), "past the lip there is no wall left to grip")
	assert_almost_eq(host.velocity.y, wc.climb_hop_up, 0.0001, "climbing clean off the top pops you up by climb_hop_up")
	assert_almost_eq(host.velocity.z, -wc.climb_hop_forward, 0.0001, "...and nudges you onto the ledge by climb_hop_forward")
	wc.enabled = false
	host.on_wall = true
	host.input_dir = Vector2(0.0, -1.0)
	host.velocity = Vector3.ZERO
	wc.tick(DT, into_wall)
	assert_false(wc.is_climbing(), "a disabled WallClimb (implant switched off) never grips")
	assert_eq(host.velocity, Vector3.ZERO, "...and never writes the body's velocity")
	wc.free()


# --- Player tuning bounds ---

func test_player_ram_bounce_and_air_thump_tuning_keep_their_design_bounds() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	var launched_run: float = GameSettings.player_movement.max_speed * (1.0 + GameSettings.player_movement.jump_momentum_boost)
	assert_gt(p.ram_bounce_min_speed, launched_run,
		"only real rams bounce: a full run, even carried into a momentum-boosted jump, must stay under ram_bounce_min_speed, or jogging into a wall pinballs you off it")
	assert_gt(p.ram_bounce_factor, 0.0, "a qualifying ram must actually rebound you")
	assert_true(p.ram_bounce_factor <= 1.0,
		"ram_bounce_factor above 1.0 hands back MORE speed than the ram carried in — every wall becomes a free launcher")
	assert_gt(p.ram_bounce_cooldown, 0.0, "a zero bounce cooldown lets one wall re-fire the bounce every frame (jitter)")
	assert_true(p.ram_bounce_shake > 0.0 and p.ram_bounce_shake <= ScreenShake.MAX_TRAUMA,
		"the bounce punch must shake the camera, and above ScreenShake.MAX_TRAUMA the extra is clamped away")
	assert_gt(p.thump_min_speed_lost, 0.0, "at 0 every mid-air graze would count as an impact and thump")
	assert_gt(p.thump_cooldown, 0.0, "a zero thump cooldown machine-guns the sound on one slam")
	# The pinball check skips floor-ish normals (normal.y > RAM_BOUNCE_FLOOR_DOT) so fast landings don't pop you up.
	assert_gt(cos(p.floor_max_angle), p.RAM_BOUNCE_FLOOR_DOT,
		"every slope the player can STAND on must count as floor for the bounce, or a fast landing on a walkable ramp pops you back into the air")
	assert_gt(p.RAM_BOUNCE_FLOOR_DOT, 0.0,
		"a vertical wall (normal.y 0) must NOT be treated as floor, or ramming a wall never bounces")
	p.free()


## NoiseEmitter drives Player.noise_radius (what enemy hearing reads) from the Player's own noise_gunfire_* knobs.
func test_player_gunshot_is_heard_at_its_radius_then_fades_to_silence() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	var e := NoiseEmitter.new()
	e.host = p
	const DT := 1.0 / 60.0
	e.gunfire()
	e.tick(DT)
	var shot: float = p.noise_radius
	assert_almost_eq(shot, p.noise_gunfire_radius, p.noise_gunfire_decay * DT + 0.001,
		"the frame a shot is fired it carries its full noise_gunfire_radius, less one frame of decay")
	for i in 10:
		e.tick(DT)
	assert_lt(p.noise_radius, shot, "the gunshot's noise shrinks back over time at noise_gunfire_decay")
	var elapsed := 0.0
	while p.noise_radius > 0.0 and elapsed < 30.0:
		e.tick(DT)
		elapsed += DT
	assert_eq(p.noise_radius, 0.0,
		"a gunshot must fade to exact silence — never ring on for guards long after the shot, never go negative")
	e.free()
	p.free()


func test_player_feedback_bounds_that_make_each_cue_read() -> void:
	# The PlayerFeedbackSettings relations test_managers_tuning.gd deliberately leaves to this file (it pins the
	# > 0 floors); asserted on the class defaults GameSettings.player_feedback is authored from.
	var fb: PlayerFeedbackSettings = PlayerFeedbackSettings.new()
	assert_lt(fb.hurt_freeze_scale, 1.0,
		"hurt_freeze_scale must dip BELOW 1.0 — otherwise there's no slow-mo on a hit")
	assert_gt(fb.hurt_lpf_clear, fb.hurt_lpf_cutoff,
		"The muffle must sweep UPWARD (cutoff -> clear) to un-muffle; clear must exceed the hurt cutoff")
	assert_gte(fb.hurt_lpf_clear, 20000.0,
		"the CLEAR cutoff must sit at or above the ~20 kHz top of human hearing, or a recovered player still hears the whole mix faintly muffled")
	assert_true(fb.hurt_shake > 0.0 and fb.hurt_shake <= ScreenShake.MAX_TRAUMA,
		"a hit must punch the camera, and a punch above ScreenShake.MAX_TRAUMA is clamped away")
	assert_lt(fb.dash_flash_peak_alpha, 1.0,
		"The recharge flash must not be fully opaque — it's a cue, not a screen wipe")
	assert_lt(fb.death_time_scale, 1.0,
		"death_time_scale must be below 1.0 — death goes into slow-mo")
	assert_gt(fb.death_camera_roll, 0.0,
		"death_camera_roll must roll the camera onto its side (keeling over) by a positive angle")
	fb = null
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_eq(AudioServer.get_bus_name(p.MASTER_BUS), "Master",
		"the hurt low-pass is added to MASTER_BUS, which must be the Master bus so the muffle covers music, SFX and voices alike")
	p.free()


func test_shipped_fall_death_card_names_the_impact_speed() -> void:
	assert_true(PlayerFeedbackSettings.new().death_message_fall.contains("[mph]"),
		"the default fall-death line carries the [mph] token, so a fresh resource still reports the impact speed")
	var p = load(PLAYER_SCRIPT_PATH).new()
	var line: String = p._compose_fall_death_message(20.0)
	assert_ne(line, "", "fall-damage deaths have their own death-card line — blank falls back to the generic card")
	assert_true(line.contains("45"), "the shipped line must report a 20 m/s impact as 45 mph")
	assert_false(line.contains("[mph]"), "a player must never read a raw [mph] token on the death card")
	p.free()


func test_fall_damage_mph_rounds_for_death_card() -> void:
	assert_eq(FallDamage.mph(20.0), 45,
		"20 m/s impact speed should read as 45 mph on the fall-death card")
	assert_eq(FallDamage.mph(-1.0), 0,
		"fall speed display clamps negative inputs to zero")


## The fall-death card composer: reads only GameSettings.player_feedback + the pure FallDamage.mph (no tree, no
## global side effects). [mph] is THE token; a legacy
## %d/%s/%f still substitutes; substitution is replace()-based so a designer's literal '%' never raises the
## `%` operator's "unsupported format character" error. Mutates the shared autoload resource, so it restores
## the authored line before exiting (GUT asserts never abort the test, so the restore always runs).
func test_fall_death_message_substitution_is_percent_safe() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	var fb = GameSettings.player_feedback
	var saved: String = fb.death_message_fall
	fb.death_message_fall = "Hit at [mph] mph."
	assert_eq(p._compose_fall_death_message(20.0), "Hit at 45 mph.",
		"[mph] substitutes the rounded impact speed")
	fb.death_message_fall = "100% dead at %d mph"
	assert_eq(p._compose_fall_death_message(20.0), "100% dead at 45 mph",
		"a legacy %d beside a literal percent substitutes via replace() — the old % operator path errored here")
	fb.death_message_fall = saved
	p.free()


## The heartbeat ramp the beat code needs (_update_low_hp lerps slow->fast and min->max dB by how far HP sits below
## the threshold), on the script defaults AND on the threshold the shipped Player.tscn authors over them.
func test_player_heartbeat_uses_real_asset_and_ramps_toward_death() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_true(p.heartbeat_start_frac > 0.0 and p.heartbeat_start_frac <= 1.0,
		"the heartbeat threshold is an HP fraction; 0 disables it and above 1 would beat at full health")
	var shipped_frac: Variant = _shipped_player_property(&"heartbeat_start_frac")
	if shipped_frac != null:
		assert_true(float(shipped_frac) > 0.0 and float(shipped_frac) <= 1.0,
			"Player.tscn's heartbeat threshold must be an HP fraction in (0, 1]: 0 silences the shipped heartbeat, above 1 beats at full health")
	assert_lt(p.heartbeat_interval_fast, p.heartbeat_interval_slow,
		"the beat must QUICKEN as HP falls (heartbeat_interval_fast shorter than heartbeat_interval_slow)")
	assert_lt(p.heartbeat_db_min, p.heartbeat_db_max,
		"the beat must get LOUDER as HP falls (heartbeat_db_min quieter than heartbeat_db_max)")
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
	assert_true(p._stealth_hud_snap.is_empty(),
		"off-tree the stealth HUD must bail before the full-NPC awareness scan (it would ask a null SceneTree for the npc group)")
	p._update_crosshair()
	p._aim_remark_timer = 0.3
	p._check_aim_remark(0.2)
	assert_almost_eq(p._aim_remark_timer, 0.3, 0.0001,
		"off-tree the aim remark must bail before touching its timer or casting a ray into a null World3D")
	p._remark_reckless_fire()  # reaches get_tree() only in-tree; any engine error here fails the test
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
	# Off-tree there is no UI, so the toast itself no-ops — but the cooldown bookkeeping in front of it is real.
	var never: int = p._last_sneak_toast_msec
	p.notify_sneak_result(false)
	assert_eq(p._last_sneak_toast_msec, never,
		"a normal (non-sneak) hit says nothing, so it must not start the sneak-toast cooldown either")
	p.notify_sneak_result(true)
	var shown: int = p._last_sneak_toast_msec
	assert_gt(shown, never, "a sneak hit shows its toast and starts the cooldown")
	# Back-date the stamp instead of firing twice in a row: two calls in the same millisecond can't tell a
	# throttled call from an ungated re-stamp (both leave the same value). Half a window back must hold; a full
	# window back must let the next sneak hit toast again.
	var cooldown: int = GameSettings.player_feedback.sneak_toast_cooldown_ms
	assert_gt(cooldown, 1, "precondition: the shipped sneak toast has a real cooldown window")
	var inside_window: int = Time.get_ticks_msec() - int(cooldown * 0.5)
	p._last_sneak_toast_msec = inside_window
	p.notify_sneak_result(true)
	assert_eq(p._last_sneak_toast_msec, inside_window,
		"a second sneak result inside sneak_toast_cooldown_ms is throttled — a multi-pellet sneak shot shows ONE line")
	var expired: int = Time.get_ticks_msec() - cooldown - 1
	p._last_sneak_toast_msec = expired
	p.notify_sneak_result(true)
	assert_gt(p._last_sneak_toast_msec, expired,
		"control: once sneak_toast_cooldown_ms has elapsed the next sneak hit toasts (and re-stamps) again")
	p._on_head_crippled(null)  # the attacker-arg signature must stay callable with no UI (an engine error fails the test)
	p.free()


## Duck-typed hostile-NPC killer for the death-settlement banking test — the two methods
## HostilityHelpers.death_settles_grudges probes on whoever killed the player.
class _SettlingKiller extends Node:
	func is_hostile() -> bool:
		return true
	func stand_down_on_player_death() -> bool:
		return false


func test_death_settlement_is_judged_at_death_and_spent_on_the_respawn() -> void:
	# The two halves of the provoked-grudge settlement. Character calls _on_killed_by on EVERY lethal path
	# (take_damage + _die_from_continuous_fall); it only BANKS a verdict, because the killer can die or be leashed
	# home during the seconds of death cinematic. _respawn_at_checkpoint (and the pre-reload death modes) then spend
	# that verdict exactly once, standing every still-provoked NPC back down where the player can see it happen.
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_true(p.has_method("_on_killed_by"),
		"Player must override _on_killed_by — Character calls it BY NAME on every lethal path, so a rename silently drops the death settlement")
	var killer := _SettlingKiller.new()
	add_child_autofree(killer)
	p._on_killed_by(null)
	assert_false(p._death_settlement_pending,
		"a fall / hazard / self-inflicted death banks nothing — nobody won that fight")
	p._on_killed_by(killer)
	assert_true(p._death_settlement_pending,
		"dying to a hostile NPC banks the verdict at DEATH, while the killer is still guaranteed live")
	p._on_killed_by(null)
	assert_true(p._death_settlement_pending,
		"a non-hostile re-death (a fall inside the revive's quiet window) must not ERASE a verdict still waiting to be spent")
	# Off-tree the sweep has no SceneTree to reach the &"npc" group through, so it must spend the verdict and bail
	# rather than dereference a null tree (any engine error fails the test).
	p._settle_provoked_grudges()
	assert_false(p._death_settlement_pending,
		"the respawn spends the verdict, so a later revive can't settle the same death's grudges twice")
	p.free()


func test_holster_forgiveness_tutorial_text_formats_reload_binding() -> void:
	# The tutorial teaches a KEY, so whatever the player has the action bound to has to reach the sentence, and no
	# raw {key} token may be left on screen. Two unlike bindings (a stock key, a rebound mouse button) show the text
	# follows its argument instead of a baked-in default; the wording around the key is copy, deliberately unpinned.
	for binding: String in ["R", "Mouse Button 5"]:
		var text := PlayerText.holster_forgiveness_tutorial(binding)
		assert_true(text.contains(binding),
			"the holster-forgiveness tutorial names the binding it was given ('%s'), got: %s" % [binding, text])
		assert_false(text.contains("{key}"),
			"the binding token is substituted, never shown raw (binding '%s'), got: %s" % [binding, text])
		assert_gt(text.length(), binding.length(),
			"the tutorial is a sentence around the key, not the bare binding (binding '%s')" % binding)


func test_player_look_target_api() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_true(p.has_method("on_look_target_changed"),
		"Player must expose on_look_target_changed — the interaction ray (ray_cast.gd) calls it by name to drive the look-at readout")
	p.on_look_target_changed(null)  # safe off-tree (no UI built -> no-op clear); an engine error fails the test
	p.free()


func test_player_drop_item_api() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_true(p.has_method("drop_item"),
		"Player must expose drop_item — the inventory's Drop button calls it")
	# Safe off-tree: inventory is null pre-_ready, so drop_item must early-return (an engine error fails the test).
	p.drop_item(null, 1)
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


func test_movement_state_reads_forward_to_the_ability_nodes_and_null_guard_a_bare_player() -> void:
	# Climb / slide / grapple state lives on the WallClimb / Slide / Grapple ability nodes, which a Player only holds
	# once _register_ability has found them. A player without one (a bare instance here; in play, an ability never
	# granted) must read false through the null guard rather than error.
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_false(p.is_climbing(),
		"is_climbing() reads false with no WallClimb ability — it is set only while scaling a wall")
	assert_false(p.is_sliding(),
		"is_sliding() reads false with no Slide ability — a slide begins only on a fast crouched landing")
	assert_false(p.is_grappling(),
		"is_grappling() reads false with no Grapple ability, so stamina recovery treats the rope as idle")
	assert_false(p.is_grapple_attached(),
		"is_grapple_attached() reads false with no Grapple ability, so AirMovement never stands down for a rope that isn't there")
	# Control: the SAME player handed live ability nodes reads their state, so the falses above come from the missing
	# nodes, not from gates that always answer false.
	var host := _AbilityHost.new()
	add_child_autofree(host)
	var sl := Slide.new()
	sl.host = host
	Input.action_press(&"Crouch")  # released in after_each
	sl.try_start(Vector3(0.0, 0.0, sl.slide_max_speed))
	assert_true(sl.is_active(), "premise: a fast, hands-off, crouched landing started the slide")
	p._slide = sl
	assert_true(p.is_sliding(), "a player whose Slide ability is mid-slide reads as sliding")
	var wc := WallClimb.new()
	wc.host = host
	host.on_wall = true
	host.wall_normal = Vector3(0.0, 0.0, 1.0)
	host.input_dir = Vector2(0.0, -1.0)
	Input.action_press(&"jump")  # released in after_each
	wc.tick(1.0 / 60.0, Vector3(0.0, 0.0, -1.0))
	assert_true(wc.is_climbing(), "premise: W into a wall with jump held gripped it")
	p._wall_climb = wc
	assert_true(p.is_climbing(), "a player whose WallClimb ability is gripping a wall reads as climbing")
	# The grapple's two senses: a RETRACTING hook is still busy (the wide is_grappling that stamina recovery and step
	# assist stand down on) but no longer attached (the narrow gate AirMovement stands down on).
	var gr := Grapple.new()
	var hook := GrappleHook.new()
	gr._hook = hook
	p._grapple_ability = gr
	hook._state = GrappleHook.State.RETRACTING
	assert_true(p.is_grappling(), "a retracting hook still reads as grappling (fired, attached OR retracting)")
	assert_false(p.is_grapple_attached(),
		"a retracting hook is NOT attached — air control must not stay stood down for a rope on its way home")
	hook._state = GrappleHook.State.ATTACHED
	assert_true(p.is_grapple_attached(), "an attached rope reads as attached")
	assert_true(p.is_grappling(), "...and as grappling")
	p._slide = null
	p._wall_climb = null
	p._grapple_ability = null
	sl.free()
	wc.free()
	hook.free()
	gr.free()
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
	assert_almost_eq(p._stamina_mgr._sprint_lockout_left, GameSettings.player_movement.stamina_sprint_lockout, 0.001,
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


## is_sprinting() is what CameraEffects reads to widen the sprint FOV, so it must share every gate the sprint drain
## uses. A bare Player is never on the floor, so its own StaminaManager is pointed at a grounded stand-in body.
func test_is_sprinting_needs_a_grounded_run_with_stamina_stick_input_and_no_ads() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_true(p.has_method(&"is_sprinting"),
		"CameraEffects duck-calls is_sprinting() for the sprint FOV widen — a rename silently kills the widen")
	var body: _TestBody = await _grounded_body(TEST_FLOOR_ORIGIN)
	assert_true(body.is_on_floor(), "precondition: the stand-in body is standing on the test floor")
	p._stamina_mgr.host = body
	p.input_dir = Vector2(0.0, -1.0)
	Input.action_press(InputManager.action_run)
	assert_true(p.is_sprinting(), "control: Run held + stick forward + grounded + stamina + hip-fire = sprinting")
	p.input_dir = Vector2.ZERO
	assert_false(p.is_sprinting(),
		"no stick input is not a sprint even with Run held — is_sprinting must pass the Player's live input_dir")
	p.input_dir = Vector2(0.0, -1.0)
	Input.action_release(InputManager.action_run)
	assert_false(p.is_sprinting(), "Run is opt-in: without the modifier you walk")
	Input.action_press(InputManager.action_run)
	body._is_scoped = true
	assert_false(p.is_sprinting(),
		"aiming down sights pins you to the walk tier, so the sprint read (drain + FOV widen) must stop too")
	GameSettings.weapon_general.allow_sprint_while_scoped = true
	assert_true(p.is_sprinting(), "allow_sprint_while_scoped is the designer opt-out that restores run-while-scoped")
	GameSettings.weapon_general.allow_sprint_while_scoped = _saved_allow_sprint_while_scoped
	body._is_scoped = false
	p._begin_sprint_lockout()
	assert_false(p.is_sprinting(), "a sprint lockout blocks the sprint read even with stamina left")
	p._update_sprint_lockout(GameSettings.player_movement.stamina_sprint_lockout + 0.01)
	assert_true(p.is_sprinting(), "the lockout running out restores the sprint")
	p.stamina = 0.0
	assert_false(p.is_sprinting(), "an empty stamina pool can't sprint")
	p.stamina = p.stamina_max()
	assert_true(p.is_sprinting(), "control: a refilled pool sprints again while still grounded")
	body.velocity = Vector3(0.0, 8.0, 0.0)
	body.move_and_slide()
	assert_false(body.is_on_floor(), "precondition: the stand-in body has left the floor")
	assert_false(p.is_sprinting(), "airborne is never sprinting — the FOV must not stay widened through a jump off a stale read")
	p.free()


func test_aiming_down_sights_blocks_sprint() -> void:
	# The ONE ADS/sprint gate, shared by _wants_sprint (stamina drain + the sprint FOV widen) and
	# GroundMovement's walk-tier fallback. Pure predicate, so it reads correctly off-tree. (That _wants_sprint
	# really consults it is driven in the is_sprinting test above.)
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_false(p.sprint_blocked_by_scope(),
		"hip-fire must never block sprint")
	p._is_scoped = true
	assert_true(p.sprint_blocked_by_scope(),
		"aiming down sights locks the player out of the run tier")
	var prior: bool = GameSettings.weapon_general.allow_sprint_while_scoped
	GameSettings.weapon_general.allow_sprint_while_scoped = true
	assert_false(p.sprint_blocked_by_scope(),
		"allow_sprint_while_scoped is the designer opt-out that restores run-while-scoped")
	GameSettings.weapon_general.allow_sprint_while_scoped = prior
	p.free()


func test_player_jump_launch_is_gated_on_paying_its_stamina_cost() -> void:
	# SOURCE-SCOPED pin, kept on purpose: the launch lives inside Player._physics_process, which never runs in a unit
	# test (see the header). spend_stamina's refusal on an empty pool is driven above.
	var body := _player_func_body("func _physics_process(delta: float) -> void:")
	var gate_at := body.find("if coyote_time.can_jump()")
	var launch_at := body.find("velocity.y = GameSettings.player_movement.jump_velocity")
	assert_true(gate_at > -1 and launch_at > gate_at,
		"precondition: _physics_process still opens the jump with the coyote/buffer gate and then sets the launch velocity")
	var header_end := body.find(":\n", gate_at)
	var spend_at := body.find("spend_stamina(GameSettings.player_movement.stamina_jump_cost)", gate_at)
	assert_true(spend_at > gate_at and spend_at < header_end and header_end < launch_at,
		"the jump's stamina_jump_cost must be paid in the launch CONDITION — spend_stamina refuses on an empty pool, so an exhausted player can't jump; paying inside the block (or after it) would launch for free")


func test_bare_stamina_manager_null_guards_and_pure_regen_curve() -> void:
	# The StaminaManager's null-guard contract: the Player builds it at var-init and wires host in _init, but a
	# BARE manager (host == null, straight load().new()) must degrade to the bare off-tree Player's defaults —
	# no sheet, not on the floor, standing, unscoped — and never crash. RefCounted: released with `= null`.
	var m = load(STAMINA_SCRIPT_PATH).new()
	assert_almost_eq(m.stamina_max(), maxf(1.0, GameSettings.player_movement.max_stamina), 0.001,
		"a bare manager's stamina_max is the base tuning max (no endurance sheet), still floored at 1.0")
	assert_true(m.can_sprint(),
		"a bare manager starts with a full pool and no lockout, so can_sprint reads true")
	assert_false(m.sprint_blocked_by_scope(),
		"a bare manager reads _is_scoped false through the null-guard — hip-fire semantics, no crash")
	assert_false(m._wants_sprint(Vector2(0, -1)),
		"a bare manager is never on the floor (host is_on_floor -> false), so _wants_sprint refuses without crashing")
	m._update_sprint_lockout(0.016)
	m._update_stamina_recovery(0.016)
	assert_almost_eq(m.stamina, m.stamina_max(), 0.001,
		"the bare lockout/recovery ticks no-op safely against the null host (a full pool stays put)")
	# The pure static regen curve (the Landing impact_for idiom): tier ordering mirrors test_settings_load's
	# knob pins — resting recovers fastest, special movement slowest, airborne bypasses the moving predicate.
	var idle: float = m.recovery_rate_for(false, false, 0.0, 0.0)
	var moving: float = m.recovery_rate_for(false, false, 1.0, 0.0)
	var active: float = m.recovery_rate_for(true, false, 0.0, 0.0)
	var airborne: float = m.recovery_rate_for(false, true, 0.0, 0.0)
	assert_gt(idle, moving,
		"the pure regen curve keeps idle > moving (standing still recovers fastest)")
	assert_gt(moving, active,
		"the pure regen curve keeps moving > active (climb/slide/grapple recovers slowest)")
	assert_almost_eq(airborne, GameSettings.player_movement.stamina_regen_airborne, 0.001,
		"airborne picks the airborne tier ahead of the moving/idle predicates")
	var drift: float = m.recovery_rate_for(false, false, 0.0, GameSettings.player_movement.footstep_min_horizontal_speed + 0.1)
	assert_almost_eq(drift, GameSettings.player_movement.stamina_regen_moving, 0.001,
		"real horizontal speed with no stick input still counts as moving (the footstep threshold)")
	m = null


func test_agility_scales_the_stamina_regen_curve() -> void:
	# AGILITY's third derived effect (CharacterStats.stamina_regen_mult) lands HERE: it scales whichever tier the
	# curve already picked, and never promotes the tier — a high-agility climber recovers faster ON the climbing
	# rate, they don't get handed the idle rate. The scale is a DEFAULTED trailing arg, so every four-arg probe in
	# the test above still reads the authored curve unscaled.
	var m = load(STAMINA_SCRIPT_PATH).new()
	var idle: float = m.recovery_rate_for(false, false, 0.0, 0.0)
	assert_almost_eq(m.recovery_rate_for(false, false, 0.0, 0.0, 1.2), idle * 1.2, 0.001,
		"the agility scale multiplies the picked tier rate")
	assert_almost_eq(m.recovery_rate_for(false, false, 0.0, 0.0, -2.0), 0.0, 0.001,
		"a negative scale floors at 0 — recovery can stop dead, but it must never invert into a silent drain")
	assert_almost_eq(m.recovery_rate_for(true, false, 0.0, 0.0, 2.0),
		GameSettings.player_movement.stamina_regen_active * 2.0, 0.001,
		"the scale rides the special-movement tier too — agility helps in every state, it doesn't change which state you're in")
	m = null
	# The LIVE host wiring. Both players are bare and off-tree, so is_on_floor() is false for both and each picks
	# the SAME (airborne) tier — the only difference between the two ticks is the stat sheet.
	var baseline_p = load(PLAYER_SCRIPT_PATH).new()
	var nimble_p = load(PLAYER_SCRIPT_PATH).new()
	var quick := CharacterStats.new()
	quick.agility = 10
	nimble_p.stats = quick
	baseline_p.stamina = 10.0
	nimble_p.stamina = 10.0
	baseline_p._update_stamina_recovery(0.5)
	nimble_p._update_stamina_recovery(0.5)
	assert_gt(nimble_p.stamina, baseline_p.stamina,
		"agility refills the pool faster than a baseline sheet over the same tick — the whole point of the stat")
	assert_almost_eq(nimble_p.stamina - 10.0, (baseline_p.stamina - 10.0) * 1.5, 0.001,
		"agility 10 -> exactly +50% recovered per tick (5%/pt), the linear no-soft-cap contract")
	baseline_p.free()
	nimble_p.free()
	quick = null


func test_player_apply_velocity_wires_stair_assist_around_the_slide() -> void:
	# SOURCE-SCOPED pin, kept on purpose: apply_velocity early-returns off-tree (_has_live_physics_space) and a Player
	# never enters the tree in a unit test, so this call ORDER cannot be driven. The gate it consults IS driven
	# (test_player_step_assist_blocks_live_blast_impulse), and the riser kinematics are Locomotor's shared core.
	var body := _player_func_body("func apply_velocity() -> void:")
	var walk_at := body.find("var walk_velocity := velocity")
	var blast_at := body.find("velocity += explosion_velocity")
	assert_true(walk_at > -1 and blast_at > walk_at,
		"stair intent must be captured from the WALK velocity before the blast impulse is summed in — judged on the sum, a live blast reads as walking")
	assert_true(body.contains("_can_use_step_assist(walk_velocity)"),
		"the step gate must judge that walk velocity, so upward launch frames and blast-dominated shoves never snap back to the floor")
	assert_true(body.contains("not is_climbing() and not is_grappling()"),
		"climbing and a live grapple own the vertical — stair assist must stand down for both")
	var up_at := body.find("_try_step_up(start_transform, walk_velocity")
	var slide_at := body.find("move_and_slide()")
	var down_at := body.find("_try_step_down(walk_velocity)")
	assert_true(up_at > -1 and slide_at > up_at and down_at > slide_at,
		"the riser probe must run from the grounded START pose before sliding into the step, and the descending-tread snap only after the slide has moved the body")
	var step_up := _player_func_body("func _try_step_up(")
	assert_true(step_up.contains("Locomotor.compute_step_up(self, start_transform") and step_up.contains("GameSettings.player_movement.step_up_height"),
		"the Player's step-up must delegate to the shared Locomotor core with the designer-tunable step_up_height, so one riser algorithm serves player + NPC")
	assert_true(_player_func_body("func _try_step_down(").contains("Locomotor.compute_step_down(self,"),
		"the descending-tread snap must delegate to the shared Locomotor core too")


## The airborne arm, pinned as source text for the same reason the step-assist beats above are: it is
## byte-order-critical control flow inside _physics_process that no off-tree test can execute.
func test_player_air_arm_delegates_to_airmovement_and_seeds_the_landing() -> void:
	var src := FileAccess.get_file_as_string(PLAYER_SCRIPT_PATH)
	assert_true(src.contains("AirMovement.step(self, direction, target_speed, _air_ceiling, delta, fps_factor)"),
		"the airborne arm must delegate to AirMovement — the whole never-raises-speed safety argument lives in that function, and an inline lerp here is what froze the air target at takeoff")
	assert_false(src.contains("velocity.x = lerpf(velocity.x, direction.x * current_speed, t_air)"),
		"the airborne lerp must be GONE — while it exists someone can chase `direction` scaled by the ground-frozen speed again, which is the exact defect (a standing jump steering toward the zero vector for 14 cm)")
	assert_true(src.contains("current_speed = maxf(current_speed, minf(_air_exit_speed, target_speed))"),
		"the grounded arm must seed the landing from the speed we actually arrived with — one-way and capped at the ground target, or maintained airborne speed is lerped back down on touchdown as a ~29% stumble")
	assert_true(src.contains("_air_exit_speed = Vector2(velocity.x, velocity.z).length()"),
		"the airborne arm must record the speed it will hand the ground, unconditionally — including on the frames AirMovement stands down, so a climb or grapple exit lands with an honest number too")
	assert_true(src.contains("_air_ceiling = maxf(_air_ceiling, target_speed * GameSettings.player_movement.air_speed_mult)"),
		"the air tier must be latched as a per-airtime HIGH-WATER, so releasing the key / feathering a stick / scoping / opening a modal stops you BUILDING without retroactively BRAKING what you already built")
	assert_true(src.contains("current_speed = maxf(current_speed, launched)"),
		"the momentum launch must bank the boosted speed as the air ceiling — AirMovement's settle floor is current_speed, so a launch that does not raise it is settled straight back off on the very next airborne frame")
	assert_true(src.contains("AirMovement.takeoff_speed(carried, target_speed, GameSettings.player_movement.jump_momentum_boost)"),
		"the momentum launch must route through AirMovement.takeoff_speed — its ground-legal gate is the only thing stopping the boost compounding into a free bunny-hop that out-runs the paid chip")
	# Anchored on the launch BODY, not "if jumped_now:" — that header occurs twice (the variable-jump
	# cut ~100 lines earlier reuses it), so find() returned the cut block and the ordering assert below
	# held even if the launch were deleted outright.
	var launch_at := src.find("var carried := Vector2(velocity.x, velocity.z).length()")
	var stamp_at := src.find("var bhop_speed := bunnyhop.get_target_speed(Vector2(velocity.x, velocity.z).length())")
	assert_gt(launch_at, 0,
		"the momentum launch must exist — it is the only lever that lengthens a FAST jump, since travel is speed x a fixed airtime")
	assert_lt(launch_at, stamp_at,
		"the momentum launch must sit BEFORE the bunny-hop stamp, so a chained hop overwrites it and the chip stays exempt by construction — boosting a 12 m/s chain would clear the wind, look-sensitivity, pinball and ram thresholds at once")
	assert_true(src.contains("if input_dir != Vector2.ZERO:"),
		"...and the latch must be gated on input actually being held: latching unconditionally would floor the settle at the walk tier for a player who never pressed anything, leaving every blast knockback coasting instead of damping to rest")


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
	assert_true(p.has_method("on_air_dash"),
		"Player.on_air_dash must exist — it applies the air dash's shake + FOV punch")
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


# --- out-of-combat recovery: the heartbeat duck + the passive health regen ---
# Both ride the ONE is_out_of_combat() predicate, so the softer heartbeat IS the audible tell that healing has
# begun. The two curves are PURE STATICS (the StaminaManager.recovery_rate_for idiom), pinned here host-free.

func test_health_regen_rate_curve_is_pure_and_floored() -> void:
	# health_regen_rate_for(max_hp, frac_per_sec, endurance_mult) — a static, so no Player is built at all.
	assert_almost_eq(Player.health_regen_rate_for(10.0, 0.02, 1.0), 0.2, 0.0001,
		"at a neutral endurance multiplier the rate is simply max_hp x the authored fraction")
	assert_almost_eq(Player.health_regen_rate_for(10.0, 0.02, 2.0), 0.4, 0.0001,
		"the endurance multiplier scales the rate linearly — double the multiplier, double the HP/s")
	assert_almost_eq(Player.health_regen_rate_for(20.0, 0.02, 1.0), 0.4, 0.0001,
		"the knob is a FRACTION of max HP, so doubling max_hp doubles HP/s and the empty->full TIME stays fixed as a build grows")
	assert_almost_eq(Player.health_regen_rate_for(10.0, 0.0, 1.0), 0.0, 0.0001,
		"a 0 fraction is the documented off-switch for the whole feature")
	assert_almost_eq(Player.health_regen_rate_for(10.0, 0.02, 0.0), 0.0, 0.0001,
		"an endurance multiplier of 0 (the CharacterStats floor) stops regen entirely")
	assert_almost_eq(Player.health_regen_rate_for(10.0, 0.02, -3.0), 0.0, 0.0001,
		"the rate is FLOORED at 0 and can never go negative — a negative would reach Character.heal(), which drains hp with no death check, no flash and no _dead latch")


func test_heartbeat_duck_is_volume_only_and_keeps_the_intensity_ramp() -> void:
	# heartbeat_db_for(db_min, db_max, intensity, duck_db, calm) — the calm cut folds into the SAME lerp the beat
	# already used, so the near-death ramp survives and the beat INTERVAL is untouched.
	var loud: float = Player.heartbeat_db_for(-16.0, 2.0, 0.5, 4.0, false)
	var calm: float = Player.heartbeat_db_for(-16.0, 2.0, 0.5, 4.0, true)
	assert_almost_eq(calm, loud - 4.0, 0.0001,
		"out of combat the beat is exactly duck_db quieter at the same HP — a SLIGHT cut, not a mute")
	assert_almost_eq(Player.heartbeat_db_for(-16.0, 2.0, 1.0, 4.0, true) - Player.heartbeat_db_for(-16.0, 2.0, 0.0, 4.0, true),
		Player.heartbeat_db_for(-16.0, 2.0, 1.0, 4.0, false) - Player.heartbeat_db_for(-16.0, 2.0, 0.0, 4.0, false), 0.0001,
		"the duck SHIFTS the curve without flattening it: a calm player bleeding out still gets louder as they fall, by the same dB span as in combat")
	assert_almost_eq(Player.heartbeat_db_for(-16.0, 2.0, 0.5, 0.0, true), loud, 0.0001,
		"duck_db 0 is byte-identical to the un-ducked beat — the knob's own off position")
	assert_almost_eq(Player.heartbeat_db_for(-16.0, 2.0, 0.5, -4.0, true), calm, 0.0001,
		"a NEGATIVE duck still CUTS (absf) — a designer who reads the knob as a signed offset cannot accidentally make the calm heartbeat louder")
	assert_almost_eq(Player.heartbeat_db_for(-16.0, 2.0, 0.0, 4.0, true), -20.0, 0.0001,
		"against the shipped -16/+2 range a calm threshold beat lands at -20 dB: quieter, nowhere near inaudible (silencing it is the Accessibility toggle's job, not the duck's)")


## The duck above is a pure curve; this drives the real per-beat gain line in _update_low_hp. The AudioStreamPlayer is
## in-tree (play() needs it) while the Player stays bare and off-tree, so only the heartbeat half of the beat runs.
func test_heartbeat_calm_duck_reaches_the_live_beat() -> void:
	var duck: float = absf(GameSettings.player_feedback.heartbeat_calm_duck_db)
	assert_gt(duck, 0.0,
		"the shipped heartbeat DUCKS once a fight is over — at 0 dB this test could not tell a wired duck from a dropped one")
	var p = load(PLAYER_SCRIPT_PATH).new()
	var beat := AudioStreamPlayer.new()
	beat.stream = p.heartbeat_sound
	add_child_autofree(beat)
	p._heartbeat = beat
	Settings.heartbeat_enabled = true
	p.max_hp = 100.0
	p.hp = 10.0
	p._update_low_hp(0.016)
	assert_true(beat.playing, "precondition: a badly hurt player's heartbeat beats")
	var calm_db := beat.volume_db
	p.note_combat()
	# A full slow interval always reaches the next beat: the timer is lerped between the slow and fast intervals, and
	# test_player_heartbeat_uses_real_asset_and_ramps_toward_death pins fast < slow.
	p._update_low_hp(p.heartbeat_interval_slow)
	assert_almost_eq(beat.volume_db - calm_db, duck, 0.001,
		"out of combat the live beat must be heartbeat_calm_duck_db quieter than the same HP mid-fight — a duck written anywhere but the per-beat gain is clobbered on the next beat")
	beat.stop()
	p.free()


func test_out_of_combat_grace_and_cold_boot_sentinel() -> void:
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	assert_gte(fb.combat_calm_grace, 0.0,
		"the grace is a duration, so a negative would make is_out_of_combat() true on the very frame you fired")
	# The == 0 sentinel: Time.get_ticks_msec() counts from ENGINE START, so an unstamped _last_combat_msec makes
	# seconds_since_combat() report the process uptime — on a cold boot a small number, i.e. "in combat". Deep in a
	# GUT run the uptime is already far past the shipped grace, which would hide a missing sentinel, so the cold boot
	# is reproduced by stretching the grace (restored in after_each) past the uptime instead.
	fb.combat_calm_grace = float(Time.get_ticks_msec()) / 1000.0 + 3600.0
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_lt(p.seconds_since_combat(), fb.combat_calm_grace,
		"premise: an unstamped player's time-since-combat (the engine uptime) sits inside the stretched grace, as it does on a cold boot")
	assert_true(p.is_out_of_combat(),
		"a player who has never been in a fight this process must read OUT of combat — without the _last_combat_msec == 0 sentinel a fresh spawn reads the ENGINE UPTIME as its time-since-combat and refuses to heal")
	p.note_combat()
	assert_false(p.is_out_of_combat(),
		"the instant combat is stamped the player is IN combat — the grace has not elapsed")
	# Control: once stamped, the clock really is judged against the grace — with no grace to wait out, the same
	# player reads calm again at once.
	fb.combat_calm_grace = 0.0
	assert_true(p.is_out_of_combat(),
		"with a zero combat_calm_grace a stamped player is out of combat immediately, so the grace is what held the in-combat read")
	fb.combat_calm_grace = _saved_combat_calm_grace
	p.free()


func test_health_regen_commits_in_steps_and_is_gated_by_combat_and_death() -> void:
	# Drive _update_health_regen directly with fake deltas (the _update_sprint_lockout idiom). hp/max_hp are
	# written RAW — never take_damage() off-tree, which reaches gore() -> get_world_3d() and the master bus.
	var p = load(PLAYER_SCRIPT_PATH).new()
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	p.max_hp = 10.0
	p.hp = 1.0
	var step: float = p.max_hp * fb.health_regen_commit_frac
	var rate: float = Player.health_regen_rate_for(p.max_hp, fb.health_regen_frac_per_sec, 1.0)
	assert_gt(rate, 0.0, "the shipped tuning must actually regenerate, or the rest of this test proves nothing")
	assert_gt(step, 0.0, "the shipped commit step must be a real step, or the banking half of this test proves nothing")
	# 1) below the commit step: the slice BANKS, hp does not move and `damaged` never fires.
	var almost: float = (step / rate) * 0.9
	p._update_health_regen(almost)
	assert_almost_eq(p.hp, 1.0, 0.0001,
		"a sub-step slice must NOT pay out — `damaged` is a discrete event signal (the carried emitting light recolours on it), not a 60 Hz write")
	assert_gt(p._health_regen_carry, 0.0, "the un-committed slice is BANKED in the carry, not discarded")
	# 2) crossing the step commits the whole banked carry through heal().
	var banked: float = p._health_regen_carry
	p._update_health_regen(almost)
	assert_almost_eq(p.hp, 1.0 + banked + rate * almost, 0.001,
		"once the carry crosses the commit step the WHOLE bank pays out through Character.heal()")
	assert_almost_eq(p._health_regen_carry, 0.0, 0.0001, "committing resets the carry")
	# 3) in combat: the carry is held — neither grown nor erased.
	p._update_health_regen(almost)          # bank a fresh sub-step slice
	var hp_before: float = p.hp
	var held: float = p._health_regen_carry
	assert_gt(held, 0.0, "precondition: a slice is banked before combat is stamped")
	p.note_combat()
	p._update_health_regen(almost)
	assert_almost_eq(p.hp, hp_before, 0.0001, "no healing while in combat")
	assert_almost_eq(p._health_regen_carry, held, 0.0001,
		"a lull mid-fight PAUSES progress: the banked carry survives combat unchanged — it neither grows nor is thrown away")
	# 4) dead: no regen at all, and the carry is cleared so it can never pay into a later life.
	p._dead = true
	p._update_health_regen(1.0)
	assert_almost_eq(p.hp, hp_before, 0.0001,
		"a corpse never heals — Character.heal() has no _dead guard of its own, so this gate is the only one")
	assert_almost_eq(p._health_regen_carry, 0.0, 0.0001, "death clears the banked carry")
	# 5) at the ceiling: inert, no overheal.
	p._dead = false
	p.hp = p.max_hp
	p._update_health_regen(1.0)
	assert_almost_eq(p.hp, p.max_hp, 0.0001, "regen stops at the ceiling and never overheals past max HP")
	p.free()


func test_health_regen_holds_through_a_cutscene_and_a_conversation() -> void:
	# take_damage() is off while the world is frozen (InputManager.world_frozen()), so it must not HEAL either: a
	# cutscene never pauses the tree, and a long shopkeeper chat must not become a Bonfire. Both halves of the frozen
	# predicate are flipped for real; the banked carry is HELD (like the in-combat pause), never grown or confiscated.
	var p = load(PLAYER_SCRIPT_PATH).new()
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	p.max_hp = 10.0
	p.hp = 1.0
	var step: float = p.max_hp * fb.health_regen_commit_frac
	var rate: float = Player.health_regen_rate_for(p.max_hp, fb.health_regen_frac_per_sec, 1.0)
	assert_gt(rate, 0.0, "the shipped tuning must actually regenerate, or this test proves nothing")
	assert_gt(step, 0.0, "the shipped commit step must be a real step, or the held-carry half proves nothing")
	var many_steps: float = (step / rate) * 4.0
	p._update_health_regen((step / rate) * 0.5)
	var banked: float = p._health_regen_carry
	assert_gt(banked, 0.0, "control: a calm, unfrozen player banks regen")
	CutscenePlayer._active = true
	p._update_health_regen(many_steps)
	CutscenePlayer._active = _saved_cutscene_active  # restore BEFORE asserting (after_each is the second net)
	assert_almost_eq(p.hp, 1.0, 0.0001, "no healing while a cutscene plays — watching one must not be a rest stop")
	assert_almost_eq(p._health_regen_carry, banked, 0.0001,
		"a cutscene PAUSES the banked carry; it neither grows it nor confiscates it")
	DialogueManager._active = DialogueResource.new()
	p._update_health_regen(many_steps)
	DialogueManager._active = _saved_dialogue
	assert_almost_eq(p.hp, 1.0, 0.0001,
		"no healing in a conversation — you're already damage-immune there, and the low-HP feedback is frozen with you")
	assert_almost_eq(p._health_regen_carry, banked, 0.0001, "a conversation holds the banked carry too")
	p._update_health_regen(many_steps)
	assert_gt(p.hp, 1.0, "once the world unfreezes the same tick heals again — the hold was the frozen world, not the player")
	p.free()


func test_regen_beat_runs_in_the_live_physics_step_ahead_of_the_low_hp_feedback() -> void:
	# SOURCE-SCOPED pin, kept on purpose: Player._physics_process never runs in a unit test. The regen's GATES are
	# driven above; this pins only where the beat sits.
	var body := _player_func_body("func _physics_process(delta: float) -> void:")
	var regen_at := body.find("_update_health_regen(delta)")
	var lowhp_at := body.find("_update_low_hp(delta)")
	assert_true(regen_at > -1,
		"the regen beat must be driven from Player._physics_process — die() calls set_physics_process(false), so a self-ticking Timer/component would keep healing the corpse under the death card")
	assert_true(lowhp_at > regen_at,
		"the regen beat must run BEFORE _update_low_hp so the vignette + heartbeat paint THIS frame's post-regen HP, with no one-frame lag")
	# NEGATIVE placement: the dialogue-frozen early-out returns before the live step, so a regen call moved in there
	# would stop live healing entirely (and turn every conversation into a rest stop) while both finds above still hit.
	var frozen_at := body.find("if DialogueManager.is_active():")
	var frozen_return := body.find("\t\treturn\n", frozen_at)
	assert_true(frozen_at > -1 and frozen_return > frozen_at,
		"precondition: _physics_process still opens with the dialogue-frozen early-out")
	assert_gt(regen_at, frozen_return,
		"the regen beat must sit AFTER the dialogue-frozen early-out returns — inside that branch it never runs in live play (and a conversation must not become a rest stop)")


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

func test_grapple_hook_tuning_keeps_its_reach_relations() -> void:
	# Build WITHOUT add_child so _ready (which reads InputMap + add_childs a rope mesh) never runs.
	var g = load(GRAPPLE_SCRIPT_PATH).new()
	assert_true(g is Node3D,
		"GrappleHook must extend Node3D — it lives under the player and draws the rope mesh")
	assert_gt(g.break_distance, g.max_range,
		"the force-release distance must sit beyond the aim reach, or a hook caught near max_range snaps the moment it attaches")
	assert_true(g.min_rope_length > 0.0 and g.min_rope_length < g.max_range,
		"reeling in must stop short of the anchor, and short of the aim reach or a tether could never be reeled at all")
	assert_gt(g.reel_speed, 0.0, "holding jump on a tether must actually climb toward the anchor")
	assert_gte(g.swing_assist, 0.0, "a negative swing assist would brake the swing you are pumping")
	g.free()
	# GrappleHook._apply_config overwrites max_range + break_distance from its config in _ready, so the relation must
	# also hold on every authored config layer — above all the one the shipped Player.tscn hands the hook.
	var configs: Array[GrappleHookResource] = [
		GrappleHookResource.new(),
		load(GRAPPLE_DEFAULT_CONFIG_PATH) as GrappleHookResource,
	]
	for cfg in configs:
		assert_true(cfg != null, "precondition: the grapple config loads as a GrappleHookResource")
		if cfg == null:
			continue
		assert_gt(cfg.break_distance, cfg.max_range,
			"grapple config '%s' must break beyond its aim reach, or a hook caught near max_range snaps the moment it attaches"
				% (cfg.resource_path if cfg.resource_path != "" else "GrappleHookResource defaults"))
	configs.clear()
	var shipped := _shipped_player_property(&"grapple_resource") as GrappleHookResource
	assert_true(shipped != null, "precondition: Player.tscn wires a grapple_resource")
	if shipped != null:
		assert_gt(shipped.break_distance, shipped.max_range,
			"the SHIPPED grapple config must break beyond its aim reach, or a hook caught near max_range snaps the moment it attaches")


## The YANK reel, driven for real: GrappleHook stays off-tree; its player and the grabbed enemy are parked
## Character stand-ins, so apply_pull reads live positions without any physics moving them.
func test_grapple_yank_ramps_an_enemy_up_to_yank_speed_and_drops_it_at_reach() -> void:
	var me := _parked_body(PARKED_BODY_ORIGIN)
	var enemy := _parked_body(PARKED_BODY_ORIGIN + Vector3(0.0, 0.0, -20.0))
	var g := GrappleHook.new()
	assert_lt(20.0, g.break_distance, "precondition: the enemy starts inside the rope's break distance")
	g.character = me
	g._state = GrappleHook.State.ATTACHED
	g._mode = GrappleHook.Mode.YANK
	g._yanked = enemy
	const DT := 1.0 / 60.0
	g.apply_pull(DT)
	assert_almost_eq(enemy.explosion_velocity.length(), minf(g.yank_accel * DT, g.yank_speed), 0.0001,
		"the reel RAMPS at yank_accel — a grabbed enemy is not snapped to top speed on the first frame")
	assert_gt(enemy.explosion_velocity.z, 0.0, "the enemy is reeled TOWARD the player")
	for i in 120:
		g.apply_pull(DT)
	assert_almost_eq(enemy.explosion_velocity.length(), g.yank_speed, 0.0001,
		"two seconds of reeling never pass yank_speed — the top reel-in speed caps enemies instead of accumulating without bound")
	assert_true(g.is_attached(), "the rope holds while the enemy is still out of reach")
	enemy.global_position = me.global_position + Vector3(0.0, 0.0, -0.5 * g.reach_distance)
	g.apply_pull(DT)
	assert_false(g.is_attached(), "an enemy reeled within reach_distance is let go")
	assert_true(g.is_active(), "...by RETRACTING the hook, so the next shot waits for it to come home")
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
	# Verified registered in project.godot [input] (bound to G).
	assert_true(InputMap.has_action("Grapple"),
		"The Grapple action must exist in the input map (bound to G) or the grapple never arms")


# --- player_debug.gd -------------------------------------------------------

func test_player_debug_extends_node3d_and_has_no_reload_key() -> void:
	# PlayerDebug has no _ready, so .new() is safe. The End-key hard reload was REMOVED 2026-09-12: it shipped
	# UNGATED in every build and lost unsaved progress on one press. The console's `reload` is the dev reload.
	var d = load(PLAYER_DEBUG_SCRIPT_PATH).new()
	assert_true(d is Node3D, "PlayerDebug must extend Node3D so it can sit in the Player scene")
	assert_false(d.has_method("reset"),
		"PlayerDebug.reset is gone — no ungated hard-reload key may ship (it lost unsaved progress in release builds)")
	assert_true(d.has_method("audit_null_material_meshes"),
		"the Home-key null-material mesh audit stays (its listener is gated on OS.is_debug_build)")
	d.free()
