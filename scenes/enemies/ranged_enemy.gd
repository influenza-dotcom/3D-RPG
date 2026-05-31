class_name RangedEnemy
extends Enemy

## A ranged enemy: it wields the SAME Weapon component the player does, aimed by AI instead of
## a camera. It senses the player through a Perception layer (view cone + line-of-sight with a
## detection meter) and only turns, aims, lasers, and fires once it has actually noticed you —
## no 360° omniscience. Place it like a regular Enemy; HP / gore / knockback come from Enemy.
##
## Designer surface: drop one in, point weapon_data at any .tres, and tune the perception +
## firing values in the inspector.

const WEAPON_SCENE := preload("res://scenes/weapon.tscn")
const LASER_MAX_LENGTH := 60.0

@export_group("Weapon")
## The weapon this enemy fires — any WeaponData .tres, exactly like the player's.
@export var weapon_data: WeaponData = preload("res://resources/weapons/pistol.tres")
## Local offset of the muzzle (shot origin) from the enemy origin. This model faces +Z.
@export var muzzle_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
## Seconds between shots once alerted (the weapon's own cooldown still applies on top).
@export var fire_cooldown: float = 1.5
## Won't shoot past this distance to the player (separate from how far it can SEE).
@export var fire_range: float = 30.0
## Vertical nudge on the aim point (centre of the player's collision capsule). 0 = dead centre.
@export var target_height: float = 0.0

@export_group("Perception")
## How far the enemy can see.
@export var sight_range: float = 25.0
## Full view-cone angle (degrees). Outside this off its facing it simply can't see you.
@export var fov_degrees: float = 110.0
## Seconds in view before it's fully alerted — your reaction window.
@export var time_to_detect: float = 1.0
## Seconds it stays wary at your last-known spot before giving up.
@export var forget_time: float = 4.0
## Eye height the sight / LOS rays start from.
@export var eye_height: float = 1.4
## Hear the player's noise (gunfire, fast movement) even outside the cone? Crouch is silent.
@export var hearing: bool = true
## How fast it rotates to face what it's looking at.
@export var turn_speed: float = 8.0

@export_group("Laser")
## Draw a laser sight that brightens as it detects / locks onto you.
@export var show_laser: bool = true
## Laser sight colour.
@export var laser_color: Color = Color(1.0, 0.1, 0.1)

var _weapon: Weapon
var _muzzle: Marker3D
var _perception: Perception
var _player: Node3D
var _player_body: Node3D  # player's collision shape (centre tracks crouch); falls back to _player
var _laser: MeshInstance3D
var _fire_timer: float = 0.0
var _spawn_yaw: float = 0.0

func _ready() -> void:
	super._ready()
	_spawn_yaw = rotation.y
	_muzzle = Marker3D.new()
	add_child(_muzzle)
	_muzzle.position = muzzle_offset
	_weapon = WEAPON_SCENE.instantiate()
	add_child(_weapon)
	# No camera -> ScopeIn no-ops (no ADS) and the input-driven parts are disabled.
	_weapon.setup(self, null, _muzzle)
	if weapon_data:
		_weapon.inventory.equip(weapon_data)
	_build_laser()
	_build_perception()
	_acquire_player()

func _build_perception() -> void:
	_perception = Perception.new()
	_perception.sight_range = sight_range
	_perception.fov_degrees = fov_degrees
	_perception.time_to_detect = time_to_detect
	_perception.forget_time = forget_time
	_perception.eye_height = eye_height
	_perception.hearing = hearing
	add_child(_perception)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)  # gravity + blast + knockback (Character / Enemy)
	if not is_instance_valid(_player):
		_acquire_player()
		_hide_laser()
		return
	_perception.sense(delta)
	match _perception.state:
		Perception.State.UNAWARE:
			_face_yaw(_spawn_yaw, delta)  # turn back to watching its post
			_hide_laser()
		Perception.State.DETECTING:
			_face_point(_perception.last_known_position, delta)
			_aim_laser_at(_perception.last_known_position, _perception.detection)
		Perception.State.ALERTED:
			_act_alerted(delta)
		Perception.State.INVESTIGATING:
			_face_point(_perception.last_known_position, delta)
			_aim_laser_at(_perception.last_known_position, _perception.detection * 0.6)

## Alerted: track the player, keep the laser hot, and fire on cadence while the shot is clear.
func _act_alerted(delta: float) -> void:
	var aim := _aim_point()
	_face_point(aim, delta)
	var hit := _aim_laser_at(aim, 1.0)  # laser to the shot's landing point, full glow
	var clear: bool = not hit.is_empty() and hit.get("collider") == _player
	_fire_timer = maxf(0.0, _fire_timer - delta)
	if clear and global_position.distance_to(aim) <= fire_range and _fire_timer <= 0.0:
		if _weapon.current_ammo != 0:
			_weapon.attack.try_fire()
			_fire_timer = fire_cooldown
		elif not _weapon.is_busy():
			# Out of ammo — reload (an AI wielder has no reload input).
			_weapon.reload()

## Taking a hit instantly alerts us toward the player — no free backstabs. (Overrides
## Enemy._on_damaged; super still does the hit freeze-frame.)
func _on_damaged(current_hp: float, _max_hp: float) -> void:
	super._on_damaged(current_hp, _max_hp)
	if _perception and is_instance_valid(_player):
		_perception.alert_to(_aim_point())

# --- Facing (smooth yaw; this model's front is +Z, so yaw = atan2(dx, dz)) ---
func _face_point(point: Vector3, delta: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	_face_yaw(atan2(to.x, to.z), delta)

func _face_yaw(target_yaw: float, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))

# --- Player acquisition ---
func _acquire_player() -> void:
	_player = get_tree().get_first_node_in_group("Player")
	_player_body = _player.get_node_or_null("PlayerCollisionShape") if _player else null
	if not _player_body:
		_player_body = _player
	if _perception:
		_perception.target = _player
		_perception.target_body = _player_body

## World point to aim at: the centre of the player's collision capsule (+ optional nudge).
func _aim_point() -> Vector3:
	var node: Node3D = _player_body if is_instance_valid(_player_body) else _player
	return node.global_position + Vector3.UP * target_height

## How far the aim ray / laser reaches — the equipped weapon's own effective range.
func _aim_range() -> float:
	var w: WeaponData = _weapon.equipped_weapon if _weapon else null
	return w.effective_range if w else LASER_MAX_LENGTH

# --- Laser sight ---
func _build_laser() -> void:
	_laser = MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(0.02, 0.02, 1.0)
	_laser.mesh = beam
	_laser.top_level = true  # ignore our own (rotating) transform; placed in world space
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # so the beam can fade in via alpha
	mat.emission_enabled = true
	mat.emission = laser_color
	var start := laser_color
	start.a = 0.0
	mat.albedo_color = start
	mat.emission_energy_multiplier = 0.0
	_laser.material_override = mat
	add_child(_laser)
	_laser.visible = false

func _hide_laser() -> void:
	if _laser:
		_laser.visible = false

## Point the laser from the muzzle toward `point` (capped at weapon range), glowing by `charge`
## (0..1). Returns the ray hit so callers can reuse it (e.g. the clear-shot test).
func _aim_laser_at(point: Vector3, charge: float) -> Dictionary:
	var origin := get_aim_origin()
	var dir := point - origin
	if dir.length() < 0.01:
		_hide_laser()
		return {}
	dir = dir.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * _aim_range())
	query.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not show_laser or not _laser:
		_hide_laser()
		return hit
	var endpoint: Vector3 = hit.position if not hit.is_empty() else origin + dir * _aim_range()
	var dist := origin.distance_to(endpoint)
	if dist < 0.01:
		_hide_laser()
		return hit
	# Beam basis by hand: Z column = direction * length (so the unit box stretches ALONG the
	# aim); X/Y kept unit + perpendicular so it stays thin. Centred at the midpoint it spans
	# exactly muzzle -> endpoint.
	var bdir := (endpoint - origin) / dist
	var x := bdir.cross(Vector3.UP)
	if x.length_squared() < 0.000001:
		x = bdir.cross(Vector3.FORWARD)
	x = x.normalized()
	var y := x.cross(bdir).normalized()
	_laser.visible = true
	_laser.global_transform = Transform3D(Basis(x, y, bdir * dist), (origin + endpoint) * 0.5)
	var mat := _laser.material_override as StandardMaterial3D
	if mat:
		# Opacity ramps with the charge: fully transparent while it's merely noticing you,
		# fully opaque the instant it's locked and firing — a fast "no fire -> fire" read.
		var a := clampf(charge, 0.0, 1.0)
		var c := laser_color
		c.a = a
		mat.albedo_color = c
		mat.emission_energy_multiplier = a * 5.0
	return hit

# --- WeaponHost aim contract: from the muzzle toward the player, no camera ---
func get_aim_origin() -> Vector3:
	return _muzzle.global_position if _muzzle else global_position

func get_aim_direction() -> Vector3:
	if not is_instance_valid(_player) or not _muzzle:
		return global_basis.z
	return (_aim_point() - _muzzle.global_position).normalized()

func get_aim_basis() -> Basis:
	var dir := get_aim_direction()
	# Avoid a degenerate basis if we're ever aiming near-straight up/down.
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	return Basis.looking_at(dir, up)
