extends GutTest

## ShopScreen's AUTHORED-SCENE wiring (scenes/ui/shop_screen.tscn + scripts/ui/shop_screen.gd), mirroring
## the heal-screen exemplar's contract tests (test_heal_screen_scene.gd). Menus are .tscn scenes a
## designer/artist edits; the script binds chrome by %unique name and applies the skin-driven look on top.
## These are prefab WIRING contract tests (the silent-when-broken seams): the autoload points at the SCENE,
## every %node the script binds exists, no text is authored in the scene (strings belong to PlayerText /
## l10n, never a .tscn), and the shop's own layout discipline holds. Behaviour (open/pause/buy/sell) stays
## covered by test_merchant.gd's in-tree cases + playtest.

const SCENE := "res://scenes/ui/shop_screen.tscn"

## Every unique name shop_screen.gd binds in _bind_ui — a rename in the editor breaks the bind at boot,
## so pin the roster here where it fails loudly instead.
const BOUND := [
	"Root", "Dim", "VBox", "TitleSpacer", "Title", "SortButton",
	"Columns", "StockColumn", "StockWallet", "StockScroll",
	"PlayerColumn", "PlayerWallet", "PlayerScroll", "Footer", "Detail",
]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "ShopScreen", "")), "*" + SCENE,
		"the ShopScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries shop_screen.gd")
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
	# The shop's own layout discipline survives the scene conversion:
	#  * root/dim span the screen; the panel keeps the 0.12 anchor band (the design-canvas geometry every
	#    cell-size number in _bind_ui's comments is derived from);
	#  * the Sort button clips + right-aligns and takes no focus (its FIXED width is a skin budget, code-set);
	#  * the two columns EXPAND_FILL side-by-side, each scroll slot expands with horizontal scroll DISABLED
	#    (the too-short-window fallback must never scroll sideways);
	#  * the wallet headings trim with "…" instead of widening their column (no-shift rule);
	#  * the footer is a clip host (fixed height is skin-derived, code-set) with the detail label filling it,
	#    centred + wrapping — the fixed-height detail line can't squeeze the grids;
	#  * the screen ships hidden until open_shop.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open_shop")
	var panel := (inst.get_node("%VBox") as Control).get_parent() as Control
	assert_true(panel is PanelContainer, "the content VBox lives in the themed PanelContainer")
	assert_almost_eq(panel.anchor_left, 0.12, 0.001, "the panel keeps the 0.12 anchor band (left)")
	assert_almost_eq(panel.anchor_bottom, 0.88, 0.001, "the panel keeps the 0.12 anchor band (bottom)")
	var sort_btn := inst.get_node("%SortButton") as Button
	assert_true(sort_btn.clip_text, "the Sort button clips its caption (fixed footprint as the mode cycles)")
	assert_eq(sort_btn.alignment, HORIZONTAL_ALIGNMENT_RIGHT, "the Sort caption right-aligns against the panel edge")
	assert_eq(sort_btn.focus_mode, Control.FOCUS_NONE, "the Sort button takes no focus (mouse-driven screen)")
	assert_eq((inst.get_node("%Title") as Control).size_flags_horizontal, Control.SIZE_EXPAND_FILL,
		"the title expands between its two fixed flanks (optical centring)")
	assert_eq((inst.get_node("%Columns") as Control).size_flags_vertical, Control.SIZE_EXPAND_FILL,
		"the columns row takes the panel's spare height (grids get the room)")
	for col in ["StockColumn", "PlayerColumn"]:
		assert_eq((inst.get_node("%" + col) as Control).size_flags_horizontal, Control.SIZE_EXPAND_FILL,
			"%s splits the panel width evenly with its sibling" % col)
	for sc in ["StockScroll", "PlayerScroll"]:
		var scroll := inst.get_node("%" + sc) as ScrollContainer
		assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
			"%s never scrolls sideways (the fallback is vertical-only)" % sc)
		assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "%s fills its column's slot" % sc)
	for w in ["StockWallet", "PlayerWallet"]:
		assert_eq((inst.get_node("%" + w) as Label).text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS,
			"%s trims a huge amount instead of widening the column" % w)
	assert_true((inst.get_node("%Footer") as Control).clip_contents,
		"the footer clips overflow (a long tooltip can't grow it and squeeze the grids)")
	var detail := inst.get_node("%Detail") as Label
	assert_eq(detail.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "the detail line centres under both grids")
	assert_eq(detail.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the detail line wraps within the footer")
	assert_eq(detail.anchor_right, 1.0, "the detail label fills the clip footer (anchor_right)")
	inst.free()
