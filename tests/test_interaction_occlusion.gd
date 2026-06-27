extends GutTest

## Wall line-of-sight on the look-at interaction ray — the "interact through walls" fix.
## PickupRay._query_talk_handler now casts a SECOND solid-body ray and rejects a talk hitbox sitting behind a wall,
## so pickup / talk / loot / doors can no longer be reached through solid geometry. Because EVERY look-at
## interactable (LookAtInteractable subclasses + Talkable + DialogueNPC) resolves through that one method, this one
## gate covers all of them; the tests below exercise it via CanPickUp as the representative talk-layer hitbox.
##
## These are IN-TREE physics tests: intersect_ray needs a populated space, so each builds a tiny world and awaits
## two physics frames for the bodies to register before querying (the in-tree-harness pattern this project uses for
## physics-touching logic). The MOST important case is the dual item: its OWN solid body must be excluded from the
## LOS ray, or a dropped weapon on open floor would self-occlude and never be pickable again.

const TALK_LAYER := 16  # mirror of TalkHelpers.TALK_LAYER (editor layer 5)

var _root: Node3D


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)


## A PickupRay at the world origin looking down -Z (identity basis). physics_process is OFF so the per-frame
## outline/readout pass doesn't run — we drive _query_talk_handler() directly.
func _make_ray() -> PickupRay:
	var ray := PickupRay.new()
	_root.add_child(ray)
	ray.global_transform = Transform3D.IDENTITY
	ray.set_physics_process(false)
	return ray


## A real CanPickUp talk-layer hitbox at `pos` with a `size`-cube collision shape, so the look-at ray can hit it.
## _ready() puts it on TALK_LAYER. Parented under `parent` (defaults to _root) so a dual item can nest it in a body.
func _make_pickup(pos: Vector3, size: float = 0.5, parent: Node = null) -> CanPickUp:
	var cp := CanPickUp.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, size, size)
	shape.shape = box
	cp.add_child(shape)
	(parent if parent != null else _root).add_child(cp)
	cp.global_position = pos
	return cp


## A solid wall (StaticBody3D on world layer 1) centred at `pos` — wide and thin on Z so it spans the camera ray.
func _make_wall(pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 0.2)
	shape.shape = box
	sb.add_child(shape)
	_root.add_child(sb)
	sb.global_position = pos
	return sb


func test_clear_line_of_sight_resolves_the_pickup() -> void:
	var ray := _make_ray()
	var cp := _make_pickup(Vector3(0, 0, -2))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(ray._query_talk_handler(), cp,
		"with nothing in the way the look-at ray resolves the pickup (the gate must not over-block)")


func test_wall_between_blocks_the_pickup() -> void:
	var ray := _make_ray()
	var _cp := _make_pickup(Vector3(0, 0, -2))
	_make_wall(Vector3(0, 0, -1))  # solid wall between the camera and the pickup
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_null(ray._query_talk_handler(),
		"a wall between the camera and the pickup occludes it — no interacting through walls")


func test_wall_behind_target_does_not_block() -> void:
	var ray := _make_ray()
	var cp := _make_pickup(Vector3(0, 0, -2))
	_make_wall(Vector3(0, 0, -3))  # wall BEHIND the target — not on the camera→target segment
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(ray._query_talk_handler(), cp,
		"a wall behind the target (a flush-mounted, player-facing pickup) doesn't block reaching it")


## THE regression lock: a talk hitbox sitting on a SOLID body deeper than the hitbox itself (a dropped item's
## Throwable, or any designer-tight 'use' box on a big crate). The body is on layer 1 — squarely in the occlusion
## ray's mask and IN FRONT of the talk hit — so without excluding the target's own body it would self-occlude and
## the prompt would vanish on open floor. The fix excludes it, so the pickup still resolves.
func test_target_own_body_does_not_self_occlude() -> void:
	var ray := _make_ray()
	var body := StaticBody3D.new()
	body.collision_layer = 1  # world/prop layer — the dropped item's Throwable lives here
	body.collision_mask = 0
	var bshape := CollisionShape3D.new()
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(0.8, 0.8, 0.8)  # DEEPER than the talk hitbox, so it protrudes toward the camera
	bshape.shape = bbox
	body.add_child(bshape)
	_root.add_child(body)
	body.global_position = Vector3(0, 0, -2)
	var cp := _make_pickup(Vector3(0, 0, -2), 0.4, body)  # smaller talk box, nested in the body (the dual-item shape)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(ray._query_talk_handler(), cp,
		"a dropped item's own body must be excluded from the LOS ray — E-stash still works on open floor")


## Structural unit (no physics): the exclusion collector finds the target's own body walking UP from the hitbox.
func test_self_exclusions_collect_parent_body() -> void:
	var ray := PickupRay.new()
	var body := StaticBody3D.new()
	var cp := CanPickUp.new()
	body.add_child(cp)  # CanPickUp nested under its solid body, like a dual item
	var rids := ray._target_body_exclusions(cp)
	assert_true(rids.has(body.get_rid()), "the parent solid body is gathered for exclusion")
	assert_true(rids.has(cp.get_rid()), "the hitbox itself is gathered (harmless — areas are off on the LOS ray)")
	cp.free()
	body.free()
	ray.free()
