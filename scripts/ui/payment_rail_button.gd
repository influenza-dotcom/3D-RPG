class_name PaymentRailButton
extends Button

## THE DEBIT/CREDIT SELECTOR, as a drop-in — so every point of sale can offer the choice without five copies of
## the same three lines. Drop one into a screen's authored `.tscn`, give it a `%unique_name`, and in `_bind_ui()`
## connect `rail_changed` to that screen's refresh:
##
##     _rail_btn = MenuStyle.cap_button(%RailButton) as PaymentRailButton
##     _rail_btn.rail_changed.connect(_refresh)
##
## ⭐WHY THE HOST MUST REFRESH: the armed rail changes what `Player._split` will draw on, so it changes the
## affordability dim AND the quoted total on the very same card. A toggle that repainted only its own caption
## would leave a row greyed out that the till would now serve — the exact divergence the payment seam exists to
## prevent. The signal is not optional garnish; it is how the screen stays honest.
##
## THE RAIL IS RUN STATE, NOT A PREFERENCE. It lives on `GameState.payment_method` (a String KEY) and rides the
## save, rather than sitting in Options — flipping it here is the same act as flipping it at an ATM, and every
## till in the game reads it. That is why this persists on toggle exactly as the ATM screen does.
##
## THE SOUND CUE IS OWNED HERE, not by the five hosts (see _ready): a host that added its own would stack a
## second cue on top of this one. Hosts wire `rail_changed` to their repaint and nothing else.

## The armed rail changed. Hosts connect their price/affordability repaint to this.
signal rail_changed

## Whether this screen can offer the choice at all. A CASH-ONLY vendor (`Merchant.accepts_ledger` off) draws on
## neither savings nor credit, so a rail selector there would be a control that visibly does nothing — the host
## calls `set_available(false)` and it hides itself instead of lying.
var _available: bool = true


func _ready() -> void:
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)
	# A rail flip repaints every priced row on the host screen (and on the other four that share this drop-in),
	# so it is a SIDEWAYS view swap and wears the tab cue. Two reasons it goes through set_button_sound instead
	# of a play_tab() in _on_pressed: (1) we `extends Button`, so a generic click is already auto-wired under
	# every menu root — set_button_sound REPLACES that click rather than stacking a second cue on it; (2) it
	# fires off `pressed`, i.e. player intent only. `rail_changed` is the wrong hook — the rail also moves
	# programmatically (an ATM flip, a loaded save), and those must repaint the hosts SILENTLY.
	MenuStyle.set_button_sound(self, &"tab")
	refresh()

## Repaint the caption from the live rail. Public so a host can call it after opening (the rail may have been
## changed at an ATM since this screen was last built).
func refresh() -> void:
	text = PlayerText.payment_rail_button(GameState.payment_method)
	visible = _available

## Hide the selector on a till that cannot honour it. Idempotent; safe before or after _ready.
func set_available(available: bool) -> void:
	_available = available
	visible = available

## Flip the armed rail, persist it, repaint, and tell the host to re-price. Persisting here mirrors AtmScreen:
## the rail is part of the run, so a flip made at a shop must survive a quit exactly as one made at a terminal.
func _on_pressed() -> void:
	GameState.payment_method = Player.PAY_DEBIT if GameState.payment_method == Player.PAY_CREDIT else Player.PAY_CREDIT
	var player: Node = GameState.live_player()
	if player != null:
		GameState.autosave(player)
	refresh()
	rail_changed.emit()
