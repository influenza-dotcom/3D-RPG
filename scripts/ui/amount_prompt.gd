class_name AmountPrompt
extends Control

## A small "how many zorkmids?" card that a menu screen parents into its own root — the affordance that
## replaced the wallet's backpack COIN TILE. Money is not an inventory item any more (it never was a real
## one: it was a derived mirror of `Character.money` that ate 1x1..3x3 backpack cells), so the gestures the
## tile carried — right-click to DROP the purse, click-into-the-source to STASH it — need a widget of their
## own. This is that widget, shared by InventoryScreen (drop) and LootScreen (stash) so both ask the same
## question the same way and clamp it against the same wallet.
##
## CODE-BUILT + self-contained, exactly like GridInventoryView: it is live runtime chrome bound per-open, not
## static layout an artist arranges, so it is instantiated into the authored scenes rather than authored in
## them. It draws a full-rect scrim over its host's panel and eats every click that misses the card, so the
## grid underneath can't be clicked "through" an open prompt.
##
## Usage: prompt.ask(title, cap, confirm_caption, func(amount: float) -> void: ...). The callback fires ONLY
## on a confirm, with an amount that is already clamped to `cap` and snapped to Zorkmids.QUANTUM — a caller
## never has to re-validate. Esc / Cancel closes without calling back. Seeded with the FULL cap and
## select_all()'d, so Enter-Enter still means "the whole purse" (the one-gesture the coin tile used to be)
## while a typed number takes over the moment you touch a digit.

signal cancelled

var _card: VBoxContainer
var _title: Label
var _hint: Label
var _edit: LineEdit
var _confirm_btn: Button
var _cancel_btn: Button
var _cap: float = 0.0                        ## the most this prompt may return (the live wallet at ask() time)
var _on_confirm: Callable = Callable()
var _syncing: bool = false                   ## latch: writing .text re-fires text_changed (the ATM idiom)


func _init() -> void:
	name = &"AmountPrompt"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # a click that misses the card must not reach the grid behind it
	visible = false


func _ready() -> void:
	add_child(MenuStyle.make_dim())
	_card = MenuStyle.make_dialog(self)
	_title = MenuStyle.cap_label(Label.new())
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuStyle.style_title(_title)
	_card.add_child(_title)
	# The wallet line. style_hint() turns wrapping ON for footnotes; this one is a FIXED single line (an
	# absurd wallet must clip, not add a second row) — the card's height shrink-wraps and a taller card
	# re-centres itself, which would hop the whole prompt as the number grew.
	_hint = MenuStyle.cap_label(Label.new())
	MenuStyle.style_hint(_hint)
	_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(_hint)
	_edit = LineEdit.new()
	_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_edit.context_menu_enabled = false
	_edit.placeholder_text = PlayerText.AMOUNT_PLACEHOLDER
	_edit.text_changed.connect(_on_text_changed)
	_edit.text_submitted.connect(_on_submitted)
	_card.add_child(_edit)
	# Fill chips — the CONTROLLER path (and the mouse shortcut). FOCUS_ALL for the same reason the ATM's are:
	# a control a pad can never land on is not a path at all.
	var chips := HBoxContainer.new()
	MenuStyle.style_button_row(chips)
	_card.add_child(chips)
	_add_chip(chips, PlayerText.AMOUNT_ALL, 1.0)
	_add_chip(chips, PlayerText.AMOUNT_HALF, 0.5)
	var row := HBoxContainer.new()
	MenuStyle.style_button_row(row)
	_card.add_child(row)
	# MUTED (&""): the confirm cue belongs to the CALLER — only it knows whether the money actually moved
	# (a full container refuses a stash). Leaving the auto-wired click on would sound a refused spill.
	_confirm_btn = MenuStyle.cap_button(Button.new())
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuStyle.set_button_sound(_confirm_btn, &"")
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	row.add_child(_confirm_btn)
	_cancel_btn = MenuStyle.cap_button(Button.new())
	_cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_btn.text = PlayerText.CANCEL
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	row.add_child(_cancel_btn)
	set_process_unhandled_input(false)  # only an OPEN prompt may swallow Esc (see _unhandled_input)


func is_open() -> bool:
	return visible


## Ask for an amount up to `cap`, titled `title`, committing through a button captioned `confirm_caption`.
## On confirm, `on_confirm` is called with the clamped + quantized float. A non-positive cap is refused
## outright (there is nothing to divide up) and answers with the denial cue, so a press is never silent.
func ask(title: String, cap: float, confirm_caption: String, on_confirm: Callable) -> void:
	_cap = snappedf(maxf(0.0, cap), Zorkmids.QUANTUM)
	if _cap <= 0.0:
		MenuStyle.play_denied()
		return
	_on_confirm = on_confirm
	_title.text = MenuStyle.title_text(title)
	_hint.text = PlayerText.amount_available(_cap)
	_hint.add_theme_color_override(&"font_color", MenuStyle.gold())
	_confirm_btn.text = confirm_caption
	_set_amount(_cap)  # seeded FULL: Enter alone still means "all of it", the gesture the coin tile carried
	visible = true
	set_process_unhandled_input(true)
	MenuStyle.play_open()
	_edit.grab_focus()
	_edit.select_all()  # ...and the first digit typed replaces the seed instead of appending to it
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	set_process_unhandled_input(false)
	_on_confirm = Callable()
	_cap = 0.0


## Esc closes the prompt WITHOUT closing the host screen. This runs before the host's own `_unhandled_input`
## (unhandled input walks the tree bottom-up, and we are a descendant of the host's root), so marking it
## handled is what stops one Esc from cancelling the prompt AND shutting the backpack behind it.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()


func _add_chip(row: HBoxContainer, caption: String, fraction: float) -> void:
	var b := MenuStyle.cap_button(Button.new())
	b.text = caption
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(_on_fill.bind(fraction))
	row.add_child(b)


func _on_fill(fraction: float) -> void:
	_set_amount(snappedf(_cap * fraction, Zorkmids.QUANTUM))
	_refresh()


## The typed amount, coin-quantized and capped. Junk or blank reads 0.0 — never bool(<String>), which throws.
func amount() -> float:
	var t := _edit.text.strip_edges()
	if not t.is_valid_float():
		return 0.0
	return clampf(snappedf(maxf(0.0, t.to_float()), Zorkmids.QUANTUM), 0.0, _cap)


func _set_amount(v: float) -> void:
	_syncing = true
	_edit.text = "" if v <= 0.0 else Zorkmids.fmt(v)
	_edit.caret_column = _edit.text.length()
	_syncing = false


## Digits and ONE dot only (the ATM's filter). Latched, because writing .text re-fires text_changed; the
## caret is restored so typing mid-string doesn't jump to the end.
func _on_text_changed(_t: String) -> void:
	if _syncing:
		return
	var caret := _edit.caret_column
	var clean := ""
	var seen_dot := false
	for ch in _edit.text:
		if ch.is_valid_int():
			clean += ch
		elif ch == "." and not seen_dot:
			clean += ch
			seen_dot = true
	if clean != _edit.text:
		_syncing = true
		_edit.text = clean
		_edit.caret_column = mini(caret, clean.length())
		_syncing = false
	_refresh()


func _on_submitted(_t: String) -> void:
	_on_confirm_pressed()  # Enter in the field commits, like every other prompt in the game


func _on_confirm_pressed() -> void:
	var n := amount()
	if n <= 0.0:
		MenuStyle.play_denied()  # a blank / zero entry answers rather than closing on nothing
		return
	var cb := _on_confirm
	close()  # close FIRST: the callback may open a toast / rebuild the host grid behind us
	if cb.is_valid():
		cb.call(n)


func _on_cancel_pressed() -> void:
	if not visible:
		return
	close()
	MenuStyle.play_back()
	cancelled.emit()


## Disable the commit while the entry can't buy anything (blank, zero, or filtered down to a bare dot), so the
## button state says what a press would do before the player spends a click on it.
func _refresh() -> void:
	_confirm_btn.disabled = amount() <= 0.0
