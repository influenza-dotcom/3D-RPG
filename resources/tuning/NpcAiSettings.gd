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
## Smallest angle (degrees) a deliberately-missed warning shot deflects by — the low end of the miss spread.
@export var miss_deflect_min_deg: float = 5.0
## Largest angle (degrees) a warning shot deflects by — the high end of the miss spread. Keep above min.
@export var miss_deflect_max_deg: float = 12.0
## How many seconds before a shot lands the incoming-shot warning beep plays (it also gates the in-sync
## aim-radial blink) — part of the NPC's firing cadence. Higher = more warning before the hit lands.
@export var beep_lead_time: float = 0.5

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
## Seconds between an NPC's raid-a-container scans — how often it looks for loot nearby.
@export var scavenge_scan_interval: float = 1.5
## How far (m) a scavenge scan reaches for raidable containers.
@export var scavenge_scan_radius: float = 12.0

@export_group("Loadout")
## Spare clips an armed NPC spawns with (drives reloads and what their corpse yields).
@export var starting_clips: int = 4

@export_group("Stealth")
## Do dead bodies raise the alarm? When ON, every NPC death leaves a discoverable Corpse marker at the spot,
## and a nearby UNAWARE NPC that SEES it gets spooked -- it investigates the body and calls out, so a quiet
## kill risks blowing your cover. OFF (default) -> no markers spawn and the corpse scan is a no-op, so the
## FSM is byte-identical to before. Turn it on to make stealth kills consequential, then playtest.
@export var body_discovery: bool = false
## Can a NOISE pull an NPC that has NOT yet acquired an enemy into investigating it? ON -> any NPC with
## `hearing` walks toward the loudest nearby &"noise" source (the player emits one live; thrown decoys /
## machines add more), regardless of disposition -- a guard hears your shot through a wall, a townsperson
## looks up when something crashes (companions following a leader are exempt). OFF (default) -> noise only
## matters once an NPC already has you as a target (today's behaviour), so the no-target idle path is
## byte-identical. Pairs with body_discovery: both share the no-enemy "investigate a point" path.
@export var hearing_initiates: bool = false
## Seconds between a no-target NPC's noise + corpse group scans (the &"noise" / &"corpse" walk + LOS rays),
## throttled like scavenging so an idle crowd doesn't rescan every frame. The walk-to-the-spot motion still
## runs every frame off the last result; only the (re)scan is paced. 0 = scan every frame. Only matters when
## hearing_initiates or body_discovery is on.
@export var distraction_scan_interval: float = 0.3
## Do WALLS muffle sound? When ON, a noise an NPC hears (a heard target's noise OR a &"noise" decoy) is
## attenuated when solid geometry sits between the enemy's eye and the source -- so a decoy through a doorway
## carries while one behind a wall doesn't. OFF (default) -> sound rounds corners exactly as before
## (behaviour-preserving). Makes interiors tactical; pairs with hearing_initiates / the thrown decoy.
@export var hearing_occlusion: bool = false
## How much a wall between the listener and a noise cuts its audible RADIUS (0..1) when hearing_occlusion is on.
## 0.5 = heard at half range behind a wall; 1.0 = a walled-off noise is silenced. Only matters with occlusion on.
@export_range(0.0, 1.0) var hearing_wall_attenuation: float = 0.5
## How far (m) before a noise source the occlusion ray stops, so the source's OWN body (the player's ~0.5 m
## capsule carrying the live noise, a thrown decoy's collider) is never mistaken for an occluding wall. Must
## exceed the widest noise-carrier's radius -- 1.0 clears the player capsule with headroom. A real wall within
## this distance of the source (on the listener's side) won't muffle. Only matters with occlusion on.
@export var hearing_source_skip: float = 1.0

@export_group("Music reactions")
## Do nearby NPCs react to a PLAYING radio they can hear (within the radio's audible_radius)? When ON, an idle
## non-hostile NPC turns its head toward the radio and comments once, keyed to the song/playlist QUALITY (a
## deterministic score of the radio's text). OFF (default) -> a playing radio is inert to NPCs, byte-identical to
## before. It is a passive notice + bark, NOT an investigate -- the NPC does not walk over. Needs head_look on for
## the head to actually turn (the comment fires either way). Pairs with the radio's audible_radius @export.
@export var music_reactions: bool = false
## Quality score (0..1) below which a song reads AWFUL (the lowest comment tier). Below music_tier_good -> MEH.
@export_range(0.0, 1.0) var music_tier_meh: float = 0.25
## Quality at/above music_tier_meh and below this -> MEH; at/above this and below music_tier_great -> GOOD.
@export_range(0.0, 1.0) var music_tier_good: float = 0.5
## Quality at/above this -> GREAT (the NPC loves it). Keep above music_tier_good.
@export_range(0.0, 1.0) var music_tier_great: float = 0.8

@export_group("Head look")
## Do NPC heads track what they're attending to INDEPENDENTLY of the body (Fallout-3/NV style)? When ON, any NPC
## carrying a NpcHeadLookMount rotates its VISIBLE head toward its foe / a nearby player / a noise it's
## investigating -- smoothly, clamped to a neck cone -- instead of only swivelling the whole body (which reads as
## lifeless). OFF (default) -> the mount no-ops and the head sits at its rest pose, byte-identical to before. Flip
## it on, then playtest (the head aim axis/sign can need a per-rig tweak).
@export var head_look: bool = false
