class_name ItemStack
extends Resource

## "N of this item" -- the easy way to author inventory CONTENTS with a COUNT, instead of repeating an Item N
## times. Drop these into a container's / pickup's / NPC's `item_stacks` list: "5 healthpacks, 30 pistol ammo, 2
## shotguns" is three rows (each an item + a count). Weapons are seeded as one UNIQUE instance per count (2
## shotguns = two distinct objects), matching the rest of the loot pipeline; stackables (ammo, junk) stack to the
## count. (Merchant.stock_counts uses StockEntry -- the shop-flavoured twin of this; same {item, count} idea.)

## The item this row holds. Null = an empty / ignored row.
@export var item: Item = null
## How many of it. Weapons become one UNIQUE instance per count; stackables stack to this count. 0 = skip the row.
@export_range(0, 9999) var count: int = 1

## Seed `stacks` into `inv`: weapons as UNIQUE instances (each duplicated), stackables as the shared template.
## Skips null rows, null items, and non-positive counts. The ONE place this rule lives -- reused by ItemContainer
## / CanPickUp / NPC so it can't drift (mirrors LootTable.grant and the legacy duplicate-Item loops). No-op on a
## null inventory (off-tree).
static func seed_into(inv: CharacterInventory, stacks: Array[ItemStack]) -> void:
	if inv == null:
		return
	for s in stacks:
		if s == null or s.item == null or s.count <= 0:
			continue
		if s.item.is_weapon():
			for _n in s.count:
				if inv.add(s.item.duplicate() as Item, 1) <= 0:
					# A bounded grid bag (the player's, or an NPC's once its deferred cap is on) is full with no free
					# footprint. Skip the rest of THIS row but keep seeding the others — one gun that won't fit must not
					# cancel the ammo/medkit behind it. A still-unbounded bag (fresh NPC at spawn / corpse / container) never hits this.
					push_warning("ItemStack: '%s' didn't fit the bounded bag — skipped the rest of the row" % s.item.label())
					break
		elif inv.add(s.item, s.count) <= 0:
			# Same: a full grid-capped bag can't take this stack — warn and continue to the next row rather than
			# aborting the whole loadout (a partial fit still adds what room remains, since add() returns short).
			push_warning("ItemStack: '%s' didn't fit the bounded bag — row skipped" % s.item.label())
