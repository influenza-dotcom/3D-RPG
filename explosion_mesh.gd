class_name ExplosionMesh
extends MeshInstance3D

@export var flash_speed: float = 20.0

var _time: float = 0.0
var _material: StandardMaterial3D

func _ready() -> void:
	if mesh == null:
		return
	mesh = mesh.duplicate()
	_material = StandardMaterial3D.new()
	_material.emission_enabled = true
	_material.emission_energy_multiplier = 3.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	set_surface_override_material(0, _material)

func _process(delta: float) -> void:
	if _material == null:
		return
	_time += delta * flash_speed
	var t = (sin(_time) + 1.0) / 2.0
	_material.albedo_color = Color(t, t, t)
	_material.emission = Color(t, t, t)
