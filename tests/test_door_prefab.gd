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
