extends GutTest

## AUTHORED-SCENE wiring contracts for the Options menu (scenes/ui/options_menu.tscn + options_menu.gd),
## mirroring the exemplar tests/test_heal_screen_scene.gd. The scene owns STRUCTURE only — the tab pages are
## generated from SettingsCatalog/ActionCatalog into the authored (empty) %Tabs container, and every string
## comes from PlayerText. These pin the silent-when-broken seams: the autoload points at the SCENE, every
## %node the script binds exists, no text is authored, and the screen-specific layout contracts hold.
## Behaviour (open/close/rebind/staging) stays in tests/test_options_menu.gd + playtest.

const SCENE := "res://scenes/ui/options_menu.tscn"

## Every unique name options_menu.gd binds in _bind_ui — a rename in the editor breaks the bind at boot,
## so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "VBox", "Title", "Tabs", "Bottom",
	"SaveLoadButton", "MainMenuButton", "ApplyButton", "RevertButton", "CloseButton", "QuitButton",
	"QuitConfirm", "QuitDim", "QuitCard", "QuitTitle", "ConfirmRow", "ConfirmButton", "CancelButton"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "OptionsMenu", "")), "*" + SCENE,
		"the OptionsMenu autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries options_menu.gd")
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
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	# Root + dims cover the screen; root eats clicks so nothing falls through behind the menu.
	for full in ["Root", "Dim", "QuitDim", "QuitConfirm"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_eq((inst.get_node("%Root") as Control).mouse_filter, Control.MOUSE_FILTER_STOP,
		"%Root eats clicks so nothing falls through behind the menu")
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open()")
	# The Panel keeps the PANEL_MARGIN anchor band (the fraction-inset panel that adapts to any res).
	var panel := inst.get_node("%Root/Panel") as PanelContainer
	var m: float = load("res://scripts/ui/options_menu.gd").PANEL_MARGIN
	assert_almost_eq(panel.anchor_left, m, 0.001, "Panel is inset by PANEL_MARGIN on the left")
	assert_almost_eq(panel.anchor_top, m, 0.001, "Panel is inset by PANEL_MARGIN on the top")
	assert_almost_eq(panel.anchor_right, 1.0 - m, 0.001, "Panel is inset by PANEL_MARGIN on the right")
	assert_almost_eq(panel.anchor_bottom, 1.0 - m, 0.001, "Panel is inset by PANEL_MARGIN on the bottom")
	# The tab container fills the panel and ships EMPTY — every page is generated from the catalogs.
	var tabs := inst.get_node("%Tabs") as TabContainer
	assert_eq(tabs.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "Tabs expand horizontally")
	assert_eq(tabs.size_flags_vertical, Control.SIZE_EXPAND_FILL, "Tabs expand vertically")
	assert_eq(tabs.get_tab_count(), 0,
		"the scene authors NO tab pages — _rebuild_tabs generates them from SettingsCatalog/ActionCatalog")
	# ONE card size for every tab. A TabContainer's minimum is the CURRENT page's minimum unless this is on,
	# so a wider page (Accessibility's two-up columns) handed the container a wider minimum and Godot grew the
	# whole panel past its anchor band mid-click. MenuStyle.apply pins it at runtime as well; authored here so
	# the editor preview tells the same truth. tests/test_menu_layout_stability.gd measures the result.
	assert_true(tabs.use_hidden_tabs_for_min_size,
		"the tab block reports ONE minimum for every page (use_hidden_tabs_for_min_size)")
	# Bottom row: END-aligned, with the in-game-only pair FIRST (left end) so hiding them at the start menu
	# never moves Apply/Revert/Close/Quit off the right edge.
	var bottom := inst.get_node("%Bottom") as HBoxContainer
	assert_eq(bottom.alignment, BoxContainer.ALIGNMENT_END, "the bottom row is right-justified")
	var order: Array[String] = []
	for c in bottom.get_children():
		order.append(String(c.name))
	assert_eq(order, ["SaveLoadButton", "MainMenuButton", "ApplyButton", "RevertButton", "CloseButton", "QuitButton"],
		"Save/Load + Main Menu sit FIRST (left end) so hiding them keeps Apply/Revert/Close/Quit in place")
	# The quit-confirm overlay ships disarmed and is %Root's LAST child so it draws over the panel.
	var qc := inst.get_node("%QuitConfirm") as Control
	assert_false(qc.visible, "the quit-confirm ships disarmed")
	var root := inst.get_node("%Root") as Control
	assert_eq(root.get_child(root.get_child_count() - 1), qc,
		"QuitConfirm is Root's last child (draws on top of the whole menu)")
	assert_eq((inst.get_node("%ConfirmRow") as HBoxContainer).alignment, BoxContainer.ALIGNMENT_CENTER,
		"Confirm/Cancel are centered in the quit card")
	inst.free()
