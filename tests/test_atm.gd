extends GutTest

## THE LEDGER TERMINAL — the `Atm` component's two transactions, the `LedgerAccrual` interest posting, the
## `CreditWatch` announcer, and the banking fields' save round-trip.
##
## ⭐THE ONE IDEA EVERYTHING BELOW RESTS ON: `GameState.account` is a SINGLE SIGNED number — positive is
## savings, negative is what you owe — so DEPOSITING against a negative balance IS repaying the debt. There is
## no third verb and no second ledger, which is why "pay off your debt" needs no code of its own and why you
## can never hold death-safe savings WHILE owing.
##
## The components are driven off-tree (`.new()`, never `_ready`) with a bare Player as the host. GameState is
## an AUTOLOAD, so every test snapshots and restores the banking fields (the test_start_menu Settings idiom):
## leaving a balance behind would silently make a "broke" player solvent in some other suite.

const PLAYER_PATH := "res://scripts/player/player.gd"
const ATM_PATH := "res://scripts/components/atm.gd"
const ACCRUAL_PATH := "res://scripts/components/ledger_accrual.gd"
const WATCH_PATH := "res://scripts/components/credit_watch.gd"

var _prev_account: float
var _prev_method: String
var _prev_standing: float
var _prev_profile: bool


func before_each() -> void:
	_prev_account = GameState.account
	_prev_method = GameState.payment_method
	_prev_standing = GameState.credit_standing
	_prev_profile = GameState.profile_active
	GameState.account = 0.0
	GameState.payment_method = "debit"
	GameState.credit_standing = 0.0
	GameState.profile_active = true  # the accrual/announce gates require a real run


func after_each() -> void:
	GameState.account = _prev_account
	GameState.payment_method = _prev_method
	GameState.credit_standing = _prev_standing
	GameState.profile_active = _prev_profile


## A bare off-tree Player. ALIVE (hp > 0) because the accrual and announcer both refuse to touch a dead one.
## Never added to the tree — its _ready wants the whole prefab (CLAUDE.md).
func _player(cash: float) -> Variant:
	var p = load(PLAYER_PATH).new()
	p.money = cash
	p.max_hp = 100.0
	p.hp = 100.0
	return p


func _atm() -> Variant:
	return load(ATM_PATH).new()


# --- DEPOSIT (which is also how you repay) -----------------------------------------------------------------

func test_deposit_moves_cash_into_the_account() -> void:
	var atm = _atm()
	var p = _player(100.0)
	assert_eq(atm.deposit(p, 40.0), 40.0, "deposit returns what actually moved")
	assert_eq(p.money, 60.0, "…debited from the wallet")
	assert_eq(GameState.account, 40.0, "…and credited to the account")
	atm.free()
	p.free()


func test_deposit_is_clamped_to_cash_actually_carried() -> void:
	# ⭐You cannot deposit money you do not physically have. Without this clamp a debtor could "deposit" their
	# way to a positive balance out of nothing — minting money (the LootScreen deposit precedent).
	var atm = _atm()
	var p = _player(30.0)
	assert_eq(atm.deposit(p, 5000.0), 30.0, "an over-large deposit is clamped to the cash on hand")
	assert_eq(p.money, 0.0, "…which empties the wallet exactly")
	assert_eq(GameState.account, 30.0, "…and banks exactly what was carried")
	atm.free()
	p.free()


func test_a_broke_player_deposits_nothing() -> void:
	var atm = _atm()
	var p = _player(0.0)
	GameState.account = -200.0
	assert_eq(atm.deposit(p, 100.0), 0.0, "with no cash, nothing moves")
	assert_eq(GameState.account, -200.0, "…and the debt is NOT deepened by a failed deposit")
	atm.free()
	p.free()


func test_depositing_against_a_debt_IS_repayment() -> void:
	# THE headline behaviour: one signed field means settling and depositing are the same operation.
	var atm = _atm()
	var p = _player(100.0)
	GameState.account = -240.0
	assert_eq(atm.deposit(p, 100.0), 100.0, "the deposit goes through while in the red")
	assert_eq(GameState.account, -140.0, "…and moves the balance TOWARD zero — that is the repayment")
	atm.free()
	p.free()


func test_overpaying_a_debt_leaves_the_remainder_banked() -> void:
	var atm = _atm()
	var p = _player(400.0)
	GameState.account = -100.0
	atm.deposit(p, 400.0)
	assert_eq(GameState.account, 300.0,
		"paying 400 against a 100 debt clears it and banks the other 300 — one field, one subtraction")
	atm.free()
	p.free()


# --- WITHDRAW ----------------------------------------------------------------------------------------------

func test_withdraw_moves_savings_into_the_pocket() -> void:
	var atm = _atm()
	var p = _player(0.0)
	GameState.account = 300.0
	assert_eq(atm.withdraw(p, 120.0), 120.0, "withdraw returns what moved")
	assert_eq(p.money, 120.0, "…into the wallet")
	assert_eq(GameState.account, 180.0, "…out of the account")
	atm.free()
	p.free()


func test_withdraw_can_never_become_a_cash_advance() -> void:
	# ⭐THE anti-arbitrage guard, and the reason it is a single clamp: if the credit line could be drawn as
	# CASH, a player could withdraw it, redeposit it as "savings", and collect interest on borrowed money.
	# Credit funds PURCHASES, never cash.
	var atm = _atm()
	var p = _player(0.0)
	GameState.account = -240.0
	GameState.payment_method = "credit"
	assert_eq(atm.withdraw(p, 100.0), 0.0, "a debtor has nothing positive to draw, whatever their line")
	assert_eq(p.money, 0.0, "…so no cash appears")
	assert_eq(GameState.account, -240.0, "…and the debt is unchanged")
	atm.free()
	p.free()


func test_withdraw_is_clamped_to_the_positive_balance() -> void:
	var atm = _atm()
	var p = _player(0.0)
	GameState.account = 50.0
	assert_eq(atm.withdraw(p, 5000.0), 50.0, "an over-large withdrawal is clamped to the balance")
	assert_eq(GameState.account, 0.0, "…emptying the account exactly, never past zero into credit")
	atm.free()
	p.free()


func test_a_terminal_can_refuse_either_service() -> void:
	# Per-machine authoring: a withdrawal-only cash machine, or a deposit-only night safe.
	var atm = _atm()
	var p = _player(100.0)
	GameState.account = 100.0
	atm.allows_deposit = false
	assert_eq(atm.deposit(p, 10.0), 0.0, "a terminal with deposits off refuses them")
	atm.allows_deposit = true
	atm.allows_withdraw = false
	assert_eq(atm.withdraw(p, 10.0), 0.0, "…and one with withdrawals off refuses those")
	assert_eq(p.money, 100.0, "neither refusal moved anything")
	assert_eq(GameState.account, 100.0, "…on either side")
	atm.free()
	p.free()


func test_transactions_are_free_in_both_directions() -> void:
	# ⭐Deliberate: the counterweight is a fee on PURCHASES funded from the account, not on banking itself.
	# Charge both ends and "withdraw then pay cash" converges with "pay by debit", collapsing the decision.
	var atm = _atm()
	var p = _player(100.0)
	atm.deposit(p, 100.0)
	atm.withdraw(p, 100.0)
	assert_eq(p.money, 100.0, "a round trip through the terminal costs nothing")
	assert_eq(GameState.account, 0.0, "…and leaves the account exactly where it started")
	atm.free()
	p.free()


# --- STANDING: the earned half of the credit score ---------------------------------------------------------

func test_repaying_debt_builds_the_record() -> void:
	var atm = _atm()
	var p = _player(100.0)
	GameState.account = -300.0
	atm.deposit(p, 100.0)
	assert_almost_eq(GameState.credit_standing,
		100.0 * GameSettings.economy.credit_standing_per_zm_repaid, 0.001,
		"standing rises with the zorkmids actually put against the debt — this is the payment history")
	atm.free()
	p.free()


func test_clearing_a_debt_pays_a_bonus() -> void:
	var atm = _atm()
	var p = _player(250.0)
	GameState.account = -100.0
	atm.deposit(p, 250.0)
	var eco: EconomySettings = GameSettings.economy
	assert_almost_eq(GameState.credit_standing,
		100.0 * eco.credit_standing_per_zm_repaid + eco.credit_standing_debt_cleared, 0.001,
		"clearing the balance outright adds the one-off bonus ON TOP of the per-zorkmid credit")
	atm.free()
	p.free()


func test_saving_is_not_creditworthiness() -> void:
	# ⭐Only the portion that RETIRES DEBT scores. Otherwise a rich player could buy a spotless record without
	# ever borrowing a zorkmid, which is neither satire nor a mechanic.
	var atm = _atm()
	var p = _player(500.0)
	GameState.account = 1000.0
	atm.deposit(p, 500.0)
	assert_eq(GameState.credit_standing, 0.0,
		"depositing into an already-positive account earns NO standing — that is saving, not repayment")
	atm.free()
	p.free()


func test_the_record_is_clamped_in_both_directions() -> void:
	var cap: float = GameSettings.economy.credit_standing_max
	GameState.credit_standing = 0.0
	GameState.add_credit_standing(99999.0)
	assert_eq(GameState.credit_standing, cap, "a spotless record tops out at credit_standing_max")
	GameState.add_credit_standing(-999999.0)
	assert_eq(GameState.credit_standing, -cap, "…and the worst record bottoms out at its mirror")
	assert_eq(GameState.add_credit_standing(50.0), 50.0, "the mutator returns what actually moved")
	assert_eq(GameState.add_credit_standing(0.0), 0.0, "…and a zero delta is a no-op")


# --- INTEREST ----------------------------------------------------------------------------------------------

func test_interest_posts_on_the_signed_balance() -> void:
	var p = _player(0.0)
	var accrual = load(ACCRUAL_PATH).new()
	p.add_child(accrual)
	GameState.account = 1000.0
	accrual.post_interest()
	assert_gt(GameState.account, 1000.0, "a positive balance EARNS on a posting")
	GameState.account = -1000.0
	accrual.post_interest()
	assert_lt(GameState.account, -1000.0, "…and a negative one grows what is owed")
	p.free()


func test_arrears_damage_the_record_even_below_the_posting_floor() -> void:
	# ⭐A debt too small to accrue a coin is still a debt you have not paid. Without this, parking a token
	# balance forever would be consequence-free — the obvious exploit against a min-posting floor.
	var p = _player(0.0)
	var accrual = load(ACCRUAL_PATH).new()
	p.add_child(accrual)
	GameState.credit_standing = 20.0
	GameState.account = -0.5  # far under bank_interest_min_posting
	accrual.post_interest()
	assert_lt(GameState.credit_standing, 20.0,
		"sitting in arrears costs standing even when the interest itself rounds away to nothing")
	p.free()


func test_a_solvent_account_never_loses_standing() -> void:
	var p = _player(0.0)
	var accrual = load(ACCRUAL_PATH).new()
	p.add_child(accrual)
	GameState.credit_standing = 20.0
	GameState.account = 400.0
	accrual.post_interest()
	assert_eq(GameState.credit_standing, 20.0, "a solvent player is never marked down for the passage of time")
	p.free()


func test_interest_refuses_to_move_a_doomed_or_dead_balance() -> void:
	# Each gate is load-bearing: no billing over the black death frame, and nothing moved between a quickload
	# reading the save and the fresh scene booting (that balance is about to be thrown away).
	var p = _player(0.0)
	var accrual = load(ACCRUAL_PATH).new()
	p.add_child(accrual)
	GameState.account = -1000.0
	p.hp = 0.0
	accrual.post_interest()
	assert_eq(GameState.account, -1000.0, "a dead player is not billed")
	p.hp = 100.0
	GameState.profile_active = false
	accrual.post_interest()
	assert_eq(GameState.account, -1000.0, "…and a bare dev boot has no run to bill")
	p.free()


# --- THE ANNOUNCER -----------------------------------------------------------------------------------------

func test_the_first_reading_primes_silently() -> void:
	# ⭐A spawn, a level change and a load all start here. None of them may announce the score the player
	# already had — only a movement DURING play is worth a toast.
	var p = _player(0.0)
	var watch = load(WATCH_PATH).new()
	p.add_child(watch)
	assert_eq(watch._last_score, -1, "it starts unprimed")
	watch._check()
	assert_gt(watch._last_score, 0, "the first check adopts the current score")
	p.free()


func test_a_movement_under_the_threshold_is_not_announced() -> void:
	# A single headshot is a fraction of a point at the shipped rates; announcing per event would be either
	# silent or a spam wall, so the announcer only speaks when the INTEGER score moves.
	var p = _player(0.0)
	var watch = load(WATCH_PATH).new()
	p.add_child(watch)
	watch._check()
	var primed: int = watch._last_score
	GameState.add_credit_standing(GameSettings.economy.credit_standing_per_headshot)
	watch._check()
	assert_eq(watch._last_score, primed, "one headshot does not move the announced score")
	p.free()


func test_the_announcer_is_inert_at_a_zero_interval() -> void:
	var p = _player(0.0)
	var watch = load(WATCH_PATH).new()
	p.add_child(watch)
	watch.poll_interval = 0.0
	watch._process(999.0)
	assert_eq(watch._last_score, -1, "poll_interval 0 is the off-switch — it never even primes")
	p.free()


# --- PERSISTENCE -------------------------------------------------------------------------------------------

func test_the_banking_fields_round_trip_through_a_save() -> void:
	var path := "user://test_atm_roundtrip.cfg"
	GameState.account = -137.5
	GameState.payment_method = "credit"
	GameState.credit_standing = 42.25
	assert_eq(GameState.save_to_disk(path), OK, "the profile writes")
	GameState.account = 0.0
	GameState.payment_method = "debit"
	GameState.credit_standing = 0.0
	assert_true(GameState.load_from_disk(path), "…and reads back")
	assert_eq(GameState.account, -137.5, "the signed account survives, debt and all")
	assert_eq(GameState.payment_method, "credit", "the armed rail survives as its KEY")
	assert_eq(GameState.credit_standing, 42.25, "…and so does the earned record")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_pre_atm_save_folds_its_negative_wallet_onto_the_account() -> void:
	# ⭐Saves written BEFORE the ATM carried the implant debt as a NEGATIVE WALLET. The wallet is cash-only
	# now, so a negative one can only be that legacy debt — move it where the terminal can actually repay it.
	# Idempotent by construction, which is exactly why this needed no SAVE_VERSION bump.
	var path := "user://test_atm_legacy.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", GameState.SAVE_VERSION)
	cfg.set_value("player", "money", -250.0)  # the old shape: debt hiding in the wallet
	assert_eq(cfg.save(path), OK, "the legacy-shaped save writes")
	assert_true(GameState.load_from_disk(path), "…and loads")
	assert_eq(GameState.money, 0.0, "the negative wallet is emptied — cash can no longer be negative")
	assert_eq(GameState.account, -250.0, "…and the debt now lives on the account, where it is repayable")
	# Idempotence: saving and reloading must not fold a second time.
	assert_eq(GameState.save_to_disk(path), OK, "re-saving the folded profile")
	assert_true(GameState.load_from_disk(path), "…and reloading it")
	assert_eq(GameState.account, -250.0, "the fold ran exactly once — it can never double-charge a debt")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_new_game_starts_with_a_clean_ledger() -> void:
	GameState.account = -999.0
	GameState.payment_method = "credit"
	GameState.credit_standing = -50.0
	GameState.reset_for_new_game()
	assert_eq(GameState.account, 0.0, "a fresh run owes nothing and has nothing banked")
	assert_eq(GameState.payment_method, "debit", "…spends its own money by default")
	assert_eq(GameState.credit_standing, 0.0,
		"…and has NO record, so New Game rates the build alone (credit_rating_for defaults standing to 0)")
