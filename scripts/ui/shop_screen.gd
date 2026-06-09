extends CanvasLayer
## ShopScreen — the BUY / SELL overlay for trading with a Merchant. Autoload, non-pausing; clones the
## LootScreen / InventoryScreen pattern (frees the mouse on open; player control is suppressed via the
## is_open() gates). Two columns: the MERCHANT'S STOCK (click to BUY one into you) and YOUR items (click to
## SELL one to the merchant). Prices are markup/markdown off item.value; a header shows both wallets.
## Opened by Merchant.start_talk (standalone shop) or the dialogue "Trade" option (open_shop).

signal opened
signal closed

const PANEL_MARGIN := 0.12

var _root: Control
var _title: Label
var _money: Label
var _stock_list: VBoxContainer
var _player_list: VBoxContainer
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
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() or InventoryScreen.is_open() or LootScreen.is_open():
		return
	if not is_instance_valid(merchant) or merchant.stock == null:
		return
	_player = player as Player
	if not is_instance_valid(_player) or _player.inventory == null:
		return
	_merchant = merchant
	_bind(true)
	_is_open = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_title.text = "TRADE — %s" % merchant.shop_name if not merchant.shop_name.is_empty() else "TRADE"
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
	_merchant = null
	_player = null
	closed.emit()

## (Dis)connect both inventories' `changed` so the columns + wallets refresh after every buy/sell.
func _bind(on: bool) -> void:
	var invs := [
		_merchant.stock if is_instance_valid(_merchant) else null,
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
	_money.text = "Your zorkmids: %d        Merchant: %d zm" % [_player.money, _merchant.money]
	_fill(_stock_list, _merchant.stock, true)    # merchant column -> BUY
	_fill(_player_list, _player.inventory, false)  # your column -> SELL

## Populate `list` from `inv`: one Button per stack. is_buy_col rows BUY from the merchant (priced at
## buy_price, disabled if you can't afford it); the player column SELLS (priced at sell_price, disabled when
## worthless or the till can't pay). The wielded weapon is tagged "(equipped)" but still sellable (you fall
## back to fists when it leaves your bag).
func _fill(list: VBoxContainer, inv: CharacterInventory, is_buy_col: bool) -> void:
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
		var price: int = _merchant.buy_price(item) if is_buy_col else _merchant.sell_price(item)
		var text := item.label()
		if count > 1:
			text += "  x%d" % count
		text += "   —   %d zm" % price
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
		btn.text = text
		btn.disabled = not affordable
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
	_title.text = "TRADE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_title)

	_money = Label.new()
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_money.add_theme_font_size_override("font_size", 15)
	_money.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.4))  # gold-ish zorkmid tint
	vbox.add_child(_money)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(columns)
	_stock_list = _build_column(columns, "For sale  (click to buy)")
	_player_list = _build_column(columns, "Your items  (click to sell)")

	var hint := Label.new()
	hint.text = "Click an item to buy / sell one.   Esc to close."
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
