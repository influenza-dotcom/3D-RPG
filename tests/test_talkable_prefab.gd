extends GutTest

## Scene-wiring contract for talkable.tscn (Talkable) — the drop-in "this thing can be spoken to" component you
## instance under any node with a mesh. It works as a LOOK-AT target: an Area3D on the dedicated talk layer that
## the player's interaction ray (ray_cast.gd) detects when aimed. That requires a CollisionShape3D child and the
## talk-layer arming _ready performs — this pins both so a deleted collider or detached script can't slip past.
##
## In-tree (add_child_autofree) so _ready's talk-layer arming runs; Talkable._ready is harmless (sets layer/mask
## + builds an outline material; host meshes are gathered lazily on first highlight, not here).

const PREFAB := "res://scenes/components/talkable.tscn"


func test_prefab_root_is_a_talkable_area() -> void:
	var scene: PackedScene = load(PREFAB)
	assert_not_null(scene, "talkable.tscn loads")
	if scene == null:
		return
	var t := scene.instantiate()
	assert_true(t is Area3D, "the prefab root is an Area3D (the look-at hitbox)")
	assert_true(t is Talkable, "the root carries the Talkable script")
	t.free()


func test_prefab_has_a_collision_shape_child() -> void:
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "talkable.tscn loads")
		return
	var t := scene.instantiate()
	var shape: CollisionShape3D = null
	for c in t.get_children():
		if c is CollisionShape3D:
			shape = c as CollisionShape3D
			break
	assert_not_null(shape, "the prefab has a CollisionShape3D child (the body you aim at)")
	if shape != null:
		assert_not_null(shape.shape, "the CollisionShape3D carries a shape resource")
	t.free()


func test_ready_arms_the_hitbox_on_the_talk_layer() -> void:
	# The interaction ray only detects a Talkable that sits on the talk layer with a cleared mask — assert _ready
	# arms it, and that the duck-typed talk-handler surface ray_cast.gd relies on is intact.
	var scene: PackedScene = load(PREFAB)
	if scene == null:
		assert_not_null(scene, "talkable.tscn loads")
		return
	var t := scene.instantiate()
	add_child_autofree(t)
	assert_eq(t.collision_layer, TalkHelpers.TALK_LAYER, "armed on the talk layer so the ray can hit it")
	assert_eq(t.collision_mask, 0, "senses nothing itself (mask 0)")
	assert_true(t.has_method("start_talk"), "exposes start_talk (the interaction ray opens it)")
	assert_true(t.has_method("can_be_talked_to"), "exposes can_be_talked_to (the ray gates on it)")
	assert_true(t.has_method("set_look_highlight"), "exposes set_look_highlight (the look-at outline)")
