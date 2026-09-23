extends RefCounted

## @system World Streaming
## @seam WorldspaceBuilder is the scaffold behind File -> Run scripts/tools/new_worldspace.gd: it builds a worldspace's persistent layer from LevelTemplate.tscn (minus the navmesh + ground, plus a ChunkStreamer) and one WorldChunk scene per grid cell, each with a cell-fitted navmesh baked from its own subtree.
## @risk bake_chunk parses the chunk's OWN subtree (SOURCE_GEOMETRY_ROOT_NODE_CHILDREN on a throwaway copy of the settings), never the navmesh group: in the editor that group also holds the open scene's geometry, which would bake an unrelated level's floor into the chunk.
## @test res://tests/test_worldspace_builder.gd
##
## Preloaded as a const where needed (NO class_name). Consumers: new_worldspace.gd, tests.

const ChunkGrid = preload("res://scripts/world/chunk_grid.gd")
const CHUNK_SCRIPT := "res://scripts/world/world_chunk.gd"
const STREAMER_SCRIPT := "res://scripts/world/chunk_streamer.gd"
const SEE_THROUGH_SCRIPT := "res://scripts/components/see_through_brushes.gd"
const TEMPLATE_SCENE := "res://scenes/levels/LevelTemplate.tscn"

## Nodes of LevelTemplate.tscn that belong in a CHUNK, not in the persistent layer: the navmesh region and the ground.
## SeeThroughBrushes walks the subtree it sits in, so each chunk gets its own instead.
const PERSISTENT_DROP: Array[StringName] = [&"NavigationRegion3D", &"Geometry", &"SeeThroughBrushes"]


## A fresh chunk scene root for `cell`: a WorldChunk with a NavigationRegion3D (the template's bake settings, fitted to
## the cell), a `Geometry` group-navmesh node holding a flat ground tile whose COLLIDER runs `skirt` metres past the
## cell edge on every side (the floor the edge bake needs — see WorldChunk SEAMS) while the visible tile stays exactly
## the cell, and the usual empty Characters / Lights / Objects buckets. Built at WORLD position unless `at_origin`.
## Not baked — call bake_chunk once it is in a tree. Every node is owned by the root, so PackedScene.pack keeps them.
static func build_chunk(cell: Vector2i, size: float, skirt: float = 2.0, tint: Color = Color(0.35, 0.36, 0.33), at_origin: bool = false) -> Node3D:
	var root: Node3D = load(CHUNK_SCRIPT).new()
	root.name = "Chunk"
	root.set(&"cell", cell)
	root.set(&"cell_size", size)
	root.set(&"authored_at_origin", at_origin)
	var nav := _template_navmesh()
	root.set(&"nav_border", maxf(1.0, nav.agent_radius))

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	region.visible = false
	region.navigation_mesh = nav
	_own(root, root, region)
	region.add_to_group(Groups.NAVMESH, true)
	root.call(&"apply_cell_fit", region.navigation_mesh)

	var geometry := Node3D.new()
	geometry.name = "Geometry"
	_own(root, root, geometry)
	geometry.add_to_group(Groups.NAVMESH, true)

	var corner := Vector3.ZERO if at_origin else ChunkGrid.chunk_origin(cell, size)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size, 1.0, size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mesh.material = mat
	ground.mesh = mesh
	ground.position = corner + Vector3(size * 0.5, -0.5, size * 0.5)
	_own(root, geometry, ground)
	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	_own(root, ground, body)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(size + skirt * 2.0, 1.0, size + skirt * 2.0)
	shape.shape = box
	_own(root, body, shape)
	var blockout := Node3D.new()
	blockout.name = "Blockout"
	_own(root, geometry, blockout)
	blockout.add_to_group(Groups.NAVMESH, true)

	for bucket in [&"Characters", &"Lights", &"Objects"]:
		var n := Node.new()
		n.name = bucket
		_own(root, root, n)
	var see: Node = load(SEE_THROUGH_SCRIPT).new()
	see.name = "SeeThroughBrushes"
	_own(root, root, see)
	return root


## Bake `chunk`'s navmesh from its own subtree, synchronously, fitted to its cell. The chunk must be inside a tree
## (static-body parsing reads global transforms). Returns the baked polygon count (0 = nothing walkable was found).
## CSG caveat (measured): a CSG node builds its collision a deferred call after it enters the tree, and nothing public
## forces it, so CSG added in the SAME frame as this bake is not parsed. The editor's bake_and_audit is never that
## early; a script that builds CSG and bakes at once must wait a frame first.
static func bake_chunk(chunk: Node3D) -> int:
	var region: NavigationRegion3D = null
	for n in chunk.find_children("*", "NavigationRegion3D", true, false):
		region = n
		break
	if region == null or region.navigation_mesh == null or not chunk.is_inside_tree():
		return 0
	var nav := region.navigation_mesh
	if chunk.has_method(&"apply_cell_fit"):
		chunk.call(&"apply_cell_fit", nav)
	# Parse THIS subtree only. The saved settings keep the template's group mode (so the editor's own Bake button
	# still works inside the chunk scene); the throwaway copy switches to root-children for this parse.
	var parse_settings := nav.duplicate() as NavigationMesh
	parse_settings.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(parse_settings, source, region.get_parent())
	NavigationServer3D.bake_from_source_geometry_data(nav, source)
	return nav.get_polygon_count()


## The persistent layer: LevelTemplate.tscn with its navmesh region, ground and SeeThroughBrushes removed and a
## ChunkStreamer added, the PlayerSpawn moved to the middle of `spawn_cell`. `chunk_folder` is where the chunk scenes
## live. Returns null when the template can't load.
static func build_persistent(chunk_folder: String, size: float, spawn_cell: Vector2i = Vector2i.ZERO, at_origin: bool = false) -> Node3D:
	var template := load(TEMPLATE_SCENE) as PackedScene
	if template == null:
		return null
	var root := template.instantiate() as Node3D
	for drop in PERSISTENT_DROP:
		var n := root.get_node_or_null(NodePath(String(drop)))
		if n != null:
			root.remove_child(n)
			n.free()
	var streamer: Node3D = load(STREAMER_SCRIPT).new()
	streamer.name = "ChunkStreamer"
	streamer.set(&"chunk_folder", chunk_folder)
	streamer.set(&"chunk_size", size)
	streamer.set(&"offset_chunks_to_grid", at_origin)
	_own(root, root, streamer)
	var spawn := root.get_node_or_null(^"PlayerSpawn") as Node3D
	if spawn != null:
		spawn.position = ChunkGrid.chunk_origin(spawn_cell, size) + Vector3(size * 0.5, 1.5, size * 0.5)
	return root


## Scatter `count` landmark pillars over `chunk`'s cell, placed from a hash of the cell so a re-scaffold puts them in
## the same spots. 1 m wide on purpose: the bake erodes agent_radius off every side of the top, so a pillar carves a
## hole in the navmesh without baking a walkable roof (no NavBlocker needed, and the LevelRoot validator's
## elevated-polygon check stays quiet). A mesh + StaticBody3D rather than CSG: a CSG node builds its shape a frame
## after it enters the tree, and the scaffold bakes the same frame. Call BEFORE bake_chunk.
static func add_landmarks(chunk: Node3D, count: int) -> void:
	var blockout := chunk.get_node_or_null(^"Geometry/Blockout")
	if blockout == null or count <= 0:
		return
	var cell: Vector2i = chunk.get(&"cell")
	var size: float = chunk.get(&"cell_size")
	var at_origin: bool = chunk.get(&"authored_at_origin")
	var corner := Vector3.ZERO if at_origin else ChunkGrid.chunk_origin(cell, size)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell)
	for i in count:
		var h := rng.randf_range(3.0, 9.0)
		var pillar := MeshInstance3D.new()
		pillar.name = "Landmark%d" % i
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.0, h, 1.0)
		pillar.mesh = mesh
		# Keep clear of the cell edge so a pillar never straddles a seam.
		pillar.position = corner + Vector3(rng.randf_range(4.0, size - 4.0), h * 0.5, rng.randf_range(4.0, size - 4.0))
		_own(chunk, blockout, pillar)
		var body := StaticBody3D.new()
		body.name = "StaticBody3D"
		_own(chunk, pillar, body)
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = mesh.size
		shape.shape = box
		_own(chunk, body, shape)


## A checkerboard pair of ground tints so the cell edges read while walking a scaffolded world.
static func tint_for(cell: Vector2i) -> Color:
	return Color(0.36, 0.37, 0.33) if (cell.x + cell.y) % 2 == 0 else Color(0.30, 0.31, 0.28)


static func _template_navmesh() -> NavigationMesh:
	var template := load(TEMPLATE_SCENE) as PackedScene
	var inst := template.instantiate() if template != null else null
	var nav: NavigationMesh = null
	if inst != null:
		var region := inst.get_node_or_null(^"NavigationRegion3D") as NavigationRegion3D
		if region != null and region.navigation_mesh != null:
			nav = region.navigation_mesh.duplicate() as NavigationMesh
		inst.free()
	if nav == null:
		nav = NavigationMesh.new()
		nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		nav.agent_max_climb = 0.4
		nav.agent_max_slope = 30.0
	nav.clear()  # never carry the template's polygons, only its settings
	return nav


static func _own(root: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = root
