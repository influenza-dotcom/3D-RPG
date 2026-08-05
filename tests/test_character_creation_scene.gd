extends GutTest

## AUTHORED-SCENE wiring contract for character creation (scenes/ui/character_creation.tscn +
## scripts/ui/character_creation.gd). The screen is NOT an autoload — StartMenu preloads the SCENE and
## instances it on "New Game" — so the "autoload points at the scene" test becomes: the HOST const points at
## the scene, and the scene root carries the script. The rest mirrors test_heal_screen_scene.gd: every %node
## the script binds exists, no text is authored in the scene (strings belong to PlayerText / l10n, never a
## .tscn), and the screen-specific layout contracts hold. BEHAVIOUR (zero-sum steppers, name gating, the
## shirt canvas binding) stays in tests/test_character_creation.gd + playtest — these tests only
## instantiate() off-tree, never _ready.

const SCENE := "res://scenes/ui/character_creation.tscn"
const SCRIPT_PATH := "res://scripts/ui/character_creation.gd"
const HOST_SCRIPT := "res://scripts/ui/start_menu.gd"

## Every unique name character_creation.gd binds in _bind_ui — a rename in the editor breaks the bind at
## boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Dim", "Column", "Title", "NameLabel", "NameEdit", "NameHint",
	"Tabs", "StatsTab", "PointsLabel", "StatHint", "StatScroll", "StatGrid",
	"LookTab", "LookControls",
	"ShirtTab", "ShirtRow", "SideRow", "CanvasFrame", "ShirtMid", "ToolsRow", "SizeRow", "SizeLabel",
	"ActionsRow", "PaletteCenter", "CustomRow", "CustomLabel",
	"Buttons", "BackButton", "BeginButton"]


func test_host_points_at_the_authored_scene() -> void:
	# The conversion contract: StartMenu preloads the SCENE (root carries the script) — a bare-script .new()
	# would silently skip the authored layout and _bind_ui would null-deref the moment New Game is clicked.
	var host_src := FileAccess.get_file_as_string(HOST_SCRIPT)
	assert_true(host_src.contains("preload(\"%s\")" % SCENE),
		"StartMenu preloads the authored character-creation scene")
	assert_false(host_src.contains("preload(\"%s\")" % SCRIPT_PATH),
		"StartMenu no longer preloads the bare script")
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_true(inst is Control, "root is the full-rect Control overlay StartMenu add_child's")
	assert_not_null(inst.get_script(), "the root carries a script")
	assert_eq(String(inst.get_script().resource_path), SCRIPT_PATH, "the root carries character_creation.gd")
	inst.free()


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (the script binds it in _bind_ui)" % n)
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in PlayerText (the text-debt ratchet + l10n own them) — a caption typed into the .tscn
	# would bypass both and ship unauthored. Tab TITLES are covered too: they're painted via set_tab_title
	# from PlayerText, and the page node names are stable keys the titles never touch.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button:
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text (the script sets it from PlayerText)" % n.name)
		elif n is LineEdit:
			assert_eq((n as LineEdit).placeholder_text, "", "%s ships with an empty placeholder" % n.name)
	inst.free()


func test_bound_chrome_keeps_the_layout_contracts() -> void:
	var inst: Node = (load(SCENE) as PackedScene).instantiate()

	# The overlay eats clicks so the (hidden) menu buttons behind it never get them; the dim spans the screen.
	var root := inst as Control
	assert_eq(root.mouse_filter, Control.MOUSE_FILTER_STOP, "the root eats clicks over the hidden menu")
	assert_eq(root.anchor_right, 1.0, "the root spans the screen (anchor_right)")
	assert_eq(root.anchor_bottom, 1.0, "the root spans the screen (anchor_bottom)")
	var dim := inst.get_node("%Dim") as Control
	assert_eq(dim.anchor_right, 1.0, "the dim spans the screen (anchor_right)")
	assert_eq(dim.anchor_bottom, 1.0, "the dim spans the screen (anchor_bottom)")

	# The name field paints player-TYPED text: it must never be looked up as a translation msgid (atr), and
	# the engine's untranslatable-English right-click menu stays off — both AUTHORED, per name_entry_dialog.
	var edit := inst.get_node("%NameEdit") as LineEdit
	assert_eq(edit.auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED,
		"the name LineEdit opts out of automatic Control-text translation")
	assert_false(edit.context_menu_enabled, "the engine right-click menu stays off (untranslatable English)")

	# The "name required" hint hides by ALPHA, never `visible`: a VBox drops a hidden child from layout, so
	# the whole tab block would jump on the first keystroke. The scene must ship it visible (slot reserved).
	assert_true((inst.get_node("%NameHint") as Control).visible,
		"the name hint ships visible — the script hides it with self_modulate alpha, keeping its layout slot")

	# The tabs fill the slack between the pinned name row and the pinned Back/Begin row.
	var tabs := inst.get_node("%Tabs") as TabContainer
	assert_eq(tabs.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the tab block takes the vertical slack")
	assert_eq(tabs.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the tab block takes the full panel width")
	# Page order is a stable contract (_sync_previews + the qa harness drive tabs by index): Stats first so
	# both lazy 3D previews start INACTIVE, Look second, Shirt third.
	assert_eq(tabs.get_tab_idx_from_control(inst.get_node("%StatsTab") as Control), 0, "Stats is the first (boot) tab")
	assert_eq(tabs.get_tab_idx_from_control(inst.get_node("%LookTab") as Control), 1, "Look is the second tab")
	assert_eq(tabs.get_tab_idx_from_control(inst.get_node("%ShirtTab") as Control), 2, "Shirt is the third tab")

	# The stat grid scrolls vertically ONLY (rows are width-fitted) and carries the 5 authored columns
	# (name | − | value | + | effect).
	var scroll := inst.get_node("%StatScroll") as ScrollContainer
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"the stat scroll is vertical-only — rows fit the width")
	assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the stat scroll takes the tab's slack")
	assert_eq((inst.get_node("%StatGrid") as GridContainer).columns, 5,
		"the stat grid keeps its 5 columns (name | - | value | + | effect)")

	# The shirt paint surface stays SQUARE at any panel height (its cells must stay square).
	var canvas_frame := inst.get_node("%CanvasFrame")
	assert_true(canvas_frame is AspectRatioContainer, "the canvas host is an AspectRatioContainer")
	assert_eq((canvas_frame as AspectRatioContainer).ratio, 1.0, "the paint surface is kept square (ratio 1)")

	inst.free()
