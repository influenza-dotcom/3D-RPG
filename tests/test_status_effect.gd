extends GutTest

## Slice 5 (status effects): StatusEffectManager lifecycle (apply / refresh / remove / clear), the periodic-damage
## tick (driven manually via tick() against a stub host), duration expiry + the effect_removed signal, and the
## speed_multiplier / stat_modifier aggregations. The locomotion + consumable wiring is thin and playtest-verified;
## here we test the pure manager logic off-tree.

## A minimal host that just records the damage a DoT deals it (the only host surface the manager touches).
class _StubHost extends Node:
	var damage: float = 0.0
	func take_damage(amount: float, _crit := false, _attacker: Node = null, _hit := Vector3.INF) -> void:
		damage += amount

func _effect(eid: StringName, dur: float, interval: float, dmg: float, speed := 1.0) -> StatusEffect:
	var e := StatusEffect.new()
	e.id = eid
	e.duration = dur
	e.tick_interval = interval
	e.damage_per_tick = dmg
	e.speed_multiplier = speed
	return e

func test_apply_has_remove() -> void:
	var mgr := StatusEffectManager.new()
	assert_false(mgr.has_effect(&"poison"), "absent before apply")
	mgr.apply_effect(_effect(&"poison", 5.0, 1.0, 2.0))
	assert_true(mgr.has_effect(&"poison"), "present after apply")
	assert_eq(mgr.active_count(), 1, "one active effect")
	mgr.remove_effect(&"poison")
	assert_false(mgr.has_effect(&"poison"), "gone after remove")
	mgr.free()

func test_refresh_same_id_does_not_stack() -> void:
	var mgr := StatusEffectManager.new()
	mgr.apply_effect(_effect(&"poison", 5.0, 1.0, 2.0))
	mgr.apply_effect(_effect(&"poison", 5.0, 1.0, 2.0))
	assert_eq(mgr.active_count(), 1, "re-applying the same id refreshes, doesn't stack")
	mgr.free()

func test_dot_ticks_damage_on_interval() -> void:
	var mgr := StatusEffectManager.new()
	var stub := _StubHost.new()
	mgr.host = stub
	mgr.apply_effect(_effect(&"burn", 10.0, 0.5, 3.0))
	mgr.tick(0.5)
	assert_almost_eq(stub.damage, 3.0, 0.001, "one tick at the 0.5s interval")
	mgr.tick(0.5)
	assert_almost_eq(stub.damage, 6.0, 0.001, "a second tick")
	stub.free()
	mgr.free()

func test_duration_expires_and_emits() -> void:
	var mgr := StatusEffectManager.new()
	watch_signals(mgr)
	mgr.apply_effect(_effect(&"slow", 1.0, 0.0, 0.0, 0.5))
	mgr.tick(0.6)
	assert_true(mgr.has_effect(&"slow"), "still active before its duration elapses")
	mgr.tick(0.6)  # 1.2s total > 1.0s duration
	assert_false(mgr.has_effect(&"slow"), "removed once the duration elapses")
	assert_signal_emitted(mgr, "effect_removed", "expiry emits effect_removed")
	mgr.free()

func test_permanent_effect_does_not_expire() -> void:
	var mgr := StatusEffectManager.new()
	mgr.apply_effect(_effect(&"marked", 0.0, 0.0, 0.0))  # duration 0 = permanent until removed
	mgr.tick(100.0)
	assert_true(mgr.has_effect(&"marked"), "a 0-duration effect lasts until removed")
	mgr.free()

func test_speed_multiplier_aggregates() -> void:
	var mgr := StatusEffectManager.new()
	assert_almost_eq(mgr.speed_multiplier(), 1.0, 0.001, "no effects -> 1.0")
	mgr.apply_effect(_effect(&"slow", 0.0, 0.0, 0.0, 0.5))
	mgr.apply_effect(_effect(&"haste", 0.0, 0.0, 0.0, 1.5))
	assert_almost_eq(mgr.speed_multiplier(), 0.75, 0.001, "0.5 * 1.5")
	mgr.free()

func test_stat_modifier_sums() -> void:
	var mgr := StatusEffectManager.new()
	var e := _effect(&"buff", 0.0, 0.0, 0.0)
	e.stat_modifiers = {"strength": 2}
	mgr.apply_effect(e)
	assert_almost_eq(mgr.stat_modifier(&"strength"), 2.0, 0.001, "exposes the stat modifier")
	assert_almost_eq(mgr.stat_modifier(&"agility"), 0.0, 0.001, "unset stat -> 0")
	mgr.free()
