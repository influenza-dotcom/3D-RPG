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

var _was_on_floor: bool = false
var input_dir: Vector2 = Vector2.ZERO
var _ram_cooldown: float = 0.0
var _thump_cooldown: float = 0.0
var _bounce_cooldown: float = 0.0

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
var _hurt_tween: Tween
var _hurt_lpf: AudioEffectLowPassFilter

var _sliding: bool = false
var _slide_dir: Vector3 = Vector3.ZERO
var _slide_speed: float = 0.0
var _slide_dust_timer: float = 0.0
var _slide_sfx: AudioStreamPlayer
var _damage_indicators: DamageIndicators
var _aim_indicators: AimIndicators
# SniperGlints HUD overlay (screen-space flare over distant aimers; stays visible while scoped). Loaded
# by PATH at runtime + left untyped so player.gd parses even before the editor registers the new
# class_name in its global cache (otherwise: "Could not find type SniperGlints").
const SNIPER_GLINTS_SCRIPT := preload("res://scripts/ui/sniper_glints.gd")
var _sniper_glints
var _hitmarker: Hitmarker

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
## Wall climb: vertical speed while scaling a wall (walk into any wall + hold jump). Always usable.
@export var wall_climb_speed: float = 4.5
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
# Current audible radius (read by enemy Perception.can_hear); 0 = silent.
var noise_radius: float = 0.0
var _gunfire_noise: float = 0.0

var target_speed: float = GameSettings.player_movement.max_speed

var _walking_sfx_base_db: float
var _land_sfx_base_db: float
var _land_sfx_base_pitch: float
var _is_scoped: bool = false
const SPEED_LINES_SHADER = preload("res://resources/shaders/speed_lines.gdshader")
var _speed_lines: ColorRect  ## white speed-vignette overlay; intensity driven by movement speed
var _dash_flash: ColorRect   ## brief white full-screen flash fired when the air-dash recharges
## SFX chirped when the air-dash becomes available again (placeholder ding — swap in the inspector).
@export var air_dash_recharge_sfx: AudioStream = preload("res://assets/audio/ding.mp3")
const DASH_FLASH_PEAK_ALPHA: float = 0.5  ## white-flash opacity at the instant of recharge
const DASH_FLASH_TIME: float = 0.18       ## flash fade-out duration
## Grapple config. The grapple is built in code, so its own exports aren't inspector-reachable — assign
## a GrappleHookResource (.tres) HERE on the Player and it's passed through on creation. Holds the rope
## texture/colour, the hook-tip sprite, the SFX, and the feel tuning. Null = the grapple's own defaults.
@export var grapple_resource: GrappleHookResource
var _grapple: GrappleHook    ## Cruelty-Squad grapple; pull applied in _physics_process
const FOCUS_DURATION: float = 0.4  ## seconds to swing the camera onto a dialogue target
const DIALOGUE_FRAME_HEIGHT: float = 3.0  ## world-space vertical extent the dialogue zoom frames
const DIALOGUE_MIN_FOV: float = 25.0      ## floor so distant targets don't zoom to a pinhole
var _holster_before_dialogue: bool = false  ## weapon holster state before a conversation, restored after
var _zoom_tween: Tween  ## drives the dialogue FOV zoom, timed to the letterbox bars

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
	_setup_hurt_lpf()
	_walking_sfx_base_db = walking_sfx.volume_db
	_land_sfx_base_db = land_sfx.volume_db
	_land_sfx_base_pitch = land_sfx.pitch_scale
	weapon_system.scope_in.scoped_in.connect(_on_scoped_in)
	weapon_system.attack.air_dash_recharged.connect(_on_air_dash_recharged)
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
	# Speed vignette: a fullscreen white-edge / air-streak overlay whose intensity tracks movement
	# speed. Added before the damage arcs + crosshair so those still draw on top of it.
	_speed_lines = ColorRect.new()
	var sl_mat := ShaderMaterial.new()
	sl_mat.shader = SPEED_LINES_SHADER
	sl_mat.set_shader_parameter("intensity", 0.0)
	_speed_lines.material = sl_mat
	_speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_speed_lines)
	_speed_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# White full-screen flash for the air-dash recharge cue; alpha is pulsed in _on_air_dash_recharged.
	_dash_flash = ColorRect.new()
	_dash_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	_dash_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_dash_flash)
	_dash_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_indicators = DamageIndicators.new()
	ui.add_child(_damage_indicators)
	_damage_indicators.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_indicators.camera = camera_effects
	_aim_indicators = AimIndicators.new()
	ui.add_child(_aim_indicators)
	_aim_indicators.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_aim_indicators.camera = camera_effects
	# Sniper glint overlay: a screen-space flare over distant aimers. On the HUD (so it draws on TOP of
	# the post-process and stays crisp) and NOT hidden while scoped — you scope IN to find the sniper.
	_sniper_glints = SNIPER_GLINTS_SCRIPT.new()
	ui.add_child(_sniper_glints)
	_sniper_glints.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sniper_glints.camera = camera_effects
	_hitmarker = Hitmarker.new()
	ui.add_child(_hitmarker)
	_hitmarker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Grapple hook: built in code (no scene node), wired to this body, the camera (aim) and the muzzle
	# (rope origin). The pull itself runs in _physics_process below.
	_grapple = GrappleHook.new()
	# Hand over the config BEFORE add_child so the grapple's _ready() builds the rope + hook sprite from
	# it (assigning after would miss the one-time material/sprite build).
	_grapple.config = grapple_resource
	add_child(_grapple)
	_grapple.setup(self, camera_effects, grappling)
	# Holster: hide the gun mesh whenever Attack reports holstered (hold-R toggle / dialogue).
	weapon_system.attack.holster_changed.connect(_on_weapon_holstered)
	# Put the weapon away for conversations (restored on finish), reusing the holster.
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_finished.connect(_on_dialogue_finished)

## How far the music bus drops while scoped (slightly quieter, focused feel) + the fade time.
const SCOPE_MUSIC_BUS := &"music"
const SCOPE_MUSIC_DUCK_DB: float = -6.0
const SCOPE_MUSIC_DUCK_TIME: float = 0.25
var _scope_music_prior_db: float = 0.0
var _scope_music_ducked: bool = false
var _scope_music_tween: Tween

func _on_scoped_in(_tf: bool) -> void:
	_is_scoped = _tf
	# Is this the dedicated rifle scope (crisp scope = disables DoF)? Only the rifle gets the precise
	# crosshair dot + scope optics; a generic ADS weapon zooms with neither.
	var is_rifle := _tf and weapon_system != null and weapon_system.equipped_weapon != null \
			and weapon_system.equipped_weapon.disable_dof_while_scoped
	if ui:
		ui.set_scoped(is_rifle)  # crosshair dot ONLY for the rifle scope (other guns ADS without one)
	if _aim_indicators:
		_aim_indicators.visible = not _tf  # declutter the scope: hide the "being aimed at" radials while scoped
	if camera_effects and weapon_system and weapon_system.equipped_weapon:
		camera_effects.set_scope_dof(_tf, weapon_system.equipped_weapon.disable_dof_while_scoped)
	elif camera_effects:
		camera_effects.set_scope_dof(_tf, false)
	# Rifle scope optics (edge vignette + anamorphic lens flare) ride the same rifle-only gate.
	if ui:
		ui.set_scope_optics(is_rifle)
	# Music ducks a touch while scoped through ANY sight, restored on unscope.
	_duck_music_for_scope(_tf)

## Fade the music bus down slightly while scoped, back up on unscope (mirrors the dialogue duck). Safe
## to call repeatedly; captures the pre-duck level once so it always restores to the right baseline.
func _duck_music_for_scope(duck: bool) -> void:
	var bus := AudioServer.get_bus_index(SCOPE_MUSIC_BUS)
	if bus < 0:
		return
	if duck:
		if not _scope_music_ducked:
			_scope_music_prior_db = AudioServer.get_bus_volume_db(bus)
			_scope_music_ducked = true
	else:
		if not _scope_music_ducked:
			return
		_scope_music_ducked = false
	var target := (_scope_music_prior_db + SCOPE_MUSIC_DUCK_DB) if duck else _scope_music_prior_db
	if _scope_music_tween and _scope_music_tween.is_valid():
		_scope_music_tween.kill()
	_scope_music_tween = create_tween()
	_scope_music_tween.tween_method(_set_music_bus_db.bind(bus), AudioServer.get_bus_volume_db(bus), target, SCOPE_MUSIC_DUCK_TIME)

func _set_music_bus_db(db: float, bus: int) -> void:
	AudioServer.set_bus_volume_db(bus, db)

## Swing the gun down out of view (holster) or back up into the ready pose (unholster), FNV-style.
## Driven by Attack.holster_changed (hold-R toggle / dialogue).
func _on_weapon_holstered(on: bool) -> void:
	if on:
		# FNV-style de-escalation: holstering signals you mean no harm, so any NPC you PROVOKED into
		# hostility (a neutral/friendly you attacked) forgives you and stands down. Genuinely-hostile
		# factions (which were never provoked) are unaffected.
		for n in get_tree().get_nodes_in_group(&"npc"):
			if n.has_method(&"forgive_provoke"):
				n.forgive_provoke()
	if gun_mesh == null:
		return
	if on:
		gun_mesh.holster()
	else:
		gun_mesh.unholster()

## Put the weapon away for a conversation, remembering its prior state to restore afterward.
func _on_dialogue_started() -> void:
	if weapon_system and weapon_system.attack:
		_holster_before_dialogue = weapon_system.attack.holstered
		weapon_system.attack.set_holstered(true)

func _on_dialogue_finished() -> void:
	if weapon_system and weapon_system.attack:
		weapon_system.attack.set_holstered(_holster_before_dialogue)
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	if camera_effects:
		camera_effects.dialogue_fov = 0.0  # release the dialogue zoom; the FOV eases back to normal

## Smoothly aim the body yaw + head pitch at `target_pos` so the camera frames whatever the player
## is talking to. Called by the talk handler on conversation start; control returns afterward with
## the camera left facing the target.
func focus_camera_on(target_pos: Vector3) -> void:
	if camera_effects == null or head == null:
		return
	var to := target_pos - camera_effects.global_position
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-flat.x, -flat.z)  # body forward (-Z) faces the target horizontally
	var max_pitch := deg_to_rad(GameSettings.camera.pitch_max_deg)
	var target_pitch := clampf(atan2(to.y, flat.length()), -max_pitch, max_pitch)  # + = look up
	var yaw_target := rotation.y + wrapf(target_yaw - rotation.y, -PI, PI)  # shortest path
	var tw := create_tween().set_parallel()
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "rotation:y", yaw_target, FOCUS_DURATION)
	tw.tween_property(head, "rotation:x", target_pitch, FOCUS_DURATION)
	# Distance-based zoom (FNV-style): narrow the FOV so the target frames similarly whatever the
	# range — the farther away, the more zoom. CameraEffects eases toward this while it's set.
	var dist := to.length()
	if dist > 0.01:
		var zoom_fov := clampf(rad_to_deg(2.0 * atan((DIALOGUE_FRAME_HEIGHT * 0.5) / dist)), DIALOGUE_MIN_FOV, camera_effects.base_fov)
		# Zoom in over the SAME time the letterbox bars take to slide in, so they land together.
		camera_effects.dialogue_fov = camera_effects.base_fov  # start un-zoomed
		if _zoom_tween and _zoom_tween.is_valid():
			_zoom_tween.kill()
		_zoom_tween = create_tween()
		_zoom_tween.tween_property(camera_effects, "dialogue_fov", zoom_fov, DialogueManager.letterbox_time())

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

func on_weapon_fired(weapon: WeaponData) -> void:
	if screen_shake:
		screen_shake.shake(weapon.screen_shake_amount)
	# Real guns are loud; melee (infinite-ammo) swings + the scoped airdash stay silent.
	if weapon.max_ammo > 0:
		_gunfire_noise = noise_gunfire_radius  # loud — nearby enemies hear the shot

func get_hit_flash() -> Node3D:
	return white_flash

func on_weapon_launched(weapon: WeaponData) -> void:
	if screen_shake:
		screen_shake.shake(weapon.launch_screen_shake)
	camera_effects.fov_punch()

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

## Punchy "got hit" feedback: dip the global time-scale (via FreezeFrame), spike the screen-drain +
## audio duck, then ease them all back in REAL time (ignore_time_scale) so they recover in lockstep
## with the slow-mo lift instead of crawling at the slowed rate.
func _trigger_hurt() -> void:
	if screen_shake:
		screen_shake.shake(HURT_SHAKE)
	FreezeFrame.freeze(HURT_FREEZE_HOLD, HURT_FREEZE_SCALE, HURT_RECOVERY)
	if _hurt_tween and _hurt_tween.is_valid():
		_hurt_tween.kill()
	_set_hurt_amount(1.0)
	_hurt_tween = create_tween().set_ignore_time_scale(true)
	_hurt_tween.tween_interval(HURT_FREEZE_HOLD)
	_hurt_tween.tween_method(_set_hurt_amount, 1.0, 0.0, HURT_RECOVERY)

## Drive both the screen-drain uniform and the master-bus duck from one 0..1 amount.
func _set_hurt_amount(amount: float) -> void:
	if _nv_rect:
		var mat := _nv_rect.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("hurt", amount)
	if _hurt_lpf:
		# Exponential (log-frequency) sweep so the muffle eases off perceptually evenly.
		_hurt_lpf.cutoff_hz = HURT_LPF_CUTOFF * pow(HURT_LPF_CLEAR / HURT_LPF_CUTOFF, 1.0 - amount)

## Find (or add) a low-pass filter on the master bus for the hurt "muffle". Reused across scene
## reloads (the bus is global) so we don't stack a fresh filter each life; reset to clear on start.
func _setup_hurt_lpf() -> void:
	for i in AudioServer.get_bus_effect_count(MASTER_BUS):
		var fx := AudioServer.get_bus_effect(MASTER_BUS, i)
		if fx is AudioEffectLowPassFilter:
			_hurt_lpf = fx as AudioEffectLowPassFilter
			break
	if not _hurt_lpf:
		_hurt_lpf = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(MASTER_BUS, _hurt_lpf)
	_hurt_lpf.cutoff_hz = HURT_LPF_CLEAR

## Air-dash recharge cue: a quick white screen-flash + a chirp the instant the dash is available
## again (fired from Attack.air_dash_recharged on landing).
func _on_air_dash_recharged() -> void:
	if _dash_flash:
		_dash_flash.color.a = DASH_FLASH_PEAK_ALPHA
		var tw := create_tween().set_ignore_time_scale(true)
		tw.tween_property(_dash_flash, "color:a", 0.0, DASH_FLASH_TIME)
	if air_dash_recharge_sfx:
		AudioManager.play_2d_sfx(air_dash_recharge_sfx)

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

	input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var bhop_engaged: bool = false
	if coyote_time.can_jump() and jump_buffer.wants_jump():
		velocity.y = GameSettings.player_movement.jump_velocity
		jump_sfx.play()
		spawn_dust(GameSettings.effects.dust_jump_intensity)
		coyote_time.consume()
		jump_buffer.consume()
		if _sliding:
			# Slide-jump: fling forward scaled by your slide speed at jump time, via
			# the decaying blast impulse (like the dash) so the launch survives into
			# the air instead of being bled off by the movement lerp. Ends the slide.
			explosion_velocity += _slide_dir * _slide_speed * slide_jump_mult
			_end_slide()
		bhop_engaged = bunnyhop.try_engage(input_dir.y < 0)

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

	# Wall climb: walk into any wall and hold jump to scale it — no item required.
	var was_climbing := _climbing
	_climbing = false
	if is_on_wall() and Input.is_action_pressed(&"jump"):
		var wall_n := get_wall_normal()
		if direction.dot(-wall_n) > 0.1:
			velocity.y = wall_climb_speed
			velocity -= wall_n * maxf(velocity.dot(wall_n), 0.0)
			_climbing = true
	elif was_climbing and Input.is_action_pressed(&"jump"):
		# Climbed clean off the top — little hop to pop over the lip and land on the ledge.
		velocity.y = maxf(velocity.y, climb_hop_up)
		velocity += direction * climb_hop_forward
		if jump_sfx:
			jump_sfx.play()

	# Grapple yank — overrides the velocity we just built from input/gravity, before the move.
	if _grapple:
		_grapple.apply_pull(delta)

	var pre_landing_velocity := velocity.y
	var pre_velocity := velocity

	apply_velocity()

	_check_ram_damage(delta, pre_velocity)
	_check_air_thump(delta, pre_velocity)
	_check_bounce(delta, pre_velocity)

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
	if (on_foot or _climbing) and not _sliding and _footstep_timer <= 0.0:
		walking_sfx.volume_db = lerpf(_walking_sfx_base_db, _walking_sfx_base_db + GameSettings.player_crouch.quiet_footstep_db, crouch.crouch_t)
		walking_sfx.play()
		_footstep_timer = footstep_interval

	_update_falling_air(delta)
	_update_noise(delta)
	if _slide_sfx:
		_slide_sfx.volume_db = lerpf(_slide_sfx.volume_db, 0.0 if _sliding else -80.0, 1.0 - exp(-12.0 * delta))


## How far the player's noise currently carries (m): a decaying gunfire spike OR ground-speed
## footstep noise, whichever is louder. Crouch-walking and being airborne are silent. Enemy
## Perception.can_hear() reads noise_radius to decide whether it heard you.
func _update_noise(delta: float) -> void:
	_gunfire_noise = maxf(0.0, _gunfire_noise - noise_gunfire_decay * delta)
	var move_noise := 0.0
	if is_on_floor():
		var ground_speed := Vector2(velocity.x, velocity.z).length()
		move_noise = ground_speed * noise_move_per_speed * (1.0 - crouch.crouch_t)
	noise_radius = maxf(move_noise, _gunfire_noise)


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
	# Drive the speed vignette off the SAME speed intensity, smoothed the same way, so the white
	# air-streaks swell and fade in lockstep with the wind.
	if _speed_lines:
		var sl_mat := _speed_lines.material as ShaderMaterial
		if sl_mat:
			var cur := float(sl_mat.get_shader_parameter("intensity"))
			sl_mat.set_shader_parameter("intensity", lerpf(cur, t, smooth))


func _on_mouse_input_rotate(_amt: Vector2) -> void:
	rotate_y(_amt.y)

func _check_air_thump(delta: float, pre_velocity: Vector3) -> void:
	# Loud thump when slamming into something mid-air at speed. Triggered by a
	# sudden frame-over-frame speed drop (a real impact) rather than mere contact,
	# so sliding along a wall doesn't machine-gun the sound.
	if _thump_cooldown > 0.0:
		_thump_cooldown -= delta
		return
	if is_on_floor():
		return
	if get_slide_collision_count() == 0:
		return
	var speed_lost := pre_velocity.length() - velocity.length()
	if speed_lost < thump_min_speed_lost:
		return
	if thump_sound:
		AudioManager.play_2d_sfx(thump_sound, thump_volume_db, randf_range(0.9, 1.05))
	_thump_cooldown = thump_cooldown

const RAM_BOUNCE_FLOOR_DOT: float = 0.7

func _check_bounce(delta: float, pre_velocity: Vector3) -> void:
	# Pinball-style rebound: ramming a wall / object / enemy at speed reflects you
	# back off the surface. Routed through the decaying blast impulse so the
	# rebound carries you off the wall instead of being killed by the move lerp.
	if _bounce_cooldown > 0.0:
		_bounce_cooldown -= delta
		return
	if pre_velocity.length() < ram_bounce_min_speed:
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var normal := col.get_normal()
		if normal.y > RAM_BOUNCE_FLOOR_DOT:
			continue  # ignore the floor so fast landings don't pop you upward
		var into_speed := -pre_velocity.dot(normal)
		if into_speed < ram_bounce_min_speed:
			continue
		explosion_velocity += normal * into_speed * ram_bounce_factor
		if screen_shake:
			screen_shake.shake(ram_bounce_shake)
		if ram_bounce_sound:
			AudioManager.play_2d_sfx(ram_bounce_sound, 0.0, randf_range(0.95, 1.1))
		_bounce_cooldown = ram_bounce_cooldown
		break

func _check_ram_damage(delta: float, pre_velocity: Vector3) -> void:
	# Body-check: if moving fast enough, damage enemies we slid into this frame.
	# Use pre_velocity — the collision response already bled off `velocity` by
	# the time this runs, so checking `velocity` here would almost always fail.
	if _ram_cooldown > 0.0:
		_ram_cooldown -= delta
		return
	if pre_velocity.length() < GameSettings.physics_damage.ram_min_speed:
		return
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is NPC:
			var enemy := collider as Character
			if enemy.hp <= 0:
				continue  # already dying — don't ram a corpse
			var dmg := maxi(1, int(round(pre_velocity.length() * GameSettings.physics_damage.ram_damage_per_speed)))
			EffectFactory.spawn_blood_particle(enemy.global_position)
			if enemy.bloody_mess:
				enemy.bloody_mess.splatter_at(enemy.global_position, pre_velocity)
			enemy.take_damage(dmg)
			# Bowling-strike sfx ONLY on a ram kill; a non-lethal ram gets a heavy thud.
			if enemy.hp <= 0:
				bowling.play()
			elif ram_thud_sound:
				AudioManager.play_sfx(enemy.global_position, ram_thud_sound, 0.0, randf_range(0.95, 1.05))

			enemy.explosion_velocity += pre_velocity.normalized() * GameSettings.physics_damage.ram_knockback
			_ram_cooldown = GameSettings.physics_damage.ram_cooldown
			white_flash.visible = true
			await get_tree().create_timer(0.085).timeout
			white_flash.visible = false
			break

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
var _dying: bool = false

func take_damage(amount: float, was_crit: bool = false, attacker: Node = null) -> void:
	if _dying:
		return
	# Forward `attacker` to match Character.take_damage's signature (GDScript requires overrides to
	# match the parent). The player has no aggro hook, so the attacker identity is simply unused here.
	super.take_damage(amount, was_crit, attacker)
	if not _dying:
		_trigger_hurt()

## Ping the SINGLE aim radial toward `world_pos` (the shooter) when we actually take a hit. By the
## time an NPC fires, its aim charge has reset to 0 — so the aim arc has already vanished and nothing
## would point at "the thing that shot you". This brief ping fills that gap on the SAME radial (no
## second indicator): it rotates toward the shooter as you turn, then fades. Keyed by `source` so it
## never stacks a second arc on that enemy's live aim arc.
func indicate_damage_from(world_pos: Vector3, source: Object = null) -> void:
	if source != null and _aim_indicators:
		_aim_indicators.ping(source, world_pos)

## Show the red "being aimed at" radial toward `source` — it grows with the 0..1 aim readiness, scaled
## by the shot's `damage` (a heavier hit telegraphs a bigger ring).
func indicate_aimed_from(source: Object, world_pos: Vector3, charge: float, damage: float = 0.0, warning: bool = false, clear_shot: bool = true) -> void:
	if _aim_indicators:
		_aim_indicators.report(source, world_pos, charge, damage, warning)
	if _sniper_glints:
		# The glint shows ONLY while the enemy currently has a CLEAR SHOT on us, so it clears the instant
		# they lose line of sight / range / ammo (or die) — instead of lingering at their position through
		# the slow post-shot charge bleed, which read as a "stuck" glint. Held at a floor so it doesn't
		# blink off at charge 0 right after each shot; brightness/size still ramp with the charge.
		_sniper_glints.report(source, world_pos, (maxf(charge, 0.35) if clear_shot else 0.0))

## The player's hit-confirm "ding" — a dedicated 2D hitsound, SEPARATE from the weapons' impact
## sounds. It fires only here, and on_dealt_hit is the player's "I landed a hit" callback (NPCs
## override it to a no-op), so an NPC-vs-NPC trade can never proc the player's hitsound.
const HIT_SFX := preload("res://assets/audio/freesound_community-ding-101377.mp3")
## Headshot drops the ding's pitch DOWN (deeper, meatier) rather than up — sub-1.0 factor.
const HEADSHOT_PITCH_MULT := 0.7

## Flash the crosshair hitmarker AND play the hit-confirm ding — called when one of our shots or
## explosions lands on a target. Player-only by construction (the NPC override of on_dealt_hit no-ops).
func on_dealt_hit(headshot := false, hp_frac := 1.0) -> void:
	if _hitmarker:
		_hitmarker.flash(headshot)
	# Pitch tracks the target's remaining HP (deeper as it nears death); a headshot drops it deeper
	# still (HEADSHOT_PITCH_MULT < 1.0). NOTE: this intentionally desyncs the ding from the per-weapon
	# impact-against-character sound (attack.gd / projectile.gd still pitch UP on headshot).
	var pitch := lerpf(GameSettings.audio.enemy_hit_pitch_low_hp, GameSettings.audio.enemy_hit_pitch_full_hp, hp_frac) * (HEADSHOT_PITCH_MULT if headshot else 1.0)
	AudioManager.play_2d_sfx(HIT_SFX, 0.0, pitch)

func die() -> void:
	if _dying:
		return
	_dying = true
	# Clear any in-progress hurt feedback so the ducked master bus doesn't bleed into the scene
	# reload — the bus is global, a reload won't reset it, and the next life would read it as base.
	if _hurt_tween and _hurt_tween.is_valid():
		_hurt_tween.kill()
	_set_hurt_amount(0.0)
	died.emit()
	# Freeze the player but keep effects (gore particles, blood, sound) running
	# so the death is visible during the brief delay before the scene reloads.
	set_physics_process(false)
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_restart_scene)

func _restart_scene() -> void:
	if not is_inside_tree():
		return
	get_tree().reload_current_scene()
