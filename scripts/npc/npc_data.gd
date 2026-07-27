@tool
class_name NpcData
extends Resource

## A reusable NPC ARCHETYPE profile — the data-driven alternative to hand-overriding ~40 inspector fields on
## every enemy instance. Assign one to an NPC's `profile` export and `NPC._apply_profile()` stamps these
## values onto the NPC in _ready, BEFORE it reads its config. Author archetypes once in resources/characters/
## (raider.tres, sniper.tres, Townsperson.tres, DefaultCharacterRes.tres ship) and reuse them, exactly like
## Faction.tres / WeaponData — instead of reassembling each enemy by hand (TestLevel.tscn's perched "Von Lime"
## sniper still carries ~30 inline overrides; sniper.tres is the reusable distillation of that role).
##
## EITHER/OR by design: a profiled NPC is driven ENTIRELY by its profile (assign a profile XOR tune inline);
## to vary one stat, author a variant .tres. An NPC with NO profile keeps its inline exports unchanged, so
## every existing scene is unaffected.
##
## NOTE: threat_response is an int (@export_enum), NOT NPC.ThreatResponse — typing it as the NPC enum would
## form an NpcData <-> NPC class-compile cycle (NPC already references NpcData via its `profile` export). The
## int maps 1:1 onto NPC.ThreatResponse (0 = FIGHT, 1 = FLEE). Bark lines are a separate BarkSet (added next);
## this resource is the tuning layer.

## Faction registry (no class_name -> preloaded by path), used by _validate_property to populate the
## faction_id dropdown from resources/factions/.
const Factions := preload("res://scripts/faction/factions.gd")

@export_group("Identity")
## The archetype's name (stamped onto the NPC's display_name) — what shows in talk prompts / kill feed.
@export var display_name: String = ""
## Optional STABLE identity id (Slice 3) — the key quest KILL/TALK matching and the known-names ledger use for
## this character, decoupled from the player-facing display_name. Leave BLANK for the display_name fallback
## (fine for every existing archetype; nothing breaks). Set it on story NPCs so (a) renaming/localising the
## display_name can't stall an authored quest or re-stranger the cast, and (b) two distinct characters may share
## one display_name without merging identities. Mirrors npc.gd's save_id idiom (an optional stable id, blank =
## legacy fallback). Deliberately NOT in PROFILE_STAMPED_FIELDS / _stamp_profile_full: identity lives HERE on the
## shared archetype and is consumed via identity_key() — there is no per-NPC field to stamp it onto.
@export var id: StringName = &""
## This archetype's RPG stat sheet — copied onto the NPC at spawn (null = a neutral baseline). Lets a
## designer give a whole archetype (a brawny raider, a sharpshooter) its stats in one place. ENDURANCE/
## STRENGTH stamp the NPC's max_hp/carry at spawn; the rest read live at their seams, same as the player.
@export var stats: CharacterStats = null
## The "+friend" head-popup icon, floated over THIS NPC when the player rescues it by killing its attacker. Leave null for no rescue cue.
@export var popup_positive: Texture = null

@export_group("Vitals & outline")
## Starting/max health (HP) for this archetype. Higher = tankier; ENDURANCE in the stat sheet can raise it further.
@export var max_hp: float = 10.0
## CT-2 mitigation (mirrors Character): flat armour soaked off every hit, then damage_reduction (0..0.95) shrugs a
## fraction of the rest. 0/0 = no mitigation (the default). zone_damage_mult = per-BodyPart weakpoint multipliers
## (empty = none); e.g. { Character.BodyPart.TORSO: 3.0 } for a soft core. Stamped onto the NPC at spawn.
@export var armor_flat: float = 0.0
@export_range(0.0, 0.95) var damage_reduction: float = 0.0
@export var zone_damage_mult: Dictionary = {}
## Master switch for this archetype's combat outline. Off = flash-only overlay, no rim.
@export var has_outline: bool = true
## Outline rim colour. Combatants default to black; a friendly archetype can tint it differently.
@export var outline_color: Color = Color.BLACK
## Outline thickness fed to the shader's outline_width uniform. 2.0 is the standard enemy rim; higher = thicker.
@export var outline_width: float = 2.0

@export_group("Hostility")
## Pick this archetype's faction from a DROPDOWN by id. Resolves to the matching Faction .tres on the NPC in
## _ready. Leave EMPTY to use the `faction` resource slot below (custom / inline faction) or for unaligned.
## The dropdown AUTO-POPULATES from resources/factions/ (see _validate_property) -- adding a .tres lists it.
@export var faction_id: String = ""
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
## EASY count-based carried items (item + count rows) -- the archetype twin of NPC.item_stacks. Seeded on top of
## weapon_data. "30 ammo, 2 stims" is two rows instead of repeating items.
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
## Seconds it keeps CHASING the target's live position after losing sight (dropped off a ledge, ducked behind cover)
## before downgrading to searching the last-known spot — the "follow me off a ledge" window. Higher = commits over
## ledges / around corners harder before giving up; 0 = the old instant give-up on line-of-sight loss.
@export var pursuit_grace_time: float = 2.0
## Height (m) the sight / line-of-sight rays start from — the NPC's eyes. Measured UP from the NPC ORIGIN, which is
## the CAPSULE CENTRE (feet ~0.975 m below it), NOT the feet: ~0.8 sits the eye just below the head crown. The old
## 1.4 overshot ~0.45 m ABOVE the head, letting NPCs see over cover they were hidden behind. See NPC.eye_height.
@export var eye_height: float = 0.8
## Hear the player's noise (gunfire, fast movement) even outside the view cone? Crouch-walking stays silent.
@export var hearing: bool = true
## How fast (rad/s-ish) it rotates to face what it's tracking. Higher = snaps to aim quicker.
@export var turn_speed: float = 8.0
## Investigation look-around speed (rad/s): once at the last-known spot, the facing sweeps a slow circle hunting the target. At 0.8 a full turn takes ~8s, so a 4s forget_time reads as a half-circle scan before giving up.
@export var search_sweep_rate: float = 0.8

@export_group("Laser")
## Draw a laser sight that brightens as the NPC detects / locks onto the player (combatants only).
@export var show_laser: bool = true

@export_group("Movement")
## Walk / chase speed (m/s).
@export var move_speed: float = 4.0
## Ground acceleration (m/s^2) — also how fast it sheds knockback and brakes to a stop. Higher = snappier, sticks landings sooner.
@export var move_accel: float = 25.0
## Air acceleration (m/s^2). Kept low so a blast carries it before it recovers control.
@export var air_accel: float = 2.0
## Alerted, it closes until the target is within this FRACTION of the weapon's effective range, then holds and fires. Lower = fights from closer.
@export var engage_range_fraction: float = 0.9
## Upward impulse (m/s) for a THREATENING-pursuit NPC to vault onto a higher spot it can't walk up — chiefly the
## player on a low crate/ledge (reach = v^2/2g, so this is also the clearable height; see npc.gd jump_velocity).
## 4.5 matches npc.gd's own default — the old 10.0 launched a profiled NPC ~5m on a climb-jump (read as bouncing),
## and _stamp_profile_full copies this onto the node unconditionally, so a too-high default here re-inherited that.
@export var jump_velocity: float = 4.5
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
## Idle posture toggle: seated while unaware/off-duty; stands for combat/search, companion follow, and cutscenes, but talks from the seat.
@export var sitting: bool = false
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
## Voice a HURT bark ("I'm hit!") when this NPC is wounded mid-combat. Turn OFF for a silent / stoic archetype
## (a disciplined soldier, a mute) that takes hits without crying out — the line pool is unchanged, just muted.
@export var damage_barks: bool = true
## Voice a DEATH-WITNESS reaction ("Murderer!" / "Good riddance.") when this NPC sees the player kill someone
## nearby. Turn OFF for an unreactive archetype that ignores deaths around it. (Gates only THIS NPC's reaction.)
@export var death_barks: bool = true
## Mutter an ACTIVE-SEARCH call-out ("Where are you?") while this NPC hunts a lost target / a noise. Turn OFF for a
## silent stalker that searches without giving away its progress. (The "!" sting and the give-up line are separate.)
@export var search_barks: bool = true

@export_group("AI (GOAP)")
## The GOAP goal-set + per-action cost overrides for this archetype — the executor reads it to build its
## action/goal library (the optional per-archetype tuning over the planner's defaults; null = the defaults).
@export var goap_profile: GoapProfile = null

@export_group("Loot")
## Optional drop table rolled into the corpse on death (NPC.gore), ON TOP of the weapon + ammo it was
## carrying. Null = drop only what it carried. Lets a "raider" carry a chance at a keycard or rare item.
@export var loot: LootTable = null

@export_group("Death")
## On a PLAYER kill, drop the player's reputation with this NPC's faction (the kill_penalty). Turn OFF for a
## "free kill" target — a marked traitor / bounty whose death its faction doesn't hold against you. No effect
## on an unfactioned NPC (no standing to lose).
@export var sours_faction_on_death: bool = true
## Briefly hard-pause the game (the kill-beat hitstop) when this NPC dies. Turn OFF for a trash-mob / swarm
## enemy so the screen doesn't hitch on every kill — keep ON for weighty, single-target deaths.
@export var pause_on_kill: bool = true
## Hold this NPC frozen in place for a brief beat (EffectsSettings.death_freeze_duration) on death BEFORE it
## bursts into gore — the "freeze then explode" kill pop. Turn OFF for a trash-mob / swarm enemy that should
## gore the instant it dies. Independent of pause_on_kill: this freezes only THIS body (the world keeps moving);
## pause_on_kill hitches the whole screen.
@export var freeze_on_death: bool = true

## THE canonical identity key for this archetype (Slice 3): the authored `id`, or StringName(display_name) when
## no id is set — so every pre-identity resource keys exactly as before. Every identity consumer (NPC.identity_key
## -> GameState.notify_kill/notify_talk/reveal_name) routes through here; never read `id` raw at a call site.
func identity_key() -> StringName:
	return id if id != &"" else StringName(display_name)


## Editor-only: populate the faction_id dropdown from the factions on disk (resources/factions/*.tres) so a new
## faction .tres appears automatically -- no hand-maintained suggestion string to keep in sync. @tool + this hook
## is the only way to set a DYNAMIC enum-suggestion; safe here because NpcData is pure data (no node lifecycle).
func _validate_property(property: Dictionary) -> void:
	if property.name == &"faction_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = Factions.ids_csv()
