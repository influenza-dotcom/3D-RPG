extends GutTest

## Unit tests for the CYBER SUNDAY "Place" tab's PURE subtree bookkeeping (place_ops.gd). Only the statics are
## exercised — own_recursive / is_owned_recursive / owned_count touch nothing but a plain Node tree (no
## EditorInterface, no EditorUndoRedoManager, no viewport), so they run headless. The tab itself (scene_placer.gd)
## is editor glue (EditorInterface / get_edited_scene_root / the 3D viewport) and is NOT instantiated here — those
## classes are unavailable in a headless run and would crash the suite. The Items tab's recorded Place action
## (item_placer_dock._record_place) is replayed through a recorder standing in for the editor's undo manager.

const PlaceOps := preload("res://addons/cybersunday_tools/dock_place/place_ops.gd")
const ItemPlacer := preload("res://addons/cybersunday_tools/placer/item_placer_dock.gd")
## A tiny script-free prefab with one internal child (Node3D -> MeshInstance3D): the nested-instance case without
## running any gameplay _ready in the tree.
const NESTED_PREFAB := "res://scenes/props/grass.tscn"


## Stands in for the editor's EditorUndoRedoManager, which cannot exist headless: records what the Items tab registers
## and replays the do list on commit (and the undo list on undo) in registration order, as the editor does.
class UndoRecorder extends RefCounted:
	var actions := PackedStringArray()
	var commits := 0
	var do_ops: Array = []
	var undo_ops: Array = []
	var do_references: Array = []

	func create_action(action_name: String) -> void:
		actions.append(action_name)

	func add_do_method(obj: Object, method: StringName, ...args: Array) -> void:
		do_ops.append({"obj": obj, "method": method, "args": args})

	func add_undo_method(obj: Object, method: StringName, ...args: Array) -> void:
		undo_ops.append({"obj": obj, "method": method, "args": args})

	func add_do_property(obj: Object, property: StringName, value: Variant) -> void:
		do_ops.append({"obj": obj, "property": property, "value": value})

	func add_do_reference(obj: Object) -> void:
		do_references.append(obj)

	func commit_action() -> void:
		commits += 1
		_replay(do_ops)

	func undo() -> void:
		_replay(undo_ops)

	func _replay(ops: Array) -> void:
		for op in ops:
			var target: Object = op["obj"]
			if op.has("method"):
				target.callv(op["method"], op["args"])
			else:
				target.set(op["property"], op["value"])


## A small built subtree: root -> a -> b, plus a sibling c under root. Mirrors what a placed prefab's own internal
## (non-instanced) nodes look like before own_recursive runs. Caller frees the returned root.
func _build_tree() -> Node:
	var root := Node.new()
	root.name = "Root"
	var a := Node.new()
	a.name = "A"
	var b := Node.new()
	b.name = "B"
	var c := Node.new()
	c.name = "C"
	root.add_child(a)
	a.add_child(b)
	root.add_child(c)
	return root


func test_own_recursive_sets_owner_on_whole_subtree() -> void:
	var scene_root := Node.new()
	scene_root.name = "SceneRoot"
	var sub := _build_tree()
	scene_root.add_child(sub)
	PlaceOps.own_recursive(sub, scene_root)
	assert_eq(sub.owner, scene_root, "the placed subtree root must be owned by the scene root so it saves")
	for child in sub.get_children():
		assert_eq(child.owner, scene_root, "every descendant must be owned by the scene root (node %s)" % child.name)
	var deep := sub.get_node("A").get_node("B")
	assert_eq(deep.owner, scene_root, "a deep grandchild must also be owned (recursion reached it)")
	scene_root.free()


func test_is_owned_recursive_true_after_own_recursive() -> void:
	var scene_root := Node.new()
	var sub := _build_tree()
	scene_root.add_child(sub)
	PlaceOps.own_recursive(sub, scene_root)
	assert_true(PlaceOps.is_owned_recursive(sub, scene_root), "is_owned_recursive should confirm the post-condition own_recursive establishes")
	scene_root.free()


func test_is_owned_recursive_false_when_unowned() -> void:
	var scene_root := Node.new()
	var sub := _build_tree()
	scene_root.add_child(sub)
	# No own_recursive call: owners are still null, so the check must fail.
	assert_false(PlaceOps.is_owned_recursive(sub, scene_root), "a freshly-added subtree with null owners is not owned yet")
	scene_root.free()


func test_owned_count_counts_full_built_subtree() -> void:
	var sub := _build_tree()  # Root + A + B + C = 4 nodes
	assert_eq(PlaceOps.owned_count(sub), 4, "owned_count should count every node in a fully-built (non-instanced) subtree")
	sub.free()


func test_owned_count_of_single_node_is_one() -> void:
	var n := Node.new()
	assert_eq(PlaceOps.owned_count(n), 1, "a lone node counts as one")
	n.free()


func test_own_recursive_nulls_are_safe() -> void:
	# Defensive: the editor glue can hand a null node/root if a scene isn't open — must not crash.
	PlaceOps.own_recursive(null, null)
	var root := Node.new()
	PlaceOps.own_recursive(null, root)
	PlaceOps.own_recursive(root, null)
	assert_eq(root.owner, null, "own_recursive(node, null) must not set an owner")
	assert_eq(PlaceOps.owned_count(null), 0, "owned_count(null) should be 0, not a crash")
	assert_false(PlaceOps.is_owned_recursive(null, root), "is_owned_recursive with a null node must be false")
	root.free()


func test_own_recursive_does_not_explode_an_instanced_top_node() -> void:
	# REGRESSION: the Place tab hands own_recursive whole instanced PREFABS (NPC / Door / Container). It must own
	# only the prefab ROOT (so it saves as a clean instance) and leave the prefab's INTERNALS to the instance —
	# NOT re-own them to the level root. Re-owning explodes the instance into editable-children overrides and, for
	# an NPC, bakes BodyModelSwap's @tool live-preview limbs into the .tscn (the "white static body underneath the
	# real one, no animation, no outline" bug). Container.tscn is a light prefab with one internal child.
	var scene_root := Node.new()
	var ps := load("res://scenes/components/container.tscn") as PackedScene
	assert_not_null(ps, "container.tscn should load as a PackedScene for the instanced-top-node case")
	var inst := ps.instantiate()
	scene_root.add_child(inst)
	assert_ne(inst.scene_file_path, "", "the placed prefab root carries a non-empty scene_file_path (it's an instance)")
	assert_false(inst.get_children().is_empty(), "the fixture must have an internal child to prove recursion stops")
	var child: Node = inst.get_child(0)
	var child_owner_before: Object = child.owner  # the instance root owns its own internals after instantiate()
	PlaceOps.own_recursive(inst, scene_root)
	assert_eq(inst.owner, scene_root, "the placed instance ROOT must be owned by the level root so it saves")
	assert_eq(child.owner, child_owner_before, "an instanced prefab's INTERNALS must NOT be re-owned by the level root")
	assert_ne(child.owner, scene_root, "re-owning internals to the level root is the regression that bakes editable-children overrides + @tool preview duplicates")
	scene_root.free()


func test_item_placer_place_action_owns_the_pickup_for_save_and_undo_takes_it_back() -> void:
	# PL1: the Items tab's Place Selected must record ONE undoable action that parents the pickup, owns its whole
	# subtree to the scene root through PlaceOps.own_recursive (so it saves, while a nested prefab keeps its own
	# internals -- the corruption a hand-copied twin once reintroduced), and drops it at the camera point. The editor's
	# EditorUndoRedoManager cannot exist headless, so a recorder replays the action exactly as the editor would.
	var level := Node3D.new()
	level.name = "Level"
	add_child_autofree(level)  # in the tree: the recorded global_position write needs a real transform chain
	var props := Node3D.new()
	props.name = "Props"
	level.add_child(props)
	props.owner = level
	# The pickup a designer places: a BUILT root with a built child, carrying a nested instanced prefab.
	var pickup := Node3D.new()
	pickup.name = "Pickup"
	var visual := Node3D.new()
	visual.name = "Visual"
	pickup.add_child(visual)
	var prefab := (load(NESTED_PREFAB) as PackedScene).instantiate()
	pickup.add_child(prefab)
	assert_ne(prefab.scene_file_path, "", "fixture: the nested prop is an instanced prefab")
	assert_false(prefab.get_children().is_empty(), "fixture: the nested prefab has an internal child whose owner must survive")
	var internal: Node = prefab.get_child(0)
	var internal_owner: Node = internal.owner
	var drop := Vector3(4.0, 1.5, -2.0)
	var ur := UndoRecorder.new()
	ItemPlacer._record_place(ur, "Crate", props, pickup, level, drop)
	assert_eq(ur.actions, PackedStringArray(["Place Crate"]), "one undo entry per placement, named for the item")
	assert_eq(ur.commits, 1, "the action is committed once, so the pickup appears the moment Place Selected is pressed")
	assert_eq(pickup.get_parent(), props, "the pickup lands under the chosen parent")
	assert_eq(pickup.owner, level, "the pickup root is owned by the scene root, or saving the scene silently drops it")
	assert_eq(visual.owner, level, "a built child is owned too -- an unowned child vanishes from the saved .tscn")
	assert_eq(prefab.owner, level, "a nested prefab is owned at its root so the instance itself saves")
	assert_eq(internal.owner, internal_owner, "the nested prefab's INTERNALS keep their instance owner -- re-owning them bakes editable-children overrides into the level")
	assert_eq(pickup.global_position, drop, "the pickup is dropped at the camera focus point, not the world origin")
	assert_true(ur.do_references.has(pickup), "the placed node is registered as a do reference, so an undone placement is freed when its redo is discarded instead of leaking an orphan node")
	# What the designer actually saves: pack the scene and reload it.
	var saved := PackedScene.new()
	assert_eq(saved.pack(level), OK, "the placed scene packs")
	var reloaded := saved.instantiate()
	assert_true(reloaded.get_node_or_null("Props/Pickup") != null, "the placed pickup survives a save + reload")
	assert_true(reloaded.get_node_or_null("Props/Pickup/Visual") != null, "its built child survives too")
	var reloaded_prefab := reloaded.get_node_or_null("Props/Pickup/%s" % prefab.name)
	assert_true(reloaded_prefab != null, "the nested prefab instance survives")
	if reloaded_prefab != null:
		assert_eq(reloaded_prefab.get_child_count(), prefab.get_child_count(), "and it reloads with exactly its own internals -- no duplicated preview parts")
	reloaded.free()
	saved = null
	ur.undo()
	assert_null(pickup.get_parent(), "Ctrl+Z removes the pickup from the scene again")
	assert_eq(props.get_child_count(), 0, "and leaves nothing behind under the parent")
	pickup.free()  # detached by the undo; the recorder only held a reference, as the editor's history does


func test_owned_count_stops_at_instanced_subscene() -> void:
	# A child that is itself an instanced sub-scene (scene_file_path != "") is counted but NOT descended into — its
	# internals belong to the instance, exactly as own_recursive treats it. The fixture must HAVE internals, or
	# stopping and descending give the same count: NESTED_PREFAB is a Node3D root with a MeshInstance3D inside it.
	var scene_root := Node.new()
	var holder := Node.new()
	holder.name = "Holder"
	scene_root.add_child(holder)
	var ps := load(NESTED_PREFAB) as PackedScene
	assert_true(ps != null, "%s should load as a PackedScene for the instanced-child case" % NESTED_PREFAB)
	if ps == null:
		scene_root.free()
		return
	var inst := ps.instantiate()
	holder.add_child(inst)
	assert_ne(inst.scene_file_path, "", "an instanced sub-scene root should carry a non-empty scene_file_path")
	var internals := inst.get_child_count()
	assert_gt(internals, 0, "precondition: the instance has internal children, so a descent into it would change the count")
	# CONTROL: the same internals ARE counted when the walk starts at the instance itself (its children are plain,
	# non-instanced nodes) — the count below is not low merely because the walk never sees them.
	assert_eq(PlaceOps.owned_count(inst), 1 + internals, "counting from the instance root walks its own internals")
	# Holder (1) + the instanced child (1, not descended) = 2.
	assert_eq(PlaceOps.owned_count(holder), 2, "owned_count must stop at an instanced sub-scene (count it, don't recurse into its %d internal node(s))" % internals)
	scene_root.free()
