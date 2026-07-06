extends CanvasLayer
## ShopScreen — the BUY / SELL overlay for trading with a Merchant. Autoload; PAUSES the world while open
## (like dialogue — this layer is PROCESS_MODE_ALWAYS so its buttons keep working through the pause); else
## clones the LootScreen / InventoryScreen pattern (frees the mouse on open; player control is suppressed via the
## is_open() gates). Two columns: the MERCHANT'S STOCK (click to BUY one into you) and YOUR items (click to
## SELL one to the merchant). Prices are markup/markdown off item.value; a header shows both wallets.
## Opened by Merchant.start_talk (standalone shop) or the dialogue "Trade" option (open_shop).

signal opened
signal closed

const PANEL_MARGIN := 0.12

var _root: Control
var _title: Label
var _money_merchant: Label  ## merchant's wallet — left, over the BUY column
var _money_player: Label    ## your wallet — right, over the SELL column
var _stock_list: VBoxContainer
var _player_list: VBoxContainer
var _sort_btn: Button
var _sort_mode: int = ItemSort.Mode.DEFAULT  ## display order of BOTH columns (cycled by the Sort button)
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _merchant: Node = null  ## a Merchant — typed as Node to avoid a Merchant<->ShopScreen class cycle (Merchant calls ShopScreen.open_shop); its shop API is called dynamically

func _ready() -> void:
	layer = 121                                  # peer of the other modal overlays (loot / inventory)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

# ---------------------------------------------------------------------------------------------------
# Open / close
# ---------------------------------------------------------------------------------------------------

## Open the shop for `merchant`, trading with `player`. Refuses to stack over another modal / dialogue, and
## bails safely on an invalid merchant or no player.
func open_shop(merchant: Node, player: Node) -> void:
	if _is_open or DialogueManager.is_active() or InputManager.any_modal_open(self):  # M5: refuse over ANY other menu (incl. QuestJournal)
		return
	# .get(), not bare access: `merchant` is Node-typed (the Merchant<->ShopScreen class cycle), so a merchant
	# WITHOUT a `stock` property (a stub / non-Merchant) reads as absent and bails, never crashes.
	if not is_instance_valid(merchant):
		return
	var stock_v: Variant = merchant.get(&"stock")
	if not (stock_v is CharacterInventory):
		return
	_player = player as Player
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	_merchant = merchant
	_bind(true)
	_is_open = true
	_prev_mouse_mode = ModalMenu.grab_mouse()
	var name_v: Variant = merchant.get(&"shop_name")
	var nm: String = name_v if name_v is String else ""
	_title.text = "TRADE — %s" % nm if not nm.is_empty() else "TRADE"
	_rebuild()
	_root.visible = true
	get_tree().paused = true  # freeze the world while trading, like dialogue (we're PROCESS_MODE_ALWAYS, so the buttons keep working through the pause)
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_bind(false)
	_is_open = false
	_root.visible = false
	ModalMenu.restore_mouse(_prev_mouse_mode)
	_merchant = null
	_player = null
	get_tree().paused = false  # resume the world (we paused it on open, like dialogue)
	closed.emit()

## (Dis)connect both inventories' `changed` so the columns + wallets refresh after every buy/sell.
func _bind(on: bool) -> void:
	var invs := [
		_merchant_stock(),
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
	# Close on the SAME Interact key that opens it (the ray consumes the OPENING press — see ray_cast.gd,
	# which skips interacting while we're open), or on Esc.
	if _is_open and (event.is_action_pressed(InputManager.action_pickup) or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# Transactions + lists
# ---------------------------------------------------------------------------------------------------

## Buy ONE `item` from the merchant (Merchant.buy gates on stock / price / the player's wallet).
func _buy(item: Item) -> void:
	if is_instance_valid(_merchant) and is_instance_valid(_player):
		_merchant.buy(item, _player)  # inventories' `changed` -> _rebuild refreshes the columns + wallets

## Sell ONE `item` to the merchant (Merchant.sell gates on the player holding it / price / the till).
func _sell(item: Item) -> void:
	if is_instance_valid(_merchant) and is_instance_valid(_player):
		_merchant.sell(item, _player)

func _rebuild() -> void:
	if not is_instance_valid(_merchant) or not is_instance_valid(_player) or _player.inventory == null:
		return
	_money_merchant.text = "Merchant: %s zm" % Zorkmids.fmt(_merchant_money())
	_money_player.text = "You: %s zm" % Zorkmids.fmt(_player.money)
	_fill(_stock_list, _merchant_stock(), true)    # merchant column -> BUY
	_fill(_player_list, _player.inventory, false)  # your column -> SELL

## The merchant's stock, type-guarded: a vanished merchant, or a Node-typed merchant without a `stock`
## property (a stub / non-Merchant), reads as null instead of crashing a bare `.stock` access.
func _merchant_stock() -> CharacterInventory:
	if not is_instance_valid(_merchant):
		return null
	var raw: Variant = _merchant.get(&"stock")
	return raw if raw is CharacterInventory else null

## The merchant's wallet, type-guarded the same way (absent / non-numeric `money` reads as 0).
func _merchant_money() -> float:
	if not is_instance_valid(_merchant):
		return 0.0
	var raw: Variant = _merchant.get(&"money")
	return float(raw) if raw is float or raw is int else 0.0

## Cycle the column sort order (Default -> Name -> Type -> Value -> Weight) and rebuild both columns.
func _on_sort_pressed() -> void:
	_sort_mode = ItemSort.next_mode(_sort_mode)
	_sort_btn.text = ItemSort.button_text(_sort_mode)
	_rebuild()

## Populate `list` from `inv`: one Button per stack. is_buy_col rows BUY from the merchant (priced at
## buy_price, disabled if you can't afford it); the player column SELLS (priced at sell_price, disabled when
## worthless or the till can't pay). The wielded weapon is tagged "(equipped)" but still sellable (you fall
## back to fists when it leaves your bag).
func _fill(list: VBoxContainer, inv: CharacterInventory, is_buy_col: bool) -> void:
	for c in list.get_children():
		c.queue_free()
	if inv == null:
		return
	var stacks := ItemSort.sorted(inv.contents(), _sort_mode)
	if stacks.is_empty():
		var empty := Label.new()
		empty.text = "(empty)"
		empty.add_theme_color_override(&"font_color", MenuStyle.dim_color())
		list.add_child(empty)
		return
	for s in stacks:
		var item: Item = s["item"]
		var count: int = s["count"]
		var price: float = _merchant.buy_price(item, _player) if is_buy_col else _merchant.sell_price(item, _player)
		# Shared, LABELED row language (ItemRow) — the same format as the backpack + loot screens — plus
		# this screen's labeled price.
		var text := ItemRow.stack_text(item, count, inv)
		text += "   —   price: %s zm" % Zorkmids.fmt(price)
		var affordable: bool
		if is_buy_col:
			affordable = price > 0 and _player.money >= price
		else:
			var is_equipped: bool = item.is_weapon() and item == _player.inventory.equipped_item
			if is_equipped:
				text += "   (equipped)"
			affordable = price > 0 and _merchant.money >= price  # worthless (0) items can't be sold
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true  # keep a long row from widening the column (and the whole panel) — full text is in the hover tip
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = text
		btn.disabled = not affordable
		# Hover a row to see the item's stats in the low-res tip (a disabled, can't-afford row tips too);
		# `inv` is the bag this row belongs to (merchant or player), for the weapon spare-ammo readout.
		MenuStyle.attach_tip(btn, ItemInfo.tooltip(item, inv))
		if affordable:
			btn.pressed.connect((_buy if is_buy_col else _sell).bind(item))
		list.add_child(btn)

# ---------------------------------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
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

	_title = MenuStyle.make_title("Trade")
	vbox.add_child(_title)

	# Wallets — each sits OVER its own column: merchant (left, above the buy column), you (right, above sell).
	var wallets := HBoxContainer.new()
	wallets.add_theme_constant_override("separation", 16)
	vbox.add_child(wallets)
	_money_merchant = _make_wallet(HORIZONTAL_ALIGNMENT_LEFT)
	wallets.add_child(_money_merchant)
	_money_player = _make_wallet(HORIZONTAL_ALIGNMENT_RIGHT)
	wallets.add_child(_money_player)

	# Sort button — cycles the display order of BOTH columns (Default / Name / Type / Value / Weight).
	_sort_btn = Button.new()
	_sort_btn.focus_mode = Control.FOCUS_NONE
	_sort_btn.text = ItemSort.button_text(_sort_mode)
	_sort_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sort_btn.pressed.connect(_on_sort_pressed)
	vbox.add_child(_sort_btn)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(columns)
	_stock_list = _build_column(columns, "For sale  (click to buy)")
	_player_list = _build_column(columns, "Your items  (click to sell)")

## A wallet readout: gold, header-sized, fills half the row so it aligns over its column.
func _make_wallet(align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	l.add_theme_color_override(&"font_color", MenuStyle.gold())
	return l

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
