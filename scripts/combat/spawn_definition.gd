@tool
class_name SpawnDefinition
extends Resource

## One entry in an EncounterSpawner: WHICH enemy to spawn, HOW MANY, and the per-spawn overrides. The npc_scene
## is instanced `count` times scattered within spawn_radius; the profile / faction / weapon overrides are stamped
## on each, and auto_aggro makes them target the player on arrival.

## The enemy scene to instance (e.g. res://scenes/enemies/NPC.tscn).
@export var npc_scene: PackedScene
## How many of it to spawn.
@export_range(1, 99) var count: int = 1
## Scatter radius (m) around the spawner that the spawns land in.
@export var spawn_radius: float = 2.0
## OPTIONAL archetype stamped on each spawn (NpcData). The primary override — it sets faction / weapon / etc.
## (a profile's faction wins over faction_override below).
@export var profile: NpcData
## OPTIONAL faction override, applied when no profile dictates one.
@export var faction_override: Faction
## OPTIONAL weapon override, applied when no profile dictates one.
@export var weapon_override: WeaponData
## Make each spawn immediately hostile to + targeting the player (skip the perceive-first delay).
@export var auto_aggro: bool = true
## Seconds between each NPC in this definition (0 = all at once).
@export var spawn_delay: float = 0.0
