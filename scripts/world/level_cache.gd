extends RefCounted

## @system Run And Level Flow
## @seam LevelCache is GameRoot's in-memory level buffer (Fallout's interior cell buffer): an LRU of DETACHED level instances keyed by LevelData.resource_path. GameRoot parks the outgoing level here instead of freeing it, and a return trip takes the same instance back — NPCs, loot, corpses and dropped items exactly as left.
## @risk The cache OWNS nodes that are outside the tree, so nothing frees them automatically: every evicted / drained node must be freed by the caller (GameRoot frees on eviction and drains on its own PREDELETE), or each reload_current_scene leaks a whole level.
## @test res://tests/test_level_cache.gd
##
## Preloaded as a const where needed (NO class_name — matching WorldSaveId / WorldSnapshot / ChunkGrid). Consumer:
## `const LevelCache = preload("res://scripts/world/level_cache.gd")` (GameRoot).
##
## Pure bookkeeping: it never adds, removes or frees a node itself. put() hands back whatever fell off the far end so the
## caller decides how to free it, and take() hands a node back out of the cache. Freed entries (a node something else
## freed while it sat here) are skipped and dropped on every read, so a stale entry can never be handed back.

## How many parked levels to hold. 0 = keep none (every put evicts at once — the old free-on-leave behaviour).
var capacity: int = 2

## Parked levels, least-recently-used FIRST: [{ "key": String, "node": Node }].
var _entries: Array[Dictionary] = []


func _init(cap: int = 2) -> void:
	capacity = maxi(cap, 0)


## Park `node` under `key` as the most-recently-used entry (replacing an older entry for the same key, which comes back
## in the evicted list). Returns every node pushed out past `capacity`, oldest first — the caller must free them.
func put(key: String, node: Node) -> Array[Node]:
	var evicted: Array[Node] = []
	for i in range(_entries.size() - 1, -1, -1):
		if _entries[i].key == key:
			var old: Variant = _entries[i].node
			_entries.remove_at(i)
			if is_instance_valid(old) and old != node:
				evicted.append(old)
	if is_instance_valid(node):
		_entries.append({"key": key, "node": node})
	evicted.append_array(_trim())
	return evicted


## Take the parked level for `key` out of the cache, or null when there is none (or it was freed meanwhile).
func take(key: String) -> Node:
	for i in range(_entries.size() - 1, -1, -1):
		if _entries[i].key != key:
			continue
		var n: Variant = _entries[i].node
		_entries.remove_at(i)
		if is_instance_valid(n):
			return n
	return null


## Is a live level parked under `key`?
func has(key: String) -> bool:
	for e in _entries:
		if e.key == key and is_instance_valid(e.node):
			return true
	return false


## The parked keys, least-recently-used first (freed entries omitted).
func keys() -> PackedStringArray:
	var out := PackedStringArray()
	for e in _entries:
		if is_instance_valid(e.node):
			out.append(e.key)
	return out


## Change the capacity; returns the nodes that no longer fit (oldest first) for the caller to free.
func set_capacity(cap: int) -> Array[Node]:
	capacity = maxi(cap, 0)
	return _trim()


## Empty the cache and return every live node in it, for the caller to free (GameRoot's PREDELETE).
func drain() -> Array[Node]:
	var out: Array[Node] = []
	for e in _entries:
		if is_instance_valid(e.node):
			out.append(e.node)
	_entries.clear()
	return out


func _trim() -> Array[Node]:
	var out: Array[Node] = []
	# Drop freed entries first so they don't hold a slot a live level could use.
	for i in range(_entries.size() - 1, -1, -1):
		if not is_instance_valid(_entries[i].node):
			_entries.remove_at(i)
	while _entries.size() > capacity:
		var n: Variant = _entries.pop_front().node
		if is_instance_valid(n):
			out.append(n)
	return out
