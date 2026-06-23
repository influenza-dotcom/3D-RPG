@tool
extends RefCounted

## PURE, testable helpers for the CYBER SUNDAY "Place" tab (scene_placer.gd). NO EditorInterface, NO scene-tree
## navigation, NO undo_redo — just node-tree bookkeeping a GUT test can exercise headless. scene_placer.gd keeps
## all the editor glue (get_edited_scene_root / viewport camera / EditorUndoRedoManager) and calls into here.
##
## The one load-bearing routine is own_recursive(), mirrored from item_placer_dock._own_recursive: when you build
## or instance a subtree and add it to the edited scene, every freshly-built node must have its `owner` set to the
## scene root or it WON'T be written to the .tscn on save. An instanced sub-scene root is owned but NOT recursed
## into — its internals belong to that instance and must keep their own owner.


## Own `node` + every freshly-built descendant to `root` so the whole subtree saves into the edited scene. A child
## that is itself an instanced sub-scene (scene_file_path != "") is owned at its root but NOT recursed into.
static func own_recursive(node: Node, root: Node) -> void:
	if node == null or root == null:
		return
	node.owner = root
	for c in node.get_children():
		if c.scene_file_path == "":
			own_recursive(c, root)
		else:
			c.owner = root


## True when every node in the subtree rooted at `node` is owned by `root` (the post-condition own_recursive must
## establish), with the SAME instanced-sub-scene rule: an instanced child is checked at its root but not descended.
## The subtree root itself is exempt only when it IS `root` (a scene root owns nothing).
static func is_owned_recursive(node: Node, root: Node) -> bool:
	if node == null or root == null:
		return false
	if node != root and node.owner != root:
		return false
	for c in node.get_children():
		if c.owner != root:
			return false
		if c.scene_file_path == "":
			if not is_owned_recursive(c, root):
				return false
	return true


## Count the nodes own_recursive() will touch (the subtree, stopping the descent at instanced sub-scenes). Handy
## for a status read-out ("placed N nodes") and a deterministic test assertion without poking the editor.
static func owned_count(node: Node) -> int:
	if node == null:
		return 0
	var n := 1
	for c in node.get_children():
		if c.scene_file_path == "":
			n += owned_count(c)
		else:
			n += 1
	return n
