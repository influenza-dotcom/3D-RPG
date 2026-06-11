extends GutTest

## Consumables (use-from-inventory health packs) + the shared ItemRow row formatter.
## - Item.is_consumable gates on the CONSUMABLE category; healthpack.tres is the authored archetype.
## - Player.use_consumable heals + consumes one, refuses at full HP (no wasted packs), refuses non-
##   consumables / missing items. Off-tree: heal() is pure hp math, ui is null so toasts are skipped.
## - ItemRow.stack_text is the ONE labeled row language all three inventory-style screens share.

const PLAYER_PATH := "res://scripts/player/player.gd"


func _healthpack(heal: float = 30.0) -> Item:
	var it := Item.new()
	it.id = &"test_healthpack"
	it.display_name = "Medkit"
	it.category = Item.Category.CONSUMABLE
	it.max_stack = 5
	it.weight = 0.5
	it.heal_amount = heal
	return it


func test_is_consumable_gates_on_category() -> void:
	assert_true(_healthpack().is_consumable(), "a CONSUMABLE-category item is consumable")
	var junk := Item.new()
	assert_false(junk.is_consumable(), "the default (MISC) category is not consumable")
	junk = null


func test_authored_healthpack_tres_loads() -> void:
	var hp = load("res://resources/items/healthpack.tres")
	assert_not_null(hp, "healthpack.tres loads (lives in resources/items/, so ItemDb auto-registers it)")
	assert_true(hp is Item, "healthpack.tres deserializes as an Item")
	assert_true(hp.is_consumable(), "authored category CONSUMABLE")
	assert_gt(hp.heal_amount, 0.0, "a health pack heals")
	assert_gt(hp.max_stack, 1, "health packs stack")


func test_use_consumable_heals_and_consumes_one() -> void:
	var p = load(PLAYER_PATH).new()
	p.max_hp = 100.0
	p.hp = 50.0
	p.inventory = CharacterInventory.new()
	var pack := _healthpack(30.0)
	p.inventory.add(pack, 2)
	assert_true(p.use_consumable(pack), "using a held consumable succeeds")
	assert_almost_eq(p.hp, 80.0, 0.0001, "the pack heals its heal_amount")
	assert_eq(p.inventory.count_of(pack), 1, "ONE pack is consumed from the stack")
	assert_true(p.use_consumable(pack), "a second use, still hurt, succeeds")
	assert_almost_eq(p.hp, 100.0, 0.0001, "healing clamps at max_hp")
	assert_eq(p.inventory.count_of(pack), 0, "the stack is spent")
	assert_false(p.use_consumable(pack), "no packs left -> refused")
	p.inventory.free()
	p.free()
	pack = null


func test_use_consumable_refuses_at_full_hp_and_for_non_consumables() -> void:
	var p = load(PLAYER_PATH).new()
	p.max_hp = 100.0
	p.hp = 100.0
	p.inventory = CharacterInventory.new()
	var pack := _healthpack()
	p.inventory.add(pack, 1)
	assert_false(p.use_consumable(pack), "full HP -> refused, so a click can't waste a pack")
	assert_eq(p.inventory.count_of(pack), 1, "...and nothing is consumed")
	var junk := Item.new()
	p.inventory.add(junk, 1)
	assert_false(p.use_consumable(junk), "a non-consumable is never 'used'")
	p.inventory.free()
	p.free()
	pack = null
	junk = null


func test_item_row_labels_every_value() -> void:
	var pack := _healthpack()
	assert_eq(ItemRow.stack_text(pack, 3), "Medkit  x3  ·  wt 1.5",
		"the shared row text labels the count and the stack weight (no bare numbers)")
	assert_eq(ItemRow.stack_text(pack, 1), "Medkit  ·  wt 0.5",
		"a single item shows no count, just the labeled weight")
	pack = null
