@tool
extends RefCounted

## Domain A of the project audit: walks the EDITED scene tree and collects each node's configuration warnings plus
## a few typed level checks (unbaked navmesh, duplicate PlayerSpawn entry_id). Returns findings as
## Array[{severity, source, message, node, domain}] -- `node` is the offending Node ref so the panel can jump to it,
## `domain` is always DOMAIN ("scene"), the Audit tab's row filter (scene rows are in the designer's default view).
## Pure over a given root -- explicit recursion, no editor globals.

const SceneWalk := preload("res://addons/cybersunday_tools/core/scene_walk.gd")

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
	return out
