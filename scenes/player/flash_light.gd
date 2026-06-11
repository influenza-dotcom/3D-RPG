extends SpotLight3D

## Flashlight spot + laser-sight controller. Toggled by the "Light" action; while on it
## smoothly tracks the gun's aim, sets its throw distance from the equipped weapon's
## effective_range, and drives the separate LaserMesh's visibility (gated by
## WeaponData.has_laser_sight). top_level (see _ready) so it follows by manual lerp
## rather than rigidly inheriting the parent transform — giving the light a slight lag.

const FOLLOW_RATE: float = 15.0

@export var light_position: Marker3D
@onready var flashlight_click: AudioStreamPlayer3D = $FlashlightClick

@onready var laser_mesh: MeshInstance3D = $"../LaserMesh"
@onready var attack: Attack = $"../../../../Weapon/Attack"
@onready var gun_mesh: GunMesh = get_node_or_null("../GunMesh") as GunMesh

var _light_on: bool = false  ## the "Light" toggle state, decoupled from actual visibility (holster gating)

func _ready() -> void:
	# Detach from the parent transform so position/rotation are driven manually below
	# (smoothed follow). Without this the light would rigidly snap with the gun.
	top_level = true
	_light_on = visible  # seed the toggle state from whatever the scene set as the initial on/off

func _process(delta: float) -> void:
	# The laser-sight light only shines when toggled on, the weapon is out, AND this weapon has a laser
	# sight — so holstering, or a no-laser weapon (e.g. the sniper, has_laser_sight = false), hides the
	# red dot it projects onto the world too, not just the muzzle beam mesh.
	# The laser/flashlight is an UNLOCKABLE upgrade: stays dark until the wielder has the "laser_sight" mechanic
	# (duck-typed; a wielder with no unlock system is treated as having it).
	var wielder: Node = attack.character if attack else null
	var laser_unlocked := wielder == null or not wielder.has_method(&"has_mechanic") or wielder.has_mechanic(&"laser_sight")
	visible = _light_on and not attack.holstered and attack.current_weapon != null and attack.current_weapon.has_laser_sight and laser_unlocked
	if attack.current_weapon and attack.current_weapon.effective_range > 0.0:
		spot_range = attack.current_weapon.effective_range
	else:
		spot_range = 15.0
	
	# Only show the laser with the gun fully out — not while it's still swapping/reloading or
	# tweening back up into view (otherwise it draws from the half-raised muzzle).
	var gun_ready := not attack.is_reload_or_swap_active() and (gun_mesh == null or gun_mesh.is_raised())
	laser_mesh.visible = visible and attack.current_weapon != null and attack.current_weapon.has_laser_sight and gun_ready
	
	if light_position:
		global_position = light_position.global_position
	# Aim the laser DOT where the SHOT actually goes: along the player's swayed aim direction (Deus Ex —
	# the crosshair stays centred, this dot is what visibly wanders and settles). Fall back to the gun's
	# own facing when the player ref / aim is unavailable (or near-vertical, where looking_at degenerates).
	var player: Node = attack.character if attack else null
	var aim_dir := Vector3.ZERO
	if player != null and player.has_method(&"get_aim_direction"):
		aim_dir = player.get_aim_direction()
	var target_rot: Vector3 = get_parent().global_rotation
	if aim_dir.length_squared() > 0.0001 and absf(aim_dir.normalized().y) < 0.99:
		target_rot = Basis.looking_at(aim_dir).get_euler()
	if visible:
		var t := 1.0 - exp(-FOLLOW_RATE * delta)
		global_rotation.x = lerp_angle(global_rotation.x, target_rot.x, t)
		global_rotation.y = lerp_angle(global_rotation.y, target_rot.y, t)
		global_rotation.z = lerp_angle(global_rotation.z, target_rot.z, t)
	else:
		global_rotation = target_rot
	

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("Light") or flashlight_click.playing:
		return
	# Only toggle when this weapon actually HAS a laser sight and it's drawn (i.e. the laser can be
	# visible). A no-laser weapon (e.g. the sniper, has_laser_sight = false) or a holstered gun ignores
	# the key entirely — you can't toggle a sight that isn't there.
	if attack.current_weapon == null or not attack.current_weapon.has_laser_sight or attack.holstered:
		return
	_light_on = not _light_on
	flashlight_click.play()
