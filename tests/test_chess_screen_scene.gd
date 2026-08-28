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


const SCREEN_SOURCE := "res://scripts/ui/chess_screen.gd"


func test_every_piece_letter_carries_a_counter_shaded_rim() -> void:
	# ⭐THE BOARD'S HALF-LEGIBILITY, pinned. The two square tints are deliberately mid-tone so a letter of either
	# colour can stand on either shade — but measured off the QA board shot that only half-held: the WHITE letters
	# on a LIGHT square (the back rank) and the BLACK letters on a DARK square came out around 2.5:1 and read as
	# washed out beside their neighbours on the opposite shade. Re-tuning the two tints cannot fix that; it only
	# moves the failure to the other half of the board. The fix is per-PIECE — each letter carries its own thin rim
	# in the OPPOSITE shade — so legibility stops depending on which square a piece happens to be standing on.
	#
	# Driven on a bare instantiate(): _populate_board_grid is called directly (the same call _bind_ui makes) because
	# _ready needs a tree, and _rebuild_board is pure repaint over _game + _cell_labels.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	inst._populate_board_grid(inst.get_node("%BoardGrid") as GridContainer)
	var rim: int = load(SCREEN_SOURCE).PIECE_RIM_PX
	assert_gt(rim, 0, "the rim must be a real width, or every assert below passes vacuously")
	assert_eq(inst._cell_labels.size(), 64, "the stamp built the whole board")
	for lbl: Label in inst._cell_labels:
		assert_eq(lbl.get_theme_constant(&"outline_size"), rim, "every cell is BUILT with the rim width (colour flips per piece)")
	# Paint the opening position, White at the bottom, and check one letter of each colour.
	inst._game = ChessGame.new()
	inst._player_color = ChessGame.WHITE
	inst._rebuild_board()
	var white_cell: Label = inst._cell_labels[7 * 8]  # bottom-left of the display = a1 = White's rook
	var black_cell: Label = inst._cell_labels[0]      # top-left = a8 = Black's rook
	assert_eq(white_cell.text, "R", "orientation sanity: White's a1 rook is bottom-left when the player is White")
	assert_eq(black_cell.text, "r", "orientation sanity: Black's a8 rook is top-left")
	var pairs: Array = [["white", white_cell], ["black", black_cell]]
	for pair: Array in pairs:
		var l: Label = pair[1]
		var fill: Color = l.get_theme_color(&"font_color")
		var edge: Color = l.get_theme_color(&"font_outline_color")
		assert_gt(absf(fill.get_luminance() - edge.get_luminance()), 0.5,
			"the %s letter's rim must be the OPPOSITE shade to its fill — a same-shade rim carries no edge at all" % pair[0])
	inst.free()
