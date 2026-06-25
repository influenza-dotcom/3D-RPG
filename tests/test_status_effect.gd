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


func test_weapon_on_hit_effect_defaults_inert() -> void:
	# CT-3: a weapon carries no on-hit StatusEffect by default, so a normal shot applies nothing (the chemistry
	# substrate is opt-in per weapon).
	var w := WeaponData.new()
	assert_null(w.on_hit_effect, "no on-hit effect by default (inert)")
	assert_almost_eq(w.on_hit_chance, 1.0, 0.001, "on-hit chance defaults to 1.0 — applies whenever an effect IS set")
	w = null

func test_apply_effect_empty_id_always_stacks() -> void:
	# StatusEffect.id contract (status_effect.gd / AUTHORING_GUIDE): an EMPTY id ALWAYS stacks — even the same
	# instance re-applied piles up an independent copy. Leave the id blank only when you want them to pile up;
	# a weapon/consumable that should REFRESH (incl. collapsing a multi-pellet hit) gives its effect an id instead
	# (see test_refresh_same_id_does_not_stack). This pins that empty-id dedup does NOT silently flatten stacks.
	var mgr := StatusEffectManager.new()
	var fx := StatusEffect.new()  # id defaults empty (an anonymous, intentionally-stacking effect)
	fx.duration = 5.0
	mgr.apply_effect(fx)
	mgr.apply_effect(fx)
	mgr.apply_effect(fx)
	assert_eq(mgr.active_count(), 3, "an empty-id effect always stacks — 3 applications -> 3 independent copies")
	mgr.free()
	fx = null

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

## --- Save persistence (serialize / restore_effect): buffs/debuffs survive a reload with their countdown intact. ---

const TMP_FX := "user://test_status_effect_tmp.tres"

func after_each() -> void:
	if FileAccess.file_exists(TMP_FX):
		DirAccess.remove_absolute(TMP_FX)

func test_serialize_skips_pathless_effect() -> void:
	# A code-built effect has no resource_path, so it can't round-trip through a save — serialize drops it.
	var mgr := StatusEffectManager.new()
	mgr.apply_effect(_effect(&"poison", 5.0, 1.0, 2.0))
	assert_eq(mgr.serialize().size(), 0, "an effect with no .tres path isn't serialized")
	mgr.free()

func test_serialize_and_restore_continues_countdown() -> void:
	var e := _effect(&"burn", 10.0, 0.0, 0.0)
	ResourceSaver.save(e, TMP_FX)  # give it a resource_path so it can round-trip
	var src := StatusEffectManager.new()
	src.apply_effect(load(TMP_FX) as StatusEffect)
	src.tick(4.0)  # 6.0s remaining
	var saved := src.serialize()
	assert_eq(saved.size(), 1, "a path-backed effect serializes")
	assert_eq(str(saved[0]["path"]), TMP_FX, "by its .tres path")
	assert_almost_eq(float(saved[0]["remaining"]), 6.0, 0.001, "with the REMAINING time, not the full duration")
	# Restore into a fresh manager — the countdown CONTINUES from the saved remaining, not a full refresh.
	var dst := StatusEffectManager.new()
	for s in saved:
		dst.restore_effect(load(str(s["path"])) as StatusEffect, float(s["remaining"]))
	assert_true(dst.has_effect(&"burn"), "the effect is restored")
	dst.tick(5.0)
	assert_true(dst.has_effect(&"burn"), "still active 5s later (6s was restored, not the full 10s)")
	dst.tick(1.5)
	assert_false(dst.has_effect(&"burn"), "expires once the RESTORED remaining elapses")
	src.free()
	dst.free()
	e = null

func test_restore_skips_expired_timed_effect() -> void:
	var e := _effect(&"burn", 10.0, 0.0, 0.0)
	var mgr := StatusEffectManager.new()
	mgr.restore_effect(e, 0.0)  # already expired
	assert_eq(mgr.active_count(), 0, "an already-expired timed effect isn't restored")
	mgr.free()
	e = null
