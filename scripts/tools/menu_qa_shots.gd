extends Node
## Menu QA screenshot harness — boots the real game once and captures a PNG of EVERY menu screen
## at the true runtime canvas (792x444 at 16:9; stretch viewport + aspect=expand + scale 0.5).
## Doubles as the UI-ARTIST reference pack: every screen in the "Menus are scenes" roster gets a shot,
## so a reskin brief can ship the whole set (upscale the PNGs with NEAREST for a legible hand-off —
## the canvas is deliberately low-res, so a smooth upscale misrepresents the pixel look).
## Run from the project root (a real windowed run — NOT --headless, the GPU must render):
##   godot --path . res://scripts/tools/menu_qa_shots.tscn -- --shots-dir="C:/some/dir"
## Without --shots-dir it writes to user://qa_shots. Prints one QA_SHOT/QA_SKIP line per screen and
## quits when done (~30s). Context-gated screens are faked exactly like the GUT tests do: off-tree
## Merchant/Healer/LevelUp/RespecStation/LootableCorpse stubs + the LIVE player from scenes/game.tscn.
##
## Driver-copy pattern: this scene is the boot scene, but the run switches current_scene to
## start_menu/game.tscn (change_scene_to_file frees the current scene). So _ready re-attaches a COPY
## of this script on a bare Node parented to root — that copy survives every scene change and drives.

var _dir := "user://qa_shots"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		# We are the boot scene (doomed on the first scene change): spawn the detached driver copy.
		var d := Node.new()
		d.name = "MenuQaDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	# Windowed instead of the project's exclusive fullscreen so the run doesn't take over the desktop.
	# 1280x720 is 16:9, the same aspect as the user's monitor -> identical 792x444 canvas.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _frames(5)
	print("QA_CANVAS=", get_viewport().get_visible_rect().size)

	# --- Boot-flow screens (no player needed) --------------------------------------------------
	get_tree().change_scene_to_file("res://scenes/start_menu.tscn")
	await _frames(10)
	await _shot("01_start_menu")

	var cc: Control = (load("res://scenes/ui/character_creation.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(cc)
	await _frames(10)
	await _shot("02_char_create_stats")
	var tabs := cc.find_children("*", "TabContainer", true, false)
	if not tabs.is_empty():
		(tabs[0] as TabContainer).current_tab = 1
		await _frames(12)  # SubViewport preview needs frames to render
		await _shot("03_char_create_look")
	cc.queue_free()
	await _frames(2)

	if _try_open(OptionsMenu):
		var ot: TabContainer = OptionsMenu.get(&"_tabs")
		var tab_count: int = ot.get_tab_count() if ot != null else 1
		for i in tab_count:
			if ot != null:
				ot.current_tab = i
			await _frames(6)
			await _shot("04_options_tab%d" % i)
		OptionsMenu.close()
		await _frames(2)

	# The FIRST-LAUNCH TERMS gate (terms_of_service_screen.tscn — hosted by StartMenu, not an autoload,
	# so it is instantiated here the same way StartMenu does it rather than opened through a singleton).
	var tos: Control = (load("res://scenes/ui/terms_of_service_screen.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(tos)
	await _frames(8)
	await _shot("05_terms_of_service")
	tos.queue_free()
	await _frames(2)

	# SaveLoad in its BOOT flavour (in_game = false: the Load-only face the start menu shows).
	SaveLoadScreen.open(false, Callable())
	await _frames(8)
	await _shot("06_save_load")
	SaveLoadScreen.close()
	await _frames(2)

	NameEntryDialog.open("Name your dog", "Rex", Callable())
	await _frames(6)
	await _shot("07_name_entry")
	NameEntryDialog.close()
	await _frames(2)

	# --- In-game screens (need the live Player from game.tscn) ----------------------------------
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	var player: Node = null
	for i in 600:  # up to ~10s for the level + player to come up
		await get_tree().process_frame
		player = Groups.human_player(get_tree())
		if player != null:
			break
	if player == null:
		print("QA_SKIP no player after game.tscn load — in-game screens skipped")
		_finish()
		return
	await _frames(40)  # HUD/level settle

	# Seed the backpack so the grids aren't empty. Bag changes DO autosave on the live player (Player._ready
	# connects inventory.changed -> _on_inventory_autosave, which flushes GameState.autosave a frame later) —
	# so first UNPLUG that seam, or this QA run's seeded items (and the implants shot's ability grant below)
	# would be written into the user's real Continue profile while we await frames between shots.
	var inv = player.get(&"inventory")
	if inv != null:
		var autosave_cb := Callable(player, &"_on_inventory_autosave")
		if (inv.changed as Signal).is_connected(autosave_cb):
			(inv.changed as Signal).disconnect(autosave_cb)
	if inv != null:
		for id: StringName in [&"healthpack", &"ammo_pistol", &"rock"]:
			var it: Item = ItemDb.item_by_id(id)
			if it != null:
				inv.add(it, 3)

	if _try_open(InventoryScreen):
		await _frames(20)  # icon tiles bake over a few frames
		await _shot("08_inventory")
		InventoryScreen.close()
		await _frames(2)

	if _try_open(StatsScreen):
		await _frames(12)
		await _shot("09_stats")
		StatsScreen.close()
		await _frames(2)

	var m := Merchant.new()
	m.stock = CharacterInventory.new()
	for id: StringName in [&"pistol", &"healthpack", &"ammo_pistol", &"dog_crate"]:
		var it: Item = ItemDb.item_by_id(id)
		if it != null:
			m.stock.add(it, 2)
	m.set(&"money", 500.0)
	m.set(&"shop_name", "QA Trader")
	ShopScreen.open_shop(m, player)
	await _frames(8)
	await _shot("10_shop")
	ShopScreen.close()
	await _frames(2)
	m.free()

	if "hp" in player and "max_hp" in player:
		player.hp = float(player.max_hp) * 0.5  # so Heal shows a real cost, not "Fully healed"
	var h := Healer.new()
	HealScreen.open_heal(h, player)
	await _frames(6)
	await _shot("11_heal")
	HealScreen.close()
	await _frames(2)
	h.free()

	var lu := LevelUp.new()
	lu.set(&"station_name", "QA Station")
	var perks: Array = []
	for p in ["res://resources/perks/deadeye.tres", "res://resources/perks/tough_hide.tres"]:
		var r := load(p)
		if r != null:
			perks.append(r)
	lu.set(&"available_perks", perks)
	LevelUpScreen.open_level_up(lu, player)
	await _frames(8)
	await _shot("12_level_up")
	LevelUpScreen.close()
	await _frames(2)
	lu.free()

	var rs := RespecStation.new()
	rs.set(&"station_name", "QA Shrine")
	RespecScreen.open_respec(rs, player)
	await _frames(6)
	await _shot("13_respec")
	RespecScreen.close()
	await _frames(2)
	rs.free()

	var src := CharacterInventory.new()
	for id: StringName in [&"pistol", &"healthpack", &"ammo_pistol", &"rock"]:
		var it: Item = ItemDb.item_by_id(id)
		if it != null:
			src.add(it, 2)
	var corpse := LootableCorpse.new()
	corpse.setup(src, "Bandit", 35.0)
	LootScreen.open_for(corpse, player)
	await _frames(20)  # two grids of icon tiles
	await _shot("14_loot")
	LootScreen.close()
	await _frames(2)
	corpse.free()

	# --- The player-menu TAB FAMILY siblings + the remaining in-game modals ----------------------
	# Reputation / Journal live here rather than in the boot flow above: they are PlayerMenus group
	# screens whose open() refuses without a live player, so at the start menu they silently no-op'd.
	if _try_open(ReputationScreen):
		await _frames(8)
		await _shot("15_reputation")
		ReputationScreen.close()
		await _frames(2)

	if _try_open(QuestJournal):  # unseeded on purpose: no GameState mutations -> no autosave writes
		await _frames(8)
		await _shot("16_journal_empty")
		QuestJournal.close()
		await _frames(2)

	if _try_open(CharacterInspectScreen):
		await _frames(20)  # the 3D character showcase needs frames to render into its SubViewport
		await _shot("17_character_inspect")
		CharacterInspectScreen.close()
		await _frames(2)

	var ci := ChipInstaller.new()
	ci.set(&"installer_name", "QA Clinic")
	var chip_stock: Array[StockEntry] = []
	for p in ["res://resources/items/chip_grapple.tres", "res://resources/items/chip_takedown.tres",
			"res://resources/items/chip_air_dash.tres"]:
		var chip := load(p)
		if chip != null:
			var e := StockEntry.new()
			e.item = chip
			e.count = 1
			chip_stock.append(e)
	ci.set(&"stock_counts", chip_stock)
	ChipInstallScreen.open_install(ci, player)
	await _frames(8)
	await _shot("18_chip_install")
	ChipInstallScreen.close()
	await _frames(2)
	ci.free()

	# The board is the SIGHTED open: without the Board Visualizer chip the screen shows the blindfold
	# placeholder instead, which is both a different picture and (much) less layout — and the sighted one is
	# the one whose 8x8 grid decides whether the card fits its anchor band. Grant the chip and cover the
	# stake, or this shot is a toast ("you can't cover the 50 zm stake") over an unopened screen.
	player.call(&"unlock_mechanic", &"chess_visualizer")
	player.call(&"add_money", 500.0)
	var cm := ChessMatch.new()
	cm.set(&"opponent_name", "QA Grandmaster")
	cm.set(&"wager", 50)
	ChessScreen.open_match(cm, player)
	await _frames(12)  # the board grid builds its 64 cells
	await _shot("19_chess")
	ChessScreen.close()
	await _frames(2)
	cm.free()

	# The implant-purchase New Game step (StartMenu-hosted overlay, not an autoload — instantiated here the
	# same way StartMenu does it, like the TOS gate above). The first roster row is toggled DOWN before the
	# shot so the pressed/selected accent bar is in frame: the selection art vs row text alignment is
	# exactly what this shot exists to watch (the empty-row-Button height bug — MenuStyle.size_row_button).
	var imp: Control = (load("res://scenes/ui/implant_choice.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(imp)
	await _frames(8)
	var imp_rows: Array = imp.get(&"_rows")
	if imp_rows is Array and not imp_rows.is_empty():
		(imp_rows[0] as Button).button_pressed = true
		await _frames(2)
	await _shot("20_implant_choice")
	imp.queue_free()
	await _frames(2)

	# The Implants tab (the fifth Pip-Boy sibling). Seed BOTH sections so the reference shows the
	# real two-block layout: grant one mechanic and drop an uninstalled chip in the bag. Safe against the
	# profile ONLY because the inventory-autosave seam was unplugged above — unlock_mechanic itself writes
	# nothing, but the chip add would otherwise flush the grant into the user's save.
	if player.has_method(&"unlock_mechanic"):
		player.unlock_mechanic(&"wall_climb")
		# ...and a SECOND implant switched off, so the reference shot carries BOTH row states: the pressed
		# accent bar of an active implant and the dimmed caption of a switched-off one.
		player.unlock_mechanic(&"slide")
		if player.has_method(&"set_mechanic_active"):
			player.set_mechanic_active(&"slide", false)
	if inv != null:
		var chip: Item = ItemDb.item_by_id(&"chip_grapple")
		if chip != null:
			inv.add(chip, 1)
	if _try_open(ImplantsScreen):
		await _frames(8)
		await _shot("21_implants")
		ImplantsScreen.close()
		await _frames(2)

	_finish()

func _finish() -> void:
	print("QA_SHOTS_DONE dir=", _dir)
	get_tree().quit()

## open() screens that can silently refuse (modal guards): report whether it actually opened.
func _try_open(screen) -> bool:
	screen.open()
	if screen.is_open():
		return true
	print("QA_SKIP ", screen)
	return false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path)
	_report_card_rect(name)

## Print the on-screen rect of every visible menu CARD in this shot, so a sibling screen that resizes or
## re-centres its panel shows up as a number here and not just as a "hmm, that moved" in the PNGs. A card
## whose combined minimum beats its anchor band is GROWN past the anchors by the engine (never clipped, never
## scrolled) — see tests/test_menu_layout_stability.gd, which pins the tabbed screens against exactly this.
func _report_card_rect(shot_name: String) -> void:
	for panel in get_tree().root.find_children("Panel", "", true, false):
		var c := panel as Control
		if c == null or not c.is_visible_in_tree():
			continue
		var band := Vector2(
			(c.anchor_right - c.anchor_left) * get_viewport().get_visible_rect().size.x,
			(c.anchor_bottom - c.anchor_top) * get_viewport().get_visible_rect().size.y)
		var over := "  <<< MINIMUM BEATS THE ANCHOR BAND" if band.x > 0.0 and band.y > 0.0 \
				and (c.get_combined_minimum_size().x > band.x + 0.5 or c.get_combined_minimum_size().y > band.y + 0.5) else ""
		print("QA_RECT ", shot_name, " ", c.get_parent().name, "/", c.name,
			" pos=", c.global_position, " size=", c.size, " min=", c.get_combined_minimum_size(), over)
