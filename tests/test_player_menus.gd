extends GutTest
## PlayerMenus: the tab-group helper that makes Inventory / Stats / Implants / Map / Reputation / Journal behave as
## ONE Deus Ex / Pip-Boy menu — a tab strip plus switch-on-open (each screen's open() calls close_others).
## Loaded by PATH (no class_name) exactly as the screens preload it. The helper is pure statics over the screen autoloads,
## so we assert key->screen resolution (StringName routing keys; painted labels are separate PlayerText
## consts), the tab-strip structure, and the close_others/any_open contract.

const PM := preload("res://scripts/ui/player_menus.gd")

func after_each() -> void:
	for key in PM.TABS:
		var s = PM._screen_for(key)
		if s != null and s.is_open():
			s.close()

func test_tab_order_is_inventory_stats_implants_map_reputation_journal() -> void:
	# TABS holds ROUTING keys (StringName), not display text — the painted labels live in PlayerText via TAB_LABELS.
	assert_eq(PM.TABS, [&"inventory", &"stats", &"implants", &"map", &"reputation", &"journal"], "the six player menus, in tab order (routing keys)")

func test_every_tab_key_has_a_display_label() -> void:
	# The key->label lookup must cover every routing key, and each label is a PlayerText const, so a renamed
	# tab is a PlayerText edit — never a key change (build_tab_strip paints tab_label(key), never the key).
	for key in PM.TABS:
		assert_true(PM.TAB_LABELS.has(key), "tab key '%s' must have a display label in TAB_LABELS" % key)
		assert_ne(PM.tab_label(key), "", "tab key '%s' must resolve to non-empty painted text" % key)
	assert_eq(PM.tab_label(&"nope"), "nope", "an unknown key falls back to its own string (legible, never crashes)")

func test_screen_for_resolves_each_key_to_its_autoload() -> void:
	# Resolution is by KEY (the autoloads aren't all registered when InventoryScreen builds its strip in _ready).
	assert_eq(PM._screen_for(&"inventory"), InventoryScreen, "&\"inventory\" -> InventoryScreen autoload")
	assert_eq(PM._screen_for(&"stats"), StatsScreen, "&\"stats\" -> StatsScreen autoload")
	assert_eq(PM._screen_for(&"implants"), ImplantsScreen, "&\"implants\" -> ImplantsScreen autoload")
	assert_eq(PM._screen_for(&"map"), MapScreen, "&\"map\" -> MapScreen autoload")
	assert_eq(PM._screen_for(&"reputation"), ReputationScreen, "&\"reputation\" -> ReputationScreen autoload")
	assert_eq(PM._screen_for(&"journal"), QuestJournal, "&\"journal\" -> QuestJournal autoload")
	assert_null(PM._screen_for(&"nope"), "an unknown key resolves to null")

func test_tab_strip_disables_only_the_current_tab() -> void:
	var strip = PM.build_tab_strip(&"stats")  # the KEY routes; the buttons paint the labels
	assert_eq(strip.get_child_count(), 6, "one button per player menu")  # the direct-children contract (no wrappers)
	var by_text := {}
	for b in strip.get_children():
		by_text[b.text] = b
	assert_true(by_text[PlayerText.MENU_TAB_STATS].disabled, "the current tab is disabled (you're already on it)")
	assert_false(by_text[PlayerText.MENU_TAB_INVENTORY].disabled, "the other tabs are clickable")
	assert_false(by_text[PlayerText.MENU_TAB_IMPLANTS].disabled, "...")
	assert_false(by_text[PlayerText.MENU_TAB_MAP].disabled, "...including the map")
	assert_false(by_text[PlayerText.MENU_TAB_REPUTATION].disabled, "...")
	assert_false(by_text[PlayerText.MENU_TAB_JOURNAL].disabled, "...including the journal")
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


## THE STRIP MUST STILL FIT. Buttons EXPAND_FILL and split the panel, but each carries skin.tab_min_width as a
## FLOOR — so past some tab count the strip stops splitting and starts FORCING the panel wider than its
## 0.12-margin anchors, which shoved every tab screen off-centre the last time a fixed per-button width was
## used (player_menus.gd's build_tab_strip comment). Pure arithmetic against the logical canvas, no tree.
func test_the_tab_strip_still_fits_the_panel_band() -> void:
	var canvas_w := 792.0                    # the logical UI canvas (see ui-canvas-792x444)
	var band := canvas_w * (1.0 - 2.0 * 0.12)  # the shared PANEL_MARGIN anchors every tab screen authors
	var floor_total := float(PM.TABS.size()) * float(MenuStyle.skin.tab_min_width)
	var separations := float(PM.TABS.size() - 1) * 6.0  # build_tab_strip's authored separation constant
	assert_lt(floor_total + separations, band,
		"%d tabs at the %dpx width floor (+ separations) must fit inside the 0.12-margin panel at 792 wide, or the strip forces every tab screen off-centre" % [PM.TABS.size(), MenuStyle.skin.tab_min_width])
