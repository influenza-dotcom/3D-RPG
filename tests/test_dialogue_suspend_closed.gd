extends GutTest
## F-C47 — the dialogue-suspend contract for the dialogue-hostable sub-menus (Shop / ChipInstall / WeaponBench /
## Chess / Atm / Heal / LevelUp / the LootScreen's gear EXCHANGE).
##
## DialogueManager._suspend_for_menu hides the box, connects the sub-menu's `closed` as a CONNECT_ONE_SHOT resume,
## THEN calls the open. So EVERY refuse path in ShopScreen/ChipInstallScreen/WeaponBenchScreen/ChessScreen/
## AtmScreen/HealScreen/LevelUpScreen/LootScreen MUST emit `closed`, or a dialogue-hosted open that hits a guard
## strands the conversation _suspended forever (box hidden, tree paused, no way to advance). Each screen routes
## its guard early-returns through `closed.emit()`.
##
## We drive the invalid-node guard: a bare Node lacks each screen's duck-typed surface (Shop wants a `stock`
## CharacterInventory, Install wants install_carried(), the bench wants fit_mod(), Chess wants ai_search_depth(),
## the loot exchange wants an `inventory` CharacterInventory), so the open refuses with a null player. Assert the
## screen did NOT open AND `closed` fired. On the standalone path nothing listens to `closed`, so the emit is a
## harmless no-op there — this contract only matters for the dialogue-hosted open.
## Cannot build a real Player in a unit test (Player._ready forbidden), so we pass null and let the invalid-node
## guard fire first. (AtmScreen/HealScreen/LevelUpScreen have no duck-typed station guard at all — a bare Node
## passes is_instance_valid — so there it is the NULL PLAYER that refuses, which is exactly the path a
## dead/missing player takes at runtime.)

func before_each() -> void:
	# Autoloads start closed; guard against a screen leaked open by a prior test so is_open() reads true here.
	if ShopScreen.is_open():
		ShopScreen.close()
	if ChipInstallScreen.is_open():
		ChipInstallScreen.close()
	if WeaponBenchScreen.is_open():
		WeaponBenchScreen.close()
	if ChessScreen.is_open():
		ChessScreen.close()
	if AtmScreen.is_open():
		AtmScreen.close()
	if HealScreen.is_open():
		HealScreen.close()
	if LevelUpScreen.is_open():
		LevelUpScreen.close()
	if LootScreen.is_open():
		LootScreen.close()

func test_shop_refuse_emits_closed() -> void:
	var bad: Node = Node.new()  # lacks a `stock` CharacterInventory -> the invalid-merchant guard fires
	autofree(bad)
	var flag := {"closed": false}
	ShopScreen.closed.connect(func() -> void: flag["closed"] = true, CONNECT_ONE_SHOT)
	ShopScreen.open_shop(bad, null)  # null player; a guard fires before we ever read it
	assert_false(ShopScreen.is_open(), "ShopScreen refuses an invalid merchant + null player")
	assert_true(flag["closed"], "the refuse path still emits `closed` (dialogue-suspend contract)")

func test_chip_install_refuse_emits_closed() -> void:
	var bad: Node = Node.new()  # lacks install_carried() -> the not-an-installer guard fires
	autofree(bad)
	var flag := {"closed": false}
	ChipInstallScreen.closed.connect(func() -> void: flag["closed"] = true, CONNECT_ONE_SHOT)
	ChipInstallScreen.open_install(bad, null)
	assert_false(ChipInstallScreen.is_open(), "ChipInstallScreen refuses an invalid installer + null player")
	assert_true(flag["closed"], "the refuse path still emits `closed` (dialogue-suspend contract)")

func test_weapon_bench_refuse_emits_closed() -> void:
	# The gunsmith bench is the newest dialogue-hosted station (the "Modify" option on a WeaponBench-bearing
	# speaker). A bare Node lacks fit_mod() -> the not-a-bench guard fires, before the null player is ever read.
	# Its refuse path routes through _refuse_open(), whose ONLY job is this emit.
	var bad: Node = Node.new()
	autofree(bad)
	var flag := {"closed": false}
	WeaponBenchScreen.closed.connect(func() -> void: flag["closed"] = true, CONNECT_ONE_SHOT)
	WeaponBenchScreen.open_bench(bad, null)
	assert_false(WeaponBenchScreen.is_open(), "WeaponBenchScreen refuses an invalid bench + null player")
	assert_true(flag["closed"], "the refuse path still emits `closed` (dialogue-suspend contract)")

func test_chess_refuse_emits_closed() -> void:
	var bad: Node = Node.new()  # lacks ai_search_depth() -> the not-a-match guard fires
	autofree(bad)
	var flag := {"closed": false}
	ChessScreen.closed.connect(func() -> void: flag["closed"] = true, CONNECT_ONE_SHOT)
	ChessScreen.open_match(bad, null)
	assert_false(ChessScreen.is_open(), "ChessScreen refuses an invalid match + null player")
	assert_true(flag["closed"], "the refuse path still emits `closed` (dialogue-suspend contract)")

func test_atm_refuse_emits_closed() -> void:
	var bad: Node = Node.new()  # a valid Node, so it is the null PLAYER that refuses this open
	autofree(bad)
	var flag := {"closed": false}
	AtmScreen.closed.connect(func() -> void: flag["closed"] = true, CONNECT_ONE_SHOT)
	AtmScreen.open_atm(bad, null)
	assert_false(AtmScreen.is_open(), "AtmScreen refuses an open with no player")
	assert_true(flag["closed"], "the refuse path still emits `closed` (dialogue-suspend contract)")

func test_heal_refuse_emits_closed() -> void:
	var bad: Node = Node.new()  # a valid Node, so it is the null PLAYER that refuses this open
	autofree(bad)
	var flag := {"closed": false}
	HealScreen.closed.connect(func() -> void: flag["closed"] = true, CONNECT_ONE_SHOT)
	HealScreen.open_heal(bad, null)
	assert_false(HealScreen.is_open(), "HealScreen refuses an open with no player")
	assert_true(flag["closed"], "the refuse path still emits `closed` (dialogue-suspend contract)")

func test_level_up_refuse_emits_closed() -> void:
	var bad: Node = Node.new()  # a valid Node, so it is the null PLAYER that refuses this open
	autofree(bad)
	var flag := {"closed": false}
	LevelUpScreen.closed.connect(func() -> void: flag["closed"] = true, CONNECT_ONE_SHOT)
	LevelUpScreen.open_level_up(bad, null)
	assert_false(LevelUpScreen.is_open(), "LevelUpScreen refuses an open with no player")
	assert_true(flag["closed"], "the refuse path still emits `closed` (dialogue-suspend contract)")

func test_loot_exchange_refuse_emits_closed() -> void:
	# The LootScreen's only dialogue-hosted entry is the gear EXCHANGE (DialogueManager._on_exchange_pressed);
	# corpse loot / pickpocket / containers open standalone. A bare Node has no `inventory` CharacterInventory,
	# so the not-an-exchange-partner guard fires (before the shared _open, whose guards emit `closed` too).
	var bad: Node = Node.new()
	autofree(bad)
	var flag := {"closed": false}
	LootScreen.closed.connect(func() -> void: flag["closed"] = true, CONNECT_ONE_SHOT)
	LootScreen.exchange(bad, null)
	assert_false(LootScreen.is_open(), "LootScreen refuses an exchange with no partner inventory + null player")
	assert_true(flag["closed"], "the refuse path still emits `closed` (dialogue-suspend contract)")
