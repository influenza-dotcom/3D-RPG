class_name StockEntry
extends Resource

## One authored line of a Merchant's stock: WHICH item and HOW MANY of it this specific shop sells.
## Designers fill Merchant.stock_counts with these instead of repeating an item in starting_stock —
## "3 health packs, 20 pistol clips, 2 shotguns" is three entries. Weapons are stocked as one UNIQUE
## instance per count (two shotguns are two distinct objects), exactly like the legacy x1 path.

## The item this shop sells on this line. Null = an empty/ignored row.
@export var item: Item = null
## How many of that item the shop stocks. Weapons are stocked as one UNIQUE instance per count (3 = three distinct objects).
@export_range(1, 999) var count: int = 1
## WR-5 OPTIONAL reputation gate: this line only stocks (at seed AND on each refill) when the player's standing
## with the MERCHANT's faction (Merchant.faction_id) is at least this. 0 (default) = always stocked. Standing is
## on the GameSettings.reputation scale (0 = neutral); a merchant with no faction_id can't measure standing, so
## the gate is ignored and the line stocks. For "the fence only sells the good stuff once the gang trusts you".
@export var required_reputation: float = 0.0
