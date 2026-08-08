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
##   * The DEATH SETTLEMENT (Player._bequeath_wallet): the purse goes to the killer, or is
##     left alone when there is nowhere to spill it, or is untouched entirely in a reload
##     death mode — plus the two revive toasts that name the destination. Money is MOVED,
##     never destroyed, and that is what these pin.
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
##     (character.gd:40-43) touches no get_tree()/transform state — it is a pure
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

class _HolsterReminderKiller extends Node:
	var should_remind: bool = true

	func should_remind_holster_forgiveness_tutorial_on_player_death() -> bool:
		return should_remind

## A killer the death settlement will actually pay: the ONLY thing _bequeath_wallet requires of a killer is a
## duck-typed add_money (it is loosely typed there — an NPC, a titled hazard, a stub like this). `display_name` is
## what _killer_display_name reads for the revive toast; no resolved_disposition, so the stranger mask is skipped
## and the raw name comes through (that mask is pinned in test_death_card.gd, not here).
class _PayableKiller extends Node:
	var money: float = 0.0
	var display_name: String = "Test Killer"
	var alive: bool = true

	func add_money(delta: float) -> void:
		money = snappedf(money + delta, Zorkmids.QUANTUM)

	## Every real Character has this; the settlement refuses to pay a DEAD one (its loot was already minted).
	func is_alive() -> bool:
		return alive


## Force the death settlement's in-place-revive gate OPEN / restore it. _bequeath_wallet does NOTHING unless
## Player._death_revives_in_place() is true (death_mode is not a RELOAD_* AND a respawn point is set) — see the
## reload test below for why. Both bits live on AUTOLOADS shared with every other suite, so each test that moves
## them banks the old values and puts them back, pass or fail.
func _bank_respawn_state() -> Dictionary:
	return {
		"mode": GameSettings.player_feedback.death_mode,
		"has": GameState.has_respawn,
		"pos": GameState.respawn_position,
		"yaw": GameState.respawn_yaw,
	}


func _restore_respawn_state(banked: Dictionary) -> void:
	GameSettings.player_feedback.death_mode = banked["mode"]
	GameState.has_respawn = banked["has"]
	GameState.respawn_position = banked["pos"]
	GameState.respawn_yaw = banked["yaw"]


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
	# QUANTUM (landing exactly on 1.0) and then TextFormat.num's "%.2f" + rstrip renders the whole
	# amount bare — so accumulated noise can never leak '0.999999' (or '1.00') into the HUD.
	assert_eq(Zorkmids.fmt(0.999999), "1",
		"float noise just under a whole snaps to the bare int — the player must never see '0.999999' zorkmids")
	assert_eq(Zorkmids.fmt(12.000001), "12",
		"noise just OVER a whole snaps down to bare '12' too — the snap is to the nearest coin, both directions")


func test_fmt_large_wallet_keeps_its_cents() -> void:
	# Regression pin for a bug the TextFormat.num delegation FIXED: the retired in-place idiom's
	# integer shortcut used is_equal_approx, whose tolerance is RELATIVE (~1e-5 * |q|), so above
	# ~1000 zm a real 0.01 fraction fell inside the tolerance and the cent silently vanished from
	# the HUD (fmt(1500.01) printed "1500"). The "%.2f" path has no magnitude-dependent shortcut.
	assert_eq(Zorkmids.fmt(1500.01), "1500.01",
		"a rich wallet must not eat cents — the old is_equal_approx shortcut collapsed 1500.01 to '1500'")
	assert_eq(Zorkmids.fmt(10000.5), "10000.5",
		"the half-zorkmid must survive at five figures too — no magnitude-relative rounding in display")


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
	# character.gd:40-41: is_zero_approx(delta) returns BEFORE the snap and the emit. A zero
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
	# character.gd:43 emits (new total, signed delta) IN THAT ORDER — the player's HUD reads
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
	# reward_kill (character.gd:48-49) is the duck-typed kill-bounty hook _award_kill calls on
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


func test_killer_pockets_the_whole_wallet_on_death() -> void:
	# THE headline rule: death hands your zorkmids to whoever killed you, in full — it never destroys them. The
	# killer holds them in their live wallet, which NpcMortality reads at THEIR death so LootableCorpse mints it as
	# a coin tile in their loot bag (that copy is pinned in test_loot_drop.gd). Kill them, loot it back.
	assert_eq(GameSettings.economy.death_purse_loss_fraction, 1.0,
		"death_purse_loss_fraction ships at 1.0 — the killer takes the WHOLE purse, because you can go and take it back")
	var banked := _bank_respawn_state()
	GameSettings.player_feedback.death_mode = PlayerFeedbackSettings.DeathMode.CHECKPOINT_RESPAWN
	GameState.set_respawn(Vector3.ZERO, 0.0)
	var p = load("res://scripts/player/player.gd").new()
	var killer := _PayableKiller.new()
	p.money = 101.0
	p._bequeath_wallet(killer)
	assert_eq(p.money, 0.0,
		"the whole wallet leaves the player — a half-measure would leave nothing worth hunting the killer for")
	assert_eq(killer.money, 101.0,
		"...and lands in the KILLER's wallet, conserved to the coin: money is moved, never burnt")
	# Amount + killer NAME are banked at death for the revive toast: the toast waits for the respawn (die()'s
	# HUD-hide would swallow it) and the killer node can be freed or leashed home before then, so the name is
	# resolved to a STRING now, while the killer is guaranteed live.
	assert_eq(p._death_wallet_lost, 101.0,
		"_bequeath_wallet records what moved so _respawn_at_checkpoint can toast the exact amount on the revive")
	assert_eq(p._death_wallet_killer_name, "Test Killer",
		"a NAMED destination makes the revive toast say who to hunt — resolved at death, not from a node that may be gone by then")
	# The toast picks killer-vs-ground off this FLAG, never off the name: a designer may blank
	# death_unknown_killer and an NPC ships with a blank display_name, and switching on "" would then tell the
	# player their purse is on the ground while it is really in a killer's pocket (CLAUDE.md: display strings are
	# never behaviour keys).
	assert_true(p._death_wallet_to_killer,
		"the killer branch is recorded as a BOOL, so the revive toast can never mistake an unnamed killer for a ground drop")
	killer.free()
	p.free()
	_restore_respawn_state(banked)


func test_a_dead_killer_is_not_a_holder() -> void:
	# A corpse can't be robbed of money it never had: NpcMortality/GoreSpawner mint the loot bag from `money` at the
	# INSTANT of death, so anything paid in afterwards is unreachable — and a pooled body stays is_instance_valid
	# long after, until acquire() re-stamps its authored wallet and the money is simply gone. This is reachable in
	# ordinary play: kill someone, then fall off a ledge inside kill_credit_window_ms and _resolve_killer hands that
	# same corpse back as your killer. So a dead killer must fall THROUGH to the ground spill.
	var banked := _bank_respawn_state()
	GameSettings.player_feedback.death_mode = PlayerFeedbackSettings.DeathMode.CHECKPOINT_RESPAWN
	GameState.set_respawn(Vector3.ZERO, 0.0)
	var p = load("res://scripts/player/player.gd").new()
	var corpse := _PayableKiller.new()
	corpse.alive = false
	p.money = 101.0
	p._bequeath_wallet(corpse)
	assert_eq(corpse.money, 0.0,
		"a killer that is already dead is never paid — its loot bag was minted at its own death, so the money would be unreachable")
	assert_false(p._death_wallet_to_killer,
		"...and the settlement falls through to the ground-spill branch instead, where 'nobody alive killed you' is the truth")
	assert_eq(p.money, 101.0,
		"off-tree there is nowhere to spill either, so the wallet is left alone rather than emptied into nothing")
	corpse.free()
	p.free()
	_restore_respawn_state(banked)


func test_loss_fraction_scales_what_the_killer_takes() -> void:
	# The knob is a designer-facing OFF SWITCH as well as a dial (EconomySettings: "0 = keep it all / feature off"),
	# and it is documented as such in AUTHORING_GUIDE. Without this, _death_wallet_loss could ignore the fraction
	# entirely and every other test here would still pass, because they all run at the shipped 1.0.
	var banked := _bank_respawn_state()
	var banked_fraction: float = GameSettings.economy.death_purse_loss_fraction
	GameSettings.player_feedback.death_mode = PlayerFeedbackSettings.DeathMode.CHECKPOINT_RESPAWN
	GameState.set_respawn(Vector3.ZERO, 0.0)

	GameSettings.economy.death_purse_loss_fraction = 0.0
	var p = load("res://scripts/player/player.gd").new()
	var killer := _PayableKiller.new()
	p.money = 101.0
	p._bequeath_wallet(killer)
	assert_eq(p.money, 101.0,
		"fraction 0 is the documented OFF switch — death must take nothing at all, not silently take everything")
	assert_eq(killer.money, 0.0,
		"...and pay nobody, so a designer who turns the feature off really has turned it off")

	GameSettings.economy.death_purse_loss_fraction = 0.5
	p.money = 101.0
	p._bequeath_wallet(killer)
	assert_eq(p.money, 50.5,
		"a partial fraction takes exactly that share of the wallet, quantized to the coin grid")
	assert_eq(killer.money, 50.5,
		"...and the killer receives exactly what the player lost — the fraction scales the transfer, it never mints or burns")

	killer.free()
	p.free()
	GameSettings.economy.death_purse_loss_fraction = banked_fraction
	_restore_respawn_state(banked)


func test_unattributed_death_never_debits_without_a_bag_to_put_it_in() -> void:
	# The other half of "money is moved, never burnt": with no killer the purse SPILLS on the ground as a physics
	# MoneyBag. That spawn needs a world, so an off-tree player (this one — CLAUDE.md forbids running Player._ready
	# in a unit test) has nowhere to put it, _death_purse_anchor returns null, and the wallet is left ALONE rather
	# than emptied into nothing. Same guard drop_money has always had. The in-tree spill itself is playtested.
	var banked := _bank_respawn_state()
	GameSettings.player_feedback.death_mode = PlayerFeedbackSettings.DeathMode.CHECKPOINT_RESPAWN
	GameState.set_respawn(Vector3.ZERO, 0.0)
	var p = load("res://scripts/player/player.gd").new()
	p.money = 101.0
	p._bequeath_wallet(null)
	assert_eq(p.money, 101.0,
		"nowhere to drop the bag -> the money stays in the wallet; we never debit before the purse is really in the world")
	assert_eq(p._death_wallet_lost, 0.0,
		"...and nothing is recorded, so the revive can never toast a loss that did not happen")
	p.free()
	_restore_respawn_state(banked)


func test_reload_death_modes_settle_nothing() -> void:
	# A RELOAD_* death rebuilds the world: the killer is reset and any dropped bag is gone, so there would be
	# nowhere recoverable for the money to sit — and the save restores this wallet anyway. Worse, add_money's
	# autosave flush would write the emptied wallet to the very file RELOAD_LAST_SAVE then reads back, permanently
	# destroying it. So _death_revives_in_place() gates the WHOLE settlement (it used to gate only the hand-off,
	# which is exactly how the money got burnt).
	var banked := _bank_respawn_state()
	GameSettings.player_feedback.death_mode = PlayerFeedbackSettings.DeathMode.RELOAD_LAST_SAVE
	GameState.set_respawn(Vector3.ZERO, 0.0)
	var p = load("res://scripts/player/player.gd").new()
	var killer := _PayableKiller.new()
	p.money = 101.0
	p._bequeath_wallet(killer)
	assert_eq(p.money, 101.0,
		"a reload-mode death takes nothing — the reload restores this wallet, so debiting it is money burnt for nobody")
	assert_eq(killer.money, 0.0,
		"...and pays nobody: the killer is about to be reset by the reload, so they could never be looted for it")
	assert_eq(p._death_wallet_lost, 0.0,
		"nothing moved -> no revive toast (the reload rebuilds the Player anyway)")
	killer.free()
	p.free()
	_restore_respawn_state(banked)


func test_broke_player_death_settles_nothing() -> void:
	# A broke death moves nothing, so _death_wallet_lost stays 0 and the revive skips the toast entirely
	# (the toast is gated on > 0). Pins the "no free-floating 0 zm toast" edge.
	var banked := _bank_respawn_state()
	GameSettings.player_feedback.death_mode = PlayerFeedbackSettings.DeathMode.CHECKPOINT_RESPAWN
	GameState.set_respawn(Vector3.ZERO, 0.0)
	var p = load("res://scripts/player/player.gd").new()
	var killer := _PayableKiller.new()
	p.money = 0.0
	p._bequeath_wallet(killer)
	assert_eq(p._death_wallet_lost, 0.0,
		"nothing to move -> nothing recorded -> the in-place revive shows no wallet toast")
	assert_eq(p._death_wallet_killer_name, "",
		"...and no destination is banked either, so a broke death can't leave a stale killer name for the NEXT death to toast")
	killer.free()
	p.free()
	_restore_respawn_state(banked)


func test_player_death_to_reminder_eligible_npc_queues_holster_forgiveness_tutorial() -> void:
	GameState.consume_holster_forgiveness_tutorial_reminder()  # clear any reminder left by a prior focused run
	var p = load("res://scripts/player/player.gd").new()
	p.money = 0.0  # keep this about the tutorial bridge, not wallet transfer / in-place respawn mode
	var killer := _HolsterReminderKiller.new()
	p._bequeath_wallet(killer)
	assert_true(GameState.consume_holster_forgiveness_tutorial_reminder(),
		"dying to the NPC that owns the active provoke lesson queues a one-shot holster-forgiveness reminder")
	assert_false(GameState.consume_holster_forgiveness_tutorial_reminder(),
		"the death reminder is consume-once so a HUD rebuild does not repeat it")
	killer.should_remind = false
	p._bequeath_wallet(killer)
	assert_false(GameState.consume_holster_forgiveness_tutorial_reminder(),
		"an unrelated killer, forgiven NPC, or unavailable pardon does not queue the holster tutorial")
	killer.free()
	p.free()


func test_death_wallet_toasts_name_where_the_money_went() -> void:
	# Both respawn toasts are single-[PH] placeholder lines carrying the amount via Zorkmids.fmt (mirrors
	# chess_loss / long_range_kill). Pins the marker + format so the AI-text scrub stays consistent — and, more
	# importantly, that the two DESTINATIONS read differently: the whole point of the feature is that the player
	# is told where to go get their zorkmids back.
	assert_eq(PlayerText.purse_taken("Test Killer", 50.5), "[PH] Robbed!  50.5 zm taken by Test Killer",
		"the killer-took-it toast reads '[PH] Robbed!  <amount> zm taken by <killer>', one placeholder marker up front")
	assert_eq(PlayerText.purse_dropped(50.5), "[PH] Purse dropped!  50.5 zm where you fell",
		"the no-killer toast instead points at the GROUND, so a fall death reads as recoverable rather than as a penalty")
	# The killer name arrives pre-masked from Player._killer_display_name, so an unintroduced NPC renders as the
	# lowercase indefinite form. It must sit MID-sentence for that to be grammatical.
	assert_eq(PlayerText.purse_taken("a stranger", 12.0), "[PH] Robbed!  12 zm taken by a stranger",
		"the masked 'a stranger' fallback reads grammatically because the name never opens the sentence")
