extends Node

## @system PS1 Warp
## @seam Runtime ShaderMaterial overrides on opaque BaseMaterial3D surfaces only, skipping Character/Throwable/Camera3D; live-scaled by Settings.ps1_warp_intensity, and 0% restores originals.
## @risk If _warp's Character/Throwable/Camera3D skip regresses, actor outline/hit-flash and the FP view-model warp silently — no test covers the subtree walk.
## @risk If _restore stops clearing overrides or restoring cast_shadow, 0% no longer returns the world to normal — an accessibility regression with no round-trip test.
## @test res://tests/test_ps1_applier.gd
## @test res://tests/test_effects.gd
## PS1 warp applier. Walks the level and swaps each OPAQUE mesh surface's material for ps1.gdshader
## (vertex snapping + affine/perspective-incorrect texture mapping), carrying over each surface's
## albedo texture + colour so the level keeps its look — just warped + crunchy.
##
## NON-DESTRUCTIVE: it sets surface OVERRIDE materials on the live instances at runtime, so your saved
## scene and its materials are untouched — everything restores when you stop the game, OR when the
## accessibility slider drops the warp to 0% (the overrides are cleared and the originals return).
## (That also means you see the effect on PLAY, not in the editor viewport — for now.)
##
## ACCESSIBILITY: the global `Settings.ps1_warp_intensity` (Options → Accessibility, 0..100%) scales the
## effect LIVE. 100% = the authored `vertex_snap` / `affine_amount` below (the full effect); lower values
## reduce the visible vertex JITTER (the motion-sickness trigger — amplitude ∝ 1/vertex_snap) and the
## affine texture swim PROPORTIONALLY; 0% clears the overrides so the level renders normally. It's polled
## each frame, so moving the slider re-applies / rescales / restores without a level reload. The mapping is
## the pure, unit-tested `warp_params()` below.
##
## Skips: Characters (player, enemies) + Throwables (gibs/crates), so their outline/hit-flash
## overlays survive; transparent/cutout materials (foliage, glass), because the warp shader is
## opaque — pushing alpha through it would punch holes in the mesh and its shadow; and any
## non-BaseMaterial3D surface — a ShaderMaterial (authored effect, OR our own ps1 override on a
## re-walk, so the walk is idempotent) or a material-less surface has no albedo to carry into the
## warp, and swapping it would paint it flat white. Only plain BaseMaterial3D surfaces are warpable.
##
## USE: add a plain Node to your Level scene, attach this script, press play. Tune in the inspector.
## (The `Ps1Warp` autoload — ps1_warp.gd — does exactly this AUTOMATICALLY for every LevelRoot as it loads, so you
## only add the Node by hand for a non-level scene that still wants the warp, e.g. computerroom.tscn.)

## Master switch: when off, the PS1 warp is never applied and the level renders normally.
@export var enabled: bool = true
## LOWER = chunkier wobble. ~48 heavy PS1, ~80 moderate, ~200 subtle. This is the FULL-intensity (100%)
## base — the accessibility slider scales the visible jitter down from here.
@export var vertex_snap: float = 80.0
## 0 = normal perspective UVs, 1 = full PS1 texture warp. The FULL-intensity (100%) base; the slider scales it.
@export_range(0.0, 1.0) var affine_amount: float = 1.0
## Let warped geometry keep casting shadows. The vertex jitter can speckle dynamic shadows (acne),
## worse at low vertex_snap — turn this OFF for a clean look (PS1 had no real-time shadows anyway).
@export var cast_shadows: bool = true
## What to warp. Leave empty to warp the whole running scene.
@export var target_root: Node

const PS1_SHADER: Shader = preload("res://resources/shaders/ps1.gdshader")
## Effective-snap ceiling: at low intensity `vertex_snap / t` blows up, so cap it at a grid fine enough
## that no snap is visible (a huge grid = sub-pixel = no jitter). Keeps a near-zero slider value sane.
const SNAP_CEIL := 4096.0

var _mat_cache: Dictionary = {}             ## source Material -> the shared ShaderMaterial we swapped in
var _warped: Array[Dictionary] = []         ## restore records: {mi, surfaces: Array[int], shadow: int}
var _applied: bool = false
var _last_t: float = -1.0                    ## last intensity we refreshed at (-1 forces a first-frame apply)
var _settings: Node = null                   ## the Settings autoload (null in a bare harness -> full effect)

func _ready() -> void:
	_settings = get_node_or_null(^"/root/Settings")
	# Driven from _process so BOTH the whole scene tree is in place AND the live accessibility intensity is
	# honoured (apply / rescale / restore as the player moves the slider) without a level reload.
	set_process(true)

func _process(_delta: float) -> void:
	var t := _intensity()
	if is_equal_approx(t, _last_t):
		return
	_last_t = t
	_refresh(t)

## The live effect strength 0..1: the player's accessibility slider, gated by this applier's own `enabled`.
func _intensity() -> float:
	if not enabled:
		return 0.0
	if _settings == null:
		return 1.0  # no Settings autoload (a bare test / harness) -> the authored full effect
	# Per-frame autoload read via .get() + null-guard (reimport-safe), not a direct property access.
	var v: Variant = _settings.get(&"ps1_warp_intensity")
	return clampf(float(v) if v != null else 1.0, 0.0, 1.0)

func _refresh(t: float) -> void:
	if t <= 0.0:
		_restore()        # 0% -> clear the overrides; the level renders normally
		return
	if not _applied:
		_apply_warp()     # first time (or returning from 0%): walk the scene + swap materials
	_update_params(t)     # (re)scale the shared shader params to the current intensity

## Pure mapping from accessibility intensity (0..1) to the two shader params. t=1 -> the authored full
## effect; lower t scales the jitter AMPLITUDE (∝ 1/vertex_snap) and the affine warp LINEARLY toward 0;
## t<=0 means "don't apply" (render normally). Static + pure so it's unit-testable off-tree.
static func warp_params(base_snap: float, base_affine: float, t: float) -> Dictionary:
	var tt := clampf(t, 0.0, 1.0)
	if tt <= 0.0:
		return {"apply": false, "snap": base_snap, "affine": 0.0}
	return {
		"apply": true,
		"snap": minf(base_snap / tt, SNAP_CEIL),   # finer grid (less jitter) as intensity drops
		"affine": clampf(base_affine * tt, 0.0, 1.0),
	}

func _update_params(t: float) -> void:
	var p := warp_params(vertex_snap, affine_amount, t)
	for mat in _mat_cache.values():
		mat.set_shader_parameter("vertex_snap", p["snap"])
		mat.set_shader_parameter("affine_amount", p["affine"])

func _apply_warp() -> void:
	_applied = true
	var root: Node = target_root if target_root else get_tree().current_scene
	if root:
		_warp(root)

func _restore() -> void:
	if not _applied:
		return
	for rec in _warped:
		var mi = rec["mi"]  # untyped: is_instance_valid FIRST (a typed cast on a freed node hard-errors)
		if not is_instance_valid(mi):
			continue
		for s in rec["surfaces"]:
			mi.set_surface_override_material(s, null)
		mi.cast_shadow = rec["shadow"]
	_warped.clear()
	_mat_cache.clear()
	_applied = false

func _warp(node: Node) -> void:
	# Actors run their own material overlays (outline / hit-flash), and a Camera3D's children are the FP
	# view-model / full-screen post-process quads (e.g. the pixel.gdshader screen quad) — warping either is
	# never intended, so skip their whole subtree.
	if node is Character or node is Throwable or node is Camera3D:
		return
	if node is MeshInstance3D:
		_ps1ify(node as MeshInstance3D)
	for child in node.get_children():
		_warp(child)

func _ps1ify(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	var surfaces: Array[int] = []
	for s in mi.mesh.get_surface_count():
		var src := mi.get_active_material(s)
		# Only warp plain BaseMaterial3D surfaces — we carry their albedo tex/colour into the warp. A ShaderMaterial
		# (including our OWN ps1 override on a re-walk -> idempotent) or a null/None surface has no albedo to read;
		# swapping it for the opaque warp shader would paint it flat white and wipe an authored shader effect. Skip it.
		if not (src is BaseMaterial3D):
			continue
		# Leave transparent / cutout materials alone — the warp shader is opaque, so pushing a
		# texture with alpha through it would hole the mesh AND its shadow.
		if (src as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var mat: ShaderMaterial = _mat_cache.get(src)
		if mat == null:
			mat = ShaderMaterial.new()
			mat.shader = PS1_SHADER
			# src is guaranteed BaseMaterial3D here (the skip above), so read its albedo directly — no white fallback.
			var bm := src as BaseMaterial3D
			var tex: Texture2D = bm.albedo_texture
			mat.set_shader_parameter("albedo_tex", tex)
			mat.set_shader_parameter("use_texture", tex != null)
			mat.set_shader_parameter("albedo_color", bm.albedo_color)
			# vertex_snap / affine_amount are set by _update_params right after this walk, scaled to intensity.
			_mat_cache[src] = mat
		mi.set_surface_override_material(s, mat)
		surfaces.append(s)
	if surfaces.is_empty():
		return
	# Record what we changed so _restore() can put the originals (and shadow mode) back at 0% intensity.
	# `shadow` is captured BEFORE we (maybe) flip it off below, so restore returns the authored setting.
	_warped.append({"mi": mi, "surfaces": surfaces, "shadow": mi.cast_shadow})
	# Only the geometry we actually warped is at risk of shadow acne from the jitter.
	if not cast_shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
