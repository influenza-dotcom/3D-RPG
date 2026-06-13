extends CanvasLayer
## InventoryScreen — the player's backpack overlay, opened with Tab. Code-built and registered as an
## autoload so ONE instance survives scene changes, mirroring OptionsMenu.
##
## Like OptionsMenu it does NOT pause the SceneTree: the world keeps simulating and the player stays
## vulnerable. It frees the mouse for the UI on open (restored on close), and player CONTROL is suppressed
## via is_open() gates (player move/jump, MouseInput fire, ScopeIn aim) so menu clicks/keys don't drive
## the character. Lists the player's items; clicking a weapon equips it through the backpack's equip
## bridge (CharacterInventory.equip_item -> Player._on_equip_weapon_requested -> the swap animation).

signal opened
signal closed

const PANEL_MARGIN := 0.12  ## fraction of the screen left as a border — SAME margin as the loot/shop screens, so every inventory-style menu shares one chrome

var _root: Control
var _list: VBoxContainer
var _sheet_row: HBoxContainer  ## the character sheet under the title — per-stat Labels + live HP/zorkmids, each hoverable
var _level_label: Label
var _hp_label: Label
var _zm_label: Label
var _stat_labels: Dictionary = {}  ## StringName stat -> its Label (so each stat hovers independently)
var _sort_btn: Button
var _sort_mode: int = ItemSort.Mode.DEFAULT  ## display order of the backpack list (cycled by the Sort button)
var _hovered_item: Item = null  ## the item row under the cursor — the hotbar assigns it when you press a slot key
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _bound_inventory: CharacterInventory = null

func _ready() -> void:
	layer = 120                                  # above the HUD, just under OptionsMenu (128)
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep working regardless of any pause
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

## The item the cursor is currently over (the hotbar reads this to assign it to a slot). Null when nothing is
## hovered or the hovered item has since left the bag (a guard against a stale reference after a rebuild).
func hovered_item() -> Item:
	if _hovered_item != null and is_instance_valid(_player) and _player.inventory != null and _player.inventory.has(_hovered_item):
		return _hovered_item
	return null

# ---------------------------------------------------------------------------------------------------
# Open / close — free the mouse, no SceneTree pause (control is suppressed via the is_open() gates)
# ---------------------------------------------------------------------------------------------------

func toggle() -> void:
	if _is_open:
		close()
	else:
		open()

func open() -> void:
	# Yield to dialogue, the settings menu, and every other modal — never stack two overlays. The pausing
	# screens (shop/heal/level-up) matter especially: our input runs PROCESS_MODE_ALWAYS, so without these
	# checks the inventory key would open us OVER a paused shop.
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() or LootScreen.is_open() or ShopScreen.is_open() or HealScreen.is_open() or LevelUpScreen.is_open():
		return
	_player = _find_real_player() as Player
	if not is_instance_valid(_player) or _player.inventory == null:
		return  # no player / no backpack -> nothing to show (e.g. the start menu)
	_bind_inventory(_player.inventory)
	_is_open = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild()
	_root.visible = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	Input.mouse_mode = _prev_mouse_mode
	closed.emit()

## Keep the list live: rebind to the player's backpack and refresh whenever its contents change (loot
## arriving, a weapon removed). Disconnects the previous binding so a respawned player doesn't double-fire.
func _bind_inventory(inv: CharacterInventory) -> void:
	if _bound_inventory == inv:
		return
	if is_instance_valid(_bound_inventory) and _bound_inventory.changed.is_connected(_on_inventory_changed):
		_bound_inventory.changed.disconnect(_on_inventory_changed)
	_bound_inventory = inv
	if inv != null and not inv.changed.is_connected(_on_inventory_changed):
		inv.changed.connect(_on_inventory_changed)

## Format + push the character sheet: total level (the level-up curve's input) + the five stats, then the
## LIVE vitals. Reads through stats_or_default so an unsheeted player shows a clean baseline-0 row.
func _refresh_stats() -> void:
	if _sheet_row == null or not is_instance_valid(_player):
		return
	var s := _player.stats_or_default()
	var total := 0
	for n: StringName in [&"strength", &"persuasion", &"gunplay", &"endurance", &"streetwise", &"agility"]:
		total += s.get_stat(n)
	_level_label.text = "Level %d" % total
	# Per-stat labels: same abbreviations/order as before, each carries its own hover breakdown.
	for entry: Array in [[&"strength", "Str", s.strength], [&"persuasion", "Per", s.persuasion], [&"gunplay", "Gun", s.gunplay], [&"endurance", "End", s.endurance], [&"streetwise", "Stw", s.streetwise], [&"agility", "Agi", s.agility]]:
		var stat: StringName = entry[0]
		var lbl: Label = _stat_labels[stat]
		lbl.text = "%s %d" % [entry[1], entry[2]]
		MenuStyle.attach_tip(lbl, StatInfo.tooltip(stat, s))  # idempotent: refreshes the tip text each poll
	_hp_label.text = "HP %d / %d" % [int(round(_player.hp)), int(round(_player.max_hp))]
	_zm_label.text = "%s zm" % Zorkmids.fmt(_player.money)

func _process(_delta: float) -> void:
	if _is_open:
		_refresh_stats()  # cheap label format; keeps HP/money honest while the world runs under the screen

func _on_inventory_changed() -> void:
	if _is_open:
		_rebuild()

## The human player, not a companion (companions join &"Player" for targeting but are NPCs).
func _find_real_player() -> Node:
	for p in get_tree().get_nodes_in_group(&"Player"):
		if not (p is NPC):
			return p
	return null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputManager.action_inventory):
		toggle()
		get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed(&"ui_cancel"):
		close()  # Esc closes the backpack (OptionsMenu.open() also refuses while we're open, so it won't stack)
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# UI construction + the item list
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so nothing falls through to gameplay behind
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	add_child(_root)

	_root.add_child(MenuStyle.make_dim())

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = PANEL_MARGIN
	panel.anchor_top = PANEL_MARGIN
	panel.anchor_right = 1.0 - PANEL_MARGIN
	panel.anchor_bottom = 1.0 - PANEL_MARGIN
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	vbox.add_child(MenuStyle.make_title("Inventory"))

	# Character sheet — Tab doubles as the "view my current stats" screen: the five CharacterStats + total
	# level, then HP / zorkmids. POLLED in _process while open (this screen is non-pausing, so HP and money
	# genuinely change under it — you can be shot while you sort your bag). Each of the five stats is its OWN
	# Label in this HBox so hovering ONE shows just that stat's breakdown (StatInfo.tooltip).
	_sheet_row = HBoxContainer.new()
	_sheet_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_sheet_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_sheet_row)
	_level_label = _make_sheet_label()
	_sheet_row.add_child(_level_label)
	_sheet_row.add_child(_make_sheet_sep())
	for stat: StringName in [&"strength", &"persuasion", &"gunplay", &"endurance", &"streetwise", &"agility"]:
		var lbl := _make_sheet_label()
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP  # so the per-stat tooltip shows on hover
		_stat_labels[stat] = lbl
		_sheet_row.add_child(lbl)
	_sheet_row.add_child(_make_sheet_sep())
	_hp_label = _make_sheet_label()
	_sheet_row.add_child(_hp_label)
	_sheet_row.add_child(_make_sheet_sep())
	_zm_label = _make_sheet_label()
	_sheet_row.add_child(_zm_label)

	# Sort button — cycles the backpack list's order (Default / Name / Type / Value / Weight). Right-aligned.
	_sort_btn = Button.new()
	_sort_btn.focus_mode = Control.FOCUS_NONE
	_sort_btn.text = ItemSort.button_text(_sort_mode)
	_sort_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_sort_btn.pressed.connect(_on_sort_pressed)
	vbox.add_child(_sort_btn)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

## One cell of the character-sheet HBox: a dim, body-sized Label (colour from the shared palette).
func _make_sheet_label() -> Label:
	var l := Label.new()
	l.add_theme_color_override(&"font_color", MenuStyle.dim_color())
	return l

## The faint "·" divider between the sheet's groups (level | stats | HP | zm).
func _make_sheet_sep() -> Label:
	var l := Label.new()
	l.text = "·"
	l.add_theme_color_override(&"font_color", MenuStyle.dim_color())
	return l

## Cycle the backpack list's display order (Default -> Name -> Type -> Value -> Weight) and rebuild.
func _on_sort_pressed() -> void:
	_sort_mode = ItemSort.next_mode(_sort_mode)
	_sort_btn.text = ItemSort.button_text(_sort_mode)
	_rebuild()

## Rebuild the item rows from the player's backpack. One button per stack; weapons are clickable (equip),
## consumables are clickable (use — a health pack heals), the currently-drawn weapon is marked, and
## anything else (ammo, junk) is shown disabled. Row text comes from the SHARED ItemRow formatter, so this
## list reads exactly like the loot + shop screens.
func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	# Carry-weight summary header: current / capacity, flagged + tinted red once ENCUMBERED (slowed).
	var enc: bool = _player.is_encumbered()
	var wl := Label.new()
	wl.text = "Weight: %.1f / %.1f%s" % [_player.inventory.total_weight(), _player.carry_capacity, "   — ENCUMBERED" if enc else ""]
	wl.add_theme_color_override(&"font_color", MenuStyle.danger() if enc else MenuStyle.dim_color())
	_list.add_child(wl)
	var equipped_item: Item = _player.inventory.equipped_item
	var stacks := ItemSort.sorted(_player.inventory.contents(), _sort_mode)
	if stacks.is_empty():
		var empty := Label.new()
		empty.text = "(empty)"
		empty.add_theme_color_override(&"font_color", MenuStyle.dim_color())
		_list.add_child(empty)
		return
	for s in stacks:
		var item: Item = s["item"]
		var count: int = s["count"]
		var is_equipped: bool = item.is_weapon() and item == equipped_item
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE  # mouse-driven menu: no keyboard focus, so Tab CLOSES instead of cycling rows
		# Shared, LABELED row language (ItemRow): "name  xN  ·  wt W  ·  ammo cal: M" — the same format the
		# loot + shop screens use, so every value on screen says what it is.
		var text := ItemRow.stack_text(item, count, _player.inventory)
		if is_equipped:
			text += "   (equipped — click to unequip)"
		elif item.is_consumable():
			text += "   (click to use)"
		btn.text = text
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = not (item.is_weapon() or item.is_consumable())  # weapons equip, consumables use
		# Hover the row's button to read the item's stats (weapons add their spare-ammo line) in the low-res
		# in-viewport tip. A disabled button still reports mouse_entered, so ammo/junk rows tip too.
		MenuStyle.attach_tip(btn, ItemInfo.tooltip(item, _player.inventory))
		# Track the hovered item so the hotbar can assign it to a slot when you press a number key (New Vegas).
		btn.mouse_entered.connect(func() -> void: _hovered_item = item)
		btn.mouse_exited.connect(func() -> void: if _hovered_item == item: _hovered_item = null)
		if item.is_weapon():
			btn.pressed.connect(_on_item_pressed.bind(item))
		elif item.is_consumable():
			btn.pressed.connect(_on_use_pressed.bind(item))
		row.add_child(btn)
		# Drop button — works for ANY item, including the weapon you're wielding: dropping the equipped gun
		# falls back to bare fists (via equipped_item_lost), so you can toss it on the ground and keep going.
		var drop_btn := Button.new()
		drop_btn.focus_mode = Control.FOCUS_NONE
		drop_btn.text = "Drop"
		drop_btn.pressed.connect(_on_drop_pressed.bind(item, count))
		row.add_child(drop_btn)
		_list.add_child(row)

func _on_item_pressed(item: Item) -> void:
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	if item == _player.inventory.equipped_item:
		_player.inventory.unequip()         # clicking the wielded weapon puts it away -> player falls back to fists
	else:
		_player.inventory.equip_item(item)  # -> equip_weapon_requested -> Player draws it (swap anim)
	_rebuild()                              # refresh the (equipped) marker

func _on_drop_pressed(item: Item, count: int) -> void:
	if is_instance_valid(_player):
		_player.drop_item(item, count)  # removes from the bag -> inventory.changed -> _rebuild refreshes the list

func _on_use_pressed(item: Item) -> void:
	if is_instance_valid(_player):
		_player.use_consumable(item)  # heals + consumes one -> inventory.changed -> _rebuild refreshes the stack
