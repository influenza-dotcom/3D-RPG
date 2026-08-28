class_name Faction
extends Resource

## A faction an NPC can belong to (FNV-style). Assign one to an NPC's `faction` export; a null
## faction means the NPC is UNALIGNED and uses its own standalone `disposition` instead.
##
## A faction carries: a stable id (used as the dictionary key in the Reputation autoload), a
## display name, the faction's BASELINE disposition toward the player before reputation shifts
## it, and faction-vs-faction relations (consumed by NPC.is_hostile_to for NPC-vs-NPC aggro:
## a relation < 0 makes this faction's NPCs attack the other faction's NPCs).

@export_group("Identity")
## Stable lookup key. MUST be unique per faction .tres — Reputation stores the player's standing
## keyed by this string, so two factions sharing an id would share a reputation pool.
@export var id: StringName = &""
## Human-readable name for dialogue / UI.
@export var display_name: String = ""
## What ONE member of this faction is called INSIDE A SENTENCE, indefinite and lowercase, article included:
## "a raider", "a townsperson", "an enforcer". `display_name` can't do this job -- it's a plural proper noun
## for label contexts ("Raiders"), and "You were killed by Raiders." is not a sentence about the one NPC that
## shot you. Read by the death card / purse-robbed toast when the killer is a faction member the player was
## never introduced to (Player._killer_faction_noun): "You were killed by a raider." instead of the generic
## "a stranger". BLANK (the default) keeps the old anonymous wording -- an unnamed faction is not a wrong
## faction, it just doesn't get named at you. UNALIGNED NPCs have no faction at all and always read "a
## stranger". Note this NEVER overrides a name you know: once introduced, the card says who it was.
@export var member_noun: String = ""

@export_group("Disposition & Relations")
## The faction's attitude toward the player at ZERO reputation, before Reputation applies its
## threshold shift. raiders => HOSTILE; townsfolk => NEUTRAL (or FRIENDLY). Reputation reads this
## as the baseline, then nudges it up/down by the player's standing.
@export var default_disposition: Disposition.Kind = Disposition.Kind.NEUTRAL

## --- Faction-vs-faction relations ---
## Maps another faction's id (StringName) -> a relation score (float; <0 enemies, >0 allies).
## Consumed by NPC.is_hostile_to for NPC-vs-NPC aggro. Authored in the .tres as e.g.
## { &"townsfolk": -1.0 } on the raiders faction.
@export var relations: Dictionary = {}

## Relation score toward another faction (0.0 = neutral / unlisted). Read by NPC.is_hostile_to;
## <0 means this faction treats `other_id` as an enemy.
func relation_to(other_id: StringName) -> float:
	return float(relations.get(other_id, 0.0))
