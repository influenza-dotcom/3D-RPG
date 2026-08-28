extends GutTest

## AUTHORED-SCENE wiring contract for MapScreen (scenes/ui/map_screen.tscn + scripts/ui/map_screen.gd),
## mirroring test_implants_screen_scene.gd (the tab family's exemplar). Menus are .tscn scenes a designer
## edits; the script binds chrome by %unique name and applies the skin-driven look on top. These are prefab
## WIRING contract tests — the silent-when-broken seams: the autoload points at the SCENE, every %node the
## script binds exists, no text is authored in the scene (strings belong to PlayerText / l10n, never a .tscn),
## and the player-menu-group layout contracts hold, incl. the PlayerMenus seam (the tab strip is CODE-BUILT
## into %TabSlot, so the scene must ship the slot EMPTY).
##
## ⭐THE ONE CONTRACT UNIQUE TO THIS SCREEN: %Map is a SECOND INSTANCE of the HUD minimap widget, and the four
## "Instance view" exports authored on it ARE the difference between the map tab and the corner box. Every one
## of them is silent when wrong — a missing NORTH_UP just draws a spinning map, a missing
## `zoom_key_enabled = false` quietly re-zooms the HUD box from this screen — so they are pinned off the
## authored scene here rather than trusted to an inspector checkbox. Runtime behaviour (the zoom round-trip,
## the boot-time span push) is tests/test_map_screen.gd.

const SCENE := "res://scenes/ui/map_screen.tscn"
const SCREEN_SOURCE := "res://scripts/ui/map_screen.gd"
const MINIMAP_SCRIPT := "res://scripts/ui/minimap.gd"

## Every unique name the screen depends on: the ones map_screen.gd binds in _bind_ui (Root/Dim/VBox/TabSlot/
## Map/Empty/Footer/Hint/ZoomValue/ZoomOut/ZoomIn — a rename in the editor breaks the bind at boot) plus
## %MapHost, the layout host whose EXPAND_FILL is what gives the plan the panel body, and the widget's own two
## art slots %MapUnder / %MapOver, which minimap.gd resolves by NAME (the slot name is the contract).
const BOUND := ["Root", "Dim", "VBox", "TabSlot", "MapHost", "Map", "MapUnder", "MapOver", "Empty",
		"Footer", "Hint", "ZoomValue", "ZoomOut", "ZoomIn"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "MapScreen", "")), "*" + SCENE,
		"the MapScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries map_screen.gd")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (the script binds it in _bind_ui)" % n)
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in PlayerText (the text-debt ratchet + l10n own them) — a caption typed into the .tscn would
	# bypass both and ship unauthored. This scene DOES author the footer's Labels and Buttons as layout (they
	# are fixed chrome, not runtime rows), so unlike the journal/implants pin the count here is non-zero — what
	# must hold is that every one of them ships with EMPTY text and gets its words from _bind_ui.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var text_nodes := 0
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button:
			text_nodes += 1
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text (the script sets it from PlayerText)" % n.name)
	assert_eq(text_nodes, 5,
		"the authored text-bearing nodes are exactly the five fixed chrome ones — %Empty, %Hint, %ZoomValue, %ZoomOut, %ZoomIn; a sixth is a caption that escaped PlayerText, and a missing one is a bind that will null-deref at boot")
	inst.free()


func test_layout_contracts_for_the_player_menu_group() -> void:
	# The player-menu-group discipline survives on the newest sibling:
	#  * root + dim span the screen and the screen ships hidden;
	#  * the panel keeps the shared PANEL_MARGIN 0.12 anchor band (a drifted band would off-centre this tab
	#    against its siblings at 792x444);
	#  * %TabSlot ships EMPTY — the strip is built by PlayerMenus.build_tab_strip at boot, and its
	#    one-Button-per-tab structure is a cross-screen contract (test_player_menus.gd);
	#  * the map host EXPAND_FILLs both ways and floors its height, so the plan gets the panel body rather
	#    than collapsing to nothing between the tab strip and the footer.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open()")
	assert_eq((inst.get_node("%Root") as Control).mouse_filter, Control.MOUSE_FILTER_STOP,
		"%Root must EAT the mouse: it is what stops a click falling through to gameplay behind. (Map input itself — left click / right click / drag / wheel — lives on the code-built MapInput overlay inside %MapHost; events over the plan never reliably bubbled to Root, which is why the old Root-wired gestures were dead.)")
	var panel := (inst.get_node("%VBox") as Control).get_parent() as Control
	var margin: float = load(SCREEN_SOURCE).PANEL_MARGIN
	assert_almost_eq(panel.anchor_left, margin, 0.001, "panel keeps the shared PANEL_MARGIN band (left)")
	assert_almost_eq(panel.anchor_top, margin, 0.001, "panel keeps the shared PANEL_MARGIN band (top)")
	assert_almost_eq(panel.anchor_right, 1.0 - margin, 0.001, "panel keeps the shared PANEL_MARGIN band (right)")
	assert_almost_eq(panel.anchor_bottom, 1.0 - margin, 0.001, "panel keeps the shared PANEL_MARGIN band (bottom)")
	assert_eq((inst.get_node("%TabSlot") as Node).get_child_count(), 0,
		"%TabSlot ships empty — PlayerMenus builds the tab strip into it at boot (never author tabs)")
	var host := inst.get_node("%MapHost") as Control
	assert_eq(host.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the map host fills the panel width")
	assert_eq(host.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the map host takes the panel body height")
	assert_gt(host.custom_minimum_size.y, 0.0,
		"...with a height FLOOR, or a tall footer/tab strip on a small canvas can squeeze the plan to nothing")
	inst.free()


## ⭐THE FOUR EXPORTS THAT ARE THE WHOLE FEATURE. %Map is minimap.gd — the same widget as the HUD corner box —
## and these authored values are the only thing that makes it a map tab instead of a magnified minimap. Each
## is silent when wrong, so each is pinned here off the authored scene.
func test_the_map_widget_is_the_minimap_authored_for_a_page_sized_read() -> void:
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	# Deliberately Variant, not `as Control`: every assertion below reads a property minimap.gd DECLARES and
	# Control does not, so a typed local would make each one an unsafe-property-access the analyzer has to
	# defer anyway. The script itself is read the same way (test_minimap.gd's load-by-path cache guard).
	var minimap_script: Variant = load(MINIMAP_SCRIPT)
	var map: Variant = inst.get_node("%Map")
	assert_eq(map.get_script(), minimap_script,
		"%Map IS the HUD minimap widget — the map tab must never grow a second draw path")
	assert_eq(map.heading, minimap_script.Heading.NORTH_UP,
		"the map tab is NORTH-UP: a page you read wants a fixed bearing (the corner box stays heading-up)")
	assert_false(map.zoom_key_enabled,
		"the 'Cycle Minimap Zoom' key belongs to the HUD box alone — a second live widget polling it would move two maps on one press")
	assert_gt(map.zoom_override, 0.0,
		"a zero zoom_override means 'follow Settings.minimap_zoom', which would make scrolling this map do nothing while the HUD row drove it; map_screen.gd re-pushes Settings.map_zoom over this on every open, but the authored value must already be an override")
	assert_almost_eq(map.bake_delay, 0.0, 0.0001,
		"no settle delay: the level has been running for minutes by the time a player opens the map, and a delay here just shows a blank panel for the first frames of every FIRST open")
	assert_eq(map.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the widget must not eat the wheel — minimap.gd forces this in _ready anyway, and %Root is the handler")
	# The span is the ONE view knob the scene cannot author (it is a tuning number on HudSettings.tres, and a
	# .tscn can only hold a literal) — _bind_ui pushes it. Pinned as SOURCE so the push cannot quietly vanish.
	var src := FileAccess.get_file_as_string(SCREEN_SOURCE)
	assert_true(src.contains("world_span_override = GameSettings.hud.map_world_span"),
		"_bind_ui must push the authored span onto the widget, or the map tab draws the corner box's 40 m room")
	inst.free()


## The art sandwich comes along with the widget: %MapUnder renders BEHIND the whole procedural plan and
## %MapOver in front of it, exactly as on the HUD scene, so an artist has the same two slots on both surfaces.
## show_behind_parent on the under-slot is forced by minimap.gd's _ready (the slot NAME is the contract), but
## authoring it correctly here is what makes the editor preview honest.
func test_the_art_sandwich_slots_ride_along() -> void:
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var under := inst.get_node("%MapUnder") as CanvasItem
	var over := inst.get_node("%MapOver") as CanvasItem
	assert_true(under.show_behind_parent, "%MapUnder renders behind the plan (a backdrop slot)")
	assert_false(over.show_behind_parent, "%MapOver renders in front of it (a bezel/glass/vignette slot)")
	assert_eq(under.get_parent(), inst.get_node("%Map"), "both slots are children of the widget, not the host")
	assert_eq(over.get_parent(), inst.get_node("%Map"), "...so the widget's own _draw is the filling")
	inst.free()
