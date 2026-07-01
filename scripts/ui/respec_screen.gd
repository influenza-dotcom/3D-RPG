extends CanvasLayer
## RespecScreen — the CONFIRM overlay for a RespecStation. Autoload; PAUSES the world while open (PROCESS_MODE_ALWAYS
## so its buttons keep working through the pause) and frees the mouse. Previews the respec COST + the perks that
## will be refunded, then Confirm calls RespecStation.do_respec (reverse every perk, refund its skill point, charge
## the fee). Opened by RespecStation.start_talk. Mirrors HealScreen — the single-transaction modal shape — so a
## respec now asks before it wipes a build, instead of firing instantly on Interact.

signal opened
signal closed

const PANEL_MARGIN := 0.3

var _root: Control
var _title: Label
var _status: Label
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
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() or InventoryScreen.is_open() or LootScreen.is_open() or ShopScreen.is_open() or LevelUpScreen.is_open() or StatsScreen.is_open() or ReputationScreen.is_open() or HealScreen.is_open():
		return
	if not is_instance_valid(station):
		return
	_player = player as Player
	if not is_instance_valid(_player):
		return
	_station = station
	_is_open = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var name_v: Variant = station.get(&"station_name")  # duck-typed: only is_instance_valid was checked, not the type
	var nm: String = name_v if name_v is String else ""
	_title.text = "RESPEC — %s" % nm if not nm.is_empty() else "RESPEC"
	_refresh()
	_root.visible = true
	get_tree().paused = true  # freeze the world while confirming, like the shop/heal/level-up (we're PROCESS_MODE_ALWAYS)
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	Input.mouse_mode = _prev_mouse_mode
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
		none.text = "(no perks unlocked)"
		_list.add_child(none)
	else:
		for p in perks:
			var lbl := Label.new()
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var dn: String = p.display_name if (p is Perk and not p.display_name.is_empty()) else (String(p.id) if p is Perk else "perk")
			lbl.text = "•  %s" % dn
			_list.add_child(lbl)
	_status.text = "Refund %d perk%s — skill points return to re-spend at a Level Up.\nCost: %s     Your zorkmids: %s" % [
		perks.size(), "" if perks.size() == 1 else "s", Zorkmids.fmt(cost), Zorkmids.fmt(_player.money)]
	if perks.is_empty():
		_confirm_btn.text = "Nothing to respec"
		_confirm_btn.disabled = true
	elif float(_player.money) < cost:
		_confirm_btn.text = "Respec  (%s — can't afford)" % Zorkmids.fmt(cost)
		_confirm_btn.disabled = true
	else:
		_confirm_btn.text = "Respec  —  %s" % Zorkmids.fmt(cost)
		_confirm_btn.disabled = false

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
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	_title = MenuStyle.make_title("Respec")
	vbox.add_child(_title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	vbox.add_child(_status)

	vbox.add_child(MenuStyle.make_separator())

	_list = VBoxContainer.new()
	_list.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_list)

	vbox.add_child(MenuStyle.make_separator())

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	vbox.add_child(buttons)

	_confirm_btn = Button.new()
	_confirm_btn.focus_mode = Control.FOCUS_NONE
	_confirm_btn.custom_minimum_size = Vector2(240, 0)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	buttons.add_child(_confirm_btn)

	_cancel_btn = Button.new()
	_cancel_btn.focus_mode = Control.FOCUS_NONE
	_cancel_btn.custom_minimum_size = Vector2(160, 0)
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(close)
	buttons.add_child(_cancel_btn)
