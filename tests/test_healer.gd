extends GutTest

## The Healer component (pay-to-heal) + the Character limb-heal it drives. Limb damage is set DIRECTLY on
## the condition dicts (not via take_damage, whose off-tree to_local would trip GUT's engine-error guard).

const CHARACTER_PATH := "res://scripts/player/character.gd"
const PLAYER_PATH := "res://scripts/player/player.gd"


func test_character_limb_heal() -> void:
	var c = load(CHARACTER_PATH).new()
	c.max_hp = 100.0
	assert_false(c.has_limb_damage(), "a fresh character has no limb damage")
	c._crippled[0] = true  # cripple a limb directly
	assert_true(c.has_limb_damage(), "a crippled limb registers as limb damage")
	c.heal_limbs()
	assert_false(c.has_limb_damage(), "heal_limbs un-cripples everything")
	c._limb_condition[1] = 5.0  # full pool is max_hp * limb_condition_frac (60); a depleted pool also counts
	assert_true(c.has_limb_damage(), "a below-full condition pool counts as limb damage")
	c.heal_limbs()
	assert_false(c.has_limb_damage(), "heal_limbs resets the condition pools too")
	c.free()


func test_heal_cost_is_linear_in_missing_hp() -> void:
	var h := Healer.new()
	h.cost_per_hp = 2.0
	h.min_cost = 5
	var p = load(PLAYER_PATH).new()
	p.max_hp = 100.0
	p.hp = 100.0
	assert_eq(h.heal_cost(p), 0, "full HP + no limb damage -> nothing to heal (free / refused)")
	p.hp = 60.0  # 40 missing
	assert_eq(h.heal_cost(p), 80, "cost is missing_hp * cost_per_hp (40 x 2)")
	p.hp = 99.0  # 1 missing -> 2, floored to min_cost 5
	assert_eq(h.heal_cost(p), 5, "a tiny scratch is floored at min_cost")
	h.free()
	p.free()


func test_do_heal_charges_and_restores() -> void:
	var h := Healer.new()
	h.cost_per_hp = 1.0
	h.min_cost = 5
	var p = load(PLAYER_PATH).new()
	p.max_hp = 100.0
	p.hp = 70.0
	p.money = 100
	assert_true(h.do_heal(p), "a hurt, solvent player gets healed")
	assert_almost_eq(p.hp, 100.0, 0.0001, "HP restored to full")
	assert_eq(p.money, 70, "charged the 30-missing-hp cost")
	assert_false(h.do_heal(p), "already full -> nothing to heal, no charge")
	assert_eq(p.money, 70, "no further charge once healed")
	h.free()
	p.free()


func test_do_heal_refuses_when_broke() -> void:
	var h := Healer.new()
	h.cost_per_hp = 1.0
	var p = load(PLAYER_PATH).new()
	p.max_hp = 100.0
	p.hp = 10.0  # 90 missing -> cost 90
	p.money = 20
	assert_false(h.do_heal(p), "can't afford the heal -> refused")
	assert_almost_eq(p.hp, 10.0, 0.0001, "no healing on a refused transaction")
	assert_eq(p.money, 20, "no charge on a refused transaction")
	h.free()
	p.free()
