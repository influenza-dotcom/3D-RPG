@tool
extends RefCounted

## Editor-tool scene-tree helper. Class-filtered finds reuse the project's NodeFinder (cohesion); this only adds
## the "visit EVERY node" walk NodeFinder lacks -- the audit panel calls get_configuration_warnings() on each node.
##
## All recursion is EXPLICIT over a given root. NEVER use get_tree().get_nodes_in_group() at edit time: it spans
## the whole open editor scene, not the level/scene being edited (the same trap LevelRoot's validator avoids).

## Append `root` and every descendant to `out` (depth-first, root first). Returns `out` for chaining.
static func collect_all(root: Node, out: Array[Node] = []) -> Array[Node]:
	if root == null:
		return out
	out.append(root)
	for c in root.get_children():
		collect_all(c, out)
	return out

## A node's SCRIPT-defined configuration warnings. Godot 4.6 exposes no public get_configuration_warnings() getter
## (only the _get_configuration_warnings() virtual), so we call the override directly -- but ONLY when a GDScript in
## the node's script chain actually defines it (walking base scripts catches inheritance, e.g. TutorialPrompt over
## TriggerVolume). That gate keeps us off native editor-only virtuals that would error in a headless run. Empty
## otherwise. The instance call still dispatches to the most-derived override.
static func config_warnings(n: Node) -> PackedStringArray:
	var scr: Variant = n.get_script()
	while scr is GDScript:
		for md in (scr as GDScript).get_script_method_list():
			if String(md.get("name", "")) == "_get_configuration_warnings":
				var r: Variant = n.call(&"_get_configuration_warnings")
				return r if r is PackedStringArray else PackedStringArray()
		scr = (scr as GDScript).get_base_script()
	return PackedStringArray()
