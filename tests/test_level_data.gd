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
