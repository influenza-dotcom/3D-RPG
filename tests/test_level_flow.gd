extends GutTest

## P2 (level flow): the drop-in components + GameRoot's no-arg / null-load surface. Pure / off-tree: PlayerSpawn
## and LevelDoor are inspected via .new() (no _ready), and GameRoot's load_level(null) is a guarded no-op needing
## no tree. The actual level swap + teleport drive the tree and a real LevelData, so they're playtest-verified.

func test_player_spawn_defaults_and_place() -> void:
	var ps := PlayerSpawn.new()
	assert_eq(ps.entry_id, &"", "entry_id defaults empty (the level's default arrival)")
	add_child_autofree(ps)  # in-tree: a Node3D's global_transform is invalid (errors + identity) off-tree
	ps.global_position = Vector3(5, 0, 3)
	ps.global_rotation = Vector3(0, 1.2, 0)
	var p := Node3D.new()
	add_child_autofree(p)
	ps.place(p)
	assert_eq(p.global_position, Vector3(5, 0, 3), "place() moves the player to the spawn position")
	assert_almost_eq(p.rotation.y, 1.2, 0.001, "place() faces the player along the spawn yaw")

func test_level_door_defaults() -> void:
	var d := LevelDoor.new()
	assert_null(d.target_level, "target_level defaults null")
	assert_eq(d.entry_id, &"", "entry_id defaults empty")
	assert_false(d.can_be_talked_to(), "a LevelDoor with no target_level isn't usable")
	assert_eq(d.look_name(), "Enter", "look_name falls back to 'Enter' with no target")
	d.free()

func test_game_root_surface_and_null_load_noop() -> void:
	var gr = load("res://scripts/world/game_root.gd").new()
	assert_true(gr.has_method("load_assigned_level"), "GameRoot exposes a no-arg load_assigned_level for triggers")
	assert_true(gr.has_method("load_level"), "GameRoot exposes load_level(data, entry_id)")
	gr.load_level(null)  # null data -> guarded no-op, no crash (off-tree)
	assert_null(gr.get_node_or_null(^"Level"), "load_level(null) adds no Level child")
	gr.free()
