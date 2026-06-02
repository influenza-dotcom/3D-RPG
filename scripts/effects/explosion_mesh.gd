class_name ExplosionMesh
extends MeshInstance3D

## Pulsing emissive "flash" mesh used for both muzzle flashes and explosion/hit light
## bursts. Each frame it sine-pulses emission energy (and alpha, so a transparent base
## material flickers) around the base material's color, optionally growing from zero.
##
## speed_to_scale: 0 = start at full scale (instant, e.g. muzzle flash); > 0 = start at
## zero and grow toward full (e.g. an explosion bloom), faster for larger values.

const EMISSION_ENERGY_MULTIPLIER: float = 3.0
const OUTLINE_SHADER = preload("res://resources/shaders/outline.gdshader")
const OUTLINE_COLOR: Color = Color.BLACK
const OUTLINE_WIDTH: float = 1.0

@export var speed_to_scale: float
@export var has_outline: bool = false

var _time: float = 0.0
var _material: StandardMaterial3D
var _outline_material: ShaderMaterial
var _base_emission_energy: float = EMISSION_ENERGY_MULTIPLIER
var _base_emission: Color = Color.WHITE
var _base_albedo: Color = Color.WHITE

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scale = Vector3.ZERO if speed_to_scale > 0.0 else Vector3.ONE
	if mesh == null:
		return
	mesh = mesh.duplicate()
	# If the scene already set a surface material (e.g. bulletmat on the muzzle
	# flash), use it as the base so the flash inherits its color/emission/etc.
	# Otherwise fall back to a generic white flash material.
	var existing := get_surface_override_material(0)
	if existing is StandardMaterial3D:
		_material = (existing as StandardMaterial3D).duplicate()
		_base_emission_energy = _material.emission_energy_multiplier
		_base_emission = _material.emission
		_base_albedo = _material.albedo_color
	else:
		_material = StandardMaterial3D.new()
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.emission_enabled = true
	if has_outline:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = OUTLINE_SHADER
		_outline_material.set_shader_parameter("outline_color", OUTLINE_COLOR)
		_outline_material.set_shader_parameter("outline_width", OUTLINE_WIDTH)
		_material.next_pass = _outline_material
	set_surface_override_material(0, _material)

func _process(delta: float) -> void:
	if _material == null:
		return
	_time += delta * GameSettings.effects.explosion_flash_speed
	var t := (sin(_time) + 1.0) / 2.0
	# Pulse the brightness while keeping the base material's color. Alpha
	# pulses so transparent materials (bulletmat) fade in/out per cycle.
	var pulse_albedo := _base_albedo
	pulse_albedo.a = _base_albedo.a * t
	_material.albedo_color = pulse_albedo
	_material.emission = _base_emission
	_material.emission_energy_multiplier = _base_emission_energy * t
	if speed_to_scale > 0.0:
		var grow_t := 1.0 - exp(-speed_to_scale * GameSettings.effects.explosion_light_grow_speed * delta)
		scale = scale.lerp(Vector3.ONE, grow_t)

## Recolour the flash to `c` (the paint splat uses this to match the paint). Call after _ready so it
## overrides the base material's colour; _process keeps pulsing around the new colour.
func tint(c: Color) -> void:
	_base_albedo = Color(c.r, c.g, c.b, _base_albedo.a)
	_base_emission = c
	if _material:
		_material.albedo_color = _base_albedo
		_material.emission = _base_emission
