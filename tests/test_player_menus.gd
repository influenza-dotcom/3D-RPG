extends GutTest
## PlayerMenus: the tab-group helper that makes Inventory / Stats / Reputation behave as ONE Deus Ex / Pip-Boy
## menu — a tab strip plus switch-on-open (each screen's open() calls close_others). Loaded by PATH (no
## class_name) exactly as the three screens preload it. The helper is pure statics over the screen autoloads,
## so we assert label->screen resolution, the tab-strip structure, and the close_others/any_open contract.

const PM := preload("res://scripts/ui/player_menus.gd")

func after_each() -> void:
	for label in PM.TABS:
		var s = PM._screen_for(label)
		if s != null and s.is_open():
			s.close()

func test_tab_order_is_inventory_stats_reputation_journal() -> void:
	assert_eq(PM.TABS, ["Inventory", "Stats", "Reputation", "Journal"], "the four player menus, in tab order")

func test_screen_for_resolves_each_label_to_its_autoload() -> void:
	# Resolution is by label (the autoloads aren't all registered when InventoryScreen builds its strip in _ready).
	assert_eq(PM._screen_for("Inventory"), InventoryScreen, "Inventory -> InventoryScreen autoload")
	assert_eq(PM._screen_for("Stats"), StatsScreen, "Stats -> StatsScreen autoload")
	assert_eq(PM._screen_for("Reputation"), ReputationScreen, "Reputation -> ReputationScreen autoload")
	assert_eq(PM._screen_for("Journal"), QuestJournal, "Journal -> QuestJournal autoload")
	assert_null(PM._screen_for("Nope"), "an unknown label resolves to null")

func test_tab_strip_disables_only_the_current_tab() -> void:
	var strip = PM.build_tab_strip("Stats")
	assert_eq(strip.get_child_count(), 4, "one button per player menu")
	var by_text := {}
	for b in strip.get_children():
		by_text[b.text] = b
	assert_true(by_text["Stats"].disabled, "the current tab is disabled (you're already on it)")
	assert_false(by_text["Inventory"].disabled, "the other tabs are clickable")
	assert_false(by_text["Reputation"].disabled, "...")
	assert_false(by_text["Journal"].disabled, "...including the journal")
	strip.free()

func test_any_open_and_close_others_switch_off_a_sibling() -> void:
	assert_false(PM.any_open(), "nothing open to start")
	ReputationScreen.open()  # opens without a player (reads the global Reputation)
	assert_true(PM.any_open(), "any_open() sees the open reputation screen")
	# close_others(keep) closes every sibling but `keep` — keeping StatsScreen (not open) leaves Reputation to close.
	PM.close_others(StatsScreen)
	assert_false(ReputationScreen.is_open(), "close_others closed the open sibling")
	assert_false(PM.any_open(), "...so nothing is open now")
