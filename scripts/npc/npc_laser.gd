class_name NpcLaser
extends Node3D

## The combatant's laser-SIGHT beam — the drawn telegraph that brightens as the NPC detects / locks
## onto its target. Built entirely in code (a top_level MeshInstance3D, no .tscn). Split off NPC so
## the root keeps only the AIM contract (the ray cast + clear-shot test in _aim_laser_at); this child
## owns just the VISUAL: stretching a unit box muzzle->endpoint and ramping the additive shader's hue
## + strength. NPC computes the endpoint (it has the ray hit + weapon range) then calls draw_beam().
##
## Host-coupled: NPC builds it in _ready only for a combatant (weapon_data set) and sets `host` right
## after .new(); it READS the host's _outline_color_for_disposition() for the disposition hue. Off-tree
## (a unit-test NPC built via .new() with no add_child) this child never exists, so NPC's facades guard
## on _laser being null — _aim_laser_at then takes its no-laser path exactly as the monolith did.

## How bright the additive laser beam adds at full charge (its disposition hue x this). Higher = a more
## intense glow; the per-frame charge then scales the amount actually added (fading it to invisible).
const LASER_ADD_BRIGHTNESS: float = 3.0
const NPC_LASER_SHADER := preload("res://resources/shaders/npc_laser.gdshader")

## The NPC this beam belongs to — set right after .new() in NPC._ready. READ-only here (we pull its
## disposition hue); the canonical state stays on the host.
var host: NPC

## The beam MeshInstance3D, built in setup(). Held as a child of this node; top_level keeps it in world
## space, so its placement ignores both this node's and the NPC's (rotating) transform.
var _beam: MeshInstance3D

func setup() -> void:
	_beam = MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(0.02, 0.02, 1.0)
	_beam.mesh = beam
	_beam.top_level = true  # ignore our own (rotating) transform; placed in world space
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Dedicated ADDITIVE beam shader (blend_add in its render_mode = unambiguously additive, unlike a
	# StandardMaterial3D blend_mode which can still alpha-blend and darken). Brightness rises with the
	# shot's charge (set in draw_beam); at strength 0 it adds nothing and is simply invisible.
	var mat := ShaderMaterial.new()
	mat.shader = NPC_LASER_SHADER
	var hue := host._outline_color_for_disposition()
	mat.set_shader_parameter(&"beam_color", Vector3(hue.r, hue.g, hue.b))
	mat.set_shader_parameter(&"strength", 0.0)
	_beam.material_override = mat
	# Parent the beam under THIS node (a plain child of the NPC), NOT the tree root: adding to root
	# during the NPC's _ready races the scene's own child setup (the "parent is busy setting up children"
	# error when spawned mid-frame). It still lives OUTSIDE the NPC's `mesh` subtree, so the outline +
	# look-at-highlight sweeps (which only walk under `mesh`) skip the see-through beam; top_level keeps
	# it world-placed. Auto-freed with us (and us with the NPC).
	add_child(_beam)
	_beam.visible = false

## Stretch the beam from `origin` to `endpoint`, tinted `hue` and brightened by `charge` (0..1). Hides
## itself for a degenerate (near-zero-length) span. The unit box's Z column = direction * length (so it
## stretches ALONG the aim); X/Y kept unit + perpendicular so it stays thin; centred at the midpoint it
## spans exactly origin -> endpoint.
func draw_beam(origin: Vector3, endpoint: Vector3, charge: float, hue: Color) -> void:
	if _beam == null:
		return
	var dist := origin.distance_to(endpoint)
	if dist < 0.01:
		_beam.visible = false
		return
	var bdir := (endpoint - origin) / dist
	var x := bdir.cross(Vector3.UP)
	if x.length_squared() < 0.000001:
		x = bdir.cross(Vector3.FORWARD)
	x = x.normalized()
	var y := x.cross(bdir).normalized()
	_beam.visible = true
	_beam.global_transform = Transform3D(Basis(x, y, bdir * dist), (origin + endpoint) * 0.5)
	var mat := _beam.material_override as ShaderMaterial
	if mat:
		# Brightness (additive strength) ramps with the charge: invisible while merely noticing you,
		# bright the instant it's locked — fading DOWN just adds less light, never darkens to black.
		# Hue tracks the NPC's disposition (red hostile, green friendly), so the beam reads its attitude.
		mat.set_shader_parameter(&"beam_color", Vector3(hue.r, hue.g, hue.b))
		mat.set_shader_parameter(&"strength", clampf(charge, 0.0, 1.0) * LASER_ADD_BRIGHTNESS)

## Hide the beam. NOT named hide() — Node3D already exposes hide(), and overriding a native method is a
## GDScript warning treated as an error in this project, so the host's _hide_laser facade calls this.
func hide_beam() -> void:
	if _beam:
		_beam.visible = false
