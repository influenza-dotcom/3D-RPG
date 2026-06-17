extends GutTest

## Off-tree logic tests for PanicOnDamage (scripts/components/panic_on_damage.gd): the pure fear_for() curve
## and the react() gates (disabled / panic_scale 0 / not-in-combat / already-fleeing). The RANDOM flee roll is
## manual-playtest, but a fear of exactly 1.0 makes `randf() < fear` deterministic (randf is [0,1)), so we can
## pin a certain break too. Built bare (.new(), no NPC) per CLAUDE.md with a duck-typed stub host.

class StubHost:
	var hp: float = 50.0
	var max_hp: float = 100.0
	var in_combat: bool = true
	var fleeing: bool = false
	var fled: bool = false
	func is_in_combat() -> bool:
		return in_combat
	func is_fleeing() -> bool:
		return fleeing
	func break_and_flee() -> void:
		fled = true
		fleeing = true

func _panic(scale := 1.0) -> PanicOnDamage:
	var p := PanicOnDamage.new()
	p.panic_scale = scale
	return p

func test_fear_curve() -> void:
	var p := _panic(1.0)
	assert_almost_eq(p.fear_for(100.0, 100.0), 0.0, 0.001, "full HP -> no fear")
	assert_almost_eq(p.fear_for(50.0, 100.0), 0.5, 0.001, "half HP -> half of panic_scale")
	assert_almost_eq(p.fear_for(0.0, 100.0), 1.0, 0.001, "0 HP -> the full panic_scale")
	p.free()

func test_fear_scales_with_panic_scale() -> void:
	var p := _panic(0.4)
	assert_almost_eq(p.fear_for(50.0, 100.0), 0.2, 0.001, "fear = panic_scale * fraction of HP lost")
	p.free()

func test_panic_scale_zero_never_flees() -> void:
	var p := _panic(0.0)  # fearless (the default temperament)
	var h := StubHost.new()
	h.hp = 1.0  # nearly dead
	p.react(h)
	assert_false(h.fled, "panic_scale 0 never flees, even near death")
	p.free()

func test_disabled_never_flees() -> void:
	var p := _panic(2.0)
	p.enabled = false
	var h := StubHost.new()
	h.hp = 1.0
	p.react(h)
	assert_false(h.fled, "enabled=false never flees")
	p.free()

func test_no_panic_outside_combat() -> void:
	var p := _panic(2.0)
	var h := StubHost.new()
	h.hp = 1.0
	h.in_combat = false
	p.react(h)
	assert_false(h.fled, "a hit while idle/not-in-combat doesn't make it bolt")
	p.free()

func test_already_fleeing_no_reroll() -> void:
	var p := _panic(2.0)
	var h := StubHost.new()
	h.hp = 1.0
	h.fleeing = true
	h.fled = false
	p.react(h)
	assert_false(h.fled, "already fleeing -> no re-roll / no second break")
	p.free()

func test_dead_hit_does_not_flee() -> void:
	var p := _panic(2.0)
	var h := StubHost.new()
	h.hp = 0.0  # the lethal hit
	p.react(h)
	assert_false(h.fled, "hp<=0 -> no flee on the killing blow")
	p.free()

func test_certain_fear_breaks_to_flee() -> void:
	# panic_scale 2 at half HP -> fear = 2 * 0.5 = 1.0; randf() is [0,1) so randf() < 1.0 is ALWAYS true.
	var p := _panic(2.0)
	var h := StubHost.new()
	h.hp = 50.0
	p.react(h)
	assert_true(h.fled, "a certain fear roll (>=1.0) breaks the NPC to FLEE")
	p.free()
