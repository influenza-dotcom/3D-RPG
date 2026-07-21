extends GutTest

## LevelData / GameRoot (Wave 2 #4, the level-loading seam). LevelData is a pure data resource; GameRoot
## instantiates its scene as the "Level" child. The load is tree-dependent (instantiate + add_child), so the
## GameRoot tests run IN-TREE (add_child_autofree) with a tiny packed dummy scene standing in for a real level.

func test_level_data_defaults() -> void:
	var d := LevelData.new()
	assert_null(d.scene, "a fresh LevelData has no scene")
	assert_eq(d.display_name, "", "no display name by default")
	assert_null(d.music, "no music override by default -> the scene's own autoplay is kept")
	assert_null(d.ambience, "no ambience override by default")
	d = null


## Pack a bare Node3D (named `root_name`) into a PackedScene — a stand-in level we can instantiate.
func _dummy_level(root_name: String) -> PackedScene:
	var content := Node3D.new()
	content.name = root_name
	var ps := PackedScene.new()
	assert_eq(ps.pack(content), OK, "the dummy level scene packs")
	content.free()
	return ps


func test_game_root_with_no_level_is_a_noop() -> void:
	# The incremental-adoption contract: attaching GameRoot without a LevelData changes nothing.
	var root := GameRoot.new()
	add_child_autofree(root)  # _ready runs with level == null
	assert_null(root.get_node_or_null(^"Level"), "no LevelData assigned -> no Level child is created")


func test_game_root_load_level_instantiates_the_scene_as_the_level_child() -> void:
	var data := LevelData.new()
	data.scene = _dummy_level("DummyLevel")
	var root := GameRoot.new()
	add_child_autofree(root)
	root.load_level(data)
	var level_node := root.get_node_or_null(^"Level")
	assert_not_null(level_node, "load_level instantiates the LevelData's scene as the 'Level' child")
	assert_eq(root.level, data, "load_level records the active LevelData")
	data = null


func test_game_root_load_level_replaces_the_previous_level() -> void:
	var root := GameRoot.new()
	add_child_autofree(root)
	var first := LevelData.new()
	first.scene = _dummy_level("First")
	root.load_level(first)
	var second := LevelData.new()
	second.scene = _dummy_level("Second")
	root.load_level(second)
	# Exactly one "Level" child — the swap frees the previous one rather than stacking levels.
	var levels := 0
	for c in root.get_children():
		if c.name == &"Level":
			levels += 1
	assert_eq(levels, 1, "swapping levels leaves exactly one 'Level' child (the old one is freed)")
	first = null
	second = null


func test_game_root_load_level_ignores_a_scene_less_data() -> void:
	var root := GameRoot.new()
	add_child_autofree(root)
	root.load_level(LevelData.new())  # no scene
	assert_null(root.get_node_or_null(^"Level"), "a LevelData with no packed scene is ignored (no Level child)")


## Pack a LevelRoot (class_name LevelRoot) as the scene root — the ACTUAL type GameRoot's PS1 hook gates on, unlike
## the bare-Node3D _dummy_level above (which cover() deliberately skips).
func _dummy_levelroot() -> PackedScene:
	var content := LevelRoot.new()
	content.name = "LevelRootDummy"
	var ps := PackedScene.new()
	assert_eq(ps.pack(content), OK, "the LevelRoot dummy scene packs")
	content.free()
	return ps


## The scoped PS1-warp hook (which replaced the old tree-wide node_added listener): loading a level whose root is a
## LevelRoot makes GameRoot.load_level drive Ps1Warp.cover(), parenting a "Ps1Warp" applier UNDER that level (so it's
## freed with the level on a swap) targeting the level itself. This is the POSITIVE half of the invariant —
## test_global_node_added_listeners pins the negative half (no game file connects the global node_added signal).
## Relies on the Ps1Warp autoload (present in the GUT run, resolved at /root/Ps1Warp) and GameRoot being in-tree.
func test_game_root_load_level_covers_a_levelroot_with_the_ps1_warp() -> void:
	var data := LevelData.new()
	data.scene = _dummy_levelroot()
	var root := GameRoot.new()
	add_child_autofree(root)
	root.load_level(data)
	var level_node := root.get_node_or_null(^"Level")
	assert_not_null(level_node, "the LevelRoot loaded as the 'Level' child")
	if level_node != null:
		assert_true(level_node is LevelRoot, "the loaded Level child is a LevelRoot (the type cover() gates on)")
		assert_true(level_node.has_meta(&"_ps1_warp_applied"), "cover() stamps the idempotency meta on the covered level")
		var applier := level_node.get_node_or_null(^"Ps1Warp")
		assert_not_null(applier, "GameRoot.load_level parents a 'Ps1Warp' applier under the LevelRoot (the scoped hook)")
		if applier != null:
			assert_eq(applier.get(&"target_root"), level_node, "the applier targets THIS level (not get_tree().current_scene)")
	data = null


## The shipped example LevelData (promoted from game.tscn's inline resource) is well-formed: it points at a real
## scene and carries a display name, so a designer has a working .tres to clone for a new level.
func test_example_testlevel_resource_is_well_formed() -> void:
	var d := load("res://resources/levels/TestLevel.tres") as LevelData
	assert_not_null(d, "resources/levels/TestLevel.tres loads as a LevelData")
	if d == null:
		return
	assert_not_null(d.scene, "...with a non-null scene (TestLevel.tscn)")
	assert_false(d.display_name.is_empty(), "...and a display_name for level-select / LevelDoor prompts")
	d = null
