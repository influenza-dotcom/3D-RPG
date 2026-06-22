extends GutTest

## Compile + construct smoke test for the editor-plugin docks. Instantiating each forces GDScript to compile the
## WHOLE script (catching errors that --import misses for addon-only scripts) and runs its _init UI build off-tree.
## The handlers are editor-only (EditorInterface) and are NOT exercised here.

const LevelDock := preload("res://addons/cybersunday_tools/dock_level/level_dock.gd")
const PaletteDock := preload("res://addons/cybersunday_tools/dock_palette/palette_dock.gd")
const Catalog := preload("res://addons/cybersunday_tools/core/catalog.gd")


func test_level_dock_constructs() -> void:
	var d = LevelDock.new()
	assert_not_null(d, "level dock should construct (compiles + _init builds its UI off-tree)")
	assert_eq(d.name, "Level", "dock tab name")
	d.free()


func test_palette_dock_constructs() -> void:
	var d = PaletteDock.new()
	assert_not_null(d, "palette dock should construct (compiles + builds its catalog tree off-tree)")
	assert_eq(d.name, "Palette", "dock tab name")
	d.free()


func test_palette_make_node_builds_a_child_mode_component() -> void:
	var pal = PaletteDock.new()
	var row := {}
	for r in Catalog.COMPONENTS:
		if str(r.get("add_mode", "")) == "child":
			row = r
			break
	assert_false(row.is_empty(), "catalog should hold at least one child-mode component")
	if not row.is_empty():
		var node = pal._make_node(row)
		assert_not_null(node, "child-mode _make_node should build a node for %s" % str(row.get("class_name", "?")))
		if node != null:
			assert_not_null(node.get_script(), "the built node carries its component script")
			node.free()
	pal.free()


func test_palette_make_node_null_on_empty_row() -> void:
	var pal = PaletteDock.new()
	assert_null(pal._make_node({}), "an empty row builds nothing (no crash, no load(''))")
	pal.free()
