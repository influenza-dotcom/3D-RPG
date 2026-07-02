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
## is therefore keyed on LABEL strings and resolves the actual screen autoload only AT CLICK TIME (_screen_for),
## by which point the whole autoload list is live. build_tab_strip touches NO sibling autoload at build time.

const TABS := ["Inventory", "Stats", "Reputation", "Journal"]  ## tab order; the label is the stable key (screens resolved lazily)

## Mouse-mode handling for the tab group is centralised here so switching sibling menus never round-trips through
## MOUSE_MODE_CAPTURED (which recenters the cursor). `_group_prev_mode` is the OS mouse mode before the group was
## entered (gameplay = CAPTURED), saved on the FIRST open and restored on the LAST close.
static var _group_prev_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
static var _switching: bool = false  ## true while close_others swaps one sibling for another (suppresses restore)

## The screen autoload for a tab label, resolved at CALL TIME (never cached) so it's safe even before every
## autoload has registered. Returns null for an unknown label or a not-yet-registered autoload.
static func _screen_for(label: String):
	match label:
		"Inventory": return InventoryScreen
		"Stats": return StatsScreen
		"Reputation": return ReputationScreen
		"Journal": return QuestJournal
	return null

## The currently-registered player-menu screens (skips any not yet live). Call at runtime, not during _ready.
static func _screens() -> Array:
	var out: Array = []
	for label in TABS:
		var s = _screen_for(label)
		if s != null:
			out.append(s)
	return out

## True while any of the four player menus is open.
static func any_open() -> bool:
	for s in _screens():
		if s.is_open():
			return true
	return false

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

## A centred row of tab buttons — [Inventory | Stats | Reputation | Journal] — added at the top of each screen. `current_label`
## is the host screen's own tab; that button is disabled (you're on it). The others resolve their screen autoload
## ON CLICK and open() it (which closes the current one via close_others). The buttons inherit the screen's theme.
static func build_tab_strip(current_label: String) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	for label in TABS:
		var b := Button.new()
		b.text = label
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 0)
		if label == current_label:
			b.disabled = true  # the active tab — you're already here
		else:
			# Resolve at CLICK time (lambda captures `label` by value): by runtime every autoload is registered.
			b.pressed.connect(func() -> void:
				var target = _screen_for(label)
				if target != null:
					target.open())  # open() closes the current one (close_others)
		row.add_child(b)
	return row
