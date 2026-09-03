extends GutTest

## Compile + construct smoke test for the editor-plugin docks. Instantiating each forces GDScript to compile the
## WHOLE script (catching errors that --import misses for addon-only scripts) and runs its _init UI build off-tree.
## The handlers are editor-only (EditorInterface) and are NOT exercised here.
##
## Two things ARE exercised, because both are pure decisions the editor glue merely feeds:
##   * the SIBLING RULE (_parent_for) each of the three Build-group placers implements -- placing selects what it
##     placed, so without the rule a second press nests the new node INSIDE the first (component inside component,
##     pickup inside pickup, wall inside floor). Nothing but a test can see this; the editor path is unreachable
##     headless. The tests drive _parent_for with the same inputs _on_add / _place / _finish_place hand it.
##   * a DISABLED-STATE gate. Note the trap it is written around: assigning a widget's value (LineEdit.text,
##     Range.value, OptionButton.selected) does NOT emit its changed signal off-tree, so a test that only assigns
##     and then expects a write-through handler to have run is asserting nothing. Drive the signal.

const LevelDock := preload("res://addons/cybersunday_tools/dock_level/level_dock.gd")
const PaletteDock := preload("res://addons/cybersunday_tools/dock_palette/palette_dock.gd")
const ItemPlacer := preload("res://addons/cybersunday_tools/placer/item_placer_dock.gd")
const ScenePlacer := preload("res://addons/cybersunday_tools/dock_place/scene_placer.gd")
const ArchView := preload("res://addons/cybersunday_tools/dock_arch/arch_view.gd")
const Catalog := preload("res://addons/cybersunday_tools/core/catalog.gd")


## root -> host -> first: `first` stands for the node a placer just added and auto-selected; `host` is the node the
## designer actually had selected. Caller frees the returned root (which owns the other two).
func _sibling_fixture() -> Dictionary:
	var root := Node.new()
	root.name = "SceneRoot"
	var host := Node.new()
	host.name = "Host"
	root.add_child(host)
	var first := Node.new()
	first.name = "First"
	host.add_child(first)
	return {"root": root, "host": host, "first": first}


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


func test_palette_second_add_lands_beside_the_first_not_inside_it() -> void:
	# SIBLING RULE: Add selects what it added (so the Inspector shows the new component's fields), which means the
	# NEXT Add sees that component as the Scene-tree selection. Parenting to it would bury a QuestStarter inside a
	# Talkable instead of adding both to the same host -- never what "add two components to this node" means.
	var pal = PaletteDock.new()
	var f := _sibling_fixture()
	var root: Node = f["root"]
	var host: Node = f["host"]
	var first: Node = f["first"]
	pal._last_added = first
	assert_eq(pal._parent_for(first, root), host, "adding again on the just-added component lands BESIDE it, under the same host")
	assert_eq(pal._parent_for(host, root), host, "any other selection is a deliberate parent and is honoured")
	assert_eq(pal._parent_for(null, root), root, "nothing selected -> the scene root")
	pal._last_added = null
	assert_eq(pal._parent_for(first, root), first, "with nothing remembered the selection is taken at face value")
	root.free()
	pal.free()


func test_item_placer_constructs() -> void:
	var d = ItemPlacer.new()
	assert_not_null(d, "item placer should construct (compiles + scans items off-tree)")
	assert_eq(d.name, "Items", "dock tab name")
	d.free()


func test_item_placer_scans_authored_items() -> void:
	var items := ItemPlacer._scan_items()
	assert_gt(items.size(), 0, "resources/items/ should yield at least one Item")


func test_item_placer_second_place_lands_beside_the_first_not_inside_it() -> void:
	# Same SIBLING RULE, item-placer flavour: without it a second Place Selected parents a RigidBody3D pickup inside
	# the physics body of the one just dropped. `sel` is the editor selection, so the empty case is "nothing picked".
	var pl = ItemPlacer.new()
	var f := _sibling_fixture()
	var root: Node = f["root"]
	var host: Node = f["host"]
	var first: Node = f["first"]
	pl._last_placed = first
	var on_the_new_one: Array[Node] = [first]
	var on_the_host: Array[Node] = [host]
	var nothing: Array[Node] = []
	assert_eq(pl._parent_for(on_the_new_one, root), host, "placing again on the just-placed pickup lands BESIDE it, under the same host")
	assert_eq(pl._parent_for(on_the_host, root), host, "any other selection is a deliberate parent and is honoured")
	assert_eq(pl._parent_for(nothing, root), root, "nothing selected -> the scene root")
	root.free()
	pl.free()


func test_scene_placer_constructs() -> void:
	# The Control `name` is how cyber_panel routes to this tab (open_in_editor sends every NpcData to "Place"), so it
	# is pinned here even though the tab's own handlers are editor-only.
	var d = ScenePlacer.new()
	assert_not_null(d, "place tab should construct (compiles + builds its buttons off-tree)")
	assert_eq(d.name, "Place", "dock tab name")
	d.free()


func test_scene_placer_second_place_lands_beside_the_first_not_inside_it() -> void:
	# Same SIBLING RULE again, for the tab that tiles blockout geometry: Floor / Floor / Wall with the previous piece
	# still selected must line the pieces up as siblings, not nest wall inside floor. _remember_placement is what
	# _finish_place calls after the undo action commits.
	var sp = ScenePlacer.new()
	var f := _sibling_fixture()
	var root: Node = f["root"]
	var host: Node = f["host"]
	var first: Node = f["first"]
	sp._remember_placement(first)
	assert_eq(sp._parent_for(first, root), host, "placing again on the just-placed piece lands BESIDE it, under the same host")
	assert_eq(sp._parent_for(host, root), host, "any other selection is a deliberate parent and is honoured")
	assert_eq(sp._parent_for(null, root), root, "nothing selected -> the scene root")
	root.free()
	sp.free()


func test_level_dock_new_level_button_gates_on_a_typed_name() -> void:
	# New Level cannot apply with an empty name box, so it starts greyed with a tooltip naming what is missing (the
	# handler still repeats the refusal in words, for the designer who never hovers). The signal is emitted by hand
	# on purpose: assigning LineEdit.text does NOT emit text_changed, so asserting on a bare assignment would pass
	# whatever the gate did.
	var d = LevelDock.new()
	assert_true(d._new_level_btn.disabled, "an empty name box greys New Level")
	assert_eq(d._new_level_btn.tooltip_text, LevelDock.MSG_NO_NAME, "the disabled tooltip says what is missing")
	d._name_edit.text = "Raider Camp"
	d._name_edit.text_changed.emit(d._name_edit.text)
	assert_false(d._new_level_btn.disabled, "a typed name lifts the gate")
	assert_eq(d._new_level_btn.tooltip_text, LevelDock.TIP_NEW_LEVEL, "and the button's real tooltip comes back")
	d.free()


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
