class_name Zorkmids
extends RefCounted

## The money system's units + formatting. Zorkmids are FRACTIONAL: amounts run in hundredths (half a
## zorkmid = 0.5), stored as floats but QUANTIZED to QUANTUM on every mutation (Character.add_money snaps),
## so binary-float drift can never accumulate into the economy. Display through fmt(), which prints whole
## amounts bare ("12"), fractions trimmed ("12.5", "0.75") — never a noisy "12.00".

const QUANTUM: float = 0.01  ## the smallest coin — every wallet/price lands on a multiple of this

## Stable id of the coin Item (resources/items/zorkmids.tres). The player's wallet (Character.money, the
## authoritative fractional float) is MIRRORED into a real backpack stack of this item by MoneyPurse, so
## zorkmids show up as a genuine draggable/droppable grid tile. ONE unit of the stack = one QUANTUM (0.01 zm),
## so the integer stack count stays exact while the amount stays fractional (the tile renders count × QUANTUM
## through fmt()). The single source of this id — grid_tile / inventory_screen / GameState / MoneyPurse all
## reference it here. The save DELIBERATELY excludes this stack (money persists separately as the [player]
## wallet float; the purse rebuilds the stack on load), so it must never be treated as ordinary loot.
const ITEM_ID: StringName = &"zorkmids"

## "12" / "12.5" / "0.75" / "-0.5" — quantized, with trailing zeros (and a bare trailing dot) trimmed.
static func fmt(amount: float) -> String:
	var q := snappedf(amount, QUANTUM)
	if is_equal_approx(q, roundf(q)):
		return str(int(roundf(q)))
	return ("%.2f" % q).rstrip("0").rstrip(".")
