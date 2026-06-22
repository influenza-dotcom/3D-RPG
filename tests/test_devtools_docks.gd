extends GutTest

## Compile + construct smoke test for the editor-plugin docks. Instantiating each forces GDScript to compile the
## WHOLE script (catching errors that --import misses for addon-only scripts) and runs its _init UI build off-tree.
## The handlers are editor-only (EditorInterface) and are NOT exercised here.

const LevelDock := preload("res://addons/cybersunday_tools/dock_level/level_dock.gd")


func test_level_dock_constructs() -> void:
	var d = LevelDock.new()
	assert_not_null(d, "level dock should construct (compiles + _init builds its UI off-tree)")
	assert_eq(d.name, "Level", "dock tab name")
	d.free()
