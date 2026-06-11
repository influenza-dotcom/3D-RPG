extends CanvasLayer
## LootScreen — the transfer overlay for LOOTING a corpse or PICKPOCKETING a live NPC. Autoload,
## non-pausing, clones the InventoryScreen / OptionsMenu pattern (frees the mouse on open; player control
## is suppressed via the is_open() gates). Two columns: the SOURCE's items (click one to TAKE all of it
## into the player) and the PLAYER's items (shown for context — transfer is one-way in v1). Opened by
## LootableCorpse.start_talk (open_for) or Talkable.start_talk while sneaking (pickpocket).

signal opened
signal closed

const PANEL_MARGIN := 0.12  ## fraction of the screen left as a border around the panel (any resolution)

var _root: Control
var _title: Label
var _corpse_list: VBoxContainer
var _player_list: VBoxContainer
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _source_inv: CharacterInventory = null  ## the inventory being looted / pickpocketed
var _free_when_empty: Node = null           ## a corpse to free when emptied; null for a LIVE source (pickpocket)
var _source_heading: Label = null           ## the SOURCE column's heading, retitled per-open ("Corpse" / "Pockets")
var _last_heading: Label = null             ## transient: the heading from the most recent _build_column call

func _ready() -> void:
	layer = 121                                  # above the HUD / inventory, peer of the modal overlays
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep working regardless of any pause
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

# ---------------------------------------------------------------------------------------------------
# Open / close
# ---------------------------------------------------------------------------------------------------

## Open the loot transfer for `corpse`, looting into `player`. Refuses to stack over another modal /
## dialogue, and bails safely on an invalid corpse or no player (start-menu / test safety).
func open_for(corpse: LootableCorpse, player: Node) -> void:
	if not is_instance_valid(corpse) or corpse.inventory == null:
		return
	var who := "LOOTING %s" % corpse.corpse_name if not corpse.corpse_name.is_empty() else "LOOTING"
	_open(corpse.inventory, corpse, player, who, "Corpse")

## Pickpocket a LIVE character: loot their inventory WITHOUT freeing them. Opened by Talkable.start_talk
## when the player is crouched and the NPC is unaware (off-guard).
func pickpocket(npc: Node, player: Node) -> void:
	if not is_instance_valid(npc):
		return
	var inv: Variant = npc.get(&"inventory")
	if not (inv is CharacterInventory):
		return
	var name_v: Variant = npc.get(&"display_name")
	var nm: String = name_v if name_v is String else ""
	var who := "PICKPOCKETING %s" % nm if not nm.is_empty() else "PICKPOCKETING"
	_open(inv, null, player, who, "Pockets")

## Open a persistent CONTAINER's inventory (a crate / chest / locker). Like open_for, but the container is
## NEVER freed when emptied — it's a fixture you can also deposit into. Opened by Container.start_talk.
func open_container(container: Node, player: Node) -> void:
	if not is_instance_valid(container):
		return
	var inv: Variant = container.get(&"inventory")
	if not (inv is CharacterInventory):
		return
	var name_v: Variant = container.get(&"container_name")
	var nm: String = name_v if name_v is String else ""
	var who := "LOOTING %s" % nm if not nm.is_empty() else "CONTAINER"
	_open(inv, null, player, who, "Container")

## Shared open: bind the source + player inventories, free the mouse, show the title + columns. Refuses to
## stack over another modal / dialogue, and bails on no source / no player.
func _open(source_inv: CharacterInventory, free_when_empty: Node, player: Node, title: String, source_heading: String) -> void:
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() or InventoryScreen.is_open():
		return
	if source_inv == null:
		return
	_player = player as Player
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	_source_inv = source_inv
	_free_when_empty = free_when_empty
	_bind(true)
	_is_open = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_title.text = title
	if _source_heading != null:
		_source_heading.text = source_heading
	_rebuild()
	_root.visible = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_bind(false)
	_is_open = false
	_root.visible = false
	Input.mouse_mode = _prev_mouse_mode
	_source_inv = null
	_free_when_empty = null
	_player = null
	closed.emit()

## (Dis)connect both inventories' `changed` so the two columns refresh on any transfer. is_instance_valid
## guards a corpse freed mid-loot; Godot also auto-drops the connection when a node frees.
func _bind(on: bool) -> void:
	var invs := [
		_source_inv if is_instance_valid(_source_inv) else null,
		_player.inventory if is_instance_valid(_player) else null,
	]
	for inv in invs:
		if inv == null:
			continue
		if on and not inv.changed.is_connected(_on_changed):
			inv.changed.connect(_on_changed)
		elif not on and inv.changed.is_connected(_on_changed):
			inv.changed.disconnect(_on_changed)

func _on_changed() -> void:
	if _is_open:
		_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	# Close on the SAME Interact key that opens it (the ray consumes the OPENING press, so this only fires on
	# a later press — see ray_cast.gd, which skips interacting while we're open), or on Esc.
	if _is_open and (event.is_action_pressed(InputManager.action_pickup) or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# Transfer + lists
# ---------------------------------------------------------------------------------------------------

## Take ALL of `item` from the corpse into the player. When the corpse is emptied, close + free it
## (nothing left to loot).
func _take(item: Item) -> void:
	if not is_instance_valid(_source_inv) or not is_instance_valid(_player) or _player.inventory == null:
		return
	_source_inv.transfer_to(_player.inventory, item, _source_inv.count_of(item))
	if _source_inv.is_empty():
		var emptied := _free_when_empty
		# Only a temporary CORPSE (free_when_empty != null) auto-closes + frees once looted dry. A persistent
		# CONTAINER (and a live pickpocket source) has free_when_empty == null: it STAYS OPEN showing "(empty)"
		# so you can keep depositing — close it manually with Esc / the interact key.
		if emptied != null:
			close()
			# A standalone corpse cleans itself up here; a skeleton-attached one is faded by its ragdoll.
			if is_instance_valid(emptied) and not (emptied.get_parent() is Ragdoll):
				emptied.queue_free()

## Deposit ALL of `item` from the player INTO the source container (the reverse of _take). Lets you stash
## gear into a corpse / crate — or plant items on a live NPC you're pickpocketing. Depositing the wielded
## weapon is allowed: you fall back to bare fists once it leaves the bag.
func _deposit(item: Item) -> void:
	if not is_instance_valid(_source_inv) or not is_instance_valid(_player) or _player.inventory == null:
		return
	# Depositing the weapon you're WIELDING is allowed: the transfer clears the backpack's equipped_item,
	# which fires equipped_item_lost -> the player falls back to bare fists. No need to swap first.
	_player.inventory.transfer_to(_source_inv, item, _player.inventory.count_of(item))

func _rebuild() -> void:
	# Both columns are clickable: TAKE from the source (left) into you, or DEPOSIT into it from your bag (right).
	_fill(_corpse_list, _source_inv if is_instance_valid(_source_inv) else null, _take, false)
	_fill(_player_list, _player.inventory if is_instance_valid(_player) else null, _deposit, true)

## Populate `list` from `inv`: each row is a Button that runs `on_click(item)` to move that whole stack (the
## source column takes INTO you; the player column deposits INTO the source). On the player column
## (`is_player_col`), the weapon you're WIELDING is tagged "(equipped)" but still depositable — stashing it
## drops you back to bare fists.
func _fill(list: VBoxContainer, inv: CharacterInventory, on_click: Callable, is_player_col: bool) -> void:
	for c in list.get_children():
		c.queue_free()
	if inv == null:
		return
	var stacks := inv.contents()
	if stacks.is_empty():
		var empty := Label.new()
		empty.text = "(empty)"
		empty.modulate = Color(1.0, 1.0, 1.0, 0.45)
		list.add_child(empty)
		return
	for s in stacks:
		var item: Item = s["item"]
		var count: int = s["count"]
		# Shared, LABELED row language (ItemRow) — the same format as the backpack + shop screens.
		var text := ItemRow.stack_text(item, count, inv)
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE  # mouse-driven: no Tab focus-cycling between rows
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var is_equipped: bool = is_player_col and item.is_weapon() and is_instance_valid(_player) \
				and _player.inventory != null and item == _player.inventory.equipped_item
		btn.text = (text + "   (equipped)") if is_equipped else text  # tag the wielded weapon, but keep it clickable
		btn.pressed.connect(on_click.bind(item))  # depositing the wielded weapon works now (player falls back to fists)
		list.add_child(btn)

# ---------------------------------------------------------------------------------------------------
# UI construction
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

	_title = Label.new()
	_title.text = "LOOTING"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(columns)
	_corpse_list = _build_column(columns, "Corpse")
	_source_heading = _last_heading  # remember the SOURCE heading so _open can retitle it ("Corpse" / "Pockets")
	_player_list = _build_column(columns, "You")

	var hint := Label.new()
	hint.text = "Click to move items between you and the container.   Esc to close."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)

## One titled, scrollable column; returns the VBox its rows are added to.
func _build_column(parent: HBoxContainer, heading: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	var head := Label.new()
	head.text = heading
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 16)
	col.add_child(head)
	_last_heading = head  # captured by _build_ui so the source column's heading can be retitled per-open
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	return list
