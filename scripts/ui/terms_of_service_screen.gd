extends Control

## The first-launch Terms-of-Service consent gate (the fake, comedic EULA). Shown ONCE, after the startup internet
## warning and before the player can use the menu — StartMenu instances it when Settings.tos_accepted is false, hides
## its own buttons behind it, and only records acceptance + releases the startup gate when this screen emits
## `accepted`. There is
## no way past it except agreeing: "Decline" summons an escalating comedic nag whose only exits are "Reconsider"
## (back to the agreement) and "Quit to Desktop" (emits `quit_requested`). Consent precedes play.
##
## Built in code with the shared MenuStyle chrome, structurally a sibling of character_creation.gd: a near-full-screen
## PanelContainer with a PINNED title/subtitle up top, the long agreement body in an EXPAND_FILL ScrollContainer in the
## middle, and a PINNED footnote + Decline/Agree row at the bottom (so the buttons are never buried by the wall of
## text). The document itself is a designer-editable TermsOfService resource (resources/ui/terms_of_service.gd) — this
## screen only renders it. No class_name on purpose (keeps it off the global class cache; StartMenu preloads it), and
## NOT an InputManager modal: like character_creation it's a transient menu-time overlay, not an autoload gameplay
## modal, and the menu behind it is hidden so nothing it fails to block can start a game.

signal accepted        ## the player irrevocably agreed — StartMenu records consent and boots
signal quit_requested  ## the player chose to leave rather than consent — StartMenu quits the game

const PANEL_MARGIN := 0.04  ## tiny margin -> the panel nearly fills the 792x444 UI canvas (the long text wants room)

var _terms: TermsOfService
var _scroll: ScrollContainer
var _agree_btn: Button
var _scroll_hint: Label

# The decline nag: a hidden sub-overlay (dim + centered dialog) raised when Decline is pressed — just the two choices
# (Back / Quit to Desktop), no prompt text above them. Built once, toggled by visibility.
var _nag_root: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so the (hidden) menu buttons behind us don't get them
	_terms = TermsOfService.load_default()    # the .tres if a designer authored one, else the baked defaults
	MenuStyle.apply(self)  # shared menu Theme + button sounds
	_build_ui()
	_build_nag()
	_update_scroll_state.call_deferred()  # after first layout: enables Agree immediately if the body fits without scrolling

func _build_ui() -> void:
	add_child(MenuStyle.make_dim())  # dim the menu behind the panel (also eats clicks)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = PANEL_MARGIN
	panel.anchor_top = PANEL_MARGIN
	panel.anchor_right = 1.0 - PANEL_MARGIN
	panel.anchor_bottom = 1.0 - PANEL_MARGIN
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", MenuStyle.skin.content_separation)
	panel.add_child(vbox)

	# --- Title (+ optional subtitle, only when authored) — PINNED above the scroll ---
	vbox.add_child(MenuStyle.make_title(_terms.title))
	if not _terms.subtitle.strip_edges().is_empty():
		vbox.add_child(MenuStyle.make_hint(_terms.subtitle))
	vbox.add_child(MenuStyle.make_separator())

	# --- The agreement body (EXPAND_FILL scroll — takes all slack between the header and the pinned buttons) ---
	# Horizontal scroll DISABLED forces the child to the container's width, so the body Label WRAPS instead of
	# running one endless line (same idiom as character_creation's stat scroll).
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll)

	var body_label := Label.new()
	body_label.text = _terms.body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(body_label)

	vbox.add_child(MenuStyle.make_separator())

	# --- Scroll footnote (updates when the end is reached) ---
	_scroll_hint = MenuStyle.make_hint(_terms.scroll_hint_unread)
	vbox.add_child(_scroll_hint)

	# --- Decline / Agree (PINNED below the scroll — always visible) ---
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", MenuStyle.skin.button_row_separation)
	vbox.add_child(btn_row)

	var decline_btn := Button.new()
	decline_btn.text = _terms.decline_label
	decline_btn.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	decline_btn.pressed.connect(_on_decline)
	btn_row.add_child(decline_btn)

	_agree_btn = Button.new()
	_agree_btn.text = _terms.accept_label
	_agree_btn.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	_agree_btn.disabled = _terms.require_scroll  # unlocks once the player scrolls to the end (or immediately if it fits)
	_agree_btn.pressed.connect(_on_agree)
	btn_row.add_child(_agree_btn)

	# Gate the Agree button on scroll position. `changed` fires when the range/page updates (initial layout, resize);
	# `value_changed` fires as the player scrolls — both re-evaluate whether the end has been reached.
	var vbar := _scroll.get_v_scroll_bar()
	if vbar != null:
		vbar.changed.connect(_update_scroll_state)
		vbar.value_changed.connect(func(_v: float) -> void: _update_scroll_state())

## Enable "I Agree" once the player has read to the bottom (or right away if the body is short enough to need no
## scrolling, or if require_scroll is off) — and swap the footnote to its "you may now agree" wording. Idempotent;
## driven by the scrollbar's changed/value_changed signals plus a deferred first call.
func _update_scroll_state() -> void:
	if _agree_btn == null or _scroll == null or not is_instance_valid(_scroll):
		return
	var at_end := true
	if _terms.require_scroll:
		var vbar := _scroll.get_v_scroll_bar()
		if vbar != null and vbar.max_value > vbar.page + 1.0:
			# There IS something to scroll — require the view to reach the bottom (1px slack for rounding).
			at_end = vbar.value >= vbar.max_value - vbar.page - 1.0
		# else: the whole document fits on screen; there is nothing to scroll, so treat it as read.
	_agree_btn.disabled = not at_end
	if _scroll_hint != null:
		_scroll_hint.text = _terms.scroll_hint_read if at_end else _terms.scroll_hint_unread

## The decline nag: a dim + centered dialog raised over the agreement — just the two choices, no prompt text. Back
## hides it, Quit leaves the game. Its only purpose is to make clear there is no path forward but consent — while
## giving a genuine way OUT (quit), so the player is gated, never trapped.
func _build_nag() -> void:
	_nag_root = Control.new()
	_nag_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_nag_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_nag_root.visible = false
	add_child(_nag_root)

	_nag_root.add_child(MenuStyle.make_dim())
	var v := MenuStyle.make_dialog(_nag_root)  # fixed-width card, centered at any canvas size

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", MenuStyle.skin.button_row_separation)
	v.add_child(row)

	var back := Button.new()
	back.text = _terms.reconsider_label
	back.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # EXPAND so a caption never grows the fixed-width card
	back.pressed.connect(_hide_nag)
	row.add_child(back)

	var quit := Button.new()
	quit.text = _terms.quit_label
	quit.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(func() -> void: quit_requested.emit())
	row.add_child(quit)

## Decline: there is no declining — raise the bare Back / Quit-to-Desktop nag. Consent is the only way forward.
func _on_decline() -> void:
	if _nag_root != null:
		_nag_root.visible = true

func _hide_nag() -> void:
	if _nag_root != null:
		_nag_root.visible = false

func _on_agree() -> void:
	accepted.emit()
