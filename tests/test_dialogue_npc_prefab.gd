extends GutTest

## Scene-wiring contract for dialogue_npc.tscn (DialogueNPC) — a whole-node "talkable thing" (a car, terminal,
## sign, or NPC) with the script on the root and a child Area3D repurposed as the look-at hitbox. The `range_area`
## export is WIRED (node_paths) to that child Area3D; _ready arms it on the talk layer so the interaction ray can
## target the node. Without the wired range_area (+ its own CollisionShape3D) the node is silently un-interactable
## — the exact case _get_configuration_warnings flags in-editor, pinned here headlessly.
##
## In-tree (add_child_autofree) so the node_paths export resolves to the live child and _ready's talk-layer arming
## runs; DialogueNPC._ready is harmless (sets layer/mask + builds an outline material, no heavy instantiation).

const PREFAB := "res://scenes/components/dialogue_npc.tscn"


func test_range_area_export_resolves_and_is_armed_on_the_talk_layer() -> void:
	var scene: PackedScene = load(PREFAB)
	assert_not_null(scene, "dialogue_npc.tscn loads")
	if scene == null:
		return
	var dnpc := scene.instantiate()
	add_child_autofree(dnpc)  # in-tree so range_area resolves and _ready arms the hitbox
	assert_true(dnpc is Node3D, "the prefab root is a Node3D (the script attaches to the whole node)")
	assert_true(dnpc is DialogueNPC, "the root carries the DialogueNPC script")
	assert_not_null(dnpc.range_area, "`range_area` resolved — the look-at hitbox the interaction ray targets")
	assert_true(dnpc.range_area is Area3D, "range_area is an Area3D")
	assert_eq(dnpc.range_area, dnpc.get_node_or_null(^"RangeArea"), "range_area points at the authored RangeArea child")
	# _ready puts the hitbox on the talk layer (and clears its mask) so the ray can hit it.
	assert_eq(dnpc.range_area.collision_layer, TalkHelpers.TALK_LAYER, "the hitbox was armed on the talk layer")
	assert_eq(dnpc.range_area.collision_mask, 0, "the hitbox senses nothing itself (mask 0)")


func test_range_area_has_its_own_collision_shape() -> void:
	# The hitbox Area3D is only a hitbox with a shape — assert the authored CollisionShape3D under RangeArea.
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "dialogue_npc.tscn loads")
		return
	var dnpc := scene.instantiate()
	var range_area := dnpc.get_node_or_null(^"RangeArea")
	assert_not_null(range_area, "the prefab has a RangeArea child")
	var shape: CollisionShape3D = null
	if range_area != null:
		for c in range_area.get_children():
			if c is CollisionShape3D:
				shape = c as CollisionShape3D
				break
	assert_not_null(shape, "RangeArea has a CollisionShape3D child (the body you aim at)")
	if shape != null:
		assert_not_null(shape.shape, "the CollisionShape3D carries a shape resource")
	dnpc.free()


func test_prefab_has_a_visible_mesh_for_the_highlight() -> void:
	# The look-at outline needs a mesh to draw over — the prefab ships a MeshInstance3D placeholder body.
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "dialogue_npc.tscn loads")
		return
	var dnpc := scene.instantiate()
	var has_mesh := false
	for c in dnpc.get_children():
		if c is MeshInstance3D:
			has_mesh = true
			break
	assert_true(has_mesh, "the prefab has a MeshInstance3D child (the body the look-at outline draws over)")
	dnpc.free()
