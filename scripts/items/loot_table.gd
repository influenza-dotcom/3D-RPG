@tool
class_name LootTable
extends Resource

## @tool: pure data resource (no node lifecycle), so it's safe to run in the editor -- and REQUIRED there, because
## the LootTable inspector's "Roll 1000x" button calls roll() at edit time. A non-@tool script's instance method
## can't be called in tool mode (the bug that bit the Factions matrix). Mirrors NpcData, already @tool.

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
					# The bag is a BOUNDED grid (player OR NPC — both grid-capped now) with no free footprint. Skip the
					# rest of THIS entry but keep rolling the others: each LootEntry drops INDEPENDENTLY (class doc), so one
					# gun that won't fit must not cancel the medkit behind it. A still-unbounded corpse-copy/container never hits this.
					push_warning("LootTable: '%s' didn't fit the bounded bag — dropped from the grant" % it.label())
					break
		elif inv.add(it, count) <= 0:
			# Same: a full grid-capped bag can't take this stack — warn and move on to the next entry rather than
			# aborting the whole table (partial fits still add what room remains, as add() already returns short).
			push_warning("LootTable: '%s' didn't fit the bounded bag — dropped from the grant" % it.label())
