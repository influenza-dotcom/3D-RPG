class_name Player
extends Character

var current_speed: float = 0.0

@onready var white_flash: Sprite3D = $"Head/ScreenShake/Camera3D/white flash"
@onready var bowling: AudioStreamPlayer3D = $bowling
@onready var _nv_rect: ColorRect = get_node_or_null("UI/ColorRect")

@export var jump_sfx: AudioStreamPlayer3D
@export var land_sfx: AudioStreamPlayer3D
@export var walking_sfx: AudioStreamPlayer3D
@export var falling_air_sfx: AudioStreamPlayer
@export var crouch: Crouch
@export var head: Head
@export var player_collision_shape: CollisionShape3D
@export var weapon_system: Weapon
@export var ui: UI
@export var coyote_time: CoyoteTime
@export var jump_buffer: JumpBuffer
@export var bullet_time: BulletTime
@export var bunnyhop: Bunnyhop
@export var mouse_input: MouseInput

# Resolved/derived in _enter_tree off the extracted component interfaces, not wired in the
# scene: the camera + screen-shake come off the camera rig (head.camera / head.screen_shake),
# the muzzle off the gun rig (gun_mesh.muzzle), and gun_mesh is resolved from the tree. Their
# scene NodePaths pointed into instanced sub-scenes, so the Save-Branch extractions cleared
# them from Player.tscn entirely.
var camera_effects: CameraEffects
var screen_shake: ScreenShake
var muzzle: Marker3D
@onready var grappling: Marker3D = $grappling

var gun_mesh: GunMesh

var footstep_interval: float = GameSettings.player_movement.footstep_base_interval
var _footstep_timer: float = 0.0
var _climbing: bool = false

## The fake blob shadow (a Decal child) projects straight DOWN on the ground; while wall-climbing we
## rotate it to project onto the WALL instead, easing back when grounded. Cached + driven in code.
const SHADOW_LERP_SPEED: float = 6.0  ## how fast the shadow rotates onto the wall / back to the ground
var _shadow: Decal
var _shadow_rest_local: Transform3D  ## the decal's authored local transform (projects down) — the ground pose
var _shadow_wall_blend: float = 0.0  ## 0 = grounded (down), 1 = fully projected onto the climbed wall

var _was_on_floor: bool = false
var input_dir: Vector2 = Vector2.ZERO

const NIGHT_VISION_FADE_RATE: float = 9.0
var _nv_on: bool = false
var _nv_t: float = 0.0

## Hurt feedback ("getting rocked"): a hit hard-dips the global time-scale, slaps a low-pass
## "muffle" on the master bus, punches the camera, and drains the screen to a dark red
## desaturation + tunnel vignette — all eased back together over HURT_RECOVERY.
const HURT_FREEZE_SCALE: float = 0.15  ## time_scale at the dip (lower = more brutal slow-mo)
const HURT_FREEZE_HOLD: float = 0.12   ## real-time hold at the dip before easing back
const HURT_RECOVERY: float = 0.55      ## real-time ease back to normal
const HURT_LPF_CUTOFF: float = 350.0   ## low-pass cutoff (Hz) at full hurt — lower = more muffled
const HURT_LPF_CLEAR: float = 20500.0  ## cutoff when clear (effectively no filtering)
const HURT_SHAKE: float = 0.4          ## screen-shake punch the instant you're hit
const MASTER_BUS: int = 0

var _sliding: bool = false
var _slide_dir: Vector3 = Vector3.ZERO
var _slide_speed: float = 0.0
var _slide_dust_timer: float = 0.0
var _slide_sfx: AudioStreamPlayer
# Single-responsibility components, built in code in _ready and handed a host ref right after .new()
# (mirrors the @export-wired controllers above). Each owns one slice of what was this god-file: the
# code-built HUD overlays, the ram/thump/bounce impact reactions, the noise emission enemies hear, the
# scope reactions + music duck, the "getting rocked" hurt feedback, and the conversation camera/weapon
# handling. Null off-tree (a bare .new() in a test skips _ready), so every facade below null-guards
# them and returns the monolith's old value.
var _hud: PlayerHud
var _ram_reactor: RamReactor
var _noise: NoiseEmitter
var _scope: ScopeCoordinator
var _hurt: HurtFeedback
var _dialogue: DialogueController

@export_group("Ram")
# Heavy thud played when you body-ram an enemy but DON'T kill it (a ram kill
# plays the bowling-strike sfx instead). Swap this for your preferred sound.
@export var ram_thud_sound: AudioStream = preload("uid://budx7vymim0j0")
# Pinball rebound: ramming a wall/object/enemy this fast (into the surface)
# bounces you back off it. Kept high so only real rams bounce, not walking.
@export var ram_bounce_min_speed: float = 7.0
# Rebound bounciness — 1.0 ≈ fully elastic, lower = softer.
@export var ram_bounce_factor: float = 0.2
# Min seconds between bounces (stops jitter against a single wall).
@export var ram_bounce_cooldown: float = 0.15
# Screen-shake punch on a bounce.
@export var ram_bounce_shake: float = 0.15
# Pinball "bumper" sfx played the moment a bounce fires (metallic clang default).
@export var ram_bounce_sound: AudioStream = preload("uid://c3ilkdwchpnhy")

@export_group("Air Thump")
@export var thump_sound: AudioStream = preload("uid://c23166qlxcvbi")
# Minimum speed LOST in a single frame (sudden decel from a real impact, not a
# glancing slide) required to play the thump.
@export var thump_min_speed_lost: float = 7.0
@export var thump_volume_db: float = 6.0
@export var thump_cooldown: float = 0.2

@export_group("Slide")
# Land while holding crouch above this horizontal speed to start a slide.
@export var slide_min_speed: float = 4.0
# How quickly the slide bleeds off speed (m/s per second).
@export var slide_friction: float = 4.0
# Slide ends once it decays to this speed (≈ crouch-walk pace).
@export var slide_end_speed: float = 2.5
# Hard cap on the slide's starting speed (keeps fast bhop landings sane).
@export var slide_max_speed: float = 6.0
## Variable jump (2D-platformer feel): release jump while still rising and the upward velocity is cut by
## this factor for a shorter hop — tap for a low hop, hold for the full jump_velocity arc. 1.0 = no cut.
@export var jump_cut_factor: float = 0.4
## Wall climb: vertical speed while scaling a wall (walk into any wall + hold jump). Always usable.
@export var wall_climb_speed: float = 4.5
## Into-wall press (m/s) applied while gripping so we keep contact (is_on_wall stays true) and can hold
## still on the wall instead of peeling off. Absorbed by the wall, so it adds no visible movement.
@export var wall_grip_stick: float = 2.0
## Little hop when you clear the top of a climb — upward pop + forward nudge to land on the ledge.
@export var climb_hop_up: float = 5.0
@export var climb_hop_forward: float = 3.5
# One-time speed multiplier applied the instant the slide starts (1.0 = none).
@export var slide_boost: float = 1.0
# Slide-jump launch strength as a multiple of your slide speed at jump time
# (so faster slides fling you further). 0 = no launch.
@export var slide_jump_mult: float = 1.5
# Seconds between dust puffs kicked up while sliding.
@export var slide_dust_interval: float = 0.06
# Size/strength of each slide dust puff.
@export var slide_dust_intensity: float = 0.5
# Looping slide sfx. Leave null to reuse the falling-air wind sound (placeholder).
@export var slide_sound: AudioStream

# --- Noise (drives enemy hearing) ---
# Audible radius (m) added per m/s of ground speed while not crouching.
@export var noise_move_per_speed: float = 1.2
# Audible radius (m) of a gunshot, which then decays back to 0.
@export var noise_gunfire_radius: float = 28.0
# How fast the gunshot noise radius shrinks (m/s).
@export var noise_gunfire_decay: float = 45.0
# Current audible radius (read by enemy Perception.can_hear); 0 = silent. The NoiseEmitter component
# WRITES this each frame; it stays declared here so enemy Perception can read player.noise_radius.
var noise_radius: float = 0.0

var target_speed: float = GameSettings.player_movement.max_speed

var _walking_sfx_base_db: float
var _land_sfx_base_db: float
var _land_sfx_base_pitch: float
var _is_scoped: bool = false
## SFX chirped when the air-dash becomes available again (placeholder ding — swap in the inspector).
@export var air_dash_recharge_sfx: AudioStream = preload("res://assets/audio/ding.mp3")
## DASH_FLASH_* feel consts kept here (a unit test reads them off a bare instance); the PlayerHud
## component carries its own copies for the actual flash it builds + drives.
const DASH_FLASH_PEAK_ALPHA: float = 0.5  ## white-flash opacity at the instant of recharge
const DASH_FLASH_TIME: float = 0.18       ## flash fade-out duration
## Grapple config. The grapple is built in code, so its own exports aren't inspector-reachable — assign
## a GrappleHookResource (.tres) HERE on the Player and it's passed through on creation. Holds the rope
## texture/colour, the hook-tip sprite, the SFX, and the feel tuning. Null = the grapple's own defaults.
@export var grapple_resource: GrappleHookResource
var _grapple: GrappleHook    ## Cruelty-Squad grapple; pull applied in _physics_process

func _enter_tree() -> void:
	# Slice 3 lifted the gun rig into view_model.tscn. Godot's Save-Branch-as-Scene clears
	# scene NodePath exports that point into an extracted branch, so resolve the rig from
	# the tree if its export was cleared, then derive the muzzle (the weapon's spawn
	# origin) and the damage-flash mesh from the view-model component itself rather than
	# via now-stale deep paths into the instance.
	if not gun_mesh:
		gun_mesh = get_node_or_null("Head/ScreenShake/Camera3D/GunMesh") as GunMesh
	if gun_mesh:
		muzzle = gun_mesh.muzzle
		mesh = gun_mesh
	# Resolve the HUD root if extraction cleared its export, then inject the player whose
	# HP it shows + the ammo clip it reads. Resolved before the rig below so head.setup()
	# can hand the HUD layer to the view-model camera (its composite container lives there).
	if not ui:
		ui = get_node_or_null("UI") as UI
	if ui:
		ui.setup(self, weapon_system.ammo)
	# Same for the camera rig (Head -> ScreenShake -> Camera3D): resolve the rig root if
	# its export was cleared, read the camera + screen-shake off the rig interface, and
	# inject this player into the rig parts that point back out (camera + pickup raycast).
	if not head:
		head = get_node_or_null("Head") as Head
	if head:
		camera_effects = head.camera
		screen_shake = head.screen_shake
		head.setup(self, mouse_input, ui)
	crouch.player = self
	crouch.head = head
	crouch.collision_shape = player_collision_shape
	weapon_system.setup(self, camera_effects, muzzle)
	coyote_time.character = self
	# The view model self-wires its gun-mesh pose anims + muzzle FX from these refs.
	# (The Slice-1 host-side signal bridge now lives inside GunMesh.setup().)
	gun_mesh.setup(self, weapon_system.inventory, weapon_system.attack, weapon_system.ammo, mouse_input, weapon_system.scope_in)
	bullet_time.character = self
	bullet_time.scope_in = weapon_system.scope_in
	bullet_time.attack = weapon_system.attack
	bunnyhop.character = self
	mouse_input.player = self

func _ready() -> void:
	super._ready()
	# Hurt-feedback component: owns the "getting rocked" slow-mo + screen-drain + bus muffle. Built
	# first so its master-bus low-pass is set up before anything else (matches the old _setup_hurt_lpf
	# being the first call here).
	_hurt = HurtFeedback.new()
	_hurt.host = self
	add_child(_hurt)
	_hurt.setup_lpf()
	_walking_sfx_base_db = walking_sfx.volume_db
	_land_sfx_base_db = land_sfx.volume_db
	_land_sfx_base_pitch = land_sfx.pitch_scale
	# Scope reactions + music duck: drive the crosshair/optics/DoF and duck music on ADS in/out.
	_scope = ScopeCoordinator.new()
	_scope.host = self
	add_child(_scope)
	weapon_system.scope_in.scoped_in.connect(_scope.on_scoped_in)
	weapon_system.attack.air_dash_recharged.connect(_on_air_dash_recharged)
	# Body-impact reactions (ram damage / air thump / pinball bounce), ticked from _physics_process.
	_ram_reactor = RamReactor.new()
	_ram_reactor.host = self
	add_child(_ram_reactor)
	# Noise emitter: writes our audible radius (enemy hearing) each frame; the gunfire spike is fed in
	# from on_weapon_fired.
	_noise = NoiseEmitter.new()
	_noise.host = self
	add_child(_noise)
	# Low-HP heartbeat (#11): a 2D pulse whose rate + volume rise as HP drops, driven in _update_low_hp.
	_heartbeat = AudioStreamPlayer.new()
	_heartbeat.stream = heartbeat_sound
	_heartbeat.bus = &"sfx"
	add_child(_heartbeat)
	# Dedicated looping player for the slide sfx (wind, for now). Built in code so
	# it's independent of the falling-air player, which stops itself on the floor.
	_slide_sfx = AudioStreamPlayer.new()
	_slide_sfx.stream = slide_sound if slide_sound else falling_air_sfx.stream
	_slide_sfx.volume_db = -80.0
	add_child(_slide_sfx)
	# Keep it looping silently and fade the volume in/out with the slide state instead of
	# hard play()/stop() on every brief slide — that restart was the repeated clicking.
	_slide_sfx.finished.connect(_slide_sfx.play)
	_slide_sfx.play()
	# HUD overlays (speed vignette, dash flash, damage arcs, aim radials, sniper glints, hitmarker):
	# built onto the UI layer in the original draw order, with the active camera wired in.
	_hud = PlayerHud.new()
	_hud.host = self
	add_child(_hud)
	_hud.build(ui, camera_effects)
	# Grapple hook: built in code (no scene node), wired to this body, the camera (aim) and the muzzle
	# (rope origin). The pull itself runs in _physics_process below.
	_grapple = GrappleHook.new()
	# Hand over the config BEFORE add_child so the grapple's _ready() builds the rope + hook sprite from
	# it (assigning after would miss the one-time material/sprite build).
	_grapple.config = grapple_resource
	add_child(_grapple)
	_grapple.setup(self, camera_effects, grappling)
	# Conversation camera/weapon handling: focus-on-target zoom + holster-for-dialogue + the holster
	# swing (and its provoke-forgiveness). Built last; its signal handlers are wired straight to it.
	_dialogue = DialogueController.new()
	_dialogue.host = self
	add_child(_dialogue)
	# Holster: hide the gun mesh whenever Attack reports holstered (hold-R toggle / dialogue).
	weapon_system.attack.holster_changed.connect(_dialogue.on_weapon_holstered)
	# Put the weapon away for conversations (restored on finish), reusing the holster.
	DialogueManager.dialogue_started.connect(_dialogue.on_dialogue_started)
	DialogueManager.dialogue_finished.connect(_dialogue.on_dialogue_finished)
	# A fresh life must start on a NORMAL screen. The death cinematic's grayscale + fade-to-black ride a
	# shader sub-resource the scene reload leaves dirty (it's reused from the cached PackedScene), and the
	# slow-mo touches the global Engine.time_scale — so clear them all explicitly on (re)spawn.
	_reset_screen_post_process()
	# Cache the blob-shadow decal + its authored (ground-projecting) pose so the climb can swing it onto
	# the wall and back. Null-guarded everywhere — a Player scene without a "Shadow" decal just skips it.
	_shadow = get_node_or_null("Shadow") as Decal
	if _shadow:
		_shadow_rest_local = _shadow.transform
	# Stock the backpack with the authored starting loadout so the inventory UI lists every weapon the
	# player owns. The hub keeps whatever it equipped on spawn; this just fills the bag (equipping now
	# happens from the UI, not keys 1-7).
	_seed_starting_inventory()

## Stock the backpack with the authored starting loadout (the SwapWeapons weapon_slots). On respawn a
## fresh Player rebuilds it from scratch; the has() guard also keeps a duplicate slot from double-adding.
func _seed_starting_inventory() -> void:
	if inventory == null or weapon_system == null:
		return
	for res in weapon_system.weapon_loadout():
		var w := res as WeaponData
		if w == null:
			continue
		var it := ItemDb.make_weapon_item(w)  # a UNIQUE item per weapon, so identical weapons stay distinct
		if it != null:
			inventory.add(it)
	# Mark the weapon the hub drew on spawn (weapon.tscn's default) as the equipped item, so the inventory
	# shows the right row highlighted before the player ever opens it.
	var drawn := weapon_system.equipped_weapon
	if drawn != null:
		for s in inventory.contents():
			if s["item"].weapon == drawn:
				inventory.equipped_item = s["item"]
				break

## The backpack asked to draw `weapon` (UI click now, looted-then-equipped later). Route it through the
## weapon system's swap path so the down/up swap animation plays — the trigger just moved from keys 1-7
## to the inventory UI. Overrides Character's no-op hook.
func _on_equip_weapon_requested(weapon: WeaponData) -> void:
	if weapon_system != null:
		weapon_system.equip_weapon(weapon)

## Smoothly aim the body yaw + head pitch at `target_pos` so the camera frames whatever the player
## is talking to. Called externally by the talk handler (talkable.gd / dialogue_npc.gd via
## player.focus_camera_on), so the NAME stays here; the work lives in DialogueController.
func focus_camera_on(target_pos: Vector3) -> void:
	if _dialogue:
		_dialogue.focus_camera_on(target_pos)

# Weapon-host aim: the player aims its hosted Weapon down the camera's centre ray (where
# the crosshair points), so hitscan + spread match what it sees. Overrides the Character
# defaults (which fire straight forward from the body). camera_effects is the active
# Camera3D, so this reproduces exactly what Attack used to compute from the passed camera.
func get_aim_origin() -> Vector3:
	return camera_effects.project_ray_origin(get_viewport().get_visible_rect().size / 2.0)

func get_aim_direction() -> Vector3:
	return camera_effects.project_ray_normal(get_viewport().get_visible_rect().size / 2.0)

func get_aim_basis() -> Basis:
	return camera_effects.global_transform.basis

@export_group("NPC reactions")
## A gunshot within this of a calm (non-hostile, out-of-combat) talker makes them remark on the reckless
## discharge, New Vegas style (#2).
@export var reckless_remark_radius: float = 12.0
## How often (s) to check whether you're aiming at a friendly/ally, who then comments (#3).
@export var aim_remark_interval: float = 0.35
## Max distance the aim-at-friendly check reaches.
@export var aim_remark_range: float = 25.0

const RECKLESS_LINES: Array[String] = ["Watch where you're firing!", "Hey! Careful with that thing!", "Easy on the trigger!", "Whoa — mind where you point that!"]
const AIM_LINES: Array[String] = ["Hey, point that somewhere else.", "Watch where you're aiming.", "I'd lower that if I were you.", "Easy there, friend."]

var _aim_remark_timer: float = 0.0

@export_group("Low HP feedback")
## HP fraction at/above which there's NO vignette/desaturation; below it the effect ramps in (so it's
## visible as soon as you take real damage, not only near death) to full at 0 HP.
@export var low_hp_start_frac: float = 0.85
## HP fraction at/below which the HEARTBEAT plays. 1.0 = it starts as soon as you take ANY damage (drop
## below full HP), then beats faster + louder the lower your HP falls (see _update_low_hp).
@export var heartbeat_start_frac: float = 1.0
## The heartbeat sound — a real heartbeat asset, played at natural pitch (the rate + volume convey the
## damage, not pitch).
@export var heartbeat_sound: AudioStream = preload("res://assets/audio/heartbeat.mp3")
@export var heartbeat_interval_slow: float = 1.1   ## seconds between beats at the threshold
@export var heartbeat_interval_fast: float = 0.45  ## seconds between beats near death
@export var heartbeat_db_min: float = -16.0        ## beat volume at the threshold
@export var heartbeat_db_max: float = 2.0          ## beat volume near death

var _heartbeat: AudioStreamPlayer
var _heartbeat_timer: float = 0.0

var _last_combat_msec: int = 0  ## last time we fired / took damage / were aimed at — keeps the gun up in combat

## Mark "in combat now" so the view model stays raised (GunPose reads seconds_since_combat) for a beat.
func note_combat() -> void:
	_last_combat_msec = Time.get_ticks_msec()

func seconds_since_combat() -> float:
	return float(Time.get_ticks_msec() - _last_combat_msec) / 1000.0

## True while scaling a wall (wall-climb). The camera + view model read this to treat the climb as
## "walking" — running the walk-bob and the grounded FOV rules instead of the airborne/rising ones.
func is_climbing() -> bool:
	return _climbing

## Project the blob shadow onto the WALL while climbing, easing back to the ground otherwise. The decal
## casts along its local -Y, so to land it on the wall we build a basis whose +Y is the wall normal (-Y
## points INTO the wall) and blend the decal's GLOBAL transform from its ground pose to that. Grounded, we
## restore the authored LOCAL pose so it tracks the body with no lag. Null-safe (no Shadow decal -> no-op).
func _update_wall_shadow(delta: float) -> void:
	if _shadow == null:
		return
	var want_wall := _climbing and is_on_wall()
	_shadow_wall_blend = move_toward(_shadow_wall_blend, 1.0 if want_wall else 0.0, SHADOW_LERP_SPEED * delta)
	if _shadow_wall_blend <= 0.001:
		_shadow.transform = _shadow_rest_local  # fully grounded: track the body exactly via the local pose
		return
	var ground_global := global_transform * _shadow_rest_local
	var wall_global := ground_global
	if is_on_wall():
		var up := get_wall_normal().normalized()
		var up_ref := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
		var x := up_ref.cross(up).normalized()
		var z := up.cross(x).normalized()
		var s := _shadow_rest_local.basis  # keep the authored decal scale (its column lengths)
		var wall_basis := Basis(x * s.x.length(), up * s.y.length(), z * s.z.length())
		wall_global = Transform3D(wall_basis, global_position - up * 0.1)  # sit on the wall, by the body
	_shadow.global_transform = ground_global.interpolate_with(wall_global, _shadow_wall_blend)

func on_weapon_fired(weapon: WeaponData) -> void:
	note_combat()
	if screen_shake:
		screen_shake.shake(weapon.screen_shake_amount)
	# Real guns are loud; melee (infinite-ammo) swings + the scoped airdash stay silent.
	if weapon.max_ammo > 0 and _noise:
		_noise.gunfire()  # loud — nearby enemies hear the shot
	# NOTE: the reckless-fire bystander remark (#2) is NOT fired here — it waits for on_shot_resolved(),
	# once we know whether the shot connected with an NPC (a hit isn't "reckless discharge").

## Post-shot outcome hook (WeaponHost): the reckless-fire bystander remark (#2) fires here, AFTER the shot's
## trace resolved — and only for a real (loud) gun whose shot did NOT connect with another NPC. A shot that
## hit or killed someone isn't careless "reckless discharge", so nearby NPCs stay quiet about the gun noise
## (they react to the fight through the normal combat path instead).
func on_shot_resolved(weapon: WeaponData, hit_npc: bool) -> void:
	if weapon.max_ammo > 0 and not hit_npc:
		_remark_reckless_fire()

func get_hit_flash() -> Node3D:
	return white_flash

func on_weapon_launched(weapon: WeaponData) -> void:
	if screen_shake:
		screen_shake.shake(weapon.launch_screen_shake)
	camera_effects.fov_punch()

## #2: after a gunshot, the nearest calm (non-hostile, out-of-combat) talker within reckless_remark_radius
## remarks on the reckless discharge. Just the closest, so a crowd doesn't all pipe up at once.
func _remark_reckless_fire() -> void:
	var nearest: NPC = null
	var best := reckless_remark_radius * reckless_remark_radius
	for n in get_tree().get_nodes_in_group(&"npc"):
		if not (n is NPC):
			continue
		var npc := n as NPC
		if npc.is_hostile() or npc.is_in_combat():
			continue
		var d := global_position.distance_squared_to(npc.global_position)
		if d < best:
			best = d
			nearest = npc
	if nearest != null:
		nearest.react_remark(RECKLESS_LINES)

## #3: every aim_remark_interval, if the crosshair is on a non-hostile NPC (friendly or ally), it comments.
## react_remark self-filters (non-hostile, out-of-combat, has a Talkable), so aiming at an enemy stays silent.
func _check_aim_remark(delta: float) -> void:
	# Only comment when the player is AIMING DOWN SIGHTS (holding Zoom), not merely looking their way.
	if not Input.is_action_pressed("Zoom"):
		_aim_remark_timer = 0.0  # reset so it fires promptly the moment you DO aim at someone
		return
	_aim_remark_timer -= delta
	if _aim_remark_timer > 0.0:
		return
	_aim_remark_timer = aim_remark_interval
	var world := get_world_3d()
	if world == null:
		return
	var from := get_aim_origin()
	var to := from + get_aim_direction() * aim_remark_range
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [get_rid()]
	var hit := world.direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return
	var npc := hit.get("collider") as NPC
	if npc != null:
		npc.react_remark(AIM_LINES)

func _update_night_vision(delta: float) -> void:
	# Toggle the night-vision look (NightVision action, N by default) and fade it
	# in/out by driving the post-process material's `night_vision` uniform.
	if Input.is_action_just_pressed("NightVision"):
		_nv_on = not _nv_on
	if not _nv_rect:
		return
	var mat := _nv_rect.material as ShaderMaterial
	if not mat:
		return
	var target := 1.0 if _nv_on else 0.0
	_nv_t = lerpf(_nv_t, target, 1.0 - exp(-NIGHT_VISION_FADE_RATE * delta))
	mat.set_shader_parameter("night_vision", _nv_t)

## Low-HP feedback (#11): drive the post-process `low_hp` uniform (black vignette + desaturation) and a
## heartbeat that beats faster + louder as HP falls below low_hp_start_frac. Silent + cleared above the
## threshold and when dead.
func _update_low_hp(delta: float) -> void:
	var frac := clampf(float(hp) / maxf(max_hp, 1.0), 0.0, 1.0)
	# Vignette + desaturation scale from low_hp_start_frac, so they show as soon as you're hurt.
	var vis_intensity := 0.0
	if low_hp_start_frac > 0.0:
		vis_intensity = clampf((low_hp_start_frac - frac) / low_hp_start_frac, 0.0, 1.0)
	if _nv_rect:
		var mat := _nv_rect.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("low_hp", vis_intensity)
			mat.set_shader_parameter("colorblind_mode", Settings.colorblind_mode)
	# Heartbeat is a near-death cue with its OWN, lower threshold — faster + louder the lower you go.
	var hb_intensity := 0.0
	if heartbeat_start_frac > 0.0:
		hb_intensity = clampf((heartbeat_start_frac - frac) / heartbeat_start_frac, 0.0, 1.0)
	if hb_intensity <= 0.05 or hp <= 0:
		_heartbeat_timer = 0.0  # reset so the first beat fires immediately when HP next drops low
		return
	_heartbeat_timer -= delta
	if _heartbeat_timer <= 0.0:
		_heartbeat_timer = lerpf(heartbeat_interval_slow, heartbeat_interval_fast, hb_intensity)
		if _heartbeat and _heartbeat.stream:
			_heartbeat.volume_db = lerpf(heartbeat_db_min, heartbeat_db_max, hb_intensity)
			_heartbeat.pitch_scale = 1.0  # natural pitch — the real asset already sounds like a heartbeat
			_heartbeat.play()

## Punchy "got hit" feedback — forwards to the HurtFeedback component (the slow-mo + screen-drain +
## bus muffle). Called from take_damage on a non-lethal hit. Off-tree (_hurt null) this no-ops, matching
## the monolith (FreezeFrame/tween/bus writes are skipped when the component never built).
func _on_head_crippled(_attacker: Node = null) -> void:
	_trigger_hurt()  # locational head cripple — pulse the hurt feedback so a concussion reads on screen
	notify_toast("Your head is crippled!", CRIPPLE_TOAST_COLOR)

## Min gap (ms) between sneak-result toasts so a burst / multi-pellet shot shows one line, not a stack.
const SNEAK_TOAST_COOLDOWN_MS: int = 1200
const SNEAK_HIT_COLOR := Color(0.4, 1.0, 0.45)      ## "Sneak Attack!" — green
const CRIPPLE_TOAST_COLOR := Color(1.0, 0.42, 0.38) ## limb-cripple toast — red
var _last_sneak_toast_msec: int = -100000

## Push a one-off HUD toast (top-left) via the UI layer. Player-facing notifications (sneak result, limb
## cripples, ...) route through here. No-op off-tree (no UI).
func notify_toast(text: String, color: Color) -> void:
	if ui:
		ui.push_toast(text, color)

## Toast a SUCCESSFUL sneak attack (target was off-guard); a normal hit shows nothing. Throttled by
## SNEAK_TOAST_COOLDOWN_MS so a burst / multi-pellet shot shows ONE line. Called per player hit on a
## Character from attack.gd.
func notify_sneak_result(was_sneak: bool) -> void:
	if not was_sneak:
		return  # only a successful sneak is worth a toast — a normal hit says nothing
	var now := Time.get_ticks_msec()
	if now - _last_sneak_toast_msec < SNEAK_TOAST_COOLDOWN_MS:
		return
	_last_sneak_toast_msec = now
	notify_toast("Sneak Attack!", SNEAK_HIT_COLOR)

## Drive the FNV-style look-at hover readout: when the player's aim enters/leaves a talkable, show its name
## on the HUD (tinted green for a friendly NPC) and, for an NPC, have it speak a greeting. `handler` is the
## talk handler under the crosshair (Talkable / DialogueNPC), or null when looking at nothing. Called by the
## interaction ray ONLY when the looked-at target actually changes (so the greeting fires once per look).
func on_look_target_changed(handler: Node) -> void:
	if handler == null or not handler.has_method(&"look_name"):
		if ui:
			ui.set_look_name("", Color.WHITE)
		return
	var label: String = handler.look_name()
	var col := Color(0.92, 0.92, 0.95)  # neutral / inanimate default
	var npc: NPC = handler.host_npc() if handler.has_method(&"host_npc") else null
	if npc != null:
		if npc.resolved_disposition() == Disposition.Kind.FRIENDLY:
			col = CBPalette.friendly()
		npc.greet()  # FNV-style hover greeting (cooldown-gated, non-hostile/idle only)
	if ui:
		ui.set_look_name(label, col)

func _trigger_hurt() -> void:
	if _hurt:
		_hurt.trigger()

## Air-dash recharge cue: a quick white screen-flash (via PlayerHud) + a chirp the instant the dash is
## available again (fired from Attack.air_dash_recharged on landing).
func _on_air_dash_recharged() -> void:
	if _hud:
		_hud.flash_dash()
	if air_dash_recharge_sfx:
		AudioManager.play_2d_sfx(air_dash_recharge_sfx)

const EDGE_MIN_SPEED: float = 0.2         ## below this gap-ward speed there's nothing meaningful to brake — skip the probe

## Quake-style edge friction — makes it harder to slide off a ledge. Detect whether the player is
## hanging over a ledge in `gap_dir` (a horizontal, normalized velocity-ward direction) and, if so,
## return the EXTRA friction lerp applied to the gap-ward velocity component this frame; 0.0 when not
## near an edge (caller then leaves movement unchanged). The probe math lives in MovementHelpers (and
## carries the EDGE_PROBE_AHEAD / EDGE_FLOOR_PROBE / EDGE_DROP_TOLERANCE / EDGE_FRICTION_MULT tuning);
## this thin wrapper keeps the call site in _physics_process unchanged.
func _edge_friction_t(gap_dir: Vector3, t_ground: float) -> float:
	return MovementHelpers.extra_brake_t(self, gap_dir, t_ground)

func _physics_process(delta: float) -> void:
	# Frozen during a conversation (cinematic, like the NPC) so the player can't move OR fall —
	# they hold in place while the world keeps running. The camera-focus + NPC-turn tweens still
	# animate, since those run on the SceneTree rather than in this _physics_process.
	if DialogueManager.is_active():
		velocity = Vector3.ZERO
		input_dir = Vector2.ZERO  # also zero input so CameraEffects reads no stale strafe (FOV kick / tilt)
		return
	coyote_time.tick(delta)
	gravity(delta)
	_update_night_vision(delta)
	_update_low_hp(delta)

	input_dir = Input.get_vector("left", "right", "forward", "backward")
	if OptionsMenu.is_open() or InventoryScreen.is_open() or LootScreen.is_open():
		input_dir = Vector2.ZERO  # a modal UI is open (non-pausing, Dark Souls): stand idle but keep gravity + stay vulnerable
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var bhop_engaged: bool = false
	var jumped_now := false
	if coyote_time.can_jump() and jump_buffer.wants_jump() and not OptionsMenu.is_open() and not InventoryScreen.is_open() and not LootScreen.is_open():
		velocity.y = GameSettings.player_movement.jump_velocity
		jump_sfx.play()
		spawn_dust(GameSettings.effects.dust_jump_intensity)
		coyote_time.consume()
		jump_buffer.consume()
		jumped_now = true
		if _sliding:
			# Slide-jump: fling forward scaled by your slide speed at jump time, via
			# the decaying blast impulse (like the dash) so the launch survives into
			# the air instead of being bled off by the movement lerp. Ends the slide.
			explosion_velocity += _slide_dir * _slide_speed * slide_jump_mult
			_end_slide()
		bhop_engaged = bunnyhop.try_engage(input_dir.y < 0)

	# Variable jump height: a tap gives a low hop, a hold rides the full arc. Normally we cut the rising
	# velocity on the jump's RELEASE (the elif). But a buffer-queued jump fires on LANDING, by which point
	# a TAP's release has already passed — so just_released never catches it and the tap would rocket to
	# full height. Fix: on the exact frame the jump fires, decide by whether the key is still HELD; not
	# held means it was a tap (buffered OR same-frame), so cut immediately. The elif covers held-then-let-go.
	# The if/elif are mutually exclusive so a same-frame grounded tap can't get cut twice.
	if jumped_now:
		if not Input.is_action_pressed("jump"):
			velocity.y *= jump_cut_factor
	elif Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= jump_cut_factor

	target_speed = GameSettings.player_movement.max_speed
	if input_dir.y > 0:
		target_speed = GameSettings.player_movement.max_speed * GameSettings.player_movement.backward_mult
	elif abs(input_dir.x) > 0 and input_dir.y == 0:
		target_speed = GameSettings.player_movement.max_speed * GameSettings.player_movement.strafe_mult
	target_speed = lerpf(target_speed, target_speed * GameSettings.player_crouch.speed_mult, crouch.crouch_t)
	if _is_scoped:
		target_speed *= GameSettings.weapon_general.scope_speed_mult
	# A heavy weapon slows you WHILE IT'S DRAWN (WeaponData.move_speed_multiplier); holstered = full
	# speed, FNV-style — mirrors the NPC's _current_move_speed gating on the same holster state.
	if weapon_system and weapon_system.attack and not weapon_system.attack.holstered and weapon_system.equipped_weapon:
		target_speed *= weapon_system.equipped_weapon.move_speed_multiplier
	target_speed *= limb_move_multiplier()  # crippled legs limp (locational damage)

	var ground_ratio := GameSettings.player_movement.smoothing
	var air_ratio := GameSettings.player_movement.smoothing / GameSettings.player_movement.air_smoothing_divisor
	var fps_factor := delta * GameSettings.player_movement.smoothing_reference_fps
	var t_ground := 1.0 - pow(1.0 - ground_ratio, fps_factor)
	var t_air := 1.0 - pow(1.0 - air_ratio, fps_factor)
	if _sliding:
		_update_slide(delta, direction)
	elif is_on_floor():
		if direction:
			current_speed = lerpf(current_speed, target_speed, t_ground)
		else:
			current_speed = lerpf(current_speed, 0.0, t_ground)
		velocity.x = lerpf(velocity.x, direction.x * current_speed, t_ground)
		velocity.z = lerpf(velocity.z, direction.z * current_speed, t_ground)
		# Quake edge friction: if we're sliding toward a ledge, brake the gap-ward velocity
		# component extra hard so you stick to the surface instead of skating off. Only kicks in
		# while actually moving toward an unsupported edge (the probe); flat ground is unchanged.
		var horiz := Vector3(velocity.x, 0.0, velocity.z)
		var horiz_speed := horiz.length()
		if horiz_speed > EDGE_MIN_SPEED:
			var gap_dir := horiz / horiz_speed
			var edge_t := _edge_friction_t(gap_dir, t_ground)
			if edge_t > 0.0:
				# Bleed the gap-ward speed toward zero by the extra friction lerp (the probe ray runs
				# along this same direction, so the whole horizontal velocity is heading off the ledge).
				var along := horiz.dot(gap_dir)
				var braked := lerpf(along, 0.0, edge_t)
				velocity.x += gap_dir.x * (braked - along)
				velocity.z += gap_dir.z * (braked - along)
				current_speed = lerpf(current_speed, 0.0, edge_t)
		camera_effects.bob(velocity)
	else:
		velocity.x = lerpf(velocity.x, direction.x * current_speed, t_air)
		velocity.z = lerpf(velocity.z, direction.z * current_speed, t_air)

	if bhop_engaged:
		var bhop_speed := bunnyhop.get_target_speed()
		velocity.x = direction.x * bhop_speed
		velocity.z = direction.z * bhop_speed
		current_speed = bhop_speed

	apply_blast()

	# Wall climb: walk into a wall + hold jump to grip it. Push INTO the wall to climb up; just hold (no
	# forward input) to STOP and hang on it like you're standing on it. Releasing jump lets go. You can
	# only START a grip by pushing in, so brushing a wall while holding jump doesn't stick you (no item).
	var was_climbing := _climbing
	_climbing = false
	if is_on_wall() and Input.is_action_pressed(&"jump"):
		var wall_n := get_wall_normal()
		var pushing_in := direction.dot(-wall_n) > 0.1
		if pushing_in or was_climbing:
			_climbing = true
			velocity -= wall_n * maxf(velocity.dot(wall_n), 0.0)  # don't peel off (kill outward velocity)
			velocity -= wall_n * wall_grip_stick                  # press in a touch so we stay stuck
			# Vertical control keys off the FORWARD/BACK input ONLY, so strafing along the wall never makes
			# you rise: press W into the wall to climb up, hold S to climb down, strafe-only / idle just
			# holds. (The bug was using `pushing_in` — the full move dir into the wall — which a strafe with
			# any into-wall component satisfied, so strafing climbed up.)
			if pushing_in and input_dir.y < 0.0:
				velocity.y = wall_climb_speed
			elif input_dir.y > 0.0:
				velocity.y = -wall_climb_speed
			else:
				velocity.y = 0.0
			camera_effects.bob(velocity)  # treat the climb as walking — bob the camera (bob() reads is_climbing)
	elif was_climbing and Input.is_action_pressed(&"jump"):
		# Climbed clean off the top — little hop to pop over the lip and land on the ledge.
		velocity.y = maxf(velocity.y, climb_hop_up)
		velocity += direction * climb_hop_forward
		if jump_sfx:
			jump_sfx.play()

	# Swing the blob shadow onto the wall while climbing, back to the ground otherwise.
	_update_wall_shadow(delta)

	# Grapple yank — overrides the velocity we just built from input/gravity, before the move.
	if _grapple:
		_grapple.apply_pull(delta)

	var pre_landing_velocity := velocity.y
	var pre_velocity := velocity

	apply_velocity()

	# Body-impact reactions (ram damage / air thump / pinball bounce) run AFTER the move on the
	# PRE-move velocity — see RamReactor. Off-tree (_ram_reactor null) they're skipped, as in a test.
	if _ram_reactor:
		_ram_reactor.tick(delta, pre_velocity)

	if is_on_floor() and !_was_on_floor:
		var impact := clampf(-pre_landing_velocity / GameSettings.player_movement.landing_impact_divisor, 0.0, 1.0)
		var dampened_impact := impact * (1.0 - crouch.crouch_t)
		camera_effects.land(dampened_impact)
		if gun_mesh and impact > 0.0:
			gun_mesh.land(impact)
		if screen_shake and dampened_impact > 0.0:
			screen_shake.shake(dampened_impact * 1.5)
		if impact >= GameSettings.audio.land_sfx_min_impact_to_play:
			land_sfx.volume_db = _land_sfx_base_db - (1.0 - impact) * GameSettings.audio.land_sfx_volume_db_reduction
			land_sfx.pitch_scale = lerpf(
				_land_sfx_base_pitch + GameSettings.audio.land_sfx_pitch_spread,
				_land_sfx_base_pitch - GameSettings.audio.land_sfx_pitch_spread,
				impact
			)
			land_sfx.play()
		if impact >= GameSettings.effects.dust_land_min_impact_to_spawn:
			spawn_dust(GameSettings.effects.dust_land_base_intensity + impact * GameSettings.effects.dust_land_impact_bonus)
		_try_start_slide(pre_velocity)

	_was_on_floor = is_on_floor()

	_footstep_timer -= delta

	footstep_interval = GameSettings.player_movement.footstep_base_interval * (GameSettings.player_movement.max_speed / max(target_speed, 0.01))

	var on_foot := is_on_floor() and Vector2(velocity.x, velocity.z).length() > GameSettings.player_movement.footstep_min_horizontal_speed
	# Climb footsteps only while actually moving up/down the wall — a wall-hold (velocity.y == 0) is silent
	# like standing still (the into-wall grip push isn't real movement, so don't count it).
	var on_climb := _climbing and absf(velocity.y) > GameSettings.player_movement.footstep_min_horizontal_speed
	if (on_foot or on_climb) and not _sliding and _footstep_timer <= 0.0:
		walking_sfx.volume_db = lerpf(_walking_sfx_base_db, _walking_sfx_base_db + GameSettings.player_crouch.quiet_footstep_db, crouch.crouch_t)
		walking_sfx.play()
		_footstep_timer = footstep_interval

	_update_falling_air(delta)
	_update_noise(delta)
	_check_aim_remark(delta)  # #3: comment if the player is aiming at a friendly/ally
	if _slide_sfx:
		_slide_sfx.volume_db = lerpf(_slide_sfx.volume_db, 0.0 if _sliding else -80.0, 1.0 - exp(-12.0 * delta))


## How far the player's noise currently carries — forwards to the NoiseEmitter component, which writes
## our noise_radius (the value enemy Perception.can_hear() reads). Off-tree (_noise null) this no-ops;
## noise_radius then stays at its 0.0 init, matching a freshly built bare instance.
func _update_noise(delta: float) -> void:
	if _noise:
		_noise.tick(delta)


func _try_start_slide(pre_velocity: Vector3) -> void:
	# Begin a slide if we just touched down fast while holding crouch. Uses the
	# pre-move velocity so the landing frame's preserved momentum is the seed.
	if _sliding:
		return
	if not Input.is_action_pressed("Crouch"):
		return
	# Steering input ends a slide on the very next frame (see _update_slide), so starting one
	# while a movement key is held just plays then instantly stops the slide sfx — a repeated
	# click. Don't start a slide unless you're letting momentum carry you (no move input).
	if input_dir.length() > 0.1:
		return
	var speed := Vector2(pre_velocity.x, pre_velocity.z).length()
	if speed < slide_min_speed:
		return
	_sliding = true
	_slide_dir = Vector3(pre_velocity.x, 0.0, pre_velocity.z).normalized()
	_slide_speed = minf(speed * slide_boost, slide_max_speed)
	_slide_dust_timer = 0.0

func _update_slide(delta: float, direction: Vector3) -> void:
	# Pressing any movement key overrides the slide and hands control straight
	# back to normal movement. The slide also ends when it decays to walking
	# pace, you release crouch, or you leave the ground. The last slide velocity
	# stays in `velocity` either way, so momentum carries out smoothly.
	if direction.length() > 0.1 or _slide_speed <= slide_end_speed or not Input.is_action_pressed("Crouch") or not is_on_floor():
		_end_slide()
		return
	_slide_speed = move_toward(_slide_speed, 0.0, slide_friction * delta)
	velocity.x = _slide_dir.x * _slide_speed
	velocity.z = _slide_dir.z * _slide_speed
	current_speed = _slide_speed
	# Kick up dust on an interval while sliding.
	_slide_dust_timer -= delta
	if _slide_dust_timer <= 0.0:
		spawn_dust(slide_dust_intensity)
		_slide_dust_timer = slide_dust_interval

func _end_slide() -> void:
	_sliding = false


func _update_falling_air(delta: float) -> void:
	if not falling_air_sfx:
		return
	# Wind swell from vertical speed in EITHER direction: the terminal-velocity rush
	# of a fall, but ALSO rocketing UP (blast-launch / rocket-jump). Reuses the same
	# fall-speed thresholds — a normal jump (~4.5 m/s) barely clears the min so it
	# stays near-silent, while a fast launch roars.
	var vertical_speed: float = absf(velocity.y)
	var fall_span := GameSettings.audio.falling_air_max_fall_speed - GameSettings.audio.falling_air_min_fall_speed
	var t_fall := 0.0
	if fall_span > 0.0:
		t_fall = clampf((vertical_speed - GameSettings.audio.falling_air_min_fall_speed) / fall_span, 0.0, 1.0)
	# Same swell from raw horizontal speed, so blitzing around (bhop / dash /
	# blast launch) rushes like a fall too. Skipped while sliding, which drives
	# its own looping wind player (_slide_sfx) and would otherwise double up.
	var t_move := 0.0
	if not _sliding:
		var move_speed := Vector2(velocity.x, velocity.z).length()
		var move_span := GameSettings.audio.falling_air_max_move_speed - GameSettings.audio.falling_air_min_move_speed
		if move_span > 0.0:
			t_move = clampf((move_speed - GameSettings.audio.falling_air_min_move_speed) / move_span, 0.0, 1.0)
	var t := maxf(t_fall, t_move)
	var target_db := lerpf(GameSettings.audio.falling_air_min_db, GameSettings.audio.falling_air_max_db, t)
	if t > GameSettings.audio.falling_air_audible_t:
		if not falling_air_sfx.playing and falling_air_sfx.stream:
			falling_air_sfx.play()
	elif falling_air_sfx.playing and is_on_floor():
		falling_air_sfx.stop()
	var smooth := 1.0 - exp(-GameSettings.audio.falling_air_fade_rate * delta)
	falling_air_sfx.volume_db = lerpf(falling_air_sfx.volume_db, target_db, smooth)
	# Drive the speed vignette (PlayerHud) off the SAME speed intensity, smoothed the same way, so the
	# white air-streaks swell and fade in lockstep with the wind.
	if _hud:
		_hud.drive_speed_lines(t, smooth)


func _on_mouse_input_rotate(_amt: Vector2) -> void:
	rotate_y(_amt.y)

## Floor-ish surface-normal cutoff for the pinball bounce (kept here: a unit test reads it off a bare
## instance). RamReactor references it as Player.RAM_BOUNCE_FLOOR_DOT.
const RAM_BOUNCE_FLOOR_DOT: float = 0.7

## Pinball-style rebound facade — the body lives in RamReactor (and is driven from its tick alongside
## the ram-damage + air-thump checks). Kept as a NAMED method on the Player so the smoke suite's source
## grep for "func _check_bounce" still finds it; off-tree (_ram_reactor null) it no-ops as before.
func _check_bounce(delta: float, pre_velocity: Vector3) -> void:
	if _ram_reactor:
		_ram_reactor._check_bounce(delta, pre_velocity)

func on_nearby_death(distance: float) -> void:
	if distance <= GameSettings.screen_shake.death_shake_range:
		FreezeFrame.freeze(0.01, 0.1, 0.02)
	if distance <= GameSettings.effects.blood_splatter_range and ui and ui.blood_splatter:
		var splat_t := 1.0 - clampf(distance / GameSettings.effects.blood_splatter_range, 0.0, 1.0)
		ui.blood_splatter.splash(splat_t)
	if distance <= GameSettings.screen_shake.death_shake_range and screen_shake:
		var shake_t := 1.0 - clampf(distance / GameSettings.screen_shake.death_shake_range, 0.0, 1.0)
		screen_shake.shake(shake_t * GameSettings.screen_shake.death_shake_amount)

const RESPAWN_DELAY: float = 1.0
## Death cinematic (Player): on death the world eases into slow-mo while the camera slowly rolls onto its
## side (keeling over) and the screen drains to black & white then fades to black — THEN, after a beat
## (RESPAWN_DELAY) on the black screen, the scene reloads.
const DEATH_SEQUENCE_TIME: float = 1.6   ## wall-clock seconds of the keel-over / drain / fade cinematic
const DEATH_TIME_SCALE: float = 0.3      ## slow-mo target the world eases down to as you die
const DEATH_CAMERA_ROLL: float = 1.45    ## radians the camera rolls onto its side (~83°), the keel-over
var _dying: bool = false
var _death_cam_base_z: float = 0.0       ## camera roll at the instant death starts; the keel-over adds onto it

func take_damage(amount: float, was_crit: bool = false, attacker: Node = null, hit_pos: Vector3 = Vector3.INF) -> void:
	if _dying:
		return
	note_combat()  # taking fire is combat — keep the weapon up
	# Match Character.take_damage's signature (GDScript requires overrides to match the parent) and
	# forward hit_pos so the player's own locational/limb damage + crippling apply.
	super.take_damage(amount, was_crit, attacker, hit_pos)
	if _hud:
		_hud.flash_hurt()  # whole-screen red flash on every hit (lethal too — reads as the killing blow)
	if not _dying:
		_trigger_hurt()

## Ping the SINGLE aim radial toward `world_pos` (the shooter) when we actually take a hit — forwards
## to PlayerHud (see PlayerHud.indicate_damage_from for why this fills the post-shot gap). Kept as a
## NAME here because attack.gd flashes the directional arc via player.indicate_damage_from. Off-tree
## (_hud null) it no-ops, as the monolith did when its overlays never built.
func indicate_damage_from(world_pos: Vector3, source: Object = null) -> void:
	if _hud:
		_hud.indicate_damage_from(world_pos, source)

## Show the red "being aimed at" radial + distant-sniper glint toward `source` — forwards to PlayerHud.
## Kept as a NAME here because the enemy aim telegraph calls player.indicate_aimed_from.
func indicate_aimed_from(source: Object, world_pos: Vector3, charge: float, damage: float = 0.0, warning: bool = false, clear_shot: bool = true) -> void:
	note_combat()  # an enemy is drawing a bead on us — that's combat, keep the gun up
	if _hud:
		_hud.indicate_aimed_from(source, world_pos, charge, damage, warning, clear_shot)

## The player's hit-confirm "ding" + crosshair hitmarker — the body lives in PlayerHud. These consts
## stay on the Player because PlayerHud references them as Player.HIT_SFX / Player.HEADSHOT_PITCH_MULT.
## HIT_SFX is a dedicated 2D hitsound SEPARATE from the weapons' impact sounds; it fires only via
## on_dealt_hit (the player's "I landed a hit" callback, which NPCs override to a no-op), so an
## NPC-vs-NPC trade can never proc the player's hitsound.
const HIT_SFX := preload("res://assets/audio/freesound_community-ding-101377.mp3")
## Headshot drops the ding's pitch DOWN (deeper, meatier) rather than up — sub-1.0 factor.
const HEADSHOT_PITCH_MULT := 0.7

## Flash the crosshair hitmarker AND play the hit-confirm ding — forwards to PlayerHud. Kept as a NAME
## here because a landed shot/explosion calls player.on_dealt_hit. Off-tree (_hud null) it no-ops.
func on_dealt_hit(headshot := false, hp_frac := 1.0) -> void:
	if _hud:
		_hud.on_dealt_hit(headshot, hp_frac)

func die() -> void:
	if _dying:
		return
	_dying = true
	# Clear any in-progress hurt feedback so the ducked master bus doesn't bleed into the scene
	# reload — the bus is global, a reload won't reset it, and the next life would read it as base.
	if _hurt:
		_hurt.clear()
	died.emit()
	# Freeze the player but keep effects (gore particles, blood, sound) running so the death is visible
	# through the cinematic before the scene reloads.
	set_physics_process(false)
	_run_death_sequence()

## The player-death cinematic: ease into slow-mo, slowly roll the camera onto its side (keeling over) as
## the screen drains to black & white and fades to black, hold a beat on black, then reload. Driven by ONE
## tween in WALL-CLOCK time (ignore_time_scale) so it finishes on schedule even as it slows the world;
## _death_step maps the tween's 0..1 progress onto each effect. Off-tree it just reloads directly.
func _run_death_sequence() -> void:
	if not is_inside_tree():
		_restart_scene()
		return
	# Take the camera off its per-frame driver so the keel-over roll isn't fought (CameraEffects writes
	# rotation.z + position every frame).
	if camera_effects:
		camera_effects.set_process(false)
		_death_cam_base_z = camera_effects.rotation.z
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_method(_death_step, 0.0, 1.0, DEATH_SEQUENCE_TIME)
	tw.tween_interval(RESPAWN_DELAY)  # hold on the fully-black screen a beat before reloading
	tw.tween_callback(_restart_scene)

## One frame of the death cinematic: `t` runs 0..1 over DEATH_SEQUENCE_TIME (wall-clock).
func _death_step(t: float) -> void:
	# Slow-mo: ease the world down over the first half of the cinematic (accessibility gate respected).
	if GameSettings.allow_timescale_changes:
		Engine.time_scale = lerpf(1.0, DEATH_TIME_SCALE, clampf(t / 0.5, 0.0, 1.0))
	# Keel over: roll the camera onto its side with an ease-out (tips fast, then settles).
	if camera_effects:
		var roll_t := 1.0 - (1.0 - t) * (1.0 - t)
		camera_effects.rotation.z = _death_cam_base_z + DEATH_CAMERA_ROLL * roll_t
	# Black & white over the first 40%, then fade the whole frame to black over the last 60%.
	if _nv_rect:
		var mat := _nv_rect.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("death_bw", clampf(t / 0.4, 0.0, 1.0))
			mat.set_shader_parameter("death_fade", clampf((t - 0.4) / 0.6, 0.0, 1.0))

func _restart_scene() -> void:
	# Restore globals the cinematic touched BEFORE reloading: Engine.time_scale is global and a plain
	# reload won't reset it. The death_bw / death_fade uniforms are cleared on the fresh player's _ready
	# (_reset_screen_post_process) — the shader sub-resource is reused from the cached PackedScene, so a
	# reload alone leaves it dirty (this was the "respawned to a black screen" bug).
	Engine.time_scale = 1.0
	if not is_inside_tree():
		return
	get_tree().reload_current_scene()

## Clear the screen post-process back to "normal" on spawn: the death cinematic's full grayscale +
## fade-to-black and any leftover hurt drain, plus the global slow-mo. Driven uniforms (low_hp, night
## vision) re-settle on their own each frame, but the death ones are only written during a death, so a
## reload after dying would otherwise keep the screen black/gray.
func _reset_screen_post_process() -> void:
	Engine.time_scale = 1.0
	if not _nv_rect:
		return
	var mat := _nv_rect.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("death_bw", 0.0)
	mat.set_shader_parameter("death_fade", 0.0)
	mat.set_shader_parameter("hurt", 0.0)
