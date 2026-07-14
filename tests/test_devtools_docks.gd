extends GutTest

## Compile + construct smoke test for the editor-plugin docks. Instantiating each forces GDScript to compile the
## WHOLE script (catching errors that --import misses for addon-only scripts) and runs its _init UI build off-tree.
## The handlers are editor-only (EditorInterface) and are NOT exercised here.

const LevelDock := preload("res://addons/cybersunday_tools/dock_level/level_dock.gd")
const PaletteDock := preload("res://addons/cybersunday_tools/dock_palette/palette_dock.gd")
const ItemPlacer := preload("res://addons/cybersunday_tools/placer/item_placer_dock.gd")
const ArchView := preload("res://addons/cybersunday_tools/dock_arch/arch_view.gd")
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


func test_item_placer_constructs() -> void:
	var d = ItemPlacer.new()
	assert_not_null(d, "item placer should construct (compiles + scans items off-tree)")
	assert_eq(d.name, "Items", "dock tab name")
	d.free()


func test_item_placer_scans_authored_items() -> void:
	var items := ItemPlacer._scan_items()
	assert_gt(items.size(), 0, "resources/items/ should yield at least one Item")


func test_arch_view_constructs() -> void:
	# _init scans scripts/, managers/ + resources/ for @system annotations and builds its tree off-tree (read-only viewer).
	var d = ArchView.new()
	assert_not_null(d, "architecture view should construct (compiles + scans annotations off-tree)")
	assert_eq(d.name, "Architecture", "dock tab name")
	d.free()


func test_item_placer_make_pickup_is_a_throwable_dual_item() -> void:
	var pl = ItemPlacer.new()
	var it := Item.new()
	var node = pl._make_pickup(it)
	assert_not_null(node, "builds a dual item for the item")
	if node != null:
		assert_true(node is RigidBody3D, "the placed item is a physics Throwable (RigidBody3D root) -- carry/throw with Z")
		var pickup = node.get_node_or_null(^"CanPickUp")
		assert_not_null(pickup, "has a CanPickUp child so E can loot it")
		if pickup != null:
			assert_eq(pickup.get(&"item"), it, "the CanPickUp grants the placed item")
			assert_false(bool(pickup.get(&"build_model_from_item")), "the visual is authored, not runtime-built")
		node.free()
	pl.free()
