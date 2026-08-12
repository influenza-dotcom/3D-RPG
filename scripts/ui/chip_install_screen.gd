extends CanvasLayer
## ChipInstallScreen — the INSTALL overlay for a ChipInstaller mechanic. Autoload; REAL-TIME — it does NOT pause
## the world (the STATION-SCREEN rule, argued in full in the atm_screen.gd header; this layer is
## PROCESS_MODE_ALWAYS anyway, so a dialogue-hosted open keeps working under the conversation's pause).
## Two full-width sections STACKED vertically (ShopScreen-style): INSTALL YOUR CHIPS on top (chips already in the
## backpack — click to install for the labour fee) and FOR SALE — BUY & INSTALL below (chips the mechanic stocks
## that you don't carry — click to buy the chip AND fit it in one payment). Installing consumes the chip and calls
## Player.unlock_mechanic, so the ability comes online immediately.
## Opened by ChipInstaller.start_talk (standalone) or the dialogue "Install" option (open_install).
##
## AUTHORED SCENE: the layout lives in scenes/ui/chip_install_screen.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and applies the
## skin-driven look (MenuStyle style_* adopters) on top, so a designer rearranges the panel in the editor
## and the skin keeps owning colours/fonts/separations. NO text is authored in the scene — every string is
## set here from PlayerText (l10n + the text-debt ratchet own strings, never a .tscn). The per-chip rows are
## still BUILT AT RUNTIME (_fill/_make_row — content, not chrome); the scene authors only the two list
## containers they populate. tests/test_chip_install_screen_scene.gd pins the wiring.

signal opened
signal closed

const PANEL_MARGIN := 0.12  ## shared modal inset (matches shop/loot/chess chrome). The Panel's anchor fractions are AUTHORED in the scene; this const is the pin the scene test checks them against.

var _root: Control
var _title: Label
var _rail_btn: PaymentRailButton  ## DEBIT/CREDIT selector; rail_changed drives _rebuild (both chip lists re-price)
var _money_player: Label       ## your wallet — the header readout
var _carried_list: VBoxContainer
var _stock_list: VBoxContainer
var _first_focus: Button = null  ## first install row built by the LAST _rebuild = the pad landing spot open_install seeds (never a stale ref — the fills re-record it each rebuild, and the old rows are freed)
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _installer: Node = null    ## a ChipInstaller — typed as Node to avoid a ChipInstaller<->ChipInstallScreen class cycle (the installer calls open_install); its API is called dynamically

func _ready() -> void:
	layer = 121                                  # peer of the other modal overlays (loot / shop / inventory)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_ui()
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
	# ONE OPEN CUE, NEVER TWO (the station-screen idiom): a self-serve install booth answers with its OWN
	# diegetic StationSpeaker chirp, so the generic UI sting is suppressed exactly when that chirp fires and kept
	# when the mechanic is a person (no speaker). Past every refuse guard, so a booth that couldn't open never beeps.
	_prev_mouse_mode = ModalMenu.grab_mouse(not StationSpeaker.chirp(installer))
	var name_v: Variant = installer.get(&"installer_name")
	var nm: String = name_v if name_v is String else ""
	_title.text = MenuStyle.title_text(PlayerText.install_title(nm))
	_rebuild()
	_root.visible = true
	# Seed pad/keyboard focus on the first install row (the OptionsMenu `_first_focus` / SaveLoadScreen / AtmScreen
	# idiom; atm_screen.gd's ⭐CONTROLLER PARITY header carries the full argument) — AFTER the card is visible,
	# since grab_focus on a hidden Control does nothing. _rebuild above just re-recorded the landing spot; a
	# disabled first row (can't afford it) still HOLDS focus, so ui navigation starts there either way. When the
	# card has NO rows at all (nothing carried, nothing stocked — both lists hold hint Labels), the rail selector
	# is the one authored Button left and takes the seed instead: without a focus owner, navigation has nowhere
	# to start and every control on the card is pad-unreachable (the atm_screen must-not-recur rule).
	if is_instance_valid(_first_focus):
		_first_focus.grab_focus()
	elif is_instance_valid(_rail_btn):
		_rail_btn.grab_focus()
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
## SOUND: the SUCCESS cue lives on ChipInstaller._grant (the shared tail both transaction paths reach, past
## the charge), so only the REFUSAL is cued here — at the one place the installer's bool actually comes back.
## Splitting the pair across two files is deliberate: duplicating the commit here would double it, and
## duplicating the refusal into the installer would mean four `return false` sites to keep in sync.
func _install(item: Item) -> void:
	if is_instance_valid(_installer) and is_instance_valid(_player):
		if not _installer.install_carried(item, _player):  # the bound signals -> _rebuild refreshes the lists + wallet
			MenuStyle.play_denied()

## Buy & install ONE stocked `item` (ChipInstaller.buy_and_install gates on chip / not-installed / stock / wallet).
## Refusal cued here for the same reason as _install's — see its note.
func _buy(item: Item) -> void:
	if is_instance_valid(_installer) and is_instance_valid(_player):
		if not _installer.buy_and_install(item, _player):
			MenuStyle.play_denied()

func _rebuild() -> void:
	if not is_instance_valid(_installer) or not is_instance_valid(_player):
		return
	if _rail_btn != null:
		_rail_btn.refresh()  # the rail may have been flipped at an ATM since this screen was built
	_money_player.text = PlayerText.wallet_you(_player.money)
	_money_player.add_theme_color_override(&"font_color", MenuStyle.wallet_color(_player.money))  # gold, or danger while in debt
	_first_focus = null  # the fills below re-record it; holding the OLD first row would hand open_install a queue_freed Button
	_fill(_carried_list, _installer.installable_carried(_player), false)  # your chips -> INSTALL (fee)
	_fill(_stock_list, _installer.installable_stock(_player), true)       # shelf -> BUY & INSTALL
	# Re-seed the pad landing spot when THIS rebuild just destroyed it (the level_up_screen idiom): every
	# install / buy / rail flip funnels here and queue_frees the row that HELD focus, which would strand a pad
	# after one action. Only a DYING owner is stolen from — a player parked on the rail selector keeps their
	# place. The open-time rebuild lands here with the root still hidden, where grab_focus is a silent no-op —
	# open_install seeds again right after showing it.
	if _is_open and _root.is_inside_tree() and is_instance_valid(_first_focus):
		var focus_owner: Control = _root.get_viewport().gui_get_focus_owner()
		if focus_owner == null or _carried_list.is_ancestor_of(focus_owner) or _stock_list.is_ancestor_of(focus_owner):
			_first_focus.grab_focus()

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
		var affordable := price > 0 and _player.can_pay(float(price))  # the SAME predicate ChipInstaller gates on
		var row_btn := _make_row(it, price, affordable, is_buy)
		list.add_child(row_btn)
		if _first_focus == null:
			_first_focus = row_btn  # first row of the first non-empty list (carried fills before stock) = the pad landing spot

## One install row: a full-width Button carrying an HBox of two Labels — the chip name on the left (trims with
## "…" when long) and the PRICE as its own right-aligned column. Mirrors ShopScreen._make_row. `price` is the
## BASE fee from the installer; the column paints the armed rail's ALL-IN total (see the paint-site note).
func _make_row(item: Item, price: int, affordable: bool, is_buy: bool) -> Button:
	var btn := MenuStyle.size_row_button(Button.new())  # empty-text button: without the pin its rect (selection bar + hitbox) collapses above the labels
	# FOCUS_ALL, NOT the FOCUS_NONE these rows shipped with (the atm_screen _add_chip lesson): the rows ARE the
	# pad path — with them and the rail selector all refusing focus, ui navigation had no owner to start from and
	# every action on this card was pad-unreachable. open_install seeds focus on the first row built (_first_focus).
	btn.focus_mode = Control.FOCUS_ALL
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
	# Paint the ALL-IN number (ShopScreen parity): a ledger-funded install carries the account's service charge,
	# so the sticker price alone would under-quote what actually leaves the player. ChipInstaller charges via
	# player.charge(), which re-derives this same charge_total — the label and the till can never disagree. Note
	# can_pay above still takes the BASE price (it applies the fee itself; feeding it the total would fee the fee).
	price_l.text = Zorkmids.money_text(_player.charge_total(float(price)))  # the whole money phrase — the "zm" word lives in Zorkmids.MONEY_TEMPLATE
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
	# MUTE the row's auto-wired generic click: the install's commit cue fires from ChipInstaller._grant, the shared
	# success tail of BOTH transaction paths, so a click here as well would double up. Muted unconditionally —
	# a can't-afford row is disabled (never emits pressed), but the mute is what makes the funnel the sole voice.
	MenuStyle.set_button_sound(btn, &"")
	if affordable:
		btn.pressed.connect((_buy if is_buy else _install).bind(item))
	return btn

# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/chip_install_screen.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. What each piece
## still guarantees (the same contracts the old procedural build carried):
##  * the panel is the PANEL_MARGIN anchor band (authored in the scene; the scene test pins the fractions
##    against the const) — the two stacked
##    full-width sections (ShopScreen shape) live inside it: your chips on top (install), the shelf below
##    (buy & install). Both sections' scrolls EXPAND vertically (authored), so they share the leftover
##    panel height 50/50.
##  * the wallet readout + section headings are row-inset (_style_row_inset) so their edges land on the
##    rows' name/price columns instead of overhanging them in the full panel box.
##  * the ROWS are runtime content: _fill/_make_row rebuild them per chip on every bound-signal change —
##    the scene authors only %CarriedList / %StockList, the containers they populate.
##  * every string is set HERE from PlayerText — the scene ships with empty text properties.
func _bind_ui() -> void:
	_root = %Root
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)

	var content: VBoxContainer = %Content
	content.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared vertical rhythm

	_title = %Title
	MenuStyle.style_title(_title)
	_title.text = MenuStyle.title_text(PlayerText.INSTALL_SCREEN_TITLE)  # open_install re-titles per installer

	# Wallet — one header readout (your zorkmids). Right-aligned (authored), header-sized gold (_rebuild
	# re-tints danger while in debt); row-inset so its right edge lands on the rows' price column instead
	# of overhanging it in the full panel box.
	_money_player = %MoneyPlayer
	# The rail selector: flipping it changes every price gate on this card, so its signal drives the rebuild.
	_rail_btn = %RailButton as PaymentRailButton
	MenuStyle.cap_button(_rail_btn)
	_rail_btn.rail_changed.connect(_rebuild)
	_money_player.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	_money_player.add_theme_color_override(&"font_color", MenuStyle.gold())
	_style_row_inset(%MoneyInset)

	_bind_section_heading(%CarriedHeading, %CarriedInset, PlayerText.INSTALL_CARRIED_HEADING)
	_bind_section_heading(%StockHeading, %StockInset, PlayerText.INSTALL_STOCK_HEADING)
	_carried_list = %CarriedList
	_stock_list = %StockList

## Adopt one authored section heading: PlayerText string through the single casing seam (headings case with
## their shop/loot siblings) + header size, and row-inset its Margin wrapper so the heading's left edge sits
## over the rows' name column.
func _bind_section_heading(head: Label, inset: MarginContainer, heading: String) -> void:
	head.text = MenuStyle.title_text(heading)
	head.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	_style_row_inset(inset)

## Adopt an authored MarginContainer wrapper: left/right margins equal the theme Button's content inset, so a
## header element — a section heading, the wallet readout — lines up edge-for-edge with the name column (left)
## and price column (right) of the Button rows below it. This screen keeps left-aligned Button rows (unlike
## shop/loot, whose rows became centered grid tiles), which is why the inset idiom lives here now. Wraps only
## header/wallet elements, never the row Buttons — hit-testing is unaffected. Margins are THEME-derived, so
## they are applied here, never authored in the scene.
func _style_row_inset(m: MarginContainer) -> void:
	var sb: StyleBox = MenuStyle.theme.get_stylebox(&"normal", &"Button")
	m.add_theme_constant_override(&"margin_left", int(sb.content_margin_left))
	m.add_theme_constant_override(&"margin_right", int(sb.content_margin_right))
