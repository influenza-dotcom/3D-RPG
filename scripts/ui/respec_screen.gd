extends CanvasLayer
## RespecScreen — the CONFIRM overlay for a RespecStation. Autoload; PAUSES the world while open (PROCESS_MODE_ALWAYS
## so its buttons keep working through the pause) and frees the mouse. Previews the respec COST + the perks that
## will be refunded, then Confirm calls RespecStation.do_respec (reverse every perk, refund its skill point, charge
## the fee). Opened by RespecStation.start_talk. Mirrors HealScreen — the single-transaction modal shape — so a
## respec now asks before it wipes a build, instead of firing instantly on Interact.

signal opened
signal closed


var _root: Control
var _title: Label
var _blurb: Label   ## wrapping prose explainer (what a respec does) — split from _status so its long line can't widen the card
var _status: Label  ## the short facts: cost + current zorkmids
var _list: VBoxContainer
var _confirm_btn: Button
var _cancel_btn: Button
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _station: Node = null  ## a RespecStation — typed Node to avoid a RespecStation<->RespecScreen class cycle; API called dynamically

func _ready() -> void:
	layer = 121                                  # peer of the other modal overlays (loot / inventory / shop / heal)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

## Open the confirm modal for `station`, respec-ing `player`. Refuses to stack over another modal / dialogue, and
## bails safely on an invalid station or no player. Nothing is charged or reversed until the player clicks Confirm.
func open_respec(station: Node, player: Node) -> void:
	if _is_open or DialogueManager.is_active() or InputManager.any_modal_open(self):  # M5: refuse over ANY other menu (incl. QuestJournal)
		return
	if not is_instance_valid(station):
		return
	_player = player as Player
	if not is_instance_valid(_player):
		return
	_station = station
	_is_open = true
	_prev_mouse_mode = ModalMenu.grab_mouse()
	var name_v: Variant = station.get(&"station_name")  # duck-typed: only is_instance_valid was checked, not the type
	var nm: String = name_v if name_v is String else ""
	# Runtime re-title MUST route through title_text() — make_title only cases its constructor argument.
	_title.text = MenuStyle.title_text(PlayerText.respec_title(nm))
	_refresh()
	_root.visible = true
	get_tree().paused = true  # freeze the world while confirming, like the shop/heal/level-up (we're PROCESS_MODE_ALWAYS)
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	ModalMenu.restore_mouse(_prev_mouse_mode)
	_station = null
	_player = null
	get_tree().paused = false
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	# Close (= Cancel) on the SAME Interact key that opens it (the ray consumes the OPENING press — see ray_cast.gd,
	# which skips interacting while a pausing modal is open), or on Esc. Confirm is an explicit button click.
	if _is_open and (event.is_action_pressed(InputManager.action_pickup) or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

## Commit the respec (the station is the single source of the transaction), then close. do_respec is self-guarding,
## so even if the Confirm button somehow fired while broke / with no perks, nothing bad happens.
func _on_confirm_pressed() -> void:
	if is_instance_valid(_station) and is_instance_valid(_player):
		_station.do_respec(_player)
	close()

## Rebuild the refund preview: the perks that will be reversed, the cost, and the Confirm button's enabled state.
func _refresh() -> void:
	if not is_instance_valid(_station) or not is_instance_valid(_player):
		return
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
			lbl.text = "•  %s" % dn
			_list.add_child(lbl)
	# Prose and facts are SEPARATE labels: the 64-char explainer wraps in _blurb, while _status keeps the
	# cost + funds as two short lines (the old single-label "Cost: X     Your zorkmids: Y" space-run plus
	# no-autowrap prose was exactly what dragged the card wide).
	_blurb.text = PlayerText.respec_blurb(perks.size())
	_status.text = PlayerText.respec_status(cost, _player.money)
	# The cost + affordability already read on the _status line above, so the button caption stays SHORT +
	# fixed-width ("Respec — N zm"); can't-afford just greys it out rather than appending a long "(… — can't
	# afford)" caption that would be the one string long enough to clip on the fixed-width card.
	if perks.is_empty():
		_confirm_btn.text = PlayerText.RESPEC_NOTHING
		_confirm_btn.disabled = true
	else:
		_confirm_btn.text = PlayerText.respec_button(cost)
		_confirm_btn.disabled = float(_player.money) < cost

# ---------------------------------------------------------------------------------------------------
# UI construction (mirrors heal_screen.gd)
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	add_child(_root)

	_root.add_child(MenuStyle.make_dim())

	# A FIXED-WIDTH centered card (MenuStyle.make_dialog) — pinned to skin.dialog_width so a long station name,
	# perk name, or cost can't grow the card or slide it off-centre (the old content-hugging panel's width
	# tracked its widest string). The helper builds the CenterContainer + panel + pinned VBox; we fill it and
	# CAP the unbounded children (title, perk rows, confirm caption) so the pin holds.
	var vbox := MenuStyle.make_dialog(_root, 2)  # +2 separation: this few-row card wants a touch more air

	_title = MenuStyle.cap_label(MenuStyle.make_title("Respec"))  # a long station name clips with "…", never widens the card
	vbox.add_child(_title)

	# The prose explainer is a WRAPPING hint (autowrap collapses its min-width) so its long line reflows
	# to the card's width instead of forcing the card as wide as the sentence.
	_blurb = MenuStyle.make_hint("")
	vbox.add_child(_blurb)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # cost / zorkmids wrap within the fixed card, never widen it
	_status.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	vbox.add_child(_status)

	vbox.add_child(MenuStyle.make_separator())

	# The refund preview SCROLLS: an unbounded perk list used to grow the card until Confirm/Cancel could
	# fall off-screen on the 432..495-tall canvas. ~5 rows stay visible (body_size + label leading per row);
	# the rest scroll. Horizontal scroll stays off — perk labels ellipsize instead (see _refresh).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 5 * (MenuStyle.skin.body_size + 9))
	vbox.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # give centred rows the full card width inside the scroll
	_list.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(_list)

	vbox.add_child(MenuStyle.make_separator())

	# Confirm + Cancel split the fixed card width via EXPAND_FILL (no per-button min that a cost caption could
	# push past); Confirm gets 1.5x the stretch as the emphasized, destructive action. clip_text is the safety
	# valve for an absurd cost — the caption stays short ("Respec — N zm") in normal states.
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", MenuStyle.skin.button_row_separation)
	vbox.add_child(buttons)

	_confirm_btn = MenuStyle.cap_button(Button.new())
	_confirm_btn.focus_mode = Control.FOCUS_NONE
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_btn.size_flags_stretch_ratio = 1.5  # wider than Cancel — Confirm carries the cost + is the destructive action
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	buttons.add_child(_confirm_btn)

	_cancel_btn = MenuStyle.cap_button(Button.new())
	_cancel_btn.focus_mode = Control.FOCUS_NONE
	_cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(close)
	buttons.add_child(_cancel_btn)
