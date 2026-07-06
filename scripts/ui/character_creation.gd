extends Control

## Character-creation overlay, shown when NEW GAME is clicked and BEFORE the world loads. The player NAMES their
## character, customizes their APPEARANCE (head / body / skin+limb colours, with a live 3D preview), and allocates
## the six-stat sheet as a ZERO-SUM TRADEOFF: every stat starts at 0, and the ONLY way to raise one is to pull
## points OUT of another (net stays <= 0 — you MAY underspend into a deliberately weak build, but never go
## net-positive). Each stat is clamped to [STAT_MIN, STAT_MAX] (-5..+10). Negatives are real, not dead choices:
## CharacterStats inverts every derived effect below baseline (less carry / HP / damage, more sway, slower, bigger
## rep losses), so a minus here is a genuine weakness.
##
## On "Begin" it emits confirmed(name, stat_values, appearance); StartMenu stamps those onto GameState
## (player_name + appearance + stat_values, after reset_for_new_game) then boots the game. On "Back" it emits
## cancelled. Built in code with the shared MenuStyle chrome. Instantiated by StartMenu (not an autoload) — it only
## ever appears from the menu, and StartMenu owns its lifetime. No class_name on purpose (keeps it off the global
## class cache; StartMenu preloads it).
##
## LAYOUT: name + the Back/Begin buttons are PINNED (always on screen at the game's tiny 396x216 viewport); the
## bulk sits in a TabContainer — a "Stats" tab (the zero-sum stat grid in a scroll) and a "Look" tab (the 3D
## character preview + the part/colour pickers) — so neither ever buries the pinned rows.

const CharacterPreviewScene := preload("res://scripts/ui/character_preview.gd")

signal confirmed(character_name: String, stat_values: Dictionary, appearance: Dictionary)
signal cancelled

const PANEL_MARGIN := 0.05  ## small margin -> the panel nearly fills the 396x216 viewport (every pixel counts here)
const NAME_MAX_LENGTH := 24
## Per-stat allocation bounds: a stat can be dumped to STAT_MIN (a real weakness) and raised to STAT_MAX. The
## zero-sum rule still applies on top — raising still costs a point freed by lowering another stat.
const STAT_MIN := -5
const STAT_MAX := 10
## The six stats, in display order. Mirrors GameState.STAT_NAMES / CharacterStats.stat_names() (a drift here would
## silently drop a stat from the builder); the value labels/steppers are keyed by these.
const STATS: Array[StringName] = [&"strength", &"persuasion", &"gunplay", &"endurance", &"streetwise", &"agility"]

var _name_edit: LineEdit
var _values: Dictionary = {}          ## StringName stat -> int (every stat starts at 0)
var _value_labels: Dictionary = {}    ## stat -> Label (the current number)
var _effect_labels: Dictionary = {}   ## stat -> Label (the live derived-effect blurb)
var _plus_buttons: Dictionary = {}    ## stat -> Button (disabled when no spare points OR the stat is at STAT_MAX)
var _minus_buttons: Dictionary = {}   ## stat -> Button (disabled when the stat is at STAT_MIN)
var _points_label: Label

# --- Appearance (the "Look" tab) ------------------------------------------------------------------------------
var _catalog: CharacterAppearanceCatalog
var _valid_heads: Array[CharacterPartOption] = []
var _valid_bodies: Array[CharacterPartOption] = []
var _head_idx: int = 0
var _body_idx: int = 0
var _appearance: Dictionary = {}      ## head/body ids (String) + skin/arm/leg (Color); handed to GameState on Begin
var _preview: CharacterPreview
var _head_label: Label
var _body_label: Label
var _head_prev: Button
var _head_next: Button
var _body_prev: Button
var _body_next: Button
var _swatches: Dictionary = {}        ## colour key ("skin"/"arm"/"leg") -> Array of {button, stylebox, color}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so the (hidden) menu buttons behind us don't get them
	for stat in STATS:
		_values[stat] = 0
	_init_appearance()
	MenuStyle.apply(self)  # shared menu Theme + button sounds
	_build_ui()
	_refresh()
	_refresh_look()

## Seed the appearance from the catalog defaults (the shipped look). The pickers edit this dict in place; Begin
## hands a copy to GameState. An empty catalog (no valid heads/bodies) leaves the cyclers inert but never crashes.
func _init_appearance() -> void:
	_catalog = CharacterAppearanceCatalog.get_catalog()
	_valid_heads = _catalog.valid_heads()
	_valid_bodies = _catalog.valid_bodies()
	_head_idx = 0
	_body_idx = 0
	_appearance = {
		"head": String(_catalog.default_head_id()),
		"body": String(_catalog.default_body_id()),
		"skin": _catalog.default_skin_color,
		"arm": _catalog.default_arm_color,
		"leg": _catalog.default_leg_color,
	}

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
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	vbox.add_child(MenuStyle.make_title("Create Character"))

	# --- Name (PINNED above the tabs) ---
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	vbox.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "Name"
	name_label.custom_minimum_size = Vector2(64, 0)
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Enter a name…"
	_name_edit.max_length = NAME_MAX_LENGTH
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)

	vbox.add_child(MenuStyle.make_separator())

	# --- Tabs: Stats | Look (EXPAND to fill the slack between name and the pinned buttons) ---
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(tabs)
	tabs.add_child(_build_stats_tab())
	tabs.add_child(_build_look_tab())

	vbox.add_child(MenuStyle.make_separator())

	# --- Back / Begin (PINNED below the tabs — always visible) ---
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	vbox.add_child(btn_row)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_back)
	btn_row.add_child(back)
	# Begin is always valid: the net can never exceed 0 (the + steppers gate on spare points), so a build always
	# begins in a legal state — an all-zero neutral character included.
	var begin_btn := Button.new()
	begin_btn.text = "Begin"
	begin_btn.pressed.connect(_on_begin)
	btn_row.add_child(begin_btn)

## The "Stats" tab: the spare-points banner + the one-line rule, then the zero-sum stat grid in a SCROLL region
## (so a tall list never buries the pinned buttons). Its node name becomes the tab title.
func _build_stats_tab() -> Control:
	var col := VBoxContainer.new()
	col.name = "Stats"
	col.add_theme_constant_override("separation", 6)

	_points_label = Label.new()
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.add_theme_color_override(&"font_color", MenuStyle.gold())
	col.add_child(_points_label)
	col.add_child(MenuStyle.make_hint(
		"Lower a stat to earn points, then spend them raising another (range %d to +%d). A minus is a real weakness." % [STAT_MIN, STAT_MAX]))

	# Columns: name | − | value | + | effect
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # only vertical; rows are width-fitted
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL                 # take all slack in the tab
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	for stat in STATS:
		_add_stat_row(grid, stat)
	return col

## The "Look" tab: the live 3D character preview on the left, the part cyclers + colour swatches on the right.
func _build_look_tab() -> Control:
	var row := HBoxContainer.new()
	row.name = "Look"
	row.add_theme_constant_override("separation", 8)

	_preview = CharacterPreviewScene.new()
	_preview.custom_minimum_size = Vector2(140, 0)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_preview)

	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 6)
	row.add_child(controls)

	# Body cycler (may switch to a whole-body model, which disables the head cycler below). Its own arrows disable
	# when the catalog ships a single body (the shipped default) — nothing to cycle to.
	var body_row := _make_cycler("Body", _step_body)
	_body_label = body_row.get_meta("value_label")
	_body_prev = body_row.get_meta("prev_button")
	_body_next = body_row.get_meta("next_button")
	controls.add_child(body_row)

	# Head cycler.
	var head_row := _make_cycler("Head", _step_head)
	_head_label = head_row.get_meta("value_label")
	_head_prev = head_row.get_meta("prev_button")
	_head_next = head_row.get_meta("next_button")
	controls.add_child(head_row)

	controls.add_child(MenuStyle.make_separator())

	controls.add_child(_make_swatch_row("Skin", _catalog.skin_palette, "skin"))
	controls.add_child(_make_swatch_row("Arms", _catalog.limb_palette, "arm"))
	controls.add_child(_make_swatch_row("Legs", _catalog.limb_palette, "leg"))
	return row

## A ‹ Label › cycler: a title, a prev button, the current value label, a next button. `handler` is called with
## the step direction (-1 / +1). Returns the row with the built sub-widgets stashed in metadata for the caller.
func _make_cycler(title: String, handler: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var title_l := Label.new()
	title_l.text = title
	title_l.custom_minimum_size = Vector2(44, 0)
	row.add_child(title_l)
	var prev := Button.new()
	prev.text = "<"  # plain ASCII arrows — guaranteed in the pixel font (guillemets can render as tofu)
	prev.focus_mode = Control.FOCUS_NONE
	prev.pressed.connect(handler.bind(-1))
	row.add_child(prev)
	var value_l := Label.new()
	value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_l.clip_text = true
	value_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_l.add_theme_color_override(&"font_color", MenuStyle.accent())
	row.add_child(value_l)
	var next := Button.new()
	next.text = ">"
	next.focus_mode = Control.FOCUS_NONE
	next.pressed.connect(handler.bind(1))
	row.add_child(next)
	row.set_meta("value_label", value_l)
	row.set_meta("prev_button", prev)
	row.set_meta("next_button", next)
	return row

## A titled row of clickable colour swatches from `palette`, writing the chosen Colour to _appearance[key]. Each
## swatch is a small Button restyled with a flat colour box; the selected one gets a bright border (set in
## _refresh_look). An empty palette yields just the title (a designer can add swatches in the catalog).
func _make_swatch_row(title: String, palette: PackedColorArray, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var title_l := Label.new()
	title_l.text = title
	title_l.custom_minimum_size = Vector2(44, 0)
	row.add_child(title_l)
	var entries: Array = []
	for color in palette:
		var b := Button.new()
		b.custom_minimum_size = Vector2(16, 16)
		b.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_border_width_all(0)
		sb.border_color = Color.WHITE
		for state in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(_on_swatch.bind(key, color))
		row.add_child(b)
		entries.append({"button": b, "stylebox": sb, "color": color})
	_swatches[key] = entries
	return row

func _on_swatch(key: String, color: Color) -> void:
	_appearance[key] = color
	_refresh_look()

## Step the HEAD selection by `dir` (wrapping). No-op with no valid heads or when the current body is whole-body
## (which brings its own head). Writes the new id into _appearance and refreshes the preview.
func _step_head(dir: int) -> void:
	if _valid_heads.is_empty() or _current_body_whole():
		return
	_head_idx = wrapi(_head_idx + dir, 0, _valid_heads.size())
	_appearance["head"] = String(_valid_heads[_head_idx].id)
	_refresh_look()

## Step the BODY selection by `dir` (wrapping). Writes the new id, then refreshes (which re-gates the head cycler).
func _step_body(dir: int) -> void:
	if _valid_bodies.is_empty():
		return
	_body_idx = wrapi(_body_idx + dir, 0, _valid_bodies.size())
	_appearance["body"] = String(_valid_bodies[_body_idx].id)
	_refresh_look()

## True when the selected body is a whole-character model (its own head/arms/legs) — the head picker is then moot.
func _current_body_whole() -> bool:
	return _body_idx >= 0 and _body_idx < _valid_bodies.size() and _valid_bodies[_body_idx].whole_body

## Re-stamp the cycler labels, gate the head cycler against a whole-body pick, mark the selected colour swatches,
## and push the whole appearance to the live preview.
func _refresh_look() -> void:
	if _body_label != null:
		_body_label.text = _valid_bodies[_body_idx].display_name if not _valid_bodies.is_empty() else "—"
	var body_locked := _valid_bodies.size() <= 1
	if _body_prev != null:
		_body_prev.disabled = body_locked
	if _body_next != null:
		_body_next.disabled = body_locked
	var whole := _current_body_whole()
	if _head_label != null:
		_head_label.text = ("(from body)" if whole else (_valid_heads[_head_idx].display_name if not _valid_heads.is_empty() else "—"))
		_head_label.modulate = Color(1, 1, 1, 0.4) if whole else Color.WHITE
	var head_locked := whole or _valid_heads.size() <= 1
	if _head_prev != null:
		_head_prev.disabled = head_locked
	if _head_next != null:
		_head_next.disabled = head_locked
	_mark_selected_swatches()
	if _preview != null:
		_preview.set_appearance(_appearance)

## Bright-border the swatch in each row whose colour matches the current pick (so the selection is legible).
func _mark_selected_swatches() -> void:
	for key in _swatches:
		var chosen: Color = _appearance.get(key, Color.WHITE)
		for e in _swatches[key]:
			var sb: StyleBoxFlat = e["stylebox"]
			sb.set_border_width_all(2 if (e["color"] as Color).is_equal_approx(chosen) else 0)

func _add_stat_row(grid: GridContainer, stat: StringName) -> void:
	var name_l := Label.new()
	name_l.text = StatInfo.TITLES.get(stat, str(stat))
	name_l.custom_minimum_size = Vector2(64, 0)
	MenuStyle.attach_tip(name_l, StatInfo.BLURB.get(stat, ""))  # hover the name for what the stat governs
	grid.add_child(name_l)

	var minus := Button.new()
	minus.text = "−"
	minus.focus_mode = Control.FOCUS_NONE  # mouse-driven; don't steal focus from the name field
	minus.pressed.connect(_on_minus.bind(stat))
	_minus_buttons[stat] = minus
	grid.add_child(minus)

	var val_l := Label.new()
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_l.custom_minimum_size = Vector2(28, 0)
	_value_labels[stat] = val_l
	grid.add_child(val_l)

	var plus := Button.new()
	plus.text = "+"
	plus.focus_mode = Control.FOCUS_NONE
	plus.pressed.connect(_on_plus.bind(stat))
	_plus_buttons[stat] = plus
	grid.add_child(plus)

	# Effect goes LAST (rightmost) and clips rather than forcing width — so a long blurb can never push the +/−
	# steppers off-screen. clip_text drops its min width to 0; the name tooltip carries the full breakdown anyway.
	var effect_l := Label.new()
	effect_l.clip_text = true
	effect_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_l.add_theme_color_override(&"font_color", MenuStyle.dim_color())
	_effect_labels[stat] = effect_l
	grid.add_child(effect_l)

## Spare points: how many you've freed (by lowering stats) but not yet spent (by raising others). Equals -net,
## and is >= 0 by construction because the + steppers refuse to push net above 0.
func _spare() -> int:
	var net := 0
	for stat in STATS:
		net += int(_values[stat])
	return -net

## Lower a stat by 1 — frees a point to spend elsewhere. Clamped at STAT_MIN. A minus is a real penalty.
func _on_minus(stat: StringName) -> void:
	if int(_values[stat]) <= STAT_MIN:
		return
	_values[stat] = int(_values[stat]) - 1
	_refresh()

## Raise a stat by 1 — only with a spare point (net stays <= 0) AND below STAT_MAX. Otherwise a no-op: free a point
## by lowering another stat first ("subtract from 0 to add elsewhere").
func _on_plus(stat: StringName) -> void:
	if _spare() <= 0 or int(_values[stat]) >= STAT_MAX:
		return
	_values[stat] = int(_values[stat]) + 1
	_refresh()

## Re-stamp every value/effect label + the spare-points banner, and gate the steppers: + off with no spare point OR
## at STAT_MAX; − off at STAT_MIN.
func _refresh() -> void:
	var spare := _spare()
	for stat in STATS:
		var v: int = int(_values[stat])
		(_value_labels[stat] as Label).text = str(v)
		(_effect_labels[stat] as Label).text = _effect_for(stat, v)
		(_plus_buttons[stat] as Button).disabled = spare <= 0 or v >= STAT_MAX
		(_minus_buttons[stat] as Button).disabled = v <= STAT_MIN
	_points_label.text = "Points to spend: %d" % spare

## This one stat's live effect string — a throwaway sheet with only this stat set, run through the SAME StatInfo
## formatter the in-game Stats screen uses (so the wording never drifts). Neutral at baseline.
func _effect_for(stat: StringName, value: int) -> String:
	if value == 0:
		return "neutral"
	var s := CharacterStats.new()
	s.set(stat, value)
	return StatInfo._effect(stat, s)

## Back: discard this build and return to the menu (StartMenu frees us + reshows its buttons). No profile change.
func _on_back() -> void:
	cancelled.emit()

## Confirm: hand the chosen name (trimmed) + a fresh {stat -> int} dict + the appearance dict to StartMenu, which
## writes them onto GameState and boots the game.
func _on_begin() -> void:
	var out: Dictionary = {}
	for stat in STATS:
		out[stat] = int(_values[stat])
	confirmed.emit(_name_edit.text.strip_edges(), out, _appearance.duplicate())
