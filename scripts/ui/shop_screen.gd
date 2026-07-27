extends CanvasLayer
## ShopScreen — the BUY / SELL overlay for trading with a Merchant. Autoload; PAUSES the world while open
## (like dialogue — this layer is PROCESS_MODE_ALWAYS so its buttons keep working through the pause); else
## clones the LootScreen / InventoryScreen pattern (frees the mouse on open; player control is suppressed via the
## is_open() gates). Two full-width GRID sections STACKED vertically (LootScreen-style): the MERCHANT'S STOCK on
## top (click a tile to BUY one) and YOUR bag below (click to SELL one). DRAG a tile across into the other grid
## to trade it into the exact slot you aimed at — both routes funnel through Merchant.buy / Merchant.sell, so
## the price gates, the till and the bounded-bag guards are identical.
##
## PRICES LIVE IN THE DETAIL LINE. The rows used to be Buttons with their own right-aligned price column; a grid
## CELL has nowhere to put one, so the hovered item's price (and whether the deal is affordable — the readable
## replacement for a row's disabled state) is painted under the grids by PlayerText.shop_price_line. That is the
## deliberate trade of this screen: spatial, mesh-rendered stock that matches every other transfer surface, at
## the cost of seeing every price at once.
##
## The Sort button REPACKS both grids (CharacterInventory.repack) rather than reordering rows — on a grid the
## order IS the layout, so tidying has to physically move tiles. Prices are markup/markdown off item.value; a
## header shows both wallets.
## Opened by Merchant.start_talk (standalone shop) or the dialogue "Trade" option (open_shop).

signal opened
signal closed

const PANEL_MARGIN := 0.12
const _DEFAULT_HINT := PlayerText.SHOP_HINT  ## detail line when nothing is hovered

var _root: Control
var _title: Label
var _money_merchant: Label  ## merchant's wallet — left end of the header row
var _money_player: Label    ## your wallet — right end of the header row
var _stock_grid: GridInventoryView  ## the merchant's stock as a grid — click a tile to BUY one, drag it into your grid to buy it into that slot
var _player_grid: GridInventoryView ## your bag as a grid — click to SELL one, drag into the stock grid to sell
var _detail: Label                  ## hovered item's breakdown + its price (a grid cell has no price column)
var _sort_btn: Button
## The order the Sort button REPACKS both grids into. On a list this reordered rows for display only; on a grid
## the order IS the layout, so cycling it physically tidies the tiles (CharacterInventory.repack).
var _sort_mode: int = ItemSort.Mode.DEFAULT
var _btn_sb: StyleBox  ## the theme Button's "normal" stylebox — its content margins ARE the item-row inset that every header element (wallet / headings / sort) matches via _row_inset so the columns line up
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
## bails safely on an invalid merchant or no player. EVERY refuse path emits `closed` (via _refuse_open) so a
## dialogue-hosted open that suspended the conversation on our `closed` one-shot is never stranded (see below).
func open_shop(merchant: Node, player: Node) -> void:
	if _is_open or DialogueManager.is_active() or InputManager.any_modal_open(self):  # M5: refuse over ANY other menu (incl. QuestJournal)
		_refuse_open()
		return
	# .get(), not bare access: `merchant` is Node-typed (the Merchant<->ShopScreen class cycle), so a merchant
	# WITHOUT a `stock` property (a stub / non-Merchant) reads as absent and bails, never crashes.
	if not is_instance_valid(merchant):
		_refuse_open()
		return
	var stock_v: Variant = merchant.get(&"stock")
	if not (stock_v is CharacterInventory):
		_refuse_open()
		return
	_player = player as Player
	if not is_instance_valid(_player) or _player.inventory == null:
		_refuse_open()
		return
	_merchant = merchant
	# Give the STOCK a spatial grid on first open (lazily, once — a re-open keeps the layout), exactly as the
	# loot screen grids a container. Merchant stock is seeded UNBOUNDED so a big authored stock list never
	# truncates; bounding it only now means the shelf can fill up, which is why Merchant.sell transfers before
	# it pays. Container dims (the roomier of the two budgets) — a shop holds more than a pocket.
	var stock_inv: CharacterInventory = stock_v
	if not stock_inv.grid_enabled():
		stock_inv.enable_grid(GameSettings.inventory.container_grid_cols, GameSettings.inventory.container_grid_rows)
	_stock_grid.bind(stock_inv)
	_player_grid.bind(_player.inventory)
	_bind(true)
	_is_open = true
	_prev_mouse_mode = ModalMenu.grab_mouse()
	var name_v: Variant = merchant.get(&"shop_name")
	var nm: String = name_v if name_v is String else ""
	# Runtime re-title MUST route through title_text: make_title only cased its constructor argument, so a
	# lowercase merchant name would otherwise break the skin's tracked-uppercase title look.
	_title.text = MenuStyle.title_text(PlayerText.shop_title(nm))
	_rebuild()
	_root.visible = true
	get_tree().paused = true  # freeze the world while trading, like dialogue (we're PROCESS_MODE_ALWAYS, so the buttons keep working through the pause)
	opened.emit()

## Guard failed: we never opened, but a dialogue-hosted open (DialogueManager._suspend_for_menu) suspended the
## conversation on our `closed` one-shot BEFORE calling us. Emit `closed` so _resume_from_menu re-shows the box;
## on the standalone path (Merchant.start_talk) nothing is listening, so it is harmless. Do NOT touch
## pause/mouse/_is_open here — none of that was mutated yet.
func _refuse_open() -> void:
	closed.emit()

func close() -> void:
	if not _is_open:
		return
	_bind(false)
	_is_open = false
	_root.visible = false
	ModalMenu.restore_mouse(_prev_mouse_mode)
	# Drop the bound bags so the views never hold a stale reference after close (and any in-flight drag is
	# cancelled by bind's _cancel_drag). The stock KEEPS its grid — like a container, its layout persists.
	_stock_grid.bind(null)
	_player_grid.bind(null)
	_detail.text = _DEFAULT_HINT
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
	_money_merchant.text = PlayerText.wallet_merchant(_merchant_money())
	_money_player.text = PlayerText.wallet_you(_player.money)
	_stock_grid.refresh()
	_player_grid.refresh()

## Click a STOCK tile -> buy ONE of it (same as the old row press). The grid emits activate_requested.
func _on_stock_activate(item: Item) -> void:
	if item != null:
		_buy(item)

## Click one of YOUR tiles -> sell ONE of it to the merchant.
func _on_player_activate(item: Item) -> void:
	if item != null:
		_sell(item)

## DRAG a stock tile into your grid -> BUY it and drop it on the cell you aimed at. Routed through _buy (not a
## bespoke transfer) so Merchant.buy still owns the price gate, the wallet check and the bounded-bag guard; a
## refused purchase simply leaves no new stack for place_transferred to find.
func _on_stock_transfer(item: Item, _key: int, cell: Vector2i, w: int, h: int) -> void:
	if item == null or not is_instance_valid(_player) or _player.inventory == null:
		return
	var before := _player.inventory.stack_keys()
	_buy(item)
	_player_grid.place_transferred(before, cell, w, h)

## DRAG one of your tiles into the stock grid -> SELL it, landing on the aimed cell of the merchant's grid.
func _on_player_transfer(item: Item, _key: int, cell: Vector2i, w: int, h: int) -> void:
	var stock := _merchant_stock()
	if item == null or stock == null:
		return
	var before := stock.stack_keys()
	_sell(item)
	_stock_grid.place_transferred(before, cell, w, h)

## Either grid's hover changed -> show that item's breakdown plus the PRICE it would trade at. `from_stock`
## (bound per grid in _build_ui) picks buy-side vs sell-side, and whether the deal is currently affordable —
## the readable replacement for the old rows' disabled state, since a tile can't grey itself out.
func _on_hover(item: Item, from_stock: bool = false) -> void:
	if item == null or not is_instance_valid(_merchant) or not is_instance_valid(_player):
		_detail.text = _DEFAULT_HINT
		return
	var holder: CharacterInventory = _merchant_stock() if from_stock else _player.inventory
	var body := ItemInfo.tooltip(item, holder)
	var price: float = _merchant.buy_price(item, _player) if from_stock else _merchant.sell_price(item, _player)
	var affordable: bool
	if from_stock:
		affordable = price > 0.0 and _player.money >= price
	else:
		affordable = price > 0.0 and _merchant_money() >= price
	_detail.text = PlayerText.shop_price_line(body, price, from_stock, affordable)

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

## Cycle the sort order (Default -> Name -> Type -> Value -> Weight) and TIDY both grids into it. On the old
## list this reordered rows for display only; on a grid the order IS the layout, so sorting has to physically
## repack the tiles (CharacterInventory.repack) — otherwise the button would appear to do nothing.
func _on_sort_pressed() -> void:
	_sort_mode = ItemSort.next_mode(_sort_mode)
	_sort_btn.text = ItemSort.button_text(_sort_mode)
	_repack(_merchant_stock())
	if is_instance_valid(_player):
		_repack(_player.inventory)
	_rebuild()

## Repack one bag into the current sort order. ItemSort.sorted reorders the {item, count, key, …} rows from
## placed_contents (it only ever REORDERS the array, so each row keeps its stack `key`), and repack re-places
## the stacks in that key order, top-left first.
func _repack(inv: CharacterInventory) -> void:
	if inv == null or not inv.grid_enabled():
		return
	var order: Array = []
	for row in ItemSort.sorted(inv.placed_contents(), _sort_mode):
		order.append(int((row as Dictionary)["key"]))
	inv.repack(order)

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
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared vertical rhythm across every panel screen
	panel.add_child(vbox)

	# Item ROWS are Buttons whose inner name/price HBox is inset by this stylebox's content margins (see
	# _make_row). Capture it once so the header elements below (wallet row, section headings, sort control) can
	# share that EXACT inset via _row_inset — otherwise they sit in the wider panel-content box while every row
	# sits 9px in on each side, so the names hang right of their headings and the prices stop short of the wallet.
	_btn_sb = MenuStyle.theme.get_stylebox(&"normal", &"Button")

	# Title — tracked + centred across the full panel width. (The sort control sits right-aligned on its own line
	# below, not floating dead-centre as it used to.)
	_title = MenuStyle.make_title(PlayerText.SHOP_TITLE)
	vbox.add_child(_title)

	# Wallets — one header row: merchant left, you right. INSET to the item-row box so "Merchant" sits above the
	# first stock name and "You" sits directly above the sell-PRICE column (the sections below are stacked
	# full-width, so the two readouts share this line rather than sitting over side-by-side columns).
	var wallets := HBoxContainer.new()
	wallets.add_theme_constant_override("separation", 16)
	_money_merchant = _make_wallet(HORIZONTAL_ALIGNMENT_LEFT)
	wallets.add_child(_money_merchant)
	_money_player = _make_wallet(HORIZONTAL_ALIGNMENT_RIGHT)
	wallets.add_child(_money_player)
	vbox.add_child(_row_inset(wallets))

	# Sort control — cycles the display order of BOTH columns (Default / Name / Type / Value / Weight). RIGHT-
	# aligned (SHRINK_END pins it to the panel's right edge, over the price column / under the "You" wallet)
	# instead of floating centred over nothing. Its CAPTION is right-aligned too, so the glyphs' right edge lands
	# on the SAME price/wallet column (x≈668) as everything else — the Button's own 9px content margin brings the
	# text in from its 677px right edge. (A centred caption in this fixed-width button stopped ~26px short of that
	# column.) A FIXED min width (+ clip_text) pins BOTH button edges so the footprint never shifts as the caption
	# cycles between "Sort: Default" (longest) and "Sort: Name". NOT _row_inset here: the button's content margin
	# already supplies the inset, so wrapping it would double-count and pull the caption 9px in.
	_sort_btn = MenuStyle.cap_button(Button.new())
	_sort_btn.focus_mode = Control.FOCUS_NONE
	_sort_btn.text = ItemSort.button_text(_sort_mode)
	_sort_btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sort_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_sort_btn.custom_minimum_size.x = float(MenuStyle.skin.sort_button_width)  # ≥ the widest ENGLISH caption ("Sort: Default") so the width never changes with the mode; per-locale skin budget
	_sort_btn.pressed.connect(_on_sort_pressed)
	vbox.add_child(_sort_btn)

	# The two sections are STACKED VERTICALLY (LootScreen-style), not side-by-side: at the ~570px inner
	# panel width (792x444 canvas, 0.12 anchors, 16px panel padding) a half-width column is too narrow for a
	# usable grid. Stock on top (buy), your bag below (sell); the two scrolls split the leftover height evenly.
	_stock_grid = _build_grid_section(vbox, PlayerText.SHOP_FOR_SALE_HEADING)
	_player_grid = _build_grid_section(vbox, PlayerText.SHOP_YOUR_ITEMS_HEADING)
	_stock_grid.activate_requested.connect(_on_stock_activate)
	_player_grid.activate_requested.connect(_on_player_activate)
	# .bind(true/false) APPENDS a from_stock flag so the detail line knows WHICH price to quote — a shared Item
	# template (ammo you both carry) can't be told apart by identity alone.
	_stock_grid.hover_changed.connect(_on_hover.bind(true))
	_player_grid.hover_changed.connect(_on_hover.bind(false))
	# CROSS-GRID DRAG: drag stock into your bag to BUY it into the slot you aimed at, drag yours into the stock
	# to SELL. Both funnel through the same Merchant.buy / Merchant.sell the click path uses, so the price gates,
	# the till, the bounded-bag guards and the toasts are identical either way.
	_stock_grid.transfer_partner = _player_grid
	_player_grid.transfer_partner = _stock_grid
	_stock_grid.transfer_requested.connect(_on_stock_transfer)
	_player_grid.transfer_requested.connect(_on_player_transfer)

	# Detail line under both grids — the hovered item's breakdown PLUS its price, which is where prices live now
	# that rows became tiles (a grid cell has no room for a price column). Fixed-height clip host so a long
	# tooltip can't grow the footer and squeeze the grids above it (the InventoryScreen / LootScreen construct).
	var footer := Control.new()
	footer.custom_minimum_size.y = 4 * (MenuStyle.skin.hint_size + 4)  # same 4-line clip host as the loot screen's
	footer.clip_contents = true
	vbox.add_child(footer)
	_detail = MenuStyle.make_hint(_DEFAULT_HINT)
	_detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	footer.add_child(_detail)

## One full-width titled GRID section (heading + scrollable GridInventoryView), the LootScreen shape. Both
## scrolls EXPAND vertically so they split the leftover panel height 50/50; the scroll is only the
## too-short-window fallback — its resized hook hands the grid the slot height as its max_view_height budget.
func _build_grid_section(parent: VBoxContainer, heading: String) -> GridInventoryView:
	var head := Label.new()
	head.text = MenuStyle.title_text(heading)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	parent.add_child(_row_inset(head))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var grid := GridInventoryView.new()
	scroll.add_child(grid)
	scroll.resized.connect(_on_grid_slot_resized.bind(scroll, grid))  # bound method, not a lambda (freed-capture safety)
	return grid

## Hand the grid its real vertical budget whenever its scroll slot resizes, so cells shrink to fit all rows
## instead of overflowing into a permanent scrollbar (the LootScreen hook, same reasoning).
func _on_grid_slot_resized(scroll: ScrollContainer, grid: GridInventoryView) -> void:
	if is_instance_valid(scroll) and is_instance_valid(grid):
		grid.max_view_height = int(scroll.size.y)
		grid.refresh()

## Wrap `c` in a MarginContainer whose left/right margins equal the item-row content inset (_btn_sb's content
## margins), so a header element — the wallet row, a section heading, the sort control — lines up edge-for-edge
## with the name column (left) and price column (right) of the Button rows below it. Without this the headers
## sit in the full panel-content box while every row's content sits inset on each side (the theme Button's
## content margins), so names hang right of their headings and prices stop short of the wallet.
func _row_inset(c: Control) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override(&"margin_left", int(_btn_sb.content_margin_left))
	m.add_theme_constant_override(&"margin_right", int(_btn_sb.content_margin_right))
	m.add_child(c)
	return m

## A wallet readout: gold, header-sized; the two split the header row (merchant hugs left, you hug right).
func _make_wallet(align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = align
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # each wallet owns half the header row; a huge amount trims instead of overrunning into the other
	l.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	l.add_theme_color_override(&"font_color", MenuStyle.gold())
	return l
