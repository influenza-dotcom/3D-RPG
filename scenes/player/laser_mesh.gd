extends MeshInstance3D

## Laser-sight cone, re-aligned to the gun every frame. POSITION comes from the equipped weapon's
## own "Muzzle" marker (so it sits on whatever gun is held; falls back to the rig's built-in muzzle);
## DIRECTION comes from the rig muzzle's basis, whose local -X is world barrel-forward thanks to the
## GunMesh's 90° Y bind. ONLY alignment lives here; visibility + fade are driven by flash_light.gd.

@onready var gun_mesh: GunMesh = $"../GunMesh"
@onready var muzzle: Marker3D = $"../GunMesh/Sketchfab_Scene/PlayerMuzzle"

const LASER_HALF_LENGTH: float = 0.125  # half of CylinderMesh.height (0.25)

func _process(_delta: float) -> void:
	# The laser dot is a see-through emitter, never an outlined prop: force its overlay slot empty so no
	# outline sweep can ever wrap it (the beam itself keeps its own surface laser shader).
	if material_overlay != null:
		material_overlay = null
	# Direction from the rig muzzle's basis — its local -X is the world barrel direction
	# (camera-forward) for this rig's 90° bind. The cylinder's length axis is +Y; -mb.z / mb.y
	# are chosen to keep the basis right-handed (cosmetic, since the cone is radially symmetric).
	var mb := muzzle.global_transform.basis.orthonormalized()
	var forward := -mb.x
	var new_basis := Basis(-mb.z, forward, mb.y)
	# Position from the equipped weapon's own "Muzzle" marker (case-insensitive), else the rig muzzle.
	var anchor: Node3D = gun_mesh.equipped_marker("muzzle") if gun_mesh else null
	var origin: Vector3 = anchor.global_position if anchor else muzzle.global_position
	global_position = origin + (forward * -0.8) * LASER_HALF_LENGTH
	global_transform.basis = new_basis
