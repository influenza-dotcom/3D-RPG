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
## Whatever carries the lootable WALLET: a LootableCorpse (its copied money) or a LIVE pickpocketed NPC
## (Character.money — yes, you can lift the cash straight out of their pocket). Null = no money to offer
## (containers). Read/zeroed dynamically; the "Take N zm" button shows while it holds anything.
var _money_source: Node = null
var _money_btn: Button = null
## The CHARACTER whose carry limit caps what the player can GIVE (deposit): a live exchange / pickpocket
## target. Null (corpses, containers) = unlimited dumping, as before. Read dynamically (carry_capacity).
var _capacity_owner: Node = null

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
	_open(corpse.inventory, corpse, player, who, "Corpse", corpse)

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
	# The live NPC's wallet is liftable too, and PLANTING items on them respects their carry limit.
	_open(inv, null, player, who, "Pockets", npc, npc)

## EXCHANGE GEAR with a FOLLOWING ALLY (the "Exchange Gear" dialogue option, offered only to companions
## actively following you — the gate lives in DialogueManager._speaker_exchange_npc): the same two-way
## transfer screen, no sneaking required — equipment only (no wallet button; robbing a friend's cash isn't
## "exchanging"), and what you GIVE is capped by their carry capacity.
func exchange(npc: Node, player: Node) -> void:
	if not is_instance_valid(npc):
		return
	var inv: Variant = npc.get(&"inventory")
	if not (inv is CharacterInventory):
		return
	var name_v: Variant = npc.get(&"display_name")
	var nm: String = name_v if name_v is String else ""
	var who := "EXCHANGING GEAR — %s" % nm if not nm.is_empty() else "EXCHANGING GEAR"
	_open(inv, null, player, who, "Their Gear", null, npc)

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
func _open(source_inv: CharacterInventory, free_when_empty: Node, player: Node, title: String, source_heading: String, money_source: Node = null, capacity_owner: Node = null) -> void:
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() or InventoryScreen.is_open() or ShopScreen.is_open() or HealScreen.is_open() or LevelUpScreen.is_open():
		return
	if source_inv == null:
		return
	_player = player as Player
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	_source_inv = source_inv
	_free_when_empty = free_when_empty
	_money_source = money_source
	_capacity_owner = capacity_owner
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
	_money_source = null
	_capacity_owner = null
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

## Take ALL of `item` from the corpse into the player. When the corpse is fully drained (no items AND no
## wallet left), close + free it — nothing left to loot.
func _take(item: Item) -> void:
	if not is_instance_valid(_source_inv) or not is_instance_valid(_player) or _player.inventory == null:
		return
	_source_inv.transfer_to(_player.inventory, item, _source_inv.count_of(item))
	_maybe_free_drained_corpse()

## Take the source's WALLET: the corpse's copied money, or a live pickpocket target's pocket cash. The
## nudge through on_wallet_drained lets the ragdoll's linger-until-drained fade see a cash-only loot end.
func _take_money() -> void:
	if not is_instance_valid(_player):
		return
	var amount := _source_money()
	if amount <= 0.0:
		return
	_money_source.set(&"money", 0.0)
	_player.add_money(amount)
	if _money_source is LootableCorpse:
		(_money_source as LootableCorpse).on_wallet_drained()
	_rebuild()
	_maybe_free_drained_corpse()

## The source's wallet, type-guarded: a vanished source, or one without a `money` property at all
## (a plain container / a test stub), reads as 0 instead of crashing float() on a null get().
func _source_money() -> float:
	if _money_source == null or not is_instance_valid(_money_source):
		return 0.0
	var raw: Variant = _money_source.get(&"money")
	return float(raw) if raw is float or raw is int else 0.0

## True once the source holds NOTHING — bag empty and no wallet cash left on the money source.
func _source_drained() -> bool:
	if is_instance_valid(_source_inv) and not _source_inv.is_empty():
		return false
	if _source_money() > 0.0:
		return false
	return true

## Close + free a fully drained temporary CORPSE (free_when_empty != null). A persistent CONTAINER (and a
## live pickpocket source) has free_when_empty == null: it STAYS OPEN showing "(empty)" so you can keep
## depositing — close it manually with Esc / the interact key.
func _maybe_free_drained_corpse() -> void:
	if not _source_drained():
		return
	var emptied := _free_when_empty
	if emptied != null:
		close()
		# A standalone corpse cleans itself up here; a skeleton-attached one is faded by its ragdoll.
		if is_instance_valid(emptied) and not (emptied.get_parent() is Ragdoll):
			emptied.queue_free()

## Deposit `item` from the player INTO the source (the reverse of _take) — the whole stack, except that a
## LIVE receiver (exchange / pickpocket-planting) takes only what fits under its CARRY CAPACITY: NPCs can't
## be given more than they can carry. Corpses / containers have no owner and accept anything, as before.
## Depositing the wielded weapon is allowed: you fall back to bare fists once it leaves the bag.
func _deposit(item: Item) -> void:
	if not is_instance_valid(_source_inv) or not is_instance_valid(_player) or _player.inventory == null:
		return
	var count := _player.inventory.count_of(item)
	if _capacity_owner != null and is_instance_valid(_capacity_owner):
		# .get(), not a direct access: the owner is duck-typed, and a receiver WITHOUT a
		# carry_capacity property (a stub / non-Character) is simply uncapped, like a container.
		var cap: Variant = _capacity_owner.get(&"carry_capacity")
		if cap is float or cap is int:
			count = _fits_under_capacity(item, count, _source_inv.total_weight(), float(cap))
			if count <= 0:
				if _player.has_method(&"notify_toast"):
					_player.notify_toast("They can't carry any more", Color(0.85, 0.85, 0.85))
				return
	# Depositing the weapon you're WIELDING is allowed: the transfer clears the backpack's equipped_item,
	# which fires equipped_item_lost -> the player falls back to bare fists. No need to swap first.
	_player.inventory.transfer_to(_source_inv, item, count)

## How many of `item` (holding `have`) still FIT under `capacity` for a receiver already carrying
## `load_weight` — the give-cap math, pure + static for the tests. Weightless items always fit; an
## already-over-capacity receiver takes nothing.
static func _fits_under_capacity(item: Item, have: int, load_weight: float, capacity: float) -> int:
	if item == null or have <= 0:
		return 0
	if item.weight <= 0.0:
		return have
	return clampi(int(floor((capacity - load_weight) / item.weight)), 0, have)

func _rebuild() -> void:
	# Both columns are clickable: TAKE from the source (left) into you, or DEPOSIT into it from your bag (right).
	_fill(_corpse_list, _source_inv if is_instance_valid(_source_inv) else null, _take, false)
	_fill(_player_list, _player.inventory if is_instance_valid(_player) else null, _deposit, true)
	# The wallet row: shown while the source carries cash (a corpse's pocketed money, or a live pickpocket
	# target's). Hidden for containers / drained sources.
	if _money_btn != null:
		# Use the existing type-guarded _source_money() helper rather than re-reading `money` off the Node with
		# a dead null-branch (Node.get() returns null only when absent — already handled as 0.0 in the helper).
		var cash := _source_money()
		_money_btn.visible = cash > 0.0
		_money_btn.text = "Take %s zm" % Zorkmids.fmt(cash)

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
		empty.add_theme_color_override(&"font_color", MenuStyle.dim_color())
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
		# Hover a row to see the item's breakdown in the low-res tip (weapon spare-ammo for this side's bag).
		MenuStyle.attach_tip(btn, ItemInfo.tooltip(item, inv))
		btn.pressed.connect(on_click.bind(item))  # depositing the wielded weapon works now (player falls back to fists)
		list.add_child(btn)

# ---------------------------------------------------------------------------------------------------
# UI construction
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

	_title = MenuStyle.make_title("LOOTING")  # dynamic title; _open reassigns _title.text per-open
	vbox.add_child(_title)

	# The wallet row — gold like the HUD's zorkmid readout; hidden until _rebuild finds cash on the source.
	_money_btn = Button.new()
	_money_btn.focus_mode = Control.FOCUS_NONE
	_money_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_money_btn.add_theme_color_override(&"font_color", MenuStyle.gold())
	_money_btn.visible = false
	_money_btn.pressed.connect(_take_money)
	vbox.add_child(_money_btn)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(columns)
	_corpse_list = _build_column(columns, "Corpse")
	_source_heading = _last_heading  # remember the SOURCE heading so _open can retitle it ("Corpse" / "Pockets")
	_player_list = _build_column(columns, "You")

## One titled, scrollable column; returns the VBox its rows are added to.
func _build_column(parent: HBoxContainer, heading: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	var head := Label.new()
	head.text = heading
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
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
