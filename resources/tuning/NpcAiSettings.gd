class_name NpcAiSettings
extends Resource

## Global NPC BRAIN tuning — the behaviour numbers shared by every NPC, on one inspector page
## (resources/tuning/NpcAiSettings.tres), read as GameSettings.npc_ai.<field>. Per-NPC variety
## (sight ranges, move speeds, dispositions, voices, loot) stays on the NPC / Perception / NpcData
## exports; THIS page is the species-wide dials.

@export_group("Targeting & engagement")
## Seconds between full target re-acquisition scans (invalidation still retargets immediately).
@export var retarget_interval: float = 0.5
## Fallback engage range (m) for a weapon with no effective_range.
@export var unranged_aim_fallback: float = 15.0
## Within this (m) a combatant treats its shot as CLEAR even when the LOS ray self-occludes
## (a target crowded onto the muzzle starts the ray inside its own collider) — fire anyway.
@export var point_blank_range: float = 2.0
## A deliberately-missed warning shot deflects by this many degrees (min..max).
@export var miss_deflect_min_deg: float = 5.0
@export var miss_deflect_max_deg: float = 12.0

@export_group("Self care")
## An NPC reaches for a medkit below this HP fraction...
@export var medkit_hp_frac: float = 0.5
## ...at most once per this many ms.
@export var medkit_cooldown_ms: int = 4000
## Combat over: seconds of calm before the weapon goes back in the holster.
@export var holster_delay: float = 2.5

@export_group("Companion follow")
## Following allies hold position this far (m) from the leader.
@export var follow_standoff: float = 3.0
## Fallen this far behind (m) AND off-screen -> the catch-up blink may fire...
@export var follow_teleport_distance: float = 14.0
## ...at most once per this many seconds.
@export var follow_teleport_cooldown: float = 3.0

@export_group("Scavenging")
## Seconds between raid-a-container scans, and how far (m) the scan reaches.
@export var scavenge_scan_interval: float = 1.5
@export var scavenge_scan_radius: float = 12.0

@export_group("Loadout")
## Spare clips an armed NPC spawns with (drives reloads and what their corpse yields).
@export var starting_clips: int = 4
