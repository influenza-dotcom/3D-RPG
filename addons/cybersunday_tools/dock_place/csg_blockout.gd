@tool
extends RefCounted

## PURE, testable builders for the CYBER SUNDAY "Place" tab CSG-blockout buttons (scene_placer.gd). NO
## EditorInterface, NO undo_redo, NO scene-tree glue — just constructs CSG node subtrees a GUT test can assert
## headless (mirrors place_ops.gd). scene_placer.gd does the editor placement (own/undo/viewport) around these.
##
## WHY CSG for blockout: CSGShape3D geometry feeds the level's group-based NavigationRegion3D bake in Godot 4.6
## (verified — every parser mode bakes it), so a CSG shell drops straight into the existing `navmesh`-group bake +
## NavMeshAudit + LevelRoot validator with NO new pipeline. Each returned root is put in the `Groups.NAVMESH` group
## and (for root CSG shapes) gets `use_collision = true`, so the bake parses it and physics works. Adding a piece to
## the group even when it also sits under the already-grouped `Geometry` node is harmless — the bake dedupes the
## coincident geometry (verified: still one clean island).
##
## SEAMLESS INTERIORS — the load-bearing rule: a doorway/opening must be at least DOOR_MIN_CLEAR wide or the interior
## bakes as its OWN island and NPCs can't path in (agent_radius 0.6 erodes the opening; <2.4 m pinches it shut).
## build_room_shell() defaults the door to a safe DOOR_DEFAULT_CLEAR.

## Minimum clear opening (m) that survives the level's agent_radius=0.6 erosion and keeps interior+exterior ONE island.
const DOOR_MIN_CLEAR := 2.4
## Default doorway clear width the room-shell button uses — a margin above the minimum.
const DOOR_DEFAULT_CLEAR := 2.5

## A flat floor slab. Top face sits at local y=0 (so it rests on the ground plane when dropped at ground height).
static func build_floor(size := Vector3(8.0, 0.5, 8.0)) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = "BlockoutFloor"
	box.size = size
	box.position = Vector3(0, -size.y * 0.5, 0)  # top at y=0
	box.use_collision = true
	box.add_to_group(Groups.NAVMESH, true)
	return box

## A single wall slab. Base sits at local y=0 (rests on the floor); centered on x/z.
static func build_wall(size := Vector3(4.0, 3.0, 0.3)) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = "BlockoutWall"
	box.size = size
	box.position = Vector3(0, size.y * 0.5, 0)  # base at y=0
	box.use_collision = true
	box.add_to_group(Groups.NAVMESH, true)
	return box

## A walkable ramp (tilted slab). Slope is kept at/under the level's agent_max_slope=30° baseline so the bake makes
## it walkable; clamp here so a designer can't author an un-walkable ramp by accident. Low (z-) end base at y≈0.
static func build_ramp(width := 3.0, run := 6.0, rise := 1.8, thick := 0.3) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = "BlockoutRamp"
	# Clamp the slope to <=28° (a margin under agent_max_slope=30) by capping rise for the given run.
	var max_rise: float = run * tan(deg_to_rad(28.0))
	rise = clampf(rise, 0.0, max_rise)
	var length: float = sqrt(run * run + rise * rise)  # along-slope length so the footprint covers `run`
	box.size = Vector3(width, thick, length)
	box.rotation_degrees = Vector3(-rad_to_deg(atan2(rise, run)), 0, 0)  # +z end rises
	box.position = Vector3(0, rise * 0.5, 0)
	box.use_collision = true
	box.add_to_group(Groups.NAVMESH, true)
	return box

## An enterable building shell: 4 walls (no floor — it sits on the open ground so the interior floor IS the exterior
## ground, guaranteeing one continuous island) with a doorway gap in the +Z wall. `interior` is the inside clear size.
## The combiner carries the collision + group; its wall children combine into it (they are NOT individually grouped).
static func build_room_shell(interior := Vector2(8.0, 8.0), wall_h := 3.0, wall_t := 0.3, door_clear := DOOR_DEFAULT_CLEAR) -> CSGCombiner3D:
	door_clear = maxf(door_clear, DOOR_MIN_CLEAR)  # never author a door an NPC can't walk through
	var comb := CSGCombiner3D.new()
	comb.name = "BuildingShell"
	comb.use_collision = true
	comb.add_to_group(Groups.NAVMESH, true)

	var hx: float = interior.x * 0.5
	var hz: float = interior.y * 0.5
	var outer_x: float = hx + wall_t * 0.5  # outer extent of the side walls
	# Back wall (z = -hz), full width.
	_wall_child(comb, Vector3(0, wall_h * 0.5, -hz), Vector3(interior.x + wall_t, wall_h, wall_t))
	# Left / right walls (x = ±hx), full depth.
	_wall_child(comb, Vector3(-hx, wall_h * 0.5, 0), Vector3(wall_t, wall_h, interior.y))
	_wall_child(comb, Vector3(hx, wall_h * 0.5, 0), Vector3(wall_t, wall_h, interior.y))
	# Front wall (z = +hz) split around a centered doorway of clear width `door_clear`.
	var half_open: float = door_clear * 0.5
	var seg_w: float = outer_x - half_open
	if seg_w > 0.01:
		var seg_cx: float = (outer_x + half_open) * 0.5
		_wall_child(comb, Vector3(-seg_cx, wall_h * 0.5, hz), Vector3(seg_w, wall_h, wall_t))
		_wall_child(comb, Vector3(seg_cx, wall_h * 0.5, hz), Vector3(seg_w, wall_h, wall_t))
	return comb

static func _wall_child(comb: CSGCombiner3D, pos: Vector3, size: Vector3) -> void:
	var w := CSGBox3D.new()
	w.size = size
	w.position = pos
	comb.add_child(w)
