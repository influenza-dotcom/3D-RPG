extends Node

## @system PS1 Warp
## @seam Runtime ShaderMaterial overrides on opaque BaseMaterial3D surfaces only, skipping Character/Throwable/Camera3D; live-scaled by Settings.ps1_warp_intensity, and 0% restores originals.
## @risk If _warp's Character/Throwable/Camera3D skip regresses, actor outline/hit-flash and the FP view-model warp silently — no test covers the subtree walk.
## @risk If _restore stops clearing overrides or restoring cast_shadow, 0% no longer returns the world to normal — an accessibility regression with no round-trip test.
## @test res://tests/test_ps1_applier.gd
## @test res://tests/test_effects.gd
## PS1 warp applier. Walks the level and swaps each OPAQUE mesh surface's material for ps1.gdshader
## (vertex snapping; the shader's affine/perspective-incorrect texture mapping is OPT-IN and ships
## off — see affine_amount below), carrying over each surface's albedo texture + colour so the level
## keeps its look — geometry wobbles, textures stay perspective-correct + crunchy.
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
## Snap-grid density: cells across the screen = 2 * value, and — because the func_godot brush mesh is
## UNWELDED (private per-face vertices, T-junctions, float-approximate corners) — every edge can tear
## open by up to ONE CELL, showing the sky through hollow buildings. So cell width = wobble amplitude
## = max tear width: ONE dial. 396 = one cell per texel of the ACTUAL 792-wide screen buffer (396x216
## window x viewport-stretch 0.5 -> 792x444; ui.tscn's post render_scale 1584 is finer than the buffer,
## so the buffer texel is the real pixel), the authentic PS1 ratio — every snap step is exactly one
## screen texel and tears read as pixel crawl, not holes. LOWER = chunkier wobble but proportionally
## wider sky-holes (the old 80 tore ~12px gaps). This is the FULL-intensity (100%) base — the
## accessibility slider scales the visible jitter down from here.
@export var vertex_snap: float = 396.0
## Far fade (metres of view depth): the snap eases out across [start, end] and distant geometry
## renders UNWARPED. This is what stops DISTANT BUILDINGS from strobing: the map's coplanar flush
## brush faces z-fight, and per-frame snap jitter re-randomizes the winner (flashing) while seam
## tears pierce to the sky and the camera's 30m far-DOF re-blurs the jitter (shimmer). The fade is
## continuous in depth, so it can never tear a seam open itself; wobble stays full up close.
@export_range(1.0, 200.0, 0.5, "or_greater") var snap_far_fade_start: float = 20.0
@export_range(1.0, 400.0, 0.5, "or_greater") var snap_far_fade_end: float = 40.0
## Near fade (metres of view depth): the snap also eases IN across [start, end] from the camera, so
## point-blank walls and the floor right at your feet hold still — the comfort job stabilize_floor_surfaces
## used to do, minus its seams (the fade is continuous in depth, so it cannot tear one open).
@export_range(0.05, 20.0, 0.05, "or_greater") var snap_near_fade_start: float = 0.75
@export_range(0.05, 40.0, 0.05, "or_greater") var snap_near_fade_end: float = 1.5
## 0 = normal perspective UVs, 1 = full PS1 texture warp. DEFAULT 0 (off): on this project's huge brush
## triangles the affine swim smears textures into an ugly stretch that reads as broken rendering, not
## retro — the shipped look is vertex wobble ONLY, with textures glued to the geometry. Opt in per
## instance (it's still the FULL-intensity base the accessibility slider scales) if you want the melt.
@export_range(0.0, 1.0) var affine_amount: float = 0.0
## Depth window (view-space metres) the affine texture warp spans. Affine error on a triangle grows with the
## far/near depth RATIO across it — the PS1 hid that by subdividing everything into small polys, but our brush
## levels run ONE triangle across a whole floor/wall, which smears the texture into soup at full affine. The
## shader clamps depth into [affine_near, affine_far], bounding the worst case: perspective-correct closer than
## affine_near (clean point-blank), the retro swim in the mid-range, correct again for faces wholly past
## affine_far. Widen the window for more melt, tighten it for cleaner textures.
## (The shader guards misauthoring: near is floored at 0.001 and far is floored at near.)
@export_range(0.01, 100.0, 0.01, "or_greater") var affine_near: float = 1.0
@export_range(0.01, 500.0, 0.01, "or_greater") var affine_far: float = 6.0
## Let warped geometry keep casting shadows. Safe now: the shader skips snapping in the shadow pass
## (ps1.gdshader IN_SHADOW_PASS branch — a snapped shadow map strobed every lit surface), so cast
## shadows are stable. Turn OFF only for the flat look (the real PS1 had no real-time shadows).
@export var cast_shadows: bool = true
## Keep walkable / floor-like horizontal surfaces out of the warp. OFF by default since the 1-texel-cell
## era: freezing floors while their adjoining walls warp TEARS a flickering seam along every contact line
## (stair tread/riser edges, building bases), because a frozen vertex and a snapped vertex separate by up
## to one cell — coincident vertices only stay glued when EVERYTHING snaps identically. At 1-texel cells
## the ground motion this once prevented is minor, and snap_near_fade_* below quiets the underfoot area
## seam-free. Flip ON only if a level's floors feel swimmy AND its floor textures never touch warped walls.
@export var stabilize_floor_surfaces: bool = false
## What to warp. Leave empty to warp the whole running scene.
@export var target_root: Node

const PS1_SHADER: Shader = preload("res://resources/shaders/ps1.gdshader")
## Effective-snap ceiling: at low intensity `vertex_snap / t` blows up, so cap it at a grid fine enough
## that no snap is visible (a huge grid = sub-pixel = no jitter). Keeps a near-zero slider value sane.
const SNAP_CEIL := 4096.0
## Floor test (stabilize_floor_surfaces), all three read by _surface_is_floor_like:
## |normal.y| at/above which a triangle counts as HORIZONTAL — 0.65 ≈ within ~49° of flat, so ramps and slightly
## uneven ground still read as floor (deliberately generous: a warping ramp slides just as badly as a warping floor).
const FLOOR_NORMAL_Y := 0.65
## Fraction of a surface's total triangle AREA that must be horizontal for the whole surface to count as a floor.
## Area-weighted, not triangle-counted, so one big ground quad outvotes a mess of tiny vertical curb/trim tris.
const FLOOR_AREA_RATIO := 0.55
## Degenerate-triangle epsilon: zero-area tris contribute nothing (and would divide-by-zero normalizing the cross
## product). Also the guard for a surface whose triangles are ALL degenerate — that isn't a floor, so it stays warped.
const MIN_TRIANGLE_AREA := 0.000001

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
		# Large horizontal surfaces read as sliding ground when snapped in clip space.
		if stabilize_floor_surfaces and _surface_is_floor_like(mi.mesh, s):
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
			# The affine depth window and the snap far-fade window are authored, not intensity-scaled,
			# so they're set once at creation; vertex_snap / affine_amount are set by _update_params
			# right after this walk, scaled to intensity.
			mat.set_shader_parameter("affine_near", affine_near)
			mat.set_shader_parameter("affine_far", affine_far)
			mat.set_shader_parameter("snap_far_fade_start", snap_far_fade_start)
			mat.set_shader_parameter("snap_far_fade_end", snap_far_fade_end)
			mat.set_shader_parameter("snap_near_fade_start", snap_near_fade_start)
			mat.set_shader_parameter("snap_near_fade_end", snap_near_fade_end)
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

## Is this surface mostly FLAT GROUND? Sums triangle area, splits it into horizontal vs not (FLOOR_NORMAL_Y), and
## calls the surface a floor when the horizontal share clears FLOOR_AREA_RATIO. When stabilize_floor_surfaces is
## OPTED IN (it ships OFF — see that export for the seam trade), _ps1ify skips those so the ground stays
## rock-steady: clip-space vertex snapping on a big floor plane reads as the whole world sliding underfoot
## (motion discomfort), while the same jitter on walls/props is just the intended PS1 wobble.
##
## LIMITATION: the normals here are MESH-LOCAL — the caller passes the raw Mesh, so the MeshInstance3D's own
## transform never enters the test. Level geometry is authored upright (identity/translation-only), so local +Y IS
## world up and this holds; a floor mesh ROTATED onto its side by its node transform would be misclassified (and
## just keeps warping — a cosmetic miss, never an error). Cheap on purpose: this runs once per surface at apply
## time, not per frame, but it does read back every vertex, so keep it out of any per-frame path.
func _surface_is_floor_like(mesh: Mesh, surface: int) -> bool:
	if mesh == null or surface < 0 or surface >= mesh.get_surface_count():
		return false
	# Non-triangle primitives (lines/points) have no meaningful facing to test — never a floor.
	if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
		return false
	var arrays := mesh.surface_get_arrays(surface)
	if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
		return false
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.size() < 3:
		return false
	# INDEXED vs flat: an indexed surface walks its index triples (bounds-checked — a malformed index array skips
	# the tri rather than crashing); an unindexed one takes the vertices three at a time.
	var indices: PackedInt32Array = PackedInt32Array()
	if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var floor_area := 0.0
	var total_area := 0.0
	if indices.size() >= 3:
		var tri_count := int(indices.size() / 3.0)
		for t in tri_count:
			var i := t * 3
			if indices[i] < 0 or indices[i] >= vertices.size():
				continue
			if indices[i + 1] < 0 or indices[i + 1] >= vertices.size():
				continue
			if indices[i + 2] < 0 or indices[i + 2] >= vertices.size():
				continue
			var areas := _floor_triangle_areas(vertices[indices[i]], vertices[indices[i + 1]], vertices[indices[i + 2]])
			total_area += areas.x
			floor_area += areas.y
	else:
		var tri_count := int(vertices.size() / 3.0)
		for t in tri_count:
			var i := t * 3
			var areas := _floor_triangle_areas(vertices[i], vertices[i + 1], vertices[i + 2])
			total_area += areas.x
			floor_area += areas.y
	if total_area <= MIN_TRIANGLE_AREA:
		return false
	return floor_area / total_area >= FLOOR_AREA_RATIO

## One triangle's contribution to the floor tally, packed as (total_area, horizontal_area) so the caller sums both
## in a single pass: x is always the area, y is that SAME area when the face is horizontal enough (|normal.y| >=
## FLOOR_NORMAL_Y) and 0 otherwise. Degenerate tris return ZERO for both. Pure + static (no node state), so it can
## be asserted directly off-tree; the shipped coverage drives it end-to-end through _ps1ify instead
## (tests/test_ps1_applier.gd: a floor-like surface is left un-warped when stabilize_floor_surfaces is opted in).
static func _floor_triangle_areas(a: Vector3, b: Vector3, c: Vector3) -> Vector2:
	var cross := (b - a).cross(c - a)
	var area := cross.length() * 0.5
	if area <= MIN_TRIANGLE_AREA:
		return Vector2.ZERO
	var normal := cross / (area * 2.0)
	return Vector2(area, area if absf(normal.y) >= FLOOR_NORMAL_Y else 0.0)
