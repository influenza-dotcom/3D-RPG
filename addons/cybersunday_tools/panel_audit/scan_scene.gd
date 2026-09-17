@tool
extends RefCounted

## Domain A of the project audit: walks the EDITED scene tree and collects each node's configuration warnings plus
## a few typed level checks (unbaked navmesh, duplicate PlayerSpawn entry_id). Returns findings as
## Array[{severity, source, message, node, domain}] -- `node` is the offending Node ref so the panel can jump to it,
## `domain` is always DOMAIN ("scene"), the Audit tab's row filter (scene rows are in the designer's default view).
## Pure over a given root -- explicit recursion, no editor globals.
##
## save_id checks (the one identity scheme, scripts/world/world_save_id.gd): save_id_findings() reports a persistable
## with a BLANK save_id (WARN — its state is keyed by path and position, so a layout edit loses it) and two
## persistables SHARING one (ERROR — both load and overwrite one saved state). run() adds only the duplicates, because
## each persistable's own config warning already reports a blank id as a row here; scripts/tools/validate_all.gd
## calls it with the blanks for every level scene, where no config warnings run.

const SceneWalk := preload("res://addons/cybersunday_tools/core/scene_walk.gd")
const WorldSaveId := preload("res://scripts/world/world_save_id.gd")

## The Audit tab's row-filter domain for every row this scanner emits.
const DOMAIN := "scene"


static func run(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	var spawn_ids := {}
	for n in SceneWalk.collect_all(root):
		var src := str(root.get_path_to(n))
		# Per-node engine config warnings (the engine method merges the script's _get_configuration_warnings up
		# the inheritance chain -- e.g. TutorialPrompt inheriting TriggerVolume's checks).
		for w in SceneWalk.config_warnings(n):
			out.append({"severity": "WARN", "source": src, "message": str(w), "node": n, "domain": DOMAIN})
		# Typed: an unbaked NavigationRegion3D (NPCs can't path).
		if n is NavigationRegion3D:
			var nm := (n as NavigationRegion3D).navigation_mesh
			if nm == null or nm.get_vertices().size() == 0:
				out.append({"severity": "ERROR", "source": src, "message": "NavigationRegion3D isn't baked (0 navmesh vertices) — NPCs have nothing to path on.", "node": n, "domain": DOMAIN})
		# Typed: duplicate non-blank PlayerSpawn entry_id (GameRoot uses the FIRST match).
		if n is PlayerSpawn:
			var id: StringName = (n as PlayerSpawn).entry_id
			if id != &"":
				if spawn_ids.has(id):
					out.append({"severity": "WARN", "source": src, "message": "Duplicate PlayerSpawn entry_id '%s' — GameRoot uses the FIRST, so the rest are dead." % id, "node": n, "domain": DOMAIN})
				spawn_ids[id] = true
	if WorldSaveId.is_level_scene(root):
		out.append_array(save_id_findings(root, false))
	return out


## The save_id findings for the level rooted at `root`: a WARN per persistable (WorldSaveId.wants_save_id) with a blank
## save_id when `include_blank`, and an ERROR per id used by more than one persistable. Walks EVERY node, instances
## included, because an id baked into a prefab is duplicated by every copy of it. Findings use run()'s shape; `source`
## is the node path from `root`.
static func save_id_findings(root: Node, include_blank: bool = true) -> Array:
	var out: Array = []
	if root == null:
		return out
	var by_id := {}
	for n in SceneWalk.collect_all(root):
		if n == root or not WorldSaveId.wants_save_id(n):
			continue
		var src := str(root.get_path_to(n))
		var id := StringName(n.get(&"save_id"))
		if id == &"":
			if include_blank:
				out.append({"severity": "WARN", "source": src, "message": _blank_message(n, root), "node": n, "domain": DOMAIN})
			continue
		if not by_id.has(id):
			by_id[id] = []
		(by_id[id] as Array).append(n)
	for id in by_id:
		var nodes: Array = by_id[id]
		if nodes.size() < 2:
			continue
		var paths := PackedStringArray()
		for n in nodes:
			paths.append(str(root.get_path_to(n)))
		out.append({"severity": "ERROR", "source": paths[0],
			"message": "save_id '%s' is used by %d objects (%s) — they all load and overwrite ONE saved state. Clear the copies' ids and use Place → Stamp Missing save_ids. An id set inside a reusable prefab repeats in every copy of it." % [id, nodes.size(), ", ".join(paths)],
			"node": nodes[0], "domain": DOMAIN})
	return out


## A blank persistable inside an instance the level does not let you edit can't simply be stamped: say how.
static func _blank_message(n: Node, root: Node) -> String:
	var holder := n.owner
	if holder != null and holder != root and not root.is_editable_instance(holder):
		return "No save_id, and it sits inside the instance '%s', whose internals this level does not save. Enable Editable Children on that instance, then use Place → Stamp Missing save_ids; until then %s" % [root.get_path_to(holder), WorldSaveId.BLANK_ID_CAUSE.trim_prefix("No save_id: ")]
	return "%s Use Place → Stamp Missing save_ids (or type a unique id)." % WorldSaveId.BLANK_ID_CAUSE
