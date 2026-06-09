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
## Fired when the drawn weapon-item leaves the bag (dropped / looted away) or is unequipped — i.e. whenever
## `equipped_item` returns to null. The PLAYER listens and falls back to bare fists; NPCs DON'T connect it
## (their disarm path polls is_armed() instead), so this never disturbs NPC combat.
signal equipped_item_lost

## Each entry is {"item": Item, "count": int}. Order is insertion order (stable for the list UI).
var _stacks: Array[Dictionary] = []

## The item INSTANCE currently drawn (set by equip_item). Because weapons are unique items now, several
## identical weapons (same WeaponData) can be carried as distinct items — this lets the UI mark exactly
## the ONE that's equipped, not every weapon sharing that WeaponData. Null until something is equipped;
## cleared if the equipped item is removed.
var equipped_item: Item = null


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
		if equipped_item != null and not has(equipped_item):
			equipped_item = null  # the drawn weapon left the bag — clear the marker
			equipped_item_lost.emit()  # tell the owner (player falls back to fists)
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


## Total carry weight of everything held: Σ (item.weight × count). The carrier (Character) compares this to
## its carry_capacity to decide encumbrance.
func total_weight() -> float:
	var total := 0.0
	for s in _stacks:
		var it: Item = s["item"]
		if it != null:
			total += it.weight * float(s["count"])
	return total


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


## Total reserve rounds of `caliber` held across all AMMO items (for the reload check).
func ammo_count(caliber: StringName) -> int:
	if caliber == &"":
		return 0
	var total := 0
	for s in _stacks:
		var it: Item = s["item"]
		if it != null and it.is_ammo() and it.caliber == caliber:
			total += s["count"]
	return total

## Remove up to `amount` rounds of `caliber` from the reserve (newest stacks first), erasing emptied
## stacks. Returns how many were actually taken — the reload system uses this to top a clip up.
func take_ammo(caliber: StringName, amount: int) -> int:
	if caliber == &"" or amount <= 0:
		return 0
	var to_remove := amount
	for i in range(_stacks.size() - 1, -1, -1):
		if to_remove <= 0:
			break
		var s: Dictionary = _stacks[i]
		var it: Item = s["item"]
		if it == null or not it.is_ammo() or it.caliber != caliber:
			continue
		var take: int = mini(s["count"], to_remove)
		s["count"] -= take
		to_remove -= take
		if s["count"] <= 0:
			_stacks.remove_at(i)
	var taken := amount - to_remove
	if taken > 0:
		changed.emit()
	return taken


## Request that the owner draw this item's weapon. Does NOT consume the stack — the equipped weapon
## stays in the backpack. Returns true only if `item` is actually an equippable weapon-item.
func equip_item(item: Item) -> bool:
	if item == null or not item.is_weapon():
		return false
	equipped_item = item  # remember WHICH instance is drawn (for the UI's equipped marker)
	equip_weapon_requested.emit(item.weapon)
	return true


## Put the drawn weapon AWAY without dropping it — the item stays in the backpack, but `equipped_item` clears
## and the owner is told (the player falls back to bare fists). No-op when nothing is equipped. This is the
## inventory UI's "unequip" action: clicking the already-equipped weapon toggles it back off.
func unequip() -> void:
	if equipped_item == null:
		return
	equipped_item = null
	equipped_item_lost.emit()
	changed.emit()
