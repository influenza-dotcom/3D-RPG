extends GutTest

## B-F5/F57 invariant: SceneTree.node_added is a GLOBAL signal fired for EVERY node that enters the tree. Exactly
## TWO game subsystems connect to it — star_sky (sky FX when a WorldEnvironment enters) and menu_style (button SFX
## for BaseButtons under menu roots) — both with cheap early-outs. A THIRD listener taxes EVERY node instantiation
## project-wide, so adding one must be a deliberate, reviewed decision. This scans the game source (scripts/ +
## managers/, excluding addons/gut) and fails if the count drifts from 2. Pure text scan — off-tree, no _ready.

const ROOTS := ["res://scripts", "res://managers"]


func test_exactly_two_global_node_added_listeners() -> void:
	var hits := _scan_for("node_added.connect")
	assert_eq(hits.size(), 2, "exactly 2 game files connect get_tree().node_added (star_sky + menu_style) — found: %s" % str(hits))
	# Name-check the two so a swap (one removed, a different one added) is still caught.
	var names := []
	for h in hits:
		names.append((h as String).get_file())
	assert_true(names.has("star_sky.gd"), "star_sky.gd is one of the two node_added listeners")
	assert_true(names.has("menu_style.gd"), "menu_style.gd is one of the two node_added listeners")


## Every .gd under ROOTS whose text contains `needle`. Iterative dir walk (no recursion depth worries); skips the
## navigational entries. addons/ (GUT's own node_added use) is excluded by only scanning the game roots.
func _scan_for(needle: String) -> Array:
	var found: Array = []
	var dirs: Array = ROOTS.duplicate()
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.list_dir_begin()
		var entry := da.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				var path := d.path_join(entry)
				if da.current_is_dir():
					dirs.append(path)
				elif entry.ends_with(".gd"):
					if FileAccess.get_file_as_string(path).contains(needle):
						found.append(path)
			entry = da.get_next()
		da.list_dir_end()
	return found
