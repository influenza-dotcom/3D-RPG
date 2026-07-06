@tool
class_name StatusEffect
extends Resource

## A timed BUFF / DEBUFF a StatusEffectManager runs on a character (player or NPC): periodic damage
## (poison/burn), a move-speed multiplier (slow/haste), per-stat tweaks, and an optional clinging visual.
## Authored as a .tres and applied by a consumable (Item.consumable_effect) or — later — a weapon hit.
## The SAME resource also serves as a PASSIVE held-item buff: dropped into Item.held_passive_effect it is read (by
## the carrier's PassiveItemBuffs) purely for its stat_modifiers + speed_multiplier while the item is carried —
## duration / tick_interval / damage_per_tick / visual_effect are ignored on that path (author duration = 0).

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
## Per-stat additive tweaks while active, e.g. { "agility": 2 }. CONSUMED for the MULTIPLIER stats — agility
## (move/jump), gunplay (weapon damage / sway), persuasion (shop prices), streetwise (reputation) — via
## Character.status_stat_modifier, which each live seam folds into the CharacterStats derived method's `bonus` arg.
## NOT consumed for strength/endurance on the TIMED path: those are stamped once into carry_capacity/max_hp at
## spawn (not read live). The held-item path (Item.held_passive_effect) is the exception — PassiveItemBuffs
## re-stamps a held strength/endurance total into carry_capacity/max_hp. Buffs never touch get_stat, so no boost
## (timed or held) ever passes a dialogue skill check or a stat-gate.
@export var stat_modifiers: Dictionary = {}
## Move-speed multiplier while active (0.5 = slowed, 1.5 = hastened; 1.0 = no change). Consumed via
## Character.status_move_multiplier.
@export var speed_multiplier: float = 1.0
## OPTIONAL scene attached to the host while the effect is active (a particle/overlay), freed when it ends.
@export var visual_effect: PackedScene
