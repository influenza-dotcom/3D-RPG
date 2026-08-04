extends GutTest

## AUTHORED-SCENE wiring contract for ChipInstallScreen (scenes/ui/chip_install_screen.tscn +
## chip_install_screen.gd), mirroring the heal_screen exemplar. Prefab WIRING tests (the silent-when-broken
## seams): the autoload points at the SCENE, every %node the script binds exists, no text is authored in the
## scene (strings belong to PlayerText / l10n, never a .tscn), and the screen-specific layout discipline
## (PANEL_MARGIN band, twin expanding section scrolls, right-aligned wallet) survives the conversion.
## Behaviour (open/pause/install/buy) is in-tree -> playtest + test_chip_install.gd.

const SCENE := "res://scenes/ui/chip_install_screen.tscn"

## Every unique name chip_install_screen.gd binds in _bind_ui — a rename in the editor breaks the bind at
## boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "Content", "Title", "MoneyInset", "MoneyPlayer",
	"CarriedInset", "CarriedHeading", "CarriedList", "StockInset", "StockHeading", "StockList"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "ChipInstallScreen", "")), "*" + SCENE,
		"the ChipInstallScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries chip_install_screen.gd")
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


func test_authored_chrome_keeps_the_layout_contracts() -> void:
	# The screen-specific discipline survives the scene conversion: the PANEL_MARGIN anchor band, the two
	# stacked full-width sections whose scrolls EXPAND vertically (they share the leftover panel height
	# 50/50), the right-aligned expanding wallet readout, and full-screen root/dim.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open_install")
	# The modal inset band — authored anchors must match the script's PANEL_MARGIN pin.
	var margin: float = load("res://scripts/ui/chip_install_screen.gd").PANEL_MARGIN
	var panel := (inst.get_node("%Content") as Control).get_parent() as PanelContainer
	assert_not_null(panel, "%Content sits in the anchored PanelContainer band")
	assert_almost_eq(panel.anchor_left, margin, 0.0001, "Panel's left anchor is the shared PANEL_MARGIN inset")
	assert_almost_eq(panel.anchor_top, margin, 0.0001, "Panel's top anchor is the shared PANEL_MARGIN inset")
	assert_almost_eq(panel.anchor_right, 1.0 - margin, 0.0001, "Panel's right anchor mirrors PANEL_MARGIN")
	assert_almost_eq(panel.anchor_bottom, 1.0 - margin, 0.0001, "Panel's bottom anchor mirrors PANEL_MARGIN")
	# Twin sections: each row list lives in a ScrollContainer that expands BOTH ways (the 50/50 height
	# split) with horizontal scrolling disabled (rows shrink to the panel width, never scroll sideways).
	for list_name in ["CarriedList", "StockList"]:
		var list := inst.get_node("%" + list_name) as VBoxContainer
		assert_eq(list.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s rows fill the section width" % list_name)
		var scroll := list.get_parent() as ScrollContainer
		assert_not_null(scroll, "%s lives in its section ScrollContainer" % list_name)
		assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "%s's scroll expands vertically (50/50 height share)" % list_name)
		assert_eq(scroll.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s's scroll expands horizontally" % list_name)
		assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "%s's scroll never scrolls sideways" % list_name)
	# Wallet readout: right-aligned and EXPAND_FILL so the money phrase lands on the price column's edge.
	var money := inst.get_node("%MoneyPlayer") as Label
	assert_eq(money.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT, "the wallet readout right-aligns onto the price column")
	assert_eq(money.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the wallet readout spans the row to reach that edge")
	assert_true(inst.get_node("%MoneyInset") is MarginContainer, "the wallet rides a row-inset MarginContainer (margins applied at runtime from the theme)")
	inst.free()
