extends GutTest

## AUTHORED-SCENE wiring contract for the name-entry modal (scenes/ui/name_entry_dialog.tscn +
## name_entry_dialog.gd), mirroring the heal-screen exemplar (tests/test_heal_screen_scene.gd). These pin
## the silent-when-broken seams: the autoload points at the SCENE, every %node the script binds exists,
## and no text is authored in the scene (strings belong to PlayerText / l10n, never a .tscn). Behaviour
## (open/confirm/mouse-mode) is in-tree -> playtest.

const SCENE := "res://scenes/ui/name_entry_dialog.tscn"

## Every unique name name_entry_dialog.gd binds in _bind_ui — a rename in the editor breaks the bind at
## boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "Card", "Title", "Line", "Buttons", "ConfirmButton", "CancelButton"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "NameEntryDialog", "")), "*" + SCENE,
		"the NameEntryDialog autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries name_entry_dialog.gd")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (the script binds it in _bind_ui)" % n)
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in PlayerText (the text-debt ratchet + l10n own them) — a caption typed into the .tscn
	# would bypass both and ship unauthored. The scene must hold only structure. The LineEdit's text AND
	# placeholder are covered too: text is player-typed at runtime, placeholder comes from PlayerText.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button or n is LineEdit:
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text (the script sets it from PlayerText)" % n.name)
		if n is LineEdit:
			assert_eq(String(n.get(&"placeholder_text")), "", "%s ships with an empty placeholder" % n.name)
	inst.free()


func test_bound_chrome_keeps_the_layout_contracts() -> void:
	# The fixed-width-card + typing-focus discipline survives the scene conversion: buttons split the card
	# EXPAND_FILL, clip their captions, and take NO focus (typing must never leave the field); the LineEdit
	# opts out of auto-translate (player-TYPED text is not a msgid) and of the untranslatable engine
	# right-click menu; the dim and root cover the screen and Root eats clicks.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for b in ["ConfirmButton", "CancelButton"]:
		var btn := inst.get_node("%" + b) as Button
		assert_eq(btn.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s splits the fixed card width" % b)
		assert_true(btn.clip_text, "%s clips its caption instead of growing the card" % b)
		assert_eq(btn.focus_mode, Control.FOCUS_NONE, "%s takes no focus (keyboard stays in the field)" % b)
	var line := inst.get_node("%Line") as LineEdit
	assert_eq(line.auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED,
		"the field never treats player-typed text as a translation msgid")
	assert_false(line.context_menu_enabled, "the engine's untranslatable right-click menu stays off")
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_eq((inst.get_node("%Root") as Control).mouse_filter, Control.MOUSE_FILTER_STOP,
		"Root eats clicks so nothing falls through to gameplay behind the modal")
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open()")
	inst.free()
