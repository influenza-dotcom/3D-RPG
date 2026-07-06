extends GutTest

## Tests for RandomCoat — the "pick a random albedo per instance" cosmetic drop-in. The PICK is pure static maths
## (literal rolls, no tree), so it's unit-tested here. The actual recolour (duplicate material_override + set albedo)
## is in-tree / deferred and needs a real MeshInstance3D + host, so it's manual-playtest only (mirrors PropFollow,
## whose in-tree teleport is likewise playtest-only).

const RandomCoat := preload("res://scripts/components/random_coat.gd")


func test_pick_index_low_roll_first() -> void:
	assert_eq(RandomCoat.pick_index(6, 0.0), 0, "a roll of 0 selects the first coat in the pool")


func test_pick_index_high_roll_last() -> void:
	# randf() returns [0,1) so 0.999… is the practical top; it must land on the LAST index, never out of bounds.
	assert_eq(RandomCoat.pick_index(6, 0.999), 5, "a near-1 roll selects the last coat (never past the end)")


func test_pick_index_midpoint() -> void:
	assert_eq(RandomCoat.pick_index(4, 0.5), 2, "the midpoint roll lands in the middle of the pool")


func test_pick_index_clamps_at_one() -> void:
	# Defensive: even a roll of exactly 1.0 (which randf never returns) must clamp inside the pool, not overflow.
	assert_eq(RandomCoat.pick_index(3, 1.0), 2, "a roll of 1.0 clamps to the last index instead of going out of range")


func test_pick_index_empty_pool_safe() -> void:
	assert_eq(RandomCoat.pick_index(0, 0.7), 0, "an empty pool returns 0 rather than dividing into nothing / erroring")


func test_pick_index_single_option() -> void:
	assert_eq(RandomCoat.pick_index(1, 0.42), 0, "a one-coat pool always returns the only index")


func test_enabled_by_default() -> void:
	# Off-tree field read — no add_child, so no _ready/deferred coat runs. The component ships ON so a dog wearing it
	# gets a random coat out of the box; a designer flips it off to pin a specific look.
	var c = RandomCoat.new()
	assert_true(c.enabled, "RandomCoat ships enabled — dropping it on a prop randomises the coat by default")
	assert_eq(c.coat_tints.size(), 0, "the tint pool is empty by default (the dog scene authors its own natural coats)")
	c.free()
