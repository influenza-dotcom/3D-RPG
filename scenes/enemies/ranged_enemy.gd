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

@export_group("Movement")
## How fast it walks / chases (m/s).
@export var move_speed: float = 4.0
## Ground acceleration — also how fast it sheds knockback / brakes to a stop (m/s^2).
@export var move_accel: float = 25.0
## Air acceleration (low, so a blast carries it before it recovers) (m/s^2).
@export var air_accel: float = 2.0
## Alerted: closes until the player is within this fraction of the weapon's effective range,
## then holds and fires (so it actually gets in range to hit).
@export var engage_range_fraction: float = 0.9
## Upward impulse for hopping ledges / the far end of an up navigation-link (m/s).
@export var jump_velocity: float = 10.0

var _weapon: Weapon
var _muzzle: Marker3D
var _perception: Perception
var _player: Node3D
var _player_body: Node3D  # player's collision shape (centre tracks crouch); falls back to _player
var _laser: MeshInstance3D
var _fire_timer: float = 0.0
var _spawn_yaw: float = 0.0
var _spawn_position: Vector3
var _desired_velocity: Vector3 = Vector3.ZERO
var _nav: NavigationAgent3D

func _ready() -> void:
	super._ready()
	_spawn_yaw = rotation.y
	_spawn_position = global_position
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
	_build_nav()
	_acquire_player()

## Off guard (eligible for the sneak-attack bonus) until fully ALERTED — i.e. while UNAWARE, still
## DETECTING, or INVESTIGATING a noise. Once it locks on and engages, no more free sneak damage.
func is_off_guard() -> bool:
	return _perception != null and _perception.state != Perception.State.ALERTED

func _build_perception() -> void:
	_perception = Perception.new()
	_perception.sight_range = sight_range
	_perception.fov_degrees = fov_degrees
	_perception.time_to_detect = time_to_detect
	_perception.forget_time = forget_time
	_perception.eye_height = eye_height
	_perception.hearing = hearing
	add_child(_perception)

func _build_nav() -> void:
	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.5
	_nav.target_desired_distance = 1.0
	add_child(_nav)

func _physics_process(delta: float) -> void:
	_desired_velocity = Vector3.ZERO  # default: hold position; states below may drive it
	if not is_instance_valid(_player):
		_acquire_player()
		_hide_laser()
		super._physics_process(delta)
		return
	_perception.sense(delta)
	match _perception.state:
		Perception.State.UNAWARE:
			# Walk back to its post if knocked away; once there, watch its spawn direction.
			if _move_toward(_spawn_position):
				_face_travel(delta)
			else:
				_face_yaw(_spawn_yaw, delta)
			_hide_laser()
		Perception.State.DETECTING:
			_face_point(_perception.last_known_position, delta)
			_aim_laser_at(_perception.last_known_position, _perception.detection)
		Perception.State.ALERTED:
			_act_alerted(delta)
		Perception.State.INVESTIGATING:
			# Go check the last-known spot; face where it walks, then look around once there.
			if _move_toward(_perception.last_known_position):
				_face_travel(delta)
			else:
				_face_point(_perception.last_known_position, delta)
			_aim_laser_at(_perception.last_known_position, _perception.detection * 0.6)
	super._physics_process(delta)  # gravity + blast + locomotion move (uses _desired_velocity)

## Alerted: track the player, keep the laser hot, and fire on cadence while the shot is clear.
func _act_alerted(delta: float) -> void:
	var aim := _aim_point()
	# Close until the player is comfortably inside our weapon's effective range, then hold + fire.
	if global_position.distance_to(aim) > _aim_range() * engage_range_fraction:
		_move_toward(aim)
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

# --- Locomotion: NavigationAgent3D pathing composed with the inherited knockback ---
## Path one step toward `target`: sets _desired_velocity along the next path point. Returns
## true while still travelling (false when arrived / no path). Verticality is handled by
## gravity + move_and_slide walking the baked navmesh surface.
func _move_toward(target: Vector3) -> bool:
	if not _nav:
		return false
	_nav.target_position = target
	var to_next: Vector3
	if not _nav.is_navigation_finished():
		# Normal: follow the baked navmesh path (routes around walls + obstacles).
		to_next = _nav.get_next_path_position() - global_position
		if Vector2(to_next.x, to_next.z).length() < 0.05:
			# Path won't advance — navmesh is missing/floating/disconnected under us, so the
			# agent can't route. Head straight at the target so pursuit still works. (Fix the
			# bake for proper wall-avoidance + verticality.)
			to_next = target - global_position
	elif not _nav.is_target_reachable():
		# No navmesh path to you (you dropped off a ledge / off the mesh): commit and head
		# straight for you, walking off the edge if pursuit demands it. Gravity does the fall.
		to_next = target - global_position
		if Vector2(to_next.x, to_next.z).length() < 0.5:
			return false
	else:
		return false  # genuinely arrived
	var climb := to_next.y
	to_next.y = 0.0
	# Hop up toward a higher path point — a ledge, or the far end of an up navigation-link.
	if climb > 0.6 and is_on_floor():
		velocity.y = jump_velocity
	if to_next.length() < 0.05:
		return false
	_desired_velocity = to_next.normalized() * move_speed
	return true

func _face_travel(delta: float) -> void:
	if _desired_velocity.length_squared() > 0.0001:
		_face_point(global_position + _desired_velocity, delta)

## Locomotion + knockback: ease horizontal velocity toward the desired (nav) velocity — which
## also bleeds off a blast and brakes to a stop when idle — then add the decaying blast impulse
## and slide. Mirrors Enemy.apply_velocity's blast + fall-damage tail.
func apply_velocity() -> void:
	var horizontal := Vector2(velocity.x, velocity.z)
	var desired_h := Vector2(_desired_velocity.x, _desired_velocity.z)
	var rate := move_accel if is_on_floor() else air_accel
	horizontal = horizontal.move_toward(desired_h, rate * get_physics_process_delta_time())
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	velocity += explosion_velocity
	var pre_move_velocity := velocity
	var was_grounded := is_on_floor()
	move_and_slide()
	if is_on_floor() and not was_grounded:
		_apply_fall_damage(-pre_move_velocity.y)
	_push_interactables(pre_move_velocity)
	velocity -= explosion_velocity / blast_damp_divisor

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
