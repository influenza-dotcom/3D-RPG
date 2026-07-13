class_name ChessGame
extends RefCounted

## A self-contained chess RULES engine — PURE logic with no scene / tree / UI / autoload dependencies, so it
## unit-tests off-tree under GUT and the AI (scripts/chess/chess_ai.gd) can search on a clone() with make/undo.
## The blindfold-chess minigame drives it: the player types a move (SAN or coordinate), we parse + apply it, the
## opponent AI replies, and ChessScreen renders the result — either as pure text (blindfold) or, with the Board
## Visualizer chip installed, as a rendered board. Nothing here knows about any of that; it only knows chess.
##
## BOARD: a 64-int Array indexed rank*8 + file, so a1 = 0, h1 = 7, a8 = 56, h8 = 63 (file a..h = 0..7, rank 1..8
## = 0..7). A piece is an int: 0 empty, else piece TYPE (1..6, see the enum) times COLOUR (WHITE +1 / BLACK -1) —
## so a white knight is +2, a black queen is -5. This sign-magnitude encoding makes colour/type reads branch-free.
##
## MOVES are lightweight Dictionaries {from, to, promo, flag} (see _mk). make_move() mutates the board + state and
## pushes an undo record; undo_move() pops it and restores EVERYTHING (captured piece, castling rights, ep square,
## clocks) — the make/undo pair is the search primitive the AI leans on, so it must round-trip exactly. legal_moves()
## filters pseudo-legal moves by king safety (make, test own king, undo); castling additionally refuses to pass
## through / out of check at generation time.

enum { EMPTY = 0, PAWN = 1, KNIGHT = 2, BISHOP = 3, ROOK = 4, QUEEN = 5, KING = 6 }
const WHITE := 1
const BLACK := -1

# Result of status(): the game is either still going, decided by mate, or drawn.
enum Result { ONGOING, WHITE_WINS, BLACK_WINS, STALEMATE, DRAW_50, DRAW_MATERIAL }

# Move offsets as (file_delta, rank_delta) pairs, bound-checked per step so a knight/king never wraps a-file<->h-file.
const KNIGHT_DELTAS := [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]
const KING_DELTAS := [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]
const BISHOP_DIRS := [[1, 1], [1, -1], [-1, 1], [-1, -1]]
const ROOK_DIRS := [[1, 0], [-1, 0], [0, 1], [0, -1]]

var board: Array = []            ## 64 ints (see class doc); index rank*8+file
var side: int = WHITE            ## side to move: WHITE (+1) or BLACK (-1)
var wk_castle: bool = true       ## castling rights, cleared when the king or the relevant rook first moves / is captured
var wq_castle: bool = true
var bk_castle: bool = true
var bq_castle: bool = true
var ep: int = -1                 ## en-passant TARGET square (the empty square a pawn skipped), -1 when none
var halfmove: int = 0            ## plies since the last pawn move or capture (50-move rule = 100 plies)
var fullmove: int = 1            ## full-move number, incremented after Black moves (display only)
var _history: Array = []         ## undo stack of records pushed by make_move / popped by undo_move

func _init() -> void:
	setup_standard()

# ---------------------------------------------------------------------------------------------------
# Square helpers (static — pure index math shared with tests / SAN / the UI)
# ---------------------------------------------------------------------------------------------------

static func sq(file: int, rank: int) -> int:
	return rank * 8 + file

static func file_of(s: int) -> int:
	return s & 7

static func rank_of(s: int) -> int:
	return s >> 3

## True when (file, rank) is on the board — the guard every stepping loop uses to avoid wraparound.
static func on_board(file: int, rank: int) -> bool:
	return file >= 0 and file < 8 and rank >= 0 and rank < 8

## "e4"-style algebraic name of a square index (a1..h8).
static func sq_name(s: int) -> String:
	return "%s%d" % [char("a".unicode_at(0) + file_of(s)), rank_of(s) + 1]

## Parse an "e4" square name to an index, or -1 if malformed.
static func parse_square(txt: String) -> int:
	if txt.length() != 2:
		return -1
	var f := txt.unicode_at(0) - "a".unicode_at(0)
	var r := txt.unicode_at(1) - "1".unicode_at(0)
	if not on_board(f, r):
		return -1
	return sq(f, r)

static func type_of(piece: int) -> int:
	return absi(piece)

static func color_of(piece: int) -> int:
	return signi(piece)

# ---------------------------------------------------------------------------------------------------
# Setup / cloning / FEN
# ---------------------------------------------------------------------------------------------------

## Reset to the standard starting position (white to move, all castling rights, no ep).
func setup_standard() -> void:
	board.resize(64)
	for i in 64:
		board[i] = EMPTY
	var back := [ROOK, KNIGHT, BISHOP, QUEEN, KING, BISHOP, KNIGHT, ROOK]
	for f in 8:
		board[sq(f, 0)] = back[f] * WHITE
		board[sq(f, 1)] = PAWN * WHITE
		board[sq(f, 6)] = PAWN * BLACK
		board[sq(f, 7)] = back[f] * BLACK
	side = WHITE
	wk_castle = true
	wq_castle = true
	bk_castle = true
	bq_castle = true
	ep = -1
	halfmove = 0
	fullmove = 1
	_history.clear()

## A fully independent copy (fresh board Array + state), so the AI can search without touching the live game.
## The undo history is NOT copied — a clone starts with an empty stack (the AI only make/undoes its OWN moves).
func clone() -> ChessGame:
	var g := ChessGame.new()
	g.board = board.duplicate()
	g.side = side
	g.wk_castle = wk_castle
	g.wq_castle = wq_castle
	g.bk_castle = bk_castle
	g.bq_castle = bq_castle
	g.ep = ep
	g.halfmove = halfmove
	g.fullmove = fullmove
	return g

## Load a position from Forward-Edwards Notation (FEN). Used by tests to set up castling / ep / mate positions
## without playing into them, and handy for debugging. Tolerant: a missing ep / clock field defaults sensibly.
func from_fen(fen: String) -> void:
	board.resize(64)
	for i in 64:
		board[i] = EMPTY
	var parts := fen.strip_edges().split(" ", false)
	if parts.is_empty():
		return
	var rank := 7
	var file := 0
	for ch in parts[0]:
		if ch == "/":
			rank -= 1
			file = 0
		elif ch.is_valid_int():
			file += ch.to_int()
		else:
			board[sq(file, rank)] = _fen_piece(ch)
			file += 1
	side = WHITE if (parts.size() < 2 or parts[1] == "w") else BLACK
	var rights := parts[2] if parts.size() > 2 else "-"
	wk_castle = rights.contains("K")
	wq_castle = rights.contains("Q")
	bk_castle = rights.contains("k")
	bq_castle = rights.contains("q")
	ep = parse_square(parts[3]) if (parts.size() > 3 and parts[3] != "-") else -1
	halfmove = parts[4].to_int() if parts.size() > 4 else 0
	fullmove = parts[5].to_int() if parts.size() > 5 else 1
	_history.clear()

static func _fen_piece(ch: String) -> int:
	var t: int = {"p": PAWN, "n": KNIGHT, "b": BISHOP, "r": ROOK, "q": QUEEN, "k": KING}.get(ch.to_lower(), EMPTY)
	if t == EMPTY:
		return EMPTY
	return t * (WHITE if ch == ch.to_upper() else BLACK)

# ---------------------------------------------------------------------------------------------------
# Move generation
# ---------------------------------------------------------------------------------------------------

## Build a move Dictionary. `flag` is "" (normal), "double" (two-square pawn push, sets ep), "ep" (en-passant
## capture), "ck"/"cq" (castle king/queen side). `promo` is the promotion piece TYPE (QUEEN..KNIGHT) or 0.
static func _mk(from: int, to: int, promo: int = 0, flag: String = "") -> Dictionary:
	return {"from": from, "to": to, "promo": promo, "flag": flag}

## Every LEGAL move for the side to move: pseudo-legal moves filtered so the mover's king is not left in check.
## Empty return = no legal move (checkmate if in check, else stalemate — see status()).
func legal_moves() -> Array:
	var out: Array = []
	var mover := side
	for m in _pseudo_legal(mover):
		make_move(m)
		# After make_move the side has flipped; the mover's king must not be attacked by the (now) side to move.
		if not is_square_attacked(king_square(mover), -mover):
			out.append(m)
		undo_move()
	return out

## Pseudo-legal moves for `who` — geometrically valid but NOT yet checked for leaving the own king in check.
## Castling is the exception: it is emitted only when fully legal (king not in / through / into check), because
## the "through check" squares can't be caught by the make/undo king-safety filter legal_moves() applies.
func _pseudo_legal(who: int) -> Array:
	var out: Array = []
	for s in 64:
		var p: int = board[s]
		if p == EMPTY or color_of(p) != who:
			continue
		match type_of(p):
			PAWN:
				_gen_pawn(s, who, out)
			KNIGHT:
				_gen_leaper(s, who, KNIGHT_DELTAS, out)
			KING:
				_gen_leaper(s, who, KING_DELTAS, out)
				_gen_castling(who, out)
			BISHOP:
				_gen_slider(s, who, BISHOP_DIRS, out)
			ROOK:
				_gen_slider(s, who, ROOK_DIRS, out)
			QUEEN:
				_gen_slider(s, who, BISHOP_DIRS, out)
				_gen_slider(s, who, ROOK_DIRS, out)
	return out

func _gen_pawn(s: int, who: int, out: Array) -> void:
	var f := file_of(s)
	var r := rank_of(s)
	var dr := who                                   # white pawns go up (+1 rank), black down (-1)
	var start_rank := 1 if who == WHITE else 6
	var promo_rank := 7 if who == WHITE else 0
	# Single + double forward push (only onto empty squares; never a capture).
	var one_r := r + dr
	if on_board(f, one_r) and board[sq(f, one_r)] == EMPTY:
		_pawn_push_or_promote(s, sq(f, one_r), one_r == promo_rank, out)
		var two_r := r + dr * 2
		if r == start_rank and board[sq(f, two_r)] == EMPTY:
			out.append(_mk(s, sq(f, two_r), 0, "double"))
	# Diagonal captures (incl. en passant onto the ep target square).
	for df: int in [-1, 1]:
		var cf := f + df
		var cr := r + dr
		if not on_board(cf, cr):
			continue
		var to := sq(cf, cr)
		var target: int = board[to]
		if target != EMPTY and color_of(target) == -who:
			_pawn_push_or_promote(s, to, cr == promo_rank, out)
		elif to == ep and ep != -1:
			out.append(_mk(s, to, 0, "ep"))

## Emit a pawn move to `to`, expanding to the four promotion choices when it lands on the last rank.
func _pawn_push_or_promote(from: int, to: int, is_promo: bool, out: Array) -> void:
	if is_promo:
		for promo: int in [QUEEN, ROOK, BISHOP, KNIGHT]:
			out.append(_mk(from, to, promo))
	else:
		out.append(_mk(from, to))

## Knight / king single-step moves: each delta once, onto an empty or enemy square.
func _gen_leaper(s: int, who: int, deltas: Array, out: Array) -> void:
	var f := file_of(s)
	var r := rank_of(s)
	for d in deltas:
		var nf: int = f + d[0]
		var nr: int = r + d[1]
		if not on_board(nf, nr):
			continue
		var to := sq(nf, nr)
		if board[to] == EMPTY or color_of(board[to]) == -who:
			out.append(_mk(s, to))

## Sliding pieces: ray-cast along each direction until off-board or blocked; include the first enemy hit (capture).
func _gen_slider(s: int, who: int, dirs: Array, out: Array) -> void:
	var f := file_of(s)
	var r := rank_of(s)
	for d in dirs:
		var nf: int = f + d[0]
		var nr: int = r + d[1]
		while on_board(nf, nr):
			var to := sq(nf, nr)
			var occ: int = board[to]
			if occ == EMPTY:
				out.append(_mk(s, to))
			else:
				if color_of(occ) == -who:
					out.append(_mk(s, to))     # capture the first blocker
				break                          # own piece or captured enemy stops the ray
			nf += d[0]
			nr += d[1]

## Castling: emitted only when fully legal. Requires the right, an empty path between king and rook, the king
## NOT currently in check, and the two squares the king CROSSES (incl. its destination) not attacked. The rook's
## path (queenside b-file) only needs to be empty, not safe — the king never stands there.
func _gen_castling(who: int, out: Array) -> void:
	var enemy := -who
	if who == WHITE:
		var k := sq(4, 0)  # e1
		if wk_castle and board[sq(5, 0)] == EMPTY and board[sq(6, 0)] == EMPTY \
				and not is_square_attacked(k, enemy) and not is_square_attacked(sq(5, 0), enemy) and not is_square_attacked(sq(6, 0), enemy):
			out.append(_mk(k, sq(6, 0), 0, "ck"))
		if wq_castle and board[sq(3, 0)] == EMPTY and board[sq(2, 0)] == EMPTY and board[sq(1, 0)] == EMPTY \
				and not is_square_attacked(k, enemy) and not is_square_attacked(sq(3, 0), enemy) and not is_square_attacked(sq(2, 0), enemy):
			out.append(_mk(k, sq(2, 0), 0, "cq"))
	else:
		var k := sq(4, 7)  # e8
		if bk_castle and board[sq(5, 7)] == EMPTY and board[sq(6, 7)] == EMPTY \
				and not is_square_attacked(k, enemy) and not is_square_attacked(sq(5, 7), enemy) and not is_square_attacked(sq(6, 7), enemy):
			out.append(_mk(k, sq(6, 7), 0, "ck"))
		if bq_castle and board[sq(3, 7)] == EMPTY and board[sq(2, 7)] == EMPTY and board[sq(1, 7)] == EMPTY \
				and not is_square_attacked(k, enemy) and not is_square_attacked(sq(3, 7), enemy) and not is_square_attacked(sq(2, 7), enemy):
			out.append(_mk(k, sq(2, 7), 0, "cq"))

# ---------------------------------------------------------------------------------------------------
# Attack detection
# ---------------------------------------------------------------------------------------------------

## True when square `s` is attacked by ANY piece of colour `by`. Used for check detection, castling safety, and
## the legality filter. Scans outward from `s` by piece geometry (cheaper than generating all `by` moves).
func is_square_attacked(s: int, by: int) -> bool:
	var f := file_of(s)
	var r := rank_of(s)
	# Pawns: a `by` pawn attacks diagonally FORWARD, so it sits one rank "behind" s from its own perspective —
	# a white attacker is at rank r-1, a black attacker at rank r+1, on either adjacent file.
	var pr := r - by
	for df: int in [-1, 1]:
		if on_board(f + df, pr) and board[sq(f + df, pr)] == PAWN * by:
			return true
	# Knights.
	for d in KNIGHT_DELTAS:
		if on_board(f + d[0], r + d[1]) and board[sq(f + d[0], r + d[1])] == KNIGHT * by:
			return true
	# King (adjacent).
	for d in KING_DELTAS:
		if on_board(f + d[0], r + d[1]) and board[sq(f + d[0], r + d[1])] == KING * by:
			return true
	# Sliding: diagonals hit by a bishop or queen; orthogonals by a rook or queen.
	if _ray_hit(f, r, BISHOP_DIRS, by, BISHOP):
		return true
	if _ray_hit(f, r, ROOK_DIRS, by, ROOK):
		return true
	return false

## Cast rays from (f, r); return true if the first piece met on any ray is a `by` QUEEN or a `by` `slider` type.
func _ray_hit(f: int, r: int, dirs: Array, by: int, slider: int) -> bool:
	for d in dirs:
		var nf: int = f + d[0]
		var nr: int = r + d[1]
		while on_board(nf, nr):
			var occ: int = board[sq(nf, nr)]
			if occ != EMPTY:
				if color_of(occ) == by and (type_of(occ) == slider or type_of(occ) == QUEEN):
					return true
				break
			nf += d[0]
			nr += d[1]
	return false

## The board index of `color`'s king, or -1 if (impossibly) absent.
func king_square(color: int) -> int:
	for s in 64:
		if board[s] == KING * color:
			return s
	return -1

## True when `color`'s king is currently attacked.
func is_in_check(color: int) -> bool:
	return is_square_attacked(king_square(color), -color)

# ---------------------------------------------------------------------------------------------------
# Make / undo
# ---------------------------------------------------------------------------------------------------

## Apply `m` to the board and push an undo record. Assumes `m` is legal (came from legal_moves() / parse_move()).
## Handles capture (incl. en passant, where the captured pawn is NOT on `to`), promotion, the castling rook hop,
## castling-right revocation, the en-passant target, and the clocks. undo_move() reverses all of it exactly.
func make_move(m: Dictionary) -> void:
	var from: int = m.from
	var to: int = m.to
	var piece: int = board[from]
	var mover := color_of(piece)
	var flag: String = m.get("flag", "")
	var cap_sq := to
	if flag == "ep":
		cap_sq = sq(file_of(to), rank_of(from))   # the captured pawn sits beside the mover, not on the ep square
	var captured: int = board[cap_sq]
	_history.append({
		"from": from, "to": to, "piece": piece, "captured": captured, "cap_sq": cap_sq,
		"promo": m.get("promo", 0), "flag": flag,
		"wk": wk_castle, "wq": wq_castle, "bk": bk_castle, "bq": bq_castle,
		"ep": ep, "halfmove": halfmove, "fullmove": fullmove,
	})
	# Move the piece (clearing the ep-captured pawn's real square first, if any).
	if flag == "ep":
		board[cap_sq] = EMPTY
	board[from] = EMPTY
	var promo: int = m.get("promo", 0)
	board[to] = (promo * mover) if promo != 0 else piece
	# Castling: hop the rook to the far side of the king.
	if flag == "ck":
		var r0 := rank_of(from)
		board[sq(5, r0)] = board[sq(7, r0)]
		board[sq(7, r0)] = EMPTY
	elif flag == "cq":
		var r0 := rank_of(from)
		board[sq(3, r0)] = board[sq(0, r0)]
		board[sq(0, r0)] = EMPTY
	# Revoke castling rights touched by this move (king move, rook move off home, or rook captured on home).
	_update_castle_rights(from, to, piece)
	# En-passant target: only a double pawn push offers one, on the skipped square.
	ep = ((from + to) / 2) if flag == "double" else -1
	# 50-move clock resets on a pawn move or any capture.
	if type_of(piece) == PAWN or captured != EMPTY:
		halfmove = 0
	else:
		halfmove += 1
	if mover == BLACK:
		fullmove += 1
	side = -mover

## Clear any castling right invalidated by a piece leaving/arriving at a king or rook home square.
func _update_castle_rights(from: int, to: int, piece: int) -> void:
	match type_of(piece):
		KING:
			if color_of(piece) == WHITE:
				wk_castle = false
				wq_castle = false
			else:
				bk_castle = false
				bq_castle = false
	# A rook leaving its home square, OR any capture landing on a rook's home square, kills that right.
	for s: int in [from, to]:
		if s == sq(7, 0):
			wk_castle = false
		elif s == sq(0, 0):
			wq_castle = false
		elif s == sq(7, 7):
			bk_castle = false
		elif s == sq(0, 7):
			bq_castle = false

## Reverse the most recent make_move, restoring the board and all state exactly. No-op with an empty history.
func undo_move() -> void:
	if _history.is_empty():
		return
	var u: Dictionary = _history.pop_back()
	var from: int = u.from
	var to: int = u.to
	var flag: String = u.flag
	board[from] = u.piece                      # the ORIGINAL piece (a pawn, if this was a promotion)
	board[to] = EMPTY
	if flag == "ep":
		board[u.cap_sq] = u.captured           # the ep-captured pawn goes back beside the mover; `to` stays empty
	else:
		board[to] = u.captured                 # restore whatever stood on `to` (piece or EMPTY)
	if flag == "ck":
		var r0 := rank_of(from)
		board[sq(7, r0)] = board[sq(5, r0)]
		board[sq(5, r0)] = EMPTY
	elif flag == "cq":
		var r0 := rank_of(from)
		board[sq(0, r0)] = board[sq(3, r0)]
		board[sq(3, r0)] = EMPTY
	wk_castle = u.wk
	wq_castle = u.wq
	bk_castle = u.bk
	bq_castle = u.bq
	ep = u.ep
	halfmove = u.halfmove
	fullmove = u.fullmove
	side = color_of(u.piece)                   # the side that made the move is the side to move again

# ---------------------------------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------------------------------

## The game's current result. Checkmate → the side that delivered it wins; no legal move without check →
## stalemate; the 50-move and insufficient-material draws are also reported so the UI can end the game.
func status() -> int:
	if legal_moves().is_empty():
		if is_in_check(side):
			return Result.BLACK_WINS if side == WHITE else Result.WHITE_WINS
		return Result.STALEMATE
	if halfmove >= 100:
		return Result.DRAW_50
	if _insufficient_material():
		return Result.DRAW_MATERIAL
	return Result.ONGOING

func is_game_over() -> bool:
	return status() != Result.ONGOING

## True for the trivial dead positions where NO mate is possible: bare kings (K vs K) and a king with a single
## lone minor (K+B or K+N vs K). Errs SAFE — it only ever reports the clear-cut draws, never a false one. It does
## NOT try the harder same-coloured-bishops or K+N+N cases (those stay ONGOING); this exists to stop the most
## obviously hopeless games dragging, not to be a full endgame theory table.
func _insufficient_material() -> bool:
	var minors := 0
	for s in 64:
		match type_of(board[s]):
			EMPTY, KING:
				pass
			KNIGHT, BISHOP:
				minors += 1
			_:
				return false   # a pawn, rook or queen exists -> mate is possible
	return minors <= 1

# ---------------------------------------------------------------------------------------------------
# Notation: parse player input + format for the move log
# ---------------------------------------------------------------------------------------------------

## Parse a player's typed move against the current legal moves, returning the matching move Dictionary or an
## EMPTY dict ({}) if it's illegal / unparseable. Forgiving on purpose (this is the blindfold INPUT): accepts
## coordinate notation ("e2e4", "g1f3", "e7e8q" for promotion) AND standard algebraic ("e4", "Nf3", "exd5",
## "O-O", "e8=Q"), case-insensitively for the coordinate form. The move must be LEGAL to match.
func parse_move(text: String) -> Dictionary:
	var t := text.strip_edges()
	if t.is_empty():
		return {}
	var legal := legal_moves()
	# Coordinate form: from-square + to-square (+ optional promotion letter).
	var lower := t.to_lower()
	var coord := RegEx.new()
	coord.compile("^([a-h][1-8])([a-h][1-8])([qrbn])?$")
	var mt := coord.search(lower)
	if mt != null:
		var from := parse_square(mt.get_string(1))
		var to := parse_square(mt.get_string(2))
		var promo := _promo_letter(mt.get_string(3))
		for m in legal:
			if m.from == from and m.to == to and (promo == 0 or m.promo == promo):
				# For a promotion with no letter given, default to a queen so "e7e8" still works.
				if _is_promotion(m) and promo == 0:
					if m.promo == QUEEN:
						return m
				else:
					return m
		return {}
	# SAN form: compare against each legal move's SAN (both stripped of check/decoration marks).
	var want := _strip_san(t)
	for m in legal:
		if _strip_san(move_to_san(m)) == want:
			return m
	# Also accept lower-cased SAN (a player typing "nf3").
	for m in legal:
		if _strip_san(move_to_san(m)).to_lower() == want.to_lower():
			return m
	# Structural fallback: accept OVER-specified but legal SAN the minimal generator never emits — a redundant
	# origin file/rank ("Ngf3", "N1f3") or an explicit capture "x" the target square makes obvious. Parse the
	# player's spelling into (piece, disambiguation, destination, promotion) and match the UNIQUE legal move.
	var loose := _match_structural_san(want, legal)
	if not loose.is_empty():
		return loose
	return {}

## Match an over-specified SAN string against the legal moves structurally (piece + optional file/rank
## disambiguation + destination + optional promotion), returning the UNIQUE matching legal move or {} if none /
## ambiguous. Castling is already handled by the exact-SAN pass, so it's ignored here.
func _match_structural_san(san: String, legal: Array) -> Dictionary:
	var s := san
	if s.begins_with("O-O"):
		return {}
	# Trailing promotion "=Q".
	var promo := 0
	var eq := s.find("=")
	if eq != -1:
		promo = _promo_letter(s.substr(eq + 1, 1))
		s = s.substr(0, eq)
	# Leading piece letter. Uppercase N/B/R/Q/K is always a piece; lowercase n/r/q/k are pieces too (they aren't
	# files), but lowercase 'b' is the b-FILE, not a bishop — so only an uppercase 'B' means bishop.
	var pt := PAWN
	var idx := 0
	if s.length() >= 1:
		var first := s.substr(0, 1)
		if "NBRQK".contains(first):
			pt = _letter_to_piece(first)
			idx = 1
		elif "nrqk".contains(first):
			pt = _letter_to_piece(first.to_upper())
			idx = 1
	var body := s.substr(idx).replace("x", "")   # disambiguation + destination, capture marker dropped
	if body.length() < 2:
		return {}
	var dest := parse_square(body.substr(body.length() - 2, 2))
	if dest == -1:
		return {}
	# Whatever precedes the destination is 0-2 chars of origin file/rank disambiguation.
	var hint := body.substr(0, body.length() - 2)
	var hint_file := -1
	var hint_rank := -1
	for i in hint.length():
		var c := hint.unicode_at(i)
		if c >= "a".unicode_at(0) and c <= "h".unicode_at(0):
			hint_file = c - "a".unicode_at(0)
		elif c >= "1".unicode_at(0) and c <= "8".unicode_at(0):
			hint_rank = c - "1".unicode_at(0)
	var found := {}
	var count := 0
	for m in legal:
		if type_of(board[m.from]) != pt or m.to != dest:
			continue
		if promo != 0 and int(m.get("promo", 0)) != promo:
			continue
		if promo == 0 and _is_promotion(m) and m.promo != QUEEN:
			continue                                     # unspecified promotion defaults to queen
		if hint_file != -1 and file_of(m.from) != hint_file:
			continue
		if hint_rank != -1 and rank_of(m.from) != hint_rank:
			continue
		found = m
		count += 1
	return found if count == 1 else {}

static func _letter_to_piece(ch: String) -> int:
	return {"N": KNIGHT, "B": BISHOP, "R": ROOK, "Q": QUEEN, "K": KING}.get(ch, PAWN)

static func _promo_letter(ch: String) -> int:
	return {"q": QUEEN, "r": ROOK, "b": BISHOP, "n": KNIGHT}.get(ch.to_lower(), 0)

func _is_promotion(m: Dictionary) -> bool:
	return int(m.get("promo", 0)) != 0

## Strip SAN decoration (check "+", mate "#", "!?" annotations) and normalise castling ("0-0" -> "O-O") so
## parse_move can compare a player's spelling against generated SAN.
static func _strip_san(s: String) -> String:
	var out := s.strip_edges().replace("+", "").replace("#", "").replace("!", "").replace("?", "")
	out = out.replace("0-0-0", "O-O-O").replace("0-0", "O-O").replace("o-o-o", "O-O-O").replace("o-o", "O-O")
	return out

## Standard Algebraic Notation for `m` in the CURRENT position (call BEFORE make_move). Includes piece letter,
## capture "x", disambiguation (file/rank/both when two like pieces can reach `to`), promotion "=Q", castling
## "O-O"/"O-O-O", and the check "+" / checkmate "#" suffix. This is what the move log shows.
func move_to_san(m: Dictionary) -> String:
	var flag: String = m.get("flag", "")
	if flag == "ck":
		return _san_suffix(m, "O-O")
	if flag == "cq":
		return _san_suffix(m, "O-O-O")
	var piece: int = board[m.from]
	var pt := type_of(piece)
	var is_capture: bool = board[m.to] != EMPTY or flag == "ep"
	var s := ""
	if pt == PAWN:
		if is_capture:
			s = "%sx" % char("a".unicode_at(0) + file_of(m.from))
		s += sq_name(m.to)
		if _is_promotion(m):
			s += "=%s" % _piece_letter(int(m.promo))
	else:
		s = _piece_letter(pt) + _disambiguation(m, piece) + ("x" if is_capture else "") + sq_name(m.to)
	return _san_suffix(m, s)

## The minimal file/rank/both disambiguator needed when another same-type piece could also move to m.to.
func _disambiguation(m: Dictionary, piece: int) -> String:
	var rivals: Array = []
	for other in legal_moves():
		if other.to == m.to and other.from != m.from and board[other.from] == piece:
			rivals.append(other.from)
	if rivals.is_empty():
		return ""
	var same_file := false
	var same_rank := false
	for rf in rivals:
		if file_of(rf) == file_of(m.from):
			same_file = true
		if rank_of(rf) == rank_of(m.from):
			same_rank = true
	if not same_file:
		return char("a".unicode_at(0) + file_of(m.from))           # file alone disambiguates
	if not same_rank:
		return str(rank_of(m.from) + 1)                            # else rank
	return sq_name(m.from)                                         # else the full square

## Append "+" (check) or "#" (checkmate) by making the move and inspecting the opponent. Restores the board.
func _san_suffix(m: Dictionary, base: String) -> String:
	make_move(m)
	var suffix := ""
	if is_in_check(side):
		suffix = "#" if legal_moves().is_empty() else "+"
	undo_move()
	return base + suffix

static func _piece_letter(pt: int) -> String:
	return {KNIGHT: "N", BISHOP: "B", ROOK: "R", QUEEN: "Q", KING: "K"}.get(pt, "")

# ---------------------------------------------------------------------------------------------------
# Convenience for the UI
# ---------------------------------------------------------------------------------------------------

## Coordinate string for a move ("e2e4", "e7e8q") — the compact form the blindfold prompt echoes back.
func move_to_coord(m: Dictionary) -> String:
	var s := sq_name(m.from) + sq_name(m.to)
	if _is_promotion(m):
		s += _piece_letter(int(m.promo)).to_lower()
	return s

## The Unicode glyph for a piece int (♙♘♗♖♕♔ / ♟♞♝♜♛♚), or " " for empty — used by the visualiser board when the
## font has the glyphs. ChessScreen falls back to letters if not.
static func piece_glyph(piece: int) -> String:
	var white := {PAWN: "♙", KNIGHT: "♘", BISHOP: "♗", ROOK: "♖", QUEEN: "♕", KING: "♔"}
	var black := {PAWN: "♟", KNIGHT: "♞", BISHOP: "♝", ROOK: "♜", QUEEN: "♛", KING: "♚"}
	if piece == EMPTY:
		return " "
	return white[type_of(piece)] if color_of(piece) == WHITE else black[type_of(piece)]

## The letter for a piece int (uppercase = white, lowercase = black), the glyph-free fallback for the board.
static func piece_letter_cased(piece: int) -> String:
	if piece == EMPTY:
		return ""
	var l: String = {PAWN: "P", KNIGHT: "N", BISHOP: "B", ROOK: "R", QUEEN: "Q", KING: "K"}[type_of(piece)]
	return l if color_of(piece) == WHITE else l.to_lower()
