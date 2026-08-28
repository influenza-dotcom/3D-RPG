extends GutTest

## AUTHORED-SCENE wiring contract for StatsScreen (scenes/ui/stats_screen.tscn +
## scripts/ui/stats_screen.gd), mirroring the heal_screen exemplar (test_heal_screen_scene.gd).
## Menus are .tscn scenes a designer/artist edits; the script binds chrome by %unique name and applies the
## skin-driven look on top. These are prefab WIRING contract tests (the silent-when-broken seams): the
## autoload points at the SCENE, every %node the script binds exists, no text is authored in the scene
## (strings belong to PlayerText / l10n, never a .tscn), and the player-menu-group layout contracts hold —
## incl. the PlayerMenus seam: the tab strip is CODE-BUILT into %TabSlot (its one-Button-per-tab structure is
## test_player_menus.gd's contract), so the scene must ship the slot EMPTY with zero authored Buttons.
## Behaviour (open/close/live refresh) is in-tree -> playtest + test_stats_screen.gd.

const SCENE := "res://scenes/ui/stats_screen.tscn"

## Every unique name stats_screen.gd binds in _bind_ui — a rename in the editor breaks the bind at
## boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "VBox", "TabSlot", "NameLabel", "Summary", "Body", "PortraitCol",
	"PortraitFrame", "InspectButton", "Scroll", "StatGrid"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "StatsScreen", "")), "*" + SCENE,
		"the StatsScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries stats_screen.gd")
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
	#  * the body splits 1:2 — the portrait column EXPAND_FILLs at the default 1 share, the stat scroll
	#    at stretch_ratio 2, so the six blocks keep their two-abreast width budget;
	#  * the stat scroll EXPAND_FILLs both ways with horizontal scroll OFF (long blurbs/effects must wrap
	#    to their ~180px cell instead of widening the grid past the panel);
	#  * the grid is 2 columns (the 2x3 block layout that fits the ~194px body at 792x444);
	#  * the portrait letterboxes in an AspectRatioContainer (ratio 0.8) instead of face-filling;
	#  * the name label opts out of auto-translate (a player-TYPED name is never a msgid).
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open()")
	var panel := (inst.get_node("%VBox") as Control).get_parent() as Control
	var margin: float = load("res://scripts/ui/stats_screen.gd").PANEL_MARGIN
	assert_almost_eq(panel.anchor_left, margin, 0.001, "panel keeps the shared PANEL_MARGIN band (left)")
	assert_almost_eq(panel.anchor_top, margin, 0.001, "panel keeps the shared PANEL_MARGIN band (top)")
	assert_almost_eq(panel.anchor_right, 1.0 - margin, 0.001, "panel keeps the shared PANEL_MARGIN band (right)")
	assert_almost_eq(panel.anchor_bottom, 1.0 - margin, 0.001, "panel keeps the shared PANEL_MARGIN band (bottom)")
	assert_eq((inst.get_node("%TabSlot") as Node).get_child_count(), 0,
		"%TabSlot ships empty — PlayerMenus builds the tab strip into it at boot (never author tabs)")
	var col := inst.get_node("%PortraitCol") as Control
	assert_eq(col.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the portrait column takes its 1 width share")
	assert_almost_eq(col.size_flags_stretch_ratio, 1.0, 0.001, "portrait column = 1 share vs the stat column's 2")
	var scroll := inst.get_node("%Scroll") as ScrollContainer
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"horizontal scroll is OFF so long blurbs wrap to their grid cell")
	assert_eq(scroll.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the stat scroll fills its width share")
	assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the stat scroll takes the body height")
	assert_almost_eq(scroll.size_flags_stretch_ratio, 2.0, 0.001, "stat column = 2 width shares vs the portrait's 1")
	var grid := inst.get_node("%StatGrid") as GridContainer
	assert_eq(grid.columns, 2, "six stat blocks lay out 2x3 (the ~194px body budget at 792x444)")
	assert_eq(grid.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the grid fills the scroll width")
	var frame := inst.get_node("%PortraitFrame") as AspectRatioContainer
	assert_almost_eq(frame.ratio, 0.8, 0.001, "the portrait letterboxes at the authored card ratio")
	# Inspect ships FOCUS_NONE in the .tscn and is PROMOTED to FOCUS_ALL by _bind_ui at boot (the tab strip is
	# FOCUS_NONE by cross-screen contract, so without the promotion this tab had zero focusable controls and a
	# pad could never open Character Inspect from it). This pin is the authored half — the live half is
	# tests/test_stats_screen.gd::test_inspect_is_reachable_without_a_mouse. If a designer ever authors the
	# promotion into the scene instead, flip this to FOCUS_ALL; the two must not silently disagree.
	assert_eq((inst.get_node("%InspectButton") as Button).focus_mode, Control.FOCUS_NONE,
		"the .tscn still ships Inspect focus-less; stats_screen.gd promotes it in _bind_ui")
	assert_eq((inst.get_node("%NameLabel") as Node).auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED,
		"the player-typed name never routes through auto-translate (not a msgid)")
	inst.free()
