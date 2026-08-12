class_name DialogueView
extends Node

## The dialogue box's VISUALS — the bottom text panel + cinematic letterbox bars, built in code, pulled
## out of DialogueManager. A code-built child of the manager (PROCESS_MODE_ALWAYS owner, so the box /
## choices keep rendering + advancing while the world is paused). Owns the CanvasLayer and every Control
## under it; the manager drives it through open() / close() / show_line() / set_choices() /
## add_extra_choice() / clear_choices(). Choice buttons fire back a Callable the manager supplies, so the
## jump / re-render logic stays in the coordinator.

# The letterbox bar height + slide-in duration are designer knobs on GameSettings.dialogue
# (letterbox_bar_height_fraction / letterbox_slide_in_duration).

## Faction registry (preloaded by path) for the reputation gate (WR-1).
const Factions = preload("res://scripts/faction/factions.gd")

var _layer: CanvasLayer
var _panel: PanelContainer
var _speaker_label: Label
var _text_label: Label
var _hint: Label                  # plain "continue" prompt; hidden while a line shows choices
var _choices_box: VBoxContainer   # holds one Button per choice; emptied each line
var _choices_scroll: ScrollContainer  # wraps the choices box + caps its height so many options SCROLL instead of overflowing off the top of the screen
var _bar_top: ColorRect           # cinematic letterbox bars; slid in on start, collapsed on finish
var _bar_bottom: ColorRect
var _letterbox_tween: Tween

## The letterbox bars' slide-in duration, exposed so the camera's dialogue zoom can be timed to match.
func letterbox_time() -> float:
	return GameSettings.dialogue.letterbox_slide_in_duration

## Open the box for a new conversation: build the UI lazily, show the layer, and keep the text panel +
## speaker name hidden through the intro beat (so the PRIOR conversation's speaker name doesn't flash
## before show_line() sets the new one). Slides the letterbox bars in.
func open() -> void:
	if _layer == null:
		_build_ui()
	_layer.visible = true
	_panel.visible = false  # keep the text box hidden during the intro beat
	# Hide + clear the name label during the intro too, so the PRIOR conversation's speaker name
	# doesn't flash for the half-second before show_line() sets the new one.
	_speaker_label.text = ""
	_speaker_label.visible = false
	_animate_letterbox_in()

## Reveal the text panel once the intro beat is over (the box "opens" with the first line).
func reveal_panel() -> void:
	if _panel != null:
		_panel.visible = true

## Tear down the box on finish: drop any lingering choice buttons, hide the layer, and collapse the
## bars (the layer's hidden anyway) so they re-slide in next conversation.
func close() -> void:
	clear_choices()  # drop any choice buttons so none linger into the next conversation
	if _layer:
		_layer.visible = false
	if _bar_top:
		_bar_top.offset_bottom = 0.0
		_bar_bottom.offset_top = 0.0

## Hide/show the box WITHOUT tearing it down — used to SUSPEND the conversation while a sub-menu (shop /
## level-up / heal / exchange) is open, then restore it intact when that menu closes.
func set_layer_hidden(hidden: bool) -> void:
	if _layer != null:
		_layer.visible = not hidden

## Show one line's text + speaker name. The speaker name comes from the talking character (resolved by
## the manager); an empty name hides the label. Caller drives TTS + choices separately, in order.
func show_line(text: String, speaker_name: String, name_color: Color = Color.WHITE) -> void:
	_speaker_label.text = speaker_name
	_speaker_label.visible = not speaker_name.is_empty()
	_speaker_label.add_theme_color_override("font_color", name_color)  # tinted by disposition (#13)
	_text_label.text = text

## Populate the line's authored choices: swap the continue hint for one selectable Button per choice.
## Each button fires `cb` bound to its target index (FOCUS_NONE so ui_accept can't re-press a focused
## button — selection is mouse-click driven). An empty `choices` leaves the hint up for a linear line.
func set_choices(choices: Array, cb: Callable) -> void:
	if choices.is_empty():
		_choices_scroll.visible = false
		_hint.visible = true
		return
	_hint.visible = false
	_choices_scroll.visible = true
	for choice in choices:
		if _hide_for_stat_requirement(choice):
			continue
		var b := Button.new()
		b.add_theme_font_size_override("font_size", GameSettings.dialogue.choice_button_font_size)  # rein in the (large) default theme font so the options fit
		b.text = choice.text
		# Passing stat gates are shown on the label; failed stat gates were skipped before the button was built.
		# Other gates stay visible and use `passed` for the fail-branch path.
		# `passed` rides to the handler so non-stat gate failures skip consequences and route to target_on_fail.
		var passed := true
		if choice.required_stat != &"":
			b.text = stat_gate_label(choice.required_stat, choice.required_value, choice.text)
		if choice.required_flag != &"":
			passed = passed and str(GameState.get_flag(choice.required_flag)) == choice.required_flag_value
		# WR-1/WR-3 reputation / perk / item / quest gates — folded into the SAME `passed` accumulation.
		passed = passed and _state_gates_pass(choice)
		# Non-stat failed gates stay SELECTABLE (FNV-style): the handler routes them to target_on_fail and skips
		# consequences (`passed` rides along so it can tell). Passing stat gates keep the [stat n] label.
		# FOCUS_NONE so ui_accept (Enter/Space) can't re-press a focused button; selection is
		# mouse-click driven (the mouse is MOUSE_MODE_VISIBLE once the response menu is revealed —
		# _reveal_menu -> _sync_dialogue_cursor; start() itself leaves it HIDDEN for the listen-first line).
		b.focus_mode = Control.FOCUS_NONE
		# add_child BEFORE connecting — the SAME audio-ordering rule add_extra_choice documents at length. Entering
		# the tree is what lets MenuStyle's node_added hook wire the generic click, and that connection must come
		# FIRST: a choice whose handler fires a cue (a consequence that opens Trade / Level Up, or hands out money)
		# has its click swallowed only while the click is ALREADY RINGING, so a click connected second lands on the
		# front of the cue instead of being cut. These two builders were split on this — extra choices were fixed,
		# authored ones were not.
		_choices_box.add_child(b)
		b.pressed.connect(cb.bind(choice, passed))
	_clamp_choices_height.call_deferred()  # cap at ~half-screen so many choices SCROLL rather than clip off the top

## The stat-gate choice label ("[Strength 6] Threaten him") shown on a choice the player QUALIFIES for. The stat
## name routes through StatInfo.title — the SAME authored StatText title (resources/stats/<id>.tres) the stats
## screen / creation / tooltips use — so a dialogue gate can never show a second name for a stat; an unauthored
## id still degrades to the capitalized fallback inside StatInfo.title. Static + pure so the display-name
## contract test (tests/test_display_names.gd) pins it off-tree.
static func stat_gate_label(stat: StringName, value: int, text: String) -> String:
	return "[%s %d] %s" % [StatInfo.title(stat), value, text]

## Stat-gated options should not be offered until the human player actually meets the requirement.
func _hide_for_stat_requirement(choice) -> bool:
	return choice.required_stat != &"" and _player_stat(choice.required_stat) < choice.required_value

## The human player's EFFECTIVE `stat` for a dialogue skill check: raw sheet + live modifiers from held items /
## timed effects. Group-scanned (the view holds no player ref); companions are NPCs in the same group and are
## skipped. BASELINE when no player is found, so an authored check behaves neutrally rather than crashing.
func _player_stat(stat: StringName) -> float:
	var p := Groups.human_player(get_tree())  # M6: the human-player filter lives on Groups
	return _effective_player_stat(p, stat)

static func _effective_player_stat(player: Object, stat: StringName) -> float:
	if player == null or not player.has_method(&"stats_or_default"):
		return float(CharacterStats.BASELINE)
	var sheet: CharacterStats = player.call(&"stats_or_default")
	var value := float(sheet.get_stat(stat)) if sheet != null else float(CharacterStats.BASELINE)
	if player.has_method(&"status_stat_modifier"):
		value += float(player.call(&"status_stat_modifier", stat))
	return value

## WR-1/WR-3 state gates (rep / perk / item / quest) — each empty gate is skipped, so a choice with none behaves
## exactly as before. Reputation + quest state read the autoloads; perk + item read the live player. Fail-closed
## on a missing player / unresolved faction (a misconfigured or unmeetable gate locks the choice, FNV-style).
func _state_gates_pass(choice) -> bool:
	if choice.required_faction_id != "":
		var fac := Factions.by_id(choice.required_faction_id)
		if fac == null or Reputation.get_reputation(fac) < choice.required_reputation:
			return false
	if choice.required_perk_id != &"":
		var pm := _player_perk_manager()
		if pm == null or not pm.has_perk(choice.required_perk_id):
			return false
	if choice.required_item_id != &"":
		if _player_item_count(choice.required_item_id) < choice.required_item_count:
			return false
	if choice.required_quest_id != &"":
		match choice.required_quest_state:
			DialogueChoice.QuestGate.ACTIVE:
				if not GameState.is_quest_active(choice.required_quest_id):
					return false
			DialogueChoice.QuestGate.COMPLETED:
				if not GameState.is_quest_completed(choice.required_quest_id):
					return false
			DialogueChoice.QuestGate.FAILED:  # WR-6: a choice only an NPC who knows you BLEW IT should offer
				if not GameState.is_quest_failed(choice.required_quest_id):
					return false
			_:  # ANY — the player must at least KNOW the quest (active OR completed OR failed)
				if not (GameState.is_quest_active(choice.required_quest_id) or GameState.is_quest_completed(choice.required_quest_id) or GameState.is_quest_failed(choice.required_quest_id)):
					return false
	return true

## The human player node (Groups.human_player — companions are NPCs in the same group and are excluded), or null.
func _player() -> Node:
	return Groups.human_player(get_tree())

## The player's PerkManager child (the BuildGate idiom), or null when there's no player / no manager yet.
func _player_perk_manager() -> PerkManager:
	var p := _player()
	if p == null:
		return null
	for c in p.get_children():
		if c is PerkManager:
			return c
	return null

## How many of `item_id` the live player carries (0 with no player / no inventory).
func _player_item_count(item_id: StringName) -> int:
	var p := _player()
	if p == null or p.get(&"inventory") == null:
		return 0
	return p.inventory.count_of_id(item_id)

## Splice one EXTRA button (label `text`) on top of the line's authored choices / continue prompt, firing
## `cb` when pressed — the synthesized companion recruit/dismiss affordance. Forces the choices box visible
## even on an otherwise-linear line.
func add_extra_choice(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.add_theme_font_size_override("font_size", GameSettings.dialogue.choice_button_font_size)  # match the authored choice buttons' compact size
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # mouse-click driven, like the authored choice buttons
	# add_child BEFORE connecting, and the order matters for AUDIO: entering the tree is what lets MenuStyle's
	# node_added hook wire the generic click, and that connection must come FIRST. These buttons open menus
	# (Trade / Heal / Rest / Level Up / Install / Chess), whose open sting cuts a generic click from the same
	# press — but only one already ringing, so a click connected after the handler would land on the sting's
	# front instead of being swallowed. Goodbye/companion choices carry no cue and just click normally.
	_choices_box.add_child(b)
	b.pressed.connect(cb)
	_choices_scroll.visible = true  # ensure the box shows even on an otherwise-linear line
	_hint.visible = false        # a response menu is up — drop the "continue" prompt
	_clamp_choices_height.call_deferred()

## Listen-first state: show the line's text with only a continue affordance (no response menu yet). The
## menu, if any, is revealed by the manager on the next click — New Vegas-style: hear it, THEN choose.
func show_continue_hint() -> void:
	clear_choices()
	_choices_scroll.visible = false
	_hint.text = _continue_hint_text()  # refresh in case the player rebound the advance key since the box was built
	_hint.visible = true

## The continue affordance, using the LIVE advance binding (dialogue advances on action_pickup / click) rather than
## a hardcoded "[E]" — so a rebind / a controller shows the right prompt, matching the hover-hint convention.
func _continue_hint_text() -> String:
	return PlayerText.dialogue_continue_hint(InputManager.get_action_binding(InputManager.action_pickup))

## Free the buttons spawned for the previous line so labels never stack between lines/conversations.
## remove_child FIRST, then queue_free: queue_free is deferred, so an outgoing button lingers in the tree
## until end-of-frame. _reveal_menu clears-then-re-adds choices and schedules _clamp_choices_height() (also
## deferred) in the SAME frame; if the outgoing buttons were still counted, get_combined_minimum_size() would
## measure DOUBLE the choices and lock the scroll's custom_minimum_size at ~2x — inflating the bottom-anchored
## panel so it grows UPWARD and the whole box jumps off the bottom of the screen. This bit specifically when a
## conversation RESUMED from a sub-menu (Trade/Heal/…): the response menu was still populated at resume, unlike
## the first reveal (where show_continue_hint had already emptied the box). Detaching now keeps the re-measure honest.
func clear_choices() -> void:
	if _choices_box == null:
		return
	for c in _choices_box.get_children():
		_choices_box.remove_child(c)
		c.queue_free()

## Cap the choices area at ~half the viewport height so a many-option line SCROLLS within the box instead of
## growing it up off the top of the screen; a short list still sizes to its content (the box grows just enough).
func _clamp_choices_height() -> void:
	if _choices_scroll == null:
		return
	var max_h := get_viewport().get_visible_rect().size.y * GameSettings.dialogue.choices_scroll_max_height_fraction
	var content_h := _choices_box.get_combined_minimum_size().y
	# The scroll now wears the skin's panel stylebox (the legibility backing) — its top+bottom content
	# margins sit OUTSIDE the choices box's own minimum size, so add them or the last option hides
	# behind a scrollbar in a list that used to fit exactly.
	var panel_sb := _choices_scroll.get_theme_stylebox(&"panel")
	if panel_sb != null:
		content_h += panel_sb.content_margin_top + panel_sb.content_margin_bottom
	_choices_scroll.custom_minimum_size.y = minf(content_h, max_h)

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90  # above the HUD
	add_child(_layer)
	# Cinematic letterbox bars, added first so they draw BEHIND the text box. Collapsed to zero
	# height; _animate_letterbox_in() slides them in on start.
	_bar_top = ColorRect.new()
	_bar_top.color = Color.BLACK
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_top.offset_bottom = 0.0
	_layer.add_child(_bar_top)
	_bar_bottom = ColorRect.new()
	_bar_bottom.color = Color.BLACK
	_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bottom.offset_top = 0.0
	_layer.add_child(_bar_bottom)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = GameSettings.dialogue.panel_horizontal_margin
	_panel.offset_right = -GameSettings.dialogue.panel_horizontal_margin
	# Bottom-pinned but SIZE TO CONTENT, growing UPWARD -- so a line with many choices stacks them up into view
	# instead of overflowing off the bottom of a fixed-height box. (offset_top == offset_bottom collapses the
	# anchor rect to the bottom edge; grow_vertical = BEGIN then expands it up by the content's height.)
	_panel.offset_top = -GameSettings.dialogue.panel_vertical_margin
	_panel.offset_bottom = -GameSettings.dialogue.panel_vertical_margin
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Invisible background — drop the PanelContainer's default box (the "ugly" bg). The text carries its
	# own outline (below) so it stays readable floating over the world.
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_layer.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, GameSettings.dialogue.panel_inner_padding)
	_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", GameSettings.dialogue.panel_vertical_element_spacing)
	margin.add_child(vbox)
	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_size_override("font_size", GameSettings.dialogue.dialogue_text_font_size)
	# Outlined so the text reads against the world now that the panel box is gone.
	_text_label.add_theme_constant_override("outline_size", GameSettings.dialogue.dialogue_text_outline_width)
	_text_label.add_theme_color_override("font_outline_color", Color.BLACK)
	vbox.add_child(_text_label)
	# Choices live in a ScrollContainer so a line with many options scrolls past a ~half-screen cap (set in
	# _clamp_choices_height) instead of growing the box up off the top of the screen.
	_choices_scroll = ScrollContainer.new()
	# The response menu is the box's one CLICKABLE surface, so it alone joins the menu skin: apply()
	# themes just this subtree and stamps `_menu_root`, which the global node_added hook walks for to
	# wire skin hover/click sounds onto every choice button. Deliberately NOT applied to _panel/_layer —
	# the line text, continue hint, and speaker name keep their outlined over-the-world look and their
	# GameSettings.dialogue font sizes (the per-button font-size overrides still beat the theme size).
	MenuStyle.apply(_choices_scroll)
	# LOAD-BEARING with the skin applied: the skin's Button "normal" stylebox is TRANSPARENT — its legibility
	# contract assumes the solid skin panel every menu screen puts behind its buttons. This box has no panel
	# (the dialogue chrome is outlined text straight over the 3D world), so without a backing the choice text
	# is illegible against a bright/dithery scene. Back JUST the response menu with the skin's own panel
	# stylebox — the one surface here that reads as a menu gets the menu's panel, and hover/pressed accent
	# bars keep rendering on top of it exactly as they do in every other screen.
	_choices_scroll.add_theme_stylebox_override(&"panel", MenuStyle.theme.get_stylebox(&"panel", &"PanelContainer"))
	_choices_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choices_scroll.visible = false  # only shown for branch lines (see set_choices)
	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", GameSettings.dialogue.choice_button_spacing)
	_choices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices_scroll.add_child(_choices_box)
	vbox.add_child(_choices_scroll)
	_hint = Label.new()
	_hint.text = _continue_hint_text()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.modulate = Color(1.0, 1.0, 1.0, GameSettings.dialogue.dialogue_continue_hint_opacity)
	_hint.add_theme_font_size_override("font_size", GameSettings.dialogue.dialogue_continue_hint_font_size)
	vbox.add_child(_hint)
	# Speaker name, top-left like Fallout — separate from the bottom box, drawn last so it's on top.
	# Outlined so it reads against either the letterbox bar or the world. Filled/toggled in show_line.
	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", GameSettings.dialogue.speaker_name_font_size)
	_speaker_label.add_theme_constant_override("outline_size", GameSettings.dialogue.speaker_name_outline_width)
	_speaker_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_speaker_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_speaker_label.offset_left = GameSettings.dialogue.speaker_name_screen_x_offset
	_speaker_label.offset_top = GameSettings.dialogue.speaker_name_screen_y_offset
	_speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_speaker_label)

## Slide the cinematic letterbox bars in from the top and bottom edges (each to
## letterbox_bar_height_fraction of the screen height). close() collapses them instantly since the layer hides on end.
func _animate_letterbox_in() -> void:
	if _bar_top == null:
		return
	var slide_time: float = GameSettings.dialogue.letterbox_slide_in_duration
	var h: float = get_viewport().get_visible_rect().size.y * GameSettings.dialogue.letterbox_bar_height_fraction
	if _letterbox_tween and _letterbox_tween.is_valid():
		_letterbox_tween.kill()
	_letterbox_tween = create_tween().set_parallel(true)
	_letterbox_tween.tween_property(_bar_top, "offset_bottom", h, slide_time)
	_letterbox_tween.tween_property(_bar_bottom, "offset_top", -h, slide_time)
