extends GutTest

## B-F5/F57 invariant: SceneTree.node_added is a GLOBAL signal fired for EVERY node that enters the tree. THREE game
## subsystems connect to it — star_sky (sky FX when a WorldEnvironment enters), menu_style (button SFX for
## BaseButtons under menu roots) and view_model_camera (the light_reach stamp, so a light that arrives after the gun
## pass was built — a LevelDoor's next level, a spawned muzzle flash, a pooled NPC's laser — still reaches the view
## model) — all three with a cheap early-out as their first statement. A FOURTH listener taxes EVERY node
## instantiation project-wide, so adding one must be a deliberate, reviewed decision. This scans the game source
## (scripts/ + managers/, excluding addons/gut) and fails if the count drifts from 3. Pure text scan — off-tree, no _ready.
## (ps1_warp USED to be a third listener; it now uses a scoped hook — GameRoot calls Ps1Warp.cover() on level load,
## since GameRoot owns the level-load seam — so the PS1 warp costs zero per-node tax. Keep 2 as the ceiling.)

const ROOTS := ["res://scripts", "res://managers"]
## scripts/tools/ is out of scope, the same explicit exclusion tests/test_player_text.gd and
## tests/test_menu_sound_coverage.gd carry for the same reason: those are File→Run editor tools and
## throwaway `__` probes that the SHIPPED game never loads, so a listener in one taxes nothing. The tax this
## guard exists to price is per-node instantiation IN THE GAME (a probe deliberately connects node_added to
## name what was born on a compile frame — scripts/tools/probes/__first_kill_hitch_probe.gd does exactly that).
const EXCLUDED_DIRS := ["res://scripts/tools"]


func test_exactly_three_global_node_added_listeners() -> void:
	var hits := _scan_for("node_added.connect")
	assert_eq(hits.size(), 3, "exactly 3 game files connect get_tree().node_added (star_sky + menu_style + view_model_camera) — found: %s" % str(hits))
	# Name-check the three so a swap (one removed, a different one added) is still caught.
	var names := []
	for h in hits:
		names.append((h as String).get_file())
	assert_true(names.has("star_sky.gd"), "star_sky.gd is one of the node_added listeners")
	assert_true(names.has("menu_style.gd"), "menu_style.gd is one of the node_added listeners")
	assert_true(names.has("view_model_camera.gd"), "view_model_camera.gd is one of the node_added listeners (light_reach)")
	# Regression guard: ps1_warp moved to GameRoot's scoped cover() hook — it must NOT re-add a global listener.
	assert_false(names.has("ps1_warp.gd"), "ps1_warp.gd must NOT connect node_added — it uses GameRoot's scoped Ps1Warp.cover() hook now")


## Every .gd under ROOTS whose text contains `needle`. Iterative dir walk (no recursion depth worries); skips the
## navigational entries. addons/ (GUT's own node_added use) is excluded by only scanning the game roots;
## EXCLUDED_DIRS drops the one directory under those roots that ships nothing.
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
					if not EXCLUDED_DIRS.has(path):
						dirs.append(path)
				elif entry.ends_with(".gd"):
					if FileAccess.get_file_as_string(path).contains(needle):
						found.append(path)
			entry = da.get_next()
		da.list_dir_end()
	return found
