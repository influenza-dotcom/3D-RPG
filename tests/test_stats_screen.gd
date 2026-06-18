extends GutTest
## Smoke tests for the StatsScreen autoload — it builds its UI at startup and stays closed/inert when there's
## no player present (the start-menu path; opening requires a real player + pauses the world in-game).

func after_each() -> void:
	if StatsScreen.is_open():
		StatsScreen.close()

func test_autoload_present_and_starts_closed() -> void:
	assert_not_null(StatsScreen, "StatsScreen autoload should be registered")
	assert_false(StatsScreen.is_open(), "starts closed")

func test_open_is_noop_without_a_player() -> void:
	# No node in the &"Player" group during a test -> open() must bail BEFORE pausing / showing (no crash).
	StatsScreen.open()
	assert_false(StatsScreen.is_open(), "open() with no player keeps the screen closed")
	assert_false(get_tree().paused, "and never leaves the tree paused without a player")
