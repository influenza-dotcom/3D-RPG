extends GutTest

## LootScreen's AUTHORED-SCENE conversion (scenes/ui/loot_screen.tscn + scripts/ui/loot_screen.gd), the
## heal-screen idiom (see tests/test_heal_screen_scene.gd for the exemplar rationale). Prefab WIRING
## contract tests — the silent-when-broken seams: the autoload points at the SCENE, every %node the script
## binds exists, no text is authored in the scene (strings belong to PlayerText / l10n, never a .tscn),
## and the loot-specific layout contracts (the PANEL_MARGIN anchor band, side-by-side EXPAND_FILL grid
## columns, the fixed-height clip footer) survive editor rearranging. Behaviour (take/deposit/pickpocket)
## is covered by tests/test_loot_drop.gd + tests/test_pickpocket.gd against the live autoload.

const SCENE := "res://scenes/ui/loot_screen.tscn"

## Every unique name loot_screen.gd binds in _bind_ui — a rename in the editor breaks the bind at boot,
## so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "VBox", "Title", "Columns", "SourceColumn", "SourceHeading",
	"SourceScroll", "PlayerColumn", "PlayerHeading", "PlayerScroll", "Footer", "Detail"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "LootScreen", "")), "*" + SCENE,
		"the LootScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries loot_screen.gd")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (the script binds it in _bind_ui)" % n)
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in PlayerText (the text-debt ratchet + l10n own them) — a caption typed into the .tscn
	# would bypass both and ship unauthored. The scene must hold only structure.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button:
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text (the script sets it from PlayerText)" % n.name)
	inst.free()


func test_bound_chrome_keeps_the_layout_contracts() -> void:
	# The loot layout's structural contracts: the panel sits on the PANEL_MARGIN 0.12 anchor band; the two
	# grid columns split the panel EXPAND_FILL side by side; each scroll slot expands both ways with
	# horizontal scroll DISABLED (the grid fits by width — a sideways scrollbar would hide columns); the
	# footer is a clipping host (fixed height is stamped from the skin at bind time) whose detail label
	# fills it and autowraps; root + dim cover the screen; the screen ships hidden.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var panel := (inst.get_node("%Root") as Control).get_node("Panel") as PanelContainer
	assert_not_null(panel, "the anchor-band Panel exists under %Root")
	assert_almost_eq(panel.anchor_left, 0.12, 0.001, "the panel keeps the PANEL_MARGIN left anchor")
	assert_almost_eq(panel.anchor_top, 0.12, 0.001, "the panel keeps the PANEL_MARGIN top anchor")
	assert_almost_eq(panel.anchor_right, 0.88, 0.001, "the panel keeps the PANEL_MARGIN right anchor")
	assert_almost_eq(panel.anchor_bottom, 0.88, 0.001, "the panel keeps the PANEL_MARGIN bottom anchor")
	var columns := inst.get_node("%Columns") as HBoxContainer
	assert_eq(columns.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the columns row takes the panel's spare height")
	for c in ["SourceColumn", "PlayerColumn"]:
		var col := inst.get_node("%" + c) as VBoxContainer
		assert_eq(col.get_parent(), columns, "%s sits side-by-side inside %%Columns" % c)
		assert_eq(col.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s splits the panel width evenly" % c)
		assert_eq(col.size_flags_vertical, Control.SIZE_EXPAND_FILL, "%s fills the columns row's height" % c)
	for s in ["SourceScroll", "PlayerScroll"]:
		var scroll := inst.get_node("%" + s) as ScrollContainer
		assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
			"%s never scrolls sideways (the grid fits by width; only the too-short-window fallback scrolls)" % s)
		assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "%s hands its column's height budget to the grid" % s)
		assert_eq(scroll.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s hands its column's width to the grid" % s)
	var footer := inst.get_node("%Footer") as Control
	assert_true(footer.clip_contents, "the footer CLIPS an over-long tooltip instead of growing (no grid judder)")
	var detail := inst.get_node("%Detail") as Label
	assert_eq(detail.get_parent(), footer, "the detail label lives inside the clip footer")
	assert_eq(detail.anchor_right, 1.0, "the detail label fills the footer (anchor_right)")
	assert_eq(detail.anchor_bottom, 1.0, "the detail label fills the footer (anchor_bottom)")
	assert_eq(detail.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the detail line wraps within the footer")
	assert_eq(detail.vertical_alignment, VERTICAL_ALIGNMENT_TOP, "short detail text leaves dead space BELOW, never re-centres")
	for full in ["Root", "Dim"]:
		var f := inst.get_node("%" + full) as Control
		assert_eq(f.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(f.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until an open_* call")
	inst.free()
