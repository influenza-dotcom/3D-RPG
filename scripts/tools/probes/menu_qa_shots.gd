extends Node
## Menu QA screenshot harness — boots the real game once and captures a PNG of EVERY menu screen
## at the true runtime canvas (792x444 at 16:9; stretch viewport + aspect=expand + scale 0.5).
## Doubles as the UI-ARTIST reference pack: every screen in the "Menus are scenes" roster gets a shot,
## so a reskin brief can ship the whole set (upscale the PNGs with NEAREST for a legible hand-off —
## the canvas is deliberately low-res, so a smooth upscale misrepresents the pixel look).
## RETRO-PINNED: _run forces Settings.presentation = PRESENTATION_RETRO (plain var + apply_video — NEVER a
## Settings.set_*, which persists to the dev's real settings.cfg; hud_curve_qa_shots.gd's header documents
## that rule), so the pack stays this deterministic 792x444 pixel look regardless of the dev's saved
## presentation. A HIGH FIDELITY sweep is a separate follow-up harness.
## Run from the project root (a real windowed run — NOT --headless, the GPU must render):
##   godot --path . res://scripts/tools/probes/menu_qa_shots.tscn -- --shots-dir="C:/some/dir"
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
	GameState.enable_sandbox()  # every save this run triggers lands in user://sandbox/, never the real profile (the waypoint_qa_shots seam)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	# Windowed instead of the project's exclusive fullscreen so the run doesn't take over the desktop.
	# 1280x720 is 16:9, the same aspect as the user's monitor -> identical 792x444 canvas.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	# RETRO pin (see header): PLAIN vars + apply_video(), never a Settings.set_*() — a setter save_settings()s
	# over the dev's real user://settings.cfg. window_mode/windowed_size are pinned too because apply_video()
	# re-applies the stored mode (the dev's saved fullscreen would take the desktop back), and render_scale 2.0
	# is RETRO's authored 3D supersample (project.godot rendering/scaling_3d/scale — an HF cfg carries 1.0,
	# which would soften the 3D in the shots). Nothing here persists: only the setters write the cfg.
	Settings.presentation = Settings.PRESENTATION_RETRO
	Settings.window_mode = Settings.WINDOW_MODES.find(Window.MODE_WINDOWED)
	Settings.windowed_size = Vector2i(1280, 720)
	Settings.render_scale = 2.0
	Settings.apply_video()
	await _frames(5)
	print("QA_CANVAS=", get_viewport().get_visible_rect().size)

	# --- Boot-flow screens (no player needed) --------------------------------------------------
	get_tree().change_scene_to_file("res://scenes/start_menu.tscn")
	# ⭐WAIT FOR THE MENU, DO NOT COUNT FRAMES. The boot plays two fade cards (the internet warning) over ~6 s
	# before the menu is revealed, so the old 10-frame wait shot a nearly-black frame at alpha ~0.09 and the
	# game's actual first interactive screen went unphotographed for the whole UX audit. Poll for a VISIBLE
	# menu button instead — that is the thing the shot is of.
	# Poll the SCREEN'S OWN STATE, not a guess about buttons: start_menu.gd clears `_internet_warning_active`
	# in _reveal_menu_after_internet_warning(), which is precisely "the cards are done, the menu is the
	# screen now". A button-visibility probe answered true too early (the buttons exist under the black
	# cover), which is how the audit ended up with a photograph of a fade card.
	# DRIVE THE GAME'S OWN REVEAL rather than waiting the boot cards out. start_menu.gd calls
	# _reveal_menu_after_internet_warning() itself when the cards finish (and when a skip press lands), so
	# calling it is the same door, opened on the harness's schedule — it kills the quote tween, drops the
	# black cover and shows the buttons. Waiting instead means ~13 s of fades per run, and a frame-count
	# guess is what put a photograph of a fade card into the UX audit in the first place.
	var menu_up := false
	for i in 240:
		await get_tree().process_frame
		var sm: Node = get_tree().current_scene
		if sm != null and sm.has_method(&"_reveal_menu_after_internet_warning"):
			sm.call(&"_reveal_menu_after_internet_warning")
			menu_up = true
			break
	await _frames(20)  # let the reveal settle before the shutter
	print("QA_MENU_READY=", menu_up)
	await _shot("01_start_menu")

	# THE FADE CARDS. The internet-warning card and the New Game boot quote are the first and last things a new
	# player reads before the world, and neither was ever in this pack (the reveal above skips straight past them).
	# Painted at full alpha on the start menu's own card nodes, then put back exactly as the reveal left them.
	var sm0: Node = get_tree().current_scene
	if sm0 != null and sm0.get(&"_quote_label") != null:
		var q_label: Label = sm0.get(&"_quote_label")
		var q_root: Control = sm0.get(&"_quote_root")
		var q_black: Control = sm0.get(&"_black")
		var q_attrib: Label = sm0.get(&"_attrib_label")
		var cards: PackedStringArray = sm0.get_script().get_script_constant_map().get("INTERNET_WARNING_CARDS", PackedStringArray())
		q_black.visible = true
		q_root.modulate.a = 1.0
		q_attrib.visible = false
		q_label.text = cards[0] if not cards.is_empty() else ""
		await _frames(4)
		await _shot("01b_warning_card")
		var quote: Dictionary = sm0.call(&"_pick_quote")
		q_label.text = str(quote.get("text", ""))
		q_attrib.text = PlayerText.boot_quote_attribution(str(quote.get("attribution", "")))
		q_attrib.visible = true
		await _frames(4)
		await _shot("01c_boot_quote")
		q_root.modulate.a = 0.0
		q_black.visible = false
		await _frames(2)

	var cc: Control = (load("res://scenes/ui/character_creation.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(cc)
	await _frames(10)
	await _shot("02_char_create_stats")
	var tabs := cc.find_children("*", "TabContainer", true, false)
	if not tabs.is_empty():
		(tabs[0] as TabContainer).current_tab = 1
		await _frames(12)  # SubViewport preview needs frames to render
		await _shot("03_char_create_look")
		(tabs[0] as TabContainer).current_tab = 2
		await _frames(12)
		await _shot("03b_char_create_shirt")
		if cc.has_method(&"_on_shirt_custom_open"):
			cc.call(&"_on_shirt_custom_open")
			await _frames(6)
			await _shot("03c_char_create_colour_wheel")
			var layer: Variant = cc.get(&"_shirt_picker_layer")
			if layer is CanvasLayer:
				(layer as CanvasLayer).visible = false
		(tabs[0] as TabContainer).current_tab = 0
		await _frames(4)
	var pad_kb: Variant = cc.get(&"_pad_kb")
	if pad_kb is Control and cc.get(&"_name_edit") is LineEdit:
		pad_kb.call(&"open", cc.get(&"_name_edit"))
		await _frames(6)
		await _shot("03d_char_create_pad_keyboard")
		pad_kb.call(&"close")
		await _frames(2)
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
			# A page that overflows gets a second shot at its END, so a row clipped below the fold is in the pack.
			var page: ScrollContainer = (ot.get_tab_control(i) as ScrollContainer) if ot != null else null
			if page != null and page.get_v_scroll_bar().max_value > page.get_v_scroll_bar().page + 1.0:
				page.scroll_vertical = int(page.get_v_scroll_bar().max_value)
				await _frames(4)
				await _shot("04_options_tab%d_end" % i)
				page.scroll_vertical = 0
		OptionsMenu.call(&"_show_quit_confirm")
		await _frames(4)
		await _shot("04q_options_quit_confirm")
		(OptionsMenu.get(&"_quit_confirm") as Control).visible = false
		OptionsMenu.close()
		await _frames(2)

	# The FIRST-LAUNCH TERMS gate (terms_of_service_screen.tscn — hosted by StartMenu, not an autoload,
	# so it is instantiated here the same way StartMenu does it rather than opened through a singleton).
	var tos: Control = (load("res://scenes/ui/terms_of_service_screen.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(tos)
	await _frames(8)
	await _shot("05_terms_of_service")
	if tos.has_method(&"_on_decline"):
		tos.call(&"_on_decline")
		await _frames(4)
		await _shot("05b_terms_decline_nag")
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

	# The CRASH REPORT card — shown on the launch after a crash. Fed a short fake report (never a real file).
	CrashReportScreen.open("QA sample crash report\nengine 4.7 | level alive.map\nbreadcrumbs: (sample)", "user://crash_reports/qa_sample.txt")
	await _frames(6)
	await _shot("07b_crash_report")
	CrashReportScreen.close()
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
		var hover_item: Item = ItemDb.item_by_id(&"healthpack")
		if hover_item != null:
			InventoryScreen.call(&"_on_grid_hover_changed", hover_item)
			await _frames(4)
			await _shot("08a_inventory_hover_detail")
			InventoryScreen.call(&"_on_grid_hover_changed", null)
		# The WALLET ROW's amount card (AmountPrompt) — a real menu surface with no screen of its own, so it
		# only ever appears on top of this one. Seed some cash first: the prompt refuses a 0 wallet outright
		# (nothing to divide up), which is correct behaviour but shoots an empty frame.
		if player.has_method(&"add_money") and player.money <= 0.0:
			player.add_money(125.0)
		InventoryScreen._on_drop_money_pressed()
		await _frames(8)
		await _shot("08b_inventory_drop_amount")
		InventoryScreen._amount_prompt.close()
		await _frames(2)
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
	var shop_pistol: Item = ItemDb.item_by_id(&"pistol")
	if shop_pistol != null:
		ShopScreen.call(&"_on_hover", shop_pistol, true)
		await _frames(4)
		await _shot("10b_shop_hover_price")
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

	var qa_pm: Variant = player.call(&"_perk_manager") if player.has_method(&"_perk_manager") else null
	if qa_pm != null:
		qa_pm.set(&"skill_points", 2)
	var lu := LevelUp.new()
	lu.set(&"station_name", "QA Station")
	var perks: Array[Perk] = []
	for p in ["res://resources/perks/deadeye.tres", "res://resources/perks/tough_hide.tres"]:
		var r := load(p)
		if r is Perk:
			perks.append(r)
	lu.set(&"available_perks", perks)
	LevelUpScreen.open_level_up(lu, player)
	await _frames(8)
	await _shot("12_level_up")
	LevelUpScreen.close()
	await _frames(2)
	lu.free()

	if qa_pm != null:
		var qa_perk: Resource = load("res://resources/perks/tough_hide.tres")
		if qa_perk != null:
			qa_pm.call(&"unlock_perk", qa_perk)
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
	var loot_hover: Item = ItemDb.item_by_id(&"pistol")
	if loot_hover != null:
		LootScreen.call(&"_on_hover", loot_hover, true)
		await _frames(4)
		await _shot("14a_loot_hover")
	LootScreen.close()
	await _frames(2)
	corpse.free()

	var crate := ItemContainer.new()
	crate.set(&"container_name", "Footlocker")
	crate.set(&"money", 20.0)
	get_tree().root.add_child(crate)
	await _frames(2)
	if crate.get(&"inventory") != null:
		for id: StringName in [&"ammo_pistol", &"rock"]:
			var it: Item = ItemDb.item_by_id(id)
			if it != null:
				crate.inventory.add(it, 2)
	LootScreen.open_container(crate, player)
	await _frames(20)
	if LootScreen.is_open():
		await _shot("14c_container")
		LootScreen.close()
		await _frames(2)
	else:
		print("QA_SKIP 14c_container")
	crate.queue_free()

	var live_npc: Node = null
	for n in get_tree().get_nodes_in_group(Groups.NPC):
		if is_instance_valid(n) and n.get(&"inventory") is CharacterInventory:
			live_npc = n
			break
	if live_npc != null:
		LootScreen.pickpocket(live_npc, player)
		await _frames(20)
		if LootScreen.is_open():
			await _shot("14b_pickpocket")
			LootScreen.close()
			await _frames(2)
		else:
			print("QA_SKIP 14b_pickpocket (refused)")
	else:
		print("QA_SKIP 14b_pickpocket (no NPC with an inventory in the level)")

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

	# ...and POPULATED: one active quest and one completed. Safe against the profile: enable_sandbox() above routes
	# every save this run triggers into user://sandbox/.
	var qa_q1: Resource = load("res://resources/quests/clear_the_block.tres")
	var qa_q2: Resource = load("res://resources/quests/recover_the_package.tres")
	if qa_q1 != null:
		QuestTracker.start_quest(qa_q1)
	if qa_q2 != null:
		QuestTracker.start_quest(qa_q2)
		QuestTracker.complete_quest(qa_q2.get(&"id"))
	await _frames(4)
	await _shot("16a_hud_quest_toasts")
	if _try_open(QuestJournal):
		await _frames(8)
		await _shot("16b_journal_quests")
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
	var carried_chip: Item = ItemDb.item_by_id(&"chip_takedown")
	if inv != null and carried_chip != null:
		inv.add(carried_chip, 1)
	ChipInstallScreen.open_install(ci, player)
	await _frames(8)
	await _shot("18_chip_install")
	if carried_chip != null and ChipInstallScreen.has_method(&"_on_row_pressed"):
		ChipInstallScreen.call(&"_on_row_pressed", carried_chip, false)
		await _frames(4)
		await _shot("18a_chip_install_armed")
	ChipInstallScreen.close()
	await _frames(2)
	ci.free()

	# The GUNSMITH BENCH. ⭐⭐IT WAS MISSING FROM THIS ROSTER, AND THAT IS HOW IT SHIPPED BROKEN: the newest and
	# by far the most chrome-heavy card in the game (a gun cycler, a wallet row, a notice band, TWO sections and a
	# five-line stat footer) had no shot here and no _report_card_rect line, so nobody saw that both of its row
	# lists were rendering at ZERO height inside the 0.12 anchor band, or that its Panel's minimum beat that band
	# outright. Every screen the pack photographs gets that check for free — which is the argument for the pack.
	# Seeded so the shot has CONTENT: a gun the bench can work on (the fold needs a REGISTERED ItemDb template,
	# which is what moddable_weapons filters on), a part in the pack for the carried FIT rows, and stock on the
	# shelf for the BUY & FIT rows below them.
	if inv != null:
		for id: StringName in [&"pistol", &"smg"]:
			var gun: Item = ItemDb.item_by_id(id)
			if gun != null:
				inv.add(gun, 1)
		var carried_part: Item = load("res://resources/items/mod_long_barrel.tres")
		if carried_part != null:
			inv.add(carried_part, 1)
	var wb := WeaponBench.new()
	# ⭐IN THE TREE, and standalone OFF. The bench builds its `stock` CharacterInventory in _ready() — off-tree it
	# never runs, `stock` stays null and stock_parts() returns nothing, so the BUY & FIT half of the card would go
	# unphotographed (this shot's first run did exactly that). standalone=false keeps the run from spawning a
	# talk-layer hitbox and a StationSpeaker in the middle of the level while every other shot is being taken.
	wb.set(&"standalone", false)
	wb.set(&"auto_fit_collider", false)
	wb.set(&"bench_name", "QA Gunsmith")
	var part_stock: Array[StockEntry] = []
	for p2 in ["res://resources/items/mod_extended_mag.tres", "res://resources/items/mod_suppressor.tres",
			"res://resources/items/mod_recon_scope.tres", "res://resources/items/mod_padded_stock.tres"]:
		var part := load(p2)
		if part != null:
			var e2 := StockEntry.new()
			e2.item = part
			e2.count = 1
			part_stock.append(e2)
	wb.set(&"stock_counts", part_stock)
	get_tree().root.add_child(wb)
	await _frames(2)
	print("QA_BENCH guns=", (wb.moddable_weapons(player) as Array).size(),
		" carried_parts=", (wb.fittable_parts(wb.moddable_weapons(player)[0] if not (wb.moddable_weapons(player) as Array).is_empty() else null, player) as Array).size(),
		" stock=", 0 if wb.get(&"stock") == null else (wb.get(&"stock").contents() as Array).size())
	WeaponBenchScreen.open_bench(wb, player)
	await _frames(8)
	await _shot("18b_weapon_bench")
	# ⭐AND ONE WITH THE FOOTER SPEAKING. At rest the before→after block is a header over blank lines, so a
	# resting shot photographs 75px of empty parchment and tells a reviewer nothing about the surface the whole
	# screen exists for. Focusing a PARTS row fires the same focus_entered -> _preview the pad player's navigation
	# does, which is also the wiring most likely to rot unnoticed (the mouse path would still look fine).
	var parts: VBoxContainer = WeaponBenchScreen._parts_list
	if parts != null and parts.get_child_count() > 0 and parts.get_child(0) is Button:
		(parts.get_child(0) as Button).grab_focus()
		await _frames(6)
		await _shot("18c_weapon_bench_preview")
		# ⭐AND ONE AFTER THE COMMIT. PRESSING the row is the point — driving wb.buy_and_fit() directly would
		# bypass WeaponBenchScreen._settle and photograph the bug instead of the fix. The card used to leave its
		# refresh to the bench's incidental signals, all of which fire mid-transaction, so a paid-for fit painted
		# an empty slot back over itself. This shot is what "the money left and the row changed" looks like.
		(parts.get_child(0) as Button).emit_signal(&"pressed")
		await _frames(8)
		await _shot("18d_weapon_bench_after_fit")
	else:
		print("QA_SKIP 18c_weapon_bench_preview — no parts row to focus")
	WeaponBenchScreen.close()
	await _frames(2)
	wb.queue_free()

	# The board is the SIGHTED open: without the Board Visualizer chip the screen shows the blindfold
	# placeholder instead, which is both a different picture and (much) less layout — and the sighted one is
	# the one whose 8x8 grid decides whether the card fits its anchor band. Grant the chip and cover the
	# stake, or this shot is a toast ("you can't cover the 50 zm stake") over an unopened screen.
	player.call(&"add_money", 500.0)
	var cm0 := ChessMatch.new()
	cm0.set(&"opponent_name", "QA Grandmaster")
	cm0.set(&"wager", 50)
	ChessScreen.open_match(cm0, player)
	await _frames(12)
	await _shot("19a_chess_blindfold")
	ChessScreen.close()
	await _frames(2)
	cm0.free()
	player.call(&"unlock_mechanic", &"chess_visualizer")
	player.call(&"add_money", 500.0)
	var cm := ChessMatch.new()
	cm.set(&"opponent_name", "QA Grandmaster")
	cm.set(&"wager", 50)
	ChessScreen.open_match(cm, player)
	await _frames(12)  # the board grid builds its 64 cells
	await _shot("19_chess")
	var mi: Variant = ChessScreen.get(&"_move_input")
	if mi is LineEdit:
		(mi as LineEdit).text = "zz9"
		ChessScreen.call(&"_submit_move")
		await _frames(4)
		await _shot("19b_chess_illegal_move")
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

	# The Map tab (the sixth Pip-Boy sibling). Needs MORE settle frames than its siblings: its body is a second
	# instance of the minimap widget, which gathers the level's wall geometry and slices the player's floor band
	# on its FIRST processed frame (it only processes while visible), then paints on the queued redraw after
	# that. Eight frames catches a blank panel; the shot is worth taking only once the plan is on it.
	# THE BODY CHANNEL IS IMPLANT-GATED NOW (Minimap._sample_scan_range): without a scanner chip the map draws
	# no NPC dots at all, and this reference shot would document a page-sized plan with nothing living on it.
	# Grant the LONG tier, since 55 m is the only one that puts anything on a 120 m view. Runtime-only — the
	# grant path emits mechanic_unlocked, which only ChipInstallScreen listens for, so nothing reaches user://.
	player.call(&"unlock_mechanic", &"deep_scanner")
	if _try_open(MapScreen):
		await _frames(20)
		await _shot("22_map")
		# ...and a second shot one zoom step out, because the zoom readout + the two footer buttons are the only
		# chrome this screen owns and the reference should show them having done something. RESTORED after the
		# shot: the zoom is a PERSISTED player row (Settings.set_map_zoom writes user://settings.cfg), so a QA
		# run that left it moved would follow the user into their next play session — the same class of profile
		# clobber the inventory-autosave unplug above exists to prevent.
		var was_map_zoom: float = Settings.map_zoom
		MapScreen._nudge_zoom(-1)
		await _frames(6)
		await _shot("23_map_zoomed_out")
		var lvl: String = GameState.current_level_path
		GameState.add_waypoint(lvl, player.global_position, "Stash", "Under the stairs", 0, 0)
		await _frames(4)
		MapScreen.call(&"_select", 0)
		await _frames(6)
		await _shot("22b_map_pin_selected")
		MapScreen.call(&"_on_edit_pressed")
		await _frames(6)
		await _shot("22c_map_pin_editor")
		var pr: Variant = MapScreen.get(&"_prompt")
		if pr != null and pr.has_method(&"close"):
			pr.call(&"close")
		GameState.remove_waypoint(lvl, 0)
		await _frames(2)
		Settings.set_map_zoom(was_map_zoom)
		MapScreen.close()
		await _frames(2)


	# --- Screens this pack never photographed before (09-17 "check EVERY menu") ------------------------------
	var atm := Atm.new()
	atm.set(&"standalone", false)
	atm.set(&"station_name", "QA Terminal")
	get_tree().root.add_child(atm)
	await _frames(2)
	AtmScreen.open_atm(atm, player)
	await _frames(8)
	if AtmScreen.is_open():
		await _shot("24_atm")
		AtmScreen.close()
		await _frames(2)
	else:
		print("QA_SKIP 24_atm")
	atm.queue_free()

	if _try_open(WaitScreen):
		await _frames(6)
		await _shot("25_wait")
		WaitScreen.close()
		await _frames(2)

	SaveLoadScreen.open(true)
	await _frames(8)
	await _shot("26_save_load_in_game")
	SaveLoadScreen.call(&"_on_save_pressed", 1)   # empty slot: writes (into the sandbox) and repaints
	await _frames(6)
	SaveLoadScreen.call(&"_on_save_pressed", 1)   # occupied now: arms the overwrite confirm
	await _frames(6)
	await _shot("26b_save_overwrite_confirm")
	SaveLoadScreen.close()
	await _frames(2)

	if _try_open(OptionsMenu):
		await _frames(6)
		await _shot("27_options_in_game")
		OptionsMenu.close()
		await _frames(2)

	UI.toast(PlayerText.TOAST_QUICKSAVED)
	await _frames(4)
	await _shot("28_hud_plain")

	# --- THE HUD's WORDS (09-17 "check the HUD"): every text-carrying HUD state, driven through the same HUD
	# methods the gameplay drivers call. The per-frame drivers are PAUSED for the block (the player's own
	# _physics_process re-asserts the stealth badge, and the takedown / pet / claim nodes re-assert their cues
	# every frame), then restored. Nothing here writes a save: every call is a HUD paint, not a state change.
	var hud_ui: Node = player.get(&"ui")
	var hud_ph: Variant = player.get(&"_hud")
	var paused_drivers: Array[Node] = [player]
	for c in player.get_children():
		if c is SilentTakedown or c is PetInteraction or c is ClaimInteraction:
			paused_drivers.append(c)
	for n in paused_drivers:
		n.set_physics_process(false)
	var pickup_key: String = InputManager.get_action_binding(InputManager.action_pickup)
	if hud_ui != null:
		hud_ui.call(&"set_look_name", "[%s] %s" % [pickup_key, PlayerText.talk_to(PlayerText.JOB_MERCHANT)], Color(0.92, 0.92, 0.95))
		await _frames(3)
		await _shot("30_hud_look_talk")
		hud_ui.call(&"set_look_name", "[%s] %s" % [pickup_key, PlayerText.pick_up("Health Pack")], Color(0.92, 0.92, 0.95))
		await _frames(3)
		await _shot("30b_hud_look_pickup")
		hud_ui.call(&"set_look_name", "", Color.WHITE)
	if hud_ph != null:
		hud_ph.call(&"set_takedown_cue", true, PlayerText.takedown_prompt(InputManager.get_action_binding(&"Takedown"), PlayerText.STRANGER), 0.45)
		await _frames(3)
		await _shot("31_hud_takedown_cue")
		hud_ph.call(&"clear_interaction_cues")
		hud_ph.call(&"set_stealth_level", StealthStatus.Level.HIDDEN, true)
		await _frames(3)
		await _shot("32_hud_stealth_hidden")
		hud_ph.call(&"set_stealth_level", StealthStatus.Level.DANGER, true)
		await _frames(3)
		await _shot("32b_hud_stealth_danger")
		hud_ph.call(&"clear_stealth_readout")
		var target_npc: Node = null
		for n in get_tree().get_nodes_in_group(Groups.NPC):
			if is_instance_valid(n):
				target_npc = n
				break
		hud_ph.call(&"show_enemy_health", target_npc, 40.0, 100.0, 65.0)
		await _frames(3)
		await _shot("33_hud_enemy_health")
		hud_ph.call(&"clear_enemy_health")
	var hb: Variant = hud_ui.get(&"_hotbar") if hud_ui != null else null
	if hb != null:
		hb.call(&"_wake")
		await _frames(12)
		await _shot("34_hud_hotbar")
	# Toast stacks. Each batch is shot, then allowed to clear (hold + fade) before the next, so a shot shows one family.
	var toast_hold: float = GameSettings.hud.rep_toast_hold + GameSettings.hud.rep_toast_fade + 0.3
	var fb = GameSettings.player_feedback
	for batch: Array in [
			["35_hud_toasts_combat", [
				[PlayerText.TOAST_SNEAK_ATTACK, fb.sneak_toast_color],
				[PlayerText.TOAST_TAKEDOWN, Color(0.72, 0.86, 0.92)],
				[PlayerText.head_crippled(), fb.cripple_toast_color],
				[PlayerText.crippled_target("Raider", "Leg"), Color(1.0, 0.7, 0.3)],
				[PlayerText.collateral_kill(25.0), Color(1.0, 0.86, 0.3)],
				[PlayerText.long_range_kill(48, 30.0), Color(1.0, 0.86, 0.3)],
				[PlayerText.TOAST_CAUGHT, CBPalette.loss()],
			]],
			["35b_hud_toasts_progress", [
				[PlayerText.level_up(3, 1), Color(0.7, 0.9, 1.0)],
				[PlayerText.acquired("Grapple Chip"), Color(0.5, 0.85, 1.0)],
				[PlayerText.installed("Grapple Chip"), Color(0.5, 0.85, 1.0)],
				[PlayerText.learned("Deadeye"), Color(0.6, 0.85, 1.0)],
				[PlayerText.gained_hp(25), Color(0.4, 1.0, 0.45)],
				[PlayerText.reputation_changed("Townsfolk", true), Color(0.5, 1.0, 0.5)],
				[PlayerText.alignment_changed("Raiders", PlayerText.ALIGNMENT_HOSTILE_WORD), Color(1.0, 0.4, 0.4)],
			]],
			["35c_hud_toasts_money", [
				[PlayerText.purse_taken("a stranger", 40.0), fb.death_wallet_toast_color],
				[PlayerText.purse_dropped(40.0), fb.death_wallet_toast_color],
				[PlayerText.credit_score_toast(612, -24, &"subprime", true), Color(1.0, 0.6, 0.4)],
				[PlayerText.ledger_interest(-12.0), Color(1.0, 0.6, 0.4)],
				[PlayerText.atm_deposited(100.0, true), Color(0.6, 0.85, 1.0)],
				[PlayerText.chess_win(50.0), GameSettings.hud.money_gain_color],
			]],
			["35d_hud_toasts_world", [
				[PlayerText.holster_forgiveness_tutorial(InputManager.get_action_binding(InputManager.action_reload)), Color(1.0, 0.85, 0.4)],
				[TextFormat.subst(PlayerText.WAYPOINT_MARKED, {"name": "Pin 1"}), Color.WHITE],
				[PlayerText.locked_requires("Vault Key"), Color(1.0, 0.55, 0.4)],
				[PlayerText.TOAST_BACKPACK_PARTIAL, Color(0.85, 0.85, 0.85)],
				[PlayerText.radio_on("Jukebox"), Color(0.5, 0.8, 1.0)],
				[PlayerText.befriend("Rex"), Color(1.0, 0.6, 0.7)],
				[PlayerText.inventory_full(2), Color(1.0, 0.6, 0.3)],
			]],
		]:
		await get_tree().create_timer(toast_hold).timeout
		for t: Array in batch[1]:
			player.call(&"notify_toast", String(t[0]), t[1] as Color)
		await _frames(4)
		await _shot(String(batch[0]))
	await get_tree().create_timer(toast_hold).timeout
	for n in paused_drivers:
		if is_instance_valid(n):
			n.set_physics_process(true)

	if player.has_method(&"_show_death_card") and player.has_method(&"_compose_death_message"):
		player.set(&"_death_card_text", player.call(&"_compose_death_message"))
		player.call(&"_show_death_card")
		var dc: Variant = player.get(&"_death_card")
		if dc is Control:
			(dc as Control).modulate.a = 1.0
			await _frames(4)
			await _shot("29_death_card")
			(dc as Control).visible = false
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
	_report_scrollbars(name)

## Print EVERY scrollbar actually painted in this shot, with how far the content overflows its slot. A menu that
## shows a bar for a list of six rows is a layout defect (the 09-16 "you included a scrolling bar?" review), so the
## pack reports them as numbers instead of leaving a 6px track for a reviewer's eye to catch or miss.
func _report_scrollbars(shot_name: String) -> void:
	for n in get_tree().root.find_children("*", "ScrollContainer", true, false):
		var sc := n as ScrollContainer
		if sc == null or not sc.is_visible_in_tree():
			continue
		var bar := sc.get_v_scroll_bar()
		if bar == null or not bar.visible:
			continue
		var over := bar.max_value - bar.page
		print("QA_SCROLLBAR ", shot_name, " ", sc.get_parent().name, "/", sc.name,
			" slot=", sc.size, " overflow_px=", snappedf(over, 0.1))

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
