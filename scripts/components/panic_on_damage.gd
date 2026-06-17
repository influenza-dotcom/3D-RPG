@tool
class_name PanicOnDamage
extends Node

## Drop-in: a frightened NPC may BREAK and flee once it's hurt mid-fight — a coward bolts as the fight turns
## against it. The chance scales with how hurt it is (panic_scale × fraction of HP lost). Drop it under an NPC;
## the NPC calls react() on every hit it takes. It's AUTO-ADDED (seeded from the NPC's `temperament`) when you
## don't drop one in, so behaviour is unchanged — drop a CONFIGURED instance to override per-NPC, or set
## `enabled = false` so THIS NPC holds its ground no matter how hurt.

## Off = this NPC never panic-flees (it fights on regardless of how hurt).
@export var enabled: bool = true
## How readily it breaks [0..1]: flee chance = this × the fraction of max HP currently lost. 0 = fearless.
## Seeded from the NPC's `temperament` when auto-added.
@export var panic_scale: float = 0.0

## Called by the host NPC from _on_damaged_by on every hit it takes (HP already reduced). Rolls the fear
## chance and, on a break, flips the NPC to FLEE. Only mid-combat, and only once (no re-roll while already
## fleeing). `host` is passed (duck-typed) so a bare-instance unit test can drive it with a stub.
func react(host: Variant) -> void:
	if not enabled or host == null or host.hp <= 0.0:
		return
	if panic_scale <= 0.0 or host.is_fleeing() or not host.is_in_combat():
		return
	if randf() < fear_for(host.hp, host.max_hp):
		host.break_and_flee()

## The flee CHANCE for this hit — panic_scale scaled by the fraction of max HP currently lost. Pure, so a unit
## test pins the boundaries (full HP = 0, dead = panic_scale) without depending on the random roll.
func fear_for(hp: float, max_hp: float) -> float:
	return panic_scale * (1.0 - clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0))

func _get_configuration_warnings() -> PackedStringArray:
	if get_parent() is NPC:
		return PackedStringArray()
	return PackedStringArray(["PanicOnDamage must be a child of an NPC (it reacts to that NPC taking damage)."])
