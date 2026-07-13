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

func test_has_player_false_without_a_player() -> void:
	# The GUT scene has no human Player in-tree, so the has_player gate reads false — Reputation/Journal refuse
	# to open over the start menu / character creation exactly as Inventory/Stats do.
	assert_false(PM.has_player(get_tree()), "no human Player in-tree -> has_player() is false")

func test_any_open_and_close_others_switch_off_a_sibling() -> void:
	# F-C39: Reputation/Journal now ALSO refuse to open with no human player (there's none in the GUT scene), so
	# their open() is a no-op here — the old test that exploited ReputationScreen as the one player-free-openable
	# screen no longer holds. Assert the new contract: both refuse, and close_others is a no-op when nothing is
	# open. (The live open->sibling-switch is playtest-verified per the in-tree convention: a real Player can't be
	# add_child'd in a unit test — Player._ready is forbidden by CLAUDE.md.)
	assert_false(PM.any_open(), "nothing open to start")
	ReputationScreen.open()  # refused: no human player in-tree (F-C39)
	assert_false(ReputationScreen.is_open(), "Reputation refuses to open with no player")
	QuestJournal.open()      # likewise refused
	assert_false(QuestJournal.is_open(), "Journal refuses to open with no player")
	assert_false(PM.any_open(), "nothing opened, so any_open() stays false")
	PM.close_others(StatsScreen)  # a no-op when nothing is open
	assert_false(PM.any_open(), "close_others is a no-op with nothing open")

## Off-tree unit for the mid-death gate each screen's open() consults (player_alive -> _obj_alive). A dead/dying
## player (is_alive() false — the _dead latch stays set through the death cinematic + in-place revive, player
## still in-tree) must refuse; a live player, a missing player, and an is_alive-less object must all pass so the
## gate stays strictly about death (the screens' own is_instance_valid(_player) guard owns "no player to show").
class _AliveStub extends RefCounted:
	var alive := true
	func is_alive() -> bool:
		return alive

func test_obj_alive_refuses_only_a_dead_player() -> void:
	var live := _AliveStub.new(); live.alive = true
	var dead := _AliveStub.new(); dead.alive = false
	assert_true(PM._obj_alive(live), "a live player -> menus may open")
	assert_false(PM._obj_alive(dead), "a dead/dying player -> menus refuse (no re-opening over the death cinematic)")
	assert_true(PM._obj_alive(null), "no player -> not 'dead' here (the screen's own null-check handles it)")
	assert_true(PM._obj_alive(RefCounted.new()), "an object without is_alive() -> treated as alive (duck-typed, never crashes)")
