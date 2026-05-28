extends MeshInstance3D

## Laser-sight cone mesh, re-aligned to the gun muzzle every frame so it tracks the
## gun's bob/sway. ONLY alignment lives here; visibility and the fade-out are driven
## by flash_light.gd (which also gates it on WeaponData.has_laser_sight). The tricky
## muzzle-basis math below exists because of this gun's 90° bind rotation.

@onready var gun_mesh: GunMesh = $"../GunMesh"
@onready var muzzle: Marker3D = $"../GunMesh/Sketchfab_Scene/Muzzle"

const LASER_HALF_LENGTH: float = 0.125  # half of CylinderMesh.height (0.25)

func _process(_delta: float) -> void:
	# The GunMesh has a 90° Y-rotation in its bind transform, so the muzzle's
	# local -Z ends up pointing camera-right (not forward). The actual barrel
	# direction in world space for this gun's setup is the muzzle's local -X.
	var mb := muzzle.global_transform.basis.orthonormalized()
	var forward := -mb.x
	# Build a basis with +Y aligned to forward (cylinder's length axis).
	# The cylinder is rotationally symmetric around Y so the X and Z choices
	# are cosmetic; -mb.z and mb.y are chosen to keep the basis right-handed.
	var new_basis := Basis(-mb.z, forward, mb.y)
	# Place the cylinder's BASE at the muzzle so the entire cone extends forward.
	global_position = muzzle.global_position + (forward * -.8) * LASER_HALF_LENGTH
	global_transform.basis = new_basis
