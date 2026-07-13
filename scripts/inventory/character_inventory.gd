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
## Capacity is unlimited by default (no slot cap); `Item.max_stack` only caps how many fit in ONE stack —
## overflow spills into additional stacks, so weapons (max_stack 1) each occupy their own stack.
##
## SPATIAL GRID (T2): the backpack can OPTIONALLY enforce a Tetris-style spatial cap. It's DISABLED by default —
## add() stays unlimited, exactly as before — so a fresh corpse-copy / container / merchant-stock bag (and the
## unit tests) keep v1 behaviour and never silently lose loot until something opts them in. Both the PLAYER
## (Player._ready) and every NPC (NPC._ready) call enable_grid(cols, rows) at the SAME size (InventorySettings.
## grid_cols/rows), so an NPC carries no more than the player and the bag it drops matches the player's grid.
## Once bounded, every NEW stack must claim a free width×height footprint (item.grid_width × grid_height,
## rotatable) or the add stops short (returns fewer than asked). Each STACK (not each unit) occupies ONE
## footprint. The placement lives in the pure InventoryGrid keyed by a per-stack int; persistence reads it via
## placed_contents() and the load path rebuilds it via restore_stack(). Topping up an existing stack needs no new cell.

## Fired whenever the contents change (add / remove / transfer) — the inventory + loot UIs refresh on it.
signal changed
## Fired by equip_item() for a weapon-item; the owning Character listens and actually draws the weapon.
signal equip_weapon_requested(weapon: WeaponData)
## Fired when the drawn weapon-item leaves the bag (dropped / looted away) or is unequipped — i.e. whenever
## `equipped_item` returns to null. The PLAYER listens and falls back to bare fists; NPCs DON'T connect it
## (their disarm path polls is_armed() instead), so this never disturbs NPC combat.
signal equipped_item_lost

## Each entry is {"item": Item, "count": int, "key": int}. Order is insertion order (stable for the list UI);
## `key` is the stable per-stack id the spatial grid places by (survives a stack erase / future reorder).
var _stacks: Array[Dictionary] = []

## The pure spatial model + whether the cap is enforced. DISABLED (cols/rows 0) until enable_grid() — see the
## class doc: an off grid leaves add() unlimited (v1). The player and every NPC turn it on at the same size; a
## fresh corpse-copy / container / merchant bag stays off until the loot screen grids it on open.
var _grid := InventoryGrid.new()
var _grid_enabled: bool = false
var _next_key: int = 0  ## hands each new stack its grid key

## COALESCE-`changed` latch for transfer_to. transfer_to mutates THIS bag twice (remove, then a rollback add of
## whatever the destination couldn't fit); a mirror listener wired to `changed` (MoneyPurse.sync via
## inventory.changed) must NOT fire on the intermediate post-remove state and grab the freed cells before the
## rollback re-homes the bounced remainder. While `_defer_changed` is set, add()/remove() route their emit
## through _emit_changed() which just records `_pending_changed`; transfer_to emits ONCE at the very end, after
## the rollback has settled, so a listener only ever sees the final counts/placements.
var _defer_changed: bool = false
var _pending_changed: bool = false

## The ids this backpack MIRRORS from an external source of truth (today only the MoneyPurse coin tile, keyed by
## Zorkmids.ITEM_ID). A mirrored item is a DERIVED VIEW — its count reflects a float owned elsewhere
## (Character.money), not real loot. Only the PLAYER's backpack registers one (MoneyPurse._ready); NPC / corpse /
## container bags never do, so their identical-looking coin tile is genuine loot. See is_mirrored / register_mirror.
var _mirrored_ids: Dictionary = {}

## The item INSTANCE currently drawn (set by equip_item). Because weapons are unique items now, several
## identical weapons (same WeaponData) can be carried as distinct items — this lets the UI mark exactly
## the ONE that's equipped, not every weapon sharing that WeaponData. Null until something is equipped;
## cleared if the equipped item is removed.
var equipped_item: Item = null


## Turn ON the spatial cap at cols×rows — a bounded Tetris bag. The player calls it BEFORE seeding so restored
## stacks auto-place; an NPC calls it (deferred) AFTER seeding so a normal loadout never truncates and only an
## over-authored bag's overflow is left unplaced. Idempotent / re-sizable: it re-places every existing stack
## top-left-first; a stack that no longer fits is kept in the bag but left unplaced (with a warning). With the
## grid OFF (the default) add() is unlimited, exactly as v1 — so a corpse-copy / container bag never rejects loot.
func enable_grid(cols: int, rows: int) -> void:
	_grid.configure(cols, rows)
	_grid_enabled = true
	for s in _stacks:
		var it: Item = s["item"]
		if it == null:
			continue
		var slot := _grid.find_free_slot(it.grid_width, it.grid_height, true)
		if slot["found"]:
			_grid.place(s["key"], slot["x"], slot["y"], slot["w"], slot["h"])
		else:
			push_warning("CharacterInventory: '%s' didn't fit when enabling the %d×%d grid — left unplaced" % [it.label(), cols, rows])

## Turn the spatial cap back OFF — the bag returns to the unlimited v1 model (placements dropped, stacks kept).
## The clean inverse of enable_grid, kept as part of the grid API. Currently no caller un-bounds a bag at
## runtime: the player and NPCs stay bounded for life, and corpses/containers keep whatever grid they were
## opened with. (Older builds un-gridded a LIVE pickpocket / exchange source on close, back when only the
## player's bag was bounded; NPCs now carry the same permanent cap, so that call was removed.)
func disable_grid() -> void:
	_grid_enabled = false
	_grid.configure(0, 0)  # drop all placements; the grid is inert while disabled

## Is the spatial cap on? (false = the unlimited v1 backpack — a fresh corpse-copy, container, or merchant
## stock before the loot screen grids it. The player and live NPCs are bounded, so this reads true for them.)
func grid_enabled() -> bool:
	return _grid_enabled

## Grid dimensions (0 when the grid is off) — the UI reads these to lay out cells. See enable_grid.
func grid_cols() -> int:
	return _grid.cols

func grid_rows() -> int:
	return _grid.rows

## Build a fresh stack dict with a unique grid key (the stable id the spatial grid places by).
func _new_stack(item: Item, count: int) -> Dictionary:
	var key := _next_key
	_next_key += 1
	return {"item": item, "count": count, "key": key}


## Emit `changed`, unless transfer_to has asked to COALESCE (its own remove + rollback) — then just record that a
## change is pending and let transfer_to fire the single, final emit. The three mutators transfer_to may call —
## add(), remove(), and restore_stack() (only for the unplaced-remainder rollback) — route their emit through here;
## the others (set_item_count / remove_stack / move_stack / take_ammo / unequip) emit directly because transfer_to
## never calls them, and the latch is off (false) everywhere else, so their behaviour is unchanged.
func _emit_changed() -> void:
	if _defer_changed:
		_pending_changed = true
		return
	changed.emit()


## Register `id` as a MIRRORED view on this backpack (called once by MoneyPurse._ready with Zorkmids.ITEM_ID).
## Idempotent; a blank id is ignored. This is the single place the "is this a wallet mirror, not real cash?"
## question is registered, so a looting path can debit a source's separate `money` float ONLY for a genuine mirror.
func register_mirror(id: StringName) -> void:
	if id != &"":
		_mirrored_ids[id] = true


## True when `item` is a DERIVED VIEW (a MoneyPurse coin tile) on THIS backpack, not real loot. LootScreen gates
## its wallet-float debit on this so taking a REAL coin tile (from a corpse / container / live-pickpocket NPC —
## none of which register a mirror) never also drains that source's separate `money` float. False for a null item.
func is_mirrored(item: Item) -> bool:
	return item != null and _mirrored_ids.has(item.id)


## Add `amount` of `item`, filling existing non-full stacks first then spilling into new ones. Returns how many
## were actually added — always `amount` with the grid off, but FEWER (down to 0) once the bounded player grid
## can't fit another stack's footprint. Topping up an existing stack needs no new cell, so it never fails.
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
		var slot: Dictionary = {}
		if _grid_enabled:
			# Each new stack must claim a free footprint (rotatable). None free -> stop; add only what fit.
			slot = _grid.find_free_slot(item.grid_width, item.grid_height, true)
			if not slot["found"]:
				break
		var put2: int = mini(cap, remaining)
		var stack := _new_stack(item, put2)
		_stacks.append(stack)
		if _grid_enabled:
			_grid.place(stack["key"], slot["x"], slot["y"], slot["w"], slot["h"])
		remaining -= put2
	var added := amount - remaining
	if added > 0:
		_emit_changed()  # coalesced when transfer_to is rolling a bounce back (see _emit_changed)
	return added


## The first carried item whose Item.id matches, or null — how systems that care about a KIND of item (a
## Lock needing &"lockpick", a door needing &"keycard_red") find one without holding the exact instance.
func find_by_id(id: StringName) -> Item:
	if id == &"":
		return null
	for s in _stacks:
		var it: Item = s["item"]
		if it != null and it.id == id:
			return it
	return null


## The strongest carried weapon-item by WeaponData.power_score (null when unarmed) — the NPC "equip the
## strongest" rule and the container-scavenge comparison both rank with this.
func best_weapon_item() -> Item:
	var best: Item = null
	var best_score := -1.0
	for s in _stacks:
		var it: Item = s["item"]
		if it != null and it.is_weapon():
			var score := it.weapon.power_score()
			if score > best_score:
				best_score = score
				best = it
	return best


## The first carried HEALING consumable (is_consumable with heal_amount > 0), or null — what a hurt NPC
## reaches for (the SelfHealer drop-in, self_healer.gd).
func find_healing_consumable() -> Item:
	for s in _stacks:
		var it: Item = s["item"]
		if it != null and it.is_consumable() and it.heal_amount > 0.0:
			return it
	return null


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
			if _grid_enabled:
				_grid.remove(s["key"])  # free the footprint so the freed space can hold something else
			_stacks.remove_at(i)
	var removed := amount - to_remove
	if removed > 0:
		if equipped_item != null and not has(equipped_item):
			equipped_item = null  # the drawn weapon left the bag — clear the marker
			equipped_item_lost.emit()  # tell the owner (player falls back to fists)
		if _grid_enabled:
			_rehome_unplaced()  # freed cells may now fit a stack that was stuck unplaced (P0-3a)
		_emit_changed()  # coalesced when transfer_to is mid-rollback (see _emit_changed)
	return removed


## Remove the EXACT stack the grid UI right-clicked, identified by its stable grid `key`, and return how many units
## it held (0 if no live stack carries that key). Unlike remove(item, n) — which drains the NEWEST matching stacks
## first — this drops precisely the clicked tile, so the freed grid footprint AND the dropped count are the ones the
## player pointed at. Two stacks of the same shared template no longer empty the wrong tile: two unstackable dog
## crates (two count-1 stacks), or a stackable item split 5+2, drop exactly the stack clicked. Frees the stack's grid
## placement and, if the drawn weapon left the bag, clears the equipped marker (mirrors remove()). Emits `changed`.
func remove_stack(key: int) -> int:
	for i in range(_stacks.size()):
		var s: Dictionary = _stacks[i]
		if s["key"] != key:
			continue
		var count: int = s["count"]
		if _grid_enabled:
			_grid.remove(key)  # free the footprint so the freed space can hold something else
		_stacks.remove_at(i)
		if equipped_item != null and not has(equipped_item):
			equipped_item = null  # the drawn weapon left the bag — clear the marker
			equipped_item_lost.emit()  # tell the owner (player falls back to fists)
		if _grid_enabled:
			_rehome_unplaced()  # freed cells may now fit a stack that was stuck unplaced (P0-3a)
		changed.emit()
		return count
	return 0


## Force the backpack to hold EXACTLY `count` units of `item` in a SINGLE stack at a given grid FOOTPRINT, keeping
## that stack's key when it already exists (so a live tile keeps its identity as the value ticks). `foot_w`/`foot_h`
## <= 0 fall back to the item's authored grid_width/height; pass a bigger square to make the pile take up more cells
## as it grows — the zorkmids stack, whose footprint MoneyPurse scales with the wallet. count <= 0 removes every
## stack of `item`. This is the seam for a DERIVED / mirrored quantity owned elsewhere — money lives on
## Character.money and is pushed in here (money is the source of truth; this stack is a self-healing VIEW). Unlike
## add(), it never merges by max_stack and never spills into a second stack — a mirrored singleton is always one
## tile. Surplus duplicate stacks (there should be none) are dropped defensively. Returns true and emits `changed`
## iff it altered anything, so re-asserting the same value + footprint each frame is a cheap no-op (no churn).
func set_item_count(item: Item, count: int, foot_w: int = 0, foot_h: int = 0) -> bool:
	if item == null:
		return false
	count = maxi(0, count)
	var fw: int = foot_w if foot_w > 0 else maxi(1, item.grid_width)
	var fh: int = foot_h if foot_h > 0 else maxi(1, item.grid_height)
	# Locate the FIRST stack of this item plus any surplus duplicates.
	var first := -1
	var extras: Array[int] = []
	for i in _stacks.size():
		if _stacks[i]["item"] == item:
			if first < 0:
				first = i
			else:
				extras.append(i)
	var changed_any := false
	# Collapse any accidental duplicates back to one (walk high->low so removal doesn't shift lower indices;
	# fix up `first` when a dropped index sat before it).
	for j in range(extras.size() - 1, -1, -1):
		var idx: int = extras[j]
		if _grid_enabled:
			_grid.remove(_stacks[idx]["key"])
		_stacks.remove_at(idx)
		changed_any = true
		if idx < first:
			first -= 1
	if count == 0:
		if first >= 0:
			if _grid_enabled:
				_grid.remove(_stacks[first]["key"])  # free the cells so the emptied pile stops occupying space
			_stacks.remove_at(first)
			changed_any = true
	elif first >= 0:
		if int(_stacks[first]["count"]) != count:
			_stacks[first]["count"] = count  # update IN PLACE — key untouched, so the tile keeps its identity
			changed_any = true
		# Fit the placement to the target footprint: grow/shrink the pile's square as the wallet crosses a size tier,
		# re-home it if it was left unplaced (bag was full), and keep it put when nothing changed. Only ever claims
		# FREE cells — never evicts another item; if the bigger footprint won't fit anywhere it stays its old size.
		if _grid_enabled and _refit_placement(_stacks[first]["key"], fw, fh):
			changed_any = true
	else:
		# No stack yet — create one at the target footprint, auto-placing top-left-first when the bounded grid is on.
		# A bag too full to fit it leaves it UNPLACED (kept, no tile) rather than lost; the amount is still correct on
		# the wallet + HUD, and a later set_item_count re-homes it once room frees (via _refit_placement above).
		var slot: Dictionary = {}
		if _grid_enabled:
			slot = _grid.find_free_slot(fw, fh, true)
			if not slot["found"]:
				push_warning("CharacterInventory: no free %d×%d block for '%s' — kept unplaced (bag full)" % [fw, fh, item.label()])
		var stack := _new_stack(item, count)
		_stacks.append(stack)
		if _grid_enabled and slot.get("found", false):
			_grid.place(stack["key"], slot["x"], slot["y"], slot["w"], slot["h"])
		changed_any = true
	if changed_any:
		changed.emit()
	return changed_any


## Ensure the placed stack `key` occupies an `fw`×`fh` footprint, growing/shrinking it as its owner's size tier
## changes. Order of preference: (1) already that footprint -> nothing; (2) grow/shrink at the SAME top-left (keeps
## the tile put; place() rolls back to the old cells on a bad fit); (3) relocate to a free slot big enough (freeing
## the old cells first so a LARGER footprint can reuse the space it sat on); (4) if nothing fits, RESTORE the old
## placement — a mirrored pile must never vanish just because it can't grow. Never evicts other items (free cells
## only). An unplaced key skips straight to step 3. Returns true iff it changed the grid. Guard `_grid_enabled` at
## the call site (this touches `_grid` unconditionally).
func _refit_placement(key: int, fw: int, fh: int) -> bool:
	var p := _grid.placement_of(key)
	if not p.is_empty() and int(p["w"]) == fw and int(p["h"]) == fh:
		return false  # already the right footprint — leave it exactly where it sits
	if not p.is_empty() and _grid.place(key, int(p["x"]), int(p["y"]), fw, fh):
		return true  # grew/shrank at the same corner
	var had := not p.is_empty()
	if had:
		_grid.remove(key)  # free the old cells so a bigger footprint can reuse the space it sat on
	var slot := _grid.find_free_slot(fw, fh, true)
	if slot["found"]:
		_grid.place(key, int(slot["x"]), int(slot["y"]), int(slot["w"]), int(slot["h"]))
		return true
	if had:
		_grid.place(key, int(p["x"]), int(p["y"]), int(p["w"]), int(p["h"]))  # couldn't fit the new size — restore old
	return false


## Give unplaced stacks a footprint the moment cells free up. A stack can sit IN the bag but tile-less (x<0) when it
## couldn't fit at add/restore time — e.g. a LootableCorpse seeds its wallet as a coin tile with the grid off, then
## LootScreen enable_grid()s the copy and the coin overflows a full loot grid. GridInventoryView draws no tile for an
## unplaced stack, so it can't be taken → is_empty() never trues → the ragdoll's linger-until-drained fade never fires
## and the corpse is a lootable-but-unlootable soft-lock (P0-3a). Called after any removal frees cells. Only ever
## claims FREE cells (never evicts). Returns true iff it placed at least one stack. Guard `_grid_enabled` at the call.
func _rehome_unplaced() -> bool:
	var any := false
	for s in _stacks:
		var it: Item = s["item"]
		if it == null or not _grid.placement_of(s["key"]).is_empty():
			continue
		var slot := _grid.find_free_slot(it.grid_width, it.grid_height, true)
		if slot["found"]:
			_grid.place(s["key"], int(slot["x"]), int(slot["y"]), int(slot["w"]), int(slot["h"]))
			any = true
	return any


## Total count of `item` across all its stacks.
func count_of(item: Item) -> int:
	var total := 0
	for s in _stacks:
		if s["item"] == item:
			total += s["count"]
	return total


## Total count of items of a KIND (by Item.id) across all stacks — restock/refill logic compares against an
## authored baseline by id, since weapons are UNIQUE instances and can't be counted by a single instance.
func count_of_id(id: StringName) -> int:
	var total := 0
	for s in _stacks:
		var it: Item = s["item"]
		if it != null and it.id == id:
			total += s["count"]
	return total


## Accumulate `count` of `item` into a {id -> {"item", "count"}} baseline map (summing repeats of the same id).
## A static builder so Merchant/ItemContainer can describe "what a full inventory holds" from their authored
## stock lists, then hand it to refill_to_baseline. Skips null items / non-positive counts.
static func accumulate_baseline(baseline: Dictionary, item: Item, count: int) -> void:
	if item == null or count <= 0:
		return
	var id: StringName = item.id
	if baseline.has(id):
		baseline[id]["count"] += count
	else:
		baseline[id] = {"item": item, "count": count}


## Top `inv` back up to `baseline` (from accumulate_baseline), adding ONLY the shortfall per item kind — never
## doubling what's there, never removing surplus the player sold/deposited in. Weapons restock as UNIQUE
## duplicates; stackables top up the existing stack. The shared engine behind Merchant/ItemContainer refill().
static func refill_to_baseline(inv: CharacterInventory, baseline: Dictionary) -> void:
	if inv == null:
		return
	for id in baseline:
		var item: Item = baseline[id]["item"]
		if item == null:
			continue
		var short: int = int(baseline[id]["count"]) - inv.count_of_id(id)
		if short <= 0:
			continue
		if item.is_weapon():
			for _i in short:
				inv.add(item.duplicate() as Item, 1)  # one unique instance per missing weapon
		else:
			inv.add(item, short)


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


## Move up to `amount` of `item` from this backpack into `other`. Returns how many ACTUALLY moved — clamped
## both to what's available here AND to what `other` can fit (a bounded grid bag may be full). Atomic: anything
## `other` couldn't take is restored to this bag, so a full destination never makes items vanish.
##
## SIGNAL INVARIANT: this COALESCES its own `changed` across the remove + rollback add, emitting exactly ONCE at
## the end (after the rollback has settled). A mirror listener wired to `changed` (MoneyPurse.sync via
## inventory.changed) therefore never sees the intermediate post-remove state and so can't grab the freed cells
## before the bounced remainder is re-homed — otherwise a full-bag bounce would land unplaced / be lost. `other`'s
## OWN emissions stay independent (its listeners see its real add). The resulting counts/placements are identical
## to the old two-emit path; only the number of `changed` this bag fires per transfer drops from two to one.
func transfer_to(other: CharacterInventory, item: Item, amount: int = 1) -> int:
	if other == null or item == null or amount <= 0:
		return 0
	var move: int = mini(count_of(item), amount)
	if move <= 0:
		return 0
	# Skip a guaranteed-failed deposit's remove/add round-trip (it disarms then re-arms the wielder — a signal storm)
	# when the destination can't hold even one unit. A partial-fit destination (can_accept true) still does the trip below.
	if other.has_method(&"can_accept") and not other.can_accept(item):
		return 0
	var was_equipped := (item == equipped_item)  # remove() below may clear the equipped marker + fire the lost signal
	# Coalesce THIS bag's `changed` across the remove + any rollback so a mirror listener sees only the final state.
	_defer_changed = true
	var removed := remove(item, move)
	var moved := other.add(item, removed)
	if moved < removed:
		var back := add(item, removed - moved)  # destination couldn't fit it all -> put the remainder back here
		if back < (removed - moved):
			# Even our own bag couldn't re-home the whole bounce (its grid filled). Keep the remainder as an
			# unplaced stack rather than destroy it — money/loot must never vanish just because the tile can't place.
			push_warning("CharacterInventory.transfer_to: rollback re-homed only %d/%d of '%s' — restoring remainder unplaced" % [back, removed - moved, item.label()])
			restore_stack(item, (removed - moved) - back)
		# If the WIELDED weapon fully bounced back, remove() already cleared equipped_item and disarmed the
		# owner (player dropped to fists). Re-establish the marker so a fully-rejected transfer doesn't disarm.
		if was_equipped and equipped_item == null and has(item):
			equipped_item = item
			equip_weapon_requested.emit(item.weapon)
	# Release the latch and fire the single, final emit — the listener now sees the settled counts/placements.
	_defer_changed = false
	if _pending_changed:
		_pending_changed = false
		changed.emit()
	return moved


## Would a single unit of `item` find a home right now? True with the grid off, or when an existing non-full
## stack can absorb it, or a free footprint exists. The shop / world-pickup pre-check this so the player isn't
## charged (or a world pickup consumed) for something the bounded bag can't actually hold.
func can_accept(item: Item) -> bool:
	if item == null:
		return false
	if not _grid_enabled:
		return true
	var cap: int = maxi(1, item.max_stack)
	for s in _stacks:
		if s["item"] == item and s["count"] < cap:
			return true
	return _grid.find_free_slot(item.grid_width, item.grid_height, true)["found"]


## Like contents(), but every row also carries the stack's grid KEY and placement: {item, count, key, x, y, w, h}.
## x/y are -1 (and w/h fall back to the item's footprint) when the grid is off or a stack is unplaced. The grid
## UI renders rectangles from this and passes `key` back to move_stack/can_place_stack to drag a tile;
## GameState.capture serializes id/count/x/y/w/h (it ignores key — that's a runtime handle, not persisted).
func placed_contents() -> Array:
	var out: Array = []
	for s in _stacks:
		var it: Item = s["item"]
		var fw: int = it.grid_width if it != null else 1
		var fh: int = it.grid_height if it != null else 1
		var row := {"item": it, "count": s["count"], "key": s["key"], "x": -1, "y": -1, "w": fw, "h": fh}
		if _grid_enabled:
			var p := _grid.placement_of(s["key"])
			if not p.is_empty():
				row["x"] = p["x"]
				row["y"] = p["y"]
				row["w"] = p["w"]
				row["h"] = p["h"]
		out.append(row)
	return out


## Can the stack identified by `key` sit as a w×h footprint at (x, y)? The grid UI calls this to tint the drop
## preview while dragging (and while rotating — pass swapped w/h). Ignores the stack's OWN cells so it can slide
## over where it currently sits. False with the grid off or for an unknown key.
func can_place_stack(key: int, x: int, y: int, w: int, h: int) -> bool:
	if not _grid_enabled or not _has_stack_key(key):
		return false
	return _grid.can_place(x, y, w, h, key)


## Move (and/or rotate) an already-placed stack to a new w×h footprint at (x, y) — the grid UI's drag-drop commit.
## Delegates to InventoryGrid.place (move-with-rollback: a bad target leaves the old placement intact). Returns
## true on success and emits `changed` so the view refreshes. No-op (false) with the grid off or an unknown key.
func move_stack(key: int, x: int, y: int, w: int, h: int) -> bool:
	if not _grid_enabled or not _has_stack_key(key):
		return false
	if _grid.place(key, x, y, w, h):
		changed.emit()
		return true
	return false


## Does a live stack carry this grid key? (Guards move/can_place against a stale key from an old placed_contents.)
func _has_stack_key(key: int) -> bool:
	for s in _stacks:
		if s["key"] == key:
			return true
	return false


## Append EXACTLY ONE stack of `item` (count units) at a saved placement — the load path's stack-by-stack
## rebuild, which must NOT merge like add() (so the 1:1 stack↔placement mapping the save recorded is preserved).
## With the grid on it tries the saved cell (x,y,w,h), then auto-places if that's taken / out of bounds (grid
## shrank, or the item's authored footprint drifted); a stack that fits NOWHERE is still kept in the bag,
## unplaced, rather than lost. Pass x < 0 to auto-place (an old save with no placement data). Returns true if a
## grid cell was claimed (always true with the grid off, where placement is irrelevant).
func restore_stack(item: Item, count: int, x: int = -1, y: int = -1, w: int = -1, h: int = -1) -> bool:
	if item == null or count <= 0:
		return false
	var stack := _new_stack(item, count)
	_stacks.append(stack)
	var placed := true
	if _grid_enabled:
		placed = false
		if x >= 0 and y >= 0 and w >= 1 and h >= 1 and _grid.place(stack["key"], x, y, w, h):
			placed = true
		else:
			var slot := _grid.find_free_slot(item.grid_width, item.grid_height, true)
			if slot["found"]:
				_grid.place(stack["key"], slot["x"], slot["y"], slot["w"], slot["h"])
				placed = true
			else:
				push_warning("CharacterInventory: restored '%s' didn't fit the grid — kept unplaced" % item.label())
	_emit_changed()  # coalesced when transfer_to's rollback uses restore_stack for the unplaced remainder
	return placed


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
			if _grid_enabled:
				_grid.remove(s["key"])  # free the footprint when an ammo stack empties
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
