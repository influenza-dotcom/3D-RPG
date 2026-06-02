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

func _ready() -> void:
	# Detach from the parent transform so position/rotation are driven manually below
	# (smoothed follow). Without this the light would rigidly snap with the gun.
	top_level = true

func _process(delta: float) -> void:
	
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
	var parent_rot: Vector3 = get_parent().global_rotation
	if visible:
		var t := 1.0 - exp(-FOLLOW_RATE * delta)
		global_rotation.x = lerp_angle(global_rotation.x, parent_rot.x, t)
		global_rotation.y = lerp_angle(global_rotation.y, parent_rot.y, t)
		global_rotation.z = lerp_angle(global_rotation.z, parent_rot.z, t)
	else:
		global_rotation = parent_rot
	

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Light") and !flashlight_click.playing:
		visible = !visible
		flashlight_click.play()
