class_name SeeThroughBrushes
extends Node

## The func_godot half of the see-through-geometry feature: it finds the brushes in a TrenchBroom-built level that
## are DRAWN with a transparent texture — the chain-link fences, the foliage cards — and HARVESTS them into their
## own `StaticBody3D` so sight and gunfire pass through them, while they stay solid to walk into.
##
## WHY IT HARVESTS RATHER THAN TAGS: func_godot compiles an ENTIRE map into one `StaticBody3D`
## (`entity_0_worldspawn`) carrying one `CollisionShape3D` per brush — 558 of them on `alive.map`. Putting THAT
## body in `Groups.SEE_THROUGH` would make the whole level see-through, and a per-shape mark is not enough either:
## a flying round collides with a BODY (`Projectile` excepts whole bodies; a `collision_mask` is per-body), so
## nothing can let a bullet through one brush of a body and stop it on the next. Splitting the fence brushes into
## a sibling body is what makes "shoot through the fence" expressible at all. The split is RUNTIME-ONLY — the
## saved scene, the editor and the navmesh bake never see it.
##
## The new body copies the source body's `collision_layer` / `collision_mask` verbatim, so it is the SAME solid it
## always was: you still cannot walk through it, props still bounce off it, the minimap floorplan still cuts it,
## and a re-bake still carves navmesh around it. Only the systems that consult `Groups.SEE_THROUGH` behave
## differently — `SightRay` (perception), `Projectile` (fired rounds) and `DamageTrace` (hitscan pellets).
##
## HOW A BRUSH IS RECOGNISED — by its MATERIAL, not by a hand-kept list of brush numbers. func_godot builds one
## named mesh surface per texture ("textures/fence1_a") sharing its material with `tb_materials/`. Any surface
## whose material is transparent (alpha-scissor / alpha / alpha-hash) is see-through, and a brush counts when
## EVERY corner of its convex collision shape is also a vertex of those surfaces. That "all corners" rule is what
## keeps a concrete wall standing next to a fence opaque even though the two share an edge. Nothing here depends
## on brush ORDER or node NAMES, so a func_godot rebuild (which regenerates the whole body) needs no re-authoring:
## flip a texture's material to transparent in `tb_materials/` and its brushes become see-through on next load.
##
## WHERE TO PUT IT: under the LEVEL ROOT (or any ancestor of the map), NOT under `FuncGodotMap` or the generated
## body — rebuilding the map deletes every node func_godot generated, and this component with it. It walks its
## parent's whole subtree, so one component covers every map body in the level.
##
## COST: one pass at level load (a few ms on `alive.map`), then nothing per frame.
##
## Not @tool: a plain Node never runs _ready in the editor, and the split only needs to exist at runtime — which
## is also why it can never be saved into the scene by accident.

## Off = every brush blocks sight and gunfire again, without deleting the node. Read once, in _ready.
@export var enabled: bool = true

## Extra surfaces to treat as see-through even though their material is NOT flagged transparent — for a texture
## that reads as a grille but was authored opaque. Match the func_godot surface name, with or without its folder:
## "fence2" and "textures/fence2" both work.
@export var extra_surfaces: PackedStringArray = []

## Surfaces to keep OPAQUE even though their material IS transparent — the knob for "a tree card should still be
## cover". Takes precedence over both the material test and `extra_surfaces`. Same name matching as above.
@export var opaque_surfaces: PackedStringArray = []

## How close a brush corner must sit to a see-through surface vertex to count as the same point, in metres.
## Not zero because func_godot welds and re-derives face vertices, so a corner can land a thousandth off the
## collision hull it came from. Well under any real brush, so it cannot bridge two different brushes.
@export_range(0.0, 0.5, 0.001) var vertex_tolerance: float = 0.05

## Print what was marked (per body: how many brushes of how many, and from which surfaces). Leave off in normal
## play; turn on when a fence still blinds an NPC and you need to know whether it was recognised.
@export var verbose: bool = false


func _ready() -> void:
	if not enabled:
		return
	var root := get_parent()
	if root == null:
		push_warning("SeeThroughBrushes has no parent to scan; put it under the level root, above the FuncGodotMap.")
		return
	var split_bodies := 0
	# Snapshot the body list BEFORE splitting: _harvest_body adds a sibling StaticBody3D, and walking the live
	# tree while doing that would hand us our own output to re-scan (it has no mesh child, so it would be a
	# harmless no-op — but relying on that is a trap waiting for the day the skip rule changes).
	for body in _bodies(root):
		if _harvest_body(body):
			split_bodies += 1
	if verbose:
		print("[SeeThroughBrushes] split see-through brushes off %d body(s) under %s" % [split_bodies, root.name])


## Move one body's see-through brushes into their own `Groups.SEE_THROUGH` body. Returns true when at least one
## brush qualified. A body with no mesh child (a trigger volume, a plain collider prop) is skipped: without the
## visual surfaces there is no material to read.
func _harvest_body(body: CollisionObject3D) -> bool:
	var mesh_instance := _mesh_child(body)
	if mesh_instance == null or mesh_instance.mesh == null:
		return false
	var surface_names := PackedStringArray()
	var points := _see_through_points(body, mesh_instance, surface_names)
	if points.is_empty():
		return false
	var grid := build_grid(points, vertex_tolerance)
	var see_through: Array[CollisionShape3D] = []
	var total := 0
	for owner_id in body.get_shape_owners():
		var collision_shape := body.shape_owner_get_owner(owner_id) as CollisionShape3D
		if collision_shape == null:
			continue
		total += 1
		if _shape_is_see_through(body, collision_shape, grid):
			see_through.append(collision_shape)
	if see_through.is_empty():
		return false
	if see_through.size() == total:
		# Every shape on this body is see-through (a fence authored as its own func_godot entity): nothing to
		# split off, the body IS the fence.
		body.add_to_group(Groups.SEE_THROUGH)
	else:
		_split_off(body, see_through)
	if verbose:
		print("[SeeThroughBrushes] %s: %d/%d brushes see-through via %s" % [body.name, see_through.size(), total, ", ".join(surface_names)])
	return true


## Reparent `shapes` out of `body` into a fresh sibling `StaticBody3D` in `Groups.SEE_THROUGH`. The new body is a
## SIBLING (same parent, same local transform) rather than a child, so the shapes' own local transforms carry over
## untouched and nothing has to be re-derived in global space. It copies the source body's physics identity
## verbatim — layer, mask, physics material — because the fence must stay exactly as solid as it was to everything
## that does not consult the group.
func _split_off(body: CollisionObject3D, shapes: Array[CollisionShape3D]) -> void:
	var parent := body.get_parent()
	if parent == null:
		return
	var fence := StaticBody3D.new()
	# validate_node_name: an auto-named body ("@StaticBody3D@42") carries characters a node name cannot hold, and
	# add_child would silently rewrite the name we just composed. func_godot's own names are already clean.
	fence.name = ("%s_see_through" % body.name).validate_node_name()
	fence.collision_layer = body.collision_layer
	fence.collision_mask = body.collision_mask
	if body is StaticBody3D:
		fence.physics_material_override = (body as StaticBody3D).physics_material_override
	fence.add_to_group(Groups.SEE_THROUGH)
	parent.add_child(fence)
	fence.transform = body.transform
	for collision_shape in shapes:
		body.remove_child(collision_shape)
		fence.add_child(collision_shape)


## Every corner of every see-through surface on `mesh_instance`, expressed in `body` local space (the same space
## the collision shapes are compared in). Appends the names of the surfaces it accepted to `out_names` for the
## verbose report.
func _see_through_points(body: CollisionObject3D, mesh_instance: MeshInstance3D, out_names: PackedStringArray) -> PackedVector3Array:
	var mesh := mesh_instance.mesh
	var array_mesh := mesh as ArrayMesh
	var to_body := body.global_transform.affine_inverse() * mesh_instance.global_transform
	var points := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var surface_name := array_mesh.surface_get_name(surface) if array_mesh != null else ""
		if not _is_see_through_surface(mesh_instance, surface, surface_name):
			continue
		out_names.append(surface_name if surface_name != "" else "surface %d" % surface)
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if not (verts is PackedVector3Array):
			continue
		for v: Vector3 in verts as PackedVector3Array:
			points.append(to_body * v)
	return points


## Is this surface one sight passes through? The explicit lists win over the material so a designer can always
## overrule the automatic answer; otherwise any BaseMaterial3D with transparency switched on counts (that is
## exactly what "drawn as a transparent surface" means, and it is the flag the fence/foliage materials already
## carry). A ShaderMaterial has no readable transparency mode, so it only qualifies via `extra_surfaces`.
func _is_see_through_surface(mesh_instance: MeshInstance3D, surface: int, surface_name: String) -> bool:
	if _name_listed(surface_name, opaque_surfaces):
		return false
	if _name_listed(surface_name, extra_surfaces):
		return true
	var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
	return material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED


## Does `surface_name` appear in `list`? Matches the whole name ("textures/fence2") or just its last path
## component ("fence2"), so a designer can type what they see in TrenchBroom. Case-insensitive.
static func _name_listed(surface_name: String, list: PackedStringArray) -> bool:
	if surface_name == "" or list.is_empty():
		return false
	var lowered := surface_name.to_lower()
	var leaf := lowered.get_file()
	for entry: String in list:
		var wanted := entry.strip_edges().to_lower()
		if wanted != "" and (wanted == lowered or wanted == leaf):
			return true
	return false


## True when EVERY corner of this brush's shape is also a see-through surface vertex. Shapes that are not convex
## hulls (a concave trimesh, a primitive box) have no corner list to compare and stay opaque.
func _shape_is_see_through(body: CollisionObject3D, collision_shape: CollisionShape3D, grid: Dictionary) -> bool:
	var hull := collision_shape.shape as ConvexPolygonShape3D
	if hull == null:
		return false
	var to_body := body.global_transform.affine_inverse() * collision_shape.global_transform
	var corners := PackedVector3Array()
	for corner: Vector3 in hull.points:
		corners.append(to_body * corner)
	return hull_is_see_through(corners, grid, vertex_tolerance)


## The geometry rule itself, kept pure (points in, bool out) so it is unit-testable with no scene, no physics and
## no transforms: a hull is see-through when every one of its corners lands on a see-through surface vertex.
## Fewer than 4 corners is not a solid — and a stray point or two could sit on almost any surface — so it fails.
static func hull_is_see_through(corners: PackedVector3Array, grid: Dictionary, cell_size: float) -> bool:
	if corners.size() < 4:
		return false
	for corner: Vector3 in corners:
		if not grid.has(cell_of(corner, cell_size)):
			return false
	return true


## A lookup of every see-through vertex, pre-widened by the tolerance: each point is stored under its own cell AND
## its 26 neighbours, so testing a brush corner is ONE dictionary hit instead of a 27-cell scan. Cheap because the
## see-through surfaces are a tiny slice of the map (a few hundred vertices on `alive.map`).
static func build_grid(points: PackedVector3Array, cell_size: float) -> Dictionary:
	var grid := {}
	for p: Vector3 in points:
		var base := cell_of(p, cell_size)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					grid[base + Vector3i(dx, dy, dz)] = true
	return grid


## The grid cell a point falls in. Cell size IS the tolerance, so the pre-widened neighbourhood above accepts
## anything within roughly one tolerance of a stored vertex.
static func cell_of(p: Vector3, cell_size: float) -> Vector3i:
	var size := maxf(cell_size, 0.0001)
	return Vector3i(roundi(p.x / size), roundi(p.y / size), roundi(p.z / size))


## The MeshInstance3D that draws `body`'s geometry — func_godot parents it directly under the entity body. Only
## direct children are considered: a mesh nested deeper belongs to a prop standing ON the map, not to the map.
static func _mesh_child(body: CollisionObject3D) -> MeshInstance3D:
	for child in body.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null


## Every CollisionObject3D at or under `root`.
static func _bodies(root: Node) -> Array[CollisionObject3D]:
	var found: Array[CollisionObject3D] = []
	if root is CollisionObject3D:
		found.append(root as CollisionObject3D)
	for child in root.get_children():
		found.append_array(_bodies(child))
	return found
