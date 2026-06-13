class_name StockEntry
extends Resource

## One authored line of a Merchant's stock: WHICH item and HOW MANY of it this specific shop sells.
## Designers fill Merchant.stock_counts with these instead of repeating an item in starting_stock —
## "3 health packs, 20 pistol clips, 2 shotguns" is three entries. Weapons are stocked as one UNIQUE
## instance per count (two shotguns are two distinct objects), exactly like the legacy x1 path.

@export var item: Item = null
@export_range(1, 999) var count: int = 1
