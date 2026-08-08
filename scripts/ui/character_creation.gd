extends Control

## Character-creation overlay, shown when NEW GAME is clicked and BEFORE the world loads. The player NAMES their
## character, customizes their APPEARANCE (head / body / arm+leg colours + a PAINTED shirt, with a live 3D preview), and allocates
## the stat sheet as a ZERO-SUM TRADEOFF: every stat starts at 0, and the ONLY way to raise one is to pull
## points OUT of another (net stays <= 0 — you MAY underspend into a deliberately weak build, but never go
## net-positive). Each stat is clamped to [STAT_MIN, STAT_MAX] (-5..+10). Negatives are real, not dead choices:
## CharacterStats inverts every derived effect below baseline (less carry / HP / damage, more sway, slower, bigger
## rep losses), so a minus here is a genuine weakness.
##
## A NAME is REQUIRED: "Begin" stays disabled (with a "name required" hint) until the name field is non-blank, so a
## run can never start unnamed. On "Begin" it emits confirmed(name, stat_values, appearance); StartMenu stamps those
## onto GameState (player_name + appearance + stat_values, after reset_for_new_game) then boots the game. On "Back" it emits
## cancelled. Instantiated by StartMenu (not an autoload) — it only ever appears from the menu, and StartMenu owns
## its lifetime. No class_name on purpose (keeps it off the global class cache; StartMenu preloads the SCENE).
##
## AUTHORED SCENE: the layout lives in scenes/ui/character_creation.tscn (StartMenu instances that scene — its
## root carries this script); _bind_ui binds the static chrome by %unique name and applies the skin-driven look
## (MenuStyle adopt-helpers) on top, so a designer rearranges the panel in the editor and the skin keeps owning
## colours/fonts/width pins. DYNAMIC content stays code-built into the authored containers: the stat stepper
## rows (%StatGrid), the part cyclers + colour swatches (%LookControls, from the disk catalog), the two live 3D
## previews, the ShirtCanvas paint surface + its tool/palette rows, and the lazy HSV-wheel overlay. NO text is
## authored in the scene — every string is set here from PlayerText (l10n + the text-debt ratchet own strings,
## never a .tscn); tab titles are painted via set_tab_title over KEY node names (the options_menu idiom).
## tests/test_character_creation_scene.gd pins the wiring; tests/test_character_creation.gd covers behaviour.
##
## LAYOUT: name + the Back/Begin buttons are PINNED (always on screen at the game's 792x444 UI canvas); the
## bulk sits in a TabContainer — a "Stats" tab (the zero-sum stat grid in a scroll), a "Look" tab (the 3D
## character preview + the part/colour pickers), and a "Shirt" tab (a paint canvas + a live preview) — so none
## ever buries the pinned rows. Only the VISIBLE tab's 3D preview renders (both start lazy; see _sync_previews).

const CharacterPreviewScene := preload("res://scripts/ui/character_preview.gd")
## The zero-sum stat allocator, extracted as a pure RefCounted (its rules are unit-tested off-tree). Preloaded by
## path (not a global class_name) to match this file's own "no class_name" stance and keep it off the class cache.
const StatBudget := preload("res://scripts/ui/stat_budget.gd")
## The "draw your own t-shirt" paint widget for the Shirt tab. Preloaded BY PATH and used as a type below (it has
## no class_name), the same idiom as StatBudget — keeps this UI helper off the global class cache.
const ShirtCanvas := preload("res://scripts/ui/shirt_canvas.gd")

signal confirmed(character_name: String, stat_values: Dictionary, appearance: Dictionary)
signal cancelled

const NAME_MAX_LENGTH := 24
## Selectable shirt brush footprints (square side in canvas cells) offered on the Shirt tab; first = the default.
const SHIRT_BRUSH_SIZES: Array[int] = [1, 2, 3, 4]
## Per-stat allocation bounds: a stat can be dumped to STAT_MIN (a real weakness) and raised to STAT_MAX. The
## zero-sum rule still applies on top — raising still costs a point freed by lowering another stat. DERIVED
## from the allocator (the STATS/STAT_NAMES idiom): the same pair normalizes the implant step's credit check,
## so a bound changed in one place can never leave the bank scoring against the old range.
const STAT_MIN := StatBudget.STAT_MIN
const STAT_MAX := StatBudget.STAT_MAX
## The stats, in display order. Derived from CharacterStats.STAT_NAMES (the single source; cannot drift — a drift
## here would silently drop a stat from the builder); the value labels/steppers are keyed by these.
const STATS: Array[StringName] = CharacterStats.STAT_NAMES

var _name_edit: LineEdit
var _budget: StatBudget                ## the zero-sum allocator (pure; see stat_budget.gd) — the widgets mirror it
var _value_labels: Dictionary = {}    ## stat -> Label (the current number)
var _effect_labels: Dictionary = {}   ## stat -> Label (the live derived-effect blurb)
var _plus_buttons: Dictionary = {}    ## stat -> Button (disabled when no spare points OR the stat is at STAT_MAX)
var _minus_buttons: Dictionary = {}   ## stat -> Button (disabled when the stat is at STAT_MIN)
var _points_label: Label
var _begin_btn: Button                 ## the PINNED confirm button; gated OFF until the name is non-blank (a run must be named)
var _name_hint: Label                  ## the "name required" line under the name field; visible only while the name is blank

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
var _swatches: Dictionary = {}        ## colour key ("arm"/"leg") -> Array of {button, stylebox, color}

# --- Shirt (the "Shirt" tab — the player paints their own torso texture) ---------------------------------------
var _tabs: TabContainer                 ## Stats|Look|Shirt — drives which 3D preview renders (only the visible one)
var _shirt_canvas: ShirtCanvas          ## the paint surface; owns the live shirt Image + shared ImageTexture
var _shirt_preview: CharacterPreview     ## a second live preview (full body) so the shirt shows on the torso as it's painted
var _shirt_swatches: Array = []         ## [{button, stylebox, color}] — the paint palette chips (bright border = the pick)
var _shirt_applied: bool = false        ## true once a drawn shirt has been bound into _appearance + the previews (first stroke)
var _shirt_tool_btns: Dictionary = {}   ## ShirtCanvas.TOOL_* -> toggle Button (Paint / Fill / Erase — a radio row)
var _shirt_size_btns: Dictionary = {}   ## brush-size (cells) -> toggle Button (the 1/2/3/4 radio row)
var _shirt_side_btns: Dictionary = {}   ## ShirtCanvas.SIDE_* -> toggle Button (Front / Back — the two tee sides)
var _shirt_undo_btn: Button             ## Undo — disabled while the canvas has nothing to step back to
var _shirt_mirror_btn: Button           ## the Mirror toggle (paint both horizontal halves at once)
var _shirt_custom_btn: Button           ## "Custom" swatch: opens the free HSV-wheel picker overlay (the spray-can idiom)
var _shirt_custom_sb: StyleBoxFlat      ## the Custom swatch's fill/border box — bg tracks the brush, border = active pick
var _shirt_picker_layer: CanvasLayer    ## lazily-built centered overlay hosting the HSV wheel (no native subwindow)
var _shirt_picker: ColorPicker          ## the wheel itself; its color_changed drives the brush live

func _ready() -> void:
	# Full-rect anchors + MOUSE_FILTER_STOP (eat clicks so the hidden menu buttons behind us never get them)
	# are authored in the scene, along with the dim and the near-full panel (anchors 0.05..0.95 of the 792x444
	# UI canvas — the old PANEL_MARGIN const, now editor-owned structure).
	_budget = StatBudget.new(STATS, STAT_MIN, STAT_MAX)  # seeds every stat to 0; owns the zero-sum + clamp rules
	_init_appearance()
	MenuStyle.apply(self)  # shared menu Theme + button sounds
	_bind_ui()
	_refresh()
	_refresh_look()
	_refresh_begin()  # initial state: the name starts blank, so Begin boots DISABLED and the "name required" hint shows
	_sync_previews()  # initial tab is Stats -> both 3D previews start inactive (nothing rendering off-screen)

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

## Bind the authored chrome by %unique name (structure lives in scenes/ui/character_creation.tscn), apply the
## skin-derived values on top, and fill the dynamic content. Every contract the old procedural build carried
## holds — the pinned name row + Back/Begin, the alpha-hidden hint, the lazy previews, the zero-sum steppers.
func _bind_ui() -> void:
	MenuStyle.style_dim(%Dim)  # the authored dim over the menu behind the panel (skin colour + eats clicks)

	# The panel's root column: shared skin separation (a skin knob, so applied here — never authored).
	(%Column as VBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.content_separation)

	var title: Label = MenuStyle.cap_label(%Title)
	MenuStyle.style_title(title)
	title.text = MenuStyle.title_text(PlayerText.CHARACTER_CREATE_TITLE)

	# --- Name (PINNED above the tabs; the row itself is authored — centered label + capped-width edit, no
	# EXPAND: a 24-char-max name never needs the full panel width; the shared LineEdit theme does the rest) ---
	(%NameLabel as Label).text = PlayerText.CHARACTER_CREATE_NAME_LABEL
	_name_edit = %NameEdit
	# The player TYPES their character name here — typed text must never be looked up as a translation msgid
	# by Godot's automatic Control-text translation (atr), so the field opts out wholesale. Both opt-outs are
	# AUTHORED in the scene (auto_translate_mode = Disabled + context_menu_enabled = false, the engine
	# right-click menu being untranslatable English — the name_entry_dialog.tscn idiom); the scene test pins them.
	_name_edit.placeholder_text = PlayerText.CHARACTER_NAME_PLACEHOLDER
	_name_edit.max_length = NAME_MAX_LENGTH

	# A run MUST be named before it can begin. This hint sits under the name field and shows only while the name is
	# blank; the Begin button below is gated OFF in lockstep (see _refresh_begin). Both react to text_changed and
	# use strip_edges(), so a whitespace-only entry still counts as unnamed.
	# The hint stays `visible` FOREVER and is hidden by ALPHA (self_modulate) instead: a VBox drops a hidden child
	# from layout, so a visible-toggle made the separator + the whole tab block jump up ~a hint-line on the FIRST
	# keystroke of every New Game (and back down when the name cleared). Alpha keeps the line's space reserved.
	_name_hint = %NameHint
	MenuStyle.style_hint(_name_hint)
	_name_hint.text = PlayerText.CHARACTER_CREATE_NAME_REQUIRED
	_name_edit.text_changed.connect(_on_name_changed)

	# --- Tabs: Stats | Look | Shirt (authored EXPAND_FILL to fill the slack between name and the pinned
	# buttons). The page node names are stable KEYS; the display titles are painted here from PlayerText via
	# set_tab_title (the options_menu idiom — a .tscn never carries display prose).
	_tabs = %Tabs
	_bind_stats_tab()
	_bind_look_tab()
	_bind_shirt_tab()
	_tabs.set_tab_title(_tabs.get_tab_idx_from_control(%StatsTab), PlayerText.CHARACTER_CREATE_STATS_TAB)
	_tabs.set_tab_title(_tabs.get_tab_idx_from_control(%LookTab), PlayerText.CHARACTER_CREATE_LOOK_TAB)
	_tabs.set_tab_title(_tabs.get_tab_idx_from_control(%ShirtTab), PlayerText.CHARACTER_CREATE_SHIRT_TAB)
	_tabs.tab_changed.connect(_on_tab_changed)  # render only the visible tab's 3D preview (see _sync_previews)

	# --- Back / Begin (PINNED below the tabs — always visible) ---
	# Skin-driven dialog row: shared separation + the skin's dialog button width floor, so this pair matches
	# every other menu's bottom button row instead of two bare text-width buttons.
	MenuStyle.style_button_row(%Buttons)
	var back: Button = %BackButton
	back.text = PlayerText.BACK
	back.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	back.pressed.connect(_on_back)
	# The stat build is always legal (the net can never exceed 0 — the + steppers gate on spare points, an all-zero
	# neutral character included), so the ONLY thing Begin waits on is a NAME: it's gated OFF until the name field is
	# non-blank (_refresh_begin), so a run can never start unnamed.
	_begin_btn = %BeginButton
	_begin_btn.text = PlayerText.BEGIN
	_begin_btn.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	_begin_btn.pressed.connect(_on_begin)

## The "Stats" tab: the spare-points banner + the one-line rule, then the zero-sum stat grid in an authored
## SCROLL region (vertical-only, so a tall list never buries the pinned buttons). The stepper rows are DYNAMIC
## (one per CharacterStats.STAT_NAMES entry) and stay code-built into the authored 5-column %StatGrid.
func _bind_stats_tab() -> void:
	_points_label = %PointsLabel
	_points_label.add_theme_color_override(&"font_color", MenuStyle.gold())
	var stat_hint: Label = %StatHint
	MenuStyle.style_hint(stat_hint)
	stat_hint.text = PlayerText.character_create_stat_hint(STAT_MIN, STAT_MAX)

	# Columns (authored: columns = 5): name | − | value | + | effect
	var grid: GridContainer = %StatGrid
	for stat in STATS:
		_add_stat_row(grid, stat)

## The "Look" tab: the live 3D character preview on the left, the part cyclers + colour swatches on the right.
## The preview and every control row are DYNAMIC (the preview is a code-built widget; the cyclers/swatches come
## from the disk catalog) — only the tab row + the controls column are authored.
func _bind_look_tab() -> void:
	var row: HBoxContainer = %LookTab

	# Preview and controls SHARE the tab width (~1 : 1.4, the controls column's ratio is authored) so the 3D
	# portrait gets real estate instead of being squeezed to its floor while the controls column balloons.
	# 140px stays as the preview's minimum. Inserted at index 0 — LEFT of the authored controls column.
	_preview = CharacterPreviewScene.new()
	_preview.auto_start = false  # lazy: built + rendered only while the Look tab is the active one (see _sync_previews)
	_preview.custom_minimum_size = Vector2(140, 0)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_stretch_ratio = 1.0
	row.add_child(_preview)
	row.move_child(_preview, 0)

	var controls: VBoxContainer = %LookControls

	# Body cycler (may switch to a whole-body model, which disables the head cycler below). Its own arrows disable
	# when the catalog ships a single body (the shipped default) — nothing to cycle to.
	var body_row := _make_cycler(PlayerText.CHARACTER_CREATE_BODY_LABEL, _step_body)
	_body_label = body_row.get_meta("value_label")
	_body_prev = body_row.get_meta("prev_button")
	_body_next = body_row.get_meta("next_button")
	controls.add_child(body_row)

	# Head cycler.
	var head_row := _make_cycler(PlayerText.CHARACTER_CREATE_HEAD_LABEL, _step_head)
	_head_label = head_row.get_meta("value_label")
	_head_prev = head_row.get_meta("prev_button")
	_head_next = head_row.get_meta("next_button")
	controls.add_child(head_row)

	controls.add_child(MenuStyle.make_separator())

	# No skin-colour row: skin is fixed to the catalog's default tint (the picker was removed — it had no visible
	# effect on the shipped head/body materials). _init_appearance() still seeds _appearance["skin"] = default_skin_color.
	# First arg = the painted TITLE (PlayerText); the trailing "arm"/"leg" strings are _appearance dict KEYS, not display text.
	controls.add_child(_make_swatch_row(PlayerText.CHARACTER_CREATE_ARMS_LABEL, _catalog.limb_palette, "arm"))
	controls.add_child(_make_swatch_row(PlayerText.CHARACTER_CREATE_LEGS_LABEL, _catalog.limb_palette, "leg"))

## A ‹ Label › cycler: a title, a prev button, the current value label, a next button. `handler` is called with
## the step direction (-1 / +1). Returns the row with the built sub-widgets stashed in metadata for the caller.
func _make_cycler(title: String, handler: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER  # the row spans the column; keep the widget cluster centered
	row.add_theme_constant_override("separation", 4)
	var title_l := Label.new()
	title_l.text = title
	title_l.custom_minimum_size = Vector2(44, 0)
	row.add_child(title_l)
	var prev := Button.new()
	prev.text = MenuStyle.skin.cycler_prev_glyph  # the ONE glyph home (MenuSkin) — shared with the Options cyclers
	prev.focus_mode = Control.FOCUS_NONE
	prev.pressed.connect(handler.bind(-1))
	row.add_child(prev)
	var value_l := Label.new()
	value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_l.clip_text = true
	# FIXED width (no EXPAND): an expanding label strands the < > arrows at the row's far edges. The skin
	# budget (120px, English-measured) seats every catalog display name; anything longer clips (clip_text)
	# instead of widening the row.
	value_l.custom_minimum_size = Vector2(float(MenuStyle.skin.cycler_value_width), 0)
	value_l.add_theme_color_override(&"font_color", MenuStyle.accent())
	row.add_child(value_l)
	var next := Button.new()
	next.text = MenuStyle.skin.cycler_next_glyph
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
	# Chip size derives from the skin's body text size (12*2-2 = 22 at defaults): at the 792x444 canvas a 16px
	# chip is a speck — this keeps the swatches real click targets and scales if the skin's type ramp changes.
	# (Explicit int annotation: MenuStyle is an autoload, so skin.* reads are Variant chains — := can't infer.)
	var chip: int = MenuStyle.skin.body_size * 2 - 2
	for color in palette:
		var b := Button.new()
		b.custom_minimum_size = Vector2(chip, chip)
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
		_body_label.text = _valid_bodies[_body_idx].display_name if not _valid_bodies.is_empty() else PlayerText.CHARACTER_CREATE_EMPTY_PART
	var body_locked := _valid_bodies.size() <= 1
	if _body_prev != null:
		_body_prev.disabled = body_locked
	if _body_next != null:
		_body_next.disabled = body_locked
	var whole := _current_body_whole()
	if _head_label != null:
		_head_label.text = (PlayerText.CHARACTER_CREATE_FROM_BODY if whole else (_valid_heads[_head_idx].display_name if not _valid_heads.is_empty() else PlayerText.CHARACTER_CREATE_EMPTY_PART))
		_head_label.modulate = Color(1, 1, 1, 0.4) if whole else Color.WHITE
	var head_locked := whole or _valid_heads.size() <= 1
	if _head_prev != null:
		_head_prev.disabled = head_locked
	if _head_next != null:
		_head_next.disabled = head_locked
	_mark_selected_swatches()
	_refresh_previews()  # push the appearance to BOTH tab previews (Look + Shirt) so they stay in sync

## Bright-border the swatch in each row whose colour matches the current pick (so the selection is legible).
func _mark_selected_swatches() -> void:
	for key in _swatches:
		var chosen: Color = _appearance.get(key, Color.WHITE)
		for e in _swatches[key]:
			var sb: StyleBoxFlat = e["stylebox"]
			sb.set_border_width_all(3 if (e["color"] as Color).is_equal_approx(chosen) else 0)  # 3px reads at the 22px chip size

# --- The "Shirt" tab: paint your own torso texture ------------------------------------------------------------

## The "Shirt" tab: the paint canvas on the left at the FULL tab height (it's the star — the old stacked layout
## squeezed it to ~146px), the tools + palette in a slim middle column, and a live full-body preview on the right
## so the shirt shows on the character as it's painted. The drawing starts a BLANK tee and is only APPLIED once
## the player actually paints (is_dirty) — an untouched tab leaves the character's base shirt. The column split
## (canvas 1.2 : tools : preview) is authored; every widget INSIDE the rows is dynamic (the ShirtCanvas, the
## radio/tool/palette buttons from ShirtCanvas consts + the disk catalog, the preview, the lazy HSV overlay).
func _bind_shirt_tab() -> void:
	var row: HBoxContainer = %ShirtRow

	# Left column (authored %ShirtLeft): a Front/Back side toggle above the paint surface. The tee has TWO
	# independently-drawn sides; the toggle switches which one the canvas edits (and snaps the 3D preview
	# round to that side — see _on_shirt_side).
	var side_row: HBoxContainer = %SideRow
	var side_group := ButtonGroup.new()
	for s: Array in [[ShirtCanvas.SIDE_FRONT, PlayerText.CHARACTER_CREATE_SHIRT_FRONT],
			[ShirtCanvas.SIDE_BACK, PlayerText.CHARACTER_CREATE_SHIRT_BACK]]:
		var sb := Button.new()
		sb.text = s[1]
		sb.toggle_mode = true
		sb.button_group = side_group
		sb.focus_mode = Control.FOCUS_NONE
		sb.toggled.connect(_on_shirt_side.bind(int(s[0])))
		side_row.add_child(sb)
		_shirt_side_btns[int(s[0])] = sb
	(_shirt_side_btns[ShirtCanvas.SIDE_FRONT] as Button).set_pressed_no_signal(true)

	# The paint surface, kept SQUARE by the authored AspectRatioContainer (%CanvasFrame, ratio 1 / FIT — the
	# engine defaults, so the cells stay square at any panel height).
	_shirt_canvas = ShirtCanvas.new()
	_shirt_canvas.custom_minimum_size = Vector2(150, 150)
	_shirt_canvas.changed.connect(_on_shirt_changed)
	_shirt_canvas.color_picked.connect(_on_shirt_color_picked)  # the Eyedropper tool sampled a colour
	%CanvasFrame.add_child(_shirt_canvas)

	# Middle (authored %ShirtMid): the tool rows + the palette, vertically centred (the Look-tab controls idiom).
	# Tool radio row: Paint | Fill (bucket) | Erase. One ButtonGroup so exactly one is ever down.
	var tool_group := ButtonGroup.new()
	var tools: HBoxContainer = %ToolsRow
	for t: Array in [[ShirtCanvas.TOOL_PAINT, PlayerText.CHARACTER_CREATE_SHIRT_PAINT],
			[ShirtCanvas.TOOL_FILL, PlayerText.CHARACTER_CREATE_SHIRT_FILL],
			[ShirtCanvas.TOOL_ERASE, PlayerText.CHARACTER_CREATE_SHIRT_ERASE],
			[ShirtCanvas.TOOL_EYEDROP, PlayerText.CHARACTER_CREATE_SHIRT_PICK]]:
		var tb := Button.new()
		tb.text = t[1]
		tb.toggle_mode = true
		tb.button_group = tool_group
		tb.focus_mode = Control.FOCUS_NONE
		tb.toggled.connect(_on_shirt_tool.bind(int(t[0])))
		tools.add_child(tb)
		_shirt_tool_btns[int(t[0])] = tb
	(_shirt_tool_btns[ShirtCanvas.TOOL_PAINT] as Button).set_pressed_no_signal(true)

	# Brush-size radio row: the authored "Size" label + the SHIRT_BRUSH_SIZES chips, one ButtonGroup so exactly
	# one is down. Size is the square footprint in cells (1 = a single pixel) and applies to PAINT + ERASE.
	var size_row: HBoxContainer = %SizeRow
	(%SizeLabel as Label).text = PlayerText.CHARACTER_CREATE_SHIRT_SIZE
	var size_group := ButtonGroup.new()
	for n: int in SHIRT_BRUSH_SIZES:
		var sbn := Button.new()
		sbn.text = str(n)
		sbn.toggle_mode = true
		sbn.button_group = size_group
		sbn.focus_mode = Control.FOCUS_NONE
		sbn.toggled.connect(_on_shirt_brush_size.bind(n))
		size_row.add_child(sbn)
		_shirt_size_btns[n] = sbn
	(_shirt_size_btns[SHIRT_BRUSH_SIZES[0]] as Button).set_pressed_no_signal(true)

	# Action row (authored): Mirror (toggle — paint both halves) | Undo | Reset.
	var actions: HBoxContainer = %ActionsRow
	_shirt_mirror_btn = Button.new()
	_shirt_mirror_btn.text = PlayerText.CHARACTER_CREATE_SHIRT_MIRROR
	_shirt_mirror_btn.toggle_mode = true
	_shirt_mirror_btn.focus_mode = Control.FOCUS_NONE
	_shirt_mirror_btn.toggled.connect(_on_shirt_mirror)
	actions.add_child(_shirt_mirror_btn)
	_shirt_undo_btn = Button.new()
	_shirt_undo_btn.text = PlayerText.CHARACTER_CREATE_SHIRT_UNDO
	_shirt_undo_btn.focus_mode = Control.FOCUS_NONE
	_shirt_undo_btn.disabled = true  # nothing to step back to yet; _on_shirt_changed re-gates
	_shirt_undo_btn.pressed.connect(_on_shirt_undo)
	actions.add_child(_shirt_undo_btn)
	var reset_btn := Button.new()
	reset_btn.text = PlayerText.CHARACTER_CREATE_SHIRT_RESET
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.pressed.connect(_on_shirt_reset)
	actions.add_child(reset_btn)

	# Palette: a grid of paint chips (the same chip idiom as the arm/leg swatch rows). Seed the first pick.
	# The grid itself stays CODE-BUILT (its column count derives from the authored palette's size); only its
	# centering host row (%PaletteCenter) is authored.
	var pal: PackedColorArray = _catalog.shirt_palette
	if not pal.is_empty():
		_shirt_canvas.set_paint_color(pal[0])
	var pal_grid := GridContainer.new()
	pal_grid.columns = maxi(1, mini(pal.size(), 4))  # 4 wide suits the slim middle column (12 chips = 3 rows)
	pal_grid.add_theme_constant_override("h_separation", 3)
	pal_grid.add_theme_constant_override("v_separation", 3)
	%PaletteCenter.add_child(pal_grid)
	var chip: int = MenuStyle.skin.body_size * 2 - 2  # matches the arm/leg swatch chip size (real click target)
	for color in pal:
		var b := Button.new()
		b.custom_minimum_size = Vector2(chip, chip)
		b.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_border_width_all(0)
		sb.border_color = Color.WHITE
		for state in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(_on_shirt_swatch.bind(color))
		pal_grid.add_child(b)
		_shirt_swatches.append({"button": b, "stylebox": sb, "color": color})

	# "Custom" swatch: opens the free HSV-wheel picker for any colour the presets don't cover. It's a plain Button
	# (NOT a ColorPickerButton) that toggles a centered overlay we build ourselves — the same idiom the spray can
	# uses (spray_painter.gd), because this project runs embed_subwindows = false in exclusive fullscreen, so a
	# native ColorPickerButton popup would open as a separate OS window that never shows. The swatch's own fill
	# tracks the current brush colour (bright border while it's the active pick, like the preset chips).
	# Row + label authored (%CustomRow / %CustomLabel); the swatch button itself is dynamic chrome.
	var custom_row: HBoxContainer = %CustomRow
	(%CustomLabel as Label).text = PlayerText.CHARACTER_CREATE_SHIRT_CUSTOM
	_shirt_custom_btn = Button.new()
	_shirt_custom_btn.custom_minimum_size = Vector2(chip * 2, chip)  # a wide swatch reads as a button, not a chip
	_shirt_custom_btn.focus_mode = Control.FOCUS_NONE
	_shirt_custom_sb = StyleBoxFlat.new()
	_shirt_custom_sb.bg_color = _shirt_canvas.paint_color if _shirt_canvas != null else Color.BLACK
	_shirt_custom_sb.border_color = Color.WHITE
	_shirt_custom_sb.set_border_width_all(0)
	for state in ["normal", "hover", "pressed", "disabled"]:
		_shirt_custom_btn.add_theme_stylebox_override(state, _shirt_custom_sb)
	_shirt_custom_btn.pressed.connect(_on_shirt_custom_open)
	custom_row.add_child(_shirt_custom_btn)

	# Right: a live FULL-BODY preview so the painted shirt shows on the torso. Lazy like the Look preview.
	# Appended after the authored %ShirtMid column, so it lands rightmost in the row.
	_shirt_preview = CharacterPreviewScene.new()
	_shirt_preview.auto_start = false
	_shirt_preview.auto_rotate = false  # hold still while painting so the shirt art doesn't drift out of view
	_shirt_preview.custom_minimum_size = Vector2(120, 0)
	_shirt_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shirt_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shirt_preview.size_flags_stretch_ratio = 1.0
	row.add_child(_shirt_preview)
	_mark_selected_shirt_swatch()

## Pick a brush colour. The canvas drops ERASE for the brush on a pick (keeps FILL) — mirror that on the toggles.
func _on_shirt_swatch(color: Color) -> void:
	if _shirt_canvas != null:
		_shirt_canvas.set_paint_color(color)
	_sync_shirt_tool_buttons()
	_mark_selected_shirt_swatch()

## Open the free-colour HSV wheel (building it on first use). Seeds the wheel from the current brush so it starts
## where the player left off. Toggles closed if it's already open (a second click of the swatch).
func _on_shirt_custom_open() -> void:
	if _shirt_picker_layer != null and _shirt_picker_layer.visible:
		_shirt_picker_layer.visible = false
		return
	if _shirt_picker_layer == null:
		_build_shirt_picker()
	if _shirt_picker != null and _shirt_canvas != null:
		_shirt_picker.color = _shirt_canvas.paint_color
	_shirt_picker_layer.visible = true

## Build the centered wheel overlay once: a full-rect dim that closes the picker when clicked OFF the panel, and a
## panelled trimmed HSV wheel (presets/sampler/mode/sliders/hex hidden — the compact wheel the spray can uses). A
## CanvasLayer, not a native popup, because embed_subwindows = false would open a ColorPickerButton popup as its
## own (never-shown) OS window in exclusive fullscreen.
func _build_shirt_picker() -> void:
	_shirt_picker_layer = CanvasLayer.new()
	_shirt_picker_layer.layer = 50  # above the creation panel
	add_child(_shirt_picker_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_shirt_picker_dim_input)  # a click anywhere off the panel closes the wheel
	_shirt_picker_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE  # let clicks fall through to the dim except where the panel eats them
	_shirt_picker_layer.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	_shirt_picker = ColorPicker.new()
	_shirt_picker.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	_shirt_picker.presets_visible = false
	_shirt_picker.sampler_visible = false
	_shirt_picker.color_modes_visible = false
	_shirt_picker.sliders_visible = false
	_shirt_picker.hex_visible = false
	_shirt_picker.deferred_mode = false
	_shirt_picker.color = _shirt_canvas.paint_color if _shirt_canvas != null else Color.BLACK
	_shirt_picker.color_changed.connect(_on_shirt_custom_color)
	col.add_child(_shirt_picker)
	var done := Button.new()
	done.text = PlayerText.CHARACTER_CREATE_SHIRT_PICK_DONE
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(_on_shirt_picker_close)
	col.add_child(done)

## A free colour chosen on the HSV wheel (fires live as the wheel is dragged). Same brush-pick path as a preset
## chip; no preset highlights (the Custom swatch's own fill is the tell), so a custom pick clears the chip borders.
func _on_shirt_custom_color(color: Color) -> void:
	if _shirt_canvas != null:
		_shirt_canvas.set_paint_color(color)  # forces opaque + drops ERASE for the brush
	_sync_shirt_tool_buttons()
	_mark_selected_shirt_swatch()

func _on_shirt_picker_close() -> void:
	if _shirt_picker_layer != null:
		_shirt_picker_layer.visible = false

## Close the wheel when the dim behind it is clicked (a click off the panel). The panel eats its own clicks.
func _on_shirt_picker_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_on_shirt_picker_close()

## A tool toggle went down (ButtonGroup: exactly one). Ignore the paired "up" emission of the old tool.
func _on_shirt_tool(on: bool, tool: int) -> void:
	if not on or _shirt_canvas == null:
		return
	_shirt_canvas.set_tool(tool)
	_mark_selected_shirt_swatch()  # no chip highlight while erasing

## A brush-size chip went down (ButtonGroup: exactly one). Ignore the paired "up" emission of the old size.
func _on_shirt_brush_size(on: bool, n: int) -> void:
	if not on or _shirt_canvas == null:
		return
	_shirt_canvas.set_brush_size(n)

## A Front/Back side chip went down (ButtonGroup: exactly one). Switch which side the canvas edits AND spin the 3D
## preview round to that side, so you always see the side you're drawing. Undo is per-side, so re-gate its button.
func _on_shirt_side(on: bool, side: int) -> void:
	if not on or _shirt_canvas == null:
		return
	_shirt_canvas.set_side(side)
	if _shirt_preview != null:
		_shirt_preview.set_turntable_yaw(0.0 if side == ShirtCanvas.SIDE_FRONT else PI)
	if _shirt_undo_btn != null:
		_shirt_undo_btn.disabled = not _shirt_canvas.can_undo()

func _on_shirt_mirror(on: bool) -> void:
	if _shirt_canvas != null:
		_shirt_canvas.mirror_x = on

## The Eyedropper sampled a colour from the canvas (the canvas already set it as the brush + stayed in EYEDROP so a
## drag scrubs). Reflect the pick on the Custom swatch + any matching preset chip.
func _on_shirt_color_picked(_color: Color) -> void:
	_mark_selected_shirt_swatch()

func _on_shirt_undo() -> void:
	if _shirt_canvas != null:
		_shirt_canvas.undo()  # emits changed -> _on_shirt_changed re-gates the button + (un)binds the shirt

## Reset DROPS the custom shirt: blank the canvas + clear dirty (undoable — the canvas snapshots first), remove
## the appearance key, and refresh both previews back to the character's base shirt.
func _on_shirt_reset() -> void:
	if _shirt_canvas != null:
		_shirt_canvas.reset_all()  # clears both sides; _on_shirt_changed un-applies + re-gates Undo
	_mark_selected_shirt_swatch()

## Push the canvas' tool state onto the toggle row without re-firing handlers (set_pressed_no_signal).
func _sync_shirt_tool_buttons() -> void:
	if _shirt_canvas == null:
		return
	for t: int in _shirt_tool_btns:
		(_shirt_tool_btns[t] as Button).set_pressed_no_signal(t == _shirt_canvas.tool)

## A canvas edit (stroke / fill / undo / reset). Keeps the applied-shirt binding in lockstep with is_dirty(): the
## FIRST edit binds the live shirt texture into the appearance + previews (one rig rebuild — every later stroke
## has already updated the shared texture IN PLACE), and an undo back to a clean canvas UN-binds it (the character
## returns to the base shirt). Also re-gates the Undo button.
func _on_shirt_changed() -> void:
	if _shirt_canvas == null:
		return
	if _shirt_canvas.is_dirty() and not _shirt_applied:
		_shirt_applied = true
		_appearance["shirt"] = _shirt_canvas.applied_texture()  # the live ImageTexture; _on_begin converts to bytes
		_refresh_previews()
	elif not _shirt_canvas.is_dirty() and _shirt_applied:
		_shirt_applied = false
		_appearance.erase("shirt")
		_refresh_previews()
	if _shirt_undo_btn != null:
		_shirt_undo_btn.disabled = not _shirt_canvas.can_undo()

## Push the current appearance to both tab previews (safe before either is built — set_appearance stores it).
func _refresh_previews() -> void:
	if _preview != null:
		_preview.set_appearance(_appearance)
	if _shirt_preview != null:
		_shirt_preview.set_appearance(_appearance)

## RGB match with a tolerance that bridges the 8-bit quantisation an eyedrop read introduces (see _mark_selected_shirt_swatch).
## Alpha is ignored — an eyedrop forces opaque and the palette chips are opaque. ~1.5/255 comfortably clears the ≤0.5/255
## quantisation error while staying well below the ≥0.05 spacing between distinct palette colours (no false positives).
const _SWATCH_MATCH_TOL := 1.5 / 255.0

static func _color_matches(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= _SWATCH_MATCH_TOL and absf(a.g - b.g) <= _SWATCH_MATCH_TOL and absf(a.b - b.b) <= _SWATCH_MATCH_TOL

## Bright-border the paint chip matching the current brush (nothing while erasing — the Erase toggle is the tell).
## Also point the "Custom" wheel swatch at the live brush so opening it starts from the current colour (setting
## ColorPickerButton.color in code does NOT re-emit color_changed, so this can't loop back through the handler).
func _mark_selected_shirt_swatch() -> void:
	if _shirt_canvas == null:
		return
	var erasing := _shirt_canvas.is_erasing()
	var brush := _shirt_canvas.paint_color
	var on_preset := false
	for e in _shirt_swatches:
		var sb: StyleBoxFlat = e["stylebox"]
		# Tolerant compare (not is_equal_approx): an EYEDROP brush is read back from the 8-bit RGBA8 canvas buffer, so it
		# differs from the float palette colour by up to ~1/255 — far beyond is_equal_approx's ~1e-5, which would leave
		# NO preset ever ringed after a pick (the ring always jumped to Custom). None of the authored palette colours are
		# k/255-representable. The tolerance is well under the ≥0.05 spacing between palette entries, so no false match.
		var chosen := (not erasing) and _color_matches(e["color"] as Color, brush)
		on_preset = on_preset or chosen
		sb.set_border_width_all(3 if chosen else 0)
	# The Custom swatch shows the live brush colour, and gets the active-pick border only when the brush is a
	# FREE colour (no preset matches it) — so exactly one swatch is ever ringed.
	if _shirt_custom_sb != null:
		_shirt_custom_sb.bg_color = brush
		_shirt_custom_sb.set_border_width_all(3 if (not erasing and not on_preset) else 0)

# --- Tab preview activation (only the visible tab's SubViewport renders) ---------------------------------------

func _on_tab_changed(_tab: int) -> void:
	_sync_previews()
	# Leaving the Shirt tab must not strand its colour-wheel overlay on top of Stats/Look.
	if _shirt_picker_layer != null and _tabs != null:
		var on_shirt: bool = _shirt_canvas != null and _tabs.get_current_tab_control() != null \
				and _tabs.get_current_tab_control().is_ancestor_of(_shirt_canvas)
		if not on_shirt:
			_shirt_picker_layer.visible = false

## Activate ONLY the currently-visible tab's 3D preview (Look or Shirt); deactivate the other so it isn't rendering
## a SubViewport off-screen. Stats has no preview -> both inactive there. ANCESTRY check (not direct parent) against
## the visible tab control — robust to tab reordering AND to a preview nested in sub-containers inside its tab (the
## Shirt tab wraps its row in a VBox; a parent==tab compare silently never activated it -> a black preview).
func _sync_previews() -> void:
	if _tabs == null:
		return
	var cur: Control = _tabs.get_current_tab_control()
	if _preview != null:
		_preview.set_active(cur != null and cur.is_ancestor_of(_preview))
	if _shirt_preview != null:
		_shirt_preview.set_active(cur != null and cur.is_ancestor_of(_shirt_preview))

func _add_stat_row(grid: GridContainer, stat: StringName) -> void:
	var name_l := Label.new()
	name_l.text = StatInfo.title(stat)
	name_l.custom_minimum_size = Vector2(64, 0)
	MenuStyle.attach_tip(name_l, StatInfo.blurb(stat))  # hover the name for what the stat governs
	grid.add_child(name_l)

	var minus := Button.new()
	minus.text = PlayerText.CHARACTER_CREATE_STAT_MINUS
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
	plus.text = PlayerText.CHARACTER_CREATE_STAT_PLUS
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

## Lower a stat by 1 — frees a point to spend elsewhere (StatBudget clamps at STAT_MIN). A minus is a real penalty.
func _on_minus(stat: StringName) -> void:
	if _budget.try_lower(stat):
		_refresh()

## Raise a stat by 1 — StatBudget only allows it with a spare point (net stays <= 0) AND below STAT_MAX; otherwise
## a no-op (free a point by lowering another stat first — "subtract from 0 to add elsewhere").
func _on_plus(stat: StringName) -> void:
	if _budget.try_raise(stat):
		_refresh()

## Re-stamp every value/effect label + the spare-points banner, and gate the steppers off the SAME StatBudget the
## rules live in (so the widget state can never drift from the allocator): + off with no spare point OR at
## STAT_MAX; − off at STAT_MIN.
func _refresh() -> void:
	for stat in STATS:
		var v: int = int(_budget.values[stat])
		(_value_labels[stat] as Label).text = str(v)
		(_effect_labels[stat] as Label).text = _effect_for(stat, v)
		(_plus_buttons[stat] as Button).disabled = not _budget.can_raise(stat)
		(_minus_buttons[stat] as Button).disabled = not _budget.can_lower(stat)
	_points_label.text = PlayerText.points_to_spend(_budget.spare())

## This one stat's live effect string — a throwaway sheet with only this stat set, run through the SAME StatInfo
## formatter the in-game Stats screen uses (so the wording never drifts). Neutral at baseline.
func _effect_for(stat: StringName, value: int) -> String:
	if value == 0:
		return PlayerText.NEUTRAL_EFFECT
	var s := CharacterStats.new()
	s.set(stat, value)
	return StatInfo._effect(stat, s)

## Consume `ui_cancel` while the creation overlay is up so it can't fall through to the OptionsMenu autoload (whose Escape
## toggle would STACK the settings panel over this menu-time overlay — like the TOS gate, it deliberately isn't an
## InputManager modal). Escape closes the colour wheel if it's open, else backs out of creation (same as the Back button).
func _input(event: InputEvent) -> void:
	if not visible or not is_inside_tree():
		return
	if event.is_action_pressed(&"ui_cancel"):
		if _shirt_picker_layer != null and _shirt_picker_layer.visible:
			_shirt_picker_layer.visible = false
		else:
			_on_back()
		get_viewport().set_input_as_handled()

## The implant-purchase step raises OVER this overlay: StartMenu hides us (NOT frees) so its "Back" returns here
## with the typed name / stat build / painted shirt intact. visible=false already silences _input's ui_cancel
## (its guard above), but two children outlive the root's visibility and need explicit handling: the tab
## previews' SubViewports (only re-synced on tab_changed — an active Look/Shirt preview would keep rendering
## off-screen for the implant step's whole lifetime) and the shirt HSV-wheel overlay (a CanvasLayer is NOT a
## CanvasItem, so the root's visibility never touches it).
func suspend() -> void:
	visible = false
	if _shirt_picker_layer != null:
		_shirt_picker_layer.visible = false
	if _preview != null:
		_preview.set_active(false)
	if _shirt_preview != null:
		_shirt_preview.set_active(false)

## Undo suspend(): reshow and reactivate exactly the visible tab's preview (the _sync_previews rule).
func resume() -> void:
	visible = true
	_sync_previews()

## Back: discard this build and return to the menu (StartMenu frees us + reshows its buttons). No profile change.
func _on_back() -> void:
	cancelled.emit()

## The name changed: re-gate Begin and toggle the "name required" hint. LineEdit.text_changed fires on every
## keystroke; setting .text in code does NOT emit it, so tests drive this handler directly.
func _on_name_changed(_new_text: String) -> void:
	_refresh_begin()

## Gate Begin on a NON-BLANK name (a run must be named). strip_edges() so a whitespace-only entry still counts as
## unnamed. Mirrors the stepper .disabled idiom — the button's own disabled state is the visible "can't progress
## yet" signal, backed by the "name required" hint. The _on_begin emit-guard is the belt-and-suspenders backstop.
func _refresh_begin() -> void:
	var named := not _name_edit.text.strip_edges().is_empty()
	if _begin_btn != null:
		_begin_btn.disabled = not named
	if _name_hint != null:
		# Alpha, not `visible`: the hint must KEEP its layout slot or the tabs below jump on the first keystroke.
		_name_hint.self_modulate.a = 0.0 if named else 1.0

## Confirm: hand the chosen name (trimmed) + a fresh {stat -> int} dict + the appearance dict to StartMenu, which
## writes them onto GameState and boots the game. REFUSES a blank name outright — Begin is already disabled while
## unnamed, but this backstops any other trigger (a programmatic press, a future keyboard shortcut) so a nameless
## run can never reach GameState; on refusal it focuses the field and re-asserts the gate.
func _on_begin() -> void:
	var character_name := _name_edit.text.strip_edges()
	if character_name.is_empty():
		_name_edit.grab_focus()
		_refresh_begin()
		return
	var appearance := _appearance.duplicate()
	# Emit the drawn shirt as SAVE-FRIENDLY PNG bytes (never the live ImageTexture the canvas holds — the config
	# can't serialise a Texture); drop the key entirely if the player didn't paint one (keep their base shirt).
	if _shirt_canvas != null and _shirt_canvas.is_dirty():
		appearance["shirt"] = _shirt_canvas.png_bytes()
	else:
		appearance.erase("shirt")
	confirmed.emit(character_name, _budget.to_dict(), appearance)
