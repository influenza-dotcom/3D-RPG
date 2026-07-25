extends CanvasLayer
## ShopScreen — the BUY / SELL overlay for trading with a Merchant. Autoload; PAUSES the world while open
## (like dialogue — this layer is PROCESS_MODE_ALWAYS so its buttons keep working through the pause); else
## clones the LootScreen / InventoryScreen pattern (frees the mouse on open; player control is suppressed via the
## is_open() gates). Two full-width sections STACKED vertically (LootScreen-style): the MERCHANT'S STOCK on top
## (click to BUY one into you) and YOUR items below (click to SELL one to the merchant). Prices are
## markup/markdown off item.value; a header shows both wallets.
## Opened by Merchant.start_talk (standalone shop) or the dialogue "Trade" option (open_shop).

signal opened
signal closed

const PANEL_MARGIN := 0.12

var _root: Control
var _title: Label
var _money_merchant: Label  ## merchant's wallet — left end of the header row
var _money_player: Label    ## your wallet — right end of the header row
var _stock_list: VBoxContainer
var _player_list: VBoxContainer
var _sort_btn: Button
var _sort_mode: int = ItemSort.Mode.DEFAULT  ## display order of BOTH columns (cycled by the Sort button)
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
## Rows are UPDATED IN PLACE, not torn down: _rebuild runs on EVERY inventory `changed` (each buy/sell),
## and the old queue_free-everything rebuild freed the Button under the cursor — its hover chrome and the
## stat tooltip vanished for a beat after every single transaction (Godot only re-delivers mouse_entered
## when the mouse moves). Reusing the node keeps hover + tip alive; only the row-count DELTA is added or
## freed, so a vanished stack still slides later rows up — that's a genuinely shorter list, not churn.
func _fill(list: VBoxContainer, inv: CharacterInventory, is_buy_col: bool) -> void:
	var rows: Array[Button] = []
	for c in list.get_children():
		# A buy fires `changed` on BOTH bags, so _rebuild can run twice a frame: rows this pass queued to
		# free are still children on the next pass — the is_queued_for_deletion check keeps them out of the
		# reuse pool. The non-Button child is the empty-state hint from a prior fill.
		if c is Button and not c.is_queued_for_deletion():
			rows.append(c as Button)
		else:
			c.queue_free()
	var stacks: Array = ItemSort.sorted(inv.contents(), _sort_mode) if inv != null else []
	if stacks.is_empty():
		for r in rows:
			r.queue_free()
		if inv != null:
			# Centred + dim + hint-sized, the same empty-state voice as every other screen's footnotes.
			list.add_child(MenuStyle.make_hint(PlayerText.EMPTY_LIST))
		return
	for i in stacks.size():
		var s: Dictionary = stacks[i]
		var item: Item = s["item"]
		var count: int = s["count"]
		var price: float = _merchant.buy_price(item, _player) if is_buy_col else _merchant.sell_price(item, _player)
		# Shared, LABELED row language (ItemRow) — the same format as the backpack + loot screens; the
		# price rides in its OWN right-aligned label (see _make_row), not appended to this string.
		var text := ItemRow.stack_text(item, count, inv)
		var affordable: bool
		if is_buy_col:
			affordable = price > 0 and _player.money >= price
		else:
			var is_equipped: bool = item.is_weapon() and item == _player.inventory.equipped_item
			if is_equipped:
				text += PlayerText.EQUIPPED_SUFFIX
			affordable = price > 0 and _merchant.money >= price  # worthless (0) items can't be sold
		if i < rows.size():
			_update_row(rows[i], item, inv, text, price, affordable, is_buy_col)
		else:
			list.add_child(_make_row(item, inv, text, price, affordable, is_buy_col))
	for j in range(stacks.size(), rows.size()):
		rows[j].queue_free()

## One shop row: a full-width Button (keeps the theme's hover/click chrome, the pressed wiring and the hover
## tip) carrying an HBox of two Labels — name/detail on the left (trims with "…" when long) and the PRICE as
## its own right-aligned column that can NEVER clip. The old single-string button ellipsized from the RIGHT,
## i.e. exactly where the price sat ("ammo grenades: 0 — pric"), hiding the one thing a shop row must show.
## Both labels are MOUSE_FILTER_IGNORE so hovers/clicks fall through to the Button.
func _make_row(item: Item, inv: CharacterInventory, text: String, price: float, affordable: bool, is_buy_col: bool) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.disabled = not affordable
	# The empty Button still reserves one text line (same theme font/size as the Labels inside), so the
	# full-rect HBox always fits vertically. Inset it by the button stylebox's content margins so the name
	# starts where button text would (clear of the theme's 2px left accent bar on hover). The SAME stylebox
	# feeds _row_inset, so the wallet / headings / sort share this exact inset and the columns line up.
	var sb: StyleBox = _btn_sb
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = sb.content_margin_left
	row.offset_top = sb.content_margin_top
	row.offset_right = -sb.content_margin_right
	row.offset_bottom = -sb.content_margin_bottom
	btn.add_child(row)
	var name_l := Label.new()
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # a long name trims; the price column never moves
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_l)
	var price_l := Label.new()
	price_l.size_flags_horizontal = Control.SIZE_SHRINK_END
	price_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_l.custom_minimum_size.x = 80  # fixed-ish floor -> every row's price lands in one aligned right column
	price_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(price_l)
	# The update path needs the two labels back without walking the Button's child tree.
	btn.set_meta(&"_name_l", name_l)
	btn.set_meta(&"_price_l", price_l)
	_update_row(btn, item, inv, text, price, affordable, is_buy_col)
	return btn

## Retext/rewire one LIVE row Button for (a possibly different) item — every per-stack property lives here so
## _fill can reuse the node across rebuilds instead of freeing it. The trade Callable is remembered in meta so
## exactly THIS connection can be swapped per item/affordability — `pressed` also carries MenuStyle's
## click-sound wiring, so a blanket disconnect-everything would mute the row.
func _update_row(btn: Button, item: Item, inv: CharacterInventory, text: String, price: float, affordable: bool, is_buy_col: bool) -> void:
	btn.disabled = not affordable
	var name_l := btn.get_meta(&"_name_l") as Label
	name_l.text = text
	# Labels don't inherit the Button's disabled font colour, so mirror it by hand on can't-trade rows.
	name_l.add_theme_color_override(&"font_color", MenuStyle.text_color() if affordable else MenuStyle.skin.disabled_text_color)
	var price_l := btn.get_meta(&"_price_l") as Label
	price_l.text = "%s zm" % Zorkmids.fmt(price)
	# Gold = tradeable now; danger = a real price the wallet/till can't cover; dim = worthless (0 zm).
	price_l.add_theme_color_override(&"font_color", MenuStyle.gold() if affordable else (MenuStyle.danger() if price > 0 else MenuStyle.dim_color()))
	# Hover a row to see the item's stats in the low-res tip (a disabled, can't-afford row tips too);
	# `inv` is the bag this row belongs to (merchant or player), for the weapon spare-ammo readout.
	# attach_tip is idempotent AND live-refreshes a currently-shown tip, so the hovered row's stats
	# (count, spare ammo) update mid-hover right after a transaction.
	MenuStyle.attach_tip(btn, ItemInfo.tooltip(item, inv))
	var old_cb: Variant = btn.get_meta(&"_trade_cb", null)
	if old_cb is Callable and btn.pressed.is_connected(old_cb):
		btn.pressed.disconnect(old_cb)
	btn.set_meta(&"_trade_cb", null)  # null DELETES the meta entry; re-set below when tradeable
	if affordable:
		var cb: Callable = (_buy if is_buy_col else _sell).bind(item)
		btn.pressed.connect(cb)
		btn.set_meta(&"_trade_cb", cb)

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
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared vertical rhythm across every panel screen
	panel.add_child(vbox)

	# Item ROWS are Buttons whose inner name/price HBox is inset by this stylebox's content margins (see
	# _make_row). Capture it once so the header elements below (wallet row, section headings, sort control) can
	# share that EXACT inset via _row_inset — otherwise they sit in the wider panel-content box while every row
	# sits 9px in on each side, so the names hang right of their headings and the prices stop short of the wallet.
	_btn_sb = MenuStyle.theme.get_stylebox(&"normal", &"Button")

	# Title — tracked + centred across the full panel width. (The sort control sits right-aligned on its own line
	# below, not floating dead-centre as it used to.)
	_title = MenuStyle.make_title("Trade")
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
	_sort_btn.custom_minimum_size.x = 128  # ≥ the widest caption ("Sort: Default") so the width never changes with the mode
	_sort_btn.pressed.connect(_on_sort_pressed)
	vbox.add_child(_sort_btn)

	# The two sections are STACKED VERTICALLY (LootScreen-style), not side-by-side: at the ~570px inner
	# panel width (792x444 canvas, 0.12 anchors, 16px panel padding) a half-width column clipped rows
	# mid-price. Full-width rows fit name + the aligned price column comfortably. Stock on top (buy),
	# your bag below (sell); the two scrolls split the remaining panel height evenly.
	_stock_list = _build_section(vbox, PlayerText.SHOP_FOR_SALE_HEADING)
	_player_list = _build_section(vbox, PlayerText.SHOP_YOUR_ITEMS_HEADING)

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

## One full-width titled section (heading + scrolling row list), LootScreen's _build_grid_section shape;
## returns the VBox its rows are added to. Both sections' scrolls EXPAND vertically, so they share the
## leftover panel height 50/50 and long stock lists scroll instead of growing the panel.
func _build_section(parent: VBoxContainer, heading: String) -> VBoxContainer:
	var head := Label.new()
	head.text = heading
	# LEFT-aligned AND inset (via _row_inset) so the heading text starts on the SAME x as the item-NAME column
	# below it (rows are name-left / price-right, and each row's content is inset by the Button's content margin).
	# Left-aligning alone still left the heading 9px to the left of the names — the header/row reference-frame
	# mismatch that was the bulk of the "doesn't line up" read; the inset closes it.
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	parent.add_child(_row_inset(head))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	return list
