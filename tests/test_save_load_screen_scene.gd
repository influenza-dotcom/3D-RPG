extends GutTest

## The AUTHORED-SCENE wiring contract for the SaveLoadScreen (scenes/ui/save_load_screen.tscn +
## scripts/ui/save_load_screen.gd) — the heal_screen exemplar's four pins applied to this screen. Menus are
## .tscn scenes a designer edits; the script binds chrome by %unique name (_bind_ui) and applies the
## skin-driven look on top. These are prefab WIRING tests (the silent-when-broken seams): the autoload points
## at the SCENE, every %node the script binds exists, no text is authored in the scene (strings belong to
## PlayerText / l10n, never a .tscn), and the screen-specific layout contracts hold. Behaviour (open modes,
## save/load routing, the overwrite confirm) stays in tests/test_save_load_screen.gd + playtest.

const SCENE := "res://scenes/ui/save_load_screen.tscn"

## Every unique name save_load_screen.gd binds in _bind_ui — a rename in the editor breaks the bind at
## boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "VBox", "Title", "List", "Status",
		"Confirm", "ConfirmDim", "ConfirmCard", "ConfirmTitle", "ConfirmRow", "ConfirmButton", "CancelButton"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "SaveLoadScreen", "")), "*" + SCENE,
		"the SaveLoadScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries save_load_screen.gd")
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
	# The screen-specific contracts that survived the conversion into authored structure:
	#  * root + both dims + the confirm overlay span the screen (full-rect anchors);
	#  * the slot panel keeps the shared 0.12 inventory-style margin band;
	#  * the row list's scroll DISABLES horizontal scroll (metadata captions must clip, never widen);
	#  * the status line wraps (make_hint's rule) and the confirm ships hidden (never reopen onto a stale
	#    armed confirm) exactly like the whole screen ships hidden until open().
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for full in ["Root", "Dim", "Confirm", "ConfirmDim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	var panel := inst.get_node("%VBox").get_parent() as PanelContainer
	assert_not_null(panel, "the content VBox sits in the anchored PanelContainer")
	# almost_eq: anchors round-trip through float32 in the .tscn, so 0.12 reads back as 0.11999999731779
	assert_almost_eq(panel.anchor_left, 0.12, 0.0001, "the panel keeps the shared 0.12 margin band (left)")
	assert_almost_eq(panel.anchor_top, 0.12, 0.0001, "the panel keeps the shared 0.12 margin band (top)")
	assert_almost_eq(panel.anchor_right, 0.88, 0.0001, "the panel keeps the shared 0.12 margin band (right)")
	assert_almost_eq(panel.anchor_bottom, 0.88, 0.0001, "the panel keeps the shared 0.12 margin band (bottom)")
	var scroll := inst.get_node("%List").get_parent() as ScrollContainer
	assert_not_null(scroll, "the row list lives in a ScrollContainer")
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"horizontal scroll is disabled — a long metadata caption must clip (cap_label), never scroll sideways")
	assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the scroll takes the panel's leftover height")
	var status := inst.get_node("%Status") as Label
	assert_eq(status.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the failure line wraps within the panel")
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open()")
	assert_false((inst.get_node("%Confirm") as Control).visible, "the overwrite confirm ships un-armed")
	inst.free()
