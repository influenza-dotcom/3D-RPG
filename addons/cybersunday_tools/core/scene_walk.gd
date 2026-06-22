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
