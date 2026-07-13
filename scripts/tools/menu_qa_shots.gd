extends Node
## Menu QA screenshot harness — boots the real game once and captures a PNG of every menu screen
## at the true runtime canvas (792x444 at 16:9; stretch viewport + aspect=expand + scale 0.5).
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

	var cc: Control = load("res://scripts/ui/character_creation.gd").new()
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

	if _try_open(ReputationScreen):
		await _shot("05_reputation")
		ReputationScreen.close()
		await _frames(2)

	if _try_open(QuestJournal):  # unseeded on purpose: no GameState mutations -> no autosave writes
		await _shot("06_journal_empty")
		QuestJournal.close()
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

	# Seed the backpack so the grids aren't empty (runtime-only; inventory changes don't autosave).
	var inv = player.get(&"inventory")
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
