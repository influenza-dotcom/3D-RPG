class_name StatusEffectManager
extends Node

## Drop under any character (player or NPC) to run timed StatusEffects on it: periodic damage, a move-speed
## multiplier (read by Character.status_move_multiplier), and an optional clinging visual. apply_effect /
## remove_effect / has_effect / clear_effects; it ticks durations + DoT each frame and emits effect_added /
## effect_removed. `host` is the parent character — Node-typed (a dynamic surface): it only needs host.take_damage.
## (The Player auto-creates one of these on first consumable-effect use, so it needn't be pre-placed for buffs.)

signal effect_added(effect: StatusEffect)
signal effect_removed(effect: StatusEffect)

var host: Node = null

## One active effect's live bookkeeping (the StatusEffect resource stays immutable + shareable).
class _Active:
	var effect: StatusEffect
	var remaining: float = 0.0
	var tick_t: float = 0.0
	var visual: Node = null

var _active: Array = []

func _ready() -> void:
	host = get_parent()

func _process(delta: float) -> void:
	if not _active.is_empty():
		tick(delta)

## Apply an effect — or, if one with the same (non-empty) id is already active, refresh its duration.
func apply_effect(effect: StatusEffect) -> void:
	if effect == null:
		return
	if effect.id != &"":
		for a in _active:
			if a.effect != null and a.effect.id == effect.id:
				a.remaining = effect.duration
				return
	var a := _Active.new()
	a.effect = effect
	a.remaining = effect.duration
	if effect.visual_effect != null and host != null:
		a.visual = effect.visual_effect.instantiate()
		host.add_child(a.visual)
	_active.append(a)
	effect_added.emit(effect)

## Restore an effect with a SPECIFIC remaining time (save/load) — like apply_effect but it CONTINUES the saved
## countdown instead of refreshing to the full duration. Skips an already-expired TIMED effect; a permanent effect
## (duration <= 0) is restored regardless of its remaining counter. No dedup (restore runs on a fresh manager).
func restore_effect(effect: StatusEffect, remaining: float) -> void:
	if effect == null:
		return
	if effect.duration > 0.0 and remaining <= 0.0:
		return
	var a := _Active.new()
	a.effect = effect
	a.remaining = remaining
	if effect.visual_effect != null and host != null:
		a.visual = effect.visual_effect.instantiate()
		host.add_child(a.visual)
	_active.append(a)
	effect_added.emit(effect)

## Serialize active effects as [{path, remaining}] for the save (GameState.status_effects). Skips a code-built
## effect with no resource_path (can't round-trip) and an already-expired timed effect; keeps a permanent one.
func serialize() -> Array:
	var out: Array = []
	for a in _active:
		if a.effect == null or a.effect.resource_path == "":
			continue
		if a.effect.duration > 0.0 and a.remaining <= 0.0:
			continue
		out.append({"path": a.effect.resource_path, "remaining": a.remaining})
	return out

func remove_effect(effect_id: StringName) -> void:
	for i in range(_active.size() - 1, -1, -1):
		if _active[i].effect != null and _active[i].effect.id == effect_id:
			_remove_at(i)

func has_effect(effect_id: StringName) -> bool:
	for a in _active:
		if a.effect != null and a.effect.id == effect_id:
			return true
	return false

func active_count() -> int:
	return _active.size()

func clear_effects() -> void:
	for i in range(_active.size() - 1, -1, -1):
		_remove_at(i)

## Product of every active effect's speed_multiplier (1.0 if none) — read by Character.status_move_multiplier.
func speed_multiplier() -> float:
	var m := 1.0
	for a in _active:
		if a.effect != null:
			m *= a.effect.speed_multiplier
	return m

## Sum of every active effect's modifier for `stat` (0.0 if none). Exposed for a future CharacterStats hookup.
func stat_modifier(stat: StringName) -> float:
	var total := 0.0
	for a in _active:
		if a.effect != null:
			total += float(a.effect.stat_modifiers.get(String(stat), 0))
	return total

## Per-frame update — split out so a test can drive it with a stub host. Applies each effect's periodic damage
## on its tick_interval and counts down durations, removing expired effects.
func tick(delta: float) -> void:
	for i in range(_active.size() - 1, -1, -1):
		var a: _Active = _active[i]
		var fx: StatusEffect = a.effect
		if fx == null:
			_remove_at(i)
			continue
		if fx.tick_interval > 0.0 and fx.damage_per_tick != 0.0:
			a.tick_t += delta
			while a.tick_t >= fx.tick_interval:
				a.tick_t -= fx.tick_interval
				if host != null and host.has_method(&"take_damage"):
					host.take_damage(fx.damage_per_tick)
		if fx.duration > 0.0:
			a.remaining -= delta
			if a.remaining <= 0.0:
				_remove_at(i)

func _remove_at(i: int) -> void:
	var a: _Active = _active[i]
	if a.visual != null and is_instance_valid(a.visual):
		a.visual.queue_free()
	_active.remove_at(i)
	effect_removed.emit(a.effect)
