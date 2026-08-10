class_name LedgerAccrual
extends Node

## Drop-in LEDGER BOOK-KEEPER — posts ONE period of interest on GameState.account at every WorldClock dawn.
## Savings grow, debt compounds; both come off the SAME signed field, so they are one branch and can never
## both run, drift to different periods, or need reconciling (EconomySettings.bank_interest_for).
##
## ⭐WHERE IT LIVES, AND WHY: authored as a child of scenes/player/Player.tscn.
##   * NOT a level component — GameRoot.load_level frees the level subtree but deliberately leaves the Player
##     alive, so a level-scoped copy would stop accruing on a level swap, and two levels each carrying one
##     would double-post.
##   * NOT an autoload — GameState and WorldClock are themselves autoloads, and this needs both to already
##     exist plus a live player to toast; riding the Player prefab guarantees EXACTLY ONE instance and NO
##     instance on the main menu, which closes the "interest ticks while you sit in the menu" leak with no
##     restore handshake.
##
## OFF-SWITCH: both rates at 0 -> inert (the RentCollector `rent_amount` convention).
##
## ⭐A SKIPPED TICK IS NEVER CAUGHT UP. Every posting is bounded to one period and every skip is in the
## player's favour — a deliberate, commented choice, not an oversight. Catching up would mean persisting a
## day counter, and the moment interest depends on a second stored number it can double-post across a reload.

func _ready() -> void:
	WorldClock.phase_changed.connect(_on_phase_changed)


## A WorldClock phase boundary — only DAWN (-> DAY) crossings post interest, mirroring RentCollector's
## day-counting so the two recurring systems can't disagree about what "a day" means.
func _on_phase_changed(new_phase: int) -> void:
	if new_phase == WorldClock.Phase.DAY:
		post_interest()


## Post ONE period of interest. Idempotent per dawn and safe to call directly from a test.
## Each gate is load-bearing:
##   * a dead / dying player — no toast over the black death frame, and no balance move during the reload
##     settlement window;
##   * GameState.reload_pending() — between a quickload's load_from_disk and the fresh GameRoot boot the OLD
##     player is still in-tree and every autosave is refused; a tick there would move a doomed balance;
##   * profile_active — a bare dev boot has no run to bill.
func post_interest() -> void:
	var player := get_parent() as Player
	if player == null or not GameState.profile_active or GameState.reload_pending():
		return
	if player.has_method(&"is_alive") and not player.is_alive():
		return
	var eco: EconomySettings = GameSettings.economy
	# ⭐ARREARS damage the RECORD, and they do it whether or not the interest posting itself clears the
	# minimum — a debt too small to accrue a coin is still a debt you have not paid, and letting it sit
	# consequence-free would make "keep a token balance forever" the correct play.
	if GameState.account < 0.0:
		GameState.add_credit_standing(-maxf(0.0, eco.credit_standing_arrears_per_day))
	var delta := EconomySettings.bank_interest_for(GameState.account,
			eco.bank_debt_interest_rate, eco.bank_savings_interest_rate, eco.bank_interest_min_posting)
	if is_zero_approx(delta):
		return
	GameState.account = snappedf(GameState.account + delta, Zorkmids.QUANTUM)
	GameState.autosave_world_state()  # the wallet didn't move, so queue our own coalesced write
	if player.has_method(&"notify_toast"):
		player.notify_toast(PlayerText.ledger_interest(delta),
			MenuStyle.danger() if delta < 0.0 else MenuStyle.gold())
