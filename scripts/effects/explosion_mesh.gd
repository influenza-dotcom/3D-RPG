class_name ExplosionMesh
extends MeshInstance3D

const EMISSION_ENERGY_MULTIPLIER: float = 3.0

@export var speed_to_scale: float

var _time: float = 0.0
var _material: StandardMaterial3D

func _ready() -> void:
	scale = Vector3.ZERO
	if mesh == null:
		return
	mesh = mesh.duplicate()
	_material = StandardMaterial3D.new()
	_material.emission_enabled = true
	_material.emission_energy_multiplier = EMISSION_ENERGY_MULTIPLIER
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	set_surface_override_material(0, _material)

func _process(delta: float) -> void:
	if _material == null:
		return
	_time += delta * GameTuning.EXPLOSION_FLASH_SPEED
	var t := (sin(_time) + 1.0) / 2.0
	_material.albedo_color = Color(t, t, t)
	_material.emission = Color(t, t, t)
	var grow_t := 1.0 - exp(-speed_to_scale * GameTuning.EXPLOSION_LIGHT_GROW_SPEED * delta)
	scale = scale.lerp(Vector3.ONE, grow_t)
