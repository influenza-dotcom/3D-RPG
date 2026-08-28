extends GutTest

## AUTHORED-SCENE wiring contract for InventoryScreen (scenes/ui/inventory_screen.tscn +
## scripts/ui/inventory_screen.gd), mirroring the heal_screen exemplar (test_heal_screen_scene.gd).
## Menus are .tscn scenes a designer/artist edits; the script binds chrome by %unique name and applies the
## skin-driven look on top. These are prefab WIRING contract tests (the silent-when-broken seams): the
## autoload points at the SCENE, every %node the script binds exists, no text is authored in the scene
## (strings belong to PlayerText / l10n, never a .tscn), and the player-menu-group layout contracts hold —
## incl. the PlayerMenus seam: the tab strip is CODE-BUILT into %TabSlot (its one-Button-per-tab structure is
## test_player_menus.gd's contract), so the scene must ship the slot EMPTY with zero authored Buttons.
## Behaviour (open/close/equip/grid) is in-tree -> playtest + test_inventory_screen.gd.

const SCENE := "res://scenes/ui/inventory_screen.tscn"

## Every unique name inventory_screen.gd binds in _bind_ui — a rename in the editor breaks the bind at
## boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "VBox", "TabSlot", "WalletRow", "Wallet", "DropMoneyButton",
	"Scroll", "Footer", "Detail"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "InventoryScreen", "")), "*" + SCENE,
		"the InventoryScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries inventory_screen.gd")
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


func test_layout_contracts_for_the_player_menu_group() -> void:
	# The player-menu-group discipline survives the scene conversion:
	#  * root + dim span the screen; the panel keeps the shared PANEL_MARGIN 0.12 anchor band (the
	#    loot/shop chrome — a drifted band would off-centre this tab against its siblings at 792x444);
	#  * %TabSlot ships EMPTY — the strip is built by PlayerMenus.build_tab_strip at boot, and its
	#    one-Button-per-tab structure is a cross-screen contract (test_player_menus.gd); an authored Button
	#    here would silently double the strip;
	#  * the grid's scroll slot EXPAND_FILLs both ways with horizontal scroll OFF (the grid sizes its
	#    cells to the width; the resized hook feeds it the slot height);
	#  * the footer is a clip host (fixed height comes from the skin in _bind_ui) whose Detail label
	#    wraps and top-aligns, so a long tooltip can never re-lay-out the grid above.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open()")
	var panel := (inst.get_node("%VBox") as Control).get_parent() as Control
	var margin: float = load("res://scripts/ui/inventory_screen.gd").PANEL_MARGIN
	assert_almost_eq(panel.anchor_left, margin, 0.001, "panel keeps the shared PANEL_MARGIN band (left)")
	assert_almost_eq(panel.anchor_top, margin, 0.001, "panel keeps the shared PANEL_MARGIN band (top)")
	assert_almost_eq(panel.anchor_right, 1.0 - margin, 0.001, "panel keeps the shared PANEL_MARGIN band (right)")
	assert_almost_eq(panel.anchor_bottom, 1.0 - margin, 0.001, "panel keeps the shared PANEL_MARGIN band (bottom)")
	assert_eq((inst.get_node("%TabSlot") as Node).get_child_count(), 0,
		"%TabSlot ships empty — PlayerMenus builds the tab strip into it at boot (never author tabs)")
	var scroll := inst.get_node("%Scroll") as ScrollContainer
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"horizontal scroll is OFF so the grid sizes its cells to the slot width")
	assert_eq(scroll.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the grid slot fills the panel width")
	assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the grid slot takes the spare panel height")
	var footer := inst.get_node("%Footer") as Control
	assert_true(footer.clip_contents, "the footer clips — a long tooltip must never grow it and pump the grid")
	var detail := inst.get_node("%Detail") as Label
	assert_eq(detail.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the detail line wraps within the footer")
	assert_eq(detail.vertical_alignment, VERTICAL_ALIGNMENT_TOP,
		"short text leaves dead space BELOW (top-aligned) — it never re-centres inside the clip host")
	inst.free()
