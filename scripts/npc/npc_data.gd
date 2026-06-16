class_name NpcData
extends Resource

## A reusable NPC ARCHETYPE profile — the data-driven alternative to hand-overriding ~40 inspector fields on
## every enemy instance. Assign one to an NPC's `profile` export and `NPC._apply_profile()` stamps these
## values onto the NPC in _ready, BEFORE it reads its config. Author archetypes once in resources/characters/
## (raider, townsperson, sniper, shopkeeper) and reuse them, exactly like Faction.tres / WeaponData — instead
## of reassembling each enemy by hand (today Level.tscn's "Psycho Sniper" carries ~30 inline overrides).
##
## EITHER/OR by design: a profiled NPC is driven ENTIRELY by its profile (assign a profile XOR tune inline);
## to vary one stat, author a variant .tres. An NPC with NO profile keeps its inline exports unchanged, so
## every existing scene is unaffected.
##
## NOTE: threat_response is an int (@export_enum), NOT NPC.ThreatResponse — typing it as the NPC enum would
## form an NpcData <-> NPC class-compile cycle (NPC already references NpcData via its `profile` export). The
## int maps 1:1 onto NPC.ThreatResponse (0 = FIGHT, 1 = FLEE). Bark lines are a separate BarkSet (added next);
## this resource is the tuning layer.

@export_group("Identity")
## The archetype's name (stamped onto the NPC's display_name) — what shows in talk prompts / kill feed.
@export var display_name: String = ""
## This archetype's RPG stat sheet — copied onto the NPC at spawn (null = a neutral baseline). Lets a
## designer give a whole archetype (a brawny raider, a sharpshooter) its stats in one place. ENDURANCE/
## STRENGTH stamp the NPC's max_hp/carry at spawn; the rest read live at their seams, same as the player.
@export var stats: CharacterStats = null
## The "+friend" head-popup icon, floated over THIS NPC when the player rescues it by killing its attacker. Leave null for no rescue cue.
@export var popup_positive: Texture = null

@export_group("Vitals & outline")
## Starting/max health (HP) for this archetype. Higher = tankier; ENDURANCE in the stat sheet can raise it further.
@export var max_hp: float = 10.0
## Master switch for this archetype's combat outline. Off = flash-only overlay, no rim.
@export var has_outline: bool = true
## Outline rim colour. Combatants default to black; a friendly archetype can tint it differently.
@export var outline_color: Color = Color.BLACK
## Outline thickness fed to the shader's outline_width uniform. 0.085 is the standard enemy rim; higher = thicker.
@export var outline_width: float = 0.085

@export_group("Hostility")
## Pick this archetype's faction from a DROPDOWN by id (townsfolk / raiders / neutral_wildlife). Resolves to the
## matching Faction .tres on the NPC in _ready. Leave EMPTY to use the `faction` resource slot below (custom /
## inline faction) or for unaligned. (Keep the suggestion list in sync with resources/factions/.)
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, "townsfolk,raiders,neutral_wildlife") var faction_id: String = ""
## Faction this archetype belongs to (a Faction .tres). Null = UNALIGNED: it uses the standalone disposition below instead of faction + reputation.
@export var faction: Faction = null
## Standalone attitude, used ONLY when faction is null. HOSTILE = aggressive on sight (today's default enemy).
@export var disposition: Disposition.Kind = Disposition.Kind.HOSTILE
## When true, the disposition above wins toward the player even with a faction set — an individual attitude overriding the faction's.
@export var disposition_overrides_faction: bool = false
## Cumulative player damage a FRIENDLY NPC forgives before turning hostile. Higher = a more patient ally; 0 = flips on the first hit.
@export var friendly_aggro_threshold: float = 8.0

@export_group("Weapon")
## The WeaponData this archetype wields (sets damage, rate, projectile, etc.). Null = unarmed / fists.
@export var weapon_data: WeaponData = null
## Local offset of the held gun's grip from the NPC origin — where the view-model hangs and shots/laser originate. Model faces +Z.
@export var muzzle_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
## Corrective rotation (degrees) for the held weapon model. Default -90 yaw maps a +X-barrel gun onto the NPC's +Z facing.
@export var weapon_mesh_rotation: Vector3 = Vector3(0.0, -90.0, 0.0)
## Multiplies time per shot on top of the weapon's attack_speed. 1 = the weapon's own rate; >1 slower, <1 faster (per-archetype difficulty).
@export var rate_of_fire_factor: float = 1.0
## Chance [0..1] each shot AT THE PLAYER deflects wide and misses (plays a ricochet). 0 = never miss.
@export var miss_chance: float = 0.0
## Engagement-range FALLBACK (m) for a weapon that sets NO effective_range (e.g. thrown rock). A ranged weapon scales its own standoff instead.
@export var fire_range: float = 30.0
## Vertical nudge (m) on the aim point relative to the target's capsule centre. 0 = aim dead centre.
@export var target_height: float = 0.0
## Immune to this NPC's OWN weapon recoil (the weapon's self_knockback) — for a heavy gunner. Blasts/rams/other shooters still knock it back.
@export var immune_to_weapon_knockback: bool = false
## Start with an EMPTY clip, so the NPC must reload before its first shot. Off = starts loaded.
@export var starts_unloaded: bool = false

@export_group("Inventory")
## Extra items the NPC CARRIES (a keycard, stims, junk), seeded into its backpack at spawn ON TOP of the
## weapon + ammo. Real carried items: pickpocketable + dropped on death. Add the same item twice for two.
## (`loot` below is RANDOM drops; these are DETERMINISTIC — what it actually holds.)
@export var starting_items: Array[Item] = []
## EASY count-based carried items (item + count rows) -- the archetype twin of NPC.item_stacks. Seeded on top of
## weapon_data + starting_items. "30 ammo, 2 stims" is two rows instead of repeating items.
@export var item_stacks: Array[ItemStack] = []

@export_group("Perception")
## How far (m) the NPC can see a target.
@export var sight_range: float = 25.0
## Full view-cone angle (degrees). Anything outside this off its facing is unseen.
@export var fov_degrees: float = 110.0
## Multiplier on sight_range while the target is fully crouched (stealth): 1.0 = crouch doesn't help; 0.5 =
## spotted only at half range. A sharp-eyed archetype keeps this high; a near-sighted one drops it.
@export_range(0.0, 1.0) var crouch_sight_mult: float = 0.5
## Seconds a target must stay in view before the NPC is fully alerted — the player's reaction window. Higher = slower to notice.
@export var time_to_detect: float = 1.0
## Seconds it stays wary at the last-known spot after losing sight before giving up. Higher = more persistent search.
@export var forget_time: float = 4.0
## Height (m) the sight / line-of-sight rays start from — the NPC's eyes.
@export var eye_height: float = 1.4
## Hear the player's noise (gunfire, fast movement) even outside the view cone? Crouch-walking stays silent.
@export var hearing: bool = true
## How fast (rad/s-ish) it rotates to face what it's tracking. Higher = snaps to aim quicker.
@export var turn_speed: float = 8.0
## Investigation look-around speed (rad/s): once at the last-known spot, the facing sweeps a slow circle hunting the target. At 0.8 a full turn takes ~8s, so a 4s forget_time reads as a half-circle scan before giving up.
@export var search_sweep_rate: float = 0.8

@export_group("Laser")
## Draw a laser sight that brightens as the NPC detects / locks onto the player (combatants only).
@export var show_laser: bool = true
## Colour of the laser sight beam.
@export var laser_color: Color = Color(1.0, 0.1, 0.1)

@export_group("Movement")
## Walk / chase speed (m/s).
@export var move_speed: float = 4.0
## Ground acceleration (m/s^2) — also how fast it sheds knockback and brakes to a stop. Higher = snappier, sticks landings sooner.
@export var move_accel: float = 25.0
## Air acceleration (m/s^2). Kept low so a blast carries it before it recovers control.
@export var air_accel: float = 2.0
## Alerted, it closes until the target is within this FRACTION of the weapon's effective range, then holds and fires. Lower = fights from closer.
@export var engage_range_fraction: float = 0.9
## Upward impulse (m/s) for hopping ledges / the far end of an up navigation-link.
@export var jump_velocity: float = 10.0
## Seconds between combat-dodge rolls while alerted on a live target. Each roll may trigger a brief lateral strafe (see dodge_chance).
@export var dodge_interval: float = 2.5
## Probability [0..1] that a dodge roll fires, breaking into a lateral strafe to be a harder target. 0 = never dodge (disables it).
@export_range(0.0, 1.0) var dodge_chance: float = 0.5
## How long (seconds) each dodge strafe lasts before pursuit resumes. Higher = longer side-steps.
@export var dodge_duration: float = 0.35
## Strafe speed during a dodge, as a fraction of move_speed. 1.0 = full speed sideways; lower = a slower shuffle.
@export var dodge_speed_fraction: float = 1.0

@export_group("Behavior")
## FIGHT = engage and shoot; FLEE = run away and never fire. Maps 1:1 onto NPC.ThreatResponse (0/1).
@export_enum("Fight", "Flee") var threat_response: int = 0
## How readily it BREAKS and flees once hurt in a fight [0..1]. 0 = fearless (never flees); 1 = cowardly (bolts as the fight turns).
@export var temperament: float = 0.0
## Roam near the spawn point while idle (no hostile target) instead of standing still.
@export var wanders: bool = false
## How far (m) from the spawn point wandering may stray.
@export var wander_radius: float = 6.0
## Shortest dwell (seconds) at a wander stop before picking a new spot (the low end of the randomised range).
@export var wander_dwell_min: float = 1.5
## Longest dwell (seconds) at a wander stop (the high end of the randomised range). Keep >= dwell_min.
@export var wander_dwell_max: float = 4.0
## When fleeing, how far ahead (m) to aim each step away from the threat. Bigger = longer panicked strides.
@export var flee_distance: float = 12.0
## Before talking, this non-hostile NPC walks to within this distance (m) of the player so the chat is framed. 0 = speak in place.
@export var talk_approach_distance: float = 2.5
## Safety cap (seconds) on the pre-talk approach: if blocked or the player keeps backing off, it speaks from wherever it reached.
@export var talk_approach_timeout: float = 4.0

@export_group("Barks")
## Optional per-archetype bark lines. Each category left empty falls back to the NPC's built-in defaults, so
## a profile overrides only the lines it cares about. Null = the NPC uses all its default lines.
@export var bark_set: BarkSet = null

@export_group("AI (GOAP)")
## EXPERIMENTAL: drive this archetype's AI with the GOAP planner instead of the FSM (default false = the FSM).
## Stamped onto the NPC; the strangler-fig migration flips this per-archetype as goals move off the FSM.
@export var use_goap: bool = false
## The GOAP goal-set + per-action cost overrides for this archetype — the executor reads it to build its
## action/goal library. Unused while use_goap is false / the library hasn't been migrated yet.
@export var goap_profile: GoapProfile = null

@export_group("Loot")
## Optional drop table rolled into the corpse on death (NPC.gore), ON TOP of the weapon + ammo it was
## carrying. Null = drop only what it carried. Lets a "raider" carry a chance at a keycard or rare item.
@export var loot: LootTable = null
