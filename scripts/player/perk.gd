@tool
class_name Perk
extends Resource

## A permanent player upgrade unlocked at a PerkStation (or, later, on level-up): a bundle of permanent stat
## bonuses and/or a granted ability, optionally gated behind prerequisite perks (a simple perk tree). Authored
## as a .tres.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
## Permanent stat bonuses applied on unlock, e.g. { "strength": 2, "agility": 1 } — keys are CharacterStats
## attribute names; unknown keys are ignored.
@export var stat_bonuses: Dictionary = {}
## OPTIONAL ability scene granted on unlock (added under the player, like UpgradePickup's `grants`).
@export var grants_ability: PackedScene
## Prerequisite perk ids that must already be unlocked before this one can be.
@export var requires_perks: Array[StringName] = []
