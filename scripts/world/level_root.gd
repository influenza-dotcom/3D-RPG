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
		if n.is_in_group(&"navmesh") and not (n is NavigationRegion3D):
			has_navmesh_geometry = true

	# Sky / ambient (StarSky repaints any WorldEnvironment in the `world_environment` group — see star_sky.gd).
	if world_env == null:
		w.append("No WorldEnvironment — add one (in group `world_environment`) so the level has a sky/fog and StarSky can repaint it.")
	elif not world_env.is_in_group(&"world_environment"):
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
			if rep.islands.size() > 1:
				w.append("Navmesh has %d disconnected islands — an NPC on one can't reach another. Bridge the floor gaps / remove stray walkable surfaces, then re-bake. (File -> Run `audit_navmesh.gd` for locations.)" % rep.islands.size())
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
