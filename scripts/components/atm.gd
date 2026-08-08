@tool
class_name Atm
extends LookAtInteractable

## @system Economy
## @seam deposit()/withdraw() are the ONLY writers of GameState.account outside LedgerAccrual; both are
##   self-guarding and callable off-tree, so AtmScreen stays a pure view with no rules of its own.
## @risk A deposit path that does not clamp to maxf(0.0, player.money) lets a debtor mint money.
## @risk A withdraw path that does not clamp to maxf(0.0, GameState.account) opens a cash advance — and with it
##   the draw-the-line / redeposit / earn-savings-interest arbitrage that the single clamp closes today.
## @test res://tests/test_atm.gd
##
## Drop-in LEDGER TERMINAL, dual-mode like Merchant / Healer / Bonfire:
##   1. STANDALONE (a wall terminal, a lobby kiosk): leave standalone on — aim + Interact to bank.
##   2. ON A DIALOGUE NPC: set standalone = false; the NPC's dialogue offers a "Bank" option.
##
## ⭐THE ACCOUNT IS ONE SIGNED NUMBER (GameState.account): positive is savings, negative is what you owe. So
## DEPOSITING against a negative balance IS paying your debt down — there is no third verb and no second
## ledger, and the screen only swaps a caption. Three things fall out of that one decision:
##   * You can never hold a death-safe hoard WHILE owing (every deposit is eaten by the debt until you are
##     solvent), so "buy on credit, bank the profit, then die" is unrepresentable rather than patched.
##   * The account lives ONLY on GameState — never mirrored onto a Character, never read by capture() — so
##     Player._ready has nothing to re-seed and the reboot that killed an earlier transient debt field cannot
##     happen here.
##   * Death touches only Character.money, so banked money is death-safe with ZERO code saying so.
##
## SETUP: drop it under the terminal prop (or assign highlight_target), size its CollisionShape3D, name it.
## Deposits and withdrawals are FREE in both directions on purpose — the counterweight is the service charge
## on PURCHASES funded from the account (GameSettings.economy.bank_noncash_fee_fraction), which is what keeps
## cash you already carry the cheapest way to buy.

@export var station_name: String = ""   ## hover + screen title; blank -> "Ledger Terminal"
## ON = a self-serve kiosk: aim + Interact opens the terminal directly. OFF = drive it from a dialogue NPC's
## "Bank" option instead (the station stops responding to direct interaction).
@export var standalone: bool = true
## Per-machine multiplier on the GLOBAL purchase fee, so terminal PLACEMENT becomes a design lever instead of
## a chore: 0.0 = a free public kiosk, 2.0 = a gouging machine somewhere convenient. Read by AtmScreen for its
## quoted rate line. (Purchases themselves read the global knob — a fee that changed with which terminal you
## last stood at would be unquotable at the point of sale.)
@export var fee_multiplier: float = 1.0

@export_group("Services")
## OFF = this terminal refuses deposits (a withdrawal-only cash machine).
@export var allows_deposit: bool = true
## OFF = this terminal refuses withdrawals (a deposit-only night safe).
@export var allows_withdraw: bool = true


## Editor warning: a standalone terminal on a dialogue NPC steals the interaction ray from the NPC's Talkable.
func _get_configuration_warnings() -> PackedStringArray:
	if standalone and _on_dialogue_host():
		return PackedStringArray([
			"`standalone` is on but this Atm is a child of a dialogue NPC — its talk-layer hitbox steals the interaction ray from the NPC's Talkable. Set `standalone` = false and open it from the dialogue's \"Bank\" option.",
		])
	return PackedStringArray()


func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_fit_hitbox()  # preview the auto-fit hitbox in-editor (resizes an existing collider; safe)
		return  # @tool: only _get_configuration_warnings runs in-editor; hitbox/outline setup is runtime-only
	collision_layer = TalkHelpers.TALK_LAYER if standalone else 0
	collision_mask = 0
	_build_outline()
	if auto_fit_collider:
		_fit_hitbox_to_host()


# --- Transactions — the ONLY writers of GameState.account outside the interest posting -------------------

## Move `amount` from the player's POCKET into the account. Returns what actually moved (0.0 = nothing).
## ⭐Clamped to cash ON HAND: you cannot deposit money you do not physically carry, so a broke player deposits
## nothing rather than digging the debt deeper (the LootScreen._deposit_coins_to_source precedent).
## Against a NEGATIVE balance this IS the debt repayment — same code, the caption is all that changes.
func deposit(player_node: Node, amount: float) -> float:
	var player := player_node as Player
	if player == null or not allows_deposit:
		return 0.0
	var n := snappedf(clampf(amount, 0.0, maxf(0.0, player.money)), Zorkmids.QUANTUM)
	if n <= 0.0 or n < GameSettings.economy.bank_min_transaction:
		return 0.0
	var owed_before := maxf(0.0, -GameState.account)
	var was_owed := owed_before > 0.0
	# Ledger FIRST, wallet LAST: add_money's money_changed rides the one-frame-deferred autosave, so the single
	# write it queues already sees both halves of the transfer (the LevelUp "charge LAST" precedent).
	GameState.account = snappedf(GameState.account + n, Zorkmids.QUANTUM)
	player.add_money(-n)
	# ⭐PAYMENT HISTORY — the earned half of the credit score. Only the portion that actually RETIRED DEBT
	# counts: paying into an already-positive account is saving, not creditworthiness, and rewarding it would
	# let a rich player buy a perfect record without ever borrowing. Clearing the balance outright pays a
	# one-off bonus on top (the satisfying part, and the thing a real score rewards most).
	var eco: EconomySettings = GameSettings.economy
	var repaid := minf(n, owed_before)
	if repaid > 0.0:
		GameState.add_credit_standing(repaid * maxf(0.0, eco.credit_standing_per_zm_repaid))
		if GameState.account >= 0.0:  # the debt is gone, not merely smaller
			GameState.add_credit_standing(maxf(0.0, eco.credit_standing_debt_cleared))
	GameState.autosave(player)  # a banking transaction is a milestone (the Bonfire / RespecStation convention)
	if player.has_method(&"notify_toast"):
		player.notify_toast(PlayerText.atm_deposited(n, was_owed), Color(0.6, 0.85, 1.0))
	return n


## Move `amount` from the account into the player's pocket. Returns what actually moved.
## ⭐Clamped to maxf(0.0, account): you can NEVER withdraw into credit. That single clamp is the whole
## anti-arbitrage guard — the credit line funds PURCHASES, never cash, so there is no "draw the line as cash,
## redeposit it, collect savings interest" loop and no cash-advance feature that would need balancing.
## Deliberately NOT blocked while in debt: a debtor simply has nothing positive to draw.
func withdraw(player_node: Node, amount: float) -> float:
	var player := player_node as Player
	if player == null or not allows_withdraw:
		return 0.0
	var n := snappedf(clampf(amount, 0.0, maxf(0.0, GameState.account)), Zorkmids.QUANTUM)
	if n <= 0.0 or n < GameSettings.economy.bank_min_transaction:
		return 0.0
	GameState.account = snappedf(GameState.account - n, Zorkmids.QUANTUM)
	player.add_money(n)
	GameState.autosave(player)
	if player.has_method(&"notify_toast"):
		player.notify_toast(PlayerText.atm_withdrew(n), Color(0.6, 0.85, 1.0))
	return n


# --- Talk-handler surface (mirrors Healer / LevelUp / RespecStation) -------------------------------------

## Hover readout: the configured name, else the default terminal label.
func look_name() -> String:
	return PlayerText.atm_prompt(station_name)


## Always interactable — a terminal with both services off still shows you the statement.
func can_be_talked_to() -> bool:
	return true


## Aim + Interact (standalone only) opens the terminal over the paused world.
func start_talk(player: Node) -> void:
	if player == null:
		return
	AtmScreen.open_atm(self, player)
