extends GutTest
## Smoke tests for the ReputationScreen autoload — it builds its UI at startup, and open/close round-trips
## without pausing. It needs no player (it reads the global Reputation + the Factions registry), so it can
## actually open in a test (unlike the player-bound StatsScreen).

func after_each() -> void:
	if ReputationScreen.is_open():
		ReputationScreen.close()

func test_autoload_present_and_starts_closed() -> void:
	assert_not_null(ReputationScreen, "ReputationScreen autoload should be registered")
	assert_false(ReputationScreen.is_open(), "starts closed")

func test_open_close_round_trips_without_pausing() -> void:
	ReputationScreen.open()
	assert_true(ReputationScreen.is_open(), "opens (reads global Reputation — no player required)")
	assert_false(get_tree().paused, "the reputation screen never pauses the world")
	ReputationScreen.close()
	assert_false(ReputationScreen.is_open(), "closes cleanly")
	assert_false(get_tree().paused, "and leaves the tree unpaused")
