extends CanvasLayer
## HealScreen — the PAY-TO-HEAL overlay for a Healer component. Autoload; PAUSES the world while open (like
## ShopScreen — PROCESS_MODE_ALWAYS so its button keeps working through the pause); frees the mouse on open.
## Restores HP to FULL and clears ALL limb damage for zorkmids; the cost is LINEAR in missing HP. Opened by
## Healer.start_talk (standalone med-station) or the dialogue "Heal" option (open_heal).

signal opened
signal closed


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
	if _is_open or DialogueManager.is_active() or InputManager.any_modal_open(self):  # M5: refuse over ANY other menu (incl. QuestJournal)
		return
	if not is_instance_valid(healer):
		return
	_player = player as Player
	if not is_instance_valid(_player):
		return
	_healer = healer
	_is_open = true
	_prev_mouse_mode = ModalMenu.grab_mouse()
	var heal_name_v: Variant = healer.get(&"heal_name")  # duck-typed: only is_instance_valid was checked, not the type
	var heal_nm: String = heal_name_v if heal_name_v is String else ""
	# Runtime re-title MUST route through title_text() — make_title only cases its constructor argument.
	_title.text = MenuStyle.title_text(PlayerText.heal_title(heal_nm))
	_refresh()
	_root.visible = true
	get_tree().paused = true  # freeze the world while healing, like the shop (we're PROCESS_MODE_ALWAYS)
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	ModalMenu.restore_mouse(_prev_mouse_mode)
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
	# The affordability wording rides the WRAPPING status line (not the button) so the button caption stays
	# short + fixed-width — the card is pinned to skin.dialog_width and a long "can't afford" caption would
	# otherwise be the one string long enough to clip on the button. We pass only the FACTS (limb damage on
	# its own line, affordability): PlayerText.heal_status selects one of four whole authored templates —
	# this screen never assembles line fragments (the TextFormat rule).
	var cant := cost > 0 and _player.money < cost
	var status_text := PlayerText.heal_status(int(round(_player.hp)), int(round(_player.max_hp)), _player.has_limb_damage(), _player.money, cant)
	# Pad the status to a CONSTANT 4 lines (HP / limb / zorkmids / note is the worst case). make_dialog pins
	# the card's WIDTH only — its height shrink-wraps and the CenterContainer re-centers on every height
	# change, so when a Heal click cleared the limb line the whole card (title, text, buttons) visibly hopped
	# mid-transaction. Blank pad lines keep the height identical in every state (and across opens).
	while status_text.count("\n") < 3:
		status_text += "\n "
	_status.text = status_text
	_status.add_theme_color_override(&"font_color", MenuStyle.danger() if cant else MenuStyle.text_color())
	if cost <= 0:
		_heal_btn.text = PlayerText.HEAL_FULLY_HEALED
		_heal_btn.disabled = true
	else:
		_heal_btn.text = PlayerText.heal_button(cost)  # short caption in every state; can't-afford greys it out (below)
		_heal_btn.disabled = cant

# ---------------------------------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	add_child(_root)

	_root.add_child(MenuStyle.make_dim())

	# A FIXED-WIDTH centered card (MenuStyle.make_dialog): the card is pinned to skin.dialog_width, so a long
	# healer name in the title or a big cost can't grow it or slide it off-centre the way the old content-hugging
	# panel did (its width tracked its widest string). The helper handles the CenterContainer + panel + pinned
	# VBox; we just fill it and CAP the unbounded children so the pin holds.
	var vbox := MenuStyle.make_dialog(_root, 2)  # +2 separation: this few-row card wants a touch more air

	_title = MenuStyle.cap_label(MenuStyle.make_title(PlayerText.HEAL_SCREEN_TITLE))  # a long healer name clips with "…", never widens the card

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # HP / cost / can't-afford wrap within the fixed card, never widen it
	_status.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	vbox.add_child(_title)
	vbox.add_child(_status)

	# Heal + Close side by side: once fully healed the Heal button DISABLES, so without Close a mouse-only
	# player had no visible way out (Esc/Interact still close too — see _unhandled_input). EXPAND_FILL splits the
	# fixed card width between them (no per-button width that a caption could push past); clip_text is the safety
	# valve for an absurd cost — the "can't afford" wording lives on the wrapping status line, so the caption stays
	# short ("Heal — N zm") in every normal state.
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", MenuStyle.skin.button_row_separation)
	vbox.add_child(buttons)

	_heal_btn = MenuStyle.cap_button(Button.new())
	_heal_btn.focus_mode = Control.FOCUS_NONE
	_heal_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heal_btn.pressed.connect(_on_heal_pressed)
	buttons.add_child(_heal_btn)

	var close_btn := MenuStyle.cap_button(Button.new())
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.text = PlayerText.CLOSE
	close_btn.pressed.connect(close)  # close() no-ops when not open, so this stays externally safe
	buttons.add_child(close_btn)
