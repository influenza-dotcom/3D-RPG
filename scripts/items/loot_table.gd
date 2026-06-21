class_name LootTable
extends Resource

## A data-driven LOOT TABLE: a list of LootEntry rows, each rolled INDEPENDENTLY. roll() is a PURE function
## (takes an RNG) so it's deterministic + unit-testable; grant() rolls + adds the results to an inventory,
## duplicating weapons so each is its own object (matching the rest of the loot pipeline). Assign one to
## NpcData.loot — rolled into the backpack on death (NPC.gore) so it lands in the corpse — or to a
## container / pickup later. Mirrors the WeaponData / NpcData data-resource pattern.

## The drop rows in this table. Each LootEntry is rolled INDEPENDENTLY, so mix guaranteed drops with rare ones freely.
@export var entries: Array[LootEntry] = []

## Roll every entry independently against `rng`. Returns a list of { "item": Item, "count": int } for the
## entries that hit. PURE (no global random) — pass a seeded RNG for deterministic tests.
func roll(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for e in entries:
		if e == null or e.item == null:
			continue
		if rng.randf() < e.chance:  # strict: chance 0.0 never drops (randf() can be exactly 0.0), 1.0 always
			var lo := maxi(0, e.min_count)
			var hi := maxi(lo, e.max_count)
			var count := rng.randi_range(lo, hi)
			if count > 0:
				out.append({"item": e.item, "count": count})
	return out

## Roll this table and ADD the results to `inv` — weapons as UNIQUE instances (each duplicated), like the
## rest of the loot/pickup pipeline; stackables (ammo, junk) added as the shared template.
func grant(inv: CharacterInventory, rng: RandomNumberGenerator) -> void:
	if inv == null:
		return
	for d in roll(rng):
		var it: Item = d["item"]
		# ML-4: difficulty scales drop quantity (1.0 at Normal = unchanged). A roll that HIT still yields >= 1.
		var count: int = maxi(1, roundi(float(d["count"]) * GameSettings.difficulty.loot_mult))
		if it.is_weapon():
			for _n in count:
				if inv.add(it.duplicate() as Item, 1) <= 0:
					return  # bounded (player) bag full -> stop granting; a no-op on an unbounded NPC/corpse bag
		elif inv.add(it, count) <= 0:
			return
