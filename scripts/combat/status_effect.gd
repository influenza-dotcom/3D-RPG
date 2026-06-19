@tool
class_name StatusEffect
extends Resource

## A timed BUFF / DEBUFF a StatusEffectManager runs on a character (player or NPC): periodic damage
## (poison/burn), a move-speed multiplier (slow/haste), per-stat tweaks, and an optional clinging visual.
## Authored as a .tres and applied by a consumable (Item.consumable_effect) or — later — a weapon hit.

## Stable id — re-applying an effect whose id is already active REFRESHES its duration instead of stacking. Empty = always stacks.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
## Seconds the effect lasts. 0 = permanent until explicitly removed.
@export var duration: float = 5.0
## Seconds between periodic-damage ticks. 0 = no periodic effect.
@export var tick_interval: float = 1.0
## HP applied to the host on each tick (positive = damage, e.g. poison/burn). Needs tick_interval > 0.
@export var damage_per_tick: float = 0.0
## Per-stat additive tweaks while active, e.g. { "strength": 2 }. NOTE: tracked + queryable now
## (StatusEffectManager.stat_modifier) but not yet consumed by CharacterStats — that hookup is a follow-up.
@export var stat_modifiers: Dictionary = {}
## Move-speed multiplier while active (0.5 = slowed, 1.5 = hastened; 1.0 = no change). Consumed via
## Character.status_move_multiplier.
@export var speed_multiplier: float = 1.0
## OPTIONAL scene attached to the host while the effect is active (a particle/overlay), freed when it ends.
@export var visual_effect: PackedScene
