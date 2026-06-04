class_name GrappleHook
extends Node3D

## Cruelty-Squad-style grapple, now with a SHOT-OUT hook instead of an instant snap.
##  - Pressing Grapple pre-resolves what the crosshair is on, then FIRES a hook head that flies out
##    along that aim at hook_speed. The rope trails from the muzzle to the travelling head and a
##    Sprite3D (hook_texture) rides its tip. Only when the head REACHES the target does it ATTACH —
##    so the rope visibly shoots out instead of teleporting to the crosshair.
##  - Aim at static geometry -> TETHER: a fixed-length rope you SWING on. The rope cancels velocity
##    that would stretch it past its length, so gravity + momentum pendulum you around the anchor.
##    Pump the swing with WASD; hold JUMP to reel in (climb toward the anchor). Release -> fling.
##  - Aim at a RigidBody or an enemy -> YANK: reel THAT toward you instead.
##  - To compensate for the travel feel, the pull is held off for pull_delay seconds AFTER the hook
##    attaches (no instant yank the frame the rope catches).
##
## The constraint/pull is applied from player.gd's _physics_process via apply_pull(), after
## input/gravity and before move_and_slide. Bind "Grapple" in the Input Map. Tune the defaults here.

@export var max_range: float = 30.0
## How fast the fired hook head flies out toward the aim point (m/s). Lower = a more visible travel.
@export var hook_speed: float = 80.0
## After the hook ATTACHES, wait this long before applying ANY pull — a brief beat so a fresh shot
## doesn't yank the player the instant the rope catches (compensates for the shoot-out travel).
@export var pull_delay: float = 0.1

@export_group("Tether (swing)")
@export var swing_assist: float = 15.0        ## tangential push from WASD — lets you pump the swing
@export var reel_speed: float = 2.0          ## hold Jump to climb toward the anchor at this rate
@export var min_rope_length: float = 2.0      ## can't reel closer than this
@export var release_launch: float = 12.0      ## extra speed flung toward where you're AIMING when you RELEASE a swing

@export_group("Yank (objects / enemies)")
@export var yank_speed: float = 14.0          ## top reel-in speed of a grabbed body
@export var yank_accel: float = 80.0
@export var reach_distance: float = 2.0       ## yank: release once the body is this close

@export_group("Rope")
@export var rope_color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Optional rope texture. Leave null for a flat rope_color. When set it's TILED ALONG the rope's
## length (the cylinder's V axis), so a long rope reads as repeating cord rather than one smeared
## stretch. rope_color still tints it. (Answers "can the rope take a texture?" — yes, set this.)
@export var rope_texture: Texture2D
@export var rope_texture_tiles_per_meter: float = 4.0  ## texture repeats per metre of rope length

@export_group("Hook head")
## Texture for the Sprite3D that rides the fired hook's tip. Leave null and no sprite is shown.
@export var hook_texture: Texture2D
@export var hook_pixel_size: float = 0.01     ## Sprite3D pixel_size (world metres per texture pixel)

const GRAPPLE_ACTION := &"Grapple"
enum Mode { TETHER, YANK }
## IDLE = nothing out; FIRING = hook flying toward the target; ATTACHED = caught + pulling;
## RETRACTING = let go, reeling the head back to the muzzle before it can fire again.
enum State { IDLE, FIRING, ATTACHED, RETRACTING }

## Optional one-stop config (assigned by the host before _ready). When set its fields override the
## exports above and supply the launch / hit / detach SFX. Null = use the exports + play no SFX.
var config: GrappleHookResource
var character: Character
var camera: Node3D
var muzzle: Node3D

var _state: State = State.IDLE
var _mode: Mode = Mode.TETHER
var _anchor: Vector3
var _rope_length: float = 0.0
var _yanked: Node3D
var _rope: MeshInstance3D
var _rope_material: StandardMaterial3D
var _hook_sprite: Sprite3D
var _has_action: bool = false

# --- Fired-hook travel (FIRING state) ---
var _fire_origin: Vector3       ## muzzle position captured when the hook was fired (tip travels from here)
var _hook_dir: Vector3          ## unit travel direction toward the resolved aim point
var _hook_dist: float = 0.0     ## distance from _fire_origin to the aim point
var _hook_travelled: float = 0.0
var _hook_pos: Vector3          ## current world position of the travelling hook head
var _will_attach: bool = false  ## false = the shot MISSED (flies out then retracts, no attach)
var _pending_mode: Mode = Mode.TETHER
var _pending_yanked: Node3D
var _attach_grace: float = 0.0  ## pull_delay countdown after attach — momentum is held off while > 0

func setup(p_character: Character, p_camera: Node3D, p_muzzle: Node3D) -> void:
	character = p_character
	camera = p_camera
	muzzle = p_muzzle

func _ready() -> void:
	_has_action = InputMap.has_action(GRAPPLE_ACTION)
	_apply_config()
	_build_rope()
	_build_hook_sprite()

## Copy a GrappleHookResource's fields over the exports (visuals + feel) before the rope/sprite build.
func _apply_config() -> void:
	if config == null:
		return
	hook_texture = config.hook_texture
	hook_pixel_size = config.hook_pixel_size
	rope_color = config.rope_color
	rope_texture = config.rope_texture
	rope_texture_tiles_per_meter = config.rope_texture_tiles_per_meter
	max_range = config.max_range
	hook_speed = config.hook_speed
	pull_delay = config.pull_delay
	release_launch = config.release_launch

func is_attached() -> bool:
	return _state == State.ATTACHED

func _process(delta: float) -> void:
	if not _has_action or not character:
		return
	if Input.is_action_just_pressed(GRAPPLE_ACTION):
		_try_fire()
	elif Input.is_action_just_released(GRAPPLE_ACTION):
		detach()
	if _state == State.FIRING:
		_advance_hook(delta)
	elif _state == State.RETRACTING:
		_advance_retract(delta)
	_update_visual()

## Pre-resolve what the crosshair is on, then start FIRING a hook out toward it (no instant snap).
func _try_fire() -> void:
	if _state != State.IDLE or not camera:
		return
	# Guard the world: get_world_3d() is null if we're momentarily not in a live 3D scene, and
	# dereferencing .direct_space_state on that null is exactly the reported runtime crash.
	var world := character.get_world_3d()
	if world == null:
		return
	var from: Vector3 = camera.global_position
	var to: Vector3 = from - camera.global_transform.basis.z * max_range
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [character.get_rid()]
	var hit := world.direct_space_state.intersect_ray(params)
	_fire_origin = muzzle.global_position if muzzle else character.global_position
	if hit:
		var col: Object = hit.collider
		_will_attach = true
		if col is RigidBody3D or col is Character:
			_pending_mode = Mode.YANK
			_pending_yanked = col as Node3D
		else:
			_pending_mode = Mode.TETHER
			_pending_yanked = null
		_begin_travel(hit.position)
	else:
		# Missed: still shoot the hook out to max range so the rope visibly fires, then retract.
		_will_attach = false
		_pending_yanked = null
		_begin_travel(to)
	if config and config.launch_sfx:
		AudioManager.play_2d_sfx(config.launch_sfx, config.sfx_volume_db, 1.0)

## Kick off the FIRING phase: the head will slide from the muzzle to `target` over time.
func _begin_travel(target: Vector3) -> void:
	var diff := target - _fire_origin
	_hook_dist = diff.length()
	_hook_dir = (diff / _hook_dist) if _hook_dist > 0.001 else (-camera.global_transform.basis.z)
	_hook_travelled = 0.0
	_hook_pos = _fire_origin
	_anchor = target  # the eventual tether anchor + the visual endpoint the head flies to
	_state = State.FIRING

## Slide the head along its fixed travel ray; ATTACH (or retract on a miss) once it reaches the target.
func _advance_hook(delta: float) -> void:
	_hook_travelled += hook_speed * delta
	if _hook_travelled >= _hook_dist:
		_hook_pos = _fire_origin + _hook_dir * _hook_dist
		_on_hook_arrived()
	else:
		_hook_pos = _fire_origin + _hook_dir * _hook_travelled

func _on_hook_arrived() -> void:
	if not _will_attach:
		detach()  # the shot missed — the rope just retracts
		return
	if _pending_mode == Mode.YANK:
		if not is_instance_valid(_pending_yanked):
			detach()  # the grabbed body died mid-flight
			return
		_mode = Mode.YANK
		_yanked = _pending_yanked
	else:
		_mode = Mode.TETHER
		# _anchor was set in _begin_travel; lock the swing radius from where we are NOW.
		_rope_length = (character.global_position - _anchor).length()
	_attach_grace = pull_delay  # hold momentum for a beat now that the rope has caught (#3)
	_state = State.ATTACHED
	if config and config.hit_sfx:
		AudioManager.play_sfx(_anchor, config.hit_sfx, config.sfx_volume_db, 1.0)

## Let go: the hook doesn't just vanish — it RETRACTS back to the muzzle first, and only once it's home
## is the grapple ready to fire again (you have to wait for it to come back). No-op if nothing's out.
func detach() -> void:
	if _state == State.IDLE or _state == State.RETRACTING:
		return
	if config and config.detach_sfx:
		AudioManager.play_2d_sfx(config.detach_sfx, config.sfx_volume_db, 1.0)
	# Start the return trip from wherever the head currently is: the anchor / grabbed body while
	# attached, else the travelling tip is already in _hook_pos (a mid-flight release / a miss).
	if _state == State.ATTACHED:
		_hook_pos = (_yanked.global_position if (_mode == Mode.YANK and is_instance_valid(_yanked)) else _anchor)
		# Slingshot: releasing a swing flings you toward where you're AIMING (the camera's forward), so
		# you launch where you look. Added on top of your swing momentum. (Only TETHER; a yank isn't a swing.)
		if _mode == Mode.TETHER and release_launch > 0.0 and character:
			var aim := (-camera.global_transform.basis.z) if camera else Vector3.UP
			character.velocity += aim.normalized() * release_launch
	_state = State.RETRACTING
	_yanked = null
	_pending_yanked = null

## Reel the hook head back toward the muzzle; once it's home, fully stow (IDLE) so it can fire again.
func _advance_retract(delta: float) -> void:
	var target: Vector3 = muzzle.global_position if muzzle else character.global_position
	_hook_pos = _hook_pos.move_toward(target, hook_speed * delta)
	if _hook_pos.distance_to(target) <= 0.05:
		_state = State.IDLE

func apply_pull(delta: float) -> void:
	if _state != State.ATTACHED or not character:
		return
	# Momentum delay: the rope has caught, but hold off any pull for pull_delay seconds first.
	if _attach_grace > 0.0:
		_attach_grace -= delta
		return
	if _mode == Mode.YANK:
		_apply_yank(delta)
	else:
		_apply_tether(delta)

func _apply_tether(delta: float) -> void:
	var to_anchor := _anchor - character.global_position
	var dist := to_anchor.length()
	if dist < 0.01:
		return
	var dir := to_anchor / dist   # toward the anchor

	# Reel in: hold Jump to climb toward the anchor at a steady rate, keeping your tangential swing.
	# The rope ratchets shorter as you climb so you swing at the new, tighter radius afterward.
	if Input.is_action_pressed(&"jump") and dist > min_rope_length:
		var tangential := character.velocity - dir * character.velocity.dot(dir)
		character.velocity = tangential + dir * reel_speed
		_rope_length = maxf(min_rope_length, dist)

	# Swing pump: feed your movement input in TANGENTIALLY (perpendicular to the rope) so leaning
	# into the swing builds speed instead of just hanging there.
	var wish_2d := Input.get_vector(&"left", &"right", &"forward", &"backward")
	if wish_2d != Vector2.ZERO:
		var wish := character.global_transform.basis * Vector3(wish_2d.x, 0.0, wish_2d.y)
		var tangent := wish - dir * wish.dot(dir)
		character.velocity += tangent * swing_assist * delta

	# Taut rope: cancel the velocity stretching it past its length (keep only the tangential swing).
	# Moving INWARD stays free (slack rope).
	if dist >= _rope_length:
		var along := character.velocity.dot(dir)   # + = toward anchor, - = away
		if along < 0.0:
			character.velocity -= dir * along

## Yank: reel the grabbed RigidBody / enemy toward you; release once it arrives.
func _apply_yank(delta: float) -> void:
	if not is_instance_valid(_yanked):
		detach()
		return
	var to_player := character.global_position - _yanked.global_position
	var dist := to_player.length()
	if dist <= reach_distance:
		detach()
		return
	var dir := to_player / dist
	if _yanked is RigidBody3D:
		var rb := _yanked as RigidBody3D
		rb.linear_velocity = rb.linear_velocity.move_toward(dir * yank_speed, yank_accel * delta)
	elif _yanked is Character:
		(_yanked as Character).explosion_velocity += dir * yank_accel * delta

func _build_rope() -> void:
	_rope = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0012
	cyl.bottom_radius = 0.0012
	cyl.height = 1.0
	_rope.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = rope_color
	# A texture is optional: if set it rides the albedo and is tiled along the length each frame in
	# _update_visual (the rope's length changes constantly, so the UV scale can't be baked once here).
	if rope_texture:
		mat.albedo_texture = rope_texture
	_rope.material_override = mat
	_rope_material = mat
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope.top_level = true
	_rope.visible = false
	add_child(_rope)

## A Sprite3D that rides the fired hook's tip. Billboards toward the camera so the hook icon always
## faces the player. No texture assigned => stays hidden (so the feature is opt-in, nothing to break).
func _build_hook_sprite() -> void:
	_hook_sprite = Sprite3D.new()
	if hook_texture:
		_hook_sprite.texture = hook_texture
	_hook_sprite.pixel_size = hook_pixel_size
	_hook_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hook_sprite.shaded = false
	_hook_sprite.top_level = true
	_hook_sprite.visible = false
	add_child(_hook_sprite)

## Drive the rope + hook sprite each frame: hide both while IDLE; otherwise stretch the rope from the
## live muzzle to the current endpoint (the travelling head while FIRING, the anchor / grabbed body
## once ATTACHED) and sit the hook sprite on that endpoint.
func _update_visual() -> void:
	var active := _state != State.IDLE
	if _rope:
		_rope.visible = active
	if _hook_sprite:
		_hook_sprite.visible = active and _hook_sprite.texture != null
	if not active or not _rope:
		return
	var endpoint: Vector3
	if _state == State.FIRING or _state == State.RETRACTING:
		endpoint = _hook_pos
	elif _mode == Mode.YANK:
		if not is_instance_valid(_yanked):
			return
		endpoint = _yanked.global_position
	else:
		endpoint = _anchor
	if _hook_sprite:
		_hook_sprite.global_position = endpoint
	# Stretch the rope cylinder (length axis +Y) from the muzzle to the endpoint. Sets the whole
	# global_transform at once so the basis assignment can't stomp the position.
	var origin: Vector3 = muzzle.global_position if muzzle else character.global_position
	var diff := endpoint - origin
	var length := diff.length()
	if length < 0.01:
		return
	var y := diff / length
	var x := Vector3.RIGHT
	if absf(y.dot(x)) > 0.99:
		x = Vector3.FORWARD
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	# Scale the Y *column* (the cylinder's length axis) directly — Basis.scaled() would scale the
	# matrix rows (world axes) and skew the cylinder instead of just lengthening it.
	_rope.global_transform = Transform3D(Basis(x, y * length, z), (origin + endpoint) * 0.5)
	# Tile the texture along the (live) length so it reads as cord, not a stretched smear.
	if _rope_material and rope_texture:
		_rope_material.uv1_scale = Vector3(1.0, maxf(length * rope_texture_tiles_per_meter, 0.001), 1.0)
