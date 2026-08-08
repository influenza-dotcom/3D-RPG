extends CanvasLayer
## ShopScreen — the BUY / SELL overlay for trading with a Merchant. Autoload; PAUSES the world while open
## (like dialogue — this layer is PROCESS_MODE_ALWAYS so its buttons keep working through the pause); else
## clones the LootScreen / InventoryScreen pattern (frees the mouse on open; player control is suppressed via the
## is_open() gates). Two GRID columns SIDE-BY-SIDE (LootScreen-style): the MERCHANT'S STOCK on the left (click
## a tile to BUY one) and YOUR bag on the right (click to SELL one). DRAG a tile across into the other grid
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
## order IS the layout, so tidying has to physically move tiles. Prices are markup/markdown off item.value; the
## two column HEADINGS are the wallets (merchant's till over the stock, yours over your bag).
## Opened by Merchant.start_talk (standalone shop) or the dialogue "Trade" option (open_shop).
##
## AUTHORED SCENE: the static chrome lives in scenes/ui/shop_screen.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds it by %unique name in _bind_ui and applies the skin-driven
## look (MenuStyle style_* adopters + skin reads) on top, so a designer rearranges the panel in the editor
## and the skin keeps owning colours/fonts/separations/width pins. The scene authors the 0.12 anchor band,
## the two side-by-side columns and the scroll slots; the two GridInventoryView components stay
## code-instantiated into the authored scrolls (they are runtime views bound to live inventories, not
## chrome). NO text is authored in the scene — every string is set here from PlayerText (l10n + the
## text-debt ratchet own strings, never a .tscn). tests/test_shop_screen_scene.gd pins the wiring.

signal opened
signal closed

const _DEFAULT_HINT := ""  ## resting detail line: BLANK — how-to-use prose is tutorializing (user call); prices speak on hover

var _root: Control
var _title: Label
var _money_merchant: Label  ## merchant's wallet — doubles as the STOCK column's heading
var _money_player: Label    ## your wallet — doubles as YOUR column's heading
var _stock_grid: GridInventoryView  ## the merchant's stock as a grid — click a tile to BUY one, drag it into your grid to buy it into that slot
var _player_grid: GridInventoryView ## your bag as a grid — click to SELL one, drag into the stock grid to sell
var _detail: Label                  ## hovered item's breakdown + its price (a grid cell has no price column)
var _sort_btn: Button
## The order the Sort button REPACKS both grids into. On a list this reordered rows for display only; on a grid
## the order IS the layout, so cycling it physically tidies the tiles (CharacterInventory.repack).
var _sort_mode: int = ItemSort.Mode.DEFAULT
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _merchant: Node = null  ## a Merchant — typed as Node to avoid a Merchant<->ShopScreen class cycle (Merchant calls ShopScreen.open_shop); its shop API is called dynamically

func _ready() -> void:
	layer = 121                                  # peer of the other modal overlays (loot / inventory)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_ui()
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
	# it pays. PLAYER dims, not the 10x8 container dims: the two columns share one cell scale, and a 10-wide
	# shelf in a half-panel column mathematically caps BOTH grids at ~23px cells — cramped tiles in a mostly
	# empty panel (screenshot QA). A 6x5 shelf renders ~40px tiles; an over-authored stock's tail lands in the
	# click-only overflow strip rather than shrinking every tile on screen.
	var stock_inv: CharacterInventory = stock_v
	if not stock_inv.grid_enabled():
		stock_inv.enable_grid(GameSettings.inventory.grid_cols, GameSettings.inventory.grid_rows)
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
	_detail.add_theme_color_override(&"font_color", MenuStyle.dim_color())  # hover may have brightened it (see _on_hover)
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
	# Your wallet re-tints per sign (gold, or danger while in debt); the merchant till never goes negative
	# (Merchant.sell gates on it), so its heading keeps the bind-time gold.
	_money_player.add_theme_color_override(&"font_color", MenuStyle.wallet_color(_player.money))
	_sync_cell_sizes.call_deferred()  # first open: the root was hidden — sizes settle a frame after visible

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
## (bound per grid in _bind_ui) picks buy-side vs sell-side, and whether the deal is currently affordable —
## the readable replacement for the old rows' disabled state, since a tile can't grey itself out.
func _on_hover(item: Item, from_stock: bool = false) -> void:
	# Full brightness while inspecting an item, dim while showing the idle hint (InventoryScreen parity) — the
	# price/affordability line is a read-this-now readout, not a footnote.
	if item == null or not is_instance_valid(_merchant) or not is_instance_valid(_player):
		_detail.add_theme_color_override(&"font_color", MenuStyle.dim_color())
		_detail.text = _DEFAULT_HINT
		return
	var holder: CharacterInventory = _merchant_stock() if from_stock else _player.inventory
	var body := ItemInfo.tooltip(item, holder)
	var price: float = _merchant.buy_price(item, _player) if from_stock else _merchant.sell_price(item, _player)
	var affordable: bool
	if from_stock:
		affordable = price > 0.0 and _player.can_pay(price)  # the SAME predicate Merchant.buy gates on
	else:
		affordable = price > 0.0 and _merchant_money() >= price
	_detail.add_theme_color_override(&"font_color", MenuStyle.text_color())
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

# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/shop_screen.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. The scene owns
## STRUCTURE (the 0.12 anchor band, the title row, the two columns + scroll slots, the clip footer); the
## skin keeps owning LOOK — every colour/font/separation/width budget below is a MenuStyle/skin read, so
## reskinning via resources/ui/menu_skin.tres still restyles this screen with zero scene edits.
func _bind_ui() -> void:
	_root = %Root
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)

	var vbox: VBoxContainer = %VBox
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared vertical rhythm across every panel screen

	# Title ROW (authored in the scene) — the tracked title stays optically centred between two equal FIXED
	# flanks: a spacer on the left mirroring the Sort button's fixed width on the right. Folding the sort
	# control onto this line (instead of its own row) hands its former row height to the grid columns below.
	# Both flank widths are the SKIN's sort_button_width budget, so they're stamped here, never authored.
	(%TitleSpacer as Control).custom_minimum_size.x = float(MenuStyle.skin.sort_button_width)
	_title = %Title
	MenuStyle.style_title(_title)  # title font/size/colour + ellipsis from the skin
	_title.text = MenuStyle.title_text(PlayerText.SHOP_TITLE)  # open_shop re-titles per merchant
	# Sort control — cycles the repack order of BOTH grids (Default / Name / Type / Value / Weight). A FIXED min
	# width (+ clip_text, authored in the scene alongside cap_button here) pins BOTH button edges so the
	# footprint never shifts as the caption cycles between "Sort: Default" (longest) and "Sort: Name".
	_sort_btn = MenuStyle.cap_button(%SortButton)
	_sort_btn.text = ItemSort.button_text(_sort_mode)
	_sort_btn.custom_minimum_size.x = float(MenuStyle.skin.sort_button_width)  # ≥ the widest ENGLISH caption ("Sort: Default") so the width never changes with the mode; per-locale skin budget
	_sort_btn.pressed.connect(_on_sort_pressed)

	# The two grid sections sit SIDE-BY-SIDE (the LootScreen layout, authored in the scene) — stock column
	# left, your bag right. The old vertical stack split ~84px of scroll slot between grids needing 176px
	# (10x8 stock) + 110px (6x5 bag), so both lived permanently in the scrollbar fallback with ~75% of stock
	# hidden. Geometry at the design 792x444 canvas (0.12 anchors, 16px panel margins → ~570x305 inner):
	# per-column slot ≈ 305 - title 21 - heading 19 - footer 60 - separations ≈ 182px, so the 10x8 stock fits
	# whole at 22px cells (176px); column width (570-8)/2 = 281 fits 10 columns at 28px. The wallet HEADINGS
	# are LEFT-aligned full-width labels, so amounts grow rightward and the labels never move (no-shift rule).
	(%Columns as HBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.content_separation)
	_money_merchant = %StockWallet  # the column headings ARE the wallet readouts — _rebuild stamps their text
	_money_player = %PlayerWallet
	_style_wallet(_money_merchant)
	_style_wallet(_money_player)
	# The GridInventoryView components stay CODE-instantiated into the authored scroll slots — they are live
	# runtime views (bound per open to a merchant's stock / your bag), not static chrome for the editor.
	_stock_grid = _adopt_grid_section(%StockColumn, %StockScroll)
	_player_grid = _adopt_grid_section(%PlayerColumn, %PlayerScroll)
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

	# Detail line under both grids (footer + label authored in the scene) — the hovered item's breakdown PLUS
	# its price, which is where prices live now that rows became tiles (a grid cell has no room for a price
	# column). Fixed-height clip host so a long tooltip can't grow the footer and squeeze the grids above it
	# (the InventoryScreen / LootScreen construct); the height budget is skin-derived, so it's stamped here.
	var footer: Control = %Footer
	footer.custom_minimum_size.y = 4 * (MenuStyle.skin.hint_size + 4)  # same 4-line clip host as the loot screen's
	_detail = %Detail
	MenuStyle.style_hint(_detail)  # dim wrap-friendly footnote styling from the skin
	_detail.text = _DEFAULT_HINT

## Adopt one authored grid COLUMN — `column` (wallet heading + scroll slot, authored in the scene) gets the
## skin separation, and a code-instantiated GridInventoryView is parented into its `scroll` slot (the
## LootScreen shape). The heading IS the wallet readout, so it carries no static caption — _rebuild stamps
## it via the PlayerText wallet composers. The scroll is only the too-short-window fallback: its resized
## hook hands the grid the slot's height as its max_view_height budget, so at the design canvas both grids
## render whole, no scrollbars.
func _adopt_grid_section(column: VBoxContainer, scroll: ScrollContainer) -> GridInventoryView:
	column.add_theme_constant_override("separation", MenuStyle.skin.content_separation)
	var grid := GridInventoryView.new()
	scroll.add_child(grid)
	scroll.resized.connect(_on_grid_slot_resized.bind(scroll, grid))  # bound method, not a lambda (freed-capture safety)
	return grid

## Hand the grid its real vertical budget whenever its scroll slot resizes, so cells shrink to fit all rows
## instead of overflowing into a permanent scrollbar (the LootScreen hook, same reasoning); then re-sync BOTH
## columns' cell sizes — a one-sided budget change must not let the two grids drift apart.
func _on_grid_slot_resized(scroll: ScrollContainer, grid: GridInventoryView) -> void:
	if is_instance_valid(scroll) and is_instance_valid(grid):
		grid.max_view_height = int(scroll.size.y)
		# Deferred for the same one-frame layout lag as LootScreen's hook (size.x reads 0 mid-pass; a
		# synchronous sync sticks the shared cap at the 22px minimum — caught by screenshot QA).
		_sync_cell_sizes.call_deferred()

## Cap both views to the SMALLER of their natural cell sizes so the same item renders the same size on either
## side of the counter (LootScreen's _sync_cell_sizes, same reasoning) — left to fit independently, the 10x8
## stock lands at ~22px beside a ~36px bag and the drag preview balloons mid-flight.
func _sync_cell_sizes() -> void:
	if _stock_grid == null or _player_grid == null:
		return
	# Just refresh both: each view's _recompute_cell PULLS min(own, partner) natural fit live (see the
	# pull-based note in grid_inventory_view.gd — a host-pushed cap froze at the 22px minimum because both
	# push points fired mid-layout with sizes still 0).
	_stock_grid.refresh()
	_player_grid.refresh()

## Style an authored wallet readout doubling as its column's HEADING: gold, header-sized, LEFT-aligned over
## its grid (left-alignment + the ellipsis trim — a huge amount trims instead of widening the column — are
## authored in the scene; the skin font size + gold are applied here). NOT centred: these labels restamp on
## every transaction, and a centred label re-flows every glyph whenever the amount changes width ("100 zm"
## -> "87.5 zm") — a per-purchase wobble exactly where the eye is parked (menus-don't-shift rule; the loot
## screen's centred headings are static per-open text, a false precedent). Left-aligned, the caption words
## never move and digits grow rightward from a pinned edge.
func _style_wallet(l: Label) -> void:
	l.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	l.add_theme_color_override(&"font_color", MenuStyle.gold())  # bind-time default; _rebuild re-tints YOUR wallet danger while in debt
