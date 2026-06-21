@tool
class_name LevelRoot
extends Node3D

## The root script for a LEVEL scene (the Node GameRoot loads as the "Level" child). At RUNTIME it's a no-op — it
## exists purely so the EDITOR can tell you, right in the inspector, whether the level has everything it needs to
## actually work: a sky StarSky can repaint, a navmesh region + geometry to bake from, and at least one PlayerSpawn
## for GameRoot to drop the player on. Start a new level by duplicating `scenes/levels/LevelTemplate.tscn` (or
## File -> Run `scripts/tools/new_level.gd`) — it comes pre-wired, so this validator stays quiet until you break it.

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
