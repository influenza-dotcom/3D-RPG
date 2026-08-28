class_name DialogueView
extends Node

## The dialogue's VISUALS, built in code, pulled out of DialogueManager. Since the 08-24 box-less pass the
## look is cinematic subtitles: the letterbox bars slide in as before, a bottom SUBTITLE block (name over
## the outlined line, hint right) sits above the lower bar left-aligned at its gutter, and the response
## column (digit-keyed rows on translucent beds, a pinned Goodbye below the scroll) hangs at the same
## left gutter — the CENTRE of frame stays clear, because the dialogue camera holds the SPEAKER dead
## centre and they are the shot. No box slab; the art survives behind MenuSkin.dialogue_panel_enabled,
## and both placements can flip centred via knobs (dialogue_text_centered / choice_column_centered). A code-built child of the manager (PROCESS_MODE_ALWAYS owner, so the
## box / choices keep rendering + advancing while the world is paused). Owns the CanvasLayer and every
## Control under it; the manager drives it through open() / close() / show_line() / set_choices() /
## add_extra_choice() / add_exit_choice() / reveal_recap() / show_menu_hint() / press_numbered_choice() /
## clear_choices(). Choice buttons fire back a Callable the manager supplies, so the jump / re-render
## logic stays in the coordinator.

# The letterbox bar height + slide-in duration are designer knobs on GameSettings.dialogue
# (letterbox_bar_height_fraction / letterbox_slide_in_duration).

## Faction registry (preloaded by path) for the reputation gate (WR-1).
const Factions = preload("res://scripts/faction/factions.gd")

var _layer: CanvasLayer
var _panel: PanelContainer        # the bottom SUBTITLE block: name, spoken line, then the right-aligned hint row
var _speaker_label: Label         # rides inside the subtitle block since the 08-24 box-less pass (Fallout-corner placement retired; its offsets exports are kept but unused)
var _text_label: Label
var _hint: Label                  # "[F]" while listening / the digit-keys hint while the menu is up; its own right-aligned row under the line
var _column: VBoxContainer        # the response column (left gutter by default): [scrollable rows · hairline · pinned exit]; seated above the subtitle block by _position_column
var _choices_box: VBoxContainer   # holds one Button per choice; emptied each line
var _choices_scroll: ScrollContainer  # wraps the choices box + caps its height so many options SCROLL instead of overflowing off the top of the screen
var _exit_rule: ColorRect         # 1px hairline separating the scrollable rows from the pinned exit
var _exit_box: VBoxContainer      # the PINNED exit row (Goodbye) — outside the scroll so it can never hide below the fold
var _exit_button: Button          # the live exit row, for press_exit_choice (digit 0 / ui_cancel)
var _numbered_buttons: Array[Button] = []  # authored-choice rows in digit order, for press_numbered_choice
var _scrim: TextureRect           # bottom transparent-to-dark gradient — the box-less look's legibility bed
var _veil: TextureRect            # optional edge vignette on top of the bars (dialogue_world_veil_alpha, 0 = off, the default)
var _bar_top: ColorRect           # cinematic letterbox bars; slid in from offscreen on start, collapsed on finish
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
	_apply_type_sizes()  # re-read font sizes each open so the Settings.dialogue_text_scale slider bites without a restart
	_layer.visible = true
	_panel.visible = false   # keep the text box hidden during the intro beat
	_column.visible = false  # ...and the response column — _panel.visible was the ONLY stale-menu hide before the split, so the column needs its own
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
	# Reset the scrim/veil fade so they re-slide in with the bars next conversation (same rule as the bars).
	if _scrim:
		_scrim.modulate.a = 0.0
		_veil.modulate.a = 0.0

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
	# A fresh line shows in FULL: release the recap clamp reveal_recap() may have applied for the
	# previous line's response menu (the clamp is a Label property, the text is never rewritten).
	_text_label.max_lines_visible = -1
	_text_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_text_label.text = text

## Populate the line's authored choices: one numbered, selectable row per choice in the response column.
## Rows are real Buttons (FOCUS_NONE — selection is mouse-click or digit-key driven, never focus traversal)
## wearing the skin's translucent rest-state beds, with the digit painted in a gutter Label INSIDE the
## button (never concatenated into .text — tests pin the label verbatim, and the digit is INPUT, not prose:
## it shows the LIVE hotbar-slot binding, which doubles as the selection key while the Player is paused).
## An empty `choices` leaves the hint up for a linear line.
func set_choices(choices: Array, cb: Callable) -> void:
	if choices.is_empty():
		_column.visible = false
		_hint.visible = true
		return
	_choices_scroll.visible = true
	_column.visible = true
	for choice in choices:
		if _hide_for_stat_requirement(choice):
			continue
		var label_text: String = choice.text
		# Passing stat gates are shown on the label; failed stat gates were skipped before the button was built.
		# Other gates stay visible and use `passed` for the fail-branch path.
		# `passed` rides to the handler so non-stat gate failures skip consequences and route to target_on_fail.
		var passed := true
		var has_stat_gate: bool = choice.required_stat != &""
		if has_stat_gate:
			label_text = stat_gate_label(choice.required_stat, choice.required_value, choice.text)
		if choice.required_flag != &"":
			passed = passed and str(GameState.get_flag(choice.required_flag)) == choice.required_flag_value
		# WR-1/WR-3 reputation / perk / item / quest gates — folded into the SAME `passed` accumulation.
		passed = passed and _state_gates_pass(choice)
		# Row ink: a passing SKILL CHECK reads in the gate-pass gold; a FAILED non-stat gate (still
		# selectable, FNV-style — it routes to target_on_fail) reads terracotta ONLY behind the
		# show_failed_gate_tags designer toggle, because hiding the failure is the current deliberate design.
		var tint := Color(0, 0, 0, 0)  # zero-alpha = "no tint" sentinel; the builder falls back to skin ink
		if has_stat_gate:
			tint = MenuStyle.skin.dialogue_choice_gate_pass_color
		elif not passed and GameSettings.dialogue.show_failed_gate_tags:
			tint = MenuStyle.skin.dialogue_choice_gate_fail_color
		var slot_idx := _numbered_buttons.size()  # digit gutter = the matching hotbar-slot binding, rows 1..9
		var gutter := ""
		if slot_idx < 9:
			gutter = PlayerText.dialogue_choice_number(InputManager.get_action_binding(InputManager.hotbar_actions[slot_idx]))
		var b := _make_choice_row(gutter, label_text, tint, false)
		# add_child BEFORE connecting — the SAME audio-ordering rule add_extra_choice documents at length. Entering
		# the tree is what lets MenuStyle's node_added hook wire the generic click, and that connection must come
		# FIRST: a choice whose handler fires a cue (a consequence that opens Trade / Level Up, or hands out money)
		# has its click swallowed only while the click is ALREADY RINGING, so a click connected second lands on the
		# front of the cue instead of being cut. These two builders were split on this — extra choices were fixed,
		# authored ones were not.
		_choices_box.add_child(b)
		b.pressed.connect(cb.bind(choice, passed))
		_numbered_buttons.append(b)
	_clamp_choices_height.call_deferred()  # cap the column so many choices SCROLL rather than climb the screen

## Collapse the spoken line to its recap clamp (dialogue_recap_max_lines wrapped rows, ellipsized) once the
## response menu is up — you've already HEARD it; that is what the listen-first flow is for. A Label
## PROPERTY, never a text rewrite: _resume_from_menu re-reveals the menu WITHOUT re-running show_line, so
## a destructive truncation would double-apply there. show_line releases the clamp for the next full line.
func reveal_recap() -> void:
	var max_lines: int = GameSettings.dialogue.dialogue_recap_max_lines
	if _text_label == null or max_lines <= 0:
		return
	_text_label.max_lines_visible = max_lines
	_text_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

## Build one response row: a flat left-aligned Button on the skin's translucent bed, its label wrapped
## inside the column, with `gutter` (a digit binding / the services caret) painted in a child Label inside
## the bed's reserved left inset. `tint` with alpha 0 falls back to the skin's row ink; `dim` drops the
## ink to ~78% for the station-service rows so they read subordinate to the spoken responses.
func _make_choice_row(gutter: String, text: String, tint: Color, dim: bool) -> Button:
	var d: DialogueSettings = GameSettings.dialogue
	var font_size := _scaled(d.choice_button_font_size)
	var gutter_px := int(ceil(font_size * 1.3)) if not gutter.is_empty() else 0
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # a long reply wraps to a second row instead of clipping at the column edge
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# FOCUS_NONE so ui_accept (Enter/Space) can't re-press a focused button; selection is mouse-click or
	# digit-key driven (the mouse is MOUSE_MODE_VISIBLE once the response menu is revealed —
	# _reveal_menu -> _sync_dialogue_cursor; start() itself leaves it HIDDEN for the listen-first line).
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	# The translucent beds (rest + raised hover/pressed) — the box-less look's legibility floor, since the
	# dialogue camera centres the LIT speaker into this region. Same shape both states (only ink + rule move).
	var normal := MenuStyle.make_dialogue_choice_normal(gutter_px)
	var hover := MenuStyle.make_dialogue_choice_hover(gutter_px)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Row ink: LIGHT (the skin's dialogue row ink, not the dark panel button ink) with the same em-ratio
	# outline the spoken line wears, so the text also survives a bright frame where the bed is translucent.
	var ink: Color = tint if tint.a > 0.0 else MenuStyle.skin.dialogue_choice_font_color
	if dim:
		ink.a *= 0.78
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, ink)
	b.add_theme_constant_override("outline_size", _outline_px(font_size))
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	if not gutter.is_empty():
		var n := Label.new()
		n.text = gutter
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.add_theme_font_size_override("font_size", font_size)
		var n_ink := ink
		n_ink.a *= 0.7  # the digit is an affordance, not prose — keep it quieter than the reply
		n.add_theme_color_override("font_color", n_ink)
		n.add_theme_constant_override("outline_size", _outline_px(font_size))
		n.add_theme_color_override("font_outline_color", Color.BLACK)
		n.set_anchors_preset(Control.PRESET_TOP_LEFT)
		n.offset_left = normal.get_margin(SIDE_LEFT) - gutter_px
		n.offset_top = normal.get_margin(SIDE_TOP)
		b.add_child(n)
	return b

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
	# The services caret: a shape glyph, not prose (composed here at the root per the PlayerText non-prose
	# rule). Services are deliberately NOT numbered — they'd renumber themselves between visits (the Exchange
	# row appears only while a companion follows), which is exactly how digit muscle memory gets betrayed.
	var b := _make_choice_row("▸", text, Color(0, 0, 0, 0), true)
	# add_child BEFORE connecting, and the order matters for AUDIO: entering the tree is what lets MenuStyle's
	# node_added hook wire the generic click, and that connection must come FIRST. These buttons open menus
	# (Trade / Heal / Rest / Level Up / Install / Chess), whose open sting cuts a generic click from the same
	# press — but only one already ringing, so a click connected after the handler would land on the sting's
	# front instead of being swallowed. Goodbye/companion choices carry no cue and just click normally.
	_choices_box.add_child(b)
	b.pressed.connect(cb)
	_choices_scroll.visible = true  # ensure the box shows even on an otherwise-linear line
	_column.visible = true
	_clamp_choices_height.call_deferred()

## The PINNED exit row (Goodbye) — below the scroll with a hairline above it, so the way out sits at a
## fixed screen position no matter how many options scroll above it. Its gutter shows the LIVE slot-10
## binding ("0" by default), the digit that fires it; ui_cancel routes here too (manager-side).
func add_exit_choice(text: String, cb: Callable) -> void:
	var gutter := PlayerText.dialogue_choice_number(InputManager.get_action_binding(InputManager.hotbar_actions[9]))
	var b := _make_choice_row(gutter, text, Color(0, 0, 0, 0), false)
	_exit_box.add_child(b)  # add_child before connect — the audio-ordering rule above
	b.pressed.connect(cb)
	_exit_button = b
	_exit_rule.visible = true
	_column.visible = true
	_clamp_choices_height.call_deferred()

## Fire the numbered row for digit `n` (1-based, the hotbar-slot key order) as if clicked — the keyboard
## path DialogueManager drives off the Weapon Slot actions while the response menu is up. False when there
## is no such row (fewer options than the digit), so the manager can leave the input unhandled.
func press_numbered_choice(n: int) -> bool:
	var i := n - 1
	if i < 0 or i >= _numbered_buttons.size():
		return false
	var b := _numbered_buttons[i]
	if b == null or not is_instance_valid(b):
		return false
	b.pressed.emit()  # through the signal, so the MenuStyle click cue fires exactly as a mouse press would
	return true

## How many digit-selectable (authored) rows the current menu carries — feeds the header hint's "1–N".
func numbered_choice_count() -> int:
	return _numbered_buttons.size()

## Fire the pinned exit row (digit 0 / ui_cancel), if one is up.
func press_exit_choice() -> bool:
	if _exit_button == null or not is_instance_valid(_exit_button):
		return false
	_exit_button.pressed.emit()
	return true

## Swap the header hint to the response-menu affordance ("1–4 · 0 backs out", supplied by the manager from
## the LIVE bindings) while the menu is up — the listen-state "[F]" comes back via show_continue_hint.
func show_menu_hint(text: String) -> void:
	_hint.text = text
	_hint.visible = true

## Listen-first state: show the line's text with only a continue affordance (no response menu yet). The
## menu, if any, is revealed by the manager on the next click — New Vegas-style: hear it, THEN choose.
func show_continue_hint() -> void:
	clear_choices()
	_column.visible = false
	_hint.text = _continue_hint_text()  # refresh in case the player rebound the advance key since the box was built
	_hint.visible = true

## The continue affordance, using the LIVE advance binding (dialogue advances on action_pickup / click) rather than
## a hardcoded "[F]" — so a rebind / a controller shows the right prompt, matching the hover-hint convention.
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
	# The pinned exit row lives OUTSIDE the scroll (its own box) but is part of the same menu — same
	# detach-now rule so a resume's re-measure never counts an outgoing Goodbye twice.
	if _exit_box != null:
		for c in _exit_box.get_children():
			_exit_box.remove_child(c)
			c.queue_free()
		_exit_rule.visible = false
	_exit_button = null
	_numbered_buttons.clear()

## Cap the scrollable response rows so a many-option line SCROLLS within the column instead of climbing
## the screen; a short list still sizes to its content. Two budgets, the tighter wins: the designer's
## screen-height fraction, and the actual space between the subtitle block's top and a fixed head-room
## inset — measured, because the subtitle's height moves with the line's wrap count and the recap clamp.
## The pinned exit row + hairline sit OUTSIDE the scroll, so their height comes off the budget first.
func _clamp_choices_height() -> void:
	if _choices_scroll == null:
		return
	var d: DialogueSettings = GameSettings.dialogue
	var viewport_h := get_viewport().get_visible_rect().size.y
	var chrome_h := 0.0  # the column's non-scrolling parts: hairline + pinned exit + their separations
	if _exit_box != null and _exit_box.get_child_count() > 0:
		chrome_h = _exit_box.get_combined_minimum_size().y + _exit_rule.custom_minimum_size.y + 2.0 * _column.get_theme_constant(&"separation")
	# Head-room: the column may climb to the same inset off the top the subtitle keeps off the bottom.
	var above_subtitle := viewport_h - float(d.panel_vertical_margin) - _panel.size.y - float(d.choice_column_gap) - float(d.panel_vertical_margin)
	var max_h := minf(viewport_h * d.choices_scroll_max_height_fraction, above_subtitle) - chrome_h
	var content_h := _choices_box.get_combined_minimum_size().y
	# The scroll's own stylebox margins sit OUTSIDE the choices box's minimum size, so add them or the last
	# option hides behind a scrollbar in a list that used to fit exactly. get_margin(), NOT the
	# content_margin_* properties: those hold the raw authored value, which is -1 ("unset") on a
	# StyleBoxEmpty — reading it directly would quietly SUBTRACT 2px from the measure. get_margin resolves
	# the -1 to the box's real default (0 for empty, the texture margin for a 9-patch).
	var panel_sb := _choices_scroll.get_theme_stylebox(&"panel")
	if panel_sb != null:
		content_h += panel_sb.get_margin(SIDE_TOP) + panel_sb.get_margin(SIDE_BOTTOM)
	_choices_scroll.custom_minimum_size.y = minf(content_h, maxf(max_h, 0.0))
	_position_column()

## Seat the response column directly ABOVE the subtitle block (same left gutter, choice_column_gap apart).
## Re-run whenever either block's height can have changed — the subtitle's resized signal, and every
## _clamp_choices_height — because the column is bottom-anchored and grows UPWARD from this seat exactly
## the way the subtitle block grows from its own (offset_top == offset_bottom + GROW_DIRECTION_BEGIN).
func _position_column() -> void:
	if _column == null or _panel == null:
		return
	var d: DialogueSettings = GameSettings.dialogue
	var seat := -(float(d.panel_vertical_margin) + _panel.size.y + float(d.choice_column_gap))
	_column.offset_bottom = seat
	_column.offset_top = seat

func _build_ui() -> void:
	var d: DialogueSettings = GameSettings.dialogue
	_layer = CanvasLayer.new()
	_layer.layer = 90  # above the HUD
	add_child(_layer)
	# Cinematic letterbox bars, added first so they draw BEHIND everything. Collapsed to zero height;
	# _animate_letterbox_in() slides them in from offscreen on start, to letterbox_bar_height_fraction
	# of the screen. The scrim below is a separate legibility bed for the text above the lower bar.
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
	# The SCRIM: a bottom transparent-to-dark gradient — the box-less look's legibility bed under the
	# subtitle block and the response column, doing the letterbox's darkening job without cropping the
	# frame. MOUSE_FILTER_IGNORE is LOAD-BEARING (the bars' rule): click-to-advance lives in
	# DialogueManager._unhandled_input, and any Control left at the default STOP is an invisible
	# click-eater over the whole bottom half of the screen. EXPAND_IGNORE_SIZE so the small generated
	# gradient texture never dictates a minimum size. Faded in with the bars (_animate_letterbox_in).
	_scrim = TextureRect.new()
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_scrim.modulate.a = 0.0
	_layer.add_child(_scrim)
	# The VEIL: an optional soft radial vignette over the frame while a conversation is up — an EXTRA
	# mode cue on top of the letterbox bars, off by default (dialogue_world_veil_alpha 0). Rides the same
	# fade window the bars and the camera zoom share (letterbox_slide_in_duration via letterbox_time()).
	_veil = TextureRect.new()
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.modulate.a = 0.0
	_layer.add_child(_veil)
	# The SUBTITLE block: bottom-pinned but SIZE TO CONTENT, growing UPWARD (offset_top == offset_bottom
	# collapses the anchor rect to the bottom edge; grow_vertical = BEGIN then expands it up by the
	# content's height). Holds the name+hint header row and the spoken line; the response menu moved to
	# its own left-hand column (below) in the 08-24 box-less pass.
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Background: the skin's OWN dialogue-box art when the artist filled the slot AND the skin's
	# dialogue_panel_enabled gate is on — deliberately NOT the theme panel, which is the full screen-card
	# art and would drown a box this short and wide. The SHIPPED look gates the art OFF (the slot keeps
	# the authored art): the PanelContainer wears a StyleBoxEmpty and the text reads over the world on
	# its own outline + the scrim. Both are supported looks, so this is a live branch, not a migration.
	var box_bg: StyleBox = MenuStyle.make_dialogue_panel_style()
	_panel.add_theme_stylebox_override("panel", box_bg if box_bg != null else StyleBoxEmpty.new())
	# Mouse-TRANSPARENT chrome (the bars' rule, applied to the box): click-to-advance lives in
	# DialogueManager._unhandled_input, and ANY Control at the Control default MOUSE_FILTER_STOP eats the
	# click first. Only the response column's ScrollContainer keeps STOP, since its buttons ARE the click
	# targets (and the manager refuses to advance at all while a response menu is up, so nothing double-fires).
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_panel)
	# Re-seat the response column whenever the subtitle's height changes (line wrap count, the recap
	# clamp) — the column sits a fixed gap above the subtitle's top edge (_position_column).
	_panel.resized.connect(_position_column)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, d.panel_inner_padding)
	_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", d.panel_vertical_element_spacing)
	margin.add_child(vbox)
	# Subtitle stack, cinematic-subtitle order: speaker name over the line, the continue/menu hint on its
	# own right-aligned row below — the name rides INSIDE the block rather than the old free-floating
	# Fallout corner (those offsets exports survive unused for anyone who wants that back). Name + line
	# alignment follows dialogue_text_centered (_apply_type_sizes), the hint stays right either way.
	_speaker_label = Label.new()
	_speaker_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_speaker_label)
	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Outlined so the line reads with NO box background (the shipped look — the outline + scrim are
	# load-bearing then, and merely a seat for the text if the box art is gated back on). The FILL ink
	# comes from DialogueSettings, never the theme: theme text_color is menu-PANEL ink (dark since the
	# plum palette), while this label must stay light for BOTH backdrops. Sizes + outline are re-applied
	# per open by _apply_type_sizes (the dialogue_text_scale accessibility slider).
	_text_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_text_label.add_theme_color_override("font_color", d.dialogue_text_color)
	vbox.add_child(_text_label)
	_hint = Label.new()
	_hint.text = _continue_hint_text()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# The hint's de-emphasis rides the FONT colour, never modulate — modulate dims the outline with the
	# ink, and this is the smallest text on the screen; 72% ink over a 100% bed reads, 72% of both doesn't.
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_hint)
	# The RESPONSE COLUMN: a vertical stack (left gutter by default; choice_column_centered flips it) seated
	# a fixed gap above the subtitle block —
	# [scrollable rows · hairline · pinned exit]. The exit (Goodbye) lives OUTSIDE the scroll so the way
	# out can never hide below the fold of a long list. The wrapper is IGNORE (per-control, not inherited,
	# so the buttons inside still click); the scroll keeps STOP since its rows ARE the click targets.
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override("separation", d.panel_vertical_element_spacing)
	_column.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_column.grow_horizontal = Control.GROW_DIRECTION_END
	_column.visible = false  # only shown while a response menu is up (see set_choices / add_extra_choice)
	# The whole column joins the menu skin: apply() themes the subtree and stamps `_menu_root`, which the
	# global node_added hook walks to wire skin hover/click sounds onto every row — INCLUDING the pinned
	# exit, which is why the stamp sits here and not on the scroll. Deliberately NOT applied to _panel /
	# _layer: the line text, hint and speaker name keep their outlined over-the-world look (the per-row
	# font/stylebox overrides in _make_choice_row beat the theme either way).
	MenuStyle.apply(_column)
	_layer.add_child(_column)
	_choices_scroll = ScrollContainer.new()
	# Rows carry their OWN translucent beds now (MenuStyle.make_dialogue_choice_normal/hover), so the
	# scroll itself always wears a StyleBoxEmpty — the old solid make_plain_panel_style backing painted a
	# near-opaque slab over the world, the exact thing the box-less pass removes.
	_choices_scroll.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	_choices_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", d.choice_button_spacing)
	_choices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices_scroll.add_child(_choices_box)
	_column.add_child(_choices_scroll)
	_exit_rule = ColorRect.new()
	_exit_rule.color = Color(MenuStyle.gold(), 0.22)
	_exit_rule.custom_minimum_size = Vector2(0, 1)
	_exit_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exit_rule.visible = false
	_column.add_child(_exit_rule)
	_exit_box = VBoxContainer.new()
	_exit_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exit_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_child(_exit_box)
	_apply_type_sizes()

## Re-read every live-tunable piece of the look: font sizes (x the Settings.dialogue_text_scale
## accessibility slider), the em-ratio outlines, the block/column geometry, and the scrim/veil gradients.
## Run per open() rather than once at build, so the Options slider and the DialogueSettings inspector
## knobs bite the NEXT conversation without a restart — the "consumers read live" rule
## (Settings.set_* writes storage and nothing else).
func _apply_type_sizes() -> void:
	var d: DialogueSettings = GameSettings.dialogue
	var text_px := _scaled(d.dialogue_text_font_size)
	_text_label.add_theme_font_size_override("font_size", text_px)
	_text_label.add_theme_constant_override("outline_size", _outline_px(text_px))
	var name_px := _scaled(d.speaker_name_font_size)
	_speaker_label.add_theme_font_size_override("font_size", name_px)
	_speaker_label.add_theme_constant_override("outline_size", d.speaker_name_outline_width)
	var hint_px := _scaled(d.dialogue_continue_hint_font_size)
	_hint.add_theme_font_size_override("font_size", hint_px)
	_hint.add_theme_constant_override("outline_size", _outline_px(hint_px))
	_hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, d.dialogue_continue_hint_opacity))
	_panel.offset_left = d.panel_horizontal_margin
	_panel.offset_right = -d.panel_horizontal_margin
	_panel.offset_top = -d.panel_vertical_margin
	_panel.offset_bottom = -d.panel_vertical_margin
	# Subtitle alignment: left at the block's gutter (the shipped look — the frame centre belongs to the
	# centred speaker) or centred cinematic-subtitle style.
	var h_align := HORIZONTAL_ALIGNMENT_CENTER if d.dialogue_text_centered else HORIZONTAL_ALIGNMENT_LEFT
	_speaker_label.horizontal_alignment = h_align
	_text_label.horizontal_alignment = h_align
	# Column seat: the left gutter (shipped), or centred on the screen axis.
	if d.choice_column_centered:
		_column.anchor_left = 0.5
		_column.anchor_right = 0.5
		_column.offset_left = -d.choice_column_width / 2.0
		_column.offset_right = d.choice_column_width / 2.0
	else:
		_column.anchor_left = 0.0
		_column.anchor_right = 0.0
		_column.offset_left = d.panel_horizontal_margin
		_column.offset_right = d.panel_horizontal_margin + d.choice_column_width
	_scrim.anchor_top = 1.0 - clampf(d.dialogue_scrim_height_fraction, 0.0, 1.0)
	_scrim.offset_top = 0.0
	_scrim.texture = _vertical_gradient(Color(0.02, 0.03, 0.04, 0.0), Color(0.02, 0.03, 0.04, d.dialogue_scrim_max_alpha))
	_veil.texture = _radial_vignette(Color(0.01, 0.01, 0.02, d.dialogue_world_veil_alpha))
	_position_column()

## Font px x the player's Accessibility text-size slider (Settings.dialogue_text_scale).
func _scaled(px: int) -> int:
	return maxi(1, int(round(px * Settings.dialogue_text_scale)))

## The em-ratio outline: px = round(font_size * dialogue_text_outline_em), so every dialogue text carries
## the same relative bed at any size — the house ~1/3 ratio the over-world HUD labels use.
func _outline_px(font_px: int) -> int:
	return maxi(0, int(round(font_px * GameSettings.dialogue.dialogue_text_outline_em)))

static func _vertical_gradient(top: Color, bottom: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([top, bottom])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	return tex

static func _radial_vignette(edge: Color) -> GradientTexture2D:
	var clear := Color(edge, 0.0)
	var g := Gradient.new()
	g.colors = PackedColorArray([clear, clear, edge])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 1.1)  # radius past the frame edge so the corners sit deepest in the falloff
	return tex

## Slide the cinematic letterbox bars in (each to letterbox_bar_height_fraction of the screen height —
## a no-op at the shipped 0.0) and fade the scrim + veil up over the same window, which is also the
## window the camera's dialogue zoom rides (letterbox_time()). close() resets all three instantly since
## the layer hides on end.
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
	_letterbox_tween.tween_property(_scrim, "modulate:a", 1.0, slide_time)
	_letterbox_tween.tween_property(_veil, "modulate:a", 1.0, slide_time)
