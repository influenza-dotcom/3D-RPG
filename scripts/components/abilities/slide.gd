class_name Slide
extends Ability

## SLIDE ability — drop under a Player to grant it. Land fast while holding crouch and you slide, momentum
## carrying you along the ground and bleeding off to a stop; jump out of it to launch forward scaled by your
## slide speed. The Player calls the hooks below at their original beats: try_start() in the landing block,
## update_movement() in the grounded movement branch (it REPLACES normal ground control while active),
## jump_launch() in the jump block, is_active() for the footstep/falling-air gates. The looping slide wind
## drives itself in _physics_process (no ordering constraint).
##
## Owns its own tuning (these used to live on the Player as exports — re-tune them HERE now). Defaults match the
## Player's old values, so a node added with no overrides slides exactly as before.

## Land while holding crouch above this horizontal speed to start a slide.
@export var slide_min_speed: float = 4.0
## How quickly the slide bleeds off speed (m/s per second).
@export var slide_friction: float = 4.0
## Slide ends once it decays to this speed (≈ crouch-walk pace).
@export var slide_end_speed: float = 2.5
## Hard cap on the slide's starting speed (keeps fast bhop landings sane).
@export var slide_max_speed: float = 6.0
## One-time speed multiplier applied the instant the slide starts (1.0 = none).
@export var slide_boost: float = 1.0
## Slide-jump launch strength as a multiple of your slide speed at jump time (so faster slides fling further).
@export var slide_jump_mult: float = 1.5
## Seconds between dust puffs kicked up while sliding.
@export var slide_dust_interval: float = 0.06
## Size/strength of each slide dust puff.
@export var slide_dust_intensity: float = 0.5
## Looping slide sfx. Leave null to reuse the Player's falling-air wind sound (placeholder).
@export var slide_sound: AudioStream

var _sliding: bool = false
var _slide_dir: Vector3 = Vector3.ZERO
var _slide_speed: float = 0.0
var _slide_dust_timer: float = 0.0
var _slide_sfx: AudioStreamPlayer  ## dedicated looping wind player; volume faded with the slide state

func ability_id() -> StringName:
	return &"slide"

func setup(player: Node) -> void:
	super.setup(player)
	# Build the looping slide-wind player only in-tree (a bare off-tree ability in a unit test skips it — play()
	# / the host's falling_air_sfx aren't available there). Mirrors the Player's old _ready construction.
	if is_inside_tree() and _slide_sfx == null:
		_build_slide_sfx()

func _build_slide_sfx() -> void:
	var stream: AudioStream = slide_sound
	if stream == null and host != null and host.falling_air_sfx != null:
		stream = host.falling_air_sfx.stream
	_slide_sfx = AudioStreamPlayer.new()
	_slide_sfx.stream = stream
	_slide_sfx.volume_db = -80.0
	_slide_sfx.bus = &"sfx"  # respect the SFX slider (a bare player lands on Master and ignores it)
	add_child(_slide_sfx)
	# Keep it looping silently and fade the volume in/out with the slide state instead of hard play()/stop()
	# on every brief slide — that restart was the repeated clicking.
	_slide_sfx.finished.connect(_slide_sfx.play)
	_slide_sfx.play()

## True while sliding — the grounded movement branch hands control to update_movement(), and footsteps /
## falling-air wind suppress. Disabled → false.
func is_active() -> bool:
	return enabled and _sliding

## Landing-block hook: begin a slide if we just touched down fast while holding crouch with no steering input.
## `pre_velocity` is the pre-move velocity so the landing frame's preserved momentum is the seed.
func try_start(pre_velocity: Vector3) -> void:
	if _sliding or not enabled:
		return
	if not Input.is_action_pressed("Crouch"):
		return
	# Steering input ends a slide next frame, so starting one while a move key is held just clicks the sfx —
	# only start when you're letting momentum carry you (no move input).
	var input_dir: Vector2 = host.input_dir
	if input_dir.length() > 0.1:
		return
	var speed := Vector2(pre_velocity.x, pre_velocity.z).length()
	if speed < slide_min_speed:
		return
	_sliding = true
	_slide_dir = Vector3(pre_velocity.x, 0.0, pre_velocity.z).normalized()
	_slide_speed = minf(speed * slide_boost, slide_max_speed)
	_slide_dust_timer = 0.0

## Movement-branch hook (replaces normal ground control while sliding). Any steering input, decay to walking
## pace, releasing crouch, or leaving the ground ends it — the last slide velocity stays in `velocity`, so
## momentum carries out smoothly. Mutates host velocity through a local (value-copy read-modify-write).
func update_movement(delta: float, direction: Vector3) -> void:
	if direction.length() > 0.1 or _slide_speed <= slide_end_speed or not Input.is_action_pressed("Crouch") or not host.is_on_floor():
		end()
		return
	_slide_speed = move_toward(_slide_speed, 0.0, slide_friction * delta)
	var v: Vector3 = host.velocity
	v.x = _slide_dir.x * _slide_speed
	v.z = _slide_dir.z * _slide_speed
	host.velocity = v
	host.current_speed = _slide_speed
	_slide_dust_timer -= delta
	if _slide_dust_timer <= 0.0:
		host.spawn_dust(slide_dust_intensity)
		_slide_dust_timer = slide_dust_interval

## Jump-block hook: if sliding, fling forward via the decaying blast impulse (like the dash) scaled by current
## slide speed, then end the slide. Returns true if it consumed a slide. host.explosion_velocity is a value
## copy, so read-modify-write it.
func jump_launch() -> bool:
	if not is_active():
		return false
	var ev: Vector3 = host.explosion_velocity
	ev += _slide_dir * _slide_speed * slide_jump_mult
	host.explosion_velocity = ev
	end()
	return true

func end() -> void:
	_sliding = false

## Drive the looping slide wind: swell to 0 dB while sliding, fade to silence otherwise. No ordering
## constraint, so it self-ticks here instead of from the host step.
func _physics_process(delta: float) -> void:
	if _slide_sfx == null:
		return
	_slide_sfx.volume_db = lerpf(_slide_sfx.volume_db, 0.0 if _sliding else -80.0, 1.0 - exp(-12.0 * delta))
