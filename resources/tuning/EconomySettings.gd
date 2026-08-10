class_name EconomySettings
extends Resource

## The economy's designer knobs — every bounty, trick-shot reward, and seed value on ONE inspector page
## (edit resources/tuning/EconomySettings.tres, no code). Read everywhere as GameSettings.economy.<field>,
## like the other tuning groups. Zorkmids are FRACTIONAL (0.5 = half a zorkmid), so every knob here is too.

@export_group("Kill bounties")
## Paid to whoever downs a character (player AND NPCs — winnings sit in an NPC's lootable wallet).
@export var kill_bounty: float = 1.0
## ...when the KILLING blow was a headshot.
@export var headshot_kill_bounty: float = 2.0
## ...when EVERY point of damage the victim took was a headshot (the applause kill).
@export var all_headshots_kill_bounty: float = 4.0

@export_group("Trick shots")
## EXTRA on a collateral kill — carried overkill piercing out of one kill into another victim.
@export var collateral_bounty: float = 2.0
## ...when the collateral blow itself was a headshot.
@export var collateral_headshot_bounty: float = 4.0
## Swatting a fresh gore gib out of the air (the confetti pop).
@export var confetti_bounty: float = 1.0

@export_group("Long-range kills")
## EXTRA bounty for downing a character from a distance — the marksman reward. Distance is measured
## killer<->victim at the MOMENT OF DEATH (exact for a hitscan; a close approximation for a projectile, whose
## shooter has barely moved during the round's flight). A kill at or beyond long_range_min_distance earns
## long_range_bounty, PLUS long_range_bounty_per_m for every metre past the threshold, all clamped to
## long_range_bounty_max. Paid ON TOP of the normal kill bounty into ANY killer's wallet — like the collateral
## / confetti trick-shots, an NPC sniper banks it too (ride-along loot); the PLAYER also gets a toast. A melee
## or point-blank kill falls under the threshold and pays nothing, so DISTANCE is the only gate — no
## weapon-type check needed. To turn the reward OFF, zero long_range_bounty AND long_range_bounty_per_m (or
## raise long_range_min_distance out of reach). Read as GameSettings.economy.long_range_*.
## Distance (m) a kill must reach to count as "long range". Default 30 = beyond a default NPC's fire_range
## (npc.gd, 30 m) and its 25 m sight_range: you outranged their gun before they could shoot back.
@export var long_range_min_distance: float = 30.0
## Flat zorkmids paid the instant a kill reaches the threshold (the base marksman reward).
@export var long_range_bounty: float = 2.0
## EXTRA zorkmids per metre shot BEYOND the threshold — the payout scales with how far the kill was, so a
## 90 m shot pays more than a 35 m one. 0 = a flat reward with no distance scaling.
@export var long_range_bounty_per_m: float = 0.1
## Cap on the TOTAL long-range bounty, so an extreme cross-map shot can't pay absurdly. At the defaults the cap
## is hit ~90 m out (30 m threshold + 60 m × 0.1).
@export var long_range_bounty_max: float = 8.0

## Pure curve: the long-range bounty a kill at `distance` metres earns, given the four knobs. Returns 0 below
## the threshold (a normal-range kill earns nothing extra); at/above it, flat + per-metre-beyond, clamped into
## [0, max]. Static + float-only so it unit-tests off-tree with no nodes (mirrors MoneyBag.size_for). max_bonus
## is floored at `flat` so a cap mistakenly set below the flat payout can never pay LESS than the flat amount.
static func long_range_bonus_for(distance: float, min_distance: float, flat: float, per_m: float, max_bonus: float) -> float:
	if distance < min_distance:
		return 0.0
	var bonus := flat + per_m * maxf(0.0, distance - min_distance)
	return clampf(bonus, 0.0, maxf(flat, max_bonus))

@export_group("Kill credit")
## A hit older than this (ms) no longer earns its shooter the kill bounty when the victim dies.
@export var kill_credit_window_ms: int = 5000

@export_group("Death")
## Fraction of the PLAYER's wallet that LEAVES YOUR POCKET on death (0 = keep it all / feature off).
## Default 1.0 — death takes everything — but the money is never DESTROYED, only moved somewhere you can go get it:
##   * killed by someone -> they pocket the whole purse, and it drops as a coin tile in their loot when you kill them;
##   * killed by nothing (a fall, a hazard, your own grenade) -> it spills on the ground as a physics money bag at
##     the spot you died, waiting to be picked back up.
## Only ever applies to an in-place CHECKPOINT_RESPAWN death: a RELOAD_* death mode rebuilds the world and restores
## the pre-death wallet from the save, so nothing is taken there at all (there would be nowhere for it to go).
## Read as GameSettings.economy.death_purse_loss_fraction.
@export_range(0.0, 1.0, 0.05) var death_purse_loss_fraction: float = 1.0
## OFF-SWITCH for the ground spill alone. true = a death nobody gets credit for drops a reclaimable money bag where
## you fell; false = an unattributed death takes nothing at all (the killer hand-off is unaffected either way).
## Read as GameSettings.economy.death_purse_drops_when_unclaimed.
@export var death_purse_drops_when_unclaimed: bool = true
## How far (m) to probe STRAIGHT DOWN from the death spot for a floor to rest the spilled bag on. The everyday drop
## probe (Player._drop_position) only reaches 3 m, which misses on the exact death this matters most for — a long
## fall that kills you in mid-air. Mirrors the player's own GROUND_SNAP_MAX_DROP search. 0 = skip the deep probe and
## fall straight through to the last-ground-you-stood-on anchor. Read as GameSettings.economy.death_purse_drop_ground_probe.
@export var death_purse_drop_ground_probe: float = 200.0
## Last-resort anchor when you die over a bottomless void AND we never saw you stand anywhere: true = the bag waits at
## the checkpoint you are about to respawn at (you always get it back); false = the void keeps it — the money stays in
## your wallet rather than spawn a bag into nothing, since a bag dropped into the void would fall forever.
## Read as GameSettings.economy.death_purse_drop_to_respawn_in_void.
@export var death_purse_drop_to_respawn_in_void: bool = true

@export_group("Reputation")
## Disposition boost toward whoever killed this NPC's attacker (the rescue thank-you).
@export var save_rep_reward: float = 15.0

@export_group("Seeds")
## The player's fresh-game wallet (a SwapWeapons Loadout overrides it; a loaded save wins over both). 0 by default -> the player starts broke.
@export var player_starting_money: float = 0.0

@export_group("Restock")
## Default seconds between a Restocker's refills when its own `interval` is left at 0 — how fast vendors /
## containers replenish fixed authored stock/item rows. Container money is not re-seeded, and loot tables are
## not re-rolled. Read as GameSettings.economy.restock_interval.
@export var restock_interval: float = 60.0

@export_group("Vendor pricing")
## ⭐THE ARBITRAGE FLOOR — the one number that couples a Merchant's two multipliers. It is the minimum gap
## (zorkmids) a vendor keeps between what it CHARGES for an item and what it PAYS for the same item from the
## same actor: `Merchant.sell_price` is clamped to `buy_price - this`, so you can never sell a thing back for
## more than it costs.
##
## ⭐WHY IT MUST EXIST: nothing else couples the two sides. STREETWISE bends buying DOWN and selling UP by the
## same 4%/point (CharacterStats.buy_price_mult / sell_price_mult, both deliberately uncapped), so at the
## shipped 1.0/0.5 spread the lines CROSS at about 9 points — well inside the +10 character creation already
## allows — and every vendor becomes an unbounded money printer (buy at 60, sell back at 70, repeat), made
## worse by a till that re-seeds from the .tscn on every level load. A `reputation_discount_curve` pushes the
## same way and can cross at streetwise 0. Clamping the SELL side keeps streetwise monotonically better for
## the player: more points narrow the spread toward parity instead of inverting it.
##
## Shipped at one Zorkmids.QUANTUM (the smallest coin), the least that keeps the inequality STRICT on the coin
## grid — so this only ever bites a build/curve that had already crossed. Raise it to guarantee every vendor a
## real cut however skilled the trader; 0 permits exact PARITY, which is still loop-free (the round trip nets
## zero) but leaves no margin. Read as GameSettings.economy.min_vendor_spread.
@export var min_vendor_spread: float = Zorkmids.QUANTUM

@export_group("Money bag")
## When you DUMP your zorkmids from the backpack (right-click the coin tile), they drop as a physics BAG you can
## grab + hurl (Player.drop_money -> MoneyBag): a fat purse is a better bludgeon, so its SIZE, MASS, and THROW
## DAMAGE all scale with how much cash it holds. These are the curves. Read as GameSettings.economy.money_bag_*.
## Overall bag HEIGHT (m) at ~0 zorkmids — the smallest a dropped purse ever looks (the bag.glb is scaled to this).
@export var money_bag_min_size: float = 0.25
## Height (m) cap — however rich you are, the bag never grows past this (stays grabbable, not a boulder).
@export var money_bag_max_size: float = 1.2
## Height (m) added per SQRT of the amount (a soft curve, so wealth reads fast then tapers — 100 zm ≈ +0.5 m).
@export var money_bag_size_per_sqrt_zm: float = 0.05
## Mass (kg) of the bag at ~0 zorkmids — a near-empty purse barely has heft.
@export var money_bag_base_mass: float = 1.0
## Mass (kg) added per zorkmid — heavier bags carry more momentum (and shove props/NPCs harder). Clamped by max.
@export var money_bag_mass_per_zm: float = 0.02
## Mass (kg) cap so a huge fortune doesn't become an immovable anchor.
@export var money_bag_max_mass: float = 30.0
## Throw-DAMAGE multiplier added per zorkmid, ON TOP of the normal impact-speed damage. 0 = the bag hits like any
## prop its size; higher = your fortune is a wrecking ball. e.g. 0.05 -> 20 zm is 2x, 100 zm is 6x (then capped).
@export var money_bag_damage_per_zm: float = 0.05
## Cap on that throw-damage multiplier, so an obscene fortune can't trivially one-shot everything.
@export var money_bag_max_damage_mult: float = 8.0
## The zorkmids stack ALSO takes up more BACKPACK space the richer you are — its grid footprint is a square whose
## side grows with the amount (a fat purse is bulky to haul). These set that curve. Minimum side (cells) — the
## footprint at ~0 zorkmids. 1 = a single cell.
@export var money_bag_grid_min_side: int = 1
## Maximum side (cells) — however rich, the money pile never occupies more than this square (keeps it from eating
## the whole bag). 3 = at most 3×3 = 9 cells.
@export var money_bag_grid_max_side: int = 3
## Side (cells) added per SQRT of the amount, floored to a whole cell. e.g. 0.2 -> 25 zm is 2×2, 100 zm is 3×3.
## The pile only grows into FREE cells and never evicts other items; if the next size won't fit, it stays smaller.
@export var money_bag_grid_side_per_sqrt_zm: float = 0.2

@export_group("Starting credit")
## New Game's implant purchase (implant_choice.gd) runs ON CREDIT — but the Ledger rates the BUILD first:
## the creation stat sheet is scored (credit_rating_for), the score maps to a spending LIMIT
## (credit_limit_for), and the implant cart can never bill past limit + player_starting_money.
##
## THE UNDERWRITING SHEET. The bank is not grading taste; it is pricing a loan against someone it expects to
## die. Four lines, each normalized to [0,1] against the ALLOCATOR's own bounds (StatBudget.STAT_MIN/MAX, so
## the scorer can never drift from the builder):
##   CAPACITY  — income_weight x invested points ....... can this body generate zorkmids?
##   VIABILITY — survival_weight x invested points ..... will it live long enough to repay?
##   TRADE     — peak invested stat / credit_depth_points  is there a marketable specialty, or a hobbyist?
##   EXPOSURE  — dump_severity x depth^exponent ........ what has been pledged, and what is it worth?
## score = score_min + span x clamp(baseline + w_cap*CAP + w_via*VIA + w_trade*TRADE - w_exp*EXPOSURE).
##
## ⭐WHY THIS SHAPE: positives feed ONLY the three additive lines and negatives feed ONLY the subtractive one,
## so raising any stat can never lower a score and lowering any can never raise it — for ANY table a designer
## authors. That is what makes it impossible to re-create the model this replaced, which (because the creation
## budget is ZERO-SUM, so every invested point is funded by a dumped one) collapsed to a flat tax on spending
## the budget: the all-zero non-character rated the ceiling and the full cap while a committed build was fined.
## Investing is now always rewarded and the maximum sits at the budget corner, where it belongs.
##
## OFF-SWITCH: set credit_score_min equal to credit_score_max — the degenerate range rates every build at the
## full credit_limit_max. Read as GameSettings.economy.credit_*.
## Score floor — the worst possible build bottoms out here (the classic 300..850 range).
@export var credit_score_min: int = 300
## Score ceiling. NOTE it is deliberately not quite reachable: the best legal build rates ~842, because a bank
## that hands out its advertised maximum is not a bank. Raise credit_baseline_fraction to close that gap.
@export var credit_score_max: int = 850
## Credit limit (zorkmids) a PERFECT score earns — the absolute cap on the implant bill's credit share.
@export var credit_limit_max: float = 2100.0
## The limit is FLOORED to whole steps of this (banks quote round numbers). 0 = exact, unstepped.
@export var credit_limit_step: float = 50.0
## Gamma on the score -> zorkmids map. 1.0 is the plain linear map; higher punishes the bottom of the range
## harder without moving a single score (a mediocre rating buys proportionally less).
@export var credit_limit_curve: float = 1.6
## ⭐THE ACTUARIAL TABLE — one row per stat (see StatUnderwriting). This is the whole model's content: change
## these 24 numbers and the bank re-prices every build in the game. An EMPTY array is a flat credit market
## (every build rates exactly credit_baseline_fraction) — a fail-OPEN degrade, never a crash and never a
## bank that declines everybody.
@export var credit_underwriting: Array[StatUnderwriting] = []
## Where the NO-FILE applicant sits in the score span — the character who allocated nothing has no assets AND
## no pledges, so every line reads zero and this fraction is their whole rating. Lower it to make the nobody
## poorer. At 0.24 they rate 432 and are advanced 200 zm: exactly one cheap chip, so nobody is locked out.
@export_range(0.0, 1.0, 0.01) var credit_baseline_fraction: float = 0.24
## How much the bank pays for predicted INCOME (the CAPACITY line).
@export var credit_weight_capacity: float = 0.48
## How much it pays for predicted SURVIVAL (the VIABILITY line).
@export var credit_weight_viability: float = 0.38
## How much it pays for a marketable SPECIALTY (the TRADE line) — commitment to one thing, priced on its own.
@export var credit_weight_trade: float = 0.23
## How hard it charges for PLEDGED attributes (the EXPOSURE line). The only subtractive weight.
@export var credit_weight_exposure: float = 0.30
## Peak invested stat at which TRADE saturates — "a complete specialty". Anchored on 8, the pickpocket
## equipped-weapon threshold (PickpocketSettings), which is this game's one real stat breakpoint.
@export var credit_depth_points: int = 8
## Superlinear dump severity: a pledge of `d` points costs `dump_severity * d^this`. 1.0 = flat per point;
## higher makes hitting a floor categorical rather than incremental (-2 costs 3x a -1, not 2x).
@export var credit_dump_exponent: float = 1.6

@export_subgroup("Standing (payment history + conduct)")
## ⭐THE FIFTH UNDERWRITING LINE, and the only one you EARN rather than build. The four build lines rate who
## you ARE; STANDING rates how you have BEHAVED — payment history is the largest single factor in a real
## credit score, and it is the only way a mediocre build's rating can climb over a run.
## It is a persisted accumulator (GameState.credit_standing) in [-credit_standing_max, +credit_standing_max],
## folded in as `credit_weight_standing * (standing / standing_max)` — so it can push a rating UP or DOWN
## without touching the build monotonicity (standing is independent of every stat).
## ⭐New Game rates the build ALONE: credit_rating_for defaults standing to 0, because a fresh character has
## no history. Everything below is earned in play.
## How much a spotless record is worth, as a share of the score span. 0 = conduct never matters.
@export var credit_weight_standing: float = 0.15
## The normalizer: the standing at which the line is maxed (and the absolute clamp in both directions).
@export var credit_standing_max: float = 100.0
## Standing gained per zorkmid of DEBT REPAID at a terminal — the payment-history engine. Only repayment
## counts; depositing into an already-positive account is saving, not creditworthiness.
@export var credit_standing_per_zm_repaid: float = 0.02
## One-off bonus for clearing a debt COMPLETELY (the account reaching zero or better). The satisfying part.
@export var credit_standing_debt_cleared: float = 10.0
## Standing LOST per in-game day spent in arrears (posted with the debt interest). Carrying a balance is what
## a real score punishes, and it is what stops "borrow and ignore it" from being free.
@export var credit_standing_arrears_per_day: float = 1.0
## ⭐Standing gained per HEADSHOT KILL — doubled for an all-headshot kill. The Ledger's algorithm is opaque
## and rewards "productive conduct" it declines to explain; marginal on purpose (at 0.05 a headshot is worth
## 1/400th of a spotless record), so it flavours a long run instead of replacing the payment history.
## 0 = the surveillance dividend is off.
@export var credit_standing_per_headshot: float = 0.05

@export_subgroup("Bands")
## The four band edges, at the real FICO cuts. Below the first is a decline; at/above the last is the best
## tier. These pick the VERDICT WORDING only (credit_rating_for returns a key) — never the score or limit.
@export var credit_band_subprime_min: int = 400
@export var credit_band_serviceable_min: int = 580
@export var credit_band_bankable_min: int = 670
@export var credit_band_preferred_min: int = 780

@export_subgroup("Filed reason")
## At/above this fraction of the score span the bank files NO adverse reason — a near-perfect build is never
## scolded, it is commended.
@export_range(0.0, 1.0, 0.01) var credit_commendation_fraction: float = 0.95
## Unspent allocation (freed points never reinvested) that overrides the reason ranking with "left undrawn" —
## the player's real problem is idle points, whatever line happens to read lowest.
@export var credit_unspent_reason_points: int = 4
## The bank's MINIMUM on each line. Falling under one is what gets filed, and the file cites the line that
## falls furthest under — deliberately unweighted, because a bank tells you what is MISSING, not what it was
## worth. (Weighting this makes CAPACITY win nearly everywhere and the line stops being informative.)
@export_range(0.0, 1.0, 0.01) var credit_reason_capacity_floor: float = 0.45
@export_range(0.0, 1.0, 0.01) var credit_reason_viability_floor: float = 0.25
@export_range(0.0, 1.0, 0.01) var credit_reason_trade_floor: float = 0.60
## The EXPOSURE line is a ceiling, not a floor — pledging more than this is what gets filed.
@export_range(0.0, 1.0, 0.01) var credit_reason_exposure_ceiling: float = 0.55

## Verdict-band keys, returned by credit_rating_for. NEVER display strings — PlayerText selects a whole
## authored template per key (the ActionSpec.section_key idiom), so re-wording a band can't change behaviour.
const BAND_NO_FILE: StringName = &"no_file"
const BAND_DECLINED: StringName = &"declined"
const BAND_SUBPRIME: StringName = &"subprime"
const BAND_SERVICEABLE: StringName = &"serviceable"
const BAND_BANKABLE: StringName = &"bankable"
const BAND_PREFERRED: StringName = &"preferred"

## Filed-reason keys (the adverse-action-notice parody), likewise display-free.
const REASON_NONE: StringName = &"none"                ## nothing below its floor — a commendation, not a fault
const REASON_NO_FILE: StringName = &"no_file"          ## allocated nothing at all
const REASON_UNSPENT: StringName = &"unspent"          ## freed points never reinvested
const REASON_THIN_TRADE: StringName = &"thin_trade"    ## spread too thin to price
const REASON_NO_INCOME: StringName = &"no_income"      ## no visible means of support
const REASON_MORTALITY: StringName = &"mortality"      ## life expectancy under the repayment term
const REASON_EXPOSURE: StringName = &"exposure"        ## pledged more than is recoverable
const REASON_DELINQUENT: StringName = &"delinquent"    ## the record itself is bad — arrears outweigh repayments


## Pure curve: the Ledger's FULL rating of a creation build. Returns
##   {"score": int, "band": StringName, "reason": StringName,
##    "capacity": float, "viability": float, "trade": float, "exposure": float}
## Static + value-only, so it unit-tests off-tree with no nodes (the long_range_bonus_for mold) — `eco` is a
## plain Resource and EconomySettings.new() constructs one with the shipped defaults. `stat_floor`/
## `stat_ceiling` are the ALLOCATOR's bounds (StatBudget.STAT_MIN/STAT_MAX), forwarded by the caller so the
## normalizers can never drift from the builder that produced the sheet.
##
## ⭐An EMPTY `stat_values` is the ABSENCE of an application, not an all-zero one: it fails OPEN to score_max
## (the bare-scene default in implant_choice.gd, which keeps Begin legitimately never-gated). The all-zero
## SIX-KEY sheet is a genuinely different input — a filed-but-empty form — and is scored normally at the
## baseline. Any future caller that passes {} for a REAL build silently gets the full cap, so don't.
static func credit_rating_for(stat_values: Dictionary, eco: EconomySettings,
		stat_floor: int, stat_ceiling: int, standing: float = 0.0) -> Dictionary:
	if eco == null:
		return {"score": 0, "band": BAND_DECLINED, "reason": REASON_NO_FILE,
			"capacity": 0.0, "viability": 0.0, "trade": 0.0, "exposure": 0.0, "standing": 0.0}
	if stat_values.is_empty():  # no application on file — fail OPEN (see the note above)
		return {"score": eco.credit_score_max, "band": eco.credit_band_for(eco.credit_score_max),
			"reason": REASON_NONE, "capacity": 0.0, "viability": 0.0, "trade": 0.0, "exposure": 0.0,
			"standing": 0.0}

	# --- the authored table, and the normalizers derived from it + the allocator's bounds ------------------
	var rows: Array[StatUnderwriting] = []
	for r in eco.credit_underwriting:
		if r != null and r.stat != &"":
			rows.append(r)
	var ceiling := float(maxi(1, stat_ceiling))
	var exponent := maxf(0.01, eco.credit_dump_exponent)
	# The most points any legal build can INVEST: dumping k stats frees k*|floor| points, and the remaining
	# (n-k) stats can only absorb (n-k)*ceiling of them. The best k is whichever maximizes the smaller.
	var invest_max := 0.0
	for k in range(1, rows.size()):
		invest_max = maxf(invest_max, minf(float(k) * absf(float(stat_floor)), float(rows.size() - k) * ceiling))
	# ...spread across this many stats at most. CAPACITY/VIABILITY normalize against the TOP-`slots` weights
	# (not invest_max x the single best weight), so both lines can actually reach 1.0 and the reason ranking
	# between them stays fair.
	var slots := maxi(1, ceili(invest_max / ceiling)) if invest_max > 0.0 else 1
	var incomes: Array[float] = []
	var survivals: Array[float] = []
	var exp_max := 0.0
	for r in rows:
		incomes.append(maxf(0.0, r.income_weight))
		survivals.append(maxf(0.0, r.survival_weight))
		# ⭐exp_max COUPLES every row: editing one stat's dump_saturation rescales EVERY build's EXPOSURE (it
		# effectively retunes credit_weight_exposure). A test pins this total for exactly that reason.
		exp_max += maxf(0.0, r.dump_severity) * pow(float(maxi(0, r.dump_saturation)), exponent)
	incomes.sort()
	incomes.reverse()
	survivals.sort()
	survivals.reverse()
	var cap_max := 0.0
	var via_max := 0.0
	for i in mini(slots, rows.size()):
		cap_max += incomes[i] * ceiling
		via_max += survivals[i] * ceiling

	# --- the four lines -----------------------------------------------------------------------------------
	var cap := 0.0
	var via := 0.0
	var pledged := 0.0
	var peak := 0.0
	var net := 0.0
	for r in rows:
		var v := float(stat_values.get(r.stat, 0))
		if v > 0.0:
			cap += maxf(0.0, r.income_weight) * v
			via += maxf(0.0, r.survival_weight) * v
			peak = maxf(peak, v)
		elif v < 0.0:
			pledged += maxf(0.0, r.dump_severity) * pow(minf(-v, float(maxi(0, r.dump_saturation))), exponent)
	for stat in stat_values:  # the NET is over the WHOLE sheet, table row or not — idle points are idle points
		net += float(stat_values[stat])
	var depth := float(maxi(1, eco.credit_depth_points))
	var capacity := clampf(cap / cap_max, 0.0, 1.0) if cap_max > 0.0 else 0.0
	var viability := clampf(via / via_max, 0.0, 1.0) if via_max > 0.0 else 0.0
	var trade := clampf(peak / depth, 0.0, 1.0)
	var exposure := clampf(pledged / exp_max, 0.0, 1.0) if exp_max > 0.0 else 0.0

	# --- composition — the ONLY place the five lines meet -------------------------------------------------
	# ⭐STANDING is the one SIGNED line: a good record pushes the rating up, arrears push it down. It is
	# independent of every stat, so it cannot break the build monotonicity the other four guarantee.
	var standing_frac := clampf(standing / maxf(1.0, eco.credit_standing_max), -1.0, 1.0)
	var frac := clampf(clampf(eco.credit_baseline_fraction, 0.0, 1.0)
			+ maxf(0.0, eco.credit_weight_capacity) * capacity
			+ maxf(0.0, eco.credit_weight_viability) * viability
			+ maxf(0.0, eco.credit_weight_trade) * trade
			+ maxf(0.0, eco.credit_weight_standing) * standing_frac
			- maxf(0.0, eco.credit_weight_exposure) * exposure, 0.0, 1.0)
	var score := clampi(roundi(float(eco.credit_score_min)
			+ float(eco.credit_score_max - eco.credit_score_min) * frac),
			mini(eco.credit_score_min, eco.credit_score_max), eco.credit_score_max)

	var untouched := _all_zero(stat_values) and is_zero_approx(standing)
	var band := BAND_NO_FILE if untouched else eco.credit_band_for(score)
	return {"score": score, "band": band,
		"reason": eco.credit_reason_for(frac, net, capacity, viability, trade, exposure, untouched, standing_frac),
		"capacity": capacity, "viability": viability, "trade": trade, "exposure": exposure,
		"standing": standing_frac}


## Thin shim so the score->limit chain and the mirror-the-formula call sites stay one-liners.
static func credit_score_for(stat_values: Dictionary, eco: EconomySettings,
		stat_floor: int, stat_ceiling: int, standing: float = 0.0) -> int:
	return int(credit_rating_for(stat_values, eco, stat_floor, stat_ceiling, standing)["score"])


## True when a sheet was FILED but nothing was allocated — every value exactly 0. Distinct from an empty
## dict (no sheet at all): this one is the player who clicked through creation without building anything.
static func _all_zero(stat_values: Dictionary) -> bool:
	if stat_values.is_empty():
		return false
	for stat in stat_values:
		if int(stat_values[stat]) != 0:
			return false
	return true


## The verdict-band key for `score`. Cuts are read SORTED, so a designer who authors them out of order gets
## sane bands rather than an unreachable tier.
func credit_band_for(score: int) -> StringName:
	var cuts := [credit_band_subprime_min, credit_band_serviceable_min,
		credit_band_bankable_min, credit_band_preferred_min]
	cuts.sort()
	if score < int(cuts[0]):
		return BAND_DECLINED
	if score < int(cuts[1]):
		return BAND_SUBPRIME
	if score < int(cuts[2]):
		return BAND_SERVICEABLE
	if score < int(cuts[3]):
		return BAND_BANKABLE
	return BAND_PREFERRED


## The single filed reason, in priority order: an empty sheet, then a commendation for a near-perfect build,
## then idle points, then whichever underwriting line falls furthest under its authored floor. Shortfalls are
## expressed as a FRACTION of each floor so four differently-scaled lines can be compared at all.
func credit_reason_for(frac: float, net: float, capacity: float, viability: float, trade: float,
		exposure: float, untouched: bool, standing_frac: float = 0.0) -> StringName:
	if untouched:
		return REASON_NO_FILE
	if frac >= clampf(credit_commendation_fraction, 0.0, 1.0):
		return REASON_NONE  # a great record is never scolded
	# ⭐A BAD RECORD outranks every build complaint: it is the one thing the player can fix TODAY (walk to a
	# terminal and pay), so telling them about their stat allocation instead would be useless advice.
	if standing_frac < 0.0:
		return REASON_DELINQUENT
	if maxf(0.0, -net) >= float(maxi(1, credit_unspent_reason_points)):
		return REASON_UNSPENT
	var worst := 0.0
	var reason := REASON_NONE
	var head := 1.0 - clampf(credit_reason_exposure_ceiling, 0.0, 1.0)
	if head > 0.0 and exposure > credit_reason_exposure_ceiling:
		worst = (exposure - credit_reason_exposure_ceiling) / head
		reason = REASON_EXPOSURE
	if credit_reason_viability_floor > 0.0 and viability < credit_reason_viability_floor:
		var s := (credit_reason_viability_floor - viability) / credit_reason_viability_floor
		if s > worst:
			worst = s
			reason = REASON_MORTALITY
	if credit_reason_capacity_floor > 0.0 and capacity < credit_reason_capacity_floor:
		var s := (credit_reason_capacity_floor - capacity) / credit_reason_capacity_floor
		if s > worst:
			worst = s
			reason = REASON_NO_INCOME
	if credit_reason_trade_floor > 0.0 and trade < credit_reason_trade_floor:
		var s := (credit_reason_trade_floor - trade) / credit_reason_trade_floor
		if s > worst:
			worst = s
			reason = REASON_THIN_TRADE
	return reason


@export_group("Banking")
## THE LEDGER ACCOUNT (GameState.account) is ONE SIGNED number: positive = savings, negative = what you owe.
## Debt and savings are the same field with opposite signs, so depositing against a negative balance IS
## repayment — and you can never hold a death-safe hoard WHILE owing, which is what makes "buy on credit,
## bank the profit, then die" structurally impossible rather than something to patch.
##
## ⭐UNIT: one in-game DAY = one WorldClock dawn. A "daily" rate below is a per-in-game-day rate applied to
## UNPAUSED play, not a per-real-day rate — reading it as real days mis-tunes it by orders of magnitude.
## Compounding rate CHARGED per in-game day while the account is NEGATIVE. 0 = debt never grows (feature off).
## Deliberately steeper than the savings rate: an idle debtor should feel the clock, and the asymmetry is what
## stops "borrow everything and sit on it" from being free.
@export var bank_debt_interest_rate: float = 0.02
## Compounding rate PAID per in-game day while the account is POSITIVE. 0 = savings never grow (feature off).
@export var bank_savings_interest_rate: float = 0.005
## Postings smaller than this are suppressed — no sub-coin dust lines and no toast spam on a 3-zorkmid
## balance. 0 = post every accrual however tiny.
@export var bank_interest_min_posting: float = 0.05
## ⭐THE COUNTERWEIGHT KNOB. Service charge on the portion of a purchase NOT covered by pocket cash. Cash pays
## NOTHING — it is free BY CONSTRUCTION, not by exception — so money you already carry is always the cheapest
## way to buy, and this fee is the price of skipping the trip to a terminal rather than a tax on banking.
## Deposits and withdrawals are FREE in both directions on purpose: charge both ends and "withdraw, then pay
## cash" converges with "pay by debit", collapsing the whole decision. 0 = OFF, and at 0 the account strictly
## dominates cash (safe, spendable, interest-bearing) — this is the design's only continuous counterweight.
@export var bank_noncash_fee_fraction: float = 0.03
## Smallest deposit / withdrawal a terminal will process (anti-dust, anti-spam-click). 0 = any amount.
@export var bank_min_transaction: float = 0.0
## Zorkmids added to the RATED credit limit per point of total level (the SUM of the six stats, floored at 0).
## SHIPPED AT 0 = OFF, and at 0 the live line is byte-identically the creation formula. The rated limit prices
## your BUILD and correctly saturates; turn this on only if you want the line to keep growing with your CAREER.
## The limit is a cap on how deep a hole you can dig, not a reward track — an unbounded late-game line defeats
## the interest asymmetry that makes debt matter.
@export var credit_limit_per_level: float = 0.0
## Absolute ceiling on the GROWN line. Inert while credit_limit_per_level is 0. Kept separate from
## credit_limit_max (2100), which remains the cap on the New Game creation cart alone.
@export var credit_limit_lifetime_max: float = 6000.0

## Pure curve: the SIGNED interest for ONE period on a signed balance. Debt and savings are the same number
## with opposite signs, so this is one branch — they can never both run, drift to different periods, or need
## reconciling. Returns the DELTA to add (negative while in debt). Postings under `min_posting` return 0.0, so
## a trivial balance never dribbles. Static + value-only (the long_range_bonus_for mold), unit-testable
## off-tree with no nodes.
static func bank_interest_for(balance: float, debt_rate: float, savings_rate: float,
		min_posting: float) -> float:
	var rate := maxf(0.0, savings_rate) if balance > 0.0 else maxf(0.0, debt_rate)
	var delta := snappedf(balance * rate, Zorkmids.QUANTUM)
	if absf(delta) < maxf(0.0, min_posting):
		return 0.0
	return delta


## The LIVE credit line: the rated limit (which prices the BUILD and saturates correctly) grown by a per-level
## term (which prices the CAREER), capped at the lifetime ceiling and floored to whole quote steps.
## ⭐With credit_limit_per_level at its shipped 0.0 this returns base_limit BYTE-IDENTICALLY — the growth term
## is an off-by-default designer knob, not a behaviour change. maxi(0, total_level) matters: a zero-sum
## creation build sums to 0 and a dumped build sums NEGATIVE, and a net-negative build must not have its line
## shrink below its base (the EXPOSURE line already priced that weakness once).
static func credit_line_for(base_limit: float, total_level: int, per_level: float,
		lifetime_max: float, step: float) -> float:
	var grown := base_limit + maxf(0.0, per_level) * float(maxi(0, total_level))
	var line := clampf(grown, 0.0, maxf(base_limit, lifetime_max))
	if step > 0.0:
		line = floorf(line / step) * step
	return snappedf(line, Zorkmids.QUANTUM)


## The whole rating -> limit -> line chain in ONE call, so New Game's implant cart and the live in-run credit
## line can never quote different numbers for the same sheet.
## ⭐`stat_values` must carry all SIX stat keys: credit_rating_for treats an EMPTY dict as "no application on
## file" and fails OPEN to score_max. ⭐`stat_ceiling` is the ALLOCATOR's bound (StatBudget.STAT_MAX), never a
## difficulty dial — cap_max is NON-monotone in it, so raising it can make ratings easier. Tune the line on the
## limit knobs instead.
static func credit_limit_for_sheet(stat_values: Dictionary, eco: EconomySettings,
		stat_floor: int, stat_ceiling: int, total_level: int, standing: float = 0.0) -> float:
	if eco == null:
		return 0.0
	var score := credit_score_for(stat_values, eco, stat_floor, stat_ceiling, standing)
	var base := credit_limit_for(score, eco.credit_score_min, eco.credit_score_max,
			eco.credit_limit_max, eco.credit_limit_step, eco.credit_limit_curve)
	return credit_line_for(base, total_level, eco.credit_limit_per_level,
			eco.credit_limit_lifetime_max, eco.credit_limit_step)


## Pure curve: the credit LIMIT (zorkmids) a score earns — score_min earns nothing, score_max earns the full
## limit_max, shaped by `curve` (1.0 = the plain linear map; the shipped 1.6 makes a mediocre rating buy
## proportionally less), FLOORED to whole `step`s (banks quote round numbers; 0 = unstepped) and quantized to
## the coin grid. A DEGENERATE score range (min >= max) rates everyone at the cap — the designer's documented
## off-switch for the whole credit check, so it fails OPEN, not closed.
static func credit_limit_for(score: int, score_min: int, score_max: int, limit_max: float, step: float,
		curve: float = 1.0) -> float:
	var capped := maxf(0.0, limit_max)
	var span := float(score_max - score_min)
	if span <= 0.0:
		return snappedf(capped, Zorkmids.QUANTUM)
	var limit := capped * pow(clampf(float(score - score_min) / span, 0.0, 1.0), maxf(0.01, curve))
	if step > 0.0:
		limit = floorf(limit / step) * step
	return snappedf(clampf(limit, 0.0, capped), Zorkmids.QUANTUM)
