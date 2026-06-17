extends GutTest

## Off-tree logic tests for the SelfHealer drop-in (scripts/components/self_healer.gd): the heal-threshold
## gate, the cooldown throttle, the `enabled` short-circuit, and the no-kit / no-inventory / dead no-ops.
## Built bare (.new(), no add_child, no NPC _ready) per CLAUDE.md; react() is driven with a duck-typed stub
## host so it needs no live NPC. The actual in-fight use is manual-playtest.

class StubInventory:
	var kit: Item = null  # a healing Item (heal_amount), or null when the bag is empty
	var removed: int = 0
	func find_healing_consumable() -> Item:
		return kit
	func remove(_item: Item, n: int) -> void:
		removed += n
		kit = null  # consumed

class StubHost:
	var hp: float = 100.0
	var max_hp: float = 100.0
	var inventory: StubInventory = null
	var healed: float = 0.0
	func heal(amount: float) -> void:
		healed += amount
		hp = minf(hp + amount, max_hp)

func _host(hp: float, with_kit := true, heal_amount := 10.0) -> StubHost:
	var h := StubHost.new()
	h.hp = hp
	var inv := StubInventory.new()
	if with_kit:
		var kit := Item.new()
		kit.heal_amount = heal_amount
		inv.kit = kit
	h.inventory = inv
	return h

func _healer(frac := 0.5, cd := 4000) -> SelfHealer:
	var s := SelfHealer.new()
	s.heal_at_hp_frac = frac
	s.cooldown_ms = cd
	return s

func test_heals_when_at_or_below_threshold() -> void:
	var s := _healer(0.5)
	var h := _host(40.0)  # 40% <= 50%
	s.react(h)
	assert_almost_eq(h.healed, 10.0, 0.001, "spends a carried kit when at/below the HP fraction")
	assert_eq(h.inventory.removed, 1, "consumes exactly one kit")
	s.free()

func test_does_not_heal_above_threshold() -> void:
	var s := _healer(0.5)
	var h := _host(60.0)  # 60% > 50%
	s.react(h)
	assert_eq(h.healed, 0.0, "no heal while above the HP fraction")
	s.free()

func test_cooldown_blocks_second_heal() -> void:
	var s := _healer(0.5, 999999)  # huge cooldown
	var h := _host(30.0)
	s.react(h)  # first heal
	assert_almost_eq(h.healed, 10.0, 0.001, "first heal lands")
	h.inventory.kit = Item.new()  # refill the bag and re-hurt it
	h.inventory.kit.heal_amount = 10.0
	h.hp = 30.0
	h.healed = 0.0
	s.react(h)
	assert_eq(h.healed, 0.0, "a second heal is blocked while on cooldown")
	s.free()

func test_disabled_short_circuits() -> void:
	var s := _healer(0.5)
	s.enabled = false
	var h := _host(10.0)
	s.react(h)
	assert_eq(h.healed, 0.0, "enabled=false never heals")
	s.free()

func test_no_kit_is_a_no_op() -> void:
	var s := _healer(0.5)
	var h := _host(10.0, false)  # empty bag
	s.react(h)
	assert_eq(h.healed, 0.0, "no healing consumable in the bag -> no-op")
	s.free()

func test_null_inventory_is_safe() -> void:
	var s := _healer(0.5)
	var h := _host(10.0)
	h.inventory = null  # civilian / no bag
	s.react(h)  # must not crash
	assert_eq(h.healed, 0.0, "no inventory -> safe no-op")
	s.free()

func test_dead_hit_does_not_heal() -> void:
	var s := _healer(0.5)
	var h := _host(0.0)  # the lethal hit (hp already <= 0 when react runs)
	s.react(h)
	assert_eq(h.healed, 0.0, "hp<=0 -> no heal on the killing blow")
	s.free()
