class_name AmbientDust
extends GPUParticles3D

## Level-wide floating dust motes. Drop ONE instance anywhere in the level: in _ready it
## builds its own particle material, and every frame it re-centres its emission volume on
## the active camera — so a soft dust haze always surrounds the player without filling the
## whole map with particles. Motes are simulated in world space (local_coords off) so you
## move through them with natural parallax instead of them sticking to the view. Tune the
## look with the exported fields below or on the GPUParticles3D itself.

## Number of motes alive at once inside the volume. Higher = thicker haze (and more cost).
@export var motes: int = 350
## Seconds each mote lives before respawning (also how long it takes the field to fill).
@export var mote_lifetime: float = 14.0
## Half-extents (metres) of the emission box that re-centres on the camera each frame.
@export var volume_extents: Vector3 = Vector3(20.0, 10.0, 20.0)
## World size of a single mote quad (metres). Keep tiny — these are specks.
@export var mote_size: float = 0.02
## Base colour + alpha of a mote. Low alpha keeps it a subtle haze, not fog.
@export var mote_color: Color = Color(0.86, 0.82, 0.74, 0.13)
## Gentle downward drift (m/s) so motes settle slowly.
@export var drift: float = 0.04
## Floating turbulence strength — the wandering, never-quite-still motion.
@export var turbulence: float = 0.15

func _ready() -> void:
	local_coords = false
	randomness = 1.0
	fixed_fps = 30
	lifetime = mote_lifetime
	# Simulate a full lifetime up front so the air is already dusty at level start.
	preprocess = mote_lifetime
	# Generous culling box so the field never pops as the emitter chases the camera.
	var pad := volume_extents + Vector3(5.0, 5.0, 5.0)
	visibility_aabb = AABB(-pad, pad * 2.0)
	process_material = _build_process_material()
	draw_pass_1 = _build_mote_mesh()
	# Set amount last: it restarts the system with the material + preprocess applied.
	amount = maxi(1, motes)

func _build_process_material() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = volume_extents
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 180.0
	pm.gravity = Vector3(0.0, -drift, 0.0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = drift * 1.5
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = turbulence
	pm.turbulence_noise_scale = 1.5
	pm.color = mote_color
	pm.color_ramp = _build_fade_ramp()
	return pm

## Alpha ramp over a mote's life: fade in at birth, hold, fade out at death — no popping.
func _build_fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)
	])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex

func _build_mote_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(mote_size, mote_size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Per-mote colour (from the process material + life ramp) drives the albedo.
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	# Soften motes where they pass close to walls/floors instead of hard-clipping.
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 0.5
	quad.material = mat
	return quad

func _process(_delta: float) -> void:
	# Re-centre the emission volume on whatever camera is currently rendering, so the
	# haze follows the player everywhere. Existing motes stay put (world space).
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position
