extends GutTest

## THE POINT OF SALE — the pieces that sit between the payment rails and a till:
##   • `Character.quote` / `Player.quote` — the two-part price quote a screen paints so the SERVICE CHARGE is
##     visible at the point of sale instead of hidden inside one opaque total.
##   • `Merchant.accepts_ledger` — the CASH-ONLY vendor. A fence or a vending machine takes coins in hand and
##     nothing else: no savings, no credit line, no service charge, and no way to deepen a debt.
##
## ⭐THE INVARIANT UNDER TEST is the one the whole payment seam exists for: ONE predicate feeds both the gate and
## the display. Here that predicate is the MERCHANT's (`can_afford`), not the player's, because a cash-only
## vendor sees less money than the player has. If ShopScreen dimmed on `player.can_pay` while `Merchant.buy`
## gated on `can_afford`, a solvent-looking row would be refused at the till.
##
## GameState is an AUTOLOAD, so the account and the armed rail are shared mutable state — snapshot/restore them
## exactly as test_payment.gd does, or a balance left behind here makes some other file's "broke" player rich.

const PLAYER_PATH := "res://scripts/player/player.gd"
const CHARACTER_PATH := "res://scripts/player/character.gd"

var _prev_account: float
var _prev_method: String
var _prev_profile: bool


func before_each() -> void:
	_prev_account = GameState.account
	_prev_method = GameState.payment_method
	_prev_profile = GameState.profile_active
	GameState.account = 0.0
	GameState.payment_method = "debit"


func after_each() -> void:
	GameState.account = _prev_account
	GameState.payment_method = _prev_method
	GameState.profile_active = _prev_profile


## A bare off-tree Player with a known stat sheet so credit_limit() is deterministic. NEVER added to the tree —
## its _ready wants the whole prefab.
func _player(cash: float) -> Variant:
	var p = load(PLAYER_PATH).new()
	p.money = cash
	var sheet := CharacterStats.new()
	sheet.gunplay = 10
	sheet.strength = 10
	sheet.endurance = -5
	sheet.agility = -5
	sheet.streetwise = -5
	sheet.larceny = -5
	p.stats = sheet
	return p

func _fee() -> float:
	return GameSettings.economy.bank_noncash_fee_fraction


# --- The two-part quote ---------------------------------------------------------------------------------------

func test_plain_character_quote_has_no_rail_and_no_fee() -> void:
	# A plain wallet has nowhere to draw from but cash, so the quote degrades to "the price is the price".
	var npc = load(CHARACTER_PATH).new()
	npc.money = 100.0
	var q: Dictionary = npc.quote(40.0)
	assert_eq(q["base"], 40.0, "base is the sticker price")
	assert_eq(q["fee"], 0.0, "a plain wallet is never charged a service fee")
	assert_eq(q["total"], 40.0, "so the total IS the base")
	assert_eq(q["rail"], 0.0, "a plain Character has no rail to draw on")
	assert_true(q["ok"], "and it can afford this")
	npc.free()

func test_all_cash_purchase_quotes_no_fee() -> void:
	# Cash is fee-free, so a purchase covered entirely by coins in hand must quote total == base. This is what
	# makes carrying cash the cheapest way to buy.
	var p = _player(100.0)
	var q: Dictionary = p.quote(40.0)
	assert_eq(q["cash"], 40.0, "the whole price comes out of cash")
	assert_eq(q["rail"], 0.0, "nothing falls to the account")
	assert_eq(q["fee"], 0.0, "so there is no service charge")
	assert_eq(q["total"], 40.0, "the quoted total is the sticker price")
	p.free()

func test_quote_splits_cash_and_rail_and_charges_the_fee_on_the_rail_only() -> void:
	# 30 cash against a 100 price: 70 has to come off the account, and ONLY that 70 is feeable.
	var p = _player(30.0)
	GameState.account = 500.0
	var q: Dictionary = p.quote(100.0)
	assert_eq(q["cash"], 30.0, "cash goes first — it is fee-free and earns nothing")
	assert_eq(q["rail"], 70.0, "the remainder falls to the account")
	assert_almost_eq(float(q["fee"]), 70.0 * _fee(), 0.01,
		"the fee is charged on the ACCOUNT portion only, not the whole price")
	assert_almost_eq(float(q["total"]), 100.0 + 70.0 * _fee(), 0.01, "total = base + fee")
	p.free()

func test_the_quote_s_parts_are_what_the_till_actually_takes() -> void:
	# The quote is what a point-of-sale label paints ("100 zm + fee"). Its parts must be the money that really moves:
	# `cash` out of the wallet, `rail` + `fee` off the account, `total` in all.
	var p = _player(30.0)
	GameState.account = 500.0
	var q: Dictionary = p.quote(100.0)
	assert_true(p.charge(100.0), "precondition: 30 cash + 500 savings covers a 100 price")
	assert_almost_eq(30.0 - float(p.money), float(q["cash"]), 0.001,
		"the wallet paid exactly the quote's cash portion")
	assert_almost_eq(500.0 - GameState.account, float(q["rail"]) + float(q["fee"]), 0.001,
		"the account paid exactly the quote's rail portion plus its service charge — the fee on the label is the fee charged")
	assert_almost_eq((30.0 - float(p.money)) + (500.0 - GameState.account), float(q["total"]), 0.001,
		"everything that left the player adds up to the quoted total")
	p.free()

func test_the_quote_s_ok_predicts_the_till_to_the_last_coin() -> void:
	# A label that says 'affordable' must be served, and one that says 'too dear' must be refused having moved
	# nothing — right at the edge, where the service charge decides it.
	var probe = _player(30.0)
	GameState.account = 500.0
	var needed: float = float(probe.quote(100.0)["total"]) - 30.0  # what the account must hold, fee included
	probe.free()

	var exact = _player(30.0)
	GameState.account = needed
	assert_true(bool(exact.quote(100.0)["ok"]), "savings that exactly cover the rail + fee quote as affordable")
	assert_true(exact.charge(100.0), "...and the till serves that quote")
	assert_almost_eq(GameState.account, 0.0, 0.001, "...spending the account down to exactly zero")
	exact.free()

	var short = _player(30.0)
	GameState.account = snappedf(needed - Zorkmids.QUANTUM, Zorkmids.QUANTUM)
	assert_false(bool(short.quote(100.0)["ok"]), "one coin short of the fee, the quote must say no")
	assert_false(short.charge(100.0), "...and the till must refuse it")
	assert_eq(short.money, 30.0, "...having taken no cash")
	assert_almost_eq(GameState.account, snappedf(needed - Zorkmids.QUANTUM, Zorkmids.QUANTUM), 0.001,
		"...and nothing off the account")
	short.free()

func test_free_service_quotes_clean_for_a_debtor() -> void:
	# A free service must clear whatever the wallet or the debt looks like — the free-respec-refused-while-negative
	# class of bug.
	var p = _player(0.0)
	GameState.account = -900.0
	var q: Dictionary = p.quote(0.0)
	assert_true(q["ok"], "a free service always clears, even deep in debt")
	assert_eq(q["total"], 0.0, "and costs nothing")
	p.free()


# --- The cash-only vendor -------------------------------------------------------------------------------------

func _merchant(takes_ledger: bool) -> Merchant:
	var m := Merchant.new()  # never add_child: _ready is not what we're testing
	m.accepts_ledger = takes_ledger
	return m

func test_ledger_vendor_sees_savings() -> void:
	var m := _merchant(true)
	var p = _player(10.0)
	GameState.account = 500.0
	assert_true(m.can_afford(100.0, p), "a ledger vendor lets the account cover what cash can't")
	m.free()
	p.free()

func test_cash_only_vendor_ignores_savings() -> void:
	var m := _merchant(false)
	var p = _player(10.0)
	GameState.account = 5000.0  # a fortune the fence cannot see
	assert_false(m.can_afford(100.0, p),
		"a cash-only vendor must not count banked savings — coins in hand only")
	assert_true(m.can_afford(10.0, p), "...but it will happily take the cash that IS in hand")
	m.free()
	p.free()

func test_cash_only_vendor_ignores_the_credit_line() -> void:
	var m := _merchant(false)
	var p = _player(10.0)
	GameState.payment_method = "credit"
	GameState.profile_active = true
	assert_false(m.can_afford(100.0, p),
		"arming CREDIT must not make a cash-only vendor extend credit")
	m.free()
	p.free()

func test_cash_only_payment_never_touches_the_account() -> void:
	# The structural point: a cash-only sale cannot draw savings and cannot deepen a debt.
	var m := _merchant(false)
	var p = _player(100.0)
	GameState.account = 250.0
	assert_true(m.take_payment(40.0, p), "the sale clears from cash")
	assert_eq(p.money, 60.0, "cash paid the whole price")
	assert_eq(GameState.account, 250.0, "the ledger account is untouched by a cash-only vendor")
	m.free()
	p.free()

func test_cash_only_payment_is_fail_closed() -> void:
	var m := _merchant(false)
	var p = _player(30.0)
	GameState.account = 5000.0
	assert_false(m.take_payment(100.0, p), "an unaffordable cash-only sale is refused")
	assert_eq(p.money, 30.0, "...having moved NOTHING — no partial draw")
	assert_eq(GameState.account, 5000.0, "...and without touching the account")
	m.free()
	p.free()

func test_cash_only_vendor_quotes_no_service_charge() -> void:
	# The fee exists because the ACCOUNT funded the purchase. A cash-only vendor never uses the account, so its
	# quoted total is always the sticker price.
	var m_cash := _merchant(false)
	var m_ledger := _merchant(true)
	var p = _player(0.0)
	GameState.account = 5000.0
	assert_eq(m_cash.quoted_total(100.0, p), 100.0, "a cash-only vendor's total is the sticker price")
	assert_gt(m_ledger.quoted_total(100.0, p), 100.0,
		"...while a ledger-funded buy carries the account's service charge")
	m_cash.free()
	m_ledger.free()
	p.free()

func test_an_authored_merchant_takes_the_ledger_unless_told_otherwise() -> void:
	# Existing authored merchants have no `accepts_ledger` in their .tres/.tscn, so the default decides their
	# behaviour. Built bare (the field never touched), a merchant must let savings pay, or every shop in the game
	# silently becomes cash-only.
	var m := Merchant.new()
	var p = _player(10.0)
	GameState.account = 500.0
	assert_true(m.can_afford(100.0, p), "a merchant authored without accepts_ledger must count banked savings")
	assert_true(m.take_payment(100.0, p), "...and ring the sale up")
	assert_lt(GameState.account, 500.0, "...drawing the shortfall from the account")
	m.free()
	p.free()

func test_gate_and_display_read_the_same_predicate() -> void:
	# ⭐The whole point. Walk a price range across both vendor kinds and assert can_afford never disagrees with
	# what take_payment actually does — a row can never look dead while the till would serve it, or the reverse —
	# and that a served row costs exactly the quoted_total it painted.
	for takes_ledger in [true, false]:
		for price in [0.0, 5.0, 25.0, 60.0, 100.0, 400.0]:
			var m := _merchant(takes_ledger)
			var p = _player(50.0)
			GameState.account = 100.0
			var shown: bool = m.can_afford(price, p)
			var shown_total: float = m.quoted_total(price, p)
			var before: float = p.money + GameState.account
			var took: bool = m.take_payment(price, p)
			var moved: float = before - (p.money + GameState.account)
			assert_eq(took, shown,
				"vendor(ledger=%s) price %s: the display predicate and the till must agree" % [takes_ledger, price])
			assert_almost_eq(moved, shown_total if took else 0.0, 0.001,
				"vendor(ledger=%s) price %s: a sale takes exactly the total the row showed; a refusal takes nothing"
				% [takes_ledger, price])
			m.free()
			p.free()


# --- The prefab -----------------------------------------------------------------------------------------------

func test_atm_prefab_wires_an_atm_with_a_collider() -> void:
	# The world-side terminal a designer drops into a level. Without a CollisionShape3D the Area3D never
	# receives the interaction ray and the terminal is invisible to the player.
	var ps := load("res://scenes/components/atm.tscn") as PackedScene
	assert_not_null(ps, "scenes/components/atm.tscn must load")
	var state := ps.get_state()
	var names: Array = []
	for i in range(state.get_node_count()):
		names.append(state.get_node_name(i))
	assert_true(names.has("CollisionShape3D"), "the ATM prefab needs a CollisionShape3D to be interactable")
	var inst := ps.instantiate()
	assert_true(inst is Atm, "the prefab root must actually be an Atm")
	inst.free()
