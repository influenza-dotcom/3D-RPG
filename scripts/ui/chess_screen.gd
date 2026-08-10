extends CanvasLayer
## ChessScreen — the blindfold-chess PLAY overlay for a ChessMatch opponent. Autoload; REAL-TIME — it does NOT
## pause the world (the STATION-SCREEN rule, argued in full in the atm_screen.gd header; this layer is
## PROCESS_MODE_ALWAYS anyway, so its input + AI timer keep working under a dialogue-hosted open's pause).
## ⭐THE LONGEST-EXPOSURE SCREEN OF THE SEVEN: a match runs minutes, not one button press, and the world runs the
## whole time — sit down at a board in a hostile street and you will be shot off it. That is a PLACEMENT rule
## for whoever authors the table, not a bug to patch here. The player types moves (SAN or coordinate) into a LineEdit; the ChessAi replies after a
## beat. By DEFAULT the board is HIDDEN — you play blindfold, tracking the position from the move log alone. The
## board renders ONLY when the player has installed the Board Visualizer chip (Player.has_mechanic(&"chess_visualizer")),
## which is the whole design hook: the chip is the difference between blindfold and sighted play.
## Opened by ChessMatch.start_talk (standalone) or the dialogue "Play Chess" option (open_match).
##
## AUTHORED SCENE: the layout lives in scenes/ui/chess_screen.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and applies the
## skin-driven look (MenuStyle style_* adopters) on top, so a designer rearranges the panel in the editor
## and the skin keeps owning colours/fonts/separations. The 64 board CELLS stay code-built into the
## authored empty %BoardGrid (dynamic content is never authored). NO text is authored in the scene —
## every string is set here from PlayerText (l10n + the text-debt ratchet own strings, never a .tscn).
## tests/test_chess_screen_scene.gd pins the wiring (idiom exemplar: heal_screen, AUTHORING_GUIDE
## "Menus are scenes").

signal opened
signal closed

## Board cell edge (px) — layout fit math, not a designer knob (the stats_screen grid-gap idiom, whose 8px gap now lives authored on its scene's %StatGrid). The 0.12
## panel band is AUTHORED on the scene's Panel (the same border as the shop/loot/install modals — shared menu chrome, so the "peer" claim at layer setup holds
## visually too); at those margins the panel's inner height on a worst-case 792x432 canvas is ~0.76*432 - 2*16 panel margins ≈ 296px;
## minus the title/status/hint rows ≈ 74px that leaves ~222px for the board row, so 8*26 = 208 fits where the
## old 28px cells (8*28) would clip. The blindfold placeholder derives its width from this too, so the two
## left panes can never drift apart again.
const BOARD_CELL := 26
const VISUALIZER_ABILITY := &"chess_visualizer"

# Board cell tints (muted, mid-tone so both white and black piece letters stay legible on either shade).
const LIGHT_SQ := Color(0.62, 0.62, 0.68)
const DARK_SQ := Color(0.40, 0.40, 0.46)
const WHITE_PIECE := Color(0.97, 0.97, 0.95)
const BLACK_PIECE := Color(0.06, 0.06, 0.10)
const LAST_MOVE_TINT := Color(0.85, 0.75, 0.35, 0.55)   # highlights the from/to of the most recent move

var _root: Control
var _title: Label
var _status: Label
var _hint: Label
var _log: RichTextLabel
var _move_input: LineEdit
var _move_btn: Button
var _board_box: VBoxContainer          ## holds the rendered board (visualiser) — hidden without the chip
var _blindfold_box: VBoxContainer      ## the "BLINDFOLD" placeholder shown in the board's place without the chip
var _cell_panels: Array = []           ## 64 board cell Panels in grid child order (row 0 = top of the display)
var _cell_labels: Array = []           ## 64 matching centred Labels

var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _match: Node = null                ## a ChessMatch — Node-typed to avoid a class cycle; its API is called dynamically
var _game: ChessGame = null
var _ai: ChessAi = null
var _san_log: Array = []               ## SAN strings in play order, rendered into the move log
var _player_color: int = ChessGame.WHITE
var _depth: int = 2
var _blunder: float = 0.0
var _wager: int = 0
var _last_from: int = -1               ## last move squares, for the board highlight
var _last_to: int = -1
var _thinking := false                 ## true while the AI's reply timer is pending (input disabled)
var _finished := false                 ## true once the game is decided + stakes applied (guards double payout)
var _player_moved := false             ## true once the PLAYER has made >=1 move — the ONLY thing that arms a forfeit (an AI opening move must not)
var _has_board := false                ## cached at open: does the player have the visualiser chip?
var _think_token := 0                  ## bumped each turn; a pending AI timer only fires if its token still matches
var _error_hint := false               ## true while the hint shows a sticky "illegal move" error (cleared on edit)

func _ready() -> void:
	layer = 121                                  # peer of the other modal overlays (loot / shop / install)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

# ---------------------------------------------------------------------------------------------------
# Open / close
# ---------------------------------------------------------------------------------------------------

## Open the match against `match_node` (a ChessMatch), serving `player`. Refuses to stack over another modal /
## dialogue, bails on an invalid opponent (a stub without the config surface) or no player, and refuses a wagered
## game the player can't cover (with a toast). EVERY refuse path emits `closed` (via _refuse_open) so a
## dialogue-hosted open that suspended the conversation on our `closed` one-shot is never stranded. Sets up a
## fresh game; if the opponent is White, it opens the game.
func open_match(match_node: Node, player: Node) -> void:
	if _is_open or DialogueManager.is_active() or InputManager.any_modal_open(self):
		_refuse_open()
		return
	# Duck-typed guard (match_node is Node-typed for the class cycle): a node WITHOUT the config surface reads as
	# not-a-match and bails, never crashes.
	if not is_instance_valid(match_node) or not match_node.has_method(&"ai_search_depth"):
		_refuse_open()
		return
	_player = player as Player
	if not is_instance_valid(_player):
		_refuse_open()
		return
	_match = match_node
	_depth = int(match_node.ai_search_depth())
	_blunder = float(match_node.ai_blunder())
	_player_color = ChessGame.WHITE if bool(match_node.player_is_white()) else ChessGame.BLACK
	_wager = int(match_node.wager_amount())
	# A wagered match refuses to start unless the player can cover the stake (a friendly game, wager 0, always plays).
	# ⭐DELIBERATELY cash-only — NOT the can_pay/charge payment seam. A wager is staked and then paid back out,
	# so a credit-funded stake would be a pure-profit loop: borrow the stake, win and keep the winnings, lose and
	# the debt survives your death anyway (the account is death-safe in both directions). You bet what you carry.
	if _wager > 0 and _player.money < float(_wager):
		if _player.has_method(&"notify_toast"):
			_player.notify_toast(PlayerText.chess_cant_cover(float(_wager)), GameSettings.hud.money_loss_color)
		_match = null
		_player = null
		# MUST still emit `closed`: a dialogue-hosted match suspends the conversation on the DialogueManager's
		# `closed` one-shot BEFORE calling us. Bailing without it would strand the conversation _suspended forever
		# (box hidden, world paused, no way to advance). Harmless on the standalone path (nothing is listening).
		# Routed through _refuse_open() for uniformity with the other refuse paths above.
		_refuse_open()
		return
	_game = ChessGame.new()
	_ai = ChessAi.new()
	_san_log.clear()
	_last_from = -1
	_last_to = -1
	_finished = false
	_player_moved = false      # an opponent-White table auto-plays move 1 into the log — but the PLAYER hasn't moved, so leaving is still free
	_thinking = false
	_error_hint = false        # a stale illegal-move error must not bleed from a previous match into this one
	_move_input.clear()        # nor should the previously-typed text
	_think_token += 1
	_has_board = _player.has_method(&"has_mechanic") and _player.has_mechanic(VISUALIZER_ABILITY)
	_title.text = MenuStyle.title_text(PlayerText.chess_title(String(match_node.display_opponent_name())))
	_build_board_cells()  # (re)build the 8×8 in the current orientation (player's colour at the bottom)
	_board_box.visible = _has_board
	_blindfold_box.visible = not _has_board
	_is_open = true
	# ONE OPEN CUE, NEVER TWO (the station-screen idiom): a self-serve board answers with its OWN diegetic
	# StationSpeaker chirp, so the generic UI sting is suppressed exactly when that chirp fires and kept when the
	# opponent is a person (no speaker). Past every refuse guard, so a table that couldn't open never beeps.
	_prev_mouse_mode = ModalMenu.grab_mouse(not StationSpeaker.chirp(match_node))
	_root.visible = true
	_refresh()
	opened.emit()
	# If it's not the player's move (the opponent is White and opens), let the AI make the first move.
	if _game.side != _player_color:
		_begin_ai_turn()
	else:
		_move_input.call_deferred(&"grab_focus")

## Guard failed: we never opened, but a dialogue-hosted open (DialogueManager._suspend_for_menu) suspended the
## conversation on our `closed` one-shot BEFORE calling us. Emit `closed` so _resume_from_menu re-shows the box;
## on the standalone path (ChessMatch.start_talk) nothing is listening, so it is harmless. Do NOT touch
## pause/mouse/_is_open here — none of that was mutated on a refused open (the wager path clears _match/_player
## itself before calling this).
func _refuse_open() -> void:
	closed.emit()

func close() -> void:
	if not _is_open:
		return
	# Abandoning a wagered game the player has already MOVED in (but that isn't decided) forfeits the stake, so a
	# player can't bail every losing position for free. Friendly (wager 0), not-yet-moved, or already-settled = free.
	# (Not-yet-moved covers an opponent-White table whose AI has already auto-played move 1 — _player_moved gates on
	# a PLAYER move, not on _san_log, so opening + Esc against a White opponent costs nothing. See forfeit_delta.)
	if not _finished:
		var delta := forfeit_delta(_wager, _player_moved)
		if delta != 0 and is_instance_valid(_player):
			_player.add_money(float(delta))
			if _player.has_method(&"notify_toast"):
				_player.notify_toast(PlayerText.chess_forfeit_loss(float(-delta)), GameSettings.hud.money_loss_color)
	_is_open = false
	_think_token += 1  # invalidate any pending AI reply timer so it can't fire into a closed screen
	_root.visible = false
	ModalMenu.restore_mouse(_prev_mouse_mode)
	_match = null
	_player = null
	_game = null
	_ai = null
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	# Close on Esc. NOT on the Interact/PickUp key — its letter (E) is a legal file, so it must reach the move
	# LineEdit as text rather than dismiss the board mid-game.
	if _is_open and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# Game flow
# ---------------------------------------------------------------------------------------------------

## The player submitted a move (Enter in the field or the Move button). Parse it against the legal moves; an
## illegal / unparseable entry shows a hint and is NOT consumed. A legal move is applied + logged, then — if the
## game isn't over — the opponent replies after a short "thinking" beat.
func _submit_move() -> void:
	if not _is_open or _finished or _thinking or _game == null:
		return
	if _game.side != _player_color:
		return
	var text := _move_input.text.strip_edges()
	if text.is_empty():
		return
	var m := _game.parse_move(text)
	if m.is_empty():
		_error_hint = true
		_hint.text = PlayerText.chess_illegal_move(text)
		_hint.add_theme_color_override(&"font_color", MenuStyle.danger())
		return
	_apply_and_log(m)
	_player_moved = true       # arm the forfeit — from here on, abandoning a wagered game costs the stake
	_move_input.clear()
	_refresh()
	if _game.is_game_over():
		_end_game()
		return
	_begin_ai_turn()

## Kick off the opponent's turn: disable input, show "thinking", and fire the AI after a short beat so the player
## sees their own move land first. The timer is token-guarded so a close (or a new turn) cancels a stale reply.
func _begin_ai_turn() -> void:
	_thinking = true
	_think_token += 1
	var tok := _think_token
	_refresh()
	# process_always so the timer survives any pause around us (a dialogue-hosted match); bound method (not a lambda) so a freed-capture
	# can't fire (the lambda-guard-is-useless gotcha). ~0.5s reads as the opponent considering the position.
	get_tree().create_timer(0.5, true).timeout.connect(_ai_move.bind(tok))

## The opponent picks + plays its move (unless the turn was cancelled by a close / restart). Then checks for game
## end, or hands the turn back to the player.
func _ai_move(tok: int) -> void:
	if not _is_open or _game == null or tok != _think_token:
		return
	var m := _ai.choose_move(_game, _depth, _blunder)
	_thinking = false
	if m.is_empty():
		_end_game()  # no legal reply -> the position is already terminal
		return
	_apply_and_log(m)
	_refresh()
	if _game.is_game_over():
		_end_game()
		return
	_move_input.call_deferred(&"grab_focus")

## Record a move's SAN (computed BEFORE it's played, while the position still has the context SAN needs) then play it.
func _apply_and_log(m: Dictionary) -> void:
	_san_log.append(_game.move_to_san(m))
	_last_from = int(m.from)
	_last_to = int(m.to)
	_game.make_move(m)

## The game is decided: settle the wager once, freeze input, and let the status line report the result.
func _end_game() -> void:
	if _finished:
		return
	_finished = true
	_thinking = false
	# Settle the decided game ONCE (guarded by _finished above): win +wager, loss -wager, draw 0. The pure
	# decided_delta routes both directions so the payout can't drift from _status_text's win/lose classification.
	var res := _game.status()
	var delta := decided_delta(res, _player_color, _wager)
	if delta != 0 and is_instance_valid(_player):
		_player.add_money(float(delta))
		if _player.has_method(&"notify_toast"):
			# Wager toasts announce MONEY outcomes — they wear the HUD's money-delta pair (not gold/danger)
			# so the toast stack speaks one gain/loss colour language across screens.
			if delta > 0:
				_player.notify_toast(PlayerText.chess_win(float(delta)), GameSettings.hud.money_gain_color)
			else:
				_player.notify_toast(PlayerText.chess_loss(float(-delta)), GameSettings.hud.money_loss_color)
	_refresh()

# --- Wager settlement (pure; unit-tested in tests/test_chess_wager.gd) ---
## +1 player win / -1 player loss / 0 draw, from a DECIDED game's result and the player's colour.
static func player_result_sign(result: int, player_color: int) -> int:
	if (result == ChessGame.Result.WHITE_WINS and player_color == ChessGame.WHITE) \
			or (result == ChessGame.Result.BLACK_WINS and player_color == ChessGame.BLACK):
		return 1
	if (result == ChessGame.Result.WHITE_WINS and player_color == ChessGame.BLACK) \
			or (result == ChessGame.Result.BLACK_WINS and player_color == ChessGame.WHITE):
		return -1
	return 0

## Signed money delta when a DECIDED game settles (called ONCE from _end_game): win +wager, loss -wager, draw 0.
static func decided_delta(result: int, player_color: int, wager: int) -> int:
	if wager <= 0:
		return 0
	return player_result_sign(result, player_color) * wager

## Signed money delta when a game is ABANDONED before it is decided. Forfeit (-wager) ONLY if the player has
## actually moved; leaving before your first move — incl. an opponent-White table you never replied to — is free.
static func forfeit_delta(wager: int, player_moved: bool) -> int:
	if wager <= 0 or not player_moved:
		return 0
	return -wager

# ---------------------------------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------------------------------

## Repaint everything from game state: the status line, the move log, the board (if shown), and the input's
## enabled state. Called after every move + on open.
func _refresh() -> void:
	if _game == null:
		return
	_status.text = _status_text()
	_status.add_theme_color_override(&"font_color", MenuStyle.accent() if not _finished else MenuStyle.gold())
	_rebuild_log()
	if _has_board:
		_rebuild_board()
	var my_turn := not _finished and not _thinking and _game.side == _player_color
	_move_input.editable = my_turn
	_move_btn.disabled = not my_turn
	if not _error_hint:
		_hint.text = _default_hint()
		_hint.add_theme_color_override(&"font_color", MenuStyle.dim_color())

func _status_text() -> String:
	if _finished:
		match _game.status():
			ChessGame.Result.WHITE_WINS:
				return PlayerText.chess_checkmate(_player_color == ChessGame.WHITE)
			ChessGame.Result.BLACK_WINS:
				return PlayerText.chess_checkmate(_player_color == ChessGame.BLACK)
			ChessGame.Result.STALEMATE:
				return PlayerText.CHESS_STALEMATE
			ChessGame.Result.DRAW_50:
				return PlayerText.CHESS_DRAW_FIFTY_MOVE
			ChessGame.Result.DRAW_MATERIAL:
				return PlayerText.CHESS_DRAW_INSUFFICIENT
			_:
				return PlayerText.CHESS_GAME_OVER
	if _thinking:
		return PlayerText.chess_thinking(_opponent_name())
	var check := _game.is_in_check(_player_color)
	if _game.side == _player_color:
		return PlayerText.CHESS_YOUR_MOVE + (PlayerText.CHESS_CHECK_SUFFIX if check else "")
	return PlayerText.chess_to_move(_opponent_name())

func _opponent_name() -> String:
	if is_instance_valid(_match) and _match.has_method(&"display_opponent_name"):
		return String(_match.display_opponent_name())
	return PlayerText.DEFAULT_CHESS_OPPONENT

## Render the move log as numbered pairs ("1. e4 e5"), auto-scrolled to the latest move.
func _rebuild_log() -> void:
	var lines: Array = []
	var i := 0
	var move_num := 1
	while i < _san_log.size():
		var line := "%d. %s" % [move_num, _san_log[i]]
		if i + 1 < _san_log.size():
			line += "  %s" % _san_log[i + 1]
		lines.append(line)
		i += 2
		move_num += 1
	# The "\n" here is the log's LINE SEPARATOR, not prose — the body is engine SAN + player-TYPED moves, which
	# is why this label opts out of auto-translate (see auto_translate_mode below). Composing it in a local keeps
	# a non-translatable separator out of the `.text =` idiom the PlayerText ratchet scans, WITHOUT loosening that
	# scanner (a lookahead that ignored `"…".method()` would also stop catching a real `.text = "Score: {n}".format(…)`).
	var body := "\n".join(lines) if not lines.is_empty() else PlayerText.CHESS_NO_MOVES
	_log.text = body
	# Follow the tail so the newest move is always visible.
	_log.scroll_to_line.call_deferred(maxi(0, _log.get_line_count() - 1))

## Repaint the 8×8 board cells from the current position, in the player's orientation (their colour at the bottom).
func _rebuild_board() -> void:
	for row in 8:
		for col in 8:
			var idx := row * 8 + col
			var file: int
			var rank: int
			if _player_color == ChessGame.WHITE:
				file = col
				rank = 7 - row          # white at the bottom: top display row is rank 8
			else:
				file = 7 - col
				rank = row              # black at the bottom: flipped both ways
			var s := ChessGame.sq(file, rank)
			var piece: int = _game.board[s]
			var label: Label = _cell_labels[idx]
			label.text = ChessGame.piece_letter_cased(piece)
			label.add_theme_color_override(&"font_color", WHITE_PIECE if ChessGame.color_of(piece) == ChessGame.WHITE else BLACK_PIECE)
			var base: Color = LIGHT_SQ if ((file + rank) % 2 == 1) else DARK_SQ
			if s == _last_from or s == _last_to:
				base = base.lerp(LAST_MOVE_TINT, LAST_MOVE_TINT.a)  # tint the last move's squares
			(_cell_panels[idx] as Panel).add_theme_stylebox_override(&"panel", _cell_style(base))

func _default_hint() -> String:
	if _finished:
		return ""  # game over needs no "Esc leaves" coaching — Esc closes every screen in the game
	if _has_board:
		return PlayerText.CHESS_INPUT_HINT
	return PlayerText.CHESS_BLINDFOLD_HINT

# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/chess_screen.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. The scene owns
## structure only (anchors, the 0.12 panel band, size flags, the main-row/input-row literal separations,
## atr opt-outs, the hint's clip); skin-derived values (fonts, colours, content_separation) and every
## string (PlayerText) are applied HERE. The 64 board cells stay code-built (_populate_board_grid) into
## the authored empty %BoardGrid — dynamic content is never authored. The same contracts the old
## procedural build carried, now split across scene + adopters:
##  * Main row (authored): the board (or blindfold placeholder) left, move log + input right; the row is
##    the panel's ONLY vertical expander. The move log scrolls itself (RichTextLabel own scroll +
##    scroll_following, authored) — no wrapping ScrollContainer, which would fight the RTL's internal
##    scroll and never reach the latest move (this screen's carve-out from the tall-content-scrolls rule).
##  * atr opt-outs (authored on %Log / %MoveInput / %Hint): the log + input carry player-TYPED moves and
##    engine SAN, and the hint's illegal-move error ECHOES the typed entry — user data must never be
##    looked up as a translation msgid. The LineEdit's engine right-click menu is also off (untranslatable
##    English, see NameEntryDialog).
func _bind_ui() -> void:
	_root = %Root
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)
	(%VBox as VBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.content_separation)

	_title = %Title
	MenuStyle.style_title(_title)
	_title.text = MenuStyle.title_text(PlayerText.CHESS_SCREEN_TITLE)  # open_match re-titles per opponent

	_status = %Status
	_status.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	_status.add_theme_color_override(&"font_color", MenuStyle.accent())

	_board_box = %BoardBox
	_populate_board_grid(%BoardGrid)

	_blindfold_box = %BlindfoldBox
	# Same width as the board pane, so blindfold/sighted swaps don't shift the log column. Derived from
	# BOARD_CELL (the fit math above), so it stays code-applied — never an authored width pin.
	_blindfold_box.custom_minimum_size = Vector2(BOARD_CELL * 8, 0)
	# The placeholder names the blindfold conceit and points at the Visualizer chip, so the UI itself
	# teaches the upgrade hook.
	var eye: Label = %BlindfoldBadge
	eye.text = PlayerText.CHESS_BLINDFOLD_BADGE
	eye.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	eye.add_theme_color_override(&"font_color", MenuStyle.dim_color())
	var sub: Label = %BlindfoldHint
	MenuStyle.style_hint(sub)
	sub.text = PlayerText.CHESS_NO_BOARD_HINT

	var log_head: Label = %LogHeading
	log_head.text = PlayerText.CHESS_MOVES_HEADING
	log_head.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)

	_log = %Log

	_move_input = %MoveInput
	_move_input.placeholder_text = PlayerText.CHESS_MOVE_PLACEHOLDER
	_move_input.text_submitted.connect(func(_t: String) -> void: _submit_move())
	_move_input.text_changed.connect(func(_t: String) -> void: _clear_error_hint())
	_move_btn = %MoveButton
	_move_btn.text = PlayerText.CHESS_MOVE_BUTTON
	_move_btn.pressed.connect(_submit_move)

	_hint = %Hint
	# ONE line, clipped — never autowrap (clip + ellipsis are AUTHORED on the scene node; cap_label here is
	# the belt-and-braces re-assert): every string this label holds is single-line by design (input /
	# blindfold / exit hints, the illegal-move error), and the main row above is the panel's only vertical
	# expander, so a hint that wrapped to a 2nd line (an illegal-move echo of a long typed entry) stole that
	# height and bounced the board + move log + input row up, then back down when the error cleared.
	# chess_illegal_move truncates its echo, so the ellipsis here is only the backstop.
	MenuStyle.cap_label(_hint)
	_hint.add_theme_font_size_override("font_size", MenuStyle.skin.hint_size)
	_hint.add_theme_color_override(&"font_color", MenuStyle.dim_color())

## Fill the authored empty %BoardGrid with the 8×8 of cell Panels (each with a centred Label). DYNAMIC
## content — 64 identical stamped cells stay code-built, the scene authors only the GridContainer. Cells
## are re-oriented + repainted per game in _build_board_cells / _rebuild_board; here we only create nodes.
func _populate_board_grid(grid: GridContainer) -> void:
	for i in 64:
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(BOARD_CELL, BOARD_CELL)
		var lbl := Label.new()
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 16)  # piece letters sized to the BOARD_CELL square
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(lbl)
		grid.add_child(cell)
		_cell_panels.append(cell)
		_cell_labels.append(lbl)

## (Re)orient + clear the board cells for a new game. The grid nodes already exist; here we just repaint them to
## the empty look — the first _rebuild_board fills in pieces. Split out so open_match can re-run it per match.
func _build_board_cells() -> void:
	for row in 8:
		for col in 8:
			var idx := row * 8 + col
			var file := col if _player_color == ChessGame.WHITE else 7 - col
			var rank := (7 - row) if _player_color == ChessGame.WHITE else row
			var base: Color = LIGHT_SQ if ((file + rank) % 2 == 1) else DARK_SQ
			(_cell_panels[idx] as Panel).add_theme_stylebox_override(&"panel", _cell_style(base))
			(_cell_labels[idx] as Label).text = ""

func _cell_style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	return sb

## Clear a sticky illegal-move error the moment the player edits the field again (so the red hint doesn't linger).
func _clear_error_hint() -> void:
	if not _error_hint:
		return
	_error_hint = false
	_hint.text = _default_hint()
	_hint.add_theme_color_override(&"font_color", MenuStyle.dim_color())
