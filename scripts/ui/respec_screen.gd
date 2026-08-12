extends CanvasLayer
## RespecScreen — the CONFIRM overlay for a RespecStation. Autoload; REAL-TIME — it does NOT pause the world
## (the STATION-SCREEN rule, argued in full in the atm_screen.gd header; PROCESS_MODE_ALWAYS anyway, so the
## screen survives any pause around it) and frees the mouse. Previews the respec COST + the perks that
## will be refunded, then Confirm calls RespecStation.do_respec (reverse every perk, refund its skill point, charge
## the fee). Opened by RespecStation.start_talk. Mirrors HealScreen — the single-transaction modal shape — so a
## respec now asks before it wipes a build, instead of firing instantly on Interact.
##
## AUTHORED SCENE: the layout lives in scenes/ui/respec_screen.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and applies the
## skin-driven look (MenuStyle style_* adopters) on top, so a designer rearranges the card in the editor
## and the skin keeps owning colours/fonts/width pins. NO text is authored in the scene — every string is
## set here from PlayerText (l10n + the text-debt ratchet own strings, never a .tscn). The perk-row
## PREVIEW stays runtime-built (see _refresh) — the scene authors only the %List container it fills.
## tests/test_respec_screen_scene.gd pins the wiring.

signal opened
signal closed


var _root: Control
var _title: Label
var _blurb: Label   ## wrapping prose explainer (what a respec does) — split from _status so its long line can't widen the card
var _status: Label  ## the short facts: cost + current zorkmids
var _list: VBoxContainer
var _confirm_btn: Button
var _rail_btn: PaymentRailButton  ## DEBIT/CREDIT selector; rail_changed drives _refresh (the Confirm gate moves with it)
var _cancel_btn: Button
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _station: Node = null  ## a RespecStation — typed Node to avoid a RespecStation<->RespecScreen class cycle; API called dynamically

func _ready() -> void:
	layer = 121                                  # peer of the other modal overlays (loot / inventory / shop / heal)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

## Open the confirm modal for `station`, respec-ing `player`. Refuses to stack over another modal / dialogue, and
## bails safely on an invalid station or no player. Nothing is charged or reversed until the player clicks Confirm.
## EVERY refuse path emits `closed` (via _refuse_open) — the dialogue-suspend contract all the station screens
## keep; see _refuse_open below for why a silent refuse is a soft-lock waiting to happen.
func open_respec(station: Node, player: Node) -> void:
	if _is_open or DialogueManager.is_active() or InputManager.any_modal_open(self):  # M5: refuse over ANY other menu (incl. QuestJournal)
		_refuse_open()
		return
	if not is_instance_valid(station):
		_refuse_open()
		return
	_player = player as Player
	if not is_instance_valid(_player):
		_refuse_open()
		return
	_station = station
	_is_open = true
	# ONE OPEN CUE, NEVER TWO (the station-screen idiom): the station answers with its OWN diegetic
	# StationSpeaker chirp, so the generic UI sting is suppressed exactly when that chirp fires and kept when the
	# machine is mute. Past every refuse guard, so a station that couldn't open never beeps.
	_prev_mouse_mode = ModalMenu.grab_mouse(not StationSpeaker.chirp(station))
	var name_v: Variant = station.get(&"station_name")  # duck-typed: only is_instance_valid was checked, not the type
	var nm: String = name_v if name_v is String else ""
	# Runtime re-title MUST route through title_text() — make_title only cases its constructor argument.
	_title.text = MenuStyle.title_text(PlayerText.respec_title(nm))
	_refresh()
	_root.visible = true
	# Seed pad/keyboard focus on Confirm (the OptionsMenu `_first_focus` / SaveLoadScreen idiom; atm_screen.gd's
	# ⭐CONTROLLER PARITY header carries the full argument) — AFTER the card is visible, since grab_focus on a
	# hidden Control does nothing. Without a focus owner, ui navigation has nowhere to start and every button on
	# the card is pad-unreachable. Confirm is the emphasized action, so it is the landing spot; when _refresh
	# just disabled it (no perks / can't afford), a disabled Button still takes focus, so the pad simply steps
	# off it to the rail selector or Cancel.
	if is_instance_valid(_confirm_btn):
		_confirm_btn.grab_focus()
	opened.emit()

## Guard failed: we never opened. Emit `closed` anyway — the dialogue-suspend contract (dialogue_manager.gd's
## @risk header + atm_screen.gd line ~81 star it): a dialogue-hosted open suspends the conversation on our
## `closed` one-shot BEFORE calling the open, so a refuse that returns silently strands it suspended forever
## (box hidden, tree paused, soft-lock, no error). Today this screen's only caller is RespecStation.start_talk
## (standalone — nothing listens, so the emit is a harmless no-op), which makes this the cheap insurance that
## wiring a "Respec" dialogue option later can't soft-lock. Do NOT touch pause/mouse/_is_open here — none of
## that was mutated yet.
func _refuse_open() -> void:
	closed.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	ModalMenu.restore_mouse(_prev_mouse_mode)
	_station = null
	_player = null
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	# Close (= Cancel) on the SAME Interact key that opens it (the ray consumes the OPENING press — see ray_cast.gd,
	# which skips interacting while any modal is open), or on Esc. Confirm is an explicit button click.
	if _is_open and (event.is_action_pressed(InputManager.action_pickup) or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

## Commit the respec (the station is the single source of the transaction), then close. do_respec is self-guarding,
## so even if the Confirm button somehow fired while broke / with no perks, nothing bad happens.
func _on_confirm_pressed() -> void:
	if is_instance_valid(_station) and is_instance_valid(_player):
		# do_respec returns the perk COUNT it actually refunded, so 0 is its "refused" answer (no perks / can't
		# afford). EITHER verdict is the cue that should be heard, so both eat the back cue that
		# ModalMenu.restore_mouse is about to fire inside close() — otherwise the two stack a frame apart. The
		# refusal used to fall through to that back cue alone, which was a lie by omission: pressing Confirm and
		# hearing the ordinary close sound reads as "done", not as "you can't afford this".
		var refunded: int = _station.do_respec(_player)
		if refunded > 0:
			MenuStyle.play_commit()
		else:
			MenuStyle.play_denied()
		MenuStyle.quiet_next_back()
	close()

## Rebuild the refund preview: the perks that will be reversed, the cost, and the Confirm button's enabled state.
func _refresh() -> void:
	if not is_instance_valid(_station) or not is_instance_valid(_player):
		return
	if _rail_btn != null:
		_rail_btn.refresh()  # the rail may have been flipped at an ATM since this screen was built
	var cost_v: Variant = _station.get(&"respec_cost")
	var cost: float = float(cost_v) if (cost_v is float or cost_v is int) else 0.0
	var pm: Object = _station.perk_manager(_player)
	var perks: Array = pm.unlocked_perks() if pm != null else []
	for c in _list.get_children():  # clear the previous preview
		c.queue_free()
	if perks.is_empty():
		var none := Label.new()
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.text = PlayerText.RESPEC_NO_PERKS
		_list.add_child(none)
	else:
		for p in perks:
			var lbl := Label.new()
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # perk names are designer-authored/unbounded: trim, never widen the card
			var dn: String = p.display_name if (p is Perk and not p.display_name.is_empty()) else (String(p.id) if p is Perk else "perk")
			lbl.text = PlayerText.respec_perk_row(dn)
			_list.add_child(lbl)
	# Prose and facts are SEPARATE labels: the 64-char explainer wraps in _blurb, while _status keeps the
	# cost + funds as two short lines (the old single-label "Cost: X     Your zorkmids: Y" space-run plus
	# no-autowrap prose was exactly what dragged the card wide).
	_blurb.text = PlayerText.respec_blurb(perks.size())
	# Heal-screen parity, for real this time (heal_screen._refresh's `cant`): ONE local feeds the danger tint AND
	# the Confirm gate below, so the card can never paint a refusal over a live button. It has to be can_pay, not
	# `money < cost`: the wallet is CASH-ONLY now, so the old cash-only test reddened the facts line for anyone
	# who had banked their zorkmids (wallet 0, account 500, a 200 zm respec) above a Confirm that gated on can_pay
	# and duly succeeded. A FREE respec stays neutral even in debt: it's affordable by definition (RespecStation's
	# zero-cost short-circuit).
	var cant := cost > 0.0 and not _player.can_pay(cost)  # the SAME predicate RespecStation.do_respec gates on
	# Paint the ALL-IN number (shop-screen parity): do_respec debits through charge(), so a ledger-funded respec
	# carries the account's service charge and the sticker price alone would under-quote what actually leaves the
	# player. charge_total re-derives it from the SAME split charge() draws on — and its base<=0 short-circuit
	# keeps a FREE station quoting 0, so the free-for-debtors wording reads exactly as before.
	var shown_cost := _player.charge_total(cost)
	# spendable(), not `money`: the funds readout must count the account (and the armed credit line) that the
	# Confirm gate can actually draw on, or a banked player reads "Your zorkmids: 0" under a working button.
	_status.text = PlayerText.respec_status(shown_cost, _player.spendable())
	_status.add_theme_color_override(&"font_color", MenuStyle.danger() if cant else MenuStyle.text_color())
	# The cost + affordability already read on the _status line above, so the button caption stays SHORT +
	# fixed-width ("Respec — N zm"); can't-afford just greys it out rather than appending a long "(… — can't
	# afford)" caption that would be the one string long enough to clip on the fixed-width card.
	if perks.is_empty():
		_confirm_btn.text = PlayerText.RESPEC_NOTHING
		_confirm_btn.disabled = true
	else:
		_confirm_btn.text = PlayerText.respec_button(shown_cost)  # the same all-in number the status line quotes
		# The same `cant` the status line was tinted from — one predicate, two surfaces. Its cost > 0 guard is
		# what keeps a FREE station clickable for a wallet in DEBT (the free-respec-refused-while-negative wart,
		# UI half), matching RespecStation.do_respec's own fee-only-when-there-is-one gate.
		_confirm_btn.disabled = cant

# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/respec_screen.tscn — this adopts it; mirrors heal_screen.gd)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. What each piece
## still guarantees (the same contracts the old procedural build carried):
##  * the card is a FIXED-WIDTH centered dialog (style_dialog_card pins %Card to skin.dialog_width) — a
##    long station name, perk name, or cost can never grow it or slide it off-centre; title + Confirm are
##    capped (clip + "…"), the blurb/status lines wrap (authored autowrap in the scene).
##  * the refund preview SCROLLS (%Scroll): an unbounded perk list used to grow the card until
##    Confirm/Cancel could fall off-screen on the 432..495-tall canvas. ~5 rows stay visible (body_size +
##    label leading per row — skin-derived, so the pin is applied HERE, not authored); the rest scroll.
##    Horizontal scroll stays off (authored) — perk labels ellipsize instead (see _refresh). The rows
##    themselves are runtime-built into %List; the scene authors only the container.
##  * Confirm + Cancel split the fixed card width EXPAND_FILL (authored, no per-button min a cost caption
##    could push past); Confirm carries 1.5x stretch as the emphasized, destructive action, and clip_text
##    is the safety valve for an absurd cost — the caption stays short ("Respec — N zm") in normal states.
##  * every string is set HERE from PlayerText — the scene ships with empty text properties.
func _bind_ui() -> void:
	_root = %Root
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)
	MenuStyle.style_dialog_card(%Card, 2)  # +2 separation: this few-row card wants a touch more air
	MenuStyle.style_button_row(%Buttons)

	_title = MenuStyle.cap_label(%Title)  # a long station name clips with "…", never widens the card
	MenuStyle.style_title(_title)
	_title.text = MenuStyle.title_text(PlayerText.RESPEC_CARD_TITLE)  # open_respec re-titles per station

	# The prose explainer is a WRAPPING hint (autowrap collapses its min-width) so its long line reflows
	# to the card's width instead of forcing the card as wide as the sentence.
	_blurb = %Blurb
	MenuStyle.style_hint(_blurb)

	_status = %Status  # autowrap authored: cost / zorkmids wrap within the fixed card, never widen it
	_status.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)

	# The scroll's visible-row budget derives from the SKIN's body size, so it's pinned here, not authored.
	var scroll: ScrollContainer = %Scroll
	scroll.custom_minimum_size = Vector2(0, 5 * (MenuStyle.skin.body_size + 9))

	_list = %List

	# The rail selector sits on its own row above Confirm/Cancel so their authored EXPAND_FILL widths survive.
	_rail_btn = %RailButton as PaymentRailButton
	MenuStyle.cap_button(_rail_btn)
	_rail_btn.rail_changed.connect(_refresh)

	_confirm_btn = MenuStyle.cap_button(%ConfirmButton)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	MenuStyle.set_button_sound(_confirm_btn, &"")  # the commit is cued CONDITIONALLY in _on_confirm_pressed (which also eats the close's back cue); the generic click would double it

	_cancel_btn = MenuStyle.cap_button(%CancelButton)
	_cancel_btn.text = PlayerText.CANCEL
	_cancel_btn.pressed.connect(close)  # close() no-ops when not open, so this stays externally safe
