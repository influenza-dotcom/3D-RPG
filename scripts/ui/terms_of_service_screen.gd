extends Control

## The first-launch Terms-of-Service consent gate (the fake, comedic EULA). Shown ONCE, after the startup internet
## warning and before the player can use the menu — StartMenu instances it when Settings.tos_accepted is false, hides
## its own buttons behind it, and only records acceptance + releases the startup gate when this screen emits
## `accepted`. There is
## no way past it except agreeing: "Decline" summons an escalating comedic nag whose only exits are "Reconsider"
## (back to the agreement) and "Quit to Desktop" (emits `quit_requested`). Consent precedes play.
##
## AUTHORED SCENE: the layout lives in scenes/ui/terms_of_service_screen.tscn (StartMenu instances that scene — its
## root carries this script), structurally a sibling of character_creation: a near-full-screen PanelContainer (anchors
## 0.04..0.96 of the 792x444 UI canvas — the old PANEL_MARGIN const, now editor-owned structure) with a PINNED
## title/subtitle up top, the long agreement body in an EXPAND_FILL ScrollContainer in the middle, and a PINNED
## footnote + Decline/Agree row at the bottom (so the buttons are never buried by the wall of text). _bind_ui binds
## the chrome by %unique name and applies the skin-driven look (MenuStyle adopt-helpers) on top, so a designer
## rearranges the panel in the editor and the skin keeps owning colours/fonts/width pins. NO text is authored in the
## scene — every string comes from the designer-editable TermsOfService resource (resources/ui/terms_of_service.gd);
## this screen only renders it. No class_name on purpose (keeps it off the global class cache; StartMenu preloads the
## SCENE), and NOT an InputManager modal: like character_creation it's a transient menu-time overlay, not an autoload
## gameplay modal, and the menu behind it is hidden so nothing it fails to block can start a game.
## tests/test_terms_of_service_scene.gd pins the wiring; tests/test_terms_of_service.gd covers content + focus policy.

signal accepted        ## the player irrevocably agreed — StartMenu records consent and boots
signal quit_requested  ## the player chose to leave rather than consent — StartMenu quits the game

var _terms: TermsOfService
var _scroll: ScrollContainer
var _agree_btn: Button
var _decline_btn: Button
var _scroll_hint: Label

# The decline nag: a hidden sub-overlay (dim + centered dialog) raised when Decline is pressed — just the two choices
# (Back / Quit to Desktop), no prompt text above them. Authored in the scene, ships hidden, toggled by visibility.
var _nag_root: Control

func _ready() -> void:
	# Full-rect anchors + MOUSE_FILTER_STOP (eat clicks so the hidden menu buttons behind us never get them)
	# are authored in the scene, along with the dim and the near-full panel (the old PANEL_MARGIN 0.04 band).
	_terms = TermsOfService.load_default()    # the .tres if a designer authored one, else the baked defaults
	MenuStyle.apply(self)  # shared menu Theme + button sounds
	_bind_ui()
	_bind_nag()
	_update_scroll_state.call_deferred()  # after first layout: enables Agree immediately if the body fits without scrolling
	# Deliberately NO focus grab here (MOUSE-FIRST, the start-menu policy): auto-focusing Decline painted it
	# with the skin's focus chrome from the first frame — a consent gate whose "Decline" sits permanently
	# highlighted, with Enter wired to press it. Pad/keyboard players still aren't stranded: the first
	# ui_left/right (or Tab) press with nothing focused seeds focus on demand — see _input.

## Keyboard / controller handling. Two jobs: (1) consume `ui_cancel` while this gate is up so it can't fall through to the
## OptionsMenu autoload, whose Escape toggle would STACK the settings panel over the legal-consent wall (its open() guard
## only knows about the InputManager modal registry, which this transient menu-time overlay deliberately isn't in). (2) map
## ui_up/ui_down to SCROLL the agreement, so a pad- or keyboard-only player (the game ships full controller bindings) can
## reach the bottom to unlock Agree — the scroll-to-end gate was otherwise mouse-wheel-only, a first-launch hard stop.
func _input(event: InputEvent) -> void:
	if not visible or not is_inside_tree():
		return
	if _nag_root != null and _nag_root.visible:
		if event.is_action_pressed(&"ui_cancel"):
			_hide_nag()  # Escape backs out of the decline nag ("Reconsider")
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel"):
		_on_decline()  # Escape == Decline; consume so it can't stack the OptionsMenu over the gate
		get_viewport().set_input_as_handled()
		return
	# MOUSE-FIRST focus seeding (the start-menu policy): nothing is focused until a keyboard/controller player
	# expresses NAVIGATION intent on the button row's axis — ui_left/right (or Tab), NOT ui_up/down, which are
	# the scroll keys below and must never light a button as a side effect of reading the agreement. Seeds on
	# Decline: it is the always-enabled button (Agree may still be locked behind the scroll gate), and an
	# accidental Enter there only raises the comedic nag — it can never consent on the player's behalf.
	if get_viewport().gui_get_focus_owner() == null and _decline_btn != null \
			and (event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right") \
			or event.is_action_pressed(&"ui_focus_next") or event.is_action_pressed(&"ui_focus_prev")):
		_decline_btn.grab_focus()
		get_viewport().set_input_as_handled()
		return
	if _scroll != null and _terms != null and _terms.require_scroll:
		var vbar := _scroll.get_v_scroll_bar()
		if vbar != null and vbar.max_value > vbar.page:
			var step := maxf(vbar.page * 0.25, 24.0)
			if event.is_action_pressed(&"ui_down", true):
				vbar.value += step
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed(&"ui_up", true):
				vbar.value -= step
				get_viewport().set_input_as_handled()

## Bind the authored chrome by %unique name (structure lives in scenes/ui/terms_of_service_screen.tscn), apply the
## skin-derived values on top, and paint the TermsOfService document into it. Every contract the old procedural
## build carried holds: pinned header + footnote + button row around an EXPAND_FILL scroll, the scroll-to-end
## Agree gate, and skin-owned separations/button widths (never authored — they'd go stale with the skin).
func _bind_ui() -> void:
	MenuStyle.style_dim(%Dim)  # the authored dim over the hidden menu behind the panel (skin colour + eats clicks)

	# The panel's root column: shared skin separation (a skin knob, so applied here — never authored).
	(%Column as VBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.content_separation)

	# --- Title (+ optional subtitle, shown only when authored) — PINNED above the scroll ---
	var title: Label = MenuStyle.cap_label(%Title)
	MenuStyle.style_title(title)
	title.text = MenuStyle.title_text(_terms.title)
	var subtitle: Label = %Subtitle
	MenuStyle.style_hint(subtitle)
	subtitle.text = _terms.subtitle
	# The subtitle slot is authored but collapses when no subheader is authored (the old build simply never added
	# one). A VBox drops a hidden child from layout — here that's the POINT: no dead hint-line above the agreement.
	subtitle.visible = not _terms.subtitle.strip_edges().is_empty()

	# --- The agreement body (EXPAND_FILL scroll — takes all slack between the header and the pinned buttons) ---
	# Horizontal scroll DISABLED (authored) forces the child to the container's width, so the body Label WRAPS
	# instead of running one endless line (same idiom as character_creation's stat scroll).
	_scroll = %Scroll
	(%BodyLabel as Label).text = _terms.body

	# --- Scroll footnote (updates when the end is reached) ---
	_scroll_hint = %ScrollHint
	MenuStyle.style_hint(_scroll_hint)
	_scroll_hint.text = _terms.scroll_hint_unread

	# --- Decline / Agree (PINNED below the scroll — always visible) ---
	# Skin-driven dialog row: shared separation + the skin's dialog button width floor, applied here so the pair
	# matches every other menu's bottom button row. Both buttons keep FOCUS_ALL (scene default) — the MOUSE-FIRST
	# focus seeding in _input needs Decline focusable on demand.
	MenuStyle.style_button_row(%Buttons)
	_decline_btn = %DeclineButton
	_decline_btn.text = _terms.decline_label
	_decline_btn.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	_decline_btn.pressed.connect(_on_decline)
	# MUTED on purpose: Escape reaches _on_decline through _input too, so the cue lives in that ONE handler
	# (see it for WHICH cue and why) — leaving the generic click on top would double the mouse path.
	MenuStyle.set_button_sound(_decline_btn, &"")

	_agree_btn = %AgreeButton
	_agree_btn.text = _terms.accept_label
	_agree_btn.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	_agree_btn.disabled = _terms.require_scroll  # unlocks once the player scrolls to the end (or immediately if it fits)
	_agree_btn.pressed.connect(_on_agree)
	# Consent is a HEAVY commit — it is recorded to disk and never asked again. The cue rides the BUTTON, not
	# the handler: agreeing is reachable ONLY from here (there is no Escape-to-accept), it maps 1:1 to the act,
	# and it cannot fail — the scroll gate keeps the button DISABLED until it may be pressed, and a disabled
	# Button emits no `pressed`, so the refused case is structurally silent already.
	MenuStyle.set_button_sound(_agree_btn, &"commit")

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
## giving a genuine way OUT (quit), so the player is gated, never trapped. Authored in the scene (ships hidden,
## full-rect + click-eating); this adopts its chrome and wires the two buttons.
func _bind_nag() -> void:
	_nag_root = %NagRoot
	MenuStyle.style_dim(%NagDim)
	MenuStyle.style_dialog_card(%NagCard)  # fixed-width card (skin.dialog_width), centered at any canvas size
	MenuStyle.style_button_row(%NagButtons)

	var back: Button = %BackButton
	back.text = _terms.reconsider_label
	back.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	# EXPAND (authored) so a caption never grows the fixed-width card.
	back.pressed.connect(_hide_nag)
	# MUTED: Escape dismisses the nag through the same handler (_input's nag branch), so the back cue is fired
	# once in _hide_nag instead of once here and never there.
	MenuStyle.set_button_sound(back, &"")

	var quit: Button = %QuitButton
	quit.text = _terms.quit_label
	quit.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	quit.pressed.connect(func() -> void: quit_requested.emit())

## Decline: there is no declining — raise the bare Back / Quit-to-Desktop nag. Consent is the only way forward.
## SELECT, not back: nothing closes here, a sub-dialog RISES — so the light click voice is the honest cue, and
## it is also the exact clip the (now muted) Decline button used to give away for free, leaving the mouse path
## unchanged while filling the Escape path, which is not a Button and would otherwise be silent. Cued inside
## the guard so the sound only ever means "the nag is up".
func _on_decline() -> void:
	if _nag_root != null:
		_nag_root.visible = true
		MenuStyle.play_select()

## Dismiss the nag ("Reconsider" or Escape) — a genuine back-out, and the one cue site for both entry paths.
func _hide_nag() -> void:
	if _nag_root != null:
		_nag_root.visible = false
		MenuStyle.play_back()

func _on_agree() -> void:
	accepted.emit()
