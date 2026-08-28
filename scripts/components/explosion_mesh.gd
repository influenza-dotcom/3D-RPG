class_name ExplosionMesh
extends MeshInstance3D

## Pulsing emissive "flash" mesh used for both muzzle flashes and explosion/hit light
## bursts. Each frame it sine-pulses emission energy (and alpha, so a transparent base
## material flickers) around the base material's color, optionally growing from zero.
##
## speed_to_scale: 0 = start at full scale (instant, e.g. muzzle flash); > 0 = start at
## zero and grow toward full (e.g. an explosion bloom), faster for larger values.
##
## ⭐⭐ A FLASH IS LIGHT, NOT GEOMETRY — IT IS EXCLUDED FROM THE WORLD'S INK (2026-08-16).
## `_ready` stamps `InkOutline.ACTOR_INK_MASK_LAYER` unconditionally, and that is not optional
## authoring. The fallback material built below is a StandardMaterial3D with transparency DISABLED
## (the alpha pulse in `_process` only bites on a transparent authored base like bulletmat), so the
## flash sphere writes depth exactly like a wall — and InkOutline's screen-space edge detect drew a
## black ring around every explosion and bullet-impact spark. That was the WORLD's outline on
## something that is meant to read as light, the same defect the player's own first-person body had:
## a mesh with NEITHER a hull rim NOR the mask bit is inked by the wrong system entirely. No stamper
## could ever have reached it — an Explosion is added under the scene root, outside every actor walk.
##
## ⭐ With the bit stamped, `has_outline` below means exactly what it says and the two lines can never
## stack: OFF = a bare flash with no line at all (the explosion/hit spark), ON = InkOutline's screen-space
## ring and only the ring (the muzzle flash). See InkOutline — "the ring and the stamp are one contract".

const EMISSION_ENERGY_MULTIPLIER: float = 3.0

## How the flash grows in. 0 = pops in at full scale instantly (a muzzle flash); > 0 = starts at zero and swells toward full size, larger values swelling faster (an explosion bloom).
@export var speed_to_scale: float
## Add a black silhouette outline around the flash mesh (toon look). This is the flash's ONLY line —
## it is excluded from the world's ink either way (class doc). Off = a bare emissive flash with no outline
## at all (explosions, hit sparks); on = InkOutline's ring, and only the ring (the muzzle flash).
## ⭐ The ring wears InkOutline.TINT_ID_NEUTRAL, so it paints the same black at the same weight as every other
## outline in the game — the per-flash OUTLINE_COLOR / OUTLINE_WIDTH consts went with the inverted hull on
## 2026-08-27. It also lands on a mesh whose SCALE is animated from zero, which the ring handles for free
## (the duplicate is a child, so it inherits the swell) where a constant-screen-width shell around a
## sub-centimetre sphere was always going to be thicker than the flash it wrapped.
@export var has_outline: bool = false

var _time: float = 0.0
var _material: StandardMaterial3D
var _base_emission_energy: float = EMISSION_ENERGY_MULTIPLIER
var _base_emission: Color = Color.WHITE
var _base_albedo: Color = Color.WHITE

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Register the flash with InkOutline's actor mask (see the class doc). OR-ed, so the scene's authored
	# layers survive, and done BEFORE the mesh-less early return below — a drop-in whose mesh is assigned
	# later must not be the one flash left wearing the world's ink line.
	layers |= InkOutline.ACTOR_INK_MASK_LAYER
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
	set_surface_override_material(0, _material)
	# The outline goes on LAST and as an id, not a material: the flash's own surface override is what the
	# duplicate mirrors, and stamping before it is assigned would mirror the mesh's authored material instead.
	if has_outline:
		InkOutline.apply_tint_mesh(self, InkOutline.TINT_ID_NEUTRAL)

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
