class_name GrappleHook
extends Node3D

## Cruelty-Squad-style grapple.
##  - Aim at static geometry -> TETHER: a fixed-length rope you SWING on. The rope cancels velocity
##    that would stretch it past its length, so gravity + momentum pendulum you around the anchor.
##    Pump the swing with WASD; hold JUMP to reel in (climb toward the anchor). Release -> fling.
##  - Aim at a RigidBody or an enemy -> YANK: reel THAT toward you instead.
##
## The constraint/pull is applied from player.gd's _physics_process via apply_pull(), after
## input/gravity and before move_and_slide. Bind "Grapple" in the Input Map. Tune the defaults here.

@export var max_range: float = 30.0

@export_group("Tether (swing)")
@export var swing_assist: float = 15.0        ## tangential push from WASD — lets you pump the swing
@export var reel_speed: float = 2.0          ## hold Jump to climb toward the anchor at this rate
@export var min_rope_length: float = 2.0      ## can't reel closer than this

@export_group("Yank (objects / enemies)")
@export var yank_speed: float = 14.0          ## top reel-in speed of a grabbed body
@export var yank_accel: float = 80.0
@export var reach_distance: float = 2.0       ## yank: release once the body is this close

@export_group("Rope")
@export var rope_color: Color = Color(1.0, 1.0, 1.0, 1.0)

const GRAPPLE_ACTION := &"Grapple"
enum Mode { TETHER, YANK }

var character: Character
var camera: Node3D
var muzzle: Node3D

var _attached: bool = false
var _mode: Mode = Mode.TETHER
var _anchor: Vector3
var _rope_length: float = 0.0
var _yanked: Node3D
var _rope: MeshInstance3D
var _has_action: bool = false

func setup(p_character: Character, p_camera: Node3D, p_muzzle: Node3D) -> void:
	character = p_character
	camera = p_camera
	muzzle = p_muzzle

func _ready() -> void:
	_has_action = InputMap.has_action(GRAPPLE_ACTION)
	_build_rope()

func is_attached() -> bool:
	return _attached

func _process(_delta: float) -> void:
	if not _has_action or not character:
		return
	if Input.is_action_just_pressed(GRAPPLE_ACTION):
		_try_attach()
	elif Input.is_action_just_released(GRAPPLE_ACTION):
		detach()
	_update_rope()

func _try_attach() -> void:
	if not camera:
		return
	var from: Vector3 = camera.global_position
	var to: Vector3 = from - camera.global_transform.basis.z * max_range
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [character.get_rid()]
	var hit := character.get_world_3d().direct_space_state.intersect_ray(params)
	if not hit:
		return
	var col: Object = hit.collider
	if col is RigidBody3D or col is Character:
		_mode = Mode.YANK
		_yanked = col as Node3D
	else:
		_mode = Mode.TETHER
		_anchor = hit.position
		_rope_length = (character.global_position - _anchor).length()
	_attached = true

func detach() -> void:
	_attached = false
	_yanked = null

func apply_pull(delta: float) -> void:
	if not _attached or not character:
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
	_rope.material_override = mat
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope.top_level = true
	_rope.visible = false
	add_child(_rope)

## Stretch the rope cylinder (length axis +Y) from the muzzle to the anchor / grabbed body. Sets the
## whole global_transform at once so the basis assignment can't stomp the position.
func _update_rope() -> void:
	if not _rope:
		return
	_rope.visible = _attached
	if not _attached:
		return
	var endpoint: Vector3
	if _mode == Mode.YANK:
		if not is_instance_valid(_yanked):
			return
		endpoint = _yanked.global_position
	else:
		endpoint = _anchor
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
