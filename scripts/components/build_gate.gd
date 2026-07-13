@tool
class_name BuildGate
extends Node

## A drop-in BUILD REQUIREMENT: drop one under an interactable (Door / Lock / TriggerVolume) and it's consulted
## before the host opens / fires. Gates on a player STAT (>= value), a learned PERK, and/or a granted ABILITY —
## every SET requirement must pass (AND). The build-aware twin of Lock, so the physical world reacts to who the
## player has become. Empty (no requirement set) always passes.

## Faction registry (preloaded by path) for the reputation gate (WR-1).
const Factions = preload("res://scripts/faction/factions.gd")

@export var required_stat: StringName = &""     ## a CharacterStats stat the opener needs at >= required_value. Empty = no stat gate.
@export var required_value: int = 1
@export var required_perk: StringName = &""      ## a Perk id the opener must have learned. Empty = no perk gate.
@export var required_ability: StringName = &""   ## a granted ability / mechanic id the opener must have. Empty = no ability gate.
@export var required_faction_id: String = ""     ## a faction id the player needs standing with (WR-1). Empty = no rep gate.
@export var required_reputation: float = 0.0     ## minimum standing with required_faction_id to pass.

## The first BuildGate under `host`, or null — how an interactable finds its own gate (BuildGate.of(self)), mirroring Lock.of.
static func of(host: Node) -> BuildGate:
	if host == null:
		return null
	for c in host.get_children():
		if c is BuildGate:
			return c as BuildGate
	return null

## True when `opener` meets every SET requirement. Fail-closed (a null opener / missing capability fails). Reads
## are duck-typed so any opener exposing stats_or_default / a PerkManager child / has_mechanic works.
func passes(opener: Node) -> bool:
	if opener == null:
		return false
	if required_stat != &"":
		var v := 0
		if opener.has_method(&"stats_or_default"):
			v = int(opener.stats_or_default().get_stat(required_stat))
		if v < required_value:
			return false
	if required_perk != &"":
		var pm := _perk_manager(opener)
		if pm == null or not pm.has_perk(required_perk):
			return false
	if required_ability != &"":
		if not (opener.has_method(&"has_mechanic") and opener.has_mechanic(required_ability)):
			return false
	if required_faction_id != "":
		var fac := Factions.by_id(required_faction_id)
		if fac == null or Reputation.get_reputation(fac) < required_reputation:
			return false  # WR-1: gate the world on the player's standing with a faction
	return true

## A short denial reason for a toast (the first FAILED requirement), or "" when the gate passes. Re-checks each
## requirement like passes() so it names the one that actually failed — not merely the first one that's SET (a set
## stat the opener MEETS must not be reported when it's really the perk gate that's blocking).
func deny_reason(opener: Node) -> String:
	if passes(opener):
		return ""
	if opener == null:
		return "Locked"
	if required_stat != &"":
		var v := 0
		if opener.has_method(&"stats_or_default"):
			v = int(opener.stats_or_default().get_stat(required_stat))
		if v < required_value:
			return PlayerText.requires_stat(required_stat, required_value)
	if required_perk != &"":
		var pm := _perk_manager(opener)
		if pm == null or not pm.has_perk(required_perk):
			return PlayerText.requires_perk(required_perk)
	if required_ability != &"":
		if not (opener.has_method(&"has_mechanic") and opener.has_mechanic(required_ability)):
			return PlayerText.requires_ability()
	if required_faction_id != "":
		var fac := Factions.by_id(required_faction_id)
		if fac == null or Reputation.get_reputation(fac) < required_reputation:
			return PlayerText.requires_standing(required_faction_id)
	return "Locked"

func _perk_manager(opener: Node) -> PerkManager:
	for c in opener.get_children():
		if c is PerkManager:
			return c
	return null

## Self-populate the required_stat dropdown from the CharacterStats attribute names (SUGGESTION; blank stays valid).
func _validate_property(property: Dictionary) -> void:
	if property.name == "required_stat":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = CharacterStats.stat_names_csv()
	elif property.name == "required_faction_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = Factions.ids_csv()
