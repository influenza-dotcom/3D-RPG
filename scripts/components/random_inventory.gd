class_name RandomInventory
extends Node

## Drop-in loot roller: add this Node under any Character (an NPC especially) and on spawn it drops a RANDOM
## selection of Items into that character's backpack. Pairs with the held-item buff system (PassiveItemBuffs) — the
## default pool is "every passive-buff trinket in the game", so an NPC seeded this way walks around actually wearing
## the buffs (and drops the trinkets as loot when killed). Designer-first: no code, just drop the node and tune the
## @exports; leave them at defaults for "give this NPC 1-2 random trinkets".
##
## TIMING (why it's deferred): a Character builds its `inventory` DURING its own _ready (CharacterInventory.new +
## add_child), but a child node's _ready runs BEFORE its parent's — so at our _ready the bag doesn't exist yet. We
## `call_deferred` the roll, which runs at idle AFTER the whole spawn settles (the NPC has seeded its own loadout by
## then, and we add ON TOP of it). Adding items fires inventory.changed, so PassiveItemBuffs recomputes the buffs.
##
## NOT SAVED: NPC bags aren't serialized, so each spawn re-rolls (set `rng_seed` for a fixed roll per placement).
## Only add this to NPCs — the player's bag is the bounded Tetris grid, and a random dump could overflow it.

## The items this can grant. Leave EMPTY to fall back to every registered Item with a `held_passive_effect`
## (all the passive-buff trinkets). Fill it to restrict the roll to a hand-picked set (e.g. only weapons, only
## a faction's gear). Nulls are ignored.
@export var pool: Array[Item] = []
## When `pool` is empty, draw from every passive-buff Item in ItemDb (via its held_passive_effect). Turn OFF to make
## an empty pool grant nothing (a placed-but-disabled roller).
@export var use_all_passive_items_if_empty: bool = true
## Fewest / most DISTINCT items granted (a count is rolled in [min, max]). With `allow_duplicates` on it's the
## number of PICKS instead, so the same item can come up twice (stacking its buff).
@export var min_items: int = 1
@export var max_items: int = 2
## Allow the same item to be picked more than once (two of a stacking trinket = double buff). Off = distinct items,
## and the count is capped at the pool size.
@export var allow_duplicates: bool = false
## Probability (0..1) this character gets ANY loadout at all — so not every NPC is dripping in trinkets. 1.0 = always.
@export_range(0.0, 1.0, 0.05) var chance: float = 1.0
## Fixed RNG seed for a REPRODUCIBLE roll (same items every spawn). 0 = fresh random each spawn.
@export var rng_seed: int = 0

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	# Deferred: the host's inventory is built during ITS _ready, which runs after ours (children ready first).
	call_deferred(&"_apply")

## Resolve the host + gate on chance, then grant. Called deferred so the backpack exists.
func _apply() -> void:
	var host := _find_host()
	if host == null:
		push_warning("RandomInventory: no Character ancestor — nothing to fill.")
		return
	if host.inventory == null:
		return
	if chance < 1.0 and _rng.randf() > chance:
		return
	var source := _resolve_pool()
	if source.is_empty():
		return
	grant_into(host.inventory, source)

## Pick and add items from `source` into `inv`. Returns how many were granted. Pure-ish (only RNG + inv.add), so a
## test drives it directly with a bare CharacterInventory + explicit pool — no host, no autoload, no _ready.
func grant_into(inv: CharacterInventory, source: Array[Item]) -> int:
	if inv == null or source.is_empty():
		return 0
	var lo := maxi(0, min_items)
	var hi := maxi(lo, max_items)
	var count := _rng.randi_range(lo, hi)
	if count <= 0:
		return 0
	var granted := 0
	if allow_duplicates:
		for i in count:
			inv.add(source[_rng.randi_range(0, source.size() - 1)], 1)
			granted += 1
	else:
		# distinct: shuffle a copy with our seeded RNG (Array.shuffle uses the GLOBAL rng, defeating rng_seed) and take N
		var picks := source.duplicate()
		for i in range(picks.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp: Item = picks[i]
			picks[i] = picks[j]
			picks[j] = tmp
		count = mini(count, picks.size())
		for i in count:
			inv.add(picks[i], 1)
			granted += 1
	return granted

## The effective item list: the authored `pool` (nulls stripped) if any, else every passive-buff Item in ItemDb
## (when use_all_passive_items_if_empty). Empty when nothing qualifies.
func _resolve_pool() -> Array[Item]:
	var out: Array[Item] = []
	if not pool.is_empty():
		for it in pool:
			if it != null:
				out.append(it)
		return out
	if use_all_passive_items_if_empty:
		var db := _item_db()
		if db != null:
			for it in db.all_items():
				if it != null and it.held_passive_effect != null:
					out.append(it)
	return out

## The ItemDb autoload, or null off-tree (a test drives grant_into with an explicit pool instead of touching it).
func _item_db() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null(^"/root/ItemDb")

## Nearest Character ancestor (this node may sit a few levels under the actor), or null.
func _find_host() -> Character:
	var n := get_parent()
	while n != null:
		if n is Character:
			return n as Character
		n = n.get_parent()
	return null
