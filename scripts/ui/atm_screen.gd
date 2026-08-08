extends CanvasLayer
## AtmScreen — the LEDGER TERMINAL overlay for an Atm component. Autoload; PAUSES the world while open (like
## HealScreen — PROCESS_MODE_ALWAYS so its buttons keep working through the pause); frees the mouse on open.
## Opened by Atm.start_talk (standalone kiosk) or the dialogue "Bank" option (open_atm).
##
## ⭐THE ACCOUNT IS ONE SIGNED NUMBER (GameState.account): positive is savings, negative is what you owe — so
## DEPOSIT and "pay off your debt" are the SAME operation and this screen only swaps a caption. All the rules
## live in Atm.deposit / Atm.withdraw; this screen is a pure VIEW that quotes them and never decides anything.
##
## AUTHORED SCENE: the layout lives in scenes/ui/atm_screen.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and applies the
## skin-driven look on top. NO text is authored in the scene — every string is set here from PlayerText.
##
## ⭐THE STATEMENT IS A CONSTANT FIVE LINES by construction: every line always paints and only the TEMPLATE per
## line is selected by sign. style_dialog_card pins the card's WIDTH only — its HEIGHT shrink-wraps and the
## CenterContainer re-centres, so a line that appeared or vanished would hop the whole card mid-transaction
## (the heal_screen constant-line-count lesson). Never hide a line with `visible`.
##
## ⭐CONTROLLER PARITY: every action is reachable through Buttons alone. The amount LineEdit is the mouse/
## keyboard convenience, but All / Half and the preset chips are the pad path — a mouse-only gate once shipped
## as a first-launch hard stop in this project and must not recur.

signal opened
signal closed

var _root: Control
var _title: Label
var _statement: Label
var _hint: Label
var _amount_edit: LineEdit
var _deposit_btn: Button
var _withdraw_btn: Button
var _close_btn: Button
var _presets: HBoxContainer
var _rail_btn: Button                     ## flips GameState.payment_method between the two rail KEYS
var _is_open := false
var _syncing := false                     ## reentrancy latch: writing .text re-fires text_changed
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _atm: Node = null                     ## an Atm — typed Node to avoid an Atm<->AtmScreen class cycle

func _ready() -> void:
	layer = 121                           # peer of the other modal overlays (loot / inventory / shop / heal)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

## Open the terminal for `atm`. Refuses to stack over another modal / dialogue and bails safely on a bad
## terminal or no player. ⭐Every refuse path emits `closed`: a dialogue-hosted open suspends the conversation
## on our `closed` one-shot BEFORE calling us, so bailing without it strands the conversation suspended
## forever (box hidden, tree paused, soft-lock, no error).
func open_atm(atm: Node, player: Node) -> void:
	if _is_open or DialogueManager.is_active() or InputManager.any_modal_open(self):
		closed.emit()
		return
	if not is_instance_valid(atm):
		closed.emit()
		return
	_player = player as Player
	if not is_instance_valid(_player):
		closed.emit()
		return
	_atm = atm
	_is_open = true
	_prev_mouse_mode = ModalMenu.grab_mouse()
	var name_v: Variant = atm.get(&"station_name")  # duck-typed: only is_instance_valid was checked
	var nm: String = name_v if name_v is String else ""
	_title.text = MenuStyle.title_text(PlayerText.atm_title(nm))
	_set_amount(0.0)
	_refresh()
	_root.visible = true
	get_tree().paused = true
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	ModalMenu.restore_mouse(_prev_mouse_mode)
	_atm = null
	_player = null
	get_tree().paused = false
	closed.emit()

## Esc closes. ⭐Deliberately NOT also the Interact key (unlike HealScreen): a focused LineEdit consumes
## printable keys as handled, so binding the close to a letter key would make it unreliable exactly while the
## player is typing an amount. Esc always survives.
func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# Transactions — every rule lives on the Atm component; this screen only asks and then repaints
# ---------------------------------------------------------------------------------------------------

func _on_deposit() -> void:
	if not _live():
		return
	if _atm.deposit(_player, _amount()) > 0.0:
		_set_amount(0.0)
	_refresh()

func _on_withdraw() -> void:
	if not _live():
		return
	if _atm.withdraw(_player, _amount()) > 0.0:
		_set_amount(0.0)
	_refresh()

func _live() -> bool:
	return is_instance_valid(_atm) and is_instance_valid(_player)

## The typed amount, coin-quantized. Junk or blank reads as 0.0 — never bool(<String>), which throws.
func _amount() -> float:
	if _amount_edit == null:
		return 0.0
	var t := _amount_edit.text.strip_edges()
	return snappedf(maxf(0.0, t.to_float()), Zorkmids.QUANTUM) if t.is_valid_float() else 0.0

func _set_amount(v: float) -> void:
	if _amount_edit == null:
		return
	_syncing = true
	_amount_edit.text = "" if v <= 0.0 else Zorkmids.fmt(v)
	_amount_edit.caret_column = _amount_edit.text.length()
	_syncing = false

## Digits and ONE dot only. Latched, because writing .text re-fires text_changed; the caret is restored so
## typing mid-string doesn't jump to the end.
func _on_amount_changed(_t: String) -> void:
	if _syncing or _amount_edit == null:
		return
	var caret := _amount_edit.caret_column
	var clean := ""
	var seen_dot := false
	for ch in _amount_edit.text:
		if ch.is_valid_int():
			clean += ch
		elif ch == "." and not seen_dot:
			clean += ch
			seen_dot = true
	if clean != _amount_edit.text:
		_syncing = true
		_amount_edit.text = clean
		_amount_edit.caret_column = mini(caret, clean.length())
		_syncing = false
	_refresh()

## Context-sensitive fills — the CONTROLLER path. "All" means whole cash for a deposit and the whole POSITIVE
## account for a withdrawal, so one button serves both directions without the player doing arithmetic.
func _on_fill(fraction: float, of_cash: bool) -> void:
	if not _live():
		return
	var pot := maxf(0.0, _player.money) if of_cash else maxf(0.0, GameState.account)
	_set_amount(snappedf(pot * fraction, Zorkmids.QUANTUM))
	_refresh()

func _on_preset(v: float) -> void:
	_set_amount(v)
	_refresh()

## Flip the armed payment rail. This is RUN STATE, not an install preference, so it lives on GameState (and
## rides the save) rather than in Options — the same argument that keeps tos_accepted out of the run profile,
## in reverse. Every till in the game reads it through Player._split, so flipping it here changes what the
## shop, the healer, the installer and the level-up station will draw on.
func _on_rail_toggle() -> void:
	GameState.payment_method = Player.PAY_DEBIT if GameState.payment_method == Player.PAY_CREDIT else Player.PAY_CREDIT
	if _live():
		GameState.autosave(_player)
	_refresh()

# ---------------------------------------------------------------------------------------------------
# Paint
# ---------------------------------------------------------------------------------------------------

## The five-line statement + the button states. CONSTANT line count by construction (see the header).
func _refresh() -> void:
	if not _live():
		return
	var cash: float = maxf(0.0, _player.money)
	var acct: float = GameState.account
	var owed: float = maxf(0.0, -acct)
	var n := _amount()
	# The rating is the LIVE one — build AND record together — so the score line moves as the player repays,
	# sits in arrears, or collects the Ledger's undisclosed conduct dividend.
	var rating: Dictionary = _player.credit_rating()
	_statement.text = PlayerText.atm_statement(cash, maxf(0.0, acct), owed,
			_player.credit_left(), _player.credit_limit(),
			int(rating["score"]), rating["band"])
	_statement.add_theme_color_override(&"font_color",
		MenuStyle.danger() if owed > 0.0 else MenuStyle.gold())
	_hint.text = PlayerText.atm_hint(GameSettings.economy.bank_noncash_fee_fraction * _fee_multiplier())
	# Deposit doubles as "settle" — the caption is the ONLY difference, selected by the account's sign.
	_deposit_btn.text = PlayerText.atm_deposit_button(owed > 0.0)
	_withdraw_btn.text = PlayerText.ATM_WITHDRAW
	_rail_btn.text = PlayerText.payment_rail_button(GameState.payment_method)
	_deposit_btn.disabled = not bool(_atm.get(&"allows_deposit")) or n <= 0.0 or n > cash
	_withdraw_btn.disabled = not bool(_atm.get(&"allows_withdraw")) or n <= 0.0 or n > maxf(0.0, acct)

func _fee_multiplier() -> float:
	var v: Variant = _atm.get(&"fee_multiplier") if is_instance_valid(_atm) else null
	return maxf(0.0, float(v)) if (v is float or v is int) else 1.0

# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/atm_screen.tscn — this adopts it; mirrors heal_screen.gd)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. What each piece
## guarantees:
##  * the card is a FIXED-WIDTH centered dialog (style_dialog_card pins %Card to skin.dialog_width) — a long
##    terminal name or a huge balance can never grow it or slide it off-centre.
##  * the statement is FIVE lines in every state, so the card cannot hop mid-transaction.
##  * every action is reachable by Button alone (All / Half / presets), so a pad player is never locked out
##    of a screen whose only other input is a LineEdit.
##  * every string is set HERE from PlayerText — the scene ships with empty text properties.
func _bind_ui() -> void:
	_root = %Root
	MenuStyle.apply(_root)
	MenuStyle.style_dim(%Dim)
	MenuStyle.style_dialog_card(%Card, 2)
	MenuStyle.style_button_row(%Buttons)

	_title = MenuStyle.cap_label(%Title)
	MenuStyle.style_title(_title)
	_title.text = MenuStyle.title_text(PlayerText.ATM_CARD_TITLE)  # open_atm re-titles per terminal

	_statement = %Statement
	_statement.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)

	_hint = %Hint
	MenuStyle.style_hint(_hint)

	_amount_edit = %AmountEdit
	_amount_edit.placeholder_text = PlayerText.ATM_AMOUNT_PLACEHOLDER
	_amount_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_amount_edit.text_changed.connect(_on_amount_changed)

	# The controller path: All / Half for each direction, plus fixed chips. Built here (not authored) because
	# the preset VALUES are economy content, and a designer changing them must not have to edit a .tscn.
	_presets = %Presets
	for c in _presets.get_children():
		c.queue_free()
	_add_chip(_presets, PlayerText.ATM_ALL_CASH, func() -> void: _on_fill(1.0, true))
	_add_chip(_presets, PlayerText.ATM_HALF_CASH, func() -> void: _on_fill(0.5, true))
	_add_chip(_presets, PlayerText.ATM_ALL_SAVED, func() -> void: _on_fill(1.0, false))
	for v in [10.0, 100.0, 1000.0]:
		_add_chip(_presets, Zorkmids.fmt(v), _on_preset.bind(v))

	# The RAIL selector. A cycling Button, not a dropdown: embed_subwindows is off, so a PopupMenu would escape
	# the 792x444 retro pipeline — and a Button is the only widget a pad can always reach. It flips
	# GameState.payment_method, a String KEY, and is read by Player._split at every till in the game.
	_rail_btn = MenuStyle.cap_button(%RailButton)
	_rail_btn.pressed.connect(_on_rail_toggle)

	_deposit_btn = MenuStyle.cap_button(%DepositButton)
	_deposit_btn.pressed.connect(_on_deposit)
	_withdraw_btn = MenuStyle.cap_button(%WithdrawButton)
	_withdraw_btn.pressed.connect(_on_withdraw)
	_close_btn = MenuStyle.cap_button(%CloseButton)
	_close_btn.text = PlayerText.CLOSE
	_close_btn.pressed.connect(close)

## One amount chip. FOCUS_NONE so the chips never steal focus from the amount field mid-type.
func _add_chip(row: HBoxContainer, caption: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = caption
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	row.add_child(b)
