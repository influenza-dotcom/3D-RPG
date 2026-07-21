@tool
class_name LevelRoot
extends Node3D

## The root script for a LEVEL scene (the Node GameRoot loads as the "Level" child). At RUNTIME it's a no-op — it
## exists purely so the EDITOR can tell you, right in the inspector, whether the level has everything it needs to
## actually work: a sky StarSky can repaint, a navmesh region + geometry to bake from, and at least one PlayerSpawn
## for GameRoot to drop the player on. Start a new level by duplicating `scenes/levels/LevelTemplate.tscn` (or
## File -> Run `scripts/tools/new_level.gd`) — it comes pre-wired, so this validator stays quiet until you break it.

## EDITOR ACTION: tick to BAKE this level's NavigationRegion3D and immediately re-check it — closing the bake->audit
## loop in one click (instead of Bake, then File -> Run audit_navmesh.gd). Prints the island/elevated/climb verdict
## to the Output panel and refreshes the warnings below. Momentary (snaps back); editor-only, a no-op at runtime.
@export var bake_and_audit: bool = false:
	set(value):
		bake_and_audit = false  # momentary: snaps back so it always re-triggers
		if value:
			_bake_and_audit_now()

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	var nodes: Array[Node] = []
	_collect(self, nodes)

	var world_env: WorldEnvironment = null
	var region: NavigationRegion3D = null
	var has_navmesh_geometry := false
	var spawns: Array[PlayerSpawn] = []
	for n in nodes:
		if n is WorldEnvironment:
			world_env = n as WorldEnvironment
		elif n is NavigationRegion3D:
			region = n as NavigationRegion3D
		elif n is PlayerSpawn:
			spawns.append(n as PlayerSpawn)
		if n.is_in_group(Groups.NAVMESH) and not (n is NavigationRegion3D):
			has_navmesh_geometry = true

	# Sky / ambient (StarSky repaints any WorldEnvironment in the `world_environment` group — see star_sky.gd).
	if world_env == null:
		w.append("No WorldEnvironment — add one (in group `world_environment`) so the level has a sky/fog and StarSky can repaint it.")
	elif not world_env.is_in_group(Groups.WORLD_ENVIRONMENT):
		w.append("The WorldEnvironment isn't in the `world_environment` group — StarSky won't find it. Add it to that group.")

	# Navigation: a region, something to bake from, and an actual bake.
	if region == null:
		w.append("No NavigationRegion3D — NPCs have nothing to path on. Add one (in group `navmesh`).")
	else:
		if not has_navmesh_geometry:
			w.append("Nothing feeds the navmesh bake — put your walkable floor/props under a node in the `navmesh` group (e.g. a `Geometry` Node3D).")
		var nm := region.navigation_mesh
		if nm == null or nm.get_vertices().size() == 0:
			w.append("The NavigationRegion3D isn't baked — once your geometry is in, select it and click `Bake NavigationMesh`.")
		else:
			# Bake QUALITY, not just existence. This is the gate that catches the TestLevel failure mode — a
			# fragmented / over-climbing bake that passes every other check but strands NPCs on roofs and islands.
			# NavMeshAudit is a pure static (no tree / transforms), safe to run at edit time.
			if nm.agent_max_climb > 0.5:
				w.append("Navmesh `agent_max_climb` is %.2f — keep it ~0.4. Higher lets the bake climb onto props/car roofs (omitting the field falls back to the engine default 0.9, the TestLevel failure). Lower it and re-bake." % nm.agent_max_climb)
			if nm.geometry_parsed_geometry_type != NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS:
				w.append("Navmesh `Parsed Geometry Type` is not `Static Colliders` — it bakes walkable polys from VISUAL meshes (the engine default is `Both`), so NPCs stick on decorative geometry that has no collision. Set it to `Static Colliders` (walkability = the physics NPCs actually touch) and re-bake.")
			var rep := NavMeshAudit.analyze(nm)
			# Islands are judged LINK-AWARE (NavMeshAudit.reachability, fed this level's NavLinks): a deliberately
			# fragmented bake — this project's brush stairs bake as one island per flight — is FINE as long as the
			# links bridge every island, so we DON'T warn on the raw island count (that false-positives forever here).
			# We warn only when the links fail to knit the mesh into one reachable network, an endpoint lands off the
			# mesh (binds to nothing), or a one-way drop strands an island. That's what actually certifies the design.
			var reach := NavMeshAudit.reachability(nm, _links_local(region, nodes))
			if reach.effective_islands > 1:
				w.append("%d navmesh island(s) aren't bridged into one network — an NPC on one can't reach the rest. Add a NavLink across the gap (File -> Run `generate_nav_links.gd`) or fix the bake. (File -> Run `audit_navmesh.gd` for locations.)" % reach.effective_islands)
			if not reach.dangling.is_empty():
				w.append("%d NavLink endpoint(s) don't land on the navmesh — that link silently bridges nothing. Nudge the handle onto a walkable surface (auto_project only rescues near-misses within project_radius), then re-check." % reach.dangling.size())
			if not reach.one_way_only.is_empty():
				w.append("%d island(s) are reachable only ONE way (a ONE_WAY_DOWN link) — an NPC there can't get back. Add a TWO_WAY or ramp return if that's unintended." % reach.one_way_only.size())
			if rep.elevated.size() > 0:
				w.append("%d navmesh polygon(s) baked above the floor (likely prop/car roofs NPCs get stuck on). Add a `NavBlocker(CARVE)` on those props or lower `agent_max_climb`, then re-bake. (File -> Run `audit_navmesh.gd` for locations.)" % rep.elevated.size())

	# Player entry: at least one spawn, and no duplicate entry_ids (GameRoot._find_spawn uses the FIRST match).
	if spawns.is_empty():
		w.append("No PlayerSpawn — GameRoot can't place the player here. Drop a `scenes/world/PlayerSpawn.tscn` (leave one with a blank entry_id as the default arrival).")
	else:
		var seen := {}
		for s in spawns:
			var id := s.entry_id
			if id == &"":
				continue
			if seen.has(id):
				w.append("Two PlayerSpawns share entry_id `%s` — GameRoot uses the FIRST, so the other is dead. Make each entry_id unique." % id)
			seen[id] = true

	return w

## Every descendant of `node`, depth-first (excludes `node`). Explicit recursion on purpose — NOT
## get_tree().get_nodes_in_group(), which at edit time scans the WHOLE open editor scene, not just this level.
func _collect(node: Node, out: Array[Node]) -> void:
	for c in node.get_children():
		out.append(c)
		_collect(c, out)

## This level's ENABLED NavLinks as { a, b, bidirectional } in the REGION's local space (= navmesh space), for
## NavMeshAudit.reachability. A link's endpoints are stored local to the link node, so world-project (link transform)
## then invert the region transform. Edit-time safe (the nodes are in the tree with valid transforms); the reachability
## math itself stays transform-free so it still unit-tests off-tree. Disabled links contribute nothing to routing.
func _links_local(region: NavigationRegion3D, nodes: Array) -> Array:
	var out: Array = []
	var inv := region.global_transform.affine_inverse()
	for nd in nodes:
		if nd is NavigationLink3D and (nd as NavigationLink3D).enabled:
			var lk := nd as NavigationLink3D
			out.append({
				"a": inv * (lk.global_transform * lk.start_position),
				"b": inv * (lk.global_transform * lk.end_position),
				"bidirectional": lk.bidirectional,
			})
	return out

## The first NavigationRegion3D under this level (the bake target), or null.
func _find_region() -> NavigationRegion3D:
	var nodes: Array[Node] = []
	_collect(self, nodes)
	for n in nodes:
		if n is NavigationRegion3D:
			return n as NavigationRegion3D
	return null

## Editor-only: bake the region's navmesh (synchronously) then summarise + refresh the inspector warnings, so the
## author sees the island / elevated / climb verdict in one click. No-op at runtime / off-tree (so it's test-safe).
func _bake_and_audit_now() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var region := _find_region()
	if region == null:
		push_warning("LevelRoot: no NavigationRegion3D under this level to bake.")
		return
	if region.navigation_mesh == null:
		push_warning("LevelRoot: the NavigationRegion3D has no NavigationMesh resource — add one, then bake.")
		return
	if region.has_method("bake_navigation_mesh"):
		region.bake_navigation_mesh(false)  # on_thread = false: synchronous, so the audit below sees the fresh mesh
	var rep := NavMeshAudit.analyze(region.navigation_mesh)
	var settings: Dictionary = rep.get("settings", {})
	var verdict := "clean" if rep.ok else "ISSUES"
	print_rich("[b]LevelRoot bake+audit[/b] (%s): %d polys, %d island(s), floor y~%.1f, climb %.2f" % [verdict, rep.poly_count, rep.islands.size(), rep.floor_y, settings.get("agent_max_climb", 0.0)])
	for w in rep.warnings:
		print("   ! ", w)
	update_configuration_warnings()  # refresh the inspector warnings to match the fresh bake
