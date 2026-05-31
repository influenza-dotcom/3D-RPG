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
@export var camera_effects: CameraEffects
@export var crouch: Crouch
@export var head: Head
@export var player_collision_shape: CollisionShape3D
@export var weapon_system: Weapon
@export var screen_shake: ScreenShake
@export var muzzle: Marker3D
@export var ui: UI
@export var coyote_time: CoyoteTime
@export var jump_buffer: JumpBuffer
@export var gun_mesh: GunMesh
@export var bullet_time: BulletTime
@export var bunnyhop: Bunnyhop
@export var mouse_input: MouseInput

var footstep_interval: float = GameSettings.player_movement.footstep_base_interval
var _footstep_timer: float = 0.0

var _was_on_floor: bool = false
var input_dir: Vector2 = Vector2.ZERO
var _ram_cooldown: float = 0.0
var _thump_cooldown: float = 0.0
var _bounce_cooldown: float = 0.0

const NIGHT_VISION_FADE_RATE: float = 9.0
var _nv_on: bool = false
var _nv_t: float = 0.0

var _sliding: bool = false
var _slide_dir: Vector3 = Vector3.ZERO
var _slide_speed: float = 0.0
var _slide_dust_timer: float = 0.0
var _slide_sfx: AudioStreamPlayer

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

var target_speed: float = GameSettings.player_movement.max_speed

var _walking_sfx_base_db: float
var _land_sfx_base_db: float
var _land_sfx_base_pitch: float
var _is_scoped: bool = false

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
	# Same for the camera rig (Head -> ScreenShake -> Camera3D): resolve the rig root if
	# its export was cleared, read the camera + screen-shake off the rig interface, and
	# inject this player into the rig parts that point back out (camera + pickup raycast).
	if not head:
		head = get_node_or_null("Head") as Head
	if head:
		camera_effects = head.camera
		screen_shake = head.screen_shake
		head.setup(self, mouse_input)
	crouch.player = self
	crouch.head = head
	crouch.collision_shape = player_collision_shape
	weapon_system.setup(self, camera_effects, muzzle, screen_shake)
	# Resolve the HUD root if extraction cleared its export, then inject the player whose
	# HP it shows + the ammo clip it reads.
	if not ui:
		ui = get_node_or_null("UI") as UI
	if ui:
		ui.setup(self, weapon_system.ammo)
	coyote_time.character = self
	# The view model self-wires its gun-mesh pose anims + muzzle FX from these refs.
	# (The Slice-1 host-side signal bridge now lives inside GunMesh.setup().)
	gun_mesh.setup(self, weapon_system.inventory, weapon_system.attack, weapon_system.ammo, mouse_input)
	bullet_time.character = self
	bullet_time.scope_in = weapon_system.scope_in
	bullet_time.attack = weapon_system.attack
	bunnyhop.character = self
	mouse_input.player = self

func _ready() -> void:
	super._ready()
	_walking_sfx_base_db = walking_sfx.volume_db
	_land_sfx_base_db = land_sfx.volume_db
	_land_sfx_base_pitch = land_sfx.pitch_scale
	weapon_system.scope_in.scoped_in.connect(_on_scoped_in)
	# Dedicated looping player for the slide sfx (wind, for now). Built in code so
	# it's independent of the falling-air player, which stops itself on the floor.
	_slide_sfx = AudioStreamPlayer.new()
	_slide_sfx.stream = slide_sound if slide_sound else falling_air_sfx.stream
	add_child(_slide_sfx)

func _on_scoped_in(_tf: bool) -> void:
	_is_scoped = _tf

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

func _physics_process(delta: float) -> void:
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
		if gun_mesh and impact > 0.0 and not gun_mesh.tween:
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

	if is_on_floor() and not _sliding and Vector2(velocity.x, velocity.z).length() > GameSettings.player_movement.footstep_min_horizontal_speed and _footstep_timer <= 0.0:
		walking_sfx.volume_db = lerpf(_walking_sfx_base_db, _walking_sfx_base_db + GameSettings.player_crouch.quiet_footstep_db, crouch.crouch_t)
		walking_sfx.play()
		_footstep_timer = footstep_interval

	_update_falling_air(delta)


func _try_start_slide(pre_velocity: Vector3) -> void:
	# Begin a slide if we just touched down fast while holding crouch. Uses the
	# pre-move velocity so the landing frame's preserved momentum is the seed.
	if _sliding:
		return
	if not Input.is_action_pressed("Crouch"):
		return
	var speed := Vector2(pre_velocity.x, pre_velocity.z).length()
	if speed < slide_min_speed:
		return
	_sliding = true
	_slide_dir = Vector3(pre_velocity.x, 0.0, pre_velocity.z).normalized()
	_slide_speed = minf(speed * slide_boost, slide_max_speed)
	_slide_dust_timer = 0.0
	if _slide_sfx and not _slide_sfx.playing:
		_slide_sfx.play()

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
	if _slide_sfx and _slide_sfx.playing:
		_slide_sfx.stop()


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
		if collider is Enemy:
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

func take_damage(amount: int) -> void:
	if _dying:
		return
	super.take_damage(amount)

func die() -> void:
	if _dying:
		return
	_dying = true
	died.emit()
	# Freeze the player but keep effects (gore particles, blood, sound) running
	# so the death is visible during the brief delay before the scene reloads.
	set_physics_process(false)
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_restart_scene)

func _restart_scene() -> void:
	if not is_inside_tree():
		return
	get_tree().reload_current_scene()
