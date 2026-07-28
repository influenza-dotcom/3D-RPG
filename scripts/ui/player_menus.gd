extends RefCounted
## Shared behaviour for the four PLAYER-MENU overlays — Inventory / Stats / Reputation / Journal — so they act as a
## Deus Ex / Pip-Boy style TAB GROUP: a tab strip switches between them, and pressing one's hotkey while another
## is open jumps STRAIGHT to it (each screen's open() calls close_others first, so opening one switches off a
## sibling rather than being blocked). No class_name on purpose (preloaded const where used), no state — just
## static helpers over the four screen autoloads. The settings menu (OptionsMenu, Esc) is deliberately NOT in
## the group; it stays a separate system menu.
##
## IMPORTANT — autoload ORDER: InventoryScreen is declared before StatsScreen/ReputationScreen in project.godot,
## so when InventoryScreen builds its UI in _ready() the sibling autoloads aren't registered yet. The tab strip
## is therefore keyed on stable StringName KEYS and resolves the actual screen autoload only AT CLICK TIME
## (_screen_for), by which point the whole autoload list is live. build_tab_strip touches NO sibling autoload at
## build time. Keys are ROUTING ids and are never painted — display text lives in PlayerText via TAB_LABELS.

const TABS: Array[StringName] = [&"inventory", &"stats", &"reputation", &"journal"]  ## tab order; each entry is the stable ROUTING key (screens resolved lazily; painted text via TAB_LABELS)

## key -> painted button text. The labels are PlayerText consts (display prose lives there, never inline),
## so re-wording a tab can't silently change the routing key above — the two were one string before.
const TAB_LABELS := {
	&"inventory": PlayerText.MENU_TAB_INVENTORY,
	&"stats": PlayerText.MENU_TAB_STATS,
	&"reputation": PlayerText.MENU_TAB_REPUTATION,
	&"journal": PlayerText.MENU_TAB_JOURNAL,
}

## Mouse-mode handling for the tab group is centralised here so switching sibling menus never round-trips through
## MOUSE_MODE_CAPTURED (which recenters the cursor). `_group_prev_mode` is the OS mouse mode before the group was
## entered (gameplay = CAPTURED), saved on the FIRST open and restored on the LAST close.
static var _group_prev_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
static var _switching: bool = false  ## true while close_others swaps one sibling for another (suppresses restore)

## The screen autoload for a tab KEY, resolved at CALL TIME (never cached) so it's safe even before every
## autoload has registered. Returns null for an unknown key or a not-yet-registered autoload.
static func _screen_for(key: StringName):
	match key:
		&"inventory": return InventoryScreen
		&"stats": return StatsScreen
		&"reputation": return ReputationScreen
		&"journal": return QuestJournal
	return null

## The painted text for a tab key. Unknown keys fall back to their own string so a stale caller still
## renders a legible button rather than erroring on a missing Dictionary entry.
static func tab_label(key: StringName) -> String:
	return String(TAB_LABELS.get(key, String(key)))

## The currently-registered player-menu screens (skips any not yet live). Call at runtime, not during _ready.
static func _screens() -> Array:
	var out: Array = []
	for key in TABS:
		var s = _screen_for(key)
		if s != null:
			out.append(s)
	return out

## True while any of the four player menus is open.
static func any_open() -> bool:
	for s in _screens():
		if s.is_open():
			return true
	return false

## Duck-typed liveness of a single candidate player. Keyed on is_alive() (Character's canonical "up and
## fightable" predicate) rather than the Player class, so this path-preloaded helper stays class-free and a
## test can pass a bare stub. A null / invalid / is_alive-less object counts as ALIVE here on purpose: the
## "no player to show" case is owned by each screen's own is_instance_valid(_player) guard — this gate is
## strictly about refusing to open MID-DEATH, not about a missing player.
static func _obj_alive(player) -> bool:
	return not is_instance_valid(player) or not player.has_method(&"is_alive") or player.is_alive()

## True unless the human player is mid-death. Each screen's open() consults this because the four menus run
## PROCESS_MODE_ALWAYS and never pause the tree, so their open hotkeys keep firing through the death cinematic
## AND the in-place checkpoint revive — where the player stays in-tree with the _dead latch set and hp 0
## (Character.is_alive() == false). die() slams any open menu shut (Player._close_open_modals), but without
## this nothing stopped the hotkey RE-opening one over the cinematic. Returns true off-tree / pre-spawn.
static func player_alive(tree: SceneTree) -> bool:
	return _obj_alive(Groups.human_player(tree))

## True only when a HUMAN player exists in-tree. The read-only global screens (Reputation reads the Reputation
## autoload, Journal reads GameState) never resolve a `_player`, so — unlike Inventory/Stats which bail on an
## invalid `_find_real_player()` — they would otherwise open over the start menu / character creation, where
## there is no player to show. Their open() ANDs this into the refuse condition. Groups is a global class_name
## util, safe to reference from this path-preloaded, class-free helper.
static func has_player(tree: SceneTree) -> bool:
	return Groups.human_player(tree) != null  # the human Player exists in-tree (start menu / char-creation have none)

## Close whichever sibling player-menus are open (all but `keep`). Each screen calls this from open() so opening
## one SWITCHES off an open sibling instead of stacking / being blocked.
static func close_others(keep) -> void:
	for s in _screens():
		if s != keep and s.is_open():
			s.close()

## A screen calls this from open() (in place of close_others). Remembers the pre-menu mouse mode on the FIRST
## open of the group, switches off any sibling WITHOUT recapturing the cursor (so it doesn't recenter), then frees
## the cursor for the UI. Call it while the opening screen's own is_open() is still false.
static func enter(keep) -> void:
	if not any_open():
		_group_prev_mode = Input.mouse_mode
	_switching = true
	close_others(keep)
	_switching = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## A screen calls this from close() AFTER clearing its own _is_open. Restores the pre-menu mouse mode only when the
## LAST group menu has closed and we're not mid-switch -- so opening a sibling keeps the cursor visible and in place.
static func leave() -> void:
	if _switching or any_open():
		return
	Input.mouse_mode = _group_prev_mode

## A full-width row of tab buttons — [Inventory | Stats | Reputation | Journal] — added at the top of each screen.
## `current_key` is the host screen's own tab KEY (&"stats" etc. — never the painted label); that button is
## disabled (you're on it) and wears the accent underline so the current tab reads as ACTIVE, not greyed-out.
## The others resolve their screen autoload ON CLICK and open() it (which closes the current one via
## close_others). The buttons inherit the screen's theme, and paint tab_label(key) — the key itself never shows.
## Buttons SPLIT the panel's width equally (EXPAND_FILL; skin.tab_min_width is only a floor) — a fixed
## per-button width once forced the strip wider than the 0.12-margin panel and shoved all four tab
## screens off-center at 792x444. Contract: the returned node's DIRECT children are exactly the 4 Buttons
## (tests/test_player_menus.gd asserts count/.text/.disabled) — never wrap them in extra containers.
static func build_tab_strip(current_key: StringName) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for key in TABS:
		var b := Button.new()
		b.text = tab_label(key)
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(MenuStyle.skin.tab_min_width, 0)
		if key == current_key:
			b.disabled = true  # the active tab — you're already here (input-wise; styled as active below)
			b.add_theme_color_override(&"font_disabled_color", MenuStyle.text_color())
			b.add_theme_stylebox_override(&"disabled", MenuStyle.make_active_tab_style())
		else:
			# Inactive tabs hover/press with the SAME accent underline as the active tab (at 35% — see
			# make_hover_tab_style), so the strip speaks one selection language; the theme Button's LEFT
			# accent bar is list-row language and read as a different system here.
			b.add_theme_stylebox_override(&"hover", MenuStyle.make_hover_tab_style())
			b.add_theme_stylebox_override(&"pressed", MenuStyle.make_hover_tab_style())
			b.add_theme_stylebox_override(&"hover_pressed", MenuStyle.make_hover_tab_style())
			# Resolve at CLICK time (lambda captures `key` by value): by runtime every autoload is registered.
			b.pressed.connect(func() -> void:
				var target = _screen_for(key)
				if target != null:
					target.open())  # open() closes the current one (close_others)
		row.add_child(b)
	return row
