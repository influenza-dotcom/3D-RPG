extends GutTest

## AUTHORED-SCENE wiring contract for ImplantsScreen (scenes/ui/implants_screen.tscn +
## scripts/ui/implants_screen.gd), mirroring test_quest_journal_scene.gd (the tab-family's list-screen
## exemplar). Menus are .tscn scenes a designer/artist edits; the script binds chrome by %unique name and
## applies the skin-driven look on top. These are prefab WIRING contract tests (the silent-when-broken
## seams): the autoload points at the SCENE, every %node the script binds exists, no text is authored in
## the scene (strings belong to PlayerText / l10n, never a .tscn), and the player-menu-group layout
## contracts hold — incl. the PlayerMenus seam: the tab strip is CODE-BUILT into %TabSlot (its
## one-Button-per-tab structure is test_player_menus.gd's contract), so the scene must ship the slot
## EMPTY with zero authored Buttons. Roster behaviour is in tests/test_implants_screen.gd; the on/off toggle
## (installed-vs-active + persistence) is tests/test_implant_toggle.gd. CONTROLLER PARITY (rows FOCUS_ALL,
## focus seeded on open, re-seated across rebuilds) is pinned at the bottom, the test_atm_screen_scene idiom.

const SCENE := "res://scenes/ui/implants_screen.tscn"
const SCREEN_SOURCE := "res://scripts/ui/implants_screen.gd"

## Every unique name the screen depends on: the ones implants_screen.gd binds in _bind_ui (Root/Dim/VBox/
## TabSlot/ImplantList — a rename in the editor breaks the bind at boot) plus %Scroll, which only the
## layout pins below read but whose scroll-mode contract the screen's no-widen row discipline relies on.
const BOUND := ["Root", "Dim", "VBox", "TabSlot", "Scroll", "ImplantList"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "ImplantsScreen", "")), "*" + SCENE,
		"the ImplantsScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries implants_screen.gd")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (the script binds it in _bind_ui)" % n)
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in PlayerText (the text-debt ratchet + l10n own them) — a caption typed into the .tscn
	# would bypass both and ship unauthored. This screen's scene holds only CONTAINERS (every Label is a
	# dynamic section/row line, the INSTALLED rows are runtime toggle Buttons, and the tab Buttons are
	# PlayerMenus-built), so the pin here matches the journal's: ZERO authored text-bearing nodes at all.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var text_nodes := 0
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button:
			text_nodes += 1
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text (the script sets it from PlayerText)" % n.name)
	assert_eq(text_nodes, 0, "the scene authors no Labels/Buttons — section blocks and the tab strip are code-built")
	inst.free()


func test_layout_contracts_for_the_player_menu_group() -> void:
	# The player-menu-group discipline survives on the new sibling:
	#  * root + dim span the screen and the screen ships hidden;
	#  * the panel keeps the shared PANEL_MARGIN 0.12 anchor band (the loot/shop chrome — a drifted band
	#    would off-centre this tab against its siblings at 792x444);
	#  * %TabSlot ships EMPTY — the strip is built by PlayerMenus.build_tab_strip at boot, and its
	#    one-Button-per-tab structure is a cross-screen contract (test_player_menus.gd); an authored
	#    Button here would silently double the strip;
	#  * the implant scroll EXPAND_FILLs both ways with horizontal scroll OFF (a long chip/ability name
	#    must TRIM in its row — _make_row's OVERRUN_TRIM_ELLIPSIS — instead of widening the panel);
	#  * %ImplantList fills the scroll width and keeps its authored 14px gap (the section-block rhythm).
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open()")
	var panel := (inst.get_node("%VBox") as Control).get_parent() as Control
	var margin: float = load("res://scripts/ui/implants_screen.gd").PANEL_MARGIN
	assert_almost_eq(panel.anchor_left, margin, 0.001, "panel keeps the shared PANEL_MARGIN band (left)")
	assert_almost_eq(panel.anchor_top, margin, 0.001, "panel keeps the shared PANEL_MARGIN band (top)")
	assert_almost_eq(panel.anchor_right, 1.0 - margin, 0.001, "panel keeps the shared PANEL_MARGIN band (right)")
	assert_almost_eq(panel.anchor_bottom, 1.0 - margin, 0.001, "panel keeps the shared PANEL_MARGIN band (bottom)")
	assert_eq((inst.get_node("%TabSlot") as Node).get_child_count(), 0,
		"%TabSlot ships empty — PlayerMenus builds the tab strip into it at boot (never author tabs)")
	var scroll := inst.get_node("%Scroll") as ScrollContainer
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"horizontal scroll is OFF so runaway names trim instead of widening the panel")
	assert_eq(scroll.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the implant scroll fills the panel width")
	assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the implant scroll takes the body height")
	var list := inst.get_node("%ImplantList") as VBoxContainer
	assert_eq(list.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the list fills the scroll width")
	assert_eq(list.get_theme_constant("separation"), 14, "the authored 14px section-block gap survives")
	inst.free()


func test_toggle_rows_are_reachable_by_a_pad() -> void:
	# ⭐CONTROLLER PARITY, the runtime-built half (the atm_screen _add_chip lesson): the INSTALLED toggle rows
	# are this tab's ONLY focusables (the tab strip is FOCUS_NONE by test_player_menus.gd's cross-screen
	# contract), so rows built FOCUS_NONE — the exact state this screen shipped in — leave a pad player with
	# no focus owner and nothing to move: every implant is unreachable. Drive the REAL builder off-tree
	# (instantiate, never add_child — _ready doesn't run; the test_implant_toggle idiom) and read the value
	# that will actually exist at runtime.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var row: Button = inst._make_toggle_row(&"air_dash", "Air Dash", "Air Dash Chip", true)
	assert_eq(row.focus_mode, Control.FOCUS_ALL,
		"a toggle row must take focus — the rows ARE the pad path, and a control a pad can never land on is not a path")
	assert_eq(inst._focus_rows.back(), row,
		"...and register itself in _focus_rows, the paint-order list open()/_reseat_focus seed the pad cursor from")
	row.free()
	inst.free()


func test_the_pad_landing_spot_is_seeded_on_open_and_across_rebuilds() -> void:
	# The other halves of parity are RUNTIME (focus grabbed in open() on a live viewport; every rebuild
	# freeing whichever row holds focus), which a unit test must not run — open() wants the live autoload
	# family and an in-tree Player. So they are pinned by SOURCE, the test_atm_screen_scene idiom, guards and
	# all: find() answers -1 for a needle that has been renamed away and a bad substr yields "", over which a
	# contains() check quietly reads as "absent" — a pin that retires itself in silence is worse than no pin.
	var src := FileAccess.get_file_as_string(SCREEN_SOURCE)
	assert_gt(src.length(), 0, "implants_screen.gd must be readable")
	var open_at := src.find("func open(")
	assert_gt(open_at, -1, "func open( no longer present — the pin is stale")
	assert_eq(src.rfind("func open("), open_at,
		"open must be defined exactly ONCE, or the body sliced below is not the one that runs")
	var open_end := src.find("\nfunc ", open_at + 1)
	assert_gt(open_end, open_at, "open's body must end at the next function — the pin is stale")
	var body := src.substr(open_at, open_end - open_at)
	var shown := body.find("_root.visible = true")
	assert_gt(shown, -1, "_root.visible = true no longer present in open — the pin is stale")
	var grabbed := body.find("_focus_rows[0].grab_focus()")
	assert_gt(grabbed, -1,
		"open must SEED focus on the first toggle row — with no focus owner, ui navigation has nowhere to start and every row is pad-unreachable")
	assert_gt(grabbed, shown,
		"and it must grab AFTER the root is shown — grab_focus on a hidden Control does nothing, so seeding first would leave the pad with no owner anyway")
	# This screen rebuilds its rows on EVERY toggle (a flip always moves the signature) AND on the refused-flip
	# repaint — each rebuild frees the focused row, so _rebuild must hand the pad cursor back or ui navigation
	# dies one press after it started.
	var rebuild_at := src.find("func _rebuild(")
	assert_gt(rebuild_at, -1, "func _rebuild( no longer present — the pin is stale")
	var rebuild_end := src.find("\nfunc ", rebuild_at + 1)
	assert_gt(rebuild_end, rebuild_at, "_rebuild's body must end at the next function — the pin is stale")
	assert_true(src.substr(rebuild_at, rebuild_end - rebuild_at).contains("_reseat_focus("),
		"_rebuild must re-seat pad focus after freeing the rows (index-preserving, the OptionsMenu _revert remembered-tab idiom) — a rebuild that strands a freed focus owner kills ui navigation")
