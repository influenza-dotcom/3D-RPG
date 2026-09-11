extends GutTest

## Scene-wiring contract for the door.tscn prefab: `pivot` (door.gd's @export Node3D) MUST resolve to the
## DoorPivot child, or open()/close() are silent no-ops. This is exactly the Inspector-wiring class of bug a pure
## script test can't catch — it instantiates the AUTHORED scene and checks the exported NodePath resolves live.

const DOOR_SCENE := "res://scenes/components/door.tscn"

func test_door_prefab_pivot_points_to_doorpivot() -> void:
	var scene: PackedScene = load(DOOR_SCENE)
	assert_not_null(scene, "door.tscn loads")
	if scene == null:
		return
	var door := scene.instantiate()
	add_child_autofree(door)  # in-tree so the exported NodePath resolves to the live DoorPivot node
	assert_not_null(door.pivot, "the prefab assigns `pivot` — open/close are no-ops without it")
	if door.pivot != null:
		assert_eq(door.pivot.name, &"DoorPivot", "`pivot` points at the DoorPivot child, not the Door root")
		assert_true(door.pivot is Node3D, "the pivot is a Node3D the door can swing")
	# #3: the placeholder DoorMesh must carry a material (or have shadows off) — a materialless authored mesh
	# spams the renderer with null-material errors. Catches a regression if the material is dropped on a re-save.
	var mesh_node := door.get_node_or_null(^"DoorPivot/DoorMesh") as MeshInstance3D
	assert_not_null(mesh_node, "door.tscn has a DoorPivot/DoorMesh")
	if mesh_node != null:
		var has_mat := mesh_node.material_override != null or mesh_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		assert_true(has_mat, "DoorMesh has a material_override (or shadows off) — no null-material renderer spam")


## Durability wiring: a shot lands on the BLOCKER body (DoorPivot/DoorBody), never on the Door root (an Area3D on the
## talk layer), so that body must carry door_panel.gd — its take_damage forwards to the Door and its
## blocks_melee_damage is what damage_trace consults for a swing. Drop the script and the door is silently
## unbreakable (door.gd's config warning says so in the editor; this pins it under GUT).
func test_door_prefab_blocker_forwards_hits_to_the_door() -> void:
	var scene: PackedScene = load(DOOR_SCENE)
	if scene == null:
		assert_not_null(scene, "door.tscn loads")
		return
	var door := scene.instantiate() as Door
	add_child_autofree(door)
	var body := door.get_node_or_null(^"DoorPivot/DoorBody")
	assert_not_null(body, "door.tscn has a DoorPivot/DoorBody blocker")
	if body == null:
		return
	assert_true(body is StaticBody3D, "the blocker is a StaticBody3D (what a world raycast / projectile hits)")
	assert_true(body.has_method(&"take_damage"), "DoorBody carries door_panel.gd: take_damage forwards to the Door")
	assert_true(body.has_method(&"blocks_melee_damage"), "DoorBody exposes the melee gate damage_trace consults")
	assert_eq(Door.of_collider(body), door, "of_collider resolves the prefab's blocker to its Door")
	assert_true(door._get_configuration_warnings().is_empty(), "the authored prefab raises no config warning (pivot set, panel takes damage)")
	# The forward is live: a hit on the body drains the DOOR's HP.
	door.max_hp = 10.0
	door.hp = 10.0
	body.call(&"take_damage", 4.0, false, null)
	assert_almost_eq(door.hp, 6.0, 0.001, "a hit on the blocker body reaches Door.take_damage")
	assert_true(DamageApplier.blocks_melee(body), "melee_can_damage is OFF by default: a swing is refused at the panel")
	door.melee_can_damage = true
	assert_false(DamageApplier.blocks_melee(body), "melee_can_damage ON lets a swing through")
