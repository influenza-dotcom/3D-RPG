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

const PANEL_MARGIN := 0.18  ## fraction of the screen left as a border around the panel (any resolution)

var _root: Control
var _list: VBoxContainer
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

# ---------------------------------------------------------------------------------------------------
# Open / close — free the mouse, no SceneTree pause (control is suppressed via the is_open() gates)
# ---------------------------------------------------------------------------------------------------

func toggle() -> void:
	if _is_open:
		close()
	else:
		open()

func open() -> void:
	# Yield to dialogue and the settings menu — never stack two modal overlays / fight for the mouse.
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open():
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
	var theme := Theme.new()
	theme.default_font_size = 14
	_root.theme = theme
	add_child(_root)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.0, 0.0, 0.55)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dimmer)

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

	var title := Label.new()
	title.text = "INVENTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	var hint := Label.new()
	hint.text = "Click a weapon to equip.   Tab / Esc to close."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)

## Rebuild the item rows from the player's backpack. One button per stack; weapons are clickable (equip),
## the currently-drawn weapon is marked, and non-weapons are shown disabled (no consumables exist yet).
func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	var equipped: WeaponData = _player.weapon_system.equipped_weapon if _player.weapon_system != null else null
	var stacks := _player.inventory.contents()
	if stacks.is_empty():
		var empty := Label.new()
		empty.text = "(empty)"
		empty.modulate = Color(1.0, 1.0, 1.0, 0.5)
		_list.add_child(empty)
		return
	for s in stacks:
		var item: Item = s["item"]
		var count: int = s["count"]
		var btn := Button.new()
		var text := item.label()
		if count > 1:
			text += "  x%d" % count
		if item.is_weapon() and item.weapon == equipped:
			text += "   (equipped)"
		btn.text = text
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.disabled = not item.is_weapon()  # only weapons are actionable for now
		if item.is_weapon():
			btn.pressed.connect(_on_item_pressed.bind(item))
		_list.add_child(btn)

func _on_item_pressed(item: Item) -> void:
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	_player.inventory.equip_item(item)  # -> equip_weapon_requested -> Player draws it (swap anim)
	_rebuild()                          # refresh the (equipped) marker
