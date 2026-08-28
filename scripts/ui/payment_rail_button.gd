class_name PaymentRailButton
extends Button

## THE DEBIT/CREDIT SELECTOR, as a drop-in — so every point of sale can offer the choice without one copy of the
## same three lines per till (six screens author one today: shop, heal, level-up, respec, chip-install, weapon
## bench). Drop one into a screen's authored `.tscn`, give it a `%unique_name`, and in `_bind_ui()`
## connect `rail_changed` to that screen's refresh:
##
##     _rail_btn = MenuStyle.cap_button(%RailButton) as PaymentRailButton
##     _rail_btn.rail_changed.connect(_refresh)
##
## ⭐WHY THE HOST MUST REFRESH: the armed rail changes what `Player._split` may draw on, so it moves the
## affordability dim on the very same card. (The all-in quoted total is rail-invariant — the service fee rides
## the cash shortfall whichever rail funds it; test_payment.gd pins that.) A toggle that repainted only its own
## caption would leave a row greyed out that the till would now serve — the exact divergence the payment seam
## exists to prevent. The signal is not optional garnish; it is how the screen stays honest.
##
## THE RAIL IS RUN STATE, NOT A PREFERENCE. It lives on `GameState.payment_method` (a String KEY) and rides the
## save, rather than sitting in Options — flipping it here is the same act as flipping it at an ATM, and every
## till in the game reads it. That is why this persists on toggle exactly as the ATM screen does.
##
## THE SOUND CUE IS OWNED HERE, not by the hosts (see _ready): a host that added its own would stack a
## second cue on top of this one. Hosts wire `rail_changed` to their repaint and nothing else.
##
## ⭐⭐IT MUST NOT READ AS A READOUT — the defect this shape exists to prevent. Authored, this is a plain Button
## in a VBox, i.e. FULL PANEL WIDTH with a centred, colon-terminated caption ("Paying with: Debit") — the widest
## and brightest control on the card, sitting above the actual Confirm/Cancel pair. Screenshot QA on the heal,
## shop, respec and chip-install cards read it as a status banner every time and never discovered that Credit
## exists at all, which quietly made the whole credit economy unreachable from a till. Two changes fix it here,
## in the drop-in, so ONE edit covers all six host screens:
##   1. CHEVRONS. The caption is flanked with the skin's cycler step glyphs — `< Paying with: Debit >` — this
##      game's existing "you can cycle this" dialect (the Options tab's cycler rows use the same pair). They
##      live on MenuSkin (non-prose paint belongs to the skin, never PlayerText) and are joined in a LOCAL
##      rather than at the `.text =` site, which keeps a shape glyph out of the PlayerText ratchet's paint-site
##      scan WITHOUT loosening that scanner (the chess move-log's separator idiom, verbatim).
##      ⭐Do NOT hardcode `‹ ›` here: the pixel font has no guillemets and renders them as tofu — that is the
##      whole reason cycler_prev_glyph/cycler_next_glyph default to plain ASCII and live on the skin.
##   2. IT STOPS FILLING THE PANEL. SHRINK_CENTER over a pinned width demotes it to a button-sized chip beside
##      its siblings instead of a full-width bar over them.

## The armed rail changed. Hosts connect their price/affordability repaint to this.
signal rail_changed

## Whether this screen can offer the choice at all. A CASH-ONLY vendor (`Merchant.accepts_ledger` off) draws on
## neither savings nor credit, so a rail selector there would be a control that visibly does nothing — the host
## calls `set_available(false)` and it hides itself instead of lying.
var _available: bool = true


func _ready() -> void:
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)
	# Stop spanning the card (see the ⭐⭐ header note). SHRINK_CENTER alone would collapse the button to its
	# caption — and every host calls MenuStyle.cap_button on us, so clip_text drops that caption's contribution
	# to ~0 and we would shrink to nothing; _pin_width supplies the real width the shrink then honours.
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# A rail flip repaints every priced row on the host screen (and on the other five that share this drop-in),
	# so it is a SIDEWAYS view swap and wears the tab cue. Two reasons it goes through set_button_sound instead
	# of a play_tab() in _on_pressed: (1) we `extends Button`, so a generic click is already auto-wired under
	# every menu root — set_button_sound REPLACES that click rather than stacking a second cue on it; (2) it
	# fires off `pressed`, i.e. player intent only. `rail_changed` is the wrong hook — the rail also moves
	# programmatically (an ATM flip, a loaded save), and those must repaint the hosts SILENTLY.
	MenuStyle.set_button_sound(self, &"tab")
	refresh()

## The width pin is FONT-measured, so it has to re-run when the font arrives. A host applies the menu Theme in
## its own `_bind_ui` — which runs AFTER this `_ready` (children ready first), so the measure taken above is
## against the engine's default font, not ours. This is the notification that lands when the host's
## MenuStyle.apply() reaches us, and it is what makes the pinned width correct on the first frame the card is
## ever shown rather than only after the first host repaint.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_pin_width()

## Repaint the caption from the live rail. Public so a host can call it after opening (the rail may have been
## changed at an ATM since this screen was last built).
func refresh() -> void:
	text = _caption_for(GameState.payment_method)
	visible = _available
	_pin_width()

## Hide the selector on a till that cannot honour it. Idempotent; safe before or after _ready.
func set_available(available: bool) -> void:
	_available = available
	visible = available

## The painted caption for one rail KEY: the PlayerText sentence between the skin's two cycler chevrons.
## Composed in a local and returned, never assigned to `.text` from a literal — see the header's note (1).
func _caption_for(method: String) -> String:
	var skin: Resource = MenuStyle.skin  # untyped like every other skin read (the MenuSkin class-cache contract)
	var parts := PackedStringArray([
		String(skin.cycler_prev_glyph),
		PlayerText.payment_rail_button(method),
		String(skin.cycler_next_glyph),
	])
	return " ".join(parts)

## Pin the button's width to the WIDER of its two captions (never to the one currently shown), floored at the
## skin's dialog-button width so it still reads as a button when a locale is terse.
##
## ⭐MEASURED, not guessed, and measured over BOTH rails — this is the menus-must-not-resize-with-text rule at
## its sharpest. Sizing to the live caption would make the button visibly grow and shrink under the cursor every
## time you flip it ("Credit" is a letter wider than "Debit"), which is precisely the twitch the house style
## forbids. And the floor cannot be the only rule either: every host cap_button()s us, so a caption wider than
## the pinned box is CLIPPED — and the thing clipped off the right edge would be the closing chevron, i.e. the
## affordance this control exists to show. Skipped off-tree (a bare `.new()` in a unit test has no theme to
## measure against and must not push engine errors).
func _pin_width() -> void:
	if not is_inside_tree():
		return
	var f: Font = get_theme_font(&"font")
	if f == null:
		return
	var font_size := get_theme_font_size(&"font_size")
	var widest := 0.0
	for rail: String in [Player.PAY_DEBIT, Player.PAY_CREDIT]:
		widest = maxf(widest, f.get_string_size(_caption_for(rail), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
	var sb: StyleBox = get_theme_stylebox(&"normal")
	var pad: float = (sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)) if sb != null else 0.0
	custom_minimum_size.x = maxf(ceilf(widest + pad), float(MenuStyle.skin.dialog_button_min_width))

## Flip the armed rail, persist it, repaint, and tell the host to re-price. Persisting here mirrors AtmScreen:
## the rail is part of the run, so a flip made at a shop must survive a quit exactly as one made at a terminal.
func _on_pressed() -> void:
	GameState.payment_method = Player.PAY_DEBIT if GameState.payment_method == Player.PAY_CREDIT else Player.PAY_CREDIT
	var player: Node = GameState.live_player()
	if player != null:
		GameState.autosave(player)
	refresh()
	rail_changed.emit()
