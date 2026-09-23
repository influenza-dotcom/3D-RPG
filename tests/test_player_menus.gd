extends GutTest
## PlayerMenus: the tab-group helper that makes Inventory / Stats / Implants / Map / Reputation / Journal behave as
## ONE Deus Ex / Pip-Boy menu — a tab strip plus switch-on-open (each screen's open() calls close_others).
## Loaded by PATH (no class_name) exactly as the screens preload it. The helper is pure statics over the screen autoloads,
## so we assert key->screen resolution (StringName routing keys; painted labels are separate PlayerText
## consts), the tab-strip structure — including the strips the six LIVE autoloads actually built in their _ready —
## and the close_others/any_open switch driven on real open state.

const PM := preload("res://scripts/ui/player_menus.gd")

## A sibling's close() ends in PlayerMenus.leave(), which restores the group's pre-menu mouse mode (CAPTURED by
## default) once the LAST tab shuts — so a test that switches tabs off moves the real cursor mode. Snapshot it.
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE

func before_each() -> void:
	_prev_mouse_mode = Input.mouse_mode

func after_each() -> void:
	for key in PM.TABS:
		var s = PM._screen_for(key)
		if s != null and s.is_open():
			s.close()
	Input.mouse_mode = _prev_mouse_mode

## The six live screens paired with the painted label of the tab each must mark as CURRENT, listed in the order
## the strip must paint them. Named here directly (never through PM._screen_for / PM.TABS) so a routing or
## ordering slip in player_menus.gd cannot also rewrite the expectation it is checked against.
func _live_screens() -> Array:
	return [
		[InventoryScreen, PlayerText.MENU_TAB_INVENTORY],
		[StatsScreen, PlayerText.MENU_TAB_STATS],
		[ImplantsScreen, PlayerText.MENU_TAB_IMPLANTS],
		[MapScreen, PlayerText.MENU_TAB_MAP],
		[ReputationScreen, PlayerText.MENU_TAB_REPUTATION],
		[QuestJournal, PlayerText.MENU_TAB_JOURNAL],
	]

## The strip a live screen built into its authored %TabSlot (build_tab_strip returns the HBoxContainer), or null.
func _strip_of(screen: Node) -> Control:
	var slot := screen.get_node_or_null("%TabSlot")
	if slot == null:
		return null
	for c in slot.get_children():
		if c is HBoxContainer:
			return c as Control
	return null

## THE STRIP EACH SCREEN ACTUALLY SHOWS. Every one of the six autoloads built its strip in _ready from a routing KEY
## it passes as a literal (build_tab_strip(&"stats") in stats_screen.gd, &"journal" in quest_journal.gd, ...). A key
## renamed on ONE side — TABS vs that screen's literal — leaves the screen's strip with NO disabled tab, so nothing
## marks where the player is; a reordered TABS reshuffles the tab row the player has learned. Both read off the
## live strips, not off the const.
func test_every_screen_strip_paints_the_tab_order_and_marks_its_own_tab() -> void:
	var screens := _live_screens()
	var painted_order: Array = []
	for pair in screens:
		painted_order.append(pair[1])
	for pair in screens:
		var screen: Node = pair[0]
		var own: String = pair[1]
		var strip := _strip_of(screen)
		assert_true(strip != null, "%s built a tab strip into its %%TabSlot" % screen.name)
		if strip == null:
			continue
		var texts: Array = []
		var current: Array = []
		for c in strip.get_children():
			var b := c as Button
			assert_true(b != null, "%s's strip holds only tab Buttons as direct children (%s is not one)" % [screen.name, c.name])
			if b == null:
				continue
			texts.append(b.text)
			if b.disabled:
				current.append(b.text)
		assert_eq(texts, painted_order,
			"%s's strip must paint Inventory | Stats | Implants | Map | Reputation | Journal in that order — the player-facing tab row every screen shares" % screen.name)
		assert_eq(current, [own],
			"%s's strip must mark exactly its OWN tab as current — a routing key renamed on one side leaves the player with no 'you are here'" % screen.name)

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

func test_journal_and_reputation_refuse_to_open_without_a_player() -> void:
	# F-C39: Reputation/Journal ALSO refuse to open with no human player (there's none in the GUT scene), matching
	# Inventory/Stats — they read global state, but over the start menu there is nobody to show it for.
	ReputationScreen.open()
	assert_false(ReputationScreen.is_open(), "Reputation refuses to open with no player (start menu / char-creation)")
	QuestJournal.open()
	assert_false(QuestJournal.is_open(), "Journal refuses to open with no player (start menu / char-creation)")

## THE SWITCH ITSELF. Opening a tab while a sibling is up must SWITCH (close_others from enter()), never stack two
## menus. The real open() refuses without a human Player (above) and a Player's _ready can't run here, so the open
## state is flipped directly — the test_modal_registry.gd idiom — and the helper is driven against it, with the
## screen being opened (`keep`) as the control that must survive.
func test_close_others_switches_off_open_siblings_but_keeps_the_one_opening() -> void:
	assert_false(PM.any_open(), "precondition: no player menu is open")
	ReputationScreen._is_open = true
	QuestJournal._is_open = true
	assert_true(PM.any_open(), "any_open() must see an open tab, or enter() treats every tab press as a cold open")
	PM.close_others(QuestJournal)
	assert_false(ReputationScreen.is_open(), "opening the Journal switches off the open Reputation tab (no stacked menus)")
	assert_true(QuestJournal.is_open(), "...but never the screen being opened itself")
	assert_true(PM.any_open(), "the group still reads open while the Journal is up")
	PM.close_others(StatsScreen)
	assert_false(QuestJournal.is_open(), "switching on to Stats closes the Journal in turn")
	assert_false(PM.any_open(), "with every tab shut any_open() reads false, so the next hotkey is a cold open")

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
## used (player_menus.gd's build_tab_strip comment). MEASURED, not re-derived: each live screen's strip reports its
## own combined minimum width (the real width floor, the real separation, the real painted captions) and is held
## against the band that screen's authored Panel anchors leave on the logical canvas.
func test_the_tab_strip_still_fits_the_panel_band() -> void:
	var canvas_w := 792.0  # the logical UI canvas (see ui-canvas-792x444)
	for pair in _live_screens():
		var screen: Node = pair[0]
		var strip := _strip_of(screen)
		assert_true(strip != null, "%s built a tab strip into its %%TabSlot" % screen.name)
		if strip == null:
			continue
		var panel := strip.get_parent() as Control
		while panel != null and not (panel is PanelContainer):
			panel = panel.get_parent() as Control
		assert_true(panel != null, "%s's strip sits inside the screen's themed PanelContainer" % screen.name)
		if panel == null:
			continue
		var band := canvas_w * (panel.anchor_right - panel.anchor_left)
		var need := strip.get_combined_minimum_size().x
		assert_gt(need, 0.0, "precondition: %s's strip reports a real minimum width" % screen.name)
		assert_lt(need, band,
			"%s: the %d-tab strip needs %.0fpx but its panel band is %.0fpx wide at 792 — past that it forces the panel wider and every tab screen off-centre" % [screen.name, strip.get_child_count(), need, band])
