extends GutTest

## Unit tests for the CYBER SUNDAY "Place" tab's PURE subtree bookkeeping (place_ops.gd). Only the statics are
## exercised — own_recursive / is_owned_recursive / owned_count touch nothing but a plain Node tree (no
## EditorInterface, no EditorUndoRedoManager, no viewport), so they run headless. The tab itself (scene_placer.gd)
## is editor glue (EditorInterface / get_edited_scene_root / the 3D viewport) and is NOT instantiated here — those
## classes are unavailable in a headless run and would crash the suite.

const PlaceOps := preload("res://addons/cybersunday_tools/dock_place/place_ops.gd")


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


func test_item_placer_routes_through_place_ops_not_a_twin() -> void:
	# PL1: the item-placer dock must own the placed subtree through the ONE tested PlaceOps.own_recursive, NOT a
	# hand-copied _own_recursive twin (the re-divergence trap on this corruption-prone routine — the twin lacked the
	# null-guard and had no test). Source-scan so a future re-introduction of the twin fails here.
	var src := FileAccess.get_file_as_string("res://addons/cybersunday_tools/placer/item_placer_dock.gd")
	assert_ne(src, "", "item_placer_dock.gd source should be readable")
	assert_true(src.contains('add_do_method(PlaceOps, "own_recursive"'), "the placer must own the subtree via PlaceOps.own_recursive (the shared static)")
	assert_false(src.contains("func _own_recursive"), "the hand-copied _own_recursive twin must be gone (routed through PlaceOps instead)")


func test_owned_count_stops_at_instanced_subscene() -> void:
	# A child that is itself an instanced sub-scene (scene_file_path != "") is counted but NOT descended into — its
	# internals belong to the instance, exactly as own_recursive treats it. We can't set scene_file_path directly,
	# so load a real PackedScene instance whose own root carries a scene_file_path.
	var scene_root := Node.new()
	var holder := Node.new()
	holder.name = "Holder"
	scene_root.add_child(holder)
	var ps := load("res://scenes/world/PlayerSpawn.tscn") as PackedScene
	assert_not_null(ps, "PlayerSpawn.tscn should load as a PackedScene for the instanced-child case")
	var inst := ps.instantiate()
	holder.add_child(inst)
	assert_ne(inst.scene_file_path, "", "an instanced sub-scene root should carry a non-empty scene_file_path")
	# Holder (1) + the instanced child (1, not descended) = 2.
	assert_eq(PlaceOps.owned_count(holder), 2, "owned_count must stop at an instanced sub-scene (count it, don't recurse)")
	scene_root.free()
