extends GutTest

## Tests for the `destructible` toggle: throwables are destructible by default, but an instance OR its ThrowableData can
## mark a prop indestructible (dropped weapons/items, the dog) — take_damage then no-ops entirely. Built off-tree
## (no _ready), so the indestructible path (which early-returns before any tree-touching flash/destroy) is unit-safe;
## the destructible path's flash/destroy is tree-bound and left to the live game.

const Throwable := preload("res://scripts/components/Throwable.gd")
const ThrowableData := preload("res://scripts/combat/throwable_data.gd")


func test_destructible_by_default() -> void:
	var t = Throwable.new()
	assert_true(t.is_destructible(), "a throwable is destructible by default (crates/barrels/gibs break)")
	t.free()


func test_instance_toggle_makes_indestructible() -> void:
	var t = Throwable.new()
	t.destructible = false
	assert_false(t.is_destructible(), "destructible = false on the instance makes the prop indestructible")
	t.free()


func test_data_toggle_makes_indestructible() -> void:
	# An ITEM resource marked indestructible covers every instance, even one whose own toggle is still on.
	var d = ThrowableData.new()
	d.destructible = false
	var t = Throwable.new()
	t.data = d
	assert_false(t.is_destructible(), "a ThrowableData with destructible = false forces the prop indestructible")
	t.free()
	d = null


func test_take_damage_noops_when_indestructible() -> void:
	# The whole point: an indestructible prop loses NO hp and is never destroyed, regardless of damage dealt.
	var t = Throwable.new()
	t.destructible = false
	t.hp = 5
	t.take_damage(999)
	assert_eq(t.hp, 5, "take_damage on an indestructible prop must not subtract hp")
	assert_false(t._destroyed, "an indestructible prop is never destroyed by damage")
	t.free()
