extends Node

## PS1 warp applier. Walks the level and swaps each OPAQUE mesh surface's material for ps1.gdshader
## (vertex snapping + affine/perspective-incorrect texture mapping), carrying over each surface's
## albedo texture + colour so the level keeps its look — just warped + crunchy.
##
## NON-DESTRUCTIVE: it sets surface OVERRIDE materials on the live instances at runtime, so your
## saved scene and its materials are untouched and everything restores when you stop the game.
## (That also means you see the effect on PLAY, not in the editor viewport — for now.)
##
## Skips: Characters (player, enemies) + Interactables (gibs/crates), so their outline/hit-flash
## overlays survive; and transparent/cutout materials (foliage, glass), because the warp shader is
## opaque — pushing alpha through it would punch holes in the mesh and its shadow.
##
## USE: add a plain Node to your Level scene, attach this script, press play. Tune in the inspector.

@export var enabled: bool = true
## LOWER = chunkier wobble. ~48 heavy PS1, ~80 moderate, ~200 subtle.
@export var vertex_snap: float = 80.0
## 0 = normal perspective UVs, 1 = full PS1 texture warp.
@export_range(0.0, 1.0) var affine_amount: float = 1.0
## Let warped geometry keep casting shadows. The vertex jitter can speckle dynamic shadows (acne),
## worse at low vertex_snap — turn this OFF for a clean look (PS1 had no real-time shadows anyway).
@export var cast_shadows: bool = true
## What to warp. Leave empty to warp the whole running scene.
@export var target_root: Node

const PS1_SHADER: Shader = preload("res://resources/shaders/ps1.gdshader")

var _mat_cache: Dictionary = {}

func _ready() -> void:
	if enabled:
		# Deferred so the whole scene tree is in place before we walk it.
		_apply.call_deferred()

func _apply() -> void:
	var root: Node = target_root if target_root else get_tree().current_scene
	if root:
		_warp(root)

func _warp(node: Node) -> void:
	# Actors run their own material overlays (outline / hit-flash) — leave them and their
	# subtrees alone so we don't strip those.
	if node is Character or node is Interactable:
		return
	if node is MeshInstance3D:
		_ps1ify(node as MeshInstance3D)
	for child in node.get_children():
		_warp(child)

func _ps1ify(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	var warped_any := false
	for s in mi.mesh.get_surface_count():
		var src := mi.get_active_material(s)
		# Leave transparent / cutout materials alone — the warp shader is opaque, so pushing a
		# texture with alpha through it would hole the mesh AND its shadow.
		if src is BaseMaterial3D and (src as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var mat: ShaderMaterial = _mat_cache.get(src)
		if mat == null:
			mat = ShaderMaterial.new()
			mat.shader = PS1_SHADER
			var tex: Texture2D = null
			var col := Color.WHITE
			if src is BaseMaterial3D:
				tex = (src as BaseMaterial3D).albedo_texture
				col = (src as BaseMaterial3D).albedo_color
			mat.set_shader_parameter("albedo_tex", tex)
			mat.set_shader_parameter("use_texture", tex != null)
			mat.set_shader_parameter("albedo_color", col)
			mat.set_shader_parameter("vertex_snap", vertex_snap)
			mat.set_shader_parameter("affine_amount", affine_amount)
			_mat_cache[src] = mat
		mi.set_surface_override_material(s, mat)
		warped_any = true
	# Only the geometry we actually warped is at risk of shadow acne from the jitter.
	if warped_any and not cast_shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
