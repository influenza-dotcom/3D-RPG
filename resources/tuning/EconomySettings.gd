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
## Fraction of the PLAYER's wallet handed to whoever kills them (0 = keep it all / feature off, 1 = lose it
## all). The zorkmids ride into the killer's wallet and drop as loot when you hunt it down — recover-your-
## losses, Dark-Souls style. Only applies when death revives you IN PLACE (a RELOAD_* death mode resets the
## world, so the transfer is skipped there). Read as GameSettings.economy.death_purse_loss_fraction.
@export_range(0.0, 1.0, 0.05) var death_purse_loss_fraction: float = 1.0

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
