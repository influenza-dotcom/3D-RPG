extends GutTest

## GUT suite for the fractional-zorkmid money helpers: Zorkmids (scripts/items/zorkmids.gd)
## and the wallet seam on the @abstract Character base (scripts/player/character.gd —
## money / add_money / money_changed / reward_kill). Each assert message states WHY the
## invariant matters, so this file doubles as executable documentation of the money grid.
##
## SCOPE — this file deliberately covers only the angles NOT already asserted elsewhere:
##   * Zorkmids.QUANTUM's value and the fmt() display table (bare wholes, trimmed
##     fractions, float-noise snap) — pinned NOWHERE else (no test references Zorkmids).
##   * Character.add_money's per-mutation quantization (drift-free accumulation,
##     sub-quantum snapping, exact-zero spend-down), the is_zero_approx no-op guard,
##     and the money_changed(total, delta) parameter contract.
##   * reward_kill routing through the add_money seam (so listeners always fire).
##   DELIBERATELY SKIPPED because they are pinned elsewhere:
##   * Merchant buy_price/sell_price directional rounding (ceil-buy / floor-sell to the
##     coin, the one-coin floor) — test_merchant.gd test_price_rounding_ceil_buy_floor_sell
##     + test_buy_price_never_below_one_coin_for_a_valued_item.
##   * Wallet persistence round-trip / junk-save degradation — test_game_save.gd.
##   * Spend gates (heal/level-up refusals leave money untouched) — test_healer.gd,
##     test_level_up.gd; wallet-to-corpse copy — test_loot_drop.gd.
##   * The kill-bounty SIZES and _award_kill's attribution rules (self-bounty guard,
##     kill-credit window) — they read GameSettings.economy and live in take_damage's
##     lethal path; in-tree behaviour, out of scope here.
##
## TESTABILITY NOTES:
##   * Character is @abstract — load(path).new() cannot instantiate it. Per the
##     test_character.gd precedent we use a fresh inner concrete stub (_WalletStub,
##     named distinctly from test_character's _Stub / test_smoke's _ConcreteCharacter
##     so the suites could merge without a clash). Built OFF-TREE (no add_child):
##     _ready never runs (no weapon scenes / nav / audio), and add_money's body
##     (character.gd:35-39) touches no get_tree()/transform state — it is a pure
##     snappedf + signal emit, so emitting off-tree is safe. Nodes -> .new() + .free().
##   * Zorkmids is RefCounted with only a const + a static func — no instance is ever
##     created; fmt() is called statically.
##   * add_money is `-> void`: its result must never be captured (analyzer error).
##   * Several asserts below use EXACT float equality (assert_eq) on purpose: the whole
##     point of snapping every mutation to QUANTUM is that wallet totals are bit-exact
##     grid values (1.0, 0.0, 12.5 are all exactly representable) — assert_almost_eq
##     would mask the very drift the seam exists to kill.

## Concrete stand-in for the @abstract Character base (which cannot be .new()'d directly).
class _WalletStub extends Character:
	pass


# ---------------------------------------------------------------------------
# Zorkmids — the quantum + the fmt() display table
# ---------------------------------------------------------------------------

func test_quantum_is_one_hundredth() -> void:
	assert_eq(Zorkmids.QUANTUM, 0.01,
		"QUANTUM is the smallest coin — the money grid EVERY transaction snaps to (Character.add_money, Merchant price rounding). Changing it re-grids every wallet and price in the economy, so it must be a deliberate decision, not drift")


func test_fmt_whole_amounts_print_bare() -> void:
	assert_eq(Zorkmids.fmt(12.0), "12",
		"a whole wallet prints bare — '12', never a noisy '12.00' (the HUD/shop readout contract in zorkmids.gd's header)")
	assert_eq(Zorkmids.fmt(100.0), "100",
		"larger wholes stay bare too — the int branch is value-independent")
	assert_eq(Zorkmids.fmt(0.0), "0",
		"an empty wallet prints '0', not '0.00' or '' — the HUD must always show a number")


func test_fmt_fractions_trim_trailing_zeros_without_a_dangling_dot() -> void:
	assert_eq(Zorkmids.fmt(12.5), "12.5",
		"half a zorkmid prints one decimal — '%.2f' gives '12.50' and the rstrip('0') trims the dead zero")
	assert_eq(Zorkmids.fmt(0.75), "0.75",
		"a three-quarter coin keeps both decimals — only TRAILING zeros are trimmed, real cents survive")
	assert_eq(Zorkmids.fmt(3.1), "3.1",
		"'3.10' loses exactly its trailing zero — the readout never pads cents that aren't there")
	assert_eq(Zorkmids.fmt(-0.5), "-0.5",
		"negative amounts (debts/deltas) format with the sign and the same trimming — zorkmids.gd:11 documents '-0.5'")
	assert_false(Zorkmids.fmt(12.5).ends_with("."),
		"trailing-zero stripping must never leave a dangling '.' — the rstrip('.') guard exists so a fully-trimmed fraction can't render as '12.'")


func test_fmt_float_noise_snaps_back_to_the_bare_int_branch() -> void:
	# 0.999999 is what 1.0 looks like after un-snapped float maths. fmt() first snaps to
	# QUANTUM (landing exactly on 1.0) and then is_equal_approx routes whole results to the
	# bare-int branch — so accumulated noise can never leak '0.999999' (or '1.00') into the HUD.
	assert_eq(Zorkmids.fmt(0.999999), "1",
		"float noise just under a whole snaps to the bare int — the player must never see '0.999999' zorkmids")
	assert_eq(Zorkmids.fmt(12.000001), "12",
		"noise just OVER a whole snaps down to bare '12' too — the snap is to the nearest coin, both directions")


# ---------------------------------------------------------------------------
# Character.add_money — the ONE quantizing seam every wallet change routes through
# ---------------------------------------------------------------------------

func test_add_money_repeated_tenths_accumulate_exactly() -> void:
	# Raw float accumulation of 0.1 ten times yields 0.9999999999999999. add_money snaps
	# EVERY mutation to QUANTUM, so the wallet lands on bit-exact 1.0 — this is the invariant
	# that lets the whole economy use == comparisons and save/load without drift.
	var c := _WalletStub.new()
	for i in 10:
		c.add_money(0.1)
	assert_eq(c.money, 1.0,
		"ten 0.1 credits must total EXACTLY 1.0 — per-mutation snappedf(money + delta, QUANTUM) kills binary-float drift before it can accumulate into the economy")
	c.free()


func test_add_money_snaps_sub_quantum_deltas_to_the_nearest_coin() -> void:
	# snappedf rounds to the NEAREST multiple of QUANTUM (floor(x/step + 0.5) * step) — not
	# directionally like Merchant's ceil-buy/floor-sell. Sub-coin dust below half a coin
	# vanishes; at/above half a coin it becomes a whole coin.
	var c := _WalletStub.new()
	c.add_money(0.004)
	assert_eq(c.money, 0.0,
		"a 0.004 credit snaps to the NEAREST cent, which is 0.0 — the wallet cannot hold sub-coin dust, so amounts below half a coin round away")
	c.add_money(0.006)
	assert_eq(c.money, 0.01,
		"a 0.006 credit snaps UP to one coin (0.01) — nearest-coin rounding, so the grid is symmetric around the half-coin midpoint")
	c.free()


func test_add_money_negative_deltas_snap_and_reach_exact_zero() -> void:
	# Spending is the same seam with a negative delta. Ten 0.1 debits from 1.0 must land on
	# bit-exact 0.0 — an un-snapped wallet would end at ~1.1e-16 and 'money == 0' checks
	# (and the fmt readout) would misbehave forever after.
	var c := _WalletStub.new()
	c.money = 1.0
	for i in 10:
		c.add_money(-0.1)
	assert_eq(c.money, 0.0,
		"spending 0.1 ten times from 1.0 must reach EXACTLY 0.0 — negative deltas snap to the same coin grid, so a wallet can always be emptied to a clean zero")
	c.free()


func test_add_money_zero_delta_is_a_silent_noop() -> void:
	# character.gd:36-37: is_zero_approx(delta) returns BEFORE the snap and the emit. A zero
	# delta must neither move money nor fire money_changed — listeners (the player's HUD
	# repaint + the one-frame autosave flush) must not churn on no-op calls.
	var c := _WalletStub.new()
	c.money = 5.0
	var fired := [0]
	c.money_changed.connect(func(_total: float, _delta: float) -> void: fired[0] += 1)
	c.add_money(0.0)
	c.add_money(0.000001)  # below is_zero_approx's epsilon — still a no-op
	assert_eq(c.money, 5.0,
		"a (near-)zero delta leaves the wallet untouched — no pointless re-snap of the stored total")
	assert_eq(fired[0], 0,
		"a (near-)zero delta must NOT emit money_changed — the player's HUD and the autosave flush would otherwise churn on every no-op call")
	c.free()


func test_money_changed_reports_total_then_delta() -> void:
	# character.gd:39 emits (new total, signed delta) IN THAT ORDER — the player's HUD reads
	# the total, the autosave hook ignores both, and loot/bounty toasts read the delta. A
	# swapped order would silently corrupt every listener, so the order is pinned here.
	var c := _WalletStub.new()
	c.money = 10.0
	watch_signals(c)
	c.add_money(2.5)
	assert_eq(c.money, 12.5,
		"the wallet holds the snapped new total (10 + 2.5) before the signal fires — listeners may read c.money OR the first parameter interchangeably")
	# money_changed must carry (new total, signed delta) — total FIRST (the HUD readout), delta
	# second (loot/bounty toasts); both already on the coin grid. (This GUT assert takes no
	# custom message — its optional 4th arg is an emit INDEX.)
	assert_signal_emitted_with_parameters(c, "money_changed", [12.5, 2.5])
	c.free()


func test_reward_kill_routes_through_the_add_money_seam() -> void:
	# reward_kill (character.gd:44-45) is the duck-typed kill-bounty hook _award_kill calls on
	# the killer. It must pay via add_money — NOT by poking `money` directly — so the credit is
	# quantized and money_changed still fires (the player's HUD + autosave see bounties too).
	var c := _WalletStub.new()
	watch_signals(c)
	c.reward_kill(2.0)
	assert_eq(c.money, 2.0,
		"the bounty lands in the wallet — every Character earns now, an NPC's winnings ride into its lootable corpse")
	# reward_kill must route through add_money so money_changed fires — a direct `money +=`
	# would skip the HUD readout and the autosave flush, silently desyncing both. (No custom
	# message: this GUT assert's optional 4th arg is an emit INDEX, not a message.)
	assert_signal_emitted_with_parameters(c, "money_changed", [2.0, 2.0])
	c.free()
