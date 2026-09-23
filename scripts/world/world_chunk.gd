@tool
class_name WorldChunk
extends LevelRoot

## @system World Streaming
## @seam WorldChunk is the root of one streamed chunk scene: a LevelRoot (so Ps1Warp.cover and the runtime brush z-fight pass apply to it exactly as to a whole level) whose validator wants a baked navmesh but NO sky and NO PlayerSpawn — those belong to the worldspace's persistent layer.
## @seam fit_navmesh_to_cell writes filter_baking_aabb + border_size onto the chunk's NavigationMesh so the bake stops EXACTLY at the cell edge with no agent_radius erosion — which is what lets two neighbouring chunks' regions knit into one network at runtime.
## @risk A WorldChunk that carries its own WorldEnvironment silently swaps the whole world's sky every time it streams in or out; the validator flags it, nothing at runtime does.
## @risk A chunk baked WITHOUT the cell fit erodes agent_radius off every edge, leaving a ~1.2 m gap no edge connection bridges — NPCs stop dead at every chunk border with nothing logged.
## @test res://tests/test_chunk_streamer.gd
##
## Make one chunk: new scene, root = WorldChunk, save it as `chunk_<x>_<z>.tscn` in the worldspace's ChunkStreamer
## `chunk_folder` (or File -> Run scripts/tools/new_worldspace.gd, which scaffolds a whole grid). Set `cell` and
## `cell_size` below to match. Put the cell's ground, buildings, props, lights and NPCs under it, plus a
## NavigationRegion3D with the usual template settings (see CLAUDE.md's Navmesh bake policy).
##
## SEAMS: let the walkable ground run a little PAST the cell edge (more than `nav_border` metres — an invisible
## collider-only skirt is fine) and bake with `bake_and_audit` below, which fits the navmesh to the cell first. The
## skirt gives Recast real floor to erode, and the fit cuts the result exactly on the edge, so this chunk's border
## polygons land on the same line as the neighbour's and the navigation map joins them.
##
## Everything else is the ordinary level toolkit — doors, containers, pickups, NPCs, spawners all work inside a chunk.
## What does NOT belong here: the WorldEnvironment / sun / day-night sky, the PlayerSpawns a door arrives at, and
## anything that must exist while the player is far away — those go in the worldspace scene next to the ChunkStreamer.

const ChunkGrid = preload("res://scripts/world/chunk_grid.gd")

## The grid cell this scene fills. Authoring metadata for the bake fit and the validator — at runtime the streamer
## places a chunk by its FILE NAME, so keep the two in agreement.
@export var cell: Vector2i = Vector2i.ZERO
## Cell width in metres; must match the ChunkStreamer's chunk_size.
@export_range(4.0, 4096.0, 1.0, "or_greater", "suffix:m") var cell_size: float = 64.0
## ON when the worldspace's ChunkStreamer has `offset_chunks_to_grid` on (this chunk is built around its own origin);
## OFF (default) when chunks are built at their real world positions.
@export var authored_at_origin: bool = false
## How far past the cell edge the navmesh bake reads before trimming back to the edge (NavigationMesh.border_size;
## the bake filter box is the cell grown by this much). Keep it at least the navmesh agent_radius so the edge isn't
## eroded, and run the ground further than this past the cell edge.
@export_range(0.0, 8.0, 0.05, "suffix:m") var nav_border: float = 1.0

## EDITOR ACTION: write the cell bounds into this chunk's NavigationMesh (filter_baking_aabb + border_size) without
## baking. `bake_and_audit` does this for you first; use this when you bake from the region's own toolbar. Momentary.
@export var fit_navmesh_to_cell: bool = false:
	set(value):
		fit_navmesh_to_cell = false
		if value:
			_fit_now()

## Recast stores a span's height in 13 bits, so a bake box taller than ~8191 x cell_height WRAPS every height around
## (measured: a 2 km box at cell_height 0.01 baked a floor at y=0 as y=-942). The box's height is therefore fitted to
## the chunk's own geometry (plus this headroom above and below) instead of spanning the whole column.
const _HEIGHT_PAD := 4.0
const _RECAST_MAX_SPANS := 8000
## Height range used when a chunk has no geometry yet (an empty scaffold): a band around the origin.
const _EMPTY_HALF_HEIGHT := 16.0


## The cell's bounds in THIS chunk's local space (which is the navmesh's space for a region at the chunk root): the
## cell's world rect when built at world positions, 0..size when built around the origin. Its height is the chunk's
## geometry height range, padded (see _HEIGHT_PAD).
func cell_bounds() -> AABB:
	var corner := Vector3.ZERO if authored_at_origin else ChunkGrid.chunk_origin(cell, cell_size)
	var y := geometry_height_range()
	return AABB(Vector3(corner.x, y.x, corner.z), Vector3(cell_size, y.y - y.x, cell_size))


## (min_y, max_y) of every mesh and collision shape under this chunk (the navmesh region excluded), in chunk-local space,
## padded by _HEIGHT_PAD. Walks LOCAL transforms, so it works off-tree too.
func geometry_height_range() -> Vector2:
	var acc := Vector2(INF, -INF)
	for c in get_children():
		acc = _height_walk(c, Transform3D.IDENTITY, acc)
	if acc.x > acc.y:
		return Vector2(-_EMPTY_HALF_HEIGHT, _EMPTY_HALF_HEIGHT)
	return Vector2(acc.x - _HEIGHT_PAD, acc.y + _HEIGHT_PAD)


## The tallest bake box the navmesh's cell_height can hold without wrapping (Recast's span-height limit).
static func max_bake_height(nav: NavigationMesh) -> float:
	return (nav.cell_height if nav != null else 0.25) * _RECAST_MAX_SPANS


func _height_walk(n: Node, parent_xf: Transform3D, acc: Vector2) -> Vector2:
	if n is NavigationRegion3D or n.has_meta(&"_chunk_preview"):
		return acc
	var xf := parent_xf
	if n is Node3D:
		xf = parent_xf * (n as Node3D).transform
	var box := AABB()
	var has_box := false
	if n is VisualInstance3D:
		box = (n as VisualInstance3D).get_aabb()
		has_box = true
	elif n is CollisionShape3D and (n as CollisionShape3D).shape != null:
		var dm := (n as CollisionShape3D).shape.get_debug_mesh()
		if dm != null:
			box = dm.get_aabb()
			has_box = true
	if has_box:
		var world_box := xf * box
		acc.x = minf(acc.x, world_box.position.y)
		acc.y = maxf(acc.y, world_box.end.y)
	for c in n.get_children():
		acc = _height_walk(c, xf, acc)
	return acc


## The navmesh bake filter: the cell grown by `nav_border` on X/Z. Godot's border_size is carved INSIDE the filter
## box (measured: a filter exactly on the cell left the mesh one border short of each edge), so the box has to reach
## one border past the cell for the trimmed result to end ON the cell line.
func bake_filter_aabb() -> AABB:
	var b := cell_bounds()
	return AABB(b.position - Vector3(nav_border, 0.0, nav_border), b.size + Vector3(nav_border * 2.0, 0.0, nav_border * 2.0))


## Apply the cell fit to `nav` (pure — the unit-tested half of fit_navmesh_to_cell). The region's own transform is
## expected to be identity under the chunk root; the validator flags one that isn't.
func apply_cell_fit(nav: NavigationMesh) -> void:
	if nav == null:
		return
	nav.filter_baking_aabb = bake_filter_aabb()
	nav.filter_baking_aabb_offset = Vector3.ZERO
	nav.border_size = nav_border
	snap_agent_to_voxels(nav)


## Recast bakes in whole voxels: it CEILS agent_height / agent_radius to cell units and truncates region_min_size²
## to an int, warning each time a value is not already on the grid. LevelTemplate's 2.2 m / 0.6 m / 0.1 on a
## 0.01 × 0.25 grid is off it on all three, so every chunk bake warned (and the test suite fails on warnings). This
## writes the values the bake ACTUALLY uses — 2.2 m, 0.75 m, 0 — so nothing changes but the warning. The −1e-6 keeps
## a multiple that float32 cannot represent exactly (220 × 0.01) from rounding just past the voxel it names.
static func snap_agent_to_voxels(nav: NavigationMesh) -> void:
	if nav == null or nav.cell_size <= 0.0 or nav.cell_height <= 0.0:
		return
	nav.agent_height = ceilf(nav.agent_height / nav.cell_height - 0.001) * nav.cell_height - 1e-6
	nav.agent_radius = maxf(ceilf(nav.agent_radius / nav.cell_size - 0.001) * nav.cell_size - 1e-6, 0.0)
	nav.region_min_size = sqrt(floorf(nav.region_min_size * nav.region_min_size + 0.001))


func _fit_now() -> void:
	var region := _find_region()
	if region == null or region.navigation_mesh == null:
		push_warning("WorldChunk: no NavigationRegion3D with a NavigationMesh under this chunk to fit.")
		return
	apply_cell_fit(region.navigation_mesh)
	print("WorldChunk: fitted %s's navmesh to cell %s (%.0f m, border %.2f m) — bake to apply." % [name, cell, cell_size, nav_border])
	update_configuration_warnings()


func _bake_and_audit_now() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		var region := _find_region()
		if region != null and region.navigation_mesh != null:
			apply_cell_fit(region.navigation_mesh)
	super._bake_and_audit_now()


func _wants_world_environment() -> bool:
	return false


func _wants_player_spawn() -> bool:
	return false


func _get_configuration_warnings() -> PackedStringArray:
	var w := super._get_configuration_warnings()
	var region := _find_region()
	if region != null and region.navigation_mesh != null:
		var nm := region.navigation_mesh
		if not nm.filter_baking_aabb.is_equal_approx(bake_filter_aabb()) or not is_equal_approx(nm.border_size, nav_border):
			w.append("The navmesh isn't fitted to cell %s — its border would erode and NOT join the neighbouring chunks. Tick `bake_and_audit` (it fits first), or `fit_navmesh_to_cell` then bake." % cell)
		elif nm.agent_radius > nav_border + 0.001:
			w.append("`nav_border` (%.2f m) is smaller than the navmesh agent_radius (%.2f m) — the edge still erodes. Raise it." % [nav_border, nm.agent_radius])
		if bake_filter_aabb().size.y > max_bake_height(nm):
			w.append("This chunk's geometry spans %.0f m of height, more than the navmesh cell_height (%.2f) can bake in one box (%.0f m) — heights would wrap. Raise cell_height or split the tall content." % [bake_filter_aabb().size.y, nm.cell_height, max_bake_height(nm)])
		if not region.transform.is_equal_approx(Transform3D.IDENTITY):
			w.append("The NavigationRegion3D isn't at the chunk root's origin — the cell fit assumes it is. Reset its transform (move the geometry, not the region).")
	# Only for the default <name>_<x>_<z>.tscn naming; a custom file_pattern is the author's to keep straight.
	var file := scene_file_path.get_file()
	var m := RegEx.create_from_string("_(-?\\d+)_(-?\\d+)\\.tscn$").search(file)
	if m != null and Vector2i(int(m.get_string(1)), int(m.get_string(2))) != cell:
		w.append("`cell` is %s but the file is '%s' — the streamer places a chunk by its file name. Make them agree." % [cell, file])
	return w
