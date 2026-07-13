extends GutTest
## F-C47 — the dialogue-suspend contract for the three dialogue-hostable sub-menus (Shop / ChipInstall / Chess).
##
## DialogueManager._suspend_for_menu hides the box, connects the sub-menu's `closed` as a CONNECT_ONE_SHOT resume,
## THEN calls the open. So EVERY refuse path in ShopScreen/ChipInstallScreen/ChessScreen MUST emit `closed`, or a
## dialogue-hosted open that hits a guard strands the conversation _suspended forever (box hidden, tree paused,
## no way to advance). Each screen routes its guard early-returns through `_refuse_open()` -> `closed.emit()`.
##
## We drive the invalid-node guard: a bare Node lacks each screen's duck-typed surface (Shop wants a `stock`
## CharacterInventory, Install wants install_carried(), Chess wants ai_search_depth()), so the open refuses with a
## null player. Assert the screen did NOT open AND `closed` fired. On the standalone path nothing listens to
## `closed`, so the emit is a harmless no-op there — this contract only matters for the dialogue-hosted open.
## Cannot build a real Player in a unit test (Player._ready forbidden), so we pass null and let the invalid-node
## guard fire first.

func before_each() -> void:
	# Autoloads start closed; guard against a screen leaked open by a prior test so is_open() reads true here.
	if ShopScreen.is_open():
		ShopScreen.close()
	if ChipInstallScreen.is_open():
		ChipInstallScreen.close()
	if ChessScreen.is_open():
		ChessScreen.close()

func test_shop_refuse_emits_closed() -> void:
	var bad := autofree(Node.new())  # lacks a `stock` CharacterInventory -> the invalid-merchant guard fires
	var flag := {"closed": false}
	ShopScreen.closed.connect(func() -> void: flag["closed"] = true, CONNECT_ONE_SHOT)
	ShopScreen.open_shop(bad, null)  # null player; a guard fires before we ever read it
	assert_false(ShopScreen.is_open(), "ShopScreen refuses an invalid merchant + null player")
	assert_true(flag["closed"], "the refuse path still emits `closed` (dialogue-suspend contract)")

func test_chip_install_refuse_emits_closed() -> void:
	var bad := autofree(Node.new())  # lacks install_carried() -> the not-an-installer guard fires
	var flag := {"closed": false}
	ChipInstallScreen.closed.connect(func() -> void: flag["closed"] = true, CONNECT_ONE_SHOT)
	ChipInstallScreen.open_install(bad, null)
	assert_false(ChipInstallScreen.is_open(), "ChipInstallScreen refuses an invalid installer + null player")
	assert_true(flag["closed"], "the refuse path still emits `closed` (dialogue-suspend contract)")

func test_chess_refuse_emits_closed() -> void:
	var bad := autofree(Node.new())  # lacks ai_search_depth() -> the not-a-match guard fires
	var flag := {"closed": false}
	ChessScreen.closed.connect(func() -> void: flag["closed"] = true, CONNECT_ONE_SHOT)
	ChessScreen.open_match(bad, null)
	assert_false(ChessScreen.is_open(), "ChessScreen refuses an invalid match + null player")
	assert_true(flag["closed"], "the refuse path still emits `closed` (dialogue-suspend contract)")
