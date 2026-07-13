class_name ChessAi
extends RefCounted

## The opponent brain for the blindfold-chess minigame. Given a ChessGame, it returns a move for the side to
## move. Pure logic (no tree/UI): negamax with alpha-beta pruning over a material + piece-square evaluation, to a
## configurable `depth`. Difficulty is two knobs a ChessMatch component exports:
##   • depth          — search plies. 1 = sees only immediate captures, ~2-3 = a competent club-ish opponent.
##   • blunder_chance — 0..1 probability of throwing the search away and playing a RANDOM legal move this turn.
##                      This is what makes a weak NPC feel human/beatable (a drunk hangs his queen now and then).
## It searches on game.clone() so the live match is never mutated by the AI's make/undo exploration.

## Centipawn material values by piece TYPE (index by ChessGame type enum; index 0/EMPTY unused). King is huge so
## the search never "trades" it — mate is scored separately, but a stray king value keeps eval sane mid-search.
const VALUES := [0, 100, 320, 330, 500, 900, 20000]

# A score beyond any material total, so a forced mate always beats a merely winning position. Offset by ply so
# the search prefers the QUICKEST mate (and the slowest escape).
const MATE := 1_000_000.0

## Tie-group width: keep every root move within half a pawn (50 cp) of best, then pick at random for cross-game
## variety. Scores are CENTIPAWNS (VALUES[PAWN]=100), so this is 50, NOT 0.5 — a bare 0.5 was 1/200th of a pawn,
## a deterministic argmax that made every match against the same NPC replay identically.
const HALF_PAWN := 50.0

# Piece-square tables (white's perspective, index a1..h8). They nudge the AI toward sound development —
# knights/bishops off the back rank, pawns to the centre, the king tucked away. Black reads them mirrored by
# rank (see _pst_value). Classic simplified tables; good enough for a characterful club opponent.
const PST := {
	ChessGame.PAWN: [
		0, 0, 0, 0, 0, 0, 0, 0,
		5, 10, 10, -20, -20, 10, 10, 5,
		5, -5, -10, 0, 0, -10, -5, 5,
		0, 0, 0, 20, 20, 0, 0, 0,
		5, 5, 10, 25, 25, 10, 5, 5,
		10, 10, 20, 30, 30, 20, 10, 10,
		50, 50, 50, 50, 50, 50, 50, 50,
		0, 0, 0, 0, 0, 0, 0, 0,
	],
	ChessGame.KNIGHT: [
		-50, -40, -30, -30, -30, -30, -40, -50,
		-40, -20, 0, 5, 5, 0, -20, -40,
		-30, 5, 10, 15, 15, 10, 5, -30,
		-30, 0, 15, 20, 20, 15, 0, -30,
		-30, 5, 15, 20, 20, 15, 5, -30,
		-30, 0, 10, 15, 15, 10, 0, -30,
		-40, -20, 0, 0, 0, 0, -20, -40,
		-50, -40, -30, -30, -30, -30, -40, -50,
	],
	ChessGame.BISHOP: [
		-20, -10, -10, -10, -10, -10, -10, -20,
		-10, 5, 0, 0, 0, 0, 5, -10,
		-10, 10, 10, 10, 10, 10, 10, -10,
		-10, 0, 10, 10, 10, 10, 0, -10,
		-10, 5, 5, 10, 10, 5, 5, -10,
		-10, 0, 5, 10, 10, 5, 0, -10,
		-10, 0, 0, 0, 0, 0, 0, -10,
		-20, -10, -10, -10, -10, -10, -10, -20,
	],
	ChessGame.ROOK: [
		0, 0, 0, 5, 5, 0, 0, 0,
		-5, 0, 0, 0, 0, 0, 0, -5,
		-5, 0, 0, 0, 0, 0, 0, -5,
		-5, 0, 0, 0, 0, 0, 0, -5,
		-5, 0, 0, 0, 0, 0, 0, -5,
		-5, 0, 0, 0, 0, 0, 0, -5,
		5, 10, 10, 10, 10, 10, 10, 5,
		0, 0, 0, 0, 0, 0, 0, 0,
	],
	ChessGame.QUEEN: [
		-20, -10, -10, -5, -5, -10, -10, -20,
		-10, 0, 5, 0, 0, 0, 0, -10,
		-10, 5, 5, 5, 5, 5, 0, -10,
		0, 0, 5, 5, 5, 5, 0, -5,
		-5, 0, 5, 5, 5, 5, 0, -5,
		-10, 0, 5, 5, 5, 5, 0, -10,
		-10, 0, 0, 0, 0, 0, 0, -10,
		-20, -10, -10, -5, -5, -10, -10, -20,
	],
	ChessGame.KING: [
		20, 30, 10, 0, 0, 10, 30, 20,
		20, 20, 0, 0, 0, 0, 20, 20,
		-10, -20, -20, -20, -20, -20, -20, -10,
		-20, -30, -30, -40, -40, -30, -30, -20,
		-30, -40, -40, -50, -50, -40, -40, -30,
		-30, -40, -40, -50, -50, -40, -40, -30,
		-30, -40, -40, -50, -50, -40, -40, -30,
		-30, -40, -40, -50, -50, -40, -40, -30,
	],
}

var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()

## Choose a move for `game`'s side to move. `depth` >= 1 = search plies; `blunder_chance` 0..1 = chance to play a
## random legal move instead (difficulty/personality). Returns an EMPTY dict ({}) when there is no legal move.
func choose_move(game: ChessGame, depth: int = 2, blunder_chance: float = 0.0) -> Dictionary:
	var work := game.clone()
	var moves := work.legal_moves()
	if moves.is_empty():
		return {}
	# A "blunder": ignore the search this turn and play a random legal move. Keeps a low-skill NPC beatable and
	# stops the opponent feeling like a flawless machine.
	if blunder_chance > 0.0 and rng.randf() < blunder_chance:
		return moves[rng.randi_range(0, moves.size() - 1)]
	# Score every root move with a FULL (-INF, INF) window so each returned score is EXACT — NOT a fail-soft
	# alpha-beta bound. With a narrow root window, a move whose reply triggers a beta cutoff returns only an UPPER
	# BOUND on its true value, which could let the tie-grouping below promote a move that is actually worse (by up
	# to a piece, not the intended half-pawn). The subtrees still prune internally, so the cost is only the root
	# ply. Then keep every move within ~half a pawn of the true best and pick one at random — variety across games
	# without weakening play (a deterministic argmax makes every match against this NPC identical).
	var d: int = maxi(1, depth)
	var scored: Array = []
	var best := -INF
	for m in _ordered(work, moves):
		work.make_move(m)
		var score := -_search(work, d - 1, -INF, INF, 1)
		work.undo_move()
		scored.append({"m": m, "s": score})
		best = maxf(best, score)
	var best_moves: Array = []
	for e in scored:
		if best - float(e.s) <= HALF_PAWN:
			best_moves.append(e.m)
	return best_moves[rng.randi_range(0, best_moves.size() - 1)]

## Negamax with alpha-beta. Returns the score RELATIVE to the side to move (positive = good for it). `ply` is the
## distance from the root, used only to prefer faster mates.
func _search(game: ChessGame, depth: int, alpha: float, beta: float, ply: int) -> float:
	var moves := game.legal_moves()
	if moves.is_empty():
		if game.is_in_check(game.side):
			return -(MATE - ply)          # checkmated: the sooner it happens (small ply), the worse -> avoid it
		return 0.0                          # stalemate = draw
	if depth <= 0:
		return _evaluate(game)
	var best := -INF
	for m in _ordered(game, moves):
		game.make_move(m)
		var score := -_search(game, depth - 1, -beta, -alpha, ply + 1)
		game.undo_move()
		if score > best:
			best = score
		if best > alpha:
			alpha = best
		if alpha >= beta:
			break                           # this line is already too good for the opponent to allow -> prune
	return best

## Order moves so likely-strong ones (captures, by victim value minus attacker value) come first — alpha-beta
## prunes far more when it sees good moves early. A cheap MVV-LVA-style key; not a full ordering scheme.
func _ordered(game: ChessGame, moves: Array) -> Array:
	var scored: Array = []
	for m in moves:
		var victim: int = game.board[m.to]
		var attacker: int = game.board[m.from]
		var key := 0.0
		if victim != ChessGame.EMPTY:
			key = VALUES[ChessGame.type_of(victim)] * 10.0 - VALUES[ChessGame.type_of(attacker)]
		if int(m.get("promo", 0)) != 0:
			key += VALUES[int(m.promo)]
		scored.append({"m": m, "k": key})
	scored.sort_custom(func(a, b): return a.k > b.k)
	var out: Array = []
	for e in scored:
		out.append(e.m)
	return out

## Static evaluation from the side-to-move's perspective (negamax convention). Sums material + piece-square for
## both colours (white positive), then flips the sign when Black is to move.
func _evaluate(game: ChessGame) -> float:
	var white_score := 0.0
	for s in 64:
		var p: int = game.board[s]
		if p == ChessGame.EMPTY:
			continue
		var v: float = VALUES[ChessGame.type_of(p)] + _pst_value(p, s)
		white_score += v if ChessGame.color_of(p) == ChessGame.WHITE else -v
	return white_score if game.side == ChessGame.WHITE else -white_score

## Piece-square bonus for `piece` on square `s`. Black reads the table mirrored top-to-bottom (rank 7-r), so both
## colours are rewarded for the same relative advancement.
func _pst_value(piece: int, s: int) -> float:
	var table: Array = PST.get(ChessGame.type_of(piece), [])
	if table.is_empty():
		return 0.0
	if ChessGame.color_of(piece) == ChessGame.WHITE:
		return float(table[s])
	var mirrored := ChessGame.sq(ChessGame.file_of(s), 7 - ChessGame.rank_of(s))
	return float(table[mirrored])
