extends GutTest

## SE-2 HazardZone: a DoT area that ticks take_damage (AMBIENT — attacker null) on overlapping bodies + an
## optional status. The qualify filter + the tick (damage / null-attribution / prune / status) are pinned here;
## the Area3D overlap detection itself is in-tree physics, playtested.

const HAZARD_PATH := "res://scripts/components/hazard_zone.gd"


## A minimal take_damage-able body: records the last hit's amount + attacker, in an optional group.
class StubBody extends Node:
	var hits: int = 0
	var total_damage: float = 0.0
	var last_attacker = "UNSET"
	func take_damage(amount: float, _crit: bool = false, attacker: Node = null, _hit := Vector3.INF) -> void:
		hits += 1
		total_damage += amount
		last_attacker = attacker


func test_defaults_are_sane() -> void:
	var h = load(HAZARD_PATH).new()
	assert_gt(h.damage_per_tick, 0.0, "a hazard hurts by default")
	assert_gt(h.tick_interval, 0.0, "the tick interval is positive")
	assert_null(h.on_tick_effect, "no status by default (damage-first)")
	h.free()


func test_qualifies_filters_by_take_damage_and_group() -> void:
	var h = load(HAZARD_PATH).new()
	var body := StubBody.new()
	assert_true(h._qualifies(body), "blank group + a take_damage-able body qualifies (fire burns everything)")
	h.damage_group = &"flammable"
	assert_false(h._qualifies(body), "with a group set, a body NOT in it is skipped")
	body.add_to_group(&"flammable")
	assert_true(h._qualifies(body), "...and IS counted once it joins the group")
	var inert := Node.new()  # no take_damage
	h.damage_group = &""
	assert_false(h._qualifies(inert), "a body with no take_damage never qualifies")
	body.free()
	inert.free()
	h.free()


func test_tick_damages_with_null_attacker() -> void:
	var h = load(HAZARD_PATH).new()
	h.damage_per_tick = 2.5
	var a := StubBody.new()
	var b := StubBody.new()
	h._bodies.assign([a, b])  # assign() into the typed Array[Node] (a plain literal can't be assigned directly)
	h._apply_tick()
	assert_almost_eq(a.total_damage, 2.5, 0.001, "each overlapping body takes damage_per_tick")
	assert_eq(a.hits, 1, "one hit per tick")
	assert_null(a.last_attacker, "the damage is AMBIENT — attacker is null (no provoke / no kill credit)")
	assert_almost_eq(b.total_damage, 2.5, 0.001, "every body in the zone is ticked")
	a.free()
	b.free()
	h.free()


func test_tick_prunes_freed_bodies() -> void:
	var h = load(HAZARD_PATH).new()
	var a := StubBody.new()
	var gone := StubBody.new()
	h._bodies.assign([a, gone])
	gone.free()  # freed while still "inside"
	h._apply_tick()
	assert_eq(h._bodies.size(), 1, "a freed body is pruned from the overlap list")
	assert_eq(a.hits, 1, "the surviving body still takes its tick")
	a.free()
	h.free()


func test_tick_applies_status_to_a_character() -> void:
	var h = load(HAZARD_PATH).new()
	h.damage_per_tick = 0.0  # status-only zone
	var fx := StatusEffect.new()
	fx.id = &"burning"
	fx.duration = 3.0
	h.on_tick_effect = fx
	var c := _CharStub.new()
	add_child_autofree(c)  # apply_status_effect lazily add_childs a StatusEffectManager — needs the tree
	h._bodies.assign([c])
	h._apply_tick()
	var mgr: StatusEffectManager = null
	for ch in c.get_children():
		if ch is StatusEffectManager:
			mgr = ch as StatusEffectManager
	assert_not_null(mgr, "a Character in the zone gets a StatusEffectManager")
	if mgr != null:
		assert_true(mgr.has_effect(&"burning"), "...and the on-tick status is applied")
	fx = null
	h.free()


## A concrete Character (abstract) for the status test — apply_status_effect comes from CT-3 on Character.
class _CharStub extends Character:
	pass
