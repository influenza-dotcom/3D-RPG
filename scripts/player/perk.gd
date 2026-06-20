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
## attribute names. An unknown key is ignored AND warned (see validate), so a typo doesn't silently do nothing.
@export var stat_bonuses: Dictionary = {}
## OPTIONAL ability scene granted on unlock (added under the player, like UpgradePickup's `grants`).
@export var grants_ability: PackedScene
## Prerequisite perk ids that must already be unlocked before this one can be.
@export var requires_perks: Array[StringName] = []

## Warn (and return false) for any stat_bonuses key that isn't a real CharacterStats attribute — a typo'd or
## renamed stat is silently skipped when applied otherwise. Called by PerkManager on unlock; also usable by a
## content validator. Mirrors GoapProfile.validate's "surface stale authoring at boot" idiom.
func validate() -> bool:
	var ok := true
	var known := CharacterStats.stat_names()
	for key in stat_bonuses:
		if not known.has(String(key)):
			push_warning("Perk '%s': stat_bonuses key '%s' is not a CharacterStats attribute — it will be ignored." % [id, key])
			ok = false
	return ok
