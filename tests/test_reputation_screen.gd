extends GutTest
## Smoke tests for the ReputationScreen autoload — it builds its UI at startup and never pauses the world.
## F-C39: it now REFUSES to open when there's no human Player in-tree (start menu / character creation), matching
## Inventory/Stats — even though it reads the global Reputation, there's nothing to show without a player. The GUT
## scene has no Player, so its open() is a no-op here; the live open->close round-trip is playtest-verified (a real
## Player can't be add_child'd in a unit test — Player._ready is forbidden by CLAUDE.md).

func after_each() -> void:
	if ReputationScreen.is_open():
		ReputationScreen.close()

func test_autoload_present_and_starts_closed() -> void:
	assert_not_null(ReputationScreen, "ReputationScreen autoload should be registered")
	assert_false(ReputationScreen.is_open(), "starts closed")

func test_open_refused_without_a_player_and_never_pauses() -> void:
	# F-C39: no human player in-tree -> open() is refused (nothing to show), and it never pauses the world either way.
	ReputationScreen.open()
	assert_false(ReputationScreen.is_open(), "refuses to open with no human player (start menu / char-creation), like Inventory/Stats")
	assert_false(get_tree().paused, "the reputation screen never pauses the world")
	ReputationScreen.close()
	assert_false(ReputationScreen.is_open(), "stays closed")
	assert_false(get_tree().paused, "and leaves the tree unpaused")
