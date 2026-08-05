extends GutTest

## AUTHORED-SCENE wiring contract for the CharacterInspectScreen (the fullscreen hero-showcase takeover),
## mirroring tests/test_heal_screen_scene.gd (the exemplar): the autoload points at the SCENE, every %node
## the script binds exists, no text is authored in the scene (strings belong to PlayerText / l10n, never a
## .tscn), and the screen-specific layout contracts survive editor rearranging. Behaviour (open/close,
## retro-pass borrowing, the FISTS-as-unarmed rule) is covered by playtest + test_character_inspect_weapon.gd.

const SCENE := "res://scenes/ui/character_inspect_screen.tscn"

## Every unique name character_inspect_screen.gd binds in _bind_ui — a rename in the editor breaks the
## bind at boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "VBox", "Title", "Body", "PreviewSlot", "NameLabel", "Summary",
	"StatList", "WeaponLabel", "Footer", "BackButton", "RetroPass"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "CharacterInspectScreen", "")), "*" + SCENE,
		"the CharacterInspectScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries character_inspect_screen.gd")
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

	# Full-screen chrome: root + dim span the screen; the screen ships hidden until open().
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open()")

	# The shared inventory-family panel band: the same 0.12 margin as inventory/loot/shop (PANEL_MARGIN).
	var panel := inst.get_node("%Root/Panel") as PanelContainer
	assert_not_null(panel, "the anchored PanelContainer exists under Root")
	assert_almost_eq(panel.anchor_left, 0.12, 0.001, "the panel keeps the shared 0.12 border band")
	assert_almost_eq(panel.anchor_right, 0.88, 0.001, "the panel keeps the shared 0.12 border band (right)")

	# The hero/info split: the code-instantiated preview's slot takes the lion's share (1.7 vs 1.0) and
	# both columns EXPAND_FILL — the read-only summary can never squeeze the model out.
	var slot := inst.get_node("%PreviewSlot") as Control
	assert_almost_eq(slot.size_flags_stretch_ratio, 1.7, 0.001, "the hero slot gets the lion's share of the body width")
	assert_eq(slot.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the hero slot expands horizontally")
	assert_eq(slot.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the hero slot expands vertically")

	# The stat scroll: horizontal scroll authored OFF, so a long stat line clips (cap_label) instead of
	# widening the info column and squeezing the preview.
	var scroll := (inst.get_node("%StatList") as Control).get_parent() as ScrollContainer
	assert_not_null(scroll, "%StatList lives inside a ScrollContainer")
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"the stat scroll disables horizontal scroll (long lines clip, never widen)")

	# Player-TYPED name: never a translation msgid (Control-text atr), so the opt-out is authored.
	assert_eq((inst.get_node("%NameLabel") as Label).auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED,
		"the name label opts out of automatic Control-text translation (player-typed text)")

	# RETRO PASS: LAST child of Root (it must composite over the whole takeover), purely visual
	# (MOUSE_FILTER_IGNORE), and hidden until a live post-process material is borrowed.
	var root := inst.get_node("%Root") as Control
	var retro := inst.get_node("%RetroPass") as ColorRect
	assert_eq(root.get_child(root.get_child_count() - 1), retro,
		"the retro pass is Root's LAST child so it composites over the whole takeover")
	assert_eq(retro.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the retro pass is purely visual (ignores the mouse)")
	assert_false(retro.visible, "the retro pass ships hidden until _refresh_retro_pass borrows a material")

	inst.free()
