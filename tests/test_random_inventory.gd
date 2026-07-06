extends GutTest

## Contract tests for RandomInventory — the NPC loot-roller. Driven OFF-TREE via grant_into() with a real
## CharacterInventory + an explicit pool + a seeded RNG (no host, no ItemDb autoload, no _ready), per the project
## test rules. Covers the count range, the distinct-vs-duplicates modes, the pool-size cap, seed determinism, and
## the empty-pool guard.

var _inv: CharacterInventory

func before_each() -> void:
	_inv = CharacterInventory.new()  # off-tree, grid off -> add() is unbounded

func after_each() -> void:
	if _inv != null:
		_inv.free()
		_inv = null

## `n` distinct stackable MISC items (ids trinket_0..n-1). Content of the buff is irrelevant to the roller.
func _pool(n: int) -> Array[Item]:
	var out: Array[Item] = []
	for i in n:
		var it := Item.new()
		it.id = StringName("trinket_%d" % i)
		it.display_name = "Trinket %d" % i
		it.category = Item.Category.MISC
		it.max_stack = 9
		out.append(it)
	return out

func _total(inv: CharacterInventory) -> int:
	var t := 0
	for row in inv.contents():
		t += int(row["count"])
	return t

## Sorted multiset of granted item ids (id repeated per count) — for comparing two rolls.
func _granted_ids(inv: CharacterInventory) -> Array:
	var ids: Array = []
	for row in inv.contents():
		var it: Item = row["item"]
		for k in int(row["count"]):
			ids.append(String(it.id))
	ids.sort()
	return ids

## Build a roller with a fixed seed (bypasses _ready) so a test roll is reproducible.
func _roller(seed_val: int) -> RandomInventory:
	var r := RandomInventory.new()
	r._rng.seed = seed_val
	return r

func test_grants_distinct_count_in_range() -> void:
	var r := _roller(123)
	r.min_items = 2
	r.max_items = 2
	r.allow_duplicates = false
	var n := r.grant_into(_inv, _pool(3))
	assert_eq(n, 2, "min==max==2 grants exactly 2")
	assert_eq(_total(_inv), 2, "two items landed in the bag")
	assert_eq(_inv.contents().size(), 2, "distinct mode -> two separate stacks (no repeats)")
	r.free()

func test_distinct_caps_at_pool_size() -> void:
	var r := _roller(7)
	r.min_items = 5
	r.max_items = 5
	r.allow_duplicates = false
	var n := r.grant_into(_inv, _pool(2))  # asked for 5 distinct from a pool of 2
	assert_eq(n, 2, "distinct count is capped at the pool size")
	assert_eq(_total(_inv), 2, "only two distinct items exist to grant")
	r.free()

func test_allow_duplicates_can_repeat() -> void:
	var r := _roller(99)
	r.min_items = 4
	r.max_items = 4
	r.allow_duplicates = true
	var n := r.grant_into(_inv, _pool(2))  # 4 picks from 2 items -> repeats
	assert_eq(n, 4, "with duplicates allowed, count can exceed the pool size")
	assert_eq(_total(_inv), 4, "four total items landed (some stacked)")
	assert_lte(_inv.contents().size(), 2, "repeats stack onto the same item's stack")
	r.free()

func test_same_seed_gives_same_roll() -> void:
	var pool := _pool(5)
	var r1 := _roller(42)
	r1.min_items = 3
	r1.max_items = 3
	r1.grant_into(_inv, pool)
	var inv2 := CharacterInventory.new()
	var r2 := _roller(42)
	r2.min_items = 3
	r2.max_items = 3
	r2.grant_into(inv2, pool)
	assert_eq(_granted_ids(_inv), _granted_ids(inv2), "same rng_seed -> identical roll")
	r1.free()
	r2.free()
	inv2.free()

func test_empty_pool_grants_nothing() -> void:
	var r := _roller(1)
	var empty: Array[Item] = []
	assert_eq(r.grant_into(_inv, empty), 0, "an empty pool grants nothing")
	assert_true(_inv.is_empty(), "the bag stays empty")
	r.free()

func test_zero_count_grants_nothing() -> void:
	var r := _roller(1)
	r.min_items = 0
	r.max_items = 0
	assert_eq(r.grant_into(_inv, _pool(3)), 0, "a 0..0 count range grants nothing")
	r.free()
