class_name BrushZFightClean
extends Node
## @system Brush Z-Fight Clean
## @seam LevelRoot._ready spawns one per level at runtime (clean_brush_zfights, default on) unless the level authored its own; it runs in _ready under the level root and assigns a NEW ArrayMesh per touched FuncGodotMap MeshInstance3D BEFORE Ps1Warp.cover() overrides materials; the rebuild preserves every surface's material / name / vertex format, and only OPAQUE surfaces are touched, so SeeThroughBrushes (which harvests TRANSPARENT surfaces in its own _ready) sees the original arrays.
## @risk A rebuilt surface that dropped its material or flipped winding would render a whole texture group of the map black or invisible on load; test_brush_zfight_clean.gd pins material, winding, UV interpolation and the exact clipped area.
## @test res://tests/test_brush_zfight_clean.gd

## Kills the z-fight flicker between INTERPENETRATING brushes at run time, so the map does not need hand-fixing.
##
## A TrenchBroom brush sunk into another (a floor slab laid over a floor slab, a wall butted through a wall) puts
## two faces on the SAME plane facing the SAME way. Both rasterize at identical depth, the winner is whatever the
## rounding says that frame, and `ps1.gdshader`'s vertex snap re-randomizes it every frame the camera moves — so
## the slab strobes between two textures. (func_godot's own `_cull_interior_faces` only removes OPPOSITE-facing
## flush caps, which back-face culling already hides; it does nothing for this.) Measured on `alive.map`
## 2026-09-13: 407 same-facing triangle pairs over ~1,500 m² (up-facing floors ~180 m², walls ~55 m², the rest
## unseen undersides), the biggest a 122 m² floor-on-floor slab — all resolved in ~0.25 s at load.
##
## This node walks its PARENT's subtree, takes every opaque triangle of every `FuncGodotMap` mesh, buckets them by
## plane, and for each same-facing overlapping pair picks a deterministic LOSER and clips the overlapped region
## out of it with a convex split (no holes, no moved vertices, no cracks for `InkOutline` to draw). Each touched
## `MeshInstance3D` gets a NEW `ArrayMesh` (same surfaces, materials, names and vertex format; kept triangles keep
## their vertices, new corners are barycentric blends of the original three, so UVs / normals / tangents stay
## exact). The result is the picture a hand fix would give: one texture, stable, in every overlap.
##
## Who loses (the only judgement made for you — any STABLE choice beats flicker):
##   1. a surface whose material name matches `loser_surfaces` (default: sky) always loses;
##   2. otherwise the LARGER triangle loses — a detail placed on a slab shows over the slab;
##   3. ties (two identical faces) break on mesh/surface/triangle order, so the later face loses.
## If a specific overlap comes out showing the wrong texture, fix THAT brush in TrenchBroom; the rest stay automatic.
##
## Automatic: `LevelRoot._ready` spawns one under every level at runtime (`clean_brush_zfights`, default on), so no
## level authors it; drop one under the root by hand only to reach the knobs below (the root then spawns none).
## Runtime-only, like `SeeThroughBrushes`: not `@tool`, so the saved `.tscn`, the editor and the navmesh bake never
## see it and a func_godot rebuild needs no re-authoring. Collision is untouched (shapes are separate nodes), and
## transparent / cutout surfaces are skipped — they render in their own pass, `SeeThroughBrushes` harvests their
## vertices in its own `_ready`, and a cutout's fight is a material problem (AUTHORING_GUIDE, "cutout brush
## flicker"). Put the node under the LEVEL ROOT, never under `FuncGodotMap`: a rebuild deletes that subtree.

## Off = every overlap fights again, without deleting the node. Read once, in _ready.
@export var enabled: bool = true

## Material names (as TrenchBroom shows them, e.g. `sky1`, or a fragment like `sky`) whose faces ALWAYS lose an
## overlap. Matched case-insensitively against the material file name. Empty = size decides everything.
@export var loser_surfaces: PackedStringArray = ["sky"]

## Two faces closer than this (metres, along the normal) count as the same plane. func_godot re-derives vertices
## from plane maths, so exactly-flush brushes come out within float noise; 1 mm is far above that and far below any
## authored step (the map grid is 1/16 m).
@export_range(0.0001, 0.05, 0.0001) var plane_tolerance: float = 0.001

## Overlaps and leftover slivers smaller than this (square metres) are ignored / dropped. 1 cm² keeps the
## shared-edge "overlap" of two triangles of one quad from counting, and drops clip slivers no pixel could show.
@export_range(0.00001, 0.01, 0.00001) var min_area: float = 0.0001

## Print the per-level tally (meshes touched, pairs resolved, triangles clipped / removed, time) to the Output.
@export var verbose: bool = false

## The tally of the last `clean()` (see its doc); empty until _ready has run. Read by QA harnesses.
var last_report: Dictionary = {}

## Overlaps thinner than this (metres) are float noise along a shared edge, never a visible fight (see _is_sliver).
const SLIVER_WIDTH := 0.001

## One triangle of one surface, in WORLD space, with what the rebuild needs to put it back.
class _Tri:
	var id: int                     # global order = the final tie-break
	var mesh_slot: int              # index into the per-mesh records
	var surface: int
	var index_offset: int           # position of this tri's first index in the surface's index array
	var indices: PackedInt32Array   # the three ORIGINAL vertex indices (attribute source for interpolation)
	var world: PackedVector3Array   # three world-space corners, same order as `indices`
	var normal: Vector3
	var d: float                    # plane offset: normal · corner
	var area: float
	var forced_loser: bool
	var poly2d: PackedVector2Array  # corners in the plane bucket's 2D basis (counter-clockwise)
	var aabb_min: Vector2
	var aabb_max: Vector2
	var cutters: Array = []         # 2D polygons (the winners) to subtract from this tri; empty = untouched


func _ready() -> void:
	if not enabled:
		return
	var parent := get_parent()
	if parent == null:
		return
	if verbose:
		var census := overlap_report(parent, 5)
		for p in census.get("top", []):
			print("BrushZFightClean: %.2f m² overlap at %s (normal %s): %s over %s" % [
				p.area, p.at, p.normal, p.materials[1], p.materials[0]])
	last_report = clean(parent)
	if verbose:
		print("BrushZFightClean: %d mesh(es), %d overlap pair(s) over %.1f m², %d tri(s) clipped, %d removed, %d tris -> %d, %d ms" % [
			last_report.meshes_touched, last_report.pairs, last_report.area_m2, last_report.tris_clipped,
			last_report.tris_removed, last_report.tris_in, last_report.tris_out, last_report.ms])


## Resolve every same-facing coplanar overlap under `root` (any node — the level root in practice). Returns
## { meshes, meshes_touched, tris_in, tris_out, pairs, area_m2, tris_clipped, tris_removed, ms }. The nodes must
## be IN a tree (it reads `global_transform`); nothing else about the scene is touched.
func clean(root: Node) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var meshes: Array[MeshInstance3D] = []
	_collect_brush_meshes(root, meshes)
	var tris: Array[_Tri] = []
	var mesh_arrays: Array = []   # per mesh slot: Array of per-surface `surface_get_arrays` (null = skipped surface)
	for slot in meshes.size():
		mesh_arrays.append(_harvest(meshes[slot], slot, tris))
	var pairs := _pair_overlaps(tris)
	var clipped := 0
	var removed := 0
	var tris_out := tris.size()
	var pieces_by_tri := {}   # tri id -> Array of convex PackedVector2Array pieces that survive
	var clipped_by_mesh := {} # mesh slot -> { surface -> { index_offset -> _Tri } }
	for t in tris:
		if t.cutters.is_empty():
			continue
		var pieces: Array = [t.poly2d]
		for cutter in t.cutters:
			var next: Array = []
			for piece in pieces:
				next.append_array(_split_convex(piece, cutter, min_area))
			pieces = next
		pieces_by_tri[t.id] = pieces
		if not clipped_by_mesh.has(t.mesh_slot):
			clipped_by_mesh[t.mesh_slot] = {}
		if not clipped_by_mesh[t.mesh_slot].has(t.surface):
			clipped_by_mesh[t.mesh_slot][t.surface] = {}
		clipped_by_mesh[t.mesh_slot][t.surface][t.index_offset] = t
		if pieces.is_empty():
			removed += 1
		else:
			clipped += 1
		var new_tris := 0
		for piece in pieces:
			new_tris += piece.size() - 2
		tris_out += new_tris - 1
	for slot in clipped_by_mesh.keys():
		_rebuild_mesh(meshes[slot], mesh_arrays[slot], clipped_by_mesh[slot], pieces_by_tri)
	var area := 0.0
	for p in pairs:
		area += p.area
	return {
		"meshes": meshes.size(), "meshes_touched": clipped_by_mesh.size(),
		"tris_in": tris.size(), "tris_out": tris_out,
		"pairs": pairs.size(), "area_m2": area,
		"tris_clipped": clipped, "tris_removed": removed,
		"ms": Time.get_ticks_msec() - t0,
	}


## Census only — how many same-facing coplanar overlaps (and how much area, m²) exist under `root` RIGHT NOW,
## changing nothing. `clean()` then `overlap_report()` on the same level reads zero pairs. `top_n` > 0 also
## returns `top`: the biggest overlaps as { area, normal, at (world), materials } — the list to walk in
## TrenchBroom if you would rather separate the brushes than let the loser rule pick.
func overlap_report(root: Node, top_n: int = 0) -> Dictionary:
	var meshes: Array[MeshInstance3D] = []
	_collect_brush_meshes(root, meshes)
	var tris: Array[_Tri] = []
	for slot in meshes.size():
		_harvest(meshes[slot], slot, tris)
	var pairs := _pair_overlaps(tris)
	var area := 0.0
	for p in pairs:
		area += p.area
	var out := {"meshes": meshes.size(), "tris": tris.size(), "pairs": pairs.size(), "area_m2": area}
	if top_n > 0:
		pairs.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.area > y.area)
		var top: Array = []
		for i in mini(top_n, pairs.size()):
			var p: Dictionary = pairs[i]
			var a: _Tri = p.a
			var b: _Tri = p.b
			top.append({
				"area": p.area, "normal": a.normal, "at": p.at,
				"materials": [_material_name(meshes[a.mesh_slot], a.surface), _material_name(meshes[b.mesh_slot], b.surface)],
			})
		out["top"] = top
	return out


static func _material_name(mi: MeshInstance3D, surface: int) -> String:
	var mat := mi.get_active_material(surface)
	if mat == null:
		return "<none>"
	var name := mat.resource_path.get_file().get_basename()
	return name if not name.is_empty() else mat.resource_name


## Every MeshInstance3D with an ArrayMesh beneath a `FuncGodotMap` under `node`. Scoped to func_godot output on
## purpose: hero-prop GLBs are authored meshes whose coplanar quads (decals, trim) are deliberate.
func _collect_brush_meshes(node: Node, out: Array[MeshInstance3D], under_map: bool = false) -> void:
	var is_map := under_map
	if not is_map:
		var script: Script = node.get_script()
		is_map = script != null and script.get_global_name() == &"FuncGodotMap"
	if is_map and node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		_collect_brush_meshes(c, out, is_map)


## True for a material that renders in the opaque pass. Transparent / cutout surfaces are skipped (see header);
## a ShaderMaterial has no readable transparency mode and is taken as opaque, a null surface as nothing to fight.
static func _is_opaque(mat: Material) -> bool:
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
	return mat != null


func _is_forced_loser(mat: Material) -> bool:
	if mat == null or loser_surfaces.is_empty():
		return false
	var name := mat.resource_path.get_file().get_basename().to_lower()
	if name.is_empty():
		name = mat.resource_name.to_lower()
	for pattern in loser_surfaces:
		var p := String(pattern).get_file().get_basename().to_lower()
		if not p.is_empty() and name.contains(p):
			return true
	return false


## Append one _Tri per opaque triangle of `mi` to `tris`; return the per-surface arrays (null = surface skipped).
func _harvest(mi: MeshInstance3D, slot: int, tris: Array[_Tri]) -> Array:
	var mesh := mi.mesh as ArrayMesh
	var xf := mi.global_transform
	var per_surface: Array = []
	for s in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			per_surface.append(null)
			continue
		var mat := mi.get_active_material(s)
		if not _is_opaque(mat):
			per_surface.append(null)
			continue
		var arrays := mesh.surface_get_arrays(s)
		# Only the attribute set the rebuild knows how to blend: a skinned or custom-channel surface is not a brush.
		if arrays[Mesh.ARRAY_BONES] != null or arrays[Mesh.ARRAY_WEIGHTS] != null \
				or arrays[Mesh.ARRAY_CUSTOM0] != null or arrays[Mesh.ARRAY_CUSTOM1] != null \
				or arrays[Mesh.ARRAY_CUSTOM2] != null or arrays[Mesh.ARRAY_CUSTOM3] != null:
			per_surface.append(null)
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if index.is_empty():
			# Unindexed: synthesize the identity index so the rebuild has one code path.
			index.resize(verts.size())
			for i in verts.size():
				index[i] = i
			arrays[Mesh.ARRAY_INDEX] = index
		per_surface.append(arrays)
		var forced := _is_forced_loser(mat)
		var tri_count := index.size() / 3
		for k in tri_count:
			var t := _Tri.new()
			t.id = tris.size()
			t.mesh_slot = slot
			t.surface = s
			t.index_offset = k * 3
			t.indices = PackedInt32Array([index[k * 3], index[k * 3 + 1], index[k * 3 + 2]])
			var a := xf * verts[t.indices[0]]
			var b := xf * verts[t.indices[1]]
			var c := xf * verts[t.indices[2]]
			# Godot front faces wind CLOCKWISE seen from outside, so the OUTWARD normal is (c-a)×(b-a).
			var n := (c - a).cross(b - a)
			var twice_area := n.length()
			if twice_area <= 1e-12:
				continue   # degenerate sliver: nothing to fight with, nothing to draw
			t.normal = n / twice_area
			t.area = twice_area * 0.5
			t.d = t.normal.dot(a)
			t.world = PackedVector3Array([a, b, c])
			t.forced_loser = forced
			tris.append(t)
	return per_surface


## Find every same-facing coplanar overlapping pair, record the winner's 2D polygon on the loser, and return one
## { area (m²), a, b, at (world centre of the overlap) } per pair. Bucketed by quantized normal so only parallel
## faces are ever compared.
func _pair_overlaps(tris: Array[_Tri]) -> Array[Dictionary]:
	var buckets := {}   # Vector3i -> Array[_Tri]
	for t in tris:
		var key := Vector3i((t.normal * 1000.0).round())
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(t)
	var pairs: Array[Dictionary] = []
	for key in buckets.keys():
		var bucket: Array = buckets[key]
		if bucket.size() < 2:
			continue
		# One 2D basis per bucket, LEFT-handed about the outward normal (r × f = -n): seen from outside a front
		# face winds clockwise (Godot's convention), which in this mirrored basis is counter-clockwise — so every
		# tri here is ccw in (r, f) with no reversal, the convex split can assume ccw cutters, and a ccw fan over
		# a piece comes back out with the original front-facing winding. All the bucket's normals agree to 1e-3.
		var n: Vector3 = (bucket[0] as _Tri).normal
		var up := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
		var r := n.cross(up).normalized()
		var f := r.cross(n).normalized()
		for t in bucket:
			t.poly2d = PackedVector2Array()
			t.aabb_min = Vector2(INF, INF)
			t.aabb_max = Vector2(-INF, -INF)
			for p in t.world:
				var q := Vector2(r.dot(p), f.dot(p))
				t.poly2d.append(q)
				t.aabb_min = t.aabb_min.min(q)
				t.aabb_max = t.aabb_max.max(q)
			if _signed_area(t.poly2d) < 0.0:
				# Float noise on a near-degenerate tri; keep corners and attribute sources in lockstep.
				t.poly2d.reverse()
				t.world.reverse()
				t.indices.reverse()
		bucket.sort_custom(func(a: _Tri, b: _Tri) -> bool: return a.d < b.d)
		for i in bucket.size():
			var a: _Tri = bucket[i]
			for j in range(i + 1, bucket.size()):
				var b: _Tri = bucket[j]
				if b.d - a.d > plane_tolerance:
					break   # sorted by d: nothing further can be coplanar with a
				if a.normal.dot(b.normal) < 0.99999:
					continue
				if a.aabb_min.x > b.aabb_max.x or b.aabb_min.x > a.aabb_max.x \
						or a.aabb_min.y > b.aabb_max.y or b.aabb_min.y > a.aabb_max.y:
					continue
				var inter := _clip_convex(a.poly2d, b.poly2d)
				if inter.size() < 3:
					continue
				var area := absf(_signed_area(inter))
				if area < min_area or _is_sliver(inter, area):
					continue
				var a_loses := _loses_to(a, b)
				var loser := a if a_loses else b
				var winner := b if a_loses else a
				loser.cutters.append(winner.poly2d)
				var c := Vector2.ZERO
				for q in inter:
					c += q
				c /= inter.size()
				pairs.append({"area": area, "a": a, "b": b, "at": r * c.x + f * c.y + n * a.d})
	return pairs


## A hair-thin overlap is float noise along a shared edge (two pieces cut on the same line, ~1e-5 m apart over
## a 20 m span), not a fight: no pixel can show it, and clipping it would only grow the mesh every pass. The
## inscribed width of a convex polygon is at most 2·area/perimeter, so this bounds the width from above.
static func _is_sliver(poly: PackedVector2Array, area: float) -> bool:
	var perimeter := 0.0
	for i in poly.size():
		perimeter += poly[i].distance_to(poly[(i + 1) % poly.size()])
	return perimeter > 0.0 and 2.0 * area / perimeter < SLIVER_WIDTH


## True when `a` is the loser of the pair (header rules). A total order, so exactly one side loses.
static func _loses_to(a: _Tri, b: _Tri) -> bool:
	if a.forced_loser != b.forced_loser:
		return a.forced_loser
	if not is_equal_approx(a.area, b.area):
		return a.area > b.area
	return a.id > b.id


static func _signed_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		s += p.x * q.y - q.x * p.y
	return s * 0.5


## Sutherland–Hodgman: `subject` clipped to the inside of convex counter-clockwise `clipper`.
static func _clip_convex(subject: PackedVector2Array, clipper: PackedVector2Array) -> PackedVector2Array:
	var out := subject
	for i in clipper.size():
		if out.size() < 3:
			return PackedVector2Array()
		out = _clip_half_plane(out, clipper[i], clipper[(i + 1) % clipper.size()], true)
	return out


## The part of convex `poly` on one side of the directed edge a->b (`inside` = its left, for a ccw clipper).
static func _clip_half_plane(poly: PackedVector2Array, a: Vector2, b: Vector2, inside: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var e := b - a
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var sp := e.cross(p - a)
		var sq := e.cross(q - a)
		if not inside:
			sp = -sp
			sq = -sq
		if sp >= 0.0:
			out.append(p)
		if (sp < 0.0 and sq > 0.0) or (sp > 0.0 and sq < 0.0):
			out.append(p + (q - p) * (sp / (sp - sq)))
	return out


## `piece` minus convex ccw `cutter`, as convex pieces: peel off the part outside each cutter edge in turn and
## keep clipping the remainder inward; what is left at the end lies inside the cutter and is the overlap being
## removed. Never produces a hole, which is what lets every piece fan-triangulate directly.
static func _split_convex(piece: PackedVector2Array, cutter: PackedVector2Array, min_piece_area: float) -> Array:
	var out: Array = []
	var rest := piece
	for i in cutter.size():
		if rest.size() < 3:
			break
		var a := cutter[i]
		var b := cutter[(i + 1) % cutter.size()]
		var outside := _clip_half_plane(rest, a, b, false)
		if outside.size() >= 3 and absf(_signed_area(outside)) >= min_piece_area:
			out.append(outside)
		rest = _clip_half_plane(rest, a, b, true)
	return out


## Replace `mi.mesh` with a copy whose clipped triangles are re-emitted as their surviving pieces. Untouched
## surfaces are copied verbatim; materials and surface names carry over.
func _rebuild_mesh(mi: MeshInstance3D, per_surface: Array, clipped_by_surface: Dictionary, pieces_by_tri: Dictionary) -> void:
	var old := mi.mesh as ArrayMesh
	var new_mesh := ArrayMesh.new()
	for s in old.get_surface_count():
		var prim := old.surface_get_primitive_type(s)
		if clipped_by_surface.has(s) and per_surface[s] != null:
			var arrays := _rebuild_arrays(per_surface[s], clipped_by_surface[s], pieces_by_tri)
			if (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
				continue   # every face of this surface was fully covered: an empty surface is an engine error, so drop it
			new_mesh.add_surface_from_arrays(prim, arrays)
		else:
			new_mesh.add_surface_from_arrays(prim, old.surface_get_arrays(s))
		var ns := new_mesh.get_surface_count() - 1
		new_mesh.surface_set_material(ns, old.surface_get_material(s))
		new_mesh.surface_set_name(ns, old.surface_get_name(s))
	mi.mesh = new_mesh


## The surface's new arrays: the original vertex attributes plus appended blended vertices, and an index array
## where each clipped triangle is replaced by the fans of its pieces (or by nothing, if it was fully covered).
static func _rebuild_arrays(arrays: Array, clipped: Dictionary, pieces_by_tri: Dictionary) -> Array:
	var out := arrays.duplicate()
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var verts: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var has_normal: bool = arrays[Mesh.ARRAY_NORMAL] != null
	var has_tangent: bool = arrays[Mesh.ARRAY_TANGENT] != null
	var has_color: bool = arrays[Mesh.ARRAY_COLOR] != null
	var has_uv: bool = arrays[Mesh.ARRAY_TEX_UV] != null
	var has_uv2: bool = arrays[Mesh.ARRAY_TEX_UV2] != null
	var normals: PackedVector3Array = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate() if has_normal else PackedVector3Array()
	var tangents: PackedFloat32Array = (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).duplicate() if has_tangent else PackedFloat32Array()
	var colors: PackedColorArray = (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate() if has_color else PackedColorArray()
	var uvs: PackedVector2Array = (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).duplicate() if has_uv else PackedVector2Array()
	var uv2s: PackedVector2Array = (arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).duplicate() if has_uv2 else PackedVector2Array()
	var new_index := PackedInt32Array()
	var k := 0
	while k < index.size():
		if not clipped.has(k):
			new_index.append(index[k])
			new_index.append(index[k + 1])
			new_index.append(index[k + 2])
			k += 3
			continue
		var t: _Tri = clipped[k]
		var pieces: Array = pieces_by_tri[t.id]
		var i0 := t.indices[0]
		var i1 := t.indices[1]
		var i2 := t.indices[2]
		for piece in pieces:
			var piece_ids := PackedInt32Array()
			for q in piece:
				var w := _barycentric(q, t.poly2d)
				piece_ids.append(verts.size())
				verts.append(verts[i0] * w.x + verts[i1] * w.y + verts[i2] * w.z)
				if has_normal:
					normals.append((normals[i0] * w.x + normals[i1] * w.y + normals[i2] * w.z).normalized())
				if has_tangent:
					# 4 floats per vertex: blend xyz, keep the first corner's handedness (flat across a brush face).
					var tv := Vector3.ZERO
					for c in 3:
						var ic: int = t.indices[c]
						tv += Vector3(tangents[ic * 4], tangents[ic * 4 + 1], tangents[ic * 4 + 2]) * w[c]
					tv = tv.normalized()
					tangents.append(tv.x)
					tangents.append(tv.y)
					tangents.append(tv.z)
					tangents.append(tangents[i0 * 4 + 3])
				if has_color:
					colors.append(colors[i0] * w.x + colors[i1] * w.y + colors[i2] * w.z)
				if has_uv:
					uvs.append(uvs[i0] * w.x + uvs[i1] * w.y + uvs[i2] * w.z)
				if has_uv2:
					uv2s.append(uv2s[i0] * w.x + uv2s[i1] * w.y + uv2s[i2] * w.z)
			for i in range(1, piece_ids.size() - 1):
				new_index.append(piece_ids[0])
				new_index.append(piece_ids[i])
				new_index.append(piece_ids[i + 1])
		k += 3
	out[Mesh.ARRAY_VERTEX] = verts
	if has_normal:
		out[Mesh.ARRAY_NORMAL] = normals
	if has_tangent:
		out[Mesh.ARRAY_TANGENT] = tangents
	if has_color:
		out[Mesh.ARRAY_COLOR] = colors
	if has_uv:
		out[Mesh.ARRAY_TEX_UV] = uvs
	if has_uv2:
		out[Mesh.ARRAY_TEX_UV2] = uv2s
	out[Mesh.ARRAY_INDEX] = new_index
	return out


## Barycentric weights of `p` w.r.t. the 2D triangle `tri` (the basis the pieces were cut in). A piece's corners
## always lie on or inside the original triangle, so the weights are non-negative up to float noise.
static func _barycentric(p: Vector2, tri: PackedVector2Array) -> Vector3:
	var a := tri[0]
	var v0 := tri[1] - a
	var v1 := tri[2] - a
	var v2 := p - a
	var den := v0.cross(v1)
	if absf(den) < 1e-12:
		return Vector3(1, 0, 0)
	var w1 := v2.cross(v1) / den
	var w2 := v0.cross(v2) / den
	return Vector3(1.0 - w1 - w2, w1, w2)
