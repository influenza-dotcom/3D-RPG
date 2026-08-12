extends CanvasLayer
## ImplantsScreen — the IMPLANTS screen, opened with its own key (InputManager.action_implants, default I).
## Registered as an autoload, mirroring StatsScreen / QuestJournal, and the fifth member of the Pip-Boy tab
## group (Inventory / Stats / Implants / Reputation / Journal). Two sections stacked in one scrolling list
## (the chip-install shape): INSTALLED — the microchip abilities fitted into your head (Player.installed_list),
## where each row is a TOGGLE that switches the implant off / back on (Player.set_mechanic_active — gameplay
## reads it off via has_mechanic, but the implant stays OWNED and persists via GameState.disabled_unlocks) —
## and CARRIED, NOT INSTALLED — upgrade chips sitting in the backpack, read-only here: installing stays a paid
## ChipInstaller interaction. Like the other player menus it does NOT pause the world; it frees the mouse
## (restored on close). Refreshes live off Player.mechanic_unlocked / mechanic_toggled + the bag's changed
## signal while open; each successful toggle autosaves so the preference survives a quit.
##
## AUTHORED SCENE: the layout lives in scenes/ui/implants_screen.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and applies the
## skin-driven look (MenuStyle style_* adopters + skin reads) on top. NO text is authored in the scene —
## every string is set here from PlayerText (l10n + the text-debt ratchet own strings, never a .tscn).
## The section blocks stay CODE-built into the authored %ImplantList (rebuilt per open / live change), and
## the PlayerMenus tab strip stays CODE-BUILT into the authored %TabSlot (the strip's one-Button-per-tab
## structure is a cross-screen contract owned by player_menus.gd, not this scene).
## tests/test_implants_screen_scene.gd pins the wiring; tests/test_implants_screen.gd covers the roster.

signal opened
signal closed


const PANEL_MARGIN := 0.12  ## same border as the other inventory-style screens — shared chrome (authored on the scene's Panel anchors; tests pin the band)
const PlayerMenus := preload("res://scripts/ui/player_menus.gd")  ## tab-group helper
## Canonical ability-name accessor (path-preloaded, no class_name — the implant_choice / item_info idiom).
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")

var _root: Control
var _list: VBoxContainer
var _is_open := false
var _player: Player = null
var _signature := ""  ## what the built rows depict (_roster_signature) — gates the live-refresh rebuild
## The INSTALLED toggle rows in paint order — this tab's ONLY focusables (the tab strip is FOCUS_NONE by the
## cross-screen contract), i.e. the pad path. The OptionsMenu `_first_focus` idiom, plural: open() seeds
## element 0, and _rebuild re-seats focus by INDEX across a teardown (_reseat_focus). Rebuilt with the rows
## (_make_toggle_row appends; _rebuild clears).
var _focus_rows: Array[Button] = []

func _ready() -> void:
	layer = 120                                  # above the HUD, just under OptionsMenu (128)
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep receiving input + rendering; this tab does NOT pause — the world runs real-time beneath it (Pip-Boy tabs are vulnerable by design)
	_bind_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

func toggle() -> void:
	if _is_open:
		close()
	else:
		open()

## Open the implants list. Refuses over the non-player modals and mid-death, and bails without a live player
## (start menu / character creation) — the installed roster is read OFF the player, matching Inventory/Stats.
func open() -> void:
	# Block only the NON-player modals; the sibling player menus instead SWITCH to us via close_others.
	if _is_open or DialogueManager.is_active() \
			or InputManager.any_tab_blocking_open() \
			or not PlayerMenus.player_alive(get_tree()):  # refuse mid-death (PROCESS_MODE_ALWAYS would else re-open over the death cinematic)
		return
	_player = Groups.human_player(get_tree()) as Player
	if not is_instance_valid(_player):
		return  # no player (e.g. the start menu) -> nothing to show
	PlayerMenus.enter(self)  # switch off a sibling + free the cursor (preserves cursor position across switches)
	_is_open = true
	_bind(true)
	_rebuild()
	_root.visible = true
	# Seed pad/keyboard focus on the first toggle row (the OptionsMenu `_first_focus` / AtmScreen / HealScreen
	# idiom) — AFTER the root shows, since grab_focus on a hidden Control does nothing. Without a focus owner,
	# ui navigation has nowhere to start and every row is pad-unreachable (the atm_screen must-not-recur rule).
	# With no rows at all — nothing installed yet — the tab legitimately opens ownerless: the toggle rows are
	# its only focusables, and there is nothing to act on.
	if not _focus_rows.is_empty():
		_focus_rows[0].grab_focus()
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	_bind(false)
	_player = null
	PlayerMenus.leave()
	closed.emit()

## (Dis)connect the live-refresh sources while open: a fresh unlock (an UpgradePickup grabbed with the tab up)
## moves a row between sections, a toggle repaints its row (mechanic_toggled — our own clicks route through
## it too), and the bag changing adds/removes carried chips. Idempotent, and disconnected on close — the
## autoload lives forever, a leaked connection would rebuild a hidden screen (the QuestJournal rule).
func _bind(on: bool) -> void:
	if not is_instance_valid(_player):
		return
	var srcs: Array = [_player.mechanic_unlocked, _player.mechanic_toggled]
	if _player.inventory != null:
		srcs.append(_player.inventory.changed)
	for sig in srcs:
		if on and not sig.is_connected(_on_changed):
			sig.connect(_on_changed)
		elif not on and sig.is_connected(_on_changed):
			sig.disconnect(_on_changed)

## Two optional args: mechanic_unlocked/inventory.changed emit one/zero, mechanic_toggled emits (id, active) —
## a connected callable must accept a signal's FULL arg count (GDScript never drops extras).
##
## Rebuilds only when the painted roster ACTUALLY changed (the StatsScreen _current_stat_signature idiom).
## `inventory.changed` fires for things this screen doesn't paint — most often the MoneyPurse syncing its
## coin stack when a delayed kill bounty lands — and a rebuild frees every row, INCLUDING one the player is
## holding the mouse down on. A Button's `toggled` fires on RELEASE, so that click would land on a freed
## node and be silently swallowed. Same-signature changes are therefore ignored entirely.
func _on_changed(_a: Variant = null, _b: Variant = null) -> void:
	if not _is_open:
		return
	var sig := _roster_signature()
	if sig == _signature:
		return
	_rebuild()

## What the list currently PAINTS, as one comparable string: each installed implant with its on/off state,
## then the carried chips. Any change here is a real repaint; anything else is noise (see _on_changed).
func _roster_signature() -> String:
	if not is_instance_valid(_player):
		return ""
	var parts: PackedStringArray = []
	for id in installed_ids(_player):
		parts.append("%s:%s" % [id, "1" if _player.has_mechanic(id) else "0"])
	parts.append("|")
	for item in carried_chips(_player):
		parts.append(String(item.installs_ability))
	return "\n".join(parts)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputManager.action_implants):
		toggle()
		get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed(&"ui_cancel"):
		close()  # Esc closes (consume it so OptionsMenu doesn't also open behind us)
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# Roster (pure reads off the player — unit-tested with a duck-typed stub, tests/test_implants_screen.gd)
# ---------------------------------------------------------------------------------------------------

## The installed roster: every INSTALLED ability id on `player` (installed_list — switched on or off; an
## off implant must stay listed to be switchable back on), sorted by AUTHORED display name so the list reads
## alphabetically regardless of grant order. Duck-typed (has_method guard) so a bare test stub works and a
## missing surface degrades to empty.
func installed_ids(player) -> Array[StringName]:
	var out: Array[StringName] = []
	if player == null or not player.has_method(&"installed_list"):
		return out
	for id in player.installed_list():
		out.append(StringName(id))
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		return AbilityRegistry.display_name_for(a).naturalnocasecmp_to(AbilityRegistry.display_name_for(b)) < 0)
	return out

## Chips in `player`'s bag whose ability ISN'T installed yet — the "find a mechanic" section. One row per
## DISTINCT ability (two identical chips still show one row — the ChipInstaller dedupe rule), keyed by
## installs_ability and never Item.id (chip_takedown installs silent_takedown — the ids don't mirror).
## INSTALLED (mechanic_installed), not ACTIVE: a switched-off implant is still owned, so its chip stays out
## of this section (the ChipInstaller filter rule). Sorted by chip label, the implant_choice order.
func carried_chips(player) -> Array[Item]:
	var out: Array[Item] = []
	if player == null or not player.has_method(&"mechanic_installed"):
		return out
	var inv: Variant = player.get(&"inventory")  # duck-typed read: absence = an empty bag, never a crash
	if inv == null:
		return out
	var seen := {}
	for e in inv.contents():
		var item: Item = e.get("item")
		if item == null or not item.is_upgrade_chip():
			continue
		var id := item.installs_ability
		if seen.has(id) or player.mechanic_installed(id):
			continue
		seen[id] = true
		out.append(item)
	out.sort_custom(func(a: Item, b: Item) -> bool: return a.label().naturalnocasecmp_to(b.label()) < 0)
	return out

## ability id -> the chip Item that installs it, from the ItemDb boot scan (export-safe — the editor-only
## AbilityRegistry.ids() dir scan is never used at runtime). Installed rows use it to name the consumed
## chip; an ability granted with NO chip on disk (a perk grant, a starting seed) maps to nothing and its
## row simply shows no chip column.
func _chip_by_ability() -> Dictionary:
	var out := {}
	for item: Item in ItemDb.all_items():
		if item != null and item.is_upgrade_chip() and not out.has(item.installs_ability):
			out[item.installs_ability] = item
	return out

# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/implants_screen.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. The scene owns
## STRUCTURE (the full-rect Root/Dim, the PANEL_MARGIN 0.12 anchor band, the tab slot, the implant list's
## scroll slot with horizontal scroll authored OFF, the list's authored 14px section gap); the skin keeps
## owning LOOK — every colour/font/separation below is a MenuStyle/skin read, so reskinning via
## resources/ui/menu_skin.tres restyles this screen with zero scene edits.
func _bind_ui() -> void:
	_root = %Root  # full-rect, MOUSE_FILTER_STOP authored — eats clicks so nothing falls through to gameplay behind
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)

	(%VBox as VBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared panel-screen rhythm (MenuSkin)
	# The tab strip is the only header (the Inventory convention, adopted across the tabs so content starts
	# at one height). The strip stays CODE-BUILT by PlayerMenus into the authored %TabSlot: its
	# one-Button-per-tab EXPAND_FILL structure is a cross-screen contract (tests/test_player_menus.gd), so
	# the scene authors only the slot.
	%TabSlot.add_child(PlayerMenus.build_tab_strip(&"implants"))  # routing KEY, not the painted label

	# The list scrolls vertically only (horizontal scroll authored OFF on %Scroll, so a long name TRIMS in
	# its row — see _make_row — instead of widening the panel past its anchors). The section blocks are
	# DYNAMIC content, rebuilt into %ImplantList on open / live change (_rebuild).
	_list = %ImplantList

func _rebuild() -> void:
	# Remember the pad cursor BEFORE teardown: this list rebuilds on EVERY toggle (a flip always moves the
	# signature), and freeing a focused row leaves the viewport with NO owner — ui navigation dies one press
	# after it started (the atm_screen _reseat_focus_after_commit lesson). Remember the row's INDEX, never the
	# node (it is about to be freed) — the OptionsMenu _revert remembered-tab idiom translated to rows:
	# installed_ids order is deterministic across rebuilds, so the same index lands on the same implant, and
	# _reseat_focus clamps when the roster shrank. Tree guard: off-tree (the scene tests) there is no viewport.
	var focus_idx := -1
	if _root != null and _root.is_inside_tree():
		focus_idx = _focus_rows.find(_root.get_viewport().gui_get_focus_owner())
	_focus_rows.clear()
	# remove_child BEFORE queue_free: a queued-for-deletion child still counts toward the container's layout
	# for the rest of the frame, so leaving them in would lay the fresh rows out below the doomed ones for
	# one drawn frame.
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if not is_instance_valid(_player):
		_signature = ""
		return
	_list.add_child(_make_section(PlayerText.IMPLANTS_INSTALLED_HEADING, _installed_rows()))
	_list.add_child(_make_section(PlayerText.IMPLANTS_CARRIED_HEADING, _carried_rows()))
	_signature = _roster_signature()  # what these rows depict — _on_changed ignores signals that don't move it
	_reseat_focus(focus_idx)

## Put pad/keyboard focus back after _rebuild freed the rows. Only while the screen is really up (open()'s
## own pre-show _rebuild is seeded by open() itself once %Root is visible — grab_focus on a hidden Control
## does nothing), and only when the teardown actually left the viewport OWNERLESS — a live owner is never
## stolen (the atm_screen _reseat_focus_after_commit guard). `prev_idx` -1 (no row held focus, e.g. a
## bag-driven repaint before the player ever navigated) seeds the first row, open()'s own landing spot.
func _reseat_focus(prev_idx: int) -> void:
	if not _is_open or _root == null or not _root.visible or not _root.is_inside_tree() or _focus_rows.is_empty():
		return
	if _root.get_viewport().gui_get_focus_owner() != null:
		return
	_focus_rows[clampi(prev_idx, 0, _focus_rows.size() - 1)].grab_focus()

## Rows for the INSTALLED section: one TOGGLE row per implant — the AUTHORED ability name leads in the accent,
## the chip that carries it dimmed on the right (chips share one model — the name is the differentiator).
## Pressed (accent bar + fill, the theme's persistent `pressed` stylebox) = switched ON; an OFF implant's
## caption dims to 40% (the implant_choice broke-row look). Clicking flips it live (_on_row_toggled). A dim
## hint under the rows teaches the verb.
func _installed_rows() -> Array:
	var rows: Array = []
	var chip_by_ability := _chip_by_ability()
	for id in installed_ids(_player):
		var chip: Item = chip_by_ability.get(id)
		var chip_name := chip.label() if chip != null else ""
		rows.append(_make_toggle_row(id, AbilityRegistry.display_name_for(id), chip_name, _player.has_mechanic(id)))
	if not rows.is_empty():
		rows.append(MenuStyle.make_hint(PlayerText.IMPLANTS_TOGGLE_HINT))
	return rows

## Rows for the CARRIED section: the chip's item label leads (that's what sits in the bag), the ability it
## would install right-aligned in the accent (the implant_choice column layout), and a dim "get it fitted"
## hint under the rows — the one actionable fact this section can teach (unlike the INSTALLED rows above,
## a carried chip has nothing to toggle: it isn't fitted yet).
func _carried_rows() -> Array:
	var rows: Array = []
	for item in carried_chips(_player):
		rows.append(_make_row(item.label(), MenuStyle.text_color(), AbilityRegistry.display_name_for(item.installs_ability), MenuStyle.accent()))
	if not rows.is_empty():
		rows.append(MenuStyle.make_hint(PlayerText.IMPLANTS_CARRIED_HINT))
	return rows

## One section: a heading (cased by the single casing seam + header-sized, the chip-install heading idiom)
## over its rows, or the shared (none) hint when empty — a fresh character legibly reads "nothing yet" in
## both sections rather than a blank panel.
func _make_section(heading: String, rows: Array) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)  # the quest-block line rhythm
	var head := Label.new()
	head.text = MenuStyle.title_text(heading)  # the ONLY casing site — never a bare .to_upper() here
	head.add_theme_font_size_override(&"font_size", MenuStyle.skin.header_size)
	box.add_child(head)
	if rows.is_empty():
		box.add_child(MenuStyle.make_hint(PlayerText.IMPLANTS_NONE))
	else:
		for r in rows:
			box.add_child(r)
	return box

## One two-column READ-ONLY row (the CARRIED section): `left` fills and trims with "…" (so the right column
## never moves — the implant_choice rule; the host %Scroll has horizontal scroll OFF, so nothing may widen
## the panel) and `right` sits right-aligned. Plain Labels in an HBox — carried chips have nothing to click
## here (installing lives at a ChipInstaller mechanic), so no empty-text-Button height pin to manage.
func _make_row(left: String, left_color: Color, right: String, right_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_l := Label.new()
	name_l.text = left
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.add_theme_color_override(&"font_color", left_color)
	row.add_child(name_l)
	if not right.is_empty():
		var tag_l := Label.new()
		tag_l.text = right
		tag_l.size_flags_horizontal = Control.SIZE_SHRINK_END
		tag_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag_l.add_theme_color_override(&"font_color", right_color)
		row.add_child(tag_l)
	return row

## One INSTALLED toggle row: a full-width empty-text TOGGLE Button carrying the inset caption HBox — the
## implant_choice / chip-install row idiom (every child MOUSE_FILTER_IGNORE so clicks land on the Button;
## MenuStyle.size_row_button pins the height an empty text buffer would collapse). `button_pressed` mirrors
## the implant's ACTIVE state via set_pressed_no_signal (painting state must not fire the toggle), and an
## OFF implant's caption dims to 40% — the theme's persistent `pressed` accent bar + the dim together read
## as on/off in one glance. Click -> _on_row_toggled flips the mechanic live.
func _make_toggle_row(id: StringName, ability_name: String, chip_name: String, active: bool) -> Button:
	var btn := MenuStyle.size_row_button(Button.new())  # empty-text button: without the pin its rect (selection bar + hitbox) collapses above the labels
	btn.toggle_mode = true
	# FOCUS_ALL, NOT the FOCUS_NONE these shipped with (the atm_screen _add_chip lesson): the toggle rows ARE
	# this tab's pad path, and a control a pad can never land on is not a path at all. Paint order = focus
	# order — _focus_rows is how open() and _reseat_focus find the landing spot after a (re)build.
	btn.focus_mode = Control.FOCUS_ALL
	_focus_rows.append(btn)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.set_pressed_no_signal(active)
	var sb: StyleBox = MenuStyle.theme.get_stylebox(&"normal", &"Button")
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = sb.content_margin_left
	row.offset_top = sb.content_margin_top
	row.offset_right = -sb.content_margin_right
	row.offset_bottom = -sb.content_margin_bottom
	row.modulate.a = 1.0 if active else 0.4  # a switched-off implant reads dim (the implant_choice broke-row look)
	btn.add_child(row)
	var name_l := Label.new()
	name_l.text = ability_name
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # a long name trims; the chip column never moves
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_l.add_theme_color_override(&"font_color", MenuStyle.accent())
	row.add_child(name_l)
	if not chip_name.is_empty():
		var chip_l := Label.new()
		chip_l.text = chip_name
		chip_l.size_flags_horizontal = Control.SIZE_SHRINK_END
		chip_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		chip_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip_l.add_theme_color_override(&"font_color", MenuStyle.dim_color())
		row.add_child(chip_l)
	# MUTE the row's auto-wired generic click: the cue belongs to _on_row_toggled, which knows the DIRECTION of the
	# flip and whether the player even accepted it. Without this the press would sound twice (click + step). Hover
	# is untouched. Order-free — _wire_button skips a button already carrying the semantic meta, so setting it here
	# (off-tree, before the row enters the list) is correct.
	MenuStyle.set_button_sound(btn, &"")
	btn.toggled.connect(_on_row_toggled.bind(id))
	return btn

## A row was clicked: flip the implant's active state on the player. The resulting mechanic_toggled signal
## drives the repaint (_on_changed -> _rebuild — queue_free of the emitting button is deferred, so flipping
## from inside its own toggled emission is safe), and the preference autosaves so a quit can't lose it (the
## save carries it as GameState.disabled_unlocks, never touching the installed set).
func _on_row_toggled(on: bool, id: StringName) -> void:
	if not is_instance_valid(_player):
		return
	if _player.set_mechanic_active(id, on):
		# Switching an implant is a state flip WITH a direction, which is exactly what the step pair says: up for
		# on, down for off. The row Button itself is muted in _make_toggle_row, so this pair is the only cue on
		# the press.
		MenuStyle.play_step(1 if on else -1)
		GameState.autosave(_player)
	else:
		# A refused flip (the implant was uninstalled out from under this paint) left the row's CheckButton
		# toggled to a state the player doesn't own — and no mechanic_toggled fires on a refusal, so nothing
		# upstream repaints. Cue the denial and snap the row back ourselves (_rebuild is safe mid-emission:
		# row teardown is deferred, per _make_toggle_row's note above).
		MenuStyle.play_denied()
		_rebuild()
