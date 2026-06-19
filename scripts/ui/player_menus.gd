extends RefCounted
## Shared behaviour for the three PLAYER-MENU overlays — Inventory / Stats / Reputation — so they act as a
## Deus Ex / Pip-Boy style TAB GROUP: a tab strip switches between them, and pressing one's hotkey while another
## is open jumps STRAIGHT to it (each screen's open() calls close_others first, so opening one switches off a
## sibling rather than being blocked). No class_name on purpose (preloaded const where used), no state — just
## static helpers over the three screen autoloads. The settings menu (OptionsMenu, Esc) is deliberately NOT in
## the group; it stays a separate system menu.
##
## IMPORTANT — autoload ORDER: InventoryScreen is declared before StatsScreen/ReputationScreen in project.godot,
## so when InventoryScreen builds its UI in _ready() the sibling autoloads aren't registered yet. The tab strip
## is therefore keyed on LABEL strings and resolves the actual screen autoload only AT CLICK TIME (_screen_for),
## by which point the whole autoload list is live. build_tab_strip touches NO sibling autoload at build time.

const TABS := ["Inventory", "Stats", "Reputation", "Journal"]  ## tab order; the label is the stable key (screens resolved lazily)

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

## True while any of the three player menus is open.
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

## A centred row of tab buttons — [Inventory | Stats | Reputation] — added at the top of each screen. `current_label`
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
