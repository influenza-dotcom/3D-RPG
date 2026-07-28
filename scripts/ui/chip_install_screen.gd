extends CanvasLayer
## ChipInstallScreen — the INSTALL overlay for a ChipInstaller mechanic. Autoload; PAUSES the world while open
## (like ShopScreen / dialogue — this layer is PROCESS_MODE_ALWAYS so its buttons keep working through the pause).
## Two full-width sections STACKED vertically (ShopScreen-style): INSTALL YOUR CHIPS on top (chips already in the
## backpack — click to install for the labour fee) and FOR SALE — BUY & INSTALL below (chips the mechanic stocks
## that you don't carry — click to buy the chip AND fit it in one payment). Installing consumes the chip and calls
## Player.unlock_mechanic, so the ability comes online immediately.
## Opened by ChipInstaller.start_talk (standalone) or the dialogue "Install" option (open_install).

signal opened
signal closed

const PANEL_MARGIN := 0.12

var _root: Control
var _title: Label
var _money_player: Label       ## your wallet — the header readout
var _carried_list: VBoxContainer
var _stock_list: VBoxContainer
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _installer: Node = null    ## a ChipInstaller — typed as Node to avoid a ChipInstaller<->ChipInstallScreen class cycle (the installer calls open_install); its API is called dynamically

func _ready() -> void:
	layer = 121                                  # peer of the other modal overlays (loot / shop / inventory)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

# ---------------------------------------------------------------------------------------------------
# Open / close
# ---------------------------------------------------------------------------------------------------

## Open the install screen for `installer`, serving `player`. Refuses to stack over another modal / dialogue, and
## bails safely on an invalid installer (a stub without the install API) or no player. EVERY refuse path emits
## `closed` (via _refuse_open) so a dialogue-hosted open that suspended the conversation on our `closed` one-shot
## is never stranded (see below).
func open_install(installer: Node, player: Node) -> void:
	if _is_open or DialogueManager.is_active() or InputManager.any_modal_open(self):
		_refuse_open()
		return
	# Duck-typed guard (installer is Node-typed for the class cycle): a node WITHOUT the install surface reads as
	# not-an-installer and bails, never crashes.
	if not is_instance_valid(installer) or not installer.has_method(&"install_carried"):
		_refuse_open()
		return
	_player = player as Player
	if not is_instance_valid(_player) or _player.inventory == null:
		_refuse_open()
		return
	_installer = installer
	_bind(true)
	_is_open = true
	_prev_mouse_mode = ModalMenu.grab_mouse()
	var name_v: Variant = installer.get(&"installer_name")
	var nm: String = name_v if name_v is String else ""
	_title.text = MenuStyle.title_text(PlayerText.install_title(nm))
	_rebuild()
	_root.visible = true
	get_tree().paused = true  # freeze the world while installing, like the shop (PROCESS_MODE_ALWAYS keeps the buttons live)
	opened.emit()

## Guard failed: we never opened, but a dialogue-hosted open (DialogueManager._suspend_for_menu) suspended the
## conversation on our `closed` one-shot BEFORE calling us. Emit `closed` so _resume_from_menu re-shows the box;
## on the standalone path (ChipInstaller.start_talk) nothing is listening, so it is harmless. Do NOT touch
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
	_installer = null
	_player = null
	get_tree().paused = false  # resume the world (we paused it on open)
	closed.emit()

## (Dis)connect the signals that should refresh the rows: the player's bag (a chip installed / consumed), the
## mechanic's stock (a chip bought), and the player's unlock stream (the just-installed ability drops out of both
## lists). Idempotent connect/disconnect.
func _bind(on: bool) -> void:
	var srcs: Array = []
	if is_instance_valid(_player):
		if _player.inventory != null:
			srcs.append(_player.inventory.changed)
		srcs.append(_player.mechanic_unlocked)
	var stock := _installer_stock()
	if stock != null:
		srcs.append(stock.changed)
	for sig in srcs:
		if on and not sig.is_connected(_on_changed):
			sig.connect(_on_changed)
		elif not on and sig.is_connected(_on_changed):
			sig.disconnect(_on_changed)

func _on_changed(_a: Variant = null) -> void:
	if _is_open:
		_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	# Close on the SAME Interact key that opens it (the ray consumes the OPENING press), or on Esc.
	if _is_open and (event.is_action_pressed(InputManager.action_pickup) or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# Transactions + lists
# ---------------------------------------------------------------------------------------------------

## Install ONE carried `item` (ChipInstaller.install_carried gates on chip / not-installed / held / wallet).
func _install(item: Item) -> void:
	if is_instance_valid(_installer) and is_instance_valid(_player):
		_installer.install_carried(item, _player)  # the bound signals -> _rebuild refreshes the lists + wallet

## Buy & install ONE stocked `item` (ChipInstaller.buy_and_install gates on chip / not-installed / stock / wallet).
func _buy(item: Item) -> void:
	if is_instance_valid(_installer) and is_instance_valid(_player):
		_installer.buy_and_install(item, _player)

func _rebuild() -> void:
	if not is_instance_valid(_installer) or not is_instance_valid(_player):
		return
	_money_player.text = PlayerText.wallet_you(_player.money)
	_fill(_carried_list, _installer.installable_carried(_player), false)  # your chips -> INSTALL (fee)
	_fill(_stock_list, _installer.installable_stock(_player), true)       # shelf -> BUY & INSTALL

## The mechanic's stock inventory, type-guarded (a vanished / non-ChipInstaller node reads as null).
func _installer_stock() -> CharacterInventory:
	if not is_instance_valid(_installer):
		return null
	var raw: Variant = _installer.get(&"stock")
	return raw if raw is CharacterInventory else null

## Populate `list` with one Button per installable chip Item. is_buy rows BUY & install (priced at
## buy_and_install_cost); the carried rows INSTALL (priced at install_fee). Disabled when the wallet can't cover it.
func _fill(list: VBoxContainer, chips: Array, is_buy: bool) -> void:
	for c in list.get_children():
		c.queue_free()
	if chips.is_empty():
		list.add_child(MenuStyle.make_hint(PlayerText.INSTALL_NONE))
		return
	for item in chips:
		var it := item as Item
		if it == null:
			continue
		var price: int = _installer.buy_and_install_cost(it) if is_buy else _installer.install_fee(it)
		var affordable := price > 0 and _player.money >= float(price)
		list.add_child(_make_row(it, price, affordable, is_buy))

## One install row: a full-width Button carrying an HBox of two Labels — the chip name on the left (trims with
## "…" when long) and the PRICE as its own right-aligned column. Mirrors ShopScreen._make_row.
func _make_row(item: Item, price: int, affordable: bool, is_buy: bool) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.disabled = not affordable
	var sb: StyleBox = MenuStyle.theme.get_stylebox(&"normal", &"Button")
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = sb.content_margin_left
	row.offset_top = sb.content_margin_top
	row.offset_right = -sb.content_margin_right
	row.offset_bottom = -sb.content_margin_bottom
	btn.add_child(row)
	var name_l := Label.new()
	name_l.text = item.label()
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # a long name trims; the price column never moves
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_l.add_theme_color_override(&"font_color", MenuStyle.text_color() if affordable else MenuStyle.skin.disabled_text_color)
	row.add_child(name_l)
	var price_l := Label.new()
	price_l.text = Zorkmids.money_text(float(price))  # the whole money phrase — the "zm" word lives in Zorkmids.MONEY_TEMPLATE
	price_l.size_flags_horizontal = Control.SIZE_SHRINK_END
	price_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_l.custom_minimum_size.x = float(MenuStyle.skin.price_col_width)  # fixed-ish floor -> every row's price lands in one aligned column (skin budget, shared with ShopScreen)
	price_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_l.add_theme_color_override(&"font_color", MenuStyle.gold() if affordable else (MenuStyle.danger() if price > 0 else MenuStyle.dim_color()))
	row.add_child(price_l)
	# Hover a row to see the chip's derived breakdown — "Installs <Ability>" + weight/value (ItemInfo._effect_lines).
	# This IS the surface where you decide to fit a chip, so it must say what the chip unlocks, not just its [PH] name;
	# mirrors ShopScreen._make_row (a disabled, can't-afford row tips too). `_player.inventory` feeds the shared formatter.
	MenuStyle.attach_tip(btn, ItemInfo.tooltip(item, _player.inventory))
	if affordable:
		btn.pressed.connect((_buy if is_buy else _install).bind(item))
	return btn

# ---------------------------------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts)
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
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared vertical rhythm
	panel.add_child(vbox)

	_title = MenuStyle.make_title(PlayerText.INSTALL_SCREEN_TITLE)
	vbox.add_child(_title)

	# Wallet — one header readout (your zorkmids). Right-aligned, header-sized gold; row-inset so its right
	# edge lands on the rows' price column instead of overhanging it in the full panel box.
	_money_player = Label.new()
	_money_player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money_player.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_player.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	_money_player.add_theme_color_override(&"font_color", MenuStyle.gold())
	vbox.add_child(_row_inset(_money_player))

	# Two stacked full-width sections (ShopScreen shape): your chips on top (install), the shelf below (buy & install).
	_carried_list = _build_section(vbox, PlayerText.INSTALL_CARRIED_HEADING)
	_stock_list = _build_section(vbox, PlayerText.INSTALL_STOCK_HEADING)

## One full-width titled section (heading + scrolling row list); returns the VBox its rows are added to. Both
## sections' scrolls EXPAND vertically, so they share the leftover panel height 50/50. The heading is
## left-aligned and row-inset so its left edge sits over the rows' name column.
func _build_section(parent: VBoxContainer, heading: String) -> VBoxContainer:
	var head := Label.new()
	head.text = MenuStyle.title_text(heading)  # the single casing seam — headings case with their shop/loot siblings
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

## Wrap `c` in a MarginContainer whose left/right margins equal the theme Button's content inset, so a header
## element — a section heading, the wallet readout — lines up edge-for-edge with the name column (left) and
## price column (right) of the Button rows below it. This screen keeps left-aligned Button rows (unlike
## shop/loot, whose rows became centered grid tiles), which is why the inset idiom lives here now. Wraps only
## header/wallet elements, never the row Buttons — hit-testing is unaffected.
func _row_inset(c: Control) -> MarginContainer:
	var sb: StyleBox = MenuStyle.theme.get_stylebox(&"normal", &"Button")
	var m := MarginContainer.new()
	m.add_theme_constant_override(&"margin_left", int(sb.content_margin_left))
	m.add_theme_constant_override(&"margin_right", int(sb.content_margin_right))
	m.add_child(c)
	return m
