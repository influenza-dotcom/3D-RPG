class_name CharacterInventory
extends Node

## A character's backpack — the generic item container every Character (player + NPC) carries. Distinct
## from the equipped-weapon hub `Inventory` (scripts/combat/inventory.gd): this holds STACKS of Items;
## that tracks the single drawn WeaponData. Call sites stay unambiguous — `character.inventory` is this
## backpack, `weapon_system.inventory` is the equip hub.
##
## Built in Character._ready() (like GoreSpawner/DustSpawner), so player and NPC both get one. The
## equip seam is the `equip_weapon_requested` signal: when a weapon-item is equipped the container does
## NOT consume it — it just asks its owner to draw that WeaponData, and the owner routes the request
## (player -> SwapWeapons.equip_this for the swap anim; NPC -> weapon_system.inventory.equip directly).
##
## Capacity is unlimited in v1 (no slot cap); `Item.max_stack` only caps how many fit in ONE stack —
## overflow spills into additional stacks, so weapons (max_stack 1) each occupy their own stack.

## Fired whenever the contents change (add / remove / transfer) — the inventory + loot UIs refresh on it.
signal changed
## Fired by equip_item() for a weapon-item; the owning Character listens and actually draws the weapon.
signal equip_weapon_requested(weapon: WeaponData)

## Each entry is {"item": Item, "count": int}. Order is insertion order (stable for the list UI).
var _stacks: Array[Dictionary] = []


## Add `amount` of `item`, filling existing non-full stacks first then spilling into new ones. Returns
## how many were actually added (always `amount` in v1 — capacity is unlimited).
func add(item: Item, amount: int = 1) -> int:
	if item == null or amount <= 0:
		return 0
	var cap: int = maxi(1, item.max_stack)
	var remaining := amount
	for s in _stacks:
		if remaining <= 0:
			break
		if s["item"] == item and s["count"] < cap:
			var put: int = mini(cap - s["count"], remaining)
			s["count"] += put
			remaining -= put
	while remaining > 0:
		var put2: int = mini(cap, remaining)
		_stacks.append({"item": item, "count": put2})
		remaining -= put2
	var added := amount - remaining
	if added > 0:
		changed.emit()
	return added


## Remove up to `amount` of `item` (newest stacks first), erasing emptied stacks. Returns how many were
## actually removed (may be fewer than asked if the backpack held fewer).
func remove(item: Item, amount: int = 1) -> int:
	if item == null or amount <= 0:
		return 0
	var to_remove := amount
	for i in range(_stacks.size() - 1, -1, -1):
		if to_remove <= 0:
			break
		var s: Dictionary = _stacks[i]
		if s["item"] != item:
			continue
		var take: int = mini(s["count"], to_remove)
		s["count"] -= take
		to_remove -= take
		if s["count"] <= 0:
			_stacks.remove_at(i)
	var removed := amount - to_remove
	if removed > 0:
		changed.emit()
	return removed


## Total count of `item` across all its stacks.
func count_of(item: Item) -> int:
	var total := 0
	for s in _stacks:
		if s["item"] == item:
			total += s["count"]
	return total


## True when the backpack holds at least one `item`.
func has(item: Item) -> bool:
	return count_of(item) > 0


## True when the backpack holds nothing.
func is_empty() -> bool:
	return _stacks.is_empty()


## A defensive copy of the stacks ({"item", "count"} dicts) for the UI / loot drop — mutating the
## returned array or its dicts does NOT touch the real inventory.
func contents() -> Array:
	var out: Array = []
	for s in _stacks:
		out.append({"item": s["item"], "count": s["count"]})
	return out


## Move up to `amount` of `item` from this backpack into `other`. Returns how many moved (clamped to
## what's available). The atomic op the loot/transfer UI calls.
func transfer_to(other: CharacterInventory, item: Item, amount: int = 1) -> int:
	if other == null or item == null or amount <= 0:
		return 0
	var move: int = mini(count_of(item), amount)
	if move <= 0:
		return 0
	var removed := remove(item, move)
	other.add(item, removed)
	return removed


## Request that the owner draw this item's weapon. Does NOT consume the stack — the equipped weapon
## stays in the backpack. Returns true only if `item` is actually an equippable weapon-item.
func equip_item(item: Item) -> bool:
	if item == null or not item.is_weapon():
		return false
	equip_weapon_requested.emit(item.weapon)
	return true
