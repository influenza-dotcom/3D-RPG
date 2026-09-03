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


## The button is greyed until a PlayerSpawn is selected, and the handler REFUSES rather than launching from the
## wrong place. Off-tree there is no editor selection at all (`_selected_spawn` returns null outside the editor),
## which is exactly the "nothing selected" case: it must write no dev-start note and leave any existing one alone.
func test_play_from_spawn_writes_nothing_without_a_selection() -> void:
	var t = PlayToolbar.new()
	assert_true(t._spawn_btn.disabled, "Play From Spawn starts greyed -- nothing is selected yet")
	assert_eq(t._spawn_btn.tooltip_text, PlayToolbar.SPAWN_TIP_DISABLED, "the greyed tooltip says what is missing")
	assert_eq(t._spawn_btn.text, "▶ Play From Spawn", "the button names the spawn it plays from")

	var had := FileAccess.file_exists(GameRoot.DEV_START_FILE)
	var before := FileAccess.get_file_as_string(GameRoot.DEV_START_FILE) if had else ""
	t._play_from_spawn()
	if had:
		assert_eq(FileAccess.get_file_as_string(GameRoot.DEV_START_FILE), before,
			"a refused Play From Spawn leaves an existing dev-start note untouched")
	else:
		assert_false(FileAccess.file_exists(GameRoot.DEV_START_FILE),
			"a refused Play From Spawn writes no dev-start note")
	t.free()
