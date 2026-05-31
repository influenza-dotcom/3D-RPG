class_name RangedEnemy
extends Enemy

## A ranged enemy: it wields the SAME Weapon component the player does, aimed by AI instead
## of a camera (the payoff of the weapon-host refactor). It spawns its own Weapon + muzzle
## in code, equips a WeaponData (the very same .tres resources the player uses), faces the
## player, and fires on a cadence when the player is in range with a clear shot. Place it
## like a regular Enemy; HP / gore / knockback are all inherited from Enemy.
##
## Designer surface: drop one in, optionally swap weapon_data / tune the cadence + range in
## the inspector. To use a different weapon, just point weapon_data at another .tres.

const WEAPON_SCENE := preload("res://scenes/weapon.tscn")
const LASER_MAX_LENGTH := 60.0

## The weapon this enemy fires — any WeaponData .tres, exactly like the player's.
@export var weapon_data: WeaponData = preload("res://resources/weapons/pistol.tres")
## Local offset of the muzzle (shot origin) from the enemy's origin. This Man.glb model
## faces +Z, so its forward is +Z.
@export var muzzle_offset: Vector3 = Vector3(0.0, 0, 0.0)
## Seconds between shots — the AI cadence (the weapon's own cooldown still applies on top).
@export var fire_cooldown: float = 1.5
## Won't shoot past this distance to the player.
@export var fire_range: float = 30.0
## Vertical nudge on the aim point (the centre of the player's collision capsule). 0 aims
## dead-centre; positive aims higher, negative lower.
@export var target_height: float = 0.0
## Grace period: the enemy must hold a clear shot for this long before the FIRST shot, so a
## fresh line-of-sight isn't an instant hitscan kill. Breaking LOS resets it; later shots
## use fire_cooldown. The laser sight brightens as this fills, telegraphing the shot.
@export var aim_time: float = 0.6
## Draw a laser sight from the muzzle to whatever the aim ray first hits, so the player can
## read the enemy's line of sight and watch the shot charge up.
@export var show_laser: bool = true
## Laser sight colour.
@export var laser_color: Color = Color(1.0, 0.1, 0.1)

var _weapon: Weapon
var _muzzle: Marker3D
var _player: Node3D
var _player_body: Node3D  # player's collision shape (centre tracks crouch); falls back to _player
var _fire_timer: float = 0.0
var _aim_t: float = 0.0    # how long we've held a clear shot (drives the grace period + laser charge)
var _laser: MeshInstance3D

func _ready() -> void:
	super._ready()
	_muzzle = Marker3D.new()
	add_child(_muzzle)
	_muzzle.position = muzzle_offset
	_weapon = WEAPON_SCENE.instantiate()
	add_child(_weapon)
	# No camera -> ScopeIn no-ops (no ADS); the wielder is this enemy.
	_weapon.setup(self, null, _muzzle)
	if weapon_data:
		_weapon.inventory.equip(weapon_data)
	_acquire_player()
	_build_laser()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)  # gravity + blast + knockback (Character / Enemy)
	if not is_instance_valid(_player):
		_acquire_player()
		if _laser:
			_laser.visible = false
		return
	var target := _aim_point()
	_face(target)
	# One ray from the muzzle along our aim tells us both whether the shot is clear (first
	# thing hit is the player) and where the laser should end.
	var hit := _aim_raycast()
	var clear: bool = not hit.is_empty() and hit.get("collider") == _player
	var has_shot := clear and global_position.distance_to(target) <= fire_range
	# Lock-on: charge while we hold a clear shot, reset the instant we lose it.
	_aim_t = (_aim_t + delta) if has_shot else 0.0
	_update_laser(hit)
	_fire_timer = maxf(0.0, _fire_timer - delta)
	# Fire only once the grace period has filled (telegraphed by the laser) AND we're off
	# cooldown — never an instant hitscan on a fresh sighting.
	if has_shot and _aim_t >= aim_time and _fire_timer <= 0.0:
		if _weapon.current_ammo != 0:
			_weapon.attack.try_fire()
			_fire_timer = fire_cooldown
		elif not _weapon.is_busy():
			# Out of ammo — reload (an AI wielder has no reload input).
			_weapon.reload()

## (Re)find the player and cache the node we aim at: its collision shape, whose centre
## stays inside the body AND drops when the player crouches (so the aim tracks a crouch).
func _acquire_player() -> void:
	_player = get_tree().get_first_node_in_group("Player")
	_player_body = _player.get_node_or_null("PlayerCollisionShape") if _player else null
	if not _player_body:
		_player_body = _player

## World point to aim at: the centre of the player's collision capsule (+ optional nudge).
func _aim_point() -> Vector3:
	var node: Node3D = _player_body if is_instance_valid(_player_body) else _player
	return node.global_position + Vector3.UP * target_height

## Yaw to face the player (flat target at our own height, so the body doesn't tip).
func _face(target: Vector3) -> void:
	var flat := Vector3(target.x, global_position.y, target.z)
	if global_position.distance_squared_to(flat) > 0.0001:
		# use_model_front: this model's front is +Z, so point +Z (not -Z) at the player.
		look_at(flat, Vector3.UP, true)

## One ray from the muzzle along the current aim direction, out to laser range. Its hit (if
## any) is reused for both the clear-shot test and the laser endpoint.
func _aim_raycast() -> Dictionary:
	var origin := get_aim_origin()
	var to := origin + get_aim_direction() * _aim_range()
	var query := PhysicsRayQueryParameters3D.create(origin, to)
	query.exclude = [self]
	return get_world_3d().direct_space_state.intersect_ray(query)

## How far the aim ray / laser reaches — the equipped weapon's own effective range.
func _aim_range() -> float:
	var w: WeaponData = _weapon.equipped_weapon if _weapon else null
	return w.effective_range if w else LASER_MAX_LENGTH

## Build the laser-sight beam: a thin unit-length box we stretch/orient each frame. top_level
## so it ignores our own (rotating) transform and we can place it in world space directly.
func _build_laser() -> void:
	_laser = MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(0.02, 0.02, 1.0)
	_laser.mesh = beam
	_laser.top_level = true
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = laser_color
	mat.emission_enabled = true
	mat.emission = laser_color
	_laser.material_override = mat
	add_child(_laser)
	_laser.visible = false

## Stretch the laser from the muzzle to the aim ray's first hit, ramping its glow from dim
## (just watching) to bright (locked on, about to fire) as the grace period fills.
func _update_laser(hit: Dictionary) -> void:
	if not _laser:
		return
	if not show_laser or not _muzzle:
		_laser.visible = false
		return
	var origin := get_aim_origin()
	var endpoint: Vector3 = hit.position if not hit.is_empty() else origin + get_aim_direction() * _aim_range()
	var dist := origin.distance_to(endpoint)
	if dist < 0.01:
		_laser.visible = false
		return
	# Build the beam basis by hand: Z column = direction * length, so the unit box stretches
	# ALONG the aim; X/Y stay unit + perpendicular so it stays thin. Centred at the midpoint
	# it spans exactly muzzle -> endpoint. (Basis.scaled() scales in the WORLD frame, which
	# stretched the box sideways and out the back — that was the weirdness.)
	var dir := (endpoint - origin) / dist
	var x := dir.cross(Vector3.UP)
	if x.length_squared() < 0.000001:
		x = dir.cross(Vector3.FORWARD)
	x = x.normalized()
	var y := x.cross(dir).normalized()
	_laser.visible = true
	_laser.global_transform = Transform3D(Basis(x, y, dir * dist), (origin + endpoint) * 0.5)
	var charge := clampf(_aim_t / aim_time, 0.0, 1.0) if aim_time > 0.0 else 1.0
	var mat := _laser.material_override as StandardMaterial3D
	if mat:
		mat.emission_energy_multiplier = lerpf(1.0, 8.0, charge)

# --- WeaponHost aim contract: from the muzzle toward the player, no camera ---
func get_aim_origin() -> Vector3:
	return _muzzle.global_position if _muzzle else global_position

func get_aim_direction() -> Vector3:
	if not is_instance_valid(_player) or not _muzzle:
		return -global_basis.z
	return (_aim_point() - _muzzle.global_position).normalized()

func get_aim_basis() -> Basis:
	var dir := get_aim_direction()
	# Avoid a degenerate basis if we're ever aiming near-straight up/down.
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	return Basis.looking_at(dir, up)
