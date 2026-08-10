class_name FloorplanSource
extends RefCounted

## @system Minimap
## @seam gather(root, hide_group) is the ONE place level geometry becomes minimap geometry: it walks a level subtree once and converts every STATIC collider into a world-space convex hull or triangle soup, which slice() then cuts at any height. Split out of FloorplanSection precisely so that file can stay pure and provable.
## @risk The static gate is `is StaticBody3D and not is AnimatableBody3D` — a PHYSICS LAYER cannot be used, because Player.tscn and enemy.tscn are both collision_layer 2, the same layer as level ground, so a mask would freeze every NPC in the room into the map as a wall blob.
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
## Convex hulls cut to closed RINGS (rooms read as outlines); soups cut to loose SEGMENTS.

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
	# THE STATIC GATE. Type, never a physics layer: Player.tscn and enemy.tscn are both collision_layer 2,
	# which is also TestLevel's ground layer, so no mask can separate characters from geometry here — and a
	# character that slipped through would be frozen into the deck cache as a wall blob that never moves.
	# AnimatableBody3D is excluded explicitly because it INHERITS StaticBody3D: a door leaf baked in whatever
	# pose it happened to hold would draw a closed door forever. Floorplans draw openings, not leaves.
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
func slice(y: float, max_span: float, min_span: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for s in solids:
		if s.has("faces"):
			out.append_array(FloorplanSection.slice_faces(s["faces"], y))
			continue
		var ring := FloorplanSection.slice_hull(s["hull"], y)
		if ring.size() < 3:
			continue  # the solid does not reach this height
		if FloorplanSection.ring_is_shell(ring, max_span):
			continue
		if FloorplanSection.ring_is_noise(ring, min_span):
			continue
		out.append_array(FloorplanSection.ring_edges(ring))
	return out


## How many solids the last gather() found. The first thing to check when a level draws no walls.
func solid_count() -> int:
	return solids.size()
