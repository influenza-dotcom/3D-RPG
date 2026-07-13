extends GutTest

## Correctness tests for the ChessGame rules engine (scripts/chess/chess_game.gd). The load-bearing one is PERFT
## — counting the leaf nodes of the move tree to a fixed depth and comparing against the values every chess engine
## agrees on. A single illegal move generated (or a legal one missed, or a broken make/undo) shifts the count, so
## matching known perft numbers from the standard AND "Kiwipete" positions is a very strong proof of legality,
## castling, en passant, promotion, check evasion, and pin handling all at once. The explicit cases below then
## pin the specific rules a designer would notice if they broke (mate/stalemate/castling-through-check/ep/promo).

const ChessGameScript := preload("res://scripts/chess/chess_game.gd")

# Kiwipete — the classic perft catch-all: castling both sides for both colours, en passant, checks, pins, promotion.
const KIWIPETE := "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"

func _perft(g, depth: int) -> int:
	if depth == 0:
		return 1
	var nodes := 0
	for m in g.legal_moves():
		g.make_move(m)
		nodes += _perft(g, depth - 1)
		g.undo_move()
	return nodes

# --- Perft: the move generator matches the universally-agreed node counts ---------------------------

func test_perft_startpos() -> void:
	var g = ChessGameScript.new()
	assert_eq(g.legal_moves().size(), 20, "the opening position has exactly 20 legal moves")
	assert_eq(_perft(g, 1), 20, "perft(1) from the start = 20")
	assert_eq(_perft(g, 2), 400, "perft(2) from the start = 400")
	assert_eq(_perft(g, 3), 8902, "perft(3) from the start = 8902")
	g = null

func test_perft_kiwipete() -> void:
	var g = ChessGameScript.new()
	g.from_fen(KIWIPETE)
	assert_eq(_perft(g, 1), 48, "Kiwipete perft(1) = 48 (castling, pins, checks all present)")
	assert_eq(_perft(g, 2), 2039, "Kiwipete perft(2) = 2039 — the standard castling/ep/pin correctness check")
	g = null

# --- make/undo round-trips exactly ------------------------------------------------------------------

func test_make_undo_restores_start() -> void:
	var g = ChessGameScript.new()
	var before: Array = g.board.duplicate()
	for m in g.legal_moves():
		g.make_move(m)
		g.undo_move()
		assert_eq(g.board, before, "board must be identical after make+undo of %s" % g.move_to_coord(m))
		assert_eq(g.side, ChessGameScript.WHITE, "side to move restored after undo")
	g = null

# --- Checkmate detection ----------------------------------------------------------------------------

func test_fools_mate_is_checkmate() -> void:
	# 1. f3 e5 2. g4 Qh4# — the fastest mate. After it White is checkmated (no legal move, in check).
	var g = ChessGameScript.new()
	for coord in ["f2f3", "e7e5", "g2g4", "d8h4"]:
		var m = g.parse_move(coord)
		assert_false(m.is_empty(), "move %s must be legal in sequence" % coord)
		g.make_move(m)
	assert_true(g.legal_moves().is_empty(), "White has no legal move after Qh4#")
	assert_true(g.is_in_check(ChessGameScript.WHITE), "White is in check after Qh4#")
	assert_eq(g.status(), ChessGameScript.Result.BLACK_WINS, "Fool's mate is a Black win")
	g = null

func test_scholars_mate_is_checkmate() -> void:
	# 1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6?? 4. Qxf7#
	var g = ChessGameScript.new()
	for coord in ["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7"]:
		var m = g.parse_move(coord)
		assert_false(m.is_empty(), "move %s must be legal" % coord)
		g.make_move(m)
	assert_eq(g.status(), ChessGameScript.Result.WHITE_WINS, "Scholar's mate is a White win")
	g = null

# --- Stalemate --------------------------------------------------------------------------------------

func test_stalemate_detected() -> void:
	# Black king h8, White queen f7, White king g6: Black is not in check but has no legal move.
	var g = ChessGameScript.new()
	g.from_fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
	assert_false(g.is_in_check(ChessGameScript.BLACK), "Black is NOT in check in the stalemate position")
	assert_true(g.legal_moves().is_empty(), "Black has no legal move")
	assert_eq(g.status(), ChessGameScript.Result.STALEMATE, "no move + not in check = stalemate")
	g = null

# --- Castling ---------------------------------------------------------------------------------------

func test_castling_both_sides_available() -> void:
	var g = ChessGameScript.new()
	g.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	var flags := _flags(g.legal_moves())
	assert_true(flags.has("ck"), "kingside castling (O-O) is legal with a clear, safe path")
	assert_true(flags.has("cq"), "queenside castling (O-O-O) is legal with a clear, safe path")
	g = null

func test_cannot_castle_through_check() -> void:
	# Black rook on f8 attacks f1, the square the king crosses castling kingside -> O-O must be refused, but the
	# king is NOT in check (f8 doesn't hit e1), so O-O-O and normal king moves remain.
	var g = ChessGameScript.new()
	g.from_fen("5r2/8/8/8/8/8/8/R3K2R w KQ - 0 1")
	var flags := _flags(g.legal_moves())
	assert_false(flags.has("ck"), "cannot castle kingside THROUGH the attacked f1 square")
	assert_true(flags.has("cq"), "queenside castling is still legal (its path is safe)")
	g = null

func test_cannot_castle_out_of_check() -> void:
	# Black rook on e8 pins nothing but gives check down the e-file: the king is in check, so NO castling at all.
	var g = ChessGameScript.new()
	g.from_fen("4r3/8/8/8/8/8/8/R3K2R w KQ - 0 1")
	assert_true(g.is_in_check(ChessGameScript.WHITE), "White king is in check from the e-file rook")
	var flags := _flags(g.legal_moves())
	assert_false(flags.has("ck"), "cannot castle out of check (kingside)")
	assert_false(flags.has("cq"), "cannot castle out of check (queenside)")
	g = null

# --- En passant -------------------------------------------------------------------------------------

func test_en_passant_capture() -> void:
	# White pawn e5, Black has just played ...f7f5 (ep target f6). exf6 e.p. is legal and removes the f5 pawn.
	var g = ChessGameScript.new()
	g.from_fen("rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3")
	var ep = g.parse_move("e5f6")
	assert_false(ep.is_empty(), "e5xf6 en passant must be legal when the ep target is f6")
	assert_eq(ep.get("flag", ""), "ep", "the capture is flagged en passant")
	var f5 = ChessGameScript.parse_square("f5")
	g.make_move(ep)
	assert_eq(g.board[f5], ChessGameScript.EMPTY, "the en-passant-captured Black pawn is removed from f5")
	g.undo_move()
	assert_eq(g.board[f5], ChessGameScript.PAWN * ChessGameScript.BLACK, "undo restores the captured pawn to f5")
	g = null

# --- Promotion --------------------------------------------------------------------------------------

func test_promotion_offers_four_pieces() -> void:
	var g = ChessGameScript.new()
	g.from_fen("8/P7/8/8/8/8/8/k6K w - - 0 1")
	var a8 = ChessGameScript.parse_square("a8")
	var promos := {}
	for m in g.legal_moves():
		if m.to == a8 and int(m.get("promo", 0)) != 0:
			promos[m.promo] = true
	assert_eq(promos.size(), 4, "a pawn reaching the last rank can promote to Q/R/B/N (4 choices)")
	var q = g.parse_move("a7a8q")
	assert_false(q.is_empty(), "a7a8q (promote to queen) parses")
	g.make_move(q)
	assert_eq(g.board[a8], ChessGameScript.QUEEN * ChessGameScript.WHITE, "the pawn becomes a white queen on a8")
	g = null

# --- Parsing + SAN ----------------------------------------------------------------------------------

func test_parse_accepts_coordinate_and_san() -> void:
	var g = ChessGameScript.new()
	var by_coord = g.parse_move("e2e4")
	var by_san = g.parse_move("e4")
	assert_false(by_coord.is_empty(), "coordinate 'e2e4' parses")
	assert_false(by_san.is_empty(), "SAN 'e4' parses")
	assert_eq(by_coord.from, by_san.from, "both spellings resolve to the same move (from)")
	assert_eq(by_coord.to, by_san.to, "both spellings resolve to the same move (to)")
	assert_true(g.parse_move("e5").is_empty(), "an illegal move ('e5' from the start) returns an empty dict")
	assert_true(g.parse_move("nonsense").is_empty(), "garbage input returns an empty dict")
	g = null

func test_parse_accepts_overspecified_san() -> void:
	# Redundant disambiguation ("Ngf3", "N1f3") is legal standard notation even when the minimal SAN is just "Nf3";
	# a forgiving blindfold parser must still resolve it to the one legal Ng1-f3.
	var g = ChessGameScript.new()
	var minimal = g.parse_move("Nf3")
	var over_file = g.parse_move("Ngf3")
	var over_rank = g.parse_move("N1f3")
	assert_false(over_file.is_empty(), "over-specified 'Ngf3' still parses")
	assert_false(over_rank.is_empty(), "over-specified 'N1f3' still parses")
	assert_eq(over_file.from, minimal.from, "'Ngf3' resolves to the same move as 'Nf3'")
	assert_eq(over_rank.from, minimal.from, "'N1f3' resolves to the same move as 'Nf3'")
	g = null

func test_san_formatting() -> void:
	var g = ChessGameScript.new()
	assert_eq(g.move_to_san(g.parse_move("g1f3")), "Nf3", "knight development SAN")
	assert_eq(g.move_to_san(g.parse_move("e2e4")), "e4", "pawn push SAN")
	g.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	assert_eq(g.move_to_san(g.parse_move("e1g1")), "O-O", "kingside castling SAN")
	assert_eq(g.move_to_san(g.parse_move("e1c1")), "O-O-O", "queenside castling SAN")
	g = null

# --- helper -----------------------------------------------------------------------------------------

## Collect the set of move flags present in a move list (for asserting castling availability).
func _flags(moves: Array) -> Dictionary:
	var out := {}
	for m in moves:
		var f: String = m.get("flag", "")
		if f != "":
			out[f] = true
	return out
