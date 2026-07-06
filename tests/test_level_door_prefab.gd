extends GutTest

## B-F61: LevelDoor is a drop-in PORTAL prefab (scenes/components/level_door.tscn). Its runtime door-to-door TRAVEL is
## DORMANT by design — no door is placed in a shipping level; the LIVE level-flow seam is GameRoot boot + PlayerSpawn
## placement. This pins the prefab's WIRING contract so the dormant prefab can't silently rot: an Area3D root carrying
## the LevelDoor script with a CollisionShape3D child, and the talk-gate keyed on target_level. Off-tree — the prefab
## is instantiated WITHOUT add_child (so _ready never runs), and the bare door via .new() (the test_level_flow idiom).

const PREFAB := "res://scenes/components/level_door.tscn"


func test_prefab_wiring() -> void:
	var scene: PackedScene = load(PREFAB)
	assert_not_null(scene, "the LevelDoor prefab loads")
	if scene == null:
		return
	var door = scene.instantiate()  # NOT add_child'd -> _ready does not run (no talk-layer/outline side effects)
	assert_true(door is Area3D, "the prefab root is an Area3D (the talk-layer hitbox PickupRay detects)")
	assert_true(door is LevelDoor, "the root carries the LevelDoor script")
	var has_shape := false
	for c in door.get_children():
		if c is CollisionShape3D:
			has_shape = true
			break
	assert_true(has_shape, "the prefab has a CollisionShape3D child (the interaction volume)")
	door.free()


func test_talk_gate_keys_on_target_level() -> void:
	var door := LevelDoor.new()  # bare, no _ready
	assert_false(door.can_be_talked_to(), "a LevelDoor with no target_level can't be talked to (inert until wired)")
	door.target_level = LevelData.new()
	assert_true(door.can_be_talked_to(), "assigning a target_level makes the door talkable")
	door.free()
