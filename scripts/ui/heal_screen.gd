extends CanvasLayer
## HealScreen — the PAY-TO-HEAL overlay for a Healer component. Autoload; PAUSES the world while open (like
## ShopScreen — PROCESS_MODE_ALWAYS so its button keeps working through the pause); frees the mouse on open.
## Restores HP to FULL and clears ALL limb damage for zorkmids; the cost is LINEAR in missing HP. Opened by
## Healer.start_talk (standalone med-station) or the dialogue "Heal" option (open_heal).

signal opened
signal closed

const PANEL_MARGIN := 0.3

var _root: Control
var _title: Label
var _status: Label
var _heal_btn: Button
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _healer: Node = null  ## a Healer — typed Node to avoid a Healer<->HealScreen class cycle; its API is called dynamically

func _ready() -> void:
	layer = 121                                  # peer of the other modal overlays (loot / inventory / shop)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

## Open the heal screen for `healer`, treating `player`. Refuses to stack over another modal / dialogue, and
## bails safely on an invalid healer or no player.
func open_heal(healer: Node, player: Node) -> void:
	if _is_open or DialogueManager.is_active() or OptionsMenu.is_open() or InventoryScreen.is_open() or LootScreen.is_open() or ShopScreen.is_open() or LevelUpScreen.is_open():
		return
	if not is_instance_valid(healer):
		return
	_player = player as Player
	if not is_instance_valid(_player):
		return
	_healer = healer
	_is_open = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_title.text = "HEAL — %s" % healer.heal_name if not healer.heal_name.is_empty() else "HEAL"
	_refresh()
	_root.visible = true
	get_tree().paused = true  # freeze the world while healing, like the shop (we're PROCESS_MODE_ALWAYS)
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	Input.mouse_mode = _prev_mouse_mode
	_healer = null
	_player = null
	get_tree().paused = false
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	# Close on the SAME Interact key that opens it (the ray consumes the OPENING press — see ray_cast.gd,
	# which skips interacting while we're open), or on Esc.
	if _is_open and (event.is_action_pressed(InputManager.action_pickup) or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

## Pay + heal, then refresh (the button disables once you're fully mended).
func _on_heal_pressed() -> void:
	if is_instance_valid(_healer) and is_instance_valid(_player):
		_healer.do_heal(_player)
		_refresh()

## Update the status line + the Heal button (cost, affordability, nothing-to-heal).
func _refresh() -> void:
	if not is_instance_valid(_healer) or not is_instance_valid(_player):
		return
	var cost: int = _healer.heal_cost(_player)
	var limb := "    — limb damage" if _player.has_limb_damage() else ""
	_status.text = "HP  %d / %d%s\nYour zorkmids: %d" % [int(round(_player.hp)), int(round(_player.max_hp)), limb, _player.money]
	if cost <= 0:
		_heal_btn.text = "Fully healed"
		_heal_btn.disabled = true
	elif _player.money < cost:
		_heal_btn.text = "Heal  (%d zm — can't afford)" % cost
		_heal_btn.disabled = true
	else:
		_heal_btn.text = "Heal  —  %d zm" % cost
		_heal_btn.disabled = false

# ---------------------------------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var theme := Theme.new()
	theme.default_font_size = 15
	_root.theme = theme
	add_child(_root)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.0, 0.0, 0.55)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dimmer)

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

	_title = Label.new()
	_title.text = "HEAL"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_status)

	_heal_btn = Button.new()
	_heal_btn.focus_mode = Control.FOCUS_NONE
	_heal_btn.custom_minimum_size = Vector2(240, 0)
	_heal_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_heal_btn.pressed.connect(_on_heal_pressed)
	vbox.add_child(_heal_btn)

	var hint := Label.new()
	hint.text = "Restores HP to full + mends all limbs.   Esc to close."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)
