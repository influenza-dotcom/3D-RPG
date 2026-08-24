class_name FloorplanSource
extends RefCounted

## @system Minimap
## @seam gather(root, hide_group) is the ONE place level geometry becomes minimap geometry: it walks a level subtree once and converts every STATIC collider into a world-space convex hull or triangle soup, which slice() then cuts at any height. Split out of FloorplanSection precisely so that file can stay pure and provable.
## @risk The static gate is `is StaticBody3D and not is AnimatableBody3D` — a TYPE, never a physics layer. Not because the layers overlap: characters are collision_layer 2 (Player.tscn, enemy.tscn) and level brush geometry is collision_layer 1 / collision_mask 0 (func_godot worldspawn / func_geo / func_detail), so a mask COULD tell a body from a wall. Layer 1 is the ENGINE DEFAULT, though, so it is also where every static thing that never touches the field lands — world brushes, props and door bodies alike (door.tscn's DoorPivot/DoorBody is a bare StaticBody3D). A mask cannot make the one distinction this picture needs, wall vs. movable leaf, and would silently drop any prefab a future author puts on another layer.
## @risk AnimatableBody3D INHERITS StaticBody3D (verified against the engine), so the naive `is StaticBody3D` gate silently includes door leaves and bakes them shut forever. The exclusion is load-bearing, not tidiness.
## @risk CSGShape3D is NOT a CollisionObject3D — in Godot 4.7 that `is` check will not even parse — so a CollisionShape3D walk finds NOTHING on a CSG blockout level. Those need the separate bake_collision_shape() branch, and CLAUDE.md names CSG as the blockout pipeline for new levels.
## @test res://tests/test_floorplan_source.gd
##
## The impure half of the HUD minimap's wall layer. It answers one question — "what solid matter does this
## level contain?" — and answers it ONCE per level, because the answer only changes when the level does.
## FloorplanSection then cuts that answer at whatever height the player's floor needs.
##
## A solid is one of two shapes, kept in WORLD space so a re-slice at a new height costs no transforms:
##   {"hull":  PackedVector3Array}  a convex point cloud (box, brush, cylinder, capsule, sphere)
##   {"faces": PackedVector3Array}  a triangle soup (trimesh collider, CSG bake)
## Convex hulls cut to closed RINGS (rooms read as outlines); soups cut to loose SEGMENTS. slice() then hands
## the rings to FloorplanSection.silhouette, which differences them against each other so overlapping and
## abutting solids print ONE outline rather than a wireframe of the brushwork.

## Every solid found by the last gather(), in world space.
var solids: Array[Dictionary] = []
## Instance id of the root the last gather() walked — the caller's staleness check.
var source_id: int = 0

## How many sides stand in for a round collider. 12 is invisible from a mismatch at this widget's ~2.7 px/m.
const ROUND_SIDES := 12


## Walk `root` once and convert every STATIC collider beneath it into a world-space solid. Two node kinds
## are handled, and the second is not optional:
##   1. CollisionShape3D whose CollisionObject3D ancestor is a StaticBody3D (but NOT an AnimatableBody3D).
##   2. CSGShape3D root shapes with use_collision — because a CSG node registers a body RID directly and is
##      not a CollisionObject3D at all, so branch 1 finds literally nothing on a CSG blockout level.
## Anything under a `hide_group` subtree is skipped (the MinimapHide drop-in), as are disabled shapes.
func gather(root: Node, hide_group: StringName) -> void:
	solids.clear()
	source_id = root.get_instance_id() if root != null else 0
	if root == null:
		return
	_walk(root, hide_group)


func _walk(n: Node, hide_group: StringName) -> void:
	# A hidden subtree is skipped WHOLE — cheaper than testing every descendant, and it matches the
	# drop-in's promise ("this prop and everything under it").
	if hide_group != &"" and n.is_in_group(hide_group):
		return
	var cs := n as CollisionShape3D
	if cs != null:
		_add_collision_shape(cs)
	else:
		_add_csg(n)
	for c in n.get_children():
		_walk(c, hide_group)


func _add_collision_shape(cs: CollisionShape3D) -> void:
	if cs.disabled or cs.shape == null:
		return
	var body := cs.get_parent() as CollisionObject3D
	if body == null:
		return
	# THE STATIC GATE. Type, never a physics layer — though NOT because the layers overlap: characters are
	# collision_layer 2 (Player.tscn, enemy.tscn) and brush geometry is collision_layer 1 / mask 0, so a mask
	# could in fact tell a body from a wall. Layer 1 is the ENGINE DEFAULT, so it is equally where props and
	# door bodies land (door.tscn's DoorPivot/DoorBody is a bare StaticBody3D); a mask cannot make the one
	# distinction that matters here, wall vs. movable leaf, and would silently drop any prefab authored onto
	# another layer. AnimatableBody3D is then excluded explicitly because it INHERITS StaticBody3D: a door
	# leaf baked in whatever pose it happened to hold would draw a closed door forever. Floorplans draw
	# openings, not leaves.
	if not (body is StaticBody3D) or body is AnimatableBody3D:
		return
	var solid := shape_solid(cs.shape, cs.global_transform)
	if not solid.is_empty():
		solids.append(solid)


## CSG blockout levels (CLAUDE.md's pipeline for new levels). Guarded by has_method so an engine API drift
## degrades to "no walls on that level" rather than an error — and the navmesh fill still draws.
func _add_csg(n: Node) -> void:
	if not (n is CSGShape3D):
		return
	var csg := n as CSGShape3D
	if not csg.use_collision or not csg.is_visible_in_tree():
		return
	if not csg.has_method(&"is_root_shape") or not csg.has_method(&"bake_collision_shape"):
		return
	if not csg.is_root_shape():
		return  # only the root of a CSG tree owns the combined result
	var baked = csg.call(&"bake_collision_shape")
	var concave := baked as ConcavePolygonShape3D
	if concave == null:
		return
	var faces := concave.get_faces()
	if faces.size() >= 3:
		solids.append({"faces": FloorplanSection.transform_points(faces, csg.global_transform)})


## The ONE Shape3D -> solid adapter. Static and pure, so every branch is unit-testable without a tree.
## WorldBoundaryShape3D and HeightMapShape3D return {} deliberately: an infinite plane would cut a segment
## straight across the entire map, and a heightfield is terrain rather than wall.
static func shape_solid(shape: Shape3D, xf: Transform3D) -> Dictionary:
	if shape is BoxShape3D:
		return {"hull": FloorplanSection.box_points((shape as BoxShape3D).size, xf)}
	if shape is ConvexPolygonShape3D:
		var pts := (shape as ConvexPolygonShape3D).points
		return {"hull": FloorplanSection.transform_points(pts, xf)} if pts.size() >= 4 else {}
	if shape is ConcavePolygonShape3D:
		var faces := (shape as ConcavePolygonShape3D).get_faces()
		return {"faces": FloorplanSection.transform_points(faces, xf)} if faces.size() >= 3 else {}
	if shape is CylinderShape3D:
		var cyl := shape as CylinderShape3D
		return {"hull": FloorplanSection.prism_points(cyl.radius, cyl.height, ROUND_SIDES, xf)}
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		return {"hull": FloorplanSection.prism_points(cap.radius, cap.height, ROUND_SIDES, xf)}
	if shape is SphereShape3D:
		var sph := shape as SphereShape3D
		return {"hull": FloorplanSection.prism_points(sph.radius, sph.radius * 2.0, ROUND_SIDES, xf)}
	return {}


## Cut every solid at plane `y` into flat draw_multiline pairs, shell- and noise-rejected. Cheap enough to
## run per floor band; the result is what the deck caches.
##
## `merge` = draw the cut as ONE SILHOUETTE (FloorplanSection.silhouette): a level is built out of overlapping
## boxes, but a floorplan drawn as overlapping boxes reads as a wireframe of the brushwork rather than as
## rooms, so every side buried inside a neighbouring solid is removed. `weld` is how far apart two solids may
## be and still count as one — brushes that share a face exactly are the normal case and need it nonzero.
## Off = every solid draws its own closed ring, the original look and the escape hatch.
##
## THE ORDER IS THE CONTRACT: reject FIRST, merge SECOND. A rejected ring must never become an occluder — a
## void-seal brush encloses the whole map, and one promoted to an occluder would erase every wall inside it.
func slice(y: float, max_span: float, min_span: float, merge: bool = true,
		weld: float = 0.0) -> PackedVector2Array:
	var rings: Array[PackedVector2Array] = []
	var soup := PackedVector2Array()
	for s in solids:
		if s.has("faces"):
			# A trimesh cut is an unordered segment set, never a ring — see FloorplanSection.silhouette on why
			# it is clipped by the rings but never clips them.
			soup.append_array(FloorplanSection.slice_faces(s["faces"], y))
			continue
		var ring := FloorplanSection.slice_hull(s["hull"], y)
		if ring.size() < 3:
			continue  # the solid does not reach this height
		if FloorplanSection.ring_is_shell(ring, max_span):
			continue
		if FloorplanSection.ring_is_noise(ring, min_span):
			continue
		rings.append(ring)
	if merge:
		return FloorplanSection.silhouette(rings, soup, weld)
	var out := PackedVector2Array()
	for r in rings:
		out.append_array(FloorplanSection.ring_edges(r))
	out.append_array(soup)
	return out


## How many solids the last gather() found. The first thing to check when a level draws no walls.
func solid_count() -> int:
	return solids.size()
