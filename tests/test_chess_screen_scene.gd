extends GutTest

## Prefab WIRING contract for the AUTHORED chess screen (scenes/ui/chess_screen.tscn + chess_screen.gd) —
## the heal_screen scene-idiom tests, applied to the blindfold-chess modal (AUTHORING_GUIDE "Menus are
## scenes"). Pins the silent-when-broken seams: the autoload points at the SCENE, every %node _bind_ui
## binds exists, no text is authored in the scene (strings belong to PlayerText / l10n, never a .tscn),
## and the screen-specific layout contracts (single-line hint, self-scrolling move log, atr opt-outs on
## the player-typed surfaces, the 0.12 panel band). Behaviour (turn loop / wager / the real-time posture —
## a match runs while the world keeps moving) is in-tree -> playtest + tests/test_chess_wager.gd.

const SCENE := "res://scenes/ui/chess_screen.tscn"

## Every unique name chess_screen.gd binds in _bind_ui — a rename in the editor breaks the bind at boot,
## so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "VBox", "Title", "Status", "BoardBox", "BoardGrid", "BlindfoldBox",
	"BlindfoldBadge", "BlindfoldHint", "LogHeading", "Log", "MoveInput", "MoveButton", "Hint"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "ChessScreen", "")), "*" + SCENE,
		"the ChessScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries chess_screen.gd")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (the script binds it in _bind_ui)" % n)
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in PlayerText (the text-debt ratchet + l10n own them) — a caption typed into the .tscn
	# would bypass both and ship unauthored. The scene must hold only structure. LineEdit placeholder and
	# RichTextLabel body count too — both are player-visible paint surfaces the script owns.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button or n is RichTextLabel:
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text (the script sets it from PlayerText)" % n.name)
		if n is LineEdit:
			assert_eq((n as LineEdit).placeholder_text, "", "%s ships with an empty placeholder (script sets it)" % n.name)
	inst.free()


func test_bound_chrome_keeps_the_layout_contracts() -> void:
	# The chess screen's specific disciplines survive the scene conversion.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	# Full-screen chrome: root + dim cover the screen; the panel keeps the shared 0.12 modal band.
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open_match")
	var panel := inst.get_node("%VBox").get_parent() as PanelContainer
	assert_not_null(panel, "the content VBox sits in the band PanelContainer")
	assert_almost_eq(panel.anchor_left, 0.12, 0.001, "the panel keeps the shared 0.12 modal band")
	assert_almost_eq(panel.anchor_right, 0.88, 0.001, "the panel keeps the shared 0.12 modal band")
	# The board grid is the authored EMPTY 8-column stamp target — the 64 cells are code-built at boot.
	var grid := inst.get_node("%BoardGrid") as GridContainer
	assert_eq(grid.columns, 8, "the board grid is 8 columns")
	assert_eq(grid.get_child_count(), 0, "the grid ships EMPTY (cells are dynamic, stamped in _populate_board_grid)")
	# The move log scrolls ITSELF — no wrapping ScrollContainer (it would fight the RTL's internal scroll
	# and never reach the latest move); scroll_following keeps the newest move visible.
	var log := inst.get_node("%Log") as RichTextLabel
	assert_true(log.scroll_active and log.scroll_following, "the move log self-scrolls and follows the tail")
	assert_false(log.bbcode_enabled, "the log is plain text (engine SAN + typed moves, never markup)")
	assert_eq(log.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the log is the right pane's vertical expander")
	# atr opt-outs: the log/input/hint carry player-TYPED text — never translation-msgid lookups.
	for atr in ["Log", "MoveInput", "Hint"]:
		assert_eq((inst.get_node("%" + atr) as Node).auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED,
			"%s opts out of auto-translate (player-typed text is data, not a msgid)" % atr)
	assert_false((inst.get_node("%MoveInput") as LineEdit).context_menu_enabled,
		"the move field's engine context menu stays off (untranslatable English)")
	# The hint is ONE line BY CONTRACT (height constancy): clipped + ellipsis, never autowrap — a wrapped
	# illegal-move echo would steal height from the main row and bounce the board/log/input.
	var hint := inst.get_node("%Hint") as Label
	assert_true(hint.clip_text, "the hint clips to one line (height constancy)")
	assert_eq(hint.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "the hint ellipsizes, never wraps")
	assert_eq(hint.autowrap_mode, TextServer.AUTOWRAP_OFF, "the hint never autowraps (single-line contract)")
	# Buttons: the Move button takes no focus so Enter stays with the LineEdit's submit.
	assert_eq((inst.get_node("%MoveButton") as Button).focus_mode, Control.FOCUS_NONE,
		"the Move button takes no focus (Enter belongs to the move field)")
	inst.free()
