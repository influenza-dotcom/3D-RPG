class_name Zorkmids
extends RefCounted

## The money system's units + formatting. Zorkmids are FRACTIONAL: amounts run in hundredths (half a
## zorkmid = 0.5), stored as floats but QUANTIZED to QUANTUM on every mutation (Character.add_money snaps),
## so binary-float drift can never accumulate into the economy. Display through fmt(), which prints whole
## amounts bare ("12"), fractions trimmed ("12.5", "0.75") — never a noisy "12.00".

const QUANTUM: float = 0.01  ## the smallest coin — every wallet/price lands on a multiple of this

## Stable id of the coin Item (resources/items/zorkmids.tres) — the tile a LOOT SOURCE carries its cash as.
## A corpse / container seeds one at spawn and a live pickpocket target's `money` float is frozen into one for
## the length of a robbery, so cash loots by clicking a tile like any other item. ONE unit of the stack = one
## QUANTUM (0.01 zm), so the integer stack count stays exact while the amount stays fractional (the tile renders
## count × QUANTUM through fmt()).
##
## ⭐THE PLAYER NEVER HOLDS ONE. Their zorkmids are `Character.money` — a plain float, read by the HUD and by
## the backpack's wallet row, dropped through it as a physics money bag. (It was briefly mirrored into a real
## backpack stack, which meant a fat purse ate 1×1..3×3 grid cells; money is not an inventory item.) Taking a
## coin tile therefore CONVERTS it (LootScreen._take -> add_money) rather than moving an Item across, and every
## other path into the player's bag refuses the id outright. The single source of this id — grid_tile /
## inventory_screen / loot_screen / GameState all reference it here.
const ITEM_ID: StringName = &"zorkmids"

## The ONE authored money template — the currency word ("zm") lives HERE, never as a per-call-site
## suffix. Every "<amount> zm" the player reads renders through money_text, so a locale that writes
## its currency in front ("zm {amount}") re-authors exactly one string.
const MONEY_TEMPLATE := "{amount} zm"

## "12" / "12.5" / "0.75" / "-0.5" — quantized, with trailing zeros (and a bare trailing dot) trimmed.
## Delegates to TextFormat.num (the single number-formatter seam) — output matches the old in-place idiom
## for all pinned/practical values, EXCEPT one deliberate fix: the old is_equal_approx integer shortcut had
## RELATIVE tolerance, so wallets above ~1000 zm silently swallowed a real cent (fmt(1500.01) printed
## "1500"); the new path prints "1500.01". tests/test_money.gd pins the shapes incl. the large-wallet case.
static func fmt(amount: float) -> String:
	return TextFormat.num(snappedf(amount, QUANTUM))


## The whole "<amount> zm" money phrase ("12 zm", "0.5 zm") — substitute THIS into sentence
## templates as a {money} token instead of appending " zm" at the call site.
static func money_text(amount: float) -> String:
	return TextFormat.subst(MONEY_TEMPLATE, {"amount": fmt(amount)})
