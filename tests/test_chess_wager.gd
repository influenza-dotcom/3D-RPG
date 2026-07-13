extends GutTest

## Chess wager SETTLEMENT math (F-T5-1). The payout/forfeit logic is extracted onto ChessScreen as PURE STATIC
## helpers precisely so it can be unit-tested off-tree — no CanvasLayer, no _ready, no autoload, headless-safe.
## We call the statics directly through the preloaded script (no instantiation). The C20 regression this pins:
## an opponent-White table auto-plays move 1 into the log before the player replies, so a forfeit gated on the
## move log (not on a PLAYER move) charged the full stake just for opening + Esc. forfeit_delta now gates on the
## player's own move, so that path is free. ChessGame is a global class_name, so its enum is reachable off-tree.

const CS := preload("res://scripts/ui/chess_screen.gd")


# --- forfeit_delta: abandoning an undecided game -----------------------------------------------------------

func test_forfeit_is_free_in_a_friendly_game() -> void:
	assert_eq(CS.forfeit_delta(0, true), 0, "wager 0 (friendly) never forfeits, even after the player moved")

func test_forfeit_is_free_before_the_player_moves() -> void:
	# The C20 fix: leaving a wagered table you haven't replied to — including an opponent-White table whose AI has
	# already auto-played move 1 — costs nothing.
	assert_eq(CS.forfeit_delta(100, false), 0, "leaving before your first move is free (opponent-White auto-move must not arm the forfeit)")

func test_forfeit_charges_the_stake_after_the_player_moves() -> void:
	assert_eq(CS.forfeit_delta(100, true), -100, "moving then bailing forfeits the full stake")


# --- decided_delta: a game that reaches a result ----------------------------------------------------------

func test_decided_win_pays_the_stake() -> void:
	assert_eq(CS.decided_delta(ChessGame.Result.WHITE_WINS, ChessGame.WHITE, 100), 100, "White winning as White pays +wager")

func test_decided_loss_costs_the_stake() -> void:
	assert_eq(CS.decided_delta(ChessGame.Result.WHITE_WINS, ChessGame.BLACK, 100), -100, "White winning while you play Black costs -wager")

func test_decided_draw_is_even() -> void:
	assert_eq(CS.decided_delta(ChessGame.Result.STALEMATE, ChessGame.WHITE, 100), 0, "a draw settles even (no money changes hands)")

func test_decided_delta_is_free_in_a_friendly_game() -> void:
	assert_eq(CS.decided_delta(ChessGame.Result.WHITE_WINS, ChessGame.WHITE, 0), 0, "a friendly game (wager 0) never pays out")


# --- player_result_sign: the underlying +1/-1/0 classifier ------------------------------------------------

func test_player_result_sign_maps_win_loss_draw() -> void:
	assert_eq(CS.player_result_sign(ChessGame.Result.BLACK_WINS, ChessGame.BLACK), 1, "Black winning as Black is a win (+1)")
	assert_eq(CS.player_result_sign(ChessGame.Result.BLACK_WINS, ChessGame.WHITE), -1, "Black winning while you play White is a loss (-1)")
	assert_eq(CS.player_result_sign(ChessGame.Result.DRAW_50, ChessGame.WHITE), 0, "a 50-move draw is neither win nor loss (0)")
