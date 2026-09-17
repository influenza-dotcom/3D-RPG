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
##
## save_id STAMPING (the one identity scheme, see scripts/world/world_save_id.gd): stamp_save_ids() gives every blank
## persistable a placement just added a unique save_id, and missing_save_id_nodes() lists the ones an existing level
## lacks for the Place tab's batch stamp. Both follow own_recursive's instance rule: only a node the LEVEL saves
## (owned by the scene root, or an instance's root) is stamped — a property set inside an instance is not written
## to the level file, so an id there would silently vanish on save.

const WorldSaveId := preload("res://scripts/world/world_save_id.gd")


## Own `node` + every freshly-built descendant to `root` so the whole subtree saves into the edited scene. An
## instanced sub-scene (scene_file_path != "") — whether it's `node` itself (a placed prefab like NPC.tscn) or a
## descendant (a nested instance) — is owned at its ROOT but NOT recursed into: its internals belong to the instance.
##
## The top-node guard is load-bearing. The Place tab hands us instanced prefabs (NPC / Door / Container / …). If we
## recursed into one, we'd re-own its internals as editable-children overrides AND — fatally for NPCs — bake the
## BodyModelSwap's UNOWNED @tool live-preview parts (Torso/head/arms/legs it spawns for the editor) into the saved
## .tscn. Those baked duplicates then ride along at runtime as static, untextured, un-animated, un-outlined bodies
## UNDER the real swapped body (the runtime _rebuild spawns a fresh, hidden-Man.glb set). Built (non-instanced)
## subtrees — e.g. the CSG blockout pieces — have scene_file_path == "", so they still recurse and own fully.
static func own_recursive(node: Node, root: Node) -> void:
	if node == null or root == null:
		return
	node.owner = root
	if node != root and node.scene_file_path != "":
		return  # `node` is itself an instance: own only its root, leave its internals to the instance
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


## Stamp a unique save_id on every persistable in the subtree rooted at `node` whose id is blank (WorldSaveId
## .wants_save_id — opted-out pickups stay blank), descending the way own_recursive does: an instanced sub-scene is
## stamped at its root but never inside, unless the level has Editable Children on for it. Ids are unique against
## every id already used under `root`. Returns how many were stamped. The Place tab, Palette and Item placer run it
## inside their placement undo action, so undoing the placement removes the stamped node with it.
static func stamp_save_ids(node: Node, root: Node) -> int:
	if node == null or root == null:
		return 0
	var taken := used_save_ids(root)
	var targets: Array[Node] = []
	_collect_stampable(node, targets, root)
	var stamped := 0
	for n in targets:
		if StringName(n.get(&"save_id")) != &"":
			continue
		var id := WorldSaveId.new_save_id(n, taken)
		taken[id] = true
		n.set(&"save_id", id)
		stamped += 1
	return stamped


## Every blank persistable in the scene that the scene file itself saves (the nodes stamp_save_ids would stamp if the
## whole scene were placed), for the Place tab's "Stamp Missing save_ids". The root itself is skipped: a prefab's own
## root is what gets stamped once it is placed in a level.
static func missing_save_id_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	if root == null:
		return out
	var targets: Array[Node] = []
	for c in root.get_children():
		_collect_stampable(c, targets, root)
	for n in targets:
		if StringName(n.get(&"save_id")) == &"":
			out.append(n)
	return out


## The set { save_id: true } of every non-blank save_id under `root` (all descendants, instances included — an id
## baked into a prefab still collides).
static func used_save_ids(root: Node) -> Dictionary:
	var out := {}
	if root == null:
		return out
	if &"save_id" in root:
		var id := StringName(root.get(&"save_id"))
		if id != &"":
			out[id] = true
	for c in root.get_children():
		out.merge(used_save_ids(c))
	return out


static func _collect_stampable(node: Node, out: Array[Node], root: Node) -> void:
	if WorldSaveId.wants_save_id(node):
		out.append(node)
	if node.scene_file_path != "" and node != root and not root.is_editable_instance(node):
		return  # an instance: its root is saved in the level, its internals are not (unless Editable Children is on)
	for c in node.get_children():
		_collect_stampable(c, out, root)
