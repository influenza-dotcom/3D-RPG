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

## A stable signature for this loadout (scene + profile + faction + weapon), used by NpcPool to bucket
## interchangeable instances. Two definitions with the SAME four resources share a pool bucket, so a reused
## instance is guaranteed to already carry this exact loadout (no re-stamp / mesh re-swap needed on reuse).
func loadout_signature() -> String:
	var scene_path: String = npc_scene.resource_path if npc_scene != null else ""
	var prof: String = profile.resource_path if profile != null else ""
	var fac: String = faction_override.resource_path if faction_override != null else ""
	var wep: String = weapon_override.resource_path if weapon_override != null else ""
	return "%s|%s|%s|%s" % [scene_path, prof, fac, wep]

## Stamp this definition's per-spawn overrides onto a freshly-instantiated (pre-_ready) NPC: the profile archetype,
## or — profile-less — the faction / weapon overrides. MUST be called BEFORE add_child so NPC._ready reads them
## (_apply_profile / _resolve_faction / the weapon branch all run in _ready). Shared by EncounterSpawner._spawn_one
## AND NpcPool warming, so the two stamp identically (a homogeneous pool bucket = one loadout). A profile WINS over
## the faction/weapon overrides (the all-or-nothing archetype contract); setting both warns.
func apply_overrides(npc: Node) -> void:
	if profile != null:
		npc.set(&"profile", profile)
		if faction_override != null or weapon_override != null:
			push_warning("SpawnDefinition: a definition with a `profile` ALSO sets faction_override/weapon_override — the profile wins and the overrides are ignored (use overrides only on a profile-less definition).")
	if faction_override != null:
		npc.set(&"faction_id", "")  # clear the id dropdown so our faction override wins in _resolve_faction
		npc.set(&"faction", faction_override)
	if weapon_override != null:
		npc.set(&"weapon_data", weapon_override)
