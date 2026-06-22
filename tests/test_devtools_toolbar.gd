extends GutTest

## Play-from-spawn toolbar (step 9): the toolbar constructs (compile-check), and GameRoot's one-shot dev-start
## entry round-trips -- written once, returned once, then consumed (so it can't leak into a later normal play).
## The actual play launch + selection read are editor-only and user-verified.

const PlayToolbar := preload("res://addons/cybersunday_tools/toolbar/play_from_spawn.gd")


func test_toolbar_constructs() -> void:
	var t = PlayToolbar.new()
	assert_not_null(t, "the play-from-spawn toolbar should construct")
	assert_eq(t.name, "PlayFromSpawn")
	t.free()


func test_game_root_consumes_dev_start_entry_once() -> void:
	var gr := GameRoot.new()
	var f := FileAccess.open(GameRoot.DEV_START_FILE, FileAccess.WRITE)
	f.store_string("door_b")
	f = null
	assert_eq(String(gr._dev_start_entry()), "door_b", "reads the written dev-start entry")
	assert_eq(String(gr._dev_start_entry()), "", "consumed -> blank on the next start (no leak into normal play)")
	gr.free()
