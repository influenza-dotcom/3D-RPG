extends GutTest

## Pins the CYBER SUNDAY editor-plugin core/ data + helpers (the palette, item placer, level dock and audit
## panel all build on these). Pure logic -- no editor, no tree mutation beyond a throwaway Node graph.

const Catalog := preload("res://addons/cybersunday_tools/core/catalog.gd")
const GroupsReflect := preload("res://addons/cybersunday_tools/core/groups_reflect.gd")
const SceneWalk := preload("res://addons/cybersunday_tools/core/scene_walk.gd")


func test_catalog_is_populated() -> void:
	assert_gt(Catalog.COMPONENTS.size(), 0, "the component catalog should list components")


func test_every_catalog_script_path_resolves() -> void:
	for row in Catalog.COMPONENTS:
		var p: String = row.get("script_path", "")
		assert_true(ResourceLoader.exists(p), "catalog script_path should exist on disk: %s (%s)" % [p, row.get("class_name", "?")])


func test_catalog_scene_paths_resolve_when_set() -> void:
	for row in Catalog.COMPONENTS:
		var p: String = row.get("scene_path", "")
		if p != "":
			assert_true(ResourceLoader.exists(p), "catalog scene_path should exist on disk: %s (%s)" % [p, row.get("class_name", "?")])


func test_catalog_add_mode_is_child_or_instance() -> void:
	for row in Catalog.COMPONENTS:
		var m: String = row.get("add_mode", "")
		assert_true(m == "child" or m == "instance", "add_mode must be 'child' or 'instance', got '%s' for %s" % [m, row.get("class_name", "?")])


func test_catalog_rows_carry_a_category_and_name() -> void:
	for row in Catalog.COMPONENTS:
		assert_ne(String(row.get("class_name", "")), "", "every catalog row needs a class_name")
		assert_ne(String(row.get("category", "")), "", "every catalog row needs a category")


func test_groups_reflect_includes_player_excludes_dead_lowercase() -> void:
	var names := GroupsReflect.allowed_names()
	assert_true(names.has(&"Player"), "the canonical &\"Player\" group should be in the allowed set")
	assert_false(names.has(&"player"), "the dead lowercase &\"player\" group must NOT be a registered name")


func test_scene_walk_collect_all_visits_every_node() -> void:
	var root := Node.new()
	var a := Node.new()
	var b := Node.new()
	root.add_child(a)
	a.add_child(b)  # nested, so a flat children loop would miss it
	var all := SceneWalk.collect_all(root)
	assert_eq(all.size(), 3, "collect_all should visit root + every descendant")
	root.free()
