extends GutTest

## World pickups (this batch): the new money pickup's pure surface, and the per-item world-model wiring —
## the grant + free + toast side effects are in-tree behaviour (playtested), so we pin only the pure logic.

func test_money_pickup_label_and_gate() -> void:
	var m := MoneyPickUp.new()
	m.amount = 50
	assert_eq(m.look_name(), "Take 50 zorkmids", "the default hover readout shows the amount")
	assert_true(m.can_be_talked_to(), "a pickup holding money is interactable")
	m.amount = 0
	assert_false(m.can_be_talked_to(), "an empty money pickup can't be interacted with")
	m.amount = 50
	m.pickup_label = "Loose change"
	assert_eq(m.look_name(), "Loose change", "a custom label overrides the amount readout")
	m.free()


func test_money_pickup_builds_a_default_coin() -> void:
	var m := MoneyPickUp.new()
	var coin := m._default_coin()
	assert_not_null(coin.mesh, "the fallback coin carries a mesh, so a bare MoneyPickUp is visible in the world")
	coin.free()
	m.free()


func test_canpickup_does_not_auto_body_authored_pickups() -> void:
	var cp := CanPickUp.new()
	assert_false(cp.build_model_from_item,
		"the item-model build is OPT-IN — an authored CanPickUp keeps its own visual unless asked")
	cp.free()


func test_item_world_model_is_opt_in() -> void:
	var it := Item.new()
	assert_null(it.world_model, "an item has no world model until one is assigned (inventory UI uses name/icon)")
	it = null
