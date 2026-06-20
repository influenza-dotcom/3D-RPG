extends GutTest

## Rank 20 (Restocker + refill): the shortfall top-up on Merchant/ItemContainer (CharacterInventory.refill_to_baseline)
## and the Restocker's TIMER + ON_VISIT scheduling. Driven off-tree (no heavy LookAtInteractable _ready).

const MerchantScript = preload("res://scripts/components/merchant.gd")
const ContainerScript = preload("res://scripts/components/container.gd")
const RestockerScript = preload("res://scripts/components/restocker.gd")
const InventoryScript = preload("res://scripts/inventory/character_inventory.gd")

const HEALTHPACK := "res://resources/items/healthpack.tres"
const PISTOL := "res://resources/items/pistol_item.tres"

class StubTarget extends Node:
	var refills := 0
	func refill() -> void:
		refills += 1

func _entry(item: Item, count: int) -> StockEntry:
	var e := StockEntry.new()
	e.item = item
	e.count = count
	return e

func _stack(item: Item, count: int) -> ItemStack:
	var s := ItemStack.new()
	s.item = item
	s.count = count
	return s

func test_merchant_refill_tops_up_shortfall() -> void:
	var hp: Item = load(HEALTHPACK)
	var m = MerchantScript.new()
	m.stock = InventoryScript.new()
	var entries: Array[StockEntry] = [_entry(hp, 5)]
	m.stock_counts = entries
	m._seed_stock(m.stock)
	assert_eq(m.stock.count_of_id(hp.id), 5, "seeded to the baseline of 5")
	m.stock.remove(hp, 2)
	assert_eq(m.stock.count_of_id(hp.id), 3, "player bought 2")
	m.refill()
	assert_eq(m.stock.count_of_id(hp.id), 5, "refill tops the shortfall back to 5")
	m.refill()
	assert_eq(m.stock.count_of_id(hp.id), 5, "a second refill never doubles existing stock")
	m.stock.free()
	m.free()

func test_merchant_refill_restocks_weapons_as_unique() -> void:
	var pistol: Item = load(PISTOL)
	assert_true(pistol.is_weapon(), "pistol_item is a weapon")
	var m = MerchantScript.new()
	m.stock = InventoryScript.new()
	var entries: Array[StockEntry] = [_entry(pistol, 2)]
	m.stock_counts = entries
	m._seed_stock(m.stock)
	assert_eq(m.stock.count_of_id(pistol.id), 2, "two unique pistols seeded")
	var one: Item = m.stock.find_by_id(pistol.id)
	m.stock.remove(one, 1)
	assert_eq(m.stock.count_of_id(pistol.id), 1, "one pistol sold")
	m.refill()
	assert_eq(m.stock.count_of_id(pistol.id), 2, "refill restocks the missing pistol as a new unique instance")
	m.stock.free()
	m.free()

func test_container_refill_tops_up_shortfall() -> void:
	var hp: Item = load(HEALTHPACK)
	var c = ContainerScript.new()
	c.inventory = InventoryScript.new()
	var stacks: Array[ItemStack] = [_stack(hp, 4)]
	c.item_stacks = stacks
	c._seed_contents()
	assert_eq(c.inventory.count_of_id(hp.id), 4, "seeded 4")
	c.inventory.remove(hp, 3)
	c.refill()
	assert_eq(c.inventory.count_of_id(hp.id), 4, "topped back to 4")
	c.inventory.free()
	c.free()

func test_timer_refills_on_interval() -> void:
	var r = RestockerScript.new()
	r.mode = RestockerScript.Mode.TIMER
	r.interval = 0.5
	var t := StubTarget.new()
	add_child_autofree(t)
	r._target = t
	r._process(0.6)
	assert_eq(t.refills, 1, "timer refills once the interval elapses")
	r._process(0.1)
	assert_eq(t.refills, 1, "no refill before the next interval")
	r._process(0.5)
	assert_eq(t.refills, 2, "refills again after another interval")
	r.free()

func test_on_visit_first_visit_then_rate_limited() -> void:
	var r = RestockerScript.new()
	r.mode = RestockerScript.Mode.ON_VISIT
	r.interval = 1.0
	var t := StubTarget.new()
	add_child_autofree(t)
	r._target = t
	r._on_visit()
	assert_eq(t.refills, 1, "the first visit always refills")
	r._on_visit()
	assert_eq(t.refills, 1, "an immediate second visit is rate-limited")
	r._process(1.1)
	r._on_visit()
	assert_eq(t.refills, 2, "a visit after the interval refills again")
	r.free()

func test_notify_visit_finds_child_restocker() -> void:
	var host := Node.new()
	var r := RestockerScript.new()
	r.mode = RestockerScript.Mode.ON_VISIT
	r.interval = 1.0
	var t := StubTarget.new()
	host.add_child(t)
	host.add_child(r)
	r._target = t
	RestockerScript.notify_visit(host)
	assert_eq(t.refills, 1, "notify_visit triggers the host's child Restocker")
	host.free()
