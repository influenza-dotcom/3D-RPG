extends CanvasLayer
## AtmScreen — the LEDGER TERMINAL overlay for an Atm component. Autoload; REAL-TIME — it does NOT pause the
## world (the LootScreen posture, not HealScreen's); frees the mouse on open.
## Opened by Atm.start_talk (standalone kiosk) or the dialogue "Bank" option (open_atm).
##
## ⭐THIS HEADER IS THE STATION-SCREEN RULE — the shop / heal / level-up / respec / chip-install / chess screens
## all point here. Every one of them used to freeze the tree, on the theory that "a transaction with an NPC" is
## a cutscene. It wasn't: those six are opened from a CONVERSATION, and DialogueManager had already paused the
## world before the sub-menu appeared, so their own `paused = true` was a no-op nobody could perceive. The Atm
## is the one station you walk up to and press Interact on with nothing in front of it — so its pause was the
## only one a player ever actually SAW, and it read as the whole city stopping dead at a cash machine. Standing
## at a terminal is not a cutscene. Every station screen is real-time now: the world keeps running, NPCs keep
## moving, and you can be shot while you bank. Dialogue's pause is the ONLY pause left in the game.
##
## Three things follow, all handled here (and the first two by every station screen):
##  * PROCESS_MODE_ALWAYS is KEPT. A dialogue-hosted station still opens under the conversation's pause (and the
##    death cinematic pauses too), so the card must keep painting and its buttons keep working through one.
##  * The Pip-Boy tabs still refuse to open over us — via InputManager's `blocks_tabs` registry row, NOT a
##    hand-named list in each tab. Not cosmetic: both screens grab the mouse, and this one is a LATER autoload,
##    so it eats Escape first and would restore the CAPTURED cursor with a backpack still open — unclickable.
##  * ONLY HERE: the statement can be CONTRADICTED by the world it quotes, so _process repaints it when a number
##    moves, and closes the card if the terminal or the player is freed under it.
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
## as a first-launch hard stop in this project and must not recur. THE MECHANISM IS THREE PARTS, all required:
## the authored Buttons in atm_screen.tscn carry NO `focus_mode = 0` (Button's default FOCUS_ALL is what a pad
## navigates onto), the code-built chips set FOCUS_ALL in _add_chip, and open_atm SEEDS focus on the first chip
## — with no focus owner at all, ui navigation has nowhere to start from and EVERY button is unreachable, which
## is exactly the state this screen shipped in while this paragraph already claimed otherwise.

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
var _first_focus: Button = null           ## first amount chip = the pad/keyboard landing spot (open_atm grabs it)
var _is_open := false
var _syncing := false                     ## reentrancy latch: writing .text re-fires text_changed
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _atm: Node = null                     ## an Atm — typed Node to avoid an Atm<->AtmScreen class cycle
# What _refresh last PAINTED, held RAW (unclamped) so _process can spot the running world moving a number under
# an open card. Written in _refresh — the one place that reads all three — and never anywhere else.
var _painted_cash := 0.0
var _painted_account := 0.0
var _painted_standing := 0.0

func _ready() -> void:
	layer = 121                           # peer of the other modal overlays (loot / inventory / shop / heal)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)                    # the drift watch below only runs while the card is up
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
	# ⭐ONE OPEN CUE, NEVER TWO — the station-screen idiom, shared with shop / heal / level-up / respec / install
	# / chess. The terminal answers with its OWN diegetic panel chirp (a StationSpeaker on the machine: panned,
	# attenuated, coming out of the panel you are standing at), and that is the BETTER open sound — so the
	# generic UI sting is suppressed exactly when the chirp actually fires, and kept when the machine is mute.
	# Fired HERE because this is the first point the open is GUARANTEED: every refuse path above has already
	# returned, so a terminal that couldn't open never beeps. close() keeps restore_mouse's back cue — there is
	# no diegetic shutdown sound to replace it with.
	_prev_mouse_mode = ModalMenu.grab_mouse(not StationSpeaker.chirp(atm))
	var name_v: Variant = atm.get(&"station_name")  # duck-typed: only is_instance_valid was checked
	var nm: String = name_v if name_v is String else ""
	_title.text = MenuStyle.title_text(PlayerText.atm_title(nm))
	_set_amount(0.0)
	_refresh()
	_root.visible = true
	# Seed pad/keyboard focus on the first amount chip (the OptionsMenu `_first_focus` / SaveLoadScreen idiom) —
	# AFTER the card is visible, since grab_focus on a hidden Control does nothing. The chip, not Deposit: the
	# card always opens with an empty amount, so both transaction buttons are DISABLED at this instant and the
	# chips are simultaneously the only live buttons and the first step of the pad path.
	if is_instance_valid(_first_focus):
		_first_focus.grab_focus()
	set_process(true)                     # start watching for the running world moving our numbers
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	set_process(false)
	ModalMenu.restore_mouse(_prev_mouse_mode)
	_atm = null
	_player = null
	closed.emit()

## THE WORLD KEEPS MOVING BEHIND THIS CARD (we don't pause — see the header), so unlike its frozen station
## siblings this screen can be outlived or contradicted by the thing it is quoting. Two jobs, both cheap, and
## only while open (set_process is flipped in open_atm/close):
##  * CLOSE ON LOSS — the terminal or the player can be freed under us (a level swap, a death the modal sweep
##    somehow missed). A card left floating over a world it can no longer transact with has a live Deposit
##    button and no owner; closing also fires `closed`, which is what a dialogue-hosted open resumes on.
##  * REPAINT ON DRIFT — LedgerAccrual posts a dawn's interest straight onto GameState.account while you stand
##    here, and a bank statement that silently shows the pre-dawn balance is worse than one that ticks over.
##    Only when a number ACTUALLY moved: _refresh rebuilds the credit rating, so this must never run per-frame.
func _process(_delta: float) -> void:
	if not _live():
		close()
		return
	if not is_equal_approx(_painted_cash, _player.money) \
			or not is_equal_approx(_painted_account, GameState.account) \
			or not is_equal_approx(_painted_standing, GameState.credit_standing):
		_refresh()

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

## ⭐THE COMMIT CUE IS GATED ON WHAT ACTUALLY MOVED, never on the press. Atm.deposit returns 0.0 on a
## deposit-blocked terminal, on an amount under GameSettings.economy.bank_min_transaction, and on an empty
## pocket — none of those are transactions, so none of them may sound like one. They now take the DENIAL cue
## rather than nothing (the back cue still means CLOSED, so borrowing it here would still be a lie). Both
## buttons are MUTED in _bind_ui so this pair is the only sound the press makes; see the note there.
## _refresh DISABLES the button for all three cases ahead of the press, so the denial is the backstop for the
## gap between the last paint and the press (the world keeps moving behind this card) plus the controller path
## that can commit while standing on a stale button — not the primary answer.
func _on_deposit() -> void:
	if not _live():
		return
	if _atm.deposit(_player, _amount()) > 0.0:
		MenuStyle.play_commit()  # money left the pocket — the heavy cue, same as any till
		_set_amount(0.0)
	else:
		MenuStyle.play_denied()
	_refresh()
	_reseat_focus_after_commit()

func _on_withdraw() -> void:
	if not _live():
		return
	if _atm.withdraw(_player, _amount()) > 0.0:
		MenuStyle.play_commit()  # gated on the moved amount exactly as the deposit above
		_set_amount(0.0)
	else:
		MenuStyle.play_denied()
	_refresh()
	_reseat_focus_after_commit()

## ⭐THE OTHER HALF OF CONTROLLER PARITY. A pad player commits while STANDING ON the button, and the repaint
## that follows zeroes the amount and therefore DISABLES that same button — leaving the viewport with no focus
## owner and the pad with nothing to move, one press after the screen started working. Hand focus back to the
## chips, which are live in every state. Only when the owner is actually gone, so a mouse player who left the
## caret in the amount field (or a pad player the engine did keep on the button) is never yanked; and only
## while the card is really up, because grab_focus on a hidden Control faults.
func _reseat_focus_after_commit() -> void:
	if not _is_open or not _root.visible or not is_instance_valid(_first_focus):
		return
	if get_viewport().gui_get_focus_owner() == null:
		_first_focus.grab_focus()

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
## Also stamps what it painted, so _process's drift watch has something to compare the live world against.
func _refresh() -> void:
	if not _live():
		return
	_painted_cash = _player.money
	_painted_account = GameState.account
	_painted_standing = GameState.credit_standing
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
	# ⭐THE QUOTED RATE IS THE GLOBAL ONE, VERBATIM. There is deliberately no per-terminal multiplier: purchases
	# are charged in Player._split from GameSettings.economy.bank_noncash_fee_fraction with no terminal in scope,
	# so a screen that scaled the number it quoted was printing a receipt the till would not honour (the whole
	# argument, and the deleted `Atm.fee_multiplier` it retired, is recorded in the Atm header).
	_hint.text = PlayerText.atm_hint(GameSettings.economy.bank_noncash_fee_fraction)
	# Deposit doubles as "settle" — the caption is the ONLY difference, selected by the account's sign.
	_deposit_btn.text = PlayerText.atm_deposit_button(owed > 0.0)
	_withdraw_btn.text = PlayerText.ATM_WITHDRAW
	_rail_btn.text = PlayerText.payment_rail_button(GameState.payment_method)
	# ⭐THE ENABLE PREDICATE MIRRORS Atm.deposit/withdraw's OWN GUARDS, the MINIMUM included. The component
	# silently returns 0.0 below bank_min_transaction, and a live button that takes a click and does nothing —
	# no toast, no hint, and no "denied" clip to borrow — is the worst refusal of the three. Inert while the
	# setting ships at 0.0 (a quantized amount is never negative), and correct the day a designer raises it.
	var min_txn: float = GameSettings.economy.bank_min_transaction
	_deposit_btn.disabled = not bool(_atm.get(&"allows_deposit")) or n <= 0.0 or n < min_txn or n > cash
	_withdraw_btn.disabled = not bool(_atm.get(&"allows_withdraw")) or n <= 0.0 or n < min_txn or n > maxf(0.0, acct)

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
	_first_focus = null   # the old chips are dying (queue_free) — only a chip from THIS build may take focus
	_add_chip(_presets, PlayerText.ATM_ALL_CASH, func() -> void: _on_fill(1.0, true))
	_add_chip(_presets, PlayerText.ATM_HALF_CASH, func() -> void: _on_fill(0.5, true))
	_add_chip(_presets, PlayerText.ATM_ALL_SAVED, func() -> void: _on_fill(1.0, false))
	for v in [10.0, 100.0, 1000.0]:
		_add_chip(_presets, Zorkmids.fmt(v), _on_preset.bind(v))

	# The RAIL selector. A cycling Button, not a dropdown: embed_subwindows is off, so a PopupMenu would escape
	# the 792x444 retro pipeline — and a Button is the only widget a pad can always reach. It flips
	# GameState.payment_method, a String KEY, and is read by Player._split at every till in the game.
	# A rail flip is a SIDEWAYS view change, not a purchase — nothing is bought, the same card just re-prices —
	# so it wears the tab cue the sort/page swaps wear (MenuStyle.play_tab's own vocabulary names the rail flip).
	# set_button_sound RE-POINTS the click apply() already wired, so this replaces rather than stacks.
	_rail_btn = MenuStyle.cap_button(%RailButton)
	MenuStyle.set_button_sound(_rail_btn, &"tab")
	_rail_btn.pressed.connect(_on_rail_toggle)

	# ⭐BOTH TRANSACTION BUTTONS ARE MUTED (&""): their cue is the play_commit() inside the handler, which fires
	# only once money ACTUALLY moved. Leaving the auto-wired generic click on would sound a successful deposit
	# twice and a refused one once — precisely backwards.
	_deposit_btn = MenuStyle.cap_button(%DepositButton)
	MenuStyle.set_button_sound(_deposit_btn, &"")
	_deposit_btn.pressed.connect(_on_deposit)
	_withdraw_btn = MenuStyle.cap_button(%WithdrawButton)
	MenuStyle.set_button_sound(_withdraw_btn, &"")
	_withdraw_btn.pressed.connect(_on_withdraw)
	_close_btn = MenuStyle.cap_button(%CloseButton)
	_close_btn.text = PlayerText.CLOSE
	_close_btn.pressed.connect(close)

## One amount chip. FOCUS_ALL, NOT the FOCUS_NONE these shipped with: the chips ARE the pad path the header
## promises, and a control a pad can never land on is not a path at all. The cost is that clicking a chip with
## the mouse pulls focus off the amount field — which is the right trade, because clicking a chip is how a
## mouse player says they are DONE typing. The first chip built is the screen's landing spot (see open_atm).
func _add_chip(row: HBoxContainer, caption: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = caption
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(on_press)
	row.add_child(b)
	if _first_focus == null:
		_first_focus = b
