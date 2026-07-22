@tool
extends EditorScript

## FUNC_GODOT NAVMESH — WIRE + BAKE  (File > Run / Ctrl+Shift+X with your TrenchBroom level OPEN in the editor).
##
## WHY THIS EXISTS: func_godot builds a TrenchBroom `.map` into brush geometry as a StaticBody (`entity_0_worldspawn`)
## full of per-brush CollisionShape3Ds, parented under a `FuncGodotMap` node. But that node is a SIBLING of the level's
## NavigationRegion3D and is in NO group, and a func_godot level's NavigationMesh ships as bare engine defaults. This
## project bakes the navmesh from the `navmesh` GROUP (see scripts/world/level_root.gd + groups.gd), so with the brush
## geometry outside that group AND a default NavigationMesh, the region bakes an EMPTY navmesh. NPCs then have nothing
## to path on: NavigationAgent3D reports finished + unreachable every frame, and the Locomotor falls into its
## straight-line pursuit branch — so they beeline at their target and grind into every wall between (the "NPCs keep
## trying to walk into walls" bug). No runtime anti-stuck logic can fix a missing navmesh; the geometry must be baked.
##
## WHAT IT DOES, on the currently-open scene:
##   1. adds the FuncGodotMap node to the `navmesh` group (GROUPS_WITH_CHILDREN then sweeps its brush colliders) — the
##      group sits on the PERSISTENT FuncGodotMap node, not the regenerated brush children, so it survives a map rebuild;
##   2. stamps the region's NavigationMesh with this project's standard bake params (identical to LevelTemplate /
##      NavSandbox: parse Static Colliders, agent_radius 0.6, agent_max_climb 0.4, …);
##   3. bakes synchronously and prints the NavMeshAudit verdict (polys / islands / elevated roofs).
##
## AFTER RUNNING: press Ctrl+S to save the scene (keeps the baked mesh + the group). RE-RUN after any func_godot map
## rebuild — the brushes regenerate, so the navmesh must be re-baked (the group persists, so it's just one click).

# Project-standard NavigationMesh bake params — kept in lockstep with scenes/levels/LevelTemplate.tscn. See the
# "Navmesh bake policy" section of CLAUDE.md for why each value matters (Static Colliders, climb 0.4, radius 0.6).
const AGENT_RADIUS := 0.6
const AGENT_HEIGHT := 2.2
const AGENT_MAX_CLIMB := 0.4
const AGENT_MAX_SLOPE := 30.0
const CELL_HEIGHT := 0.01
const REGION_MIN_SIZE := 0.1
const EDGE_MAX_ERROR := 0.1

func _run() -> void:
	var root := get_scene()  # the currently-open edited scene root
	if root == null:
		push_error("[BakeFuncGodotNavmesh] No scene is open. Open your func_godot (TrenchBroom) level, then File > Run this.")
		return
	var region := _first_of_type(root, "NavigationRegion3D") as NavigationRegion3D
	if region == null:
		push_error("[BakeFuncGodotNavmesh] No NavigationRegion3D in '%s'. Add one (as a child of the level root), then re-run." % root.name)
		return
	var funcmap := _find_funcgodot_map(root)
	if funcmap == null:
		push_error("[BakeFuncGodotNavmesh] No FuncGodotMap node found. This tool wires TrenchBroom brush geometry; for a hand-built level, put your walkable geometry under a node in the `navmesh` group and bake normally.")
		return

	# 1) Brush geometry into the bake group (persistent = true so it serializes into the .tscn on save).
	if not funcmap.is_in_group(Groups.NAVMESH):
		funcmap.add_to_group(Groups.NAVMESH, true)
		print_rich("[BakeFuncGodotNavmesh] Added [b]%s[/b] to the `navmesh` group." % funcmap.name)
	else:
		print_rich("[BakeFuncGodotNavmesh] %s already in the `navmesh` group." % funcmap.name)

	# 2) Stamp the region's NavigationMesh with the project-standard params (make one if the region has none).
	var nm := region.navigation_mesh
	if nm == null:
		nm = NavigationMesh.new()
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN  # bake from the `navmesh` group
	nm.geometry_source_group_name = Groups.NAVMESH
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS       # brush colliders, not visual meshes
	nm.agent_radius = AGENT_RADIUS
	nm.agent_height = AGENT_HEIGHT
	nm.agent_max_climb = AGENT_MAX_CLIMB
	nm.agent_max_slope = AGENT_MAX_SLOPE
	nm.cell_height = CELL_HEIGHT
	nm.region_min_size = REGION_MIN_SIZE
	nm.edge_max_error = EDGE_MAX_ERROR
	region.navigation_mesh = nm

	# 3) Bake synchronously (on_thread = false) so the audit below sees the fresh mesh, then report.
	if not region.has_method(&"bake_navigation_mesh"):
		push_error("[BakeFuncGodotNavmesh] Region can't bake on this engine build.")
		return
	print("[BakeFuncGodotNavmesh] Baking …")
	region.bake_navigation_mesh(false)
	var rep := NavMeshAudit.analyze(region.navigation_mesh)
	print_rich("[BakeFuncGodotNavmesh] Result: [b]%d polys[/b], %d verts, %d island(s), %d elevated, area %.0f" % [
		rep.poly_count, rep.vertex_count, rep.islands.size(), rep.elevated.size(), rep.total_area])
	for w in rep.warnings:
		print("   ! ", w)
	if rep.poly_count > 0:
		print_rich("[color=lime][BakeFuncGodotNavmesh] Navmesh baked. Press Ctrl+S to save the scene.[/color] NPCs will now path around walls instead of charging through them.")
	else:
		print_rich("[color=orange][BakeFuncGodotNavmesh] Baked 0 polys.[/color] Check that the brush StaticBody is on a collision layer the NavigationMesh reads (geometry_collision_mask) and that the map actually built its collision.")

## First descendant of the given class name (depth-first), or null. String-typed so the tool has no compile dep on the
## node class beyond NavigationRegion3D (which it casts).
func _first_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for c in node.get_children():
		var hit := _first_of_type(c, type_name)
		if hit != null:
			return hit
	return null

## The func_godot map node: identified by its script path (func_godot_map.gd) so a renamed node still matches; falls
## back to a node literally named "FuncGodotMap".
func _find_funcgodot_map(node: Node) -> Node:
	var scr: Variant = node.get_script()
	if scr is Script and (scr as Script).resource_path.ends_with("func_godot_map.gd"):
		return node
	if node.name == "FuncGodotMap":
		return node
	for c in node.get_children():
		var hit := _find_funcgodot_map(c)
		if hit != null:
			return hit
	return null
