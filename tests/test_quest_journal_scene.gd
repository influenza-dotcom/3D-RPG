extends GutTest

## AUTHORED-SCENE wiring contract for QuestJournal (scenes/ui/quest_journal.tscn +
## scripts/ui/quest_journal.gd), mirroring the heal_screen exemplar (test_heal_screen_scene.gd).
## Menus are .tscn scenes a designer/artist edits; the script binds chrome by %unique name and applies the
## skin-driven look on top. These are prefab WIRING contract tests (the silent-when-broken seams): the
## autoload points at the SCENE, every %node the script binds exists, no text is authored in the scene
## (strings belong to PlayerText / l10n, never a .tscn), and the player-menu-group layout contracts hold —
## incl. the PlayerMenus seam: the tab strip is CODE-BUILT into %TabSlot (its four-Button structure is
## test_player_menus.gd's contract), so the scene must ship the slot EMPTY with zero authored Buttons.
## Behaviour (open/close/live quest refresh) is in-tree -> playtest + test_quest_journal.gd if present.

const SCENE := "res://scenes/ui/quest_journal.tscn"

## Every unique name quest_journal.gd binds in _bind_ui — a rename in the editor breaks the bind at
## boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "VBox", "TabSlot", "Scroll", "QuestList"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "QuestJournal", "")), "*" + SCENE,
		"the QuestJournal autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries quest_journal.gd")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (the script binds it in _bind_ui)" % n)
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in PlayerText (the text-debt ratchet + l10n own them) — a caption typed into the .tscn
	# would bypass both and ship unauthored. This screen's scene holds only CONTAINERS (every Label is a
	# dynamic per-quest block line, and the tab Buttons are PlayerMenus-built), so the pin here is stronger
	# than the exemplar's: ZERO authored text-bearing nodes at all, not just empty .text.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var text_nodes := 0
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button:
			text_nodes += 1
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text (the script sets it from PlayerText)" % n.name)
	assert_eq(text_nodes, 0, "the scene authors no Labels/Buttons — quest blocks and the tab strip are code-built")
	inst.free()


func test_layout_contracts_for_the_player_menu_group() -> void:
	# The player-menu-group discipline survives the scene conversion:
	#  * root + dim span the screen and the screen ships hidden;
	#  * the panel keeps the shared PANEL_MARGIN 0.12 anchor band (the loot/shop chrome — a drifted band
	#    would off-centre this tab against its siblings at 792x444);
	#  * %TabSlot ships EMPTY — the strip is built by PlayerMenus.build_tab_strip at boot, and its
	#    4-direct-Button structure is a cross-screen contract (test_player_menus.gd); an authored Button
	#    here would silently double the strip;
	#  * the quest scroll EXPAND_FILLs both ways with horizontal scroll OFF (a long authored quest title
	#    must WRAP — _make_quest_block's AUTOWRAP_WORD_SMART — instead of widening the panel past its band);
	#  * %QuestList fills the scroll width and keeps its authored 14px gap (the quest-block rhythm).
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open()")
	var panel := (inst.get_node("%VBox") as Control).get_parent() as Control
	var margin: float = load("res://scripts/ui/quest_journal.gd").PANEL_MARGIN
	assert_almost_eq(panel.anchor_left, margin, 0.001, "panel keeps the shared PANEL_MARGIN band (left)")
	assert_almost_eq(panel.anchor_top, margin, 0.001, "panel keeps the shared PANEL_MARGIN band (top)")
	assert_almost_eq(panel.anchor_right, 1.0 - margin, 0.001, "panel keeps the shared PANEL_MARGIN band (right)")
	assert_almost_eq(panel.anchor_bottom, 1.0 - margin, 0.001, "panel keeps the shared PANEL_MARGIN band (bottom)")
	assert_eq((inst.get_node("%TabSlot") as Node).get_child_count(), 0,
		"%TabSlot ships empty — PlayerMenus builds the 4-button strip into it at boot (never author tabs)")
	var scroll := inst.get_node("%Scroll") as ScrollContainer
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"horizontal scroll is OFF so runaway quest titles wrap instead of widening the panel")
	assert_eq(scroll.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the quest scroll fills the panel width")
	assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the quest scroll takes the body height")
	var list := inst.get_node("%QuestList") as VBoxContainer
	assert_eq(list.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the list fills the scroll width")
	assert_eq(list.get_theme_constant("separation"), 14, "the authored 14px quest-block gap survives")
	inst.free()
