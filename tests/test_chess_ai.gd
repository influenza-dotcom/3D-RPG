extends GutTest

## Tests for the ChessAi opponent (scripts/chess/chess_ai.gd). It must always return a LEGAL move, spot a forced
## mate, and grab free material — enough to trust it as an opponent without pinning its exact (randomised) choices.

const ChessGameScript := preload("res://scripts/chess/chess_game.gd")
const ChessAiScript := preload("res://scripts/chess/chess_ai.gd")

func test_ai_returns_a_legal_move() -> void:
	var g = ChessGameScript.new()
	var ai = ChessAiScript.new()
	var legal := g.legal_moves()
	var chosen = ai.choose_move(g, 2, 0.0)
	assert_false(chosen.is_empty(), "the AI returns a move from the opening position")
	var found := false
	for m in legal:
		if m.from == chosen.from and m.to == chosen.to and int(m.get("promo", 0)) == int(chosen.get("promo", 0)):
			found = true
	assert_true(found, "the AI's move is one of the legal moves")
	g = null
	ai = null

func test_ai_finds_mate_in_one() -> void:
	# White: Ra1, Kg1. Black: Kg8, pawns f7/g7/h7. Ra1-a8 is back-rank mate; with no blunder the AI must play it.
	var g = ChessGameScript.new()
	g.from_fen("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
	var ai = ChessAiScript.new()
	var chosen = ai.choose_move(g, 2, 0.0)
	assert_eq(ChessGameScript.sq_name(chosen.from), "a1", "the AI moves the rook that delivers mate")
	assert_eq(ChessGameScript.sq_name(chosen.to), "a8", "the AI plays Ra8#, the only mate")
	g = null
	ai = null

func test_ai_grabs_free_material() -> void:
	# Black queen on d5 is UNDEFENDED (the king on e8 is too far to recapture); White's Qd1xd5 wins it clean down
	# the open d-file. A full queen is decisively best, so the AI must take it.
	var g = ChessGameScript.new()
	g.from_fen("4k3/8/8/3q4/8/8/8/3QK3 w - - 0 1")
	var ai = ChessAiScript.new()
	var chosen = ai.choose_move(g, 2, 0.0)
	assert_eq(ChessGameScript.sq_name(chosen.to), "d5", "the AI captures the hanging queen (Qxd5)")
	g = null
	ai = null

func test_half_pawn_tie_window_is_half_a_pawn() -> void:
	# The root-move tie group keeps every move within HALF_PAWN of best (then picks at random for cross-game
	# variety). Scores are centipawns (VALUES[PAWN]=100), so the window must be 50 — a bare 0.5 was 1/200th of a
	# pawn, a deterministic argmax. Pin it so the regression can't silently return.
	assert_eq(ChessAiScript.HALF_PAWN, 50.0, "tie window is half a pawn in centipawns, not ~0")
	assert_true(ChessAiScript.HALF_PAWN == ChessAiScript.VALUES[1] / 2.0, "stays half of a pawn if the pawn value changes")

func test_blunder_still_returns_legal_move() -> void:
	# With blunder_chance 1.0 the AI always plays a random legal move — it must still be legal, never empty.
	var g = ChessGameScript.new()
	var ai = ChessAiScript.new()
	for _i in 20:
		var chosen = ai.choose_move(g, 2, 1.0)
		assert_false(chosen.is_empty(), "a blunder move is still a real move")
		assert_false(g.parse_move(g.move_to_coord(chosen)).is_empty(), "a blunder move is still legal")
	g = null
	ai = null
