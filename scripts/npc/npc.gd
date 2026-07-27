@tool
## @system NPC Brain
## @seam _build_components builds one GoapExecutor per NPC; _physics_process ticks it as the sole AI decision layer in both physics branches (npc.gd:814,1832,1873).
## @risk An early-return or reorder before _executor.tick in either _physics_process branch (npc.gd:1831/1872) silently stops that NPC deciding, no error.
## @risk _perception.sense (1845) must precede the has-target tick (1872); the executor reads _perception.state (goap_executor.gd:83), so reordering picks the wrong arm silently.
## @risk In-tree tick and _act_* delegate bodies have no automated coverage (tick is playtest-only per README) — a broken build/ordering shows only in playtest.
## @test res://tests/test_npc_goap_library.gd
## @test res://tests/test_npc.gd
class_name NPC
extends Character

##TODO -- THIS FILE IS TOO DAMN LONG. IT MUST BE REFACTORED INTO NODES AS COMPONENTS

## Faction registry (preloaded, NOT class_name -> no test-suite global-class-cache dependency): resolves the
## faction_id dropdown to a Faction resource in _ready.
const Factions := preload("res://scripts/faction/factions.gd")
const GoapLibrary := preload("res://scripts/npc/goap/goap_library.gd")  # canonical goal/action names for spawn validation

@export_group("Profile")
## An NPC ARCHETYPE profile. Assign one and it stamps ~50 tuning fields onto this NPC in _ready (see
## _apply_profile), so a raider / townsperson / sniper is ONE resource assignment instead of dozens of inline
## overrides. By default a profiled NPC is driven ENTIRELY by its profile; leave it null to tune inline as
## before (every existing scene does this, so they're unaffected).
@export var profile: NpcData = null
## How the profile merges. OFF (default): the profile is authoritative -- it overwrites every tuning field (the
## original all-or-nothing behavior). ON: the profile fills only the fields you left at their default, so a
## per-instance inline tweak WINS (assign the raider archetype, but bump THIS one's HP). Cleanest from a blank
## base (enemy.tscn / civilian.tscn) -- NPC.tscn pre-sets combat fields that would then win over the profile.
@export var profile_fills_blanks_only: bool = false
## The GOAP goal-set + per-action cost overrides for this NPC (authored here or on NpcData); the executor reads
## it to build its action/goal library — the optional per-archetype tuning over the planner's defaults (a null
## profile = authored defaults). The GOAP planner is the NPC brain; this only retunes it.
@export var goap_profile: GoapProfile = null

@export_group("Body & Head")
@export_subgroup("Custom Models")
## Assign an NpcLook resource (a reusable .tres, or an inline sub-resource) to override THIS NPC's appearance:
## body/head models + scale/offset/rotation, body/head textures + tints, and arm/leg tints -- all from one place.
## Author a "raider look" / "townsperson look" once and reuse it across NPCs. Null = keep the shared default look
## authored on the NPC's BodyModelSwap child. BodyModelSwap reads it live (editor preview), so you re-skin any NPC
## by clicking it in the level, no "Editable Children" needed.
@export var look: NpcLook


## The single non-player actor class. One NPC spans everything from an inert townsperson to a ranged
## combatant — behaviour is DATA-DRIVEN, not subclassed:
##   - weapon_data == null -> CIVILIAN: no gun / laser / fire path, but still senses, wanders, flees,
##                            and turns when shot. Give it a faction / disposition to be neutral or
##                            friendly, and threat_response = FLEE to run rather than square up.
##   - weapon_data != null -> COMBATANT: wields the SAME Weapon component the player does, aimed by
##                            AI (Perception view-cone + line-of-sight + detection meter). It locks
##                            the NEAREST hostile (the player or a faction-opposed NPC, via
##                            is_hostile_to) then turns, aims, telegraphs as its weapon allows, and attacks
##                            after it has actually
##                            noticed the target — no 360 degree omniscience.
##
## Extends Character for HP / damage / gore / blast / knockback (shared with the Player, which is
## deliberately NOT an NPC). Owns the combat OUTLINE — built via TalkHelpers.make_outline_material()
## (the one shared outline builder, also used by the look-at talk highlight) and chained IN FRONT of
## Character's damage-flash overlay (outline.next_pass = flash) so a single material_overlay produces
## both the inflated-hull rim and the hit-flash — and the FNV-style hostility model (faction +
## disposition + reputation + provoke-on-attack).
##
## Designer surface: drop the scene in, optionally point weapon_data at a .tres, set faction /
## disposition / threat_response / wanders, and tune the perception + firing values in the inspector.

@export_group("Identity & Outline")
## This NPC's display name — shown as the speaker label in dialogue (DialogueManager uses it when a
## DialogueLine leaves `speaker` blank). Empty => unnamed, and the dialogue name label stays hidden.
@export var display_name: String = ""

## Optional STABLE id for the EXACT-snapshot save tier (WorldSnapshot — manual quicksave/slots). It lets a
## quicksave match THIS authored NPC across a reload so it comes back at its saved position (or stays dead). Leave
## blank for the level|node-path fallback (fine for a hand-placed NPC that is never renamed/re-parented); set it on
## story NPCs whose exact-save state must survive a scene-layout edit. Unused by the lean autosave/Continue profile.
## Mirrors Corpse.save_id; keyed POSITION-FREE (see snapshot_key) because an NPC moves.
@export var save_id: StringName = &""

## Slice 3 (stable identity): the quest/known-names key, LATCHED once in _ready right after the profile stamp so a
## RUNTIME display_name rename (Claimable pet naming writes a player-typed name into display_name) can never mutate
## this NPC's quest-match key mid-life. Internal — read it through identity_key(). &"" until _ready runs (off-tree
## test builds never latch; identity_key() then derives live).
var _identity_key: StringName = &""

## Master switch for this actor's combat outline. Off => flash-only overlay (no rim).
@export var has_outline: bool = true
## Outline rim colour. Combatants default to black; a friendly NPC can override per instance.
@export var outline_color: Color = Color.BLACK
## Outline thickness fed to the shader's `outline_width` uniform (shader scales it x4 in clip
## space). 2.0 is the standard combat rim every NPC scene ships.
@export var outline_width: float = 2.0
## Rim colour by resolved_disposition(): HOSTILE -> red, FRIENDLY -> green, NEUTRAL -> the
## `outline_color` export (black by default). So the rim reads the NPC's attitude at a glance and
## re-tints live when that attitude changes (provoke / reputation shift) — see _apply_outline().
const OUTLINE_HOSTILE := Color(0.9, 0.1, 0.1)   ## red — attacks the player on sight
const OUTLINE_FRIENDLY := Color(0.1, 0.8, 0.2)  ## green — allied
## Blue rim worn ONLY while this NPC is following the player as a recruited companion (Feature I). It
## OVERRIDES the disposition colour in _outline_color_for_disposition() so a companion reads as "mine"
## at a glance regardless of its underlying FRIENDLY/NEUTRAL tint; cleared the moment it stops following.
const OUTLINE_FOLLOWING := Color(0.15, 0.45, 1.0)  ## blue — recruited companion following the player
const PICKPOCKET_TALKABLE_NAME := "PickpocketTalkable"
const PICKPOCKET_TALKABLE_SIZE := Vector3(1.0, 2.0, 1.0)

@export_group("Hostility")
## Pick this NPC's faction from a DROPDOWN by id -- resolves to the matching Faction .tres in _ready. Leave
## EMPTY to use the `faction` resource slot below instead (for a custom / inline faction). Empty id + null
## faction => UNALIGNED (the NPC uses its standalone `disposition`). The dropdown AUTO-POPULATES from
## resources/factions/ (see _validate_property) -- adding a .tres lists it, no code edit.
@export var faction_id: String = ""
## The faction this NPC belongs to. NULL => UNALIGNED: the NPC uses its standalone `disposition`
## below instead of faction + player-reputation. Set this to a Faction .tres (e.g. raiders,
## townsfolk) to make the NPC's attitude track the player's reputation with that faction. The faction_id
## dropdown above, when set, overrides this in _ready.
@export var faction: Faction = null
## Standalone attitude, used ONLY when `faction` is null (unaligned). Defaults to HOSTILE so a
## combatant with no faction set behaves exactly like today's enemy (aggressive on sight).
@export var disposition: Disposition.Kind = Disposition.Kind.HOSTILE
## When true, THIS NPC's individual `disposition` above is used toward the player even if it has a
## faction — an individual attitude that overrides the faction's. The faction still drives reputation,
## NPC-vs-NPC relations, and grouping. (Default false = faction disposition, as before.)
@export var disposition_overrides_faction: bool = false
## Cumulative PLAYER damage a FRIENDLY NPC absorbs before it turns hostile. An ally forgives incidental
## hits (stray friendly-fire) — only being hurt past this much flips it; a neutral still aggros on the
## first hit. Higher = a more forgiving ally; 0 = turns on the first point of damage.
@export var friendly_aggro_threshold: float = 8.0
## Cumulative player damage taken WHILE FRIENDLY, counting toward friendly_aggro_threshold; once it crosses, the
## NPC is provoked. Not used in npc.gd itself — the ProvokeOnAttack component (provoke_on_attack.gd) accumulates it.
@warning_ignore("unused_private_class_variable")
var _player_aggression: float = 0.0
## When true, this NPC has been provoked (e.g. the player attacked it) and is hostile regardless
## of faction/disposition until something clears it. Runtime only — never authored in the editor.
var _provoked: bool = false
## The exact (streetwise-scaled, clamp-aware) rep delta THIS NPC's provoke() applied to its faction, so
## forgive_provoke() can reverse it precisely and stand the whole faction back down. Runtime only.
var _provoke_rep_delta: float = 0.0
## BETRAYAL one-shot: latched true the first time a holster de-escalation ACTUALLY pardons this NPC's provoke
## (forgive_provoke). Once set, a SUBSEQUENT holster refuses to stand it down again — so if the player forgives us
## then RE-ATTACKS (react() re-provokes), holstering no longer works: we "won't fall for it twice" and fight to the
## death. This closes the free-kill farm where the player spammed the hold-R holster toggle to keep pardoning a mob
## they kept shooting. Gated by GameSettings.npc_ai.holster_forgiveness_once so a designer can restore the old
## infinitely-forgivable behaviour, and EXEMPTED for a fleeing NPC (fleeing_always_forgivable) — something running
## away isn't shooting back, so there's no farm to close; see _holster_forgiveness_available(). Runtime only, like
## _provoked / _pickpocket_caught — a fresh scene reload or pool reuse gives it a clean slate (reset in
## reset_for_reuse).
var _holster_forgiveness_spent: bool = false
## True while the current player-caused provoke is eligible to remind the player about holster forgiveness if THIS
## NPC kills them. Set by ProvokeOnAttack only, so alarms/theft/dialogue provokes do not masquerade as attack lessons.
var _holster_forgiveness_tutorial_active: bool = false
## PICKPOCKET one-strike lockout: latched true the moment the player is CAUGHT lifting this NPC's pockets
## (LootScreen._on_pickpocket_caught -> react_to_caught_theft). Once set, Talkable._can_pickpocket refuses another
## attempt on this NPC FOR GOOD — even after it calms down / is forgiven — so a botched steal isn't retryable on
## the same mark. Runtime only (matches _provoked; a fresh scene reload gives it fresh pockets).
var _pickpocket_caught: bool = false
## The AUTHORED threat_response, captured the FIRST time break_and_flee() panics this NPC into FLEE. -1 = never
## panicked. `threat_response` is an authored @export that break_and_flee MUTATES for the rest of a life, which makes
## it per-life state under pooling: without this, a reused body that broke last life comes back a permanent coward —
## it never fires again (GoapActionFireArmed/Unarmed are gated on `not is_fleeing()`) and is permanently
## holster-forgivable (fleeing_always_forgivable). reset_for_reuse restores it. Runtime only.
var _pre_panic_threat_response: int = -1

@export_group("Weapon")
## The weapon this NPC fires — any WeaponData .tres, exactly like the player's. NULL => CIVILIAN
## (no weapon, laser, or fire path is built; the NPC still senses, wanders, flees, and faces).
@export var weapon_data: WeaponData = null
## Local offset of the held gun's grip from the NPC origin — where the weapon view-model hangs (and
## the shot/laser origin when the model has no barrel marker of its own). This model faces +Z.
@export var muzzle_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
## Corrective local rotation (degrees) for the held weapon model. View-models point their barrel down
## +X (e.g. ak_472), while this NPC faces +Z, so the default -90 deg yaw maps the gun's +X onto the
## NPC's forward. Tune per scene if a particular weapon needs a different grip pose.
@export var weapon_mesh_rotation: Vector3 = Vector3(0.0, -90.0, 0.0)
## Multiplies how long each shot takes: the NPC's fire cadence is the equipped WEAPON's attack_speed
## times this (1 = the weapon's own rate, >1 slower, <1 faster). The weapon is the single source of truth
## for the rate — tune per-NPC difficulty here instead of a duplicate cooldown. (Replaced fire_cooldown.)
@export var rate_of_fire_factor: float = 1.0
## Chance [0..1] that each shot AT THE PLAYER deflects wide and misses (plays a ricochet). 0 = never miss.
@export var miss_chance: float = 0.0
## Engagement-range FALLBACK for a weapon that sets NO effective_range (e.g. the thrown rock leaves it 0) —
## the engage distance is then min(this, GameSettings.npc_ai.unranged_aim_fallback). A weapon that DOES set effective_range
## scales the standoff itself (see _engage_range), so this no longer caps a ranged weapon's reach.
@export var fire_range: float = 30.0
## Vertical nudge on the aim point (centre of the target's collision capsule). 0 = dead centre.
@export var target_height: float = 0.0
## Immune to this NPC's OWN weapon recoil (the weapon's self_knockback). Lets a heavy / anchored NPC
## fire a high-recoil weapon (e.g. the sniper) without being shoved around by it. Only the wielder's
## recoil is ignored — blasts, rams, and being shot by others still knock it back normally.
@export var immune_to_weapon_knockback: bool = false
## Start with an EMPTY clip, so the NPC must reload before its first shot — it keeps its gun unloaded
## until it engages. Off = starts loaded, as usual.
@export var starts_unloaded: bool = false

@export_group("Group AI (allies)")
## ALERT PROPAGATION (GA-1): on first-hand contact (this NPC goes ALERTED on a live target), it tells
## same-faction allies within this radius (m) to converge + investigate the threat — so a squad reacts
## together instead of fighting as solo islands. Latched once per engagement; an alerted ally does NOT
## re-broadcast (it only investigates), so there's no alert storm. 0 = OFF (no propagation — the default, so
## existing encounters are unchanged until a designer opts a guard in).
@export var alert_radius: float = 0.0
## Audible radius (m) of this NPC's GUNFIRE on the shared &"noise" channel — lets a guard two rooms away HEAR
## the firefight and come investigate, so combat is no longer silent to off-screen allies. INERT until a
## listener opts in (GameSettings.npc_ai.hearing_initiates, default off); 0 = this NPC's gunfire is silent.
@export var gunfire_noise_radius: float = 18.0
## Audible radius (m) of this NPC's DEATH on the &"noise" channel (a cry / thud allies can hear). 0 = silent.
@export var death_noise_radius: float = 12.0
## Min seconds between gunfire-noise pulses, so a full-auto burst emits a steady pulse instead of one
## NoiseSource per bullet. The death cry is one-shot and ignores this.
@export var combat_noise_interval: float = 0.4
## How fast each gunfire/death noise burst fades (m/s) and how long it lives (s) — keep it short, it's a
## momentary cue. lifetime is floored just above 0 so the source is always one-shot (never a leaking persistent one).
@export var combat_noise_decay: float = 0.0
@export var combat_noise_lifetime: float = 0.35

@export_group("Inventory")
## Extra items this NPC CARRIES (a keycard, stims, junk), seeded into its backpack at spawn ON TOP of the
## EASY count-based carried items: "30 ammo, 2 stims" as rows (item + count). Seeded into the backpack
## (pickpocketable + dropped on death too).
@export var item_stacks: Array[ItemStack] = []

@export_group("Loot")
## Optional drop table rolled into the corpse on death (NPC.gore), ON TOP of the weapon + ammo + carried items.
## Null = drop only what it carried. A profile's own NpcData.loot wins when a profile is assigned (the all-or-
## nothing profile contract); this inline slot is for a NON-profiled NPC -- e.g. a one-off raider's keycard chance.
@export var loot: LootTable = null

@export_group("Perception")
## How far the NPC can see.
@export var sight_range: float = 25.0
## Full view-cone angle (degrees). Outside this off its facing it simply can't see you.
@export var fov_degrees: float = 110.0
## Multiplier on sight_range while you're fully crouched — stealth: 1.0 = crouch doesn't help; 0.5 = spotted
## only at half range when fully crouched. Mirrored onto Perception in _build_perception (the per-archetype fix).
@export_range(0.0, 1.0) var crouch_sight_mult: float = 0.5
## Seconds in view before it's fully alerted — your reaction window.
@export var time_to_detect: float = 1.0
## Seconds it stays wary at your last-known spot before giving up.
@export var forget_time: float = 4.0
## Seconds it keeps CHASING your live position after losing sight (you dropped off a ledge, ducked behind cover)
## before it downgrades to searching your last-known spot — the "follow me off a ledge" window. Mirrored onto
## Perception in _build_perception; 0 = the old instant give-up. Stamped from NpcData.pursuit_grace_time.
@export var pursuit_grace_time: float = 2.0
## Eye height (metres) the sight / LOS / hearing rays start from, measured UP from this NPC's ORIGIN. ⭐The origin is
## the CAPSULE CENTRE (enemy.tscn's CollisionShape sits at local y≈0 with a ~1.95 m capsule, so the feet are ~0.975 m
## BELOW the origin and the head crown ~0.975 m above) — NOT the feet. 1.4 here put the eye ~0.45 m ABOVE the model's
## own head, so NPCs saw/heard over cover their heads were visibly behind. ~0.8 lands the eye just below the crown
## (a natural eye line, ~1.6 m above the feet). If you ever change the capsule, re-derive this from the new centre.
@export var eye_height: float = 0.8
## Hear the player's noise (gunfire, fast movement) even outside the cone? Crouch is silent.
@export var hearing: bool = true
## How fast it rotates to face what it's looking at.
@export var turn_speed: float = 8.0
## The investigation look-around: once arrived at the last-known spot, the facing sweeps in a slow circle
## hunting for the target (rad/s — at 0.8 a full turn takes ~8s, so a 4s forget_time reads as a half-circle
## scan before giving up). Designer-tunable per NPC in the inspector, like the Perception ranges.
@export var search_sweep_rate: float = 0.8
## Per-NPC STEALTH-SENSE opt-in, OR'd with the global GameSettings.npc_ai gates: turn this ONE NPC's body-
## discovery / noise-hearing on by itself, leaving the rest of the cast oblivious. Off = follow the global flag.
@export var body_discovery_opt_in: bool = false
@export var hearing_initiates_opt_in: bool = false

@export_group("Laser")
## Draw a laser sight that brightens as it detects / locks onto you (combatants only).
@export var show_laser: bool = true

@export_group("Movement")
## How fast it walks / chases (m/s).
@export var move_speed: float = 4.0
## Ground acceleration — also how fast it sheds knockback / brakes to a stop (m/s^2).
@export var move_accel: float = 25.0
## Air acceleration (low, so a blast carries it before it recovers) (m/s^2).
@export var air_accel: float = 2.0
## Alerted: closes until the target is within this fraction of the weapon's effective range,
## then holds and fires (so it actually gets in range to hit).
@export var engage_range_fraction: float = 0.9
## Minimum upward impulse (m/s) for vaulting onto a higher spot the NPC can't walk up -- chiefly YOU perched on a low
## crate/ledge the navmesh treats as unreachable (also a baked ledge or up navigation-link, if a level provides one).
## Default 4.5 matches the Player's basic jump; when the target is higher, the NPC computes the stronger launch
## needed to reach that height plus a small clearance margin. Set 0 to disable jumping for this NPC. Only a
## THREATENING-pursuit NPC hops (chasing/searching/escorting, not a passing civilian), only AT the step, on the
## floor, and behind a cooldown, so it chases you up a ledge without jump-spamming while it is still running in.
@export var jump_velocity: float = 4.5
## Combat dodge (Feature #5): while ALERTED on a live target, every dodge_interval seconds the enemy
## rolls dodge_chance to break into a brief lateral STRAFE (left or right relative to the target) for
## dodge_duration, instead of standing still — so it's a harder target without constant jittering. The
## strafe drives _desired_velocity at dodge_speed_fraction of move_speed through the normal locomotion
## (pathing is untouched — pursuit resumes the instant the burst ends). 0 chance disables it entirely.
## Seconds between combat-dodge ROLLS. NpcCombat floors it to its DODGE_MIN_INTERVAL so an over-tuned value (e.g. 1.0
## on a "raider") can't make the NPC strafe almost every second — constant pacing, the exact thing this feature is
## meant to AVOID. Set dodge_chance = 0 for none.
@export var dodge_interval: float = 2.5
## Probability [0..1] each dodge roll fires, breaking into a lateral strafe to be a harder target. 0 = never dodge (disables the combat dodge entirely).
@export_range(0.0, 1.0) var dodge_chance: float = 0.5
## How long (seconds) each dodge strafe lasts before pursuit resumes. Higher = longer side-steps.
@export var dodge_duration: float = 0.35
## Strafe speed during a dodge, as a fraction of move_speed. 1.0 = full speed sideways; lower = a slower shuffle.
@export var dodge_speed_fraction: float = 1.0

@export_group("Behavior")
## How this NPC reacts to a hostile target it has noticed. FIGHT = engage and shoot (the default,
## i.e. today's enemy). FLEE = run away from the threat and never fire (a civilian / coward). Pair
## FLEE + `wanders` + a NEUTRAL/FRIENDLY disposition for a townsperson who only bolts when attacked.
enum ThreatResponse { FIGHT, FLEE }
## How this NPC reacts to a noticed hostile: FIGHT = engage and shoot (default enemy); FLEE = run away and never fire (a civilian/coward — pair with `wanders` + a NEUTRAL/FRIENDLY disposition for a townsperson).
@export var threat_response: ThreatResponse = ThreatResponse.FIGHT
## How readily this NPC BREAKS and flees once it takes damage in a fight [0..1]. 0 = fearless (never
## flees from being hurt); 1 = cowardly. The flee chance per damaging hit scales with how hurt it is
## (temperament * fraction of HP lost), so a coward bolts as the fight turns against it. This SEEDS the
## auto-built PanicOnDamage drop-in (panic_on_damage.gd), which owns the actual roll; drop a configured
## PanicOnDamage in the scene to override it per-NPC.
@export var temperament: float = 0.0
## Idle posture toggle: while UNAWARE and off-duty, hold this NPC at its post and ask BodyModelSwap to show a seated
## pose. Combat/search, companion follow, and cutscene movement stand it back up; dialogue talks from the seat.
@export var sitting: bool = false
## Roam near the spawn point while idle (no hostile target) instead of standing still.
@export var wanders: bool = false
## How far from the spawn point wandering may stray (metres).
@export var wander_radius: float = 6.0
## Seconds to linger at each wander stop before picking a new spot (randomised across this range).
@export var wander_dwell_min: float = 1.5
## Upper bound (seconds) of the wander-stop linger; the actual dwell is random between wander_dwell_min and this. Wider gap = less predictable pacing.
@export var wander_dwell_max: float = 4.0
## When fleeing, how far ahead (metres) to aim each step away from the threat.
@export var flee_distance: float = 12.0
## When the player talks to this (non-hostile) NPC, it walks to within this distance of the player
## before speaking, so the conversation is adequately framed (see prompt_talk -> the TalkApproach child).
## 0 => speak in place (no approach). Keep <= the ray's TALK_REACH (3.5 m) or it never needs to move.
@export var talk_approach_distance: float = 2.5
## Safety cap (seconds) on the pre-talk approach: if the path is blocked / the player keeps backing
## away, the NPC gives up closing and speaks from wherever it got to, rather than chasing forever.
@export var talk_approach_timeout: float = 4.0

# Loaded LAZILY (runtime load() in _ready, NOT a top-level preload) to avoid a circular resource
# dependency that leaves the hit-spark scene empty: explosion_area.gd / attack.gd reference `NPC`
# -> loading npc.gd would (via preload) pull in weapon.tscn -> which contains attack.gd -> which
# preloads explosion_area.tscn -> closing the load-time loop, so Godot hands back a 0-node scene.
# A runtime load() (cached by Godot) breaks the cycle; do NOT change this back to a const preload.
const WEAPON_SCENE_PATH := "res://scenes/weapons/weapon.tscn"
## Muzzle FX on the held gun — the SAME authored scenes the player's rig instances (spark burst + ejected
## casing), loaded lazily like weapon.tscn so npc.gd stays light at parse time.
const SPARK_FX_SCENE_PATH := "res://scenes/effects/spark_attack.tscn"
const SHELL_FX_SCENE_PATH := "res://scenes/effects/shell_drop.tscn"
const LASER_MAX_LENGTH := 60.0
## --- Audio-cue timing the firing CADENCE owns (the sound ASSETS + mix live on the NpcAudioCues child) ---
## The shared (static) cooldown so a swarm spotting you at once plays one MGS "!" sting. Kept here as the
## fallback + test anchor (a unit test pins NPC.ALERT_COOLDOWN_MS); the child reads the tunable
## GameSettings.npc_bark.alert_cooldown_ms, which defaults to (mirrors) this value.
const ALERT_COOLDOWN_MS: int = 3000
## Sniper charge-sting de-dup window — only dedups near-simultaneous triggers (lock + an immediate first
## shot); the fire cadence is the real rhythm. Kept short so genuine per-shot lock-ons each sting — a longer
## window swallowed the telegraph on faster shooters. The _on_aim throttle actually reads the tunable
## GameSettings.npc_bark.aim_cooldown_ms (which DEFAULTS to this const); this stays as the terminal fallback
## + test anchor. _on_aim itself lives on the root so a unit test can poke _last_aim_msec / _aim_sfx_delay on a bare instance.
const AIM_COOLDOWN_MS: int = 120
## A short beat between a shot and its charge-up sting so the two don't blur together (see _on_aim). A
## unit test pins it as NPC.AIM_SFX_DELAY; _on_aim writes GameSettings.npc_bark.aim_sfx_delay (which
## defaults to this) to _aim_sfx_delay, so this const stays as the fallback/mirror + test anchor.
const AIM_SFX_DELAY: float = 0.1

## Head-popup icons — billboarded Sprite3D built in code (no .tscn), held then faded + freed.
## EXCLAMATION pops on first alert (alongside the MGS sting); NEGATIVE pops the moment this NPC
## turns hostile / its faction is soured, and again when it REFUSES a second holster pardon. Source
## res:// paths used directly (like MGS_ALERT) — the exclamation filename literally contains a space
## and "(1)", which is legal inside the string.
const POPUP_EXCLAMATION = preload("res://assets/textures/exclamation_1 (1).png")
const POPUP_NEGATIVE = preload("res://assets/textures/negativefriend.png")
## POSITIVE is NEGATIVE's mirror on the hostility cues: it pops when a holster pardon SUCCEEDS
## (forgive_provoke), so standing down reads as clearly as being provoked does. A const like NEGATIVE —
## the de-escalation feedback must always show, so it can't depend on the popup_positive export below
## (which a designer may deliberately leave null to mute the separate RESCUE cue).
const POPUP_POSITIVE = preload("res://assets/textures/w_friend.png")
## The "+friend" head-popup icon, floated over THIS NPC when the player rescues it by killing its attacker.
## Leave null for no rescue cue. When set it ALSO re-skins this NPC's holster-pardon cue (POPUP_POSITIVE
## is the fallback there), so custom "+friend" art stays consistent across both moments.
@export var popup_positive: Texture # = preload("res://assets/textures/w_friend.png")  # "+friend": shown when you rescue an NPC by killing its attacker
var _save_rewarded: bool = false  # one-shot guard so a multi-pellet killing blow only rewards the rescue once
## Popup geometry/timing consts (POPUP_HEAD_Y / POPUP_HOLD / POPUP_FADE / POPUP_WORLD_HEIGHT) live on NpcBarkUi now
## (the head-popup presentation child); _bark_duration_ms reads NpcBarkUi.POPUP_HOLD / .POPUP_FADE.

var _last_aim_msec: int = 0
var _aim_sfx_delay: float = -1.0  # >= 0 = a charge sting counting down to play; < 0 = idle (none pending)
var _aim_targeting_player: bool = false  # captured at lock-on: was the charge aimed at the PLAYER? (drives the sting volume)
var _weapon: Weapon
var _muzzle: Marker3D        # hand/grip anchor the gun model hangs off (at muzzle_offset)
var _weapon_mesh: Node3D     # the equipped weapon's instantiated view-model, held at the hand
var _gun_muzzle: Marker3D    # the held gun's own "Muzzle" barrel marker; null => shots/laser fall back to _muzzle
var _perception: Perception
## Cached head anchor for the sniper-glint origin (Feature #8): the rigged "Head" bone on the mesh's
## Skeleton3D, resolved once (lazily) so _report_aim blooms the glint at the NPC's ACTUAL head instead
## of a guessed eye_height offset off the feet. _head_skeleton is the skeleton that owns it, _head_bone
## its bone index (-1 = none found -> we fall back to the capsule top, then the eye_height offset).
var _head_skeleton: Skeleton3D = null
var _head_bone: int = -1
var _head_resolved: bool = false  # the lookup runs once; this latches it whether or not a bone was found
var _swapped_head: Node3D = null   # a BodyModelSwap component's swapped head, if one registered -- the head-look + glint track it
var _target: Node3D
var _target_body: Node3D  # target's collision shape (centre tracks crouch); falls back to _target
var _last_attacker: Node3D = null  # most recent hostile that damaged us; favoured over the nearest in _acquire_target
var _npc_grudges: Array[NPC] = []  # NPC peers we now treat as enemies because they DAMAGED us (is_hostile_to honours it)
var _hit_by_player: bool = false   # the real player has damaged us (drives the "Hey, thanks!" assist bark on death)
var _silent_death: bool = false    # Slice 6b: a takedown set this just before the lethal hit -> _on_died suppresses the witness bark (body-discovery is the delayed cost). One-shot, never reset.
var _hurt_bark_said: bool = false  # a wounded-ally cry has already fired this life (so it only plays once)
var _saw_combat: bool = false      # has been ALERTED since the last all-clear; drives the combat-over bark
var _was_aware: bool = false       # has NOTICED a threat (any non-UNAWARE state) since the last all-clear; drives the give-up barks
@warning_ignore("unused_private_class_variable")  # not used in npc.gd itself — the GOAP search action (goap_action_search.gd) reads/advances it off the host
var _search_sweep_t: float = 0.0   ## the search head-sweep phase — accumulates; only its derivative matters
var _was_distracted: bool = false  ## true while a NO-target NPC is investigating a noise/body (drives the give-up "lost interest" bark)
var _distraction_scan_t: float = 0.0  ## throttles the noise/corpse group scans — shared by _react_unaware (no-target) AND _react_distraction (has-target while UNAWARE), both via _scan_distractions (GameSettings.npc_ai.distraction_scan_interval)
var _fire_timer: float = 0.0       # shared attack wind-up timer: gun shots AND unarmed punches (see _shot_interval)
@warning_ignore("unused_private_class_variable")  # host-owned; NpcCombat reads/writes host._charging (npc_combat.gd)
var _charging: bool = false  # winding up a clear, in-range shot (drives the lock-on sting)
@warning_ignore("unused_private_class_variable")  # host-owned; NpcCombat reads/writes host._warned (npc_combat.gd)
var _warned: bool = false    # the incoming-shot beep already played for the current charge
var _shot_miss: bool = false # this shot was rolled to MISS — get_aim_direction deflects it wide (consumed there)
## The combat FIRING dispatch child (armed/unarmed bodies + the combat dodge) — npc_combat.gd, built in
## _build_components. The GOAP FireArmed/FireUnarmed actions drive it via the _act_alerted / _act_unarmed facades.
## Holds the dodge bookkeeping; the shared _fire_timer/_charging/_warned/_shot_miss stay here (above). Null off-tree.
var _combat: NpcCombat = null
var _spawn_yaw: float = 0.0
var _spawn_position: Vector3
var _desired_velocity: Vector3 = Vector3.ZERO
var _nav: NavigationAgent3D
var _avoid_velocity: Vector3 = Vector3.ZERO  ## last RVO collision-free velocity (velocity_computed); used while moving
var _avoid_ready: bool = false               ## false until the first callback -> fall back to the raw desired

# --- Cutscene control (CutsceneActor) --- the AI brain is suppressed while a cutscene has the wheel.
var _cutscene_control: bool = false
var _cutscene_walk_target: Vector3 = Vector3.ZERO
var _cutscene_has_walk: bool = false
var _cutscene_face_target: Vector3 = Vector3.ZERO
var _cutscene_has_face: bool = false
var _scripted_investigating: bool = false  ## an investigate() is in flight — _react_unaware decays it, never snaps it to idle
var _alerted_allies: bool = false          ## GA-1: latched once we've broadcast this engagement's alert; reset on the all-clear
## Anti-stuck steering: when the NPC is trying to move but barely progressing (a wall / prop / another NPC is
## blocking it), it veers ALONG the obstacle for a short burst so it slips around instead of grinding.
# Anti-stuck / nav-hop tuning now LIVES on Locomotor (the nav brain migrated there in Phase B). These aliases keep
# NPC.STUCK_TIME etc. resolving to the SAME values for the tests (test_npc reads NPC.STUCK_TIME / UNSTICK_TIME /
# STUCK_SPEED_FRAC) with Locomotor as the single source of truth — no drift.
const STUCK_SPEED_FRAC := Locomotor.STUCK_SPEED_FRAC
const STUCK_TIME := Locomotor.STUCK_TIME
const UNSTICK_TIME := Locomotor.UNSTICK_TIME
const STUCK_GIVEUP_TIME := Locomotor.STUCK_GIVEUP_TIME
const STUCK_HOLD_TIME := Locomotor.STUCK_HOLD_TIME
const CHASE_STUCK_GIVEUP_TIME := Locomotor.CHASE_STUCK_GIVEUP_TIME
const CHASE_STUCK_HOLD_TIME := Locomotor.CHASE_STUCK_HOLD_TIME
const OFF_MESH_RECOVER_DIST := Locomotor.OFF_MESH_RECOVER_DIST
const JUMP_COOLDOWN := Locomotor.JUMP_COOLDOWN
const HOP_MIN_CLIMB := Locomotor.HOP_MIN_CLIMB
const HOP_STEP_DISTANCE := Locomotor.HOP_STEP_DISTANCE
const HOP_HEIGHT_MARGIN := Locomotor.HOP_HEIGHT_MARGIN
const STUCK_HOP_TIME := Locomotor.STUCK_HOP_TIME
# Anti-stuck / nav-hop timers + latches MIGRATED to Locomotor (Phase B); apply_velocity + the _move_toward shell reach
# them via _locomotor. Only the STRANDED diagnostic counter stays here — soak_harness reads host._stranded_cycles and
# test_ranged_behavior calls host._tick_stranded, so the counter + its warn latch are HOST-owned; Locomotor calls back
# into _note_stranded() / _reset_stranded() to drive them.
var _locomotor: Locomotor = null  ## the nav brain (built DRIVEN in _ready, after _build_nav); owns pathing/hop/anti-stuck
var _stranded_cycles: int = 0    ## consecutive give-ups in the SAME spot — a run of these = stranded on a bad-bake island
var _last_giveup_pos: Vector3 = Vector3.ZERO  ## where we last gave up, to tell "same spot" from "moved on"
var _stranded_warned: bool = false  ## one stranded-warning per episode (cleared when we make real progress)
var _retarget_timer: float = 0.0
## The leader this NPC is escorting, or null when not following. Set by start_following() (the dialogue
## "join me" option calls it), cleared by stop_following(). CANONICAL state kept on the root because
## targeting (the NpcTargeting child's _acquire_target / _pick_defend_target) reads it through the host;
## the FOLLOW BEHAVIOUR (tailing + the hidden teleport) lives on the _follow child, which reads this field. While set, the NPC tails the
## leader, wears a blue rim, and defends them — see is_following / _treats_as_enemy.
var _leader: Node3D = null
## The character this NPC defends when it is NOT a player companion — set via guard()/stop_guarding() so an
## NPC can be a bodyguard for ANY character (need not be player-aligned). _protectee() prefers _leader.
var _guarding: Node3D = null

## --- Single-responsibility children, built in _ready (code-built, no .tscn) + the host ref set right
## after .new(). Each owns one slice of NPC behaviour; the root stays a thin coordinator + facade and
## null-guards every one (they're absent on an off-tree unit-test NPC built via .new() with no _ready). ---
var _outline: NpcOutline       # the combat rim pass (built only when an outline is wanted + a mesh exists)
var _laser: NpcLaser           # the laser-sight beam (combatants only)
var _audio_cues: NpcAudioCues  # the spot/charge/beep telegraph sounds
var _talk: TalkApproach        # the pre-talk walk-up
var _follow: CompanionFollow   # the recruited-companion follow + hidden teleport
var _stance: WeaponStance      # the draw / holster / out-of-combat-reload gun stance (combatants only)
var _noise_pulser: NoisePulser # generic drop-in that pulses our gunfire / death onto the &"noise" channel (owns the throttle)
var _mortality: NpcMortality   # death world-spawns: lootable corpse + stealth body marker + kill-XP (npc_mortality.gd)
var _senses: NpcSenses         # no-target environmental SCAN primitives: loudest noise / nearest radio / visible corpse (npc_senses.gd)
## The "go home" leash (npc_home_return.gd): sends us back to our authored post when the PLAYER DIES or after we've
## been off-screen for a while. Node-typed and built by SCRIPT PATH (never the bare class_name — see _build_components)
## so this @tool root doesn't name a newly-added class at parse time. Null off-tree / before _build_components.
var _home_return: Node = null

## Editor-only: populate the faction_id dropdown from the factions on disk (resources/factions/*.tres) so a new
## faction .tres appears automatically -- no hand-maintained suggestion string. @tool makes the editor honor this;
## every runtime lifecycle method (_ready, _physics_process) is is_editor_hint()-guarded so ONLY this hook runs in
## the editor -- the AI/weapon/nav/component build never executes there.
func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == &"faction_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = Factions.ids_csv()

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: in the editor only the faction_id dropdown (_validate_property) matters; never build the AI/components
	_apply_profile()  # stamp an assigned NpcData archetype onto our exports FIRST — before super() seeds hp from max_hp, and before the components / perception / weapon branch read the rest
	_identity_key = _derive_identity_key()  # latch the stable quest/known-names key POST-stamp (see identity_key)
	_resolve_faction()  # the faction_id dropdown (set here or stamped from the profile) -> the live Faction resource
	super()  # Character._ready(): set hp + build the flash overlay on the mesh tree.
	add_to_group(Groups.NPC)  # so hostile NPCs can find us as a target (the _acquire_target scan enumerates this)
	# WorldSnapshot (exact-save tier): record our death into GameState's live per-level ledger so a later manual
	# quicksave knows this authored NPC is dead — by capture time it has freed itself and can't be found in the tree.
	# Wired in CODE (not the scene's died->_on_died) so it fires for EVERY NPC base scene (enemy/civilian/blank).
	died.connect(_record_snapshot_death)
	# Behaviour children that EVERY NPC carries — built before _setup_outline so the outline child exists
	# (and after super(), so _flash_material is ready for it to chain onto). Senses + locomotion for every
	# NPC armed or not: wandering needs a nav agent, fleeing and the turn-when-shot both need a Perception.
	_build_components()
	_setup_outline()
	_spawn_yaw = rotation.y
	_spawn_position = global_position
	_build_perception()
	_build_nav()
	_build_locomotor()  # DRIVEN nav brain; injected with _nav (built just above) so there's ONE agent on the body
	_seed_carried_items()  # carried items FIRST, so equip-the-strongest sees a weapon authored in item_stacks
	# Weapon + laser ONLY for a combatant (weapon_data set). A null weapon_data is a civilian: no gun,
	# no laser, no fire path — _physics_process gates the ALERTED branch on `_weapon != null`.
	if weapon_data != null:
		_muzzle = Marker3D.new()
		add_child(_muzzle)
		_muzzle.position = muzzle_offset
		_weapon = load(WEAPON_SCENE_PATH).instantiate()
		add_child(_weapon)
		# No camera -> ScopeIn no-ops (no ADS) and the input-driven parts are disabled.
		_weapon.setup(self, null, _muzzle)
		_equip_initial_weapon()  # seed the backpack from weapon_data, then draw the STRONGEST gun in the bag
		_fire_timer = _shot_interval()  # seed a full wind-up so the first shot charges instead of firing instantly
		if starts_unloaded and _weapon.ammo:
			_weapon.ammo.current_ammo = 0  # keep the gun dry: the AI reloads before it can fire
		_build_weapon_mesh()  # render the equipped gun in the hand and re-point shots/laser at its barrel
		_build_laser()
		_stance = WeaponStance.new()  # draw / holster / out-of-combat reload — combatant-only, like the laser
		_stance.host = self
		add_child(_stance)
		_stance.holster_weapon()  # start with the gun put away; it's drawn the moment combat begins
	_acquire_target()
	# Bound the backpack to the SAME spatial grid the player carries (InventorySettings.grid_cols/rows — ONE knob
	# for both), so an NPC can hold no more than the player and the bag it DROPS (its corpse copy) plus the
	# pickpocket / exchange screens all render at the player's size. DEFERRED so it runs AFTER every spawn-time
	# seeder — our loadout above AND any RandomInventory child, which also defers its roll: we seed unbounded,
	# THEN clamp, so a normal loadout is never truncated. Only an over-authored bag (more than the grid holds)
	# is left with its overflow stacks kept-but-unplaced (enable_grid warns) — the accepted trade for a hard cap.
	if inventory != null:
		inventory.call_deferred(&"enable_grid", GameSettings.inventory.grid_cols, GameSettings.inventory.grid_rows)

## Resolve the faction_id DROPDOWN pick into the live `faction` resource (via the Factions registry). A non-empty
## id wins over the `faction` slot; an empty id leaves the slot as-authored. Runs in _ready before any consumer
## (HostilityHelpers / Reputation / is_hostile_to) reads `faction`.
func _resolve_faction() -> void:
	if faction_id.is_empty():
		return
	var f := Factions.by_id(faction_id)
	if f != null:
		faction = f

## THE stable identity key (Slice 3) — what GameState.notify_kill / notify_talk / reveal_name key this NPC by,
## decoupled from the player-facing display string (which public_name masks and a claimed pet's rename mutates).
## The _ready-latched value wins so a runtime display_name write can't move the key; the live derivation is the
## off-tree fallback (unit tests build NPCs without _ready).
func identity_key() -> StringName:
	return _identity_key if _identity_key != &"" else _derive_identity_key()

## Derivation rule: a profile with an AUTHORED NpcData.id -> that id (rename/localization-proof, routed through
## NpcData.identity_key — the one canonical accessor). Otherwise the EFFECTIVE authored display_name — which by
## now (post-_apply_profile) already holds the profile's name on the full-clobber path OR a kept inline override
## on the additive path, so a blank-id profile must NOT defer to profile.identity_key() (that would return the
## archetype's name and merge an additive instance's distinct inline name into it). Exactly today's key when no
## id is authored, so every existing scene/quest keys unchanged.
func _derive_identity_key() -> StringName:
	if profile != null and profile.id != &"":
		return profile.identity_key()
	return StringName(display_name)

## The NPC fields an NpcData profile stamps. The additive merge (profile_fills_blanks_only) snapshots/restores
## these; the full-clobber path sets them in _stamp_profile_full. Keep in sync with _stamp_profile_full.
const PROFILE_STAMPED_FIELDS: Array[StringName] = [
	&"display_name", &"popup_positive", &"max_hp", &"stats", &"has_outline", &"outline_color", &"outline_width",
	&"faction_id", &"faction", &"disposition", &"disposition_overrides_faction", &"friendly_aggro_threshold",
	&"weapon_data", &"muzzle_offset", &"weapon_mesh_rotation", &"rate_of_fire_factor", &"miss_chance", &"fire_range",
	&"target_height", &"immune_to_weapon_knockback", &"starts_unloaded", &"item_stacks",
	&"sight_range", &"fov_degrees", &"crouch_sight_mult", &"time_to_detect", &"forget_time", &"pursuit_grace_time", &"eye_height", &"hearing",
	&"turn_speed", &"search_sweep_rate", &"show_laser", &"move_speed", &"move_accel", &"air_accel",
	&"engage_range_fraction", &"jump_velocity", &"dodge_interval", &"goap_profile", &"dodge_chance", &"dodge_duration",
	&"dodge_speed_fraction", &"threat_response", &"temperament", &"sitting", &"wanders", &"wander_radius", &"wander_dwell_min",
	&"wander_dwell_max", &"flee_distance", &"talk_approach_distance", &"talk_approach_timeout",
	&"armor_flat", &"damage_reduction", &"zone_damage_mult",
]

## npc.gd @export defaults for the stamped fields, captured once from a throwaway probe and cached, so the
## additive merge can tell which fields THIS instance overrode (!= default) from the ones it left untouched.
static var _stamped_field_defaults: Dictionary = {}

## Stamp an assigned NpcData archetype onto our matching exports. FIRST line of _ready (before super() seeds hp
## from max_hp, before _build_components / _build_perception / the weapon branch read the rest). No profile -> a
## no-op (inline-authored exports stand). profile_fills_blanks_only OFF (default): the profile is AUTHORITATIVE,
## every field comes from it (the original behavior; existing scenes rely on it). ON: the profile fills only the
## fields this instance left at its npc.gd default; any inline-overridden field WINS.
func _apply_profile() -> void:
	if profile == null:
		return
	if not profile_fills_blanks_only:
		_stamp_profile_full()
		return
	# Additive: remember the fields this instance overrode (!= the npc default), stamp the whole profile, then
	# restore those overrides so the inline tweaks win and everything else comes from the profile.
	var defaults := _npc_stamped_defaults()
	var overrides := {}
	for f in PROFILE_STAMPED_FIELDS:
		if get(f) != defaults.get(f):
			overrides[f] = get(f)
	_stamp_profile_full()
	for f in overrides:
		set(f, overrides[f])

## Copy every stamped field from the profile onto us -- the authoritative full-clobber path (also the body the
## additive merge runs before restoring overrides). Reached only with profile != null (both callers guard).
## threat_response copies int -> the ThreatResponse enum (NpcData stores it as an int to avoid an NpcData <-> NPC
## class cycle).
## M7: keep this body's `X = profile.X` fields and PROFILE_STAMPED_FIELDS a MATCHED SET — the additive merge iterates
## that array, so a field stamped here but missing from it silently drops the inline override. tests/test_npc_data.gd
## asserts the set-equality BOTH ways.
func _stamp_profile_full() -> void:
	display_name = profile.display_name
	popup_positive = profile.popup_positive
	max_hp = profile.max_hp
	armor_flat = profile.armor_flat            # CT-2 mitigation mirror
	damage_reduction = profile.damage_reduction
	zone_damage_mult = profile.zone_damage_mult
	stats = profile.stats  # archetype stat sheet -> _apply_stats (in super() below) stamps strength
	has_outline = profile.has_outline
	outline_color = profile.outline_color
	outline_width = profile.outline_width
	faction_id = profile.faction_id
	faction = profile.faction
	disposition = profile.disposition
	disposition_overrides_faction = profile.disposition_overrides_faction
	friendly_aggro_threshold = profile.friendly_aggro_threshold
	weapon_data = profile.weapon_data
	muzzle_offset = profile.muzzle_offset
	weapon_mesh_rotation = profile.weapon_mesh_rotation
	rate_of_fire_factor = profile.rate_of_fire_factor
	miss_chance = profile.miss_chance
	fire_range = profile.fire_range
	target_height = profile.target_height
	immune_to_weapon_knockback = profile.immune_to_weapon_knockback
	starts_unloaded = profile.starts_unloaded
	item_stacks = profile.item_stacks
	sight_range = profile.sight_range
	fov_degrees = profile.fov_degrees
	crouch_sight_mult = profile.crouch_sight_mult
	time_to_detect = profile.time_to_detect
	forget_time = profile.forget_time
	pursuit_grace_time = profile.pursuit_grace_time
	eye_height = profile.eye_height
	hearing = profile.hearing
	turn_speed = profile.turn_speed
	search_sweep_rate = profile.search_sweep_rate
	show_laser = profile.show_laser
	move_speed = profile.move_speed
	move_accel = profile.move_accel
	air_accel = profile.air_accel
	engage_range_fraction = profile.engage_range_fraction
	jump_velocity = profile.jump_velocity
	dodge_interval = profile.dodge_interval
	goap_profile = profile.goap_profile
	dodge_chance = profile.dodge_chance
	dodge_duration = profile.dodge_duration
	dodge_speed_fraction = profile.dodge_speed_fraction
	threat_response = profile.threat_response as ThreatResponse
	temperament = profile.temperament
	sitting = profile.sitting
	wanders = profile.wanders
	wander_radius = profile.wander_radius
	wander_dwell_min = profile.wander_dwell_min
	wander_dwell_max = profile.wander_dwell_max
	flee_distance = profile.flee_distance
	talk_approach_distance = profile.talk_approach_distance
	talk_approach_timeout = profile.talk_approach_timeout

## The npc.gd @export defaults for the stamped fields, captured once from a throwaway probe (NPC.new() with no
## _ready -- never added to the tree, freed after) and cached statically. Lets the additive merge detect which
## fields this instance overrode (value != default). Safe off-tree: bare NPC.new() is the standard test pattern.
static func _npc_stamped_defaults() -> Dictionary:
	if _stamped_field_defaults.is_empty():
		var probe := NPC.new()
		for f in PROFILE_STAMPED_FIELDS:
			_stamped_field_defaults[f] = probe.get(f)
		probe.free()
	return _stamped_field_defaults

## Seed the backpack from the assigned weapon_data and DRAW it from the backpack, so a combatant NPC
## fights with an item it actually carries (and therefore drops it on death). If weapon_data isn't a
## registered ItemDb weapon-item, fall back to a direct equip so a custom-weapon NPC still fights (it
## just won't drop a backpack item). Called from _ready's weapon branch, right after _weapon.setup().
## The fallback melee an NPC throws when it has NOTHING equipped — a civilian brawler, or a combatant whose
## weapon was pickpocketed: a weak, short-reach "fists" weapon. Damage / reach / swing cadence are read from
## this WeaponData (tunable), but the hit is applied directly in NpcCombat._punch (no projectile / hitscan rig needed).
const FISTS: WeaponData = preload("res://resources/weapons/fists.tres")

func _equip_initial_weapon() -> void:
	var witem: Item = ItemDb.make_weapon_item(weapon_data)  # a UNIQUE item, so the dropped weapon is its own object
	if witem != null and inventory != null:
		inventory.add(witem)
	# Draw the STRONGEST weapon in the bag: weapon_data only SEEDS the backpack now — if item_stacks
	# carried something better, THAT gets drawn. Falls back to the bare hub equip for a bag-less host.
	var best: Item = inventory.best_weapon_item() if inventory != null else null
	if best != null:
		inventory.equip_item(best)  # -> equip_weapon_requested -> _on_equip_weapon_requested below
	elif _weapon != null and _weapon.inventory != null:
		_weapon.inventory.equip(weapon_data)
	# Stash starting clips FOR THE DRAWN GUN: the NPC fires + reloads from these (it goes dry once they're
	# gone), and a corpse drops whatever's left to loot.
	var drawn: WeaponData = best.weapon if best != null else weapon_data
	if drawn != null and drawn.caliber != &"" and inventory != null:
		var ammo_item := ItemDb.ammo_item_for(drawn.caliber)
		if ammo_item != null:
			inventory.add(ammo_item, GameSettings.npc_ai.starting_clips)

## Seed the NPC's backpack with its authored carried items (item_stacks), ON TOP of the weapon + ammo
## above. Weapons are duplicated to UNIQUE instances (like the loot / pickup pipeline); stackables are added
## as the shared template (add the same item twice for two). Real carried items: pickpocketable + dropped on
## death because the corpse copies the bag. No-op without an inventory (off-tree) or with no carried items.
func _seed_carried_items() -> void:
	if inventory == null:
		return
	ItemStack.seed_into(inventory, item_stacks)  # the easy count-based carried items

## The backpack asked to draw `weapon` (from _equip_initial_weapon now, or a looted weapon later). Hand
## it straight to the NPC's weapon hub — an AI needs no swap animation. Overrides Character's no-op hook.
func _on_equip_weapon_requested(weapon: WeaponData) -> void:
	if _weapon != null and _weapon.inventory != null:
		_weapon.inventory.equip(weapon)
		_build_weapon_mesh()  # show the newly-equipped weapon in hand (e.g. one the player gave a disarmed NPC)

## If disarmed but the backpack now holds a weapon (e.g. the player gave us one via the loot / pickpocket
## transfer), draw it — so a stripped NPC handed a new gun fights with it instead of staying on fists. Only a
## combatant (with a _weapon hub) can actually wield one; a civilian with no hub just marks it and keeps fists.
func _ensure_armed_from_backpack() -> void:
	if is_armed() or inventory == null:
		return
	var best: Item = inventory.best_weapon_item()  # the STRONGEST carried gun, not the first found
	if best != null:
		inventory.equip_item(best)  # -> equip_weapon_requested -> _on_equip_weapon_requested (equip + mesh)

## A combatant wields its gun only while the equipped weapon-item is still in its backpack. Take the weapon out
## of the bag — loot it off the corpse, or an ally gear-exchange — and equipped_item clears (CharacterInventory.remove)
## -> nothing to draw, so it fights unarmed. (A LIVE NPC's HELD weapon can't be pickpocketed — LootScreen locks it;
## steal its ammo to disarm instead.) Civilians (never equipped a weapon item) and disarmed combatants both read
## false. Public — WeaponStance reads it to keep a disarmed NPC's gun holstered/hidden.
func is_armed() -> bool:
	return inventory != null and inventory.equipped_item != null and inventory.equipped_item.is_weapon()

## Whether this NPC has a weapon HUB at all — i.e. it was authored as a COMBATANT (weapon_data set, so
## _ready built the _weapon system). A CIVILIAN (weapon_data null) has no hub and can NEVER wield a gun,
## even one planted in its backpack: the backpack-rearm equip (_on_equip_weapon_requested) no-ops without a
## hub. A DISARMED combatant still returns true — it has a hub, it just isn't holding a weapon item right
## now, and it re-arms from the backpack on its next combat tick. Public: the pickpocket / exchange deposit
## path (LootScreen) reads this to warn the player that arming a hub-less civilian is futile.
func can_wield_weapons() -> bool:
	return _weapon != null

## Whether the NPC can fight WITH its gun right now: it's actually wielded (is_armed) AND there's ammo to
## fire this instant or a spare clip to reload. Steal all its ammo (the held weapon itself can't be lifted while
## wielded — LootScreen), or take the weapon off its corpse, and this goes false,
## dropping it to the unarmed AI (squares up + closes, but can't shoot). _weapon is non-null whenever
## is_armed is true (only a combatant ever equips a weapon item), but it's guarded regardless.
func _can_fight_with_gun() -> bool:
	if not is_armed() or _weapon == null:
		return false
	if _weapon.current_ammo > 0:
		return true
	return _weapon.ammo != null and _weapon.ammo.has_reload_supply()

## Ranged-only warning package: charge sting, incoming beep, aim radial, and sniper glint. Melee/fists are
## still valid WeaponData attacks, but they should read like close-range swings rather than aimed shots.
static func _weapon_uses_ranged_attack_telegraphs(w: WeaponData) -> bool:
	if w == null or w.is_spray_paint:
		return false
	var melee_style := w.is_infinite_ammo and w.caliber == &"" \
			and w.projectile_scene == null and not w.has_tracer
	return not melee_style

func _current_weapon_uses_ranged_attack_telegraphs() -> bool:
	var w: WeaponData = _weapon.equipped_weapon if _weapon != null else null
	return _weapon_uses_ranged_attack_telegraphs(w)

func _current_weapon_has_laser_sight() -> bool:
	var w: WeaponData = _weapon.equipped_weapon if _weapon != null else null
	return w != null and w.has_laser_sight

## Build the code-built behaviour children carried by EVERY NPC and wire each one's host ref right after
## .new() (the canonical state stays here; the children read it). The combatant-only children (laser +
## weapon stance) are built in _ready's weapon branch instead. Mirrors the existing _build_perception /
## _build_nav idiom. These exist only on an in-tree NPC — an off-tree unit-test NPC (.new() with no
## add_child) never runs _ready, so every facade below null-guards its child.
func _build_components() -> void:
	_outline = NpcOutline.new()
	_outline.host = self
	add_child(_outline)
	_audio_cues = NpcAudioCues.new()
	_audio_cues.host = self
	add_child(_audio_cues)
	_talk = TalkApproach.new()
	_talk.host = self
	add_child(_talk)
	_ensure_pickpocket_talkable()
	_follow = CompanionFollow.new()
	_follow.host = self
	add_child(_follow)
	_voice = NpcVoice.new()  # bark / social-voice orchestration (npc_voice.gd); reaches back into us for data
	_voice.host = self
	add_child(_voice)
	if profile != null:
		if profile.bark_set != null:
			_voice._bark_set = profile.bark_set
		_voice.damage_barks_enabled = profile.damage_barks  # designer bark gates (default true = unchanged)
		_voice.death_barks_enabled = profile.death_barks
		_voice.search_barks_enabled = profile.search_barks
	_bark_ui = NpcBarkUi.new()  # head-popup presentation: bark bubble + "!" / cue icons (npc_bark_ui.gd)
	_bark_ui.host = self
	add_child(_bark_ui)
	_targeting = NpcTargeting.new()  # target acquisition (npc_targeting.gd); binds the chosen target via _set_target
	_targeting.host = self
	add_child(_targeting)
	_locomotion = NpcLocomotion.new()  # non-combat movement: idle / wander / flee (npc_locomotion.gd)
	_locomotion.host = self
	add_child(_locomotion)
	_scavenge = NpcScavenge.new()  # container raiding: grab a better/first weapon from a nearby crate
	_scavenge.host = self
	add_child(_scavenge)
	_combat = NpcCombat.new()  # firing dispatch: armed/unarmed attack bodies + combat dodge (npc_combat.gd); drives _act_alerted/_act_unarmed
	_combat.host = self
	add_child(_combat)
	# Movement FEEDBACK like the player -- footstep SFX while walking + a landing thud/dust on touchdown. Auto-built
	# unless a configured LocomotionFx was already dropped under this NPC in the scene (then we leave that one to it).
	var has_loco_fx := false
	for c in get_children():
		if c is LocomotionFx:
			has_loco_fx = true
			break
	if not has_loco_fx:
		add_child(LocomotionFx.new())
	# React-to-own-HP drop-ins (self_healer.gd / panic_on_damage.gd). Same self-build idiom as LocomotionFx: a
	# CONFIGURED instance dropped in the scene wins; otherwise auto-add one SEEDED from today's globals so every
	# existing NPC heals / panics EXACTLY as before. The NPC calls react() on each child from _on_damaged_by.
	for c in get_children():
		if c is SelfHealer:
			_self_healer = c as SelfHealer
		elif c is PanicOnDamage:
			_panic = c as PanicOnDamage
		elif c is ProvokeOnAttack:
			_provoke_on_attack = c as ProvokeOnAttack
	if _self_healer == null:
		var sh := SelfHealer.new()
		sh.heal_at_hp_frac = GameSettings.npc_ai.medkit_hp_frac  # seed from the global medkit tuning -> unchanged behaviour
		sh.cooldown_ms = GameSettings.npc_ai.medkit_cooldown_ms
		add_child(sh)
		_self_healer = sh
	if _panic == null:
		var p := PanicOnDamage.new()
		p.panic_scale = temperament  # `temperament` stays the authored fear source; it seeds the auto-added component
		add_child(p)
		_panic = p
	if _provoke_on_attack == null:
		var pa := ProvokeOnAttack.new()  # default enabled -> the inlined provoke/forgiveness behaviour, unchanged
		add_child(pa)
		_provoke_on_attack = pa
	# Cripple callouts (the "Crippled X's arm" player toast + the NPC's own "My arm!" bark) — a portable Type-1
	# react() drop-in, auto-added like the ones above so behaviour is unchanged; drop a configured CrippleCallout
	# under the NPC to retint the toast or disable it. Matched + built by SCRIPT PATH (never `is CrippleCallout`
	# or `.new()` on the bare type) so this @tool root doesn't name the new class_name at parse time — a bare-type
	# ref to a not-yet-reimported class can fail npc.gd's parse in the live editor (new-classname cascade).
	var cripple_script := "res://scripts/components/cripple_callout.gd"
	for c in get_children():
		var cs: Variant = c.get_script()
		if cs != null and cs.resource_path == cripple_script:
			_cripple_callout = c
			break
	if _cripple_callout == null:
		_cripple_callout = load(cripple_script).new()
		add_child(_cripple_callout)
	# The "go home" leash: back to our authored post when the player dies, or after we've been off-screen a while
	# (the dog / companion hidden-blink trick, aimed at our spawn spot instead of at the player). Matched + built by
	# SCRIPT PATH — never `is NpcHomeReturn` or a bare-type `.new()` — for the same reason as CrippleCallout above:
	# a bare-type reference to a not-yet-reimported class can fail this @tool root's parse in the live editor. A
	# CONFIGURED NpcHomeReturn dropped under the NPC in the scene WINS (we only bind its host); otherwise one is
	# auto-added and seeded from GameSettings.npc_ai so the whole cast shares the global leash tuning.
	var home_script := "res://scripts/npc/npc_home_return.gd"
	for c in get_children():
		var hrs: Variant = c.get_script()
		if hrs != null and hrs.resource_path == home_script:
			_home_return = c
			break
	if _home_return == null:
		var hr: Node = load(home_script).new()
		hr.enabled = GameSettings.npc_ai.home_return
		hr.return_on_player_death = GameSettings.npc_ai.home_return_on_player_death
		hr.death_return_delay = GameSettings.npc_ai.home_return_death_delay
		hr.return_when_off_screen = GameSettings.npc_ai.home_return_off_screen
		hr.off_screen_delay = GameSettings.npc_ai.home_return_off_screen_delay
		hr.off_screen_requires_calm = GameSettings.npc_ai.home_return_requires_calm
		hr.home_slack = GameSettings.npc_ai.home_return_slack
		hr.blink_home = GameSettings.npc_ai.home_return_blink
		hr.min_blink_distance = GameSettings.npc_ai.home_return_min_blink_distance
		add_child(hr)
		_home_return = hr
	_home_return.host = self
	# Combat-noise drop-in: pulses our gunfire / death onto the shared &"noise" channel (GA-2) so listening allies
	# can hear the firefight. Host-agnostic (reads get_parent()); we just seed its fade/lifetime/throttle from our
	# noise exports and hand it a radius per pulse. Inert until GameSettings.npc_ai.hearing_initiates opts a listener in.
	_noise_pulser = NoisePulser.new()
	_noise_pulser.decay = combat_noise_decay
	_noise_pulser.lifetime = combat_noise_lifetime
	_noise_pulser.min_interval = combat_noise_interval  # the throttle now lives on the pulser
	add_child(_noise_pulser)
	# Death world-spawns: the lootable corpse + stealth body marker + kill-XP that _on_died calls in order (via the
	# thin _drop_loot / _award_kill_xp / _spawn_corpse_marker facades). Host-coupled internal helper (Node-typed).
	_mortality = NpcMortality.new()
	_mortality.host = self
	add_child(_mortality)
	# No-target environmental scans (loudest noise / nearest radio / visible corpse). Pure queries the stateful
	# reactions (_react_unaware / _react_music) call via the _loudest_noise / _nearest_audible_radio /
	# _nearest_visible_corpse facades. Host-coupled internal helper (Node-typed).
	_senses = NpcSenses.new()
	_senses.host = self
	add_child(_senses)
	# The GOAP brain — drives every NPC's AI as the sole decision layer. Plain
	# RefCounted, not a child Node. See _build_goap_actions/_goals for the library it plans over.
	_executor = GoapExecutor.new()
	_executor.setup(_build_goap_actions(), _build_goap_goals())
	# Spawn-time validation: a code-built profile is never scanned by the content validator, and an unknown
	# goals[]/override name silently narrows or ignores behaviour. validate() push_warns per offender; add the
	# NPC name so a bad archetype is traceable in play. Runtime-only path (_ready early-returns in the editor).
	if goap_profile != null and not goap_profile.validate(GoapLibrary.goal_names(), GoapLibrary.action_names()):
		push_warning("NPC '%s': goap_profile names an unknown goal/action (see warnings above) — that entry is ignored." % name)

## Pickpocketing rides the same look-at handler as talking. Authored Talkables win (dialogue NPCs keep their
## conversation component), but a plain hostile NPC still needs a hitbox so crouch-interact can reach can_pickpocket.
func _ensure_pickpocket_talkable() -> void:
	if _has_talkable_child():
		return
	var t := Talkable.new()
	t.name = PICKPOCKET_TALKABLE_NAME
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = PICKPOCKET_TALKABLE_SIZE
	shape.shape = box
	t.add_child(shape)
	add_child(t)

func _has_talkable_child() -> bool:
	for c in get_children():
		if c is Talkable:
			return true
	return false

## The GOAP action + goal libraries the executor plans over — facades onto GoapLibrary.build_* (which owns the full
## vocabulary + design rationale + its name registries in ONE file so they can't drift). Kept as methods (not inlined
## at the _executor.setup call) because test_npc_goap_library.gd builds the library off a bare NPC through these to
## drift-check GoapLibrary's name lists. They pass this NPC's goap_profile, which retunes costs / priorities / the goal
## allow-list.
func _build_goap_actions() -> Array:
	return GoapLibrary.build_actions(goap_profile)

func _build_goap_goals() -> Array:
	return GoapLibrary.build_goals(goap_profile)

## Build the initial combat outline rim — facade onto the NpcOutline child. No-op off-tree (no child),
## exactly as the monolith no-op'd when _flash_material was null (the off-tree super() never built it).
func _setup_outline() -> void:
	if _outline != null:
		_outline.setup()

## Rebuild the outline rim from the CURRENT _outline_color_for_disposition() — facade onto the NpcOutline
## child. Called on provoke / forgive / follow-toggle and on a rep-driven attitude change (the poll). The
## child guards has_outline + _flash_material internally; null off-tree -> no-op (behaviour-preserving).
func _apply_outline() -> void:
	if _outline != null:
		_outline.apply()

## Resolve this NPC's CURRENT attitude toward the player from its state (provoked > faction-rep >
## standalone disposition) — facade onto HostilityHelpers, which owns the pure resolution. The STATE
## (_provoked, faction, disposition) stays here; we just hand it down.
func resolved_disposition() -> Disposition.Kind:
	return HostilityHelpers.resolved_kind(_provoked, faction, disposition, disposition_overrides_faction)

## True when this NPC currently treats the player as an enemy. The combat AI (this NPC's own
## Perception loop) gates ALL hostile behaviour — detect, aim, fire — on this. A non-hostile NPC
## keeps gravity / idle / wander but never engages the player until provoked.
func is_hostile() -> bool:
	return resolved_disposition() == Disposition.Kind.HOSTILE

## True when this NPC is HOSTILE BY DESIGN -- its authored attitude (faction-rep or standalone disposition)
## resolves to HOSTILE on its own, IGNORING runtime provoke. A pre-disposed enemy keeps its gun OUT at all times
## (WeaponStance never stands it down), unlike a neutral/friendly armed NPC that holsters between fights; a
## townsperson that merely got provoked is NOT pre-disposed, so it still holsters. Off-tree-safe (pure reads + the
## static resolver + the Reputation autoload).
func is_predisposed_hostile() -> bool:
	return HostilityHelpers.resolved_kind(false, faction, disposition, disposition_overrides_faction) == Disposition.Kind.HOSTILE

## The outline rim colour for this NPC right now. A recruited COMPANION (following) wears BLUE, which
## OVERRIDES the disposition colour (Feature I) so it reads as "mine" at a glance. Otherwise it's keyed to
## resolved_disposition(): HOSTILE -> red, FRIENDLY -> green, NEUTRAL -> the `outline_color` export (black).
func _outline_color_for_disposition() -> Color:
	if is_following():
		return OUTLINE_FOLLOWING  # blue companion rim overrides the disposition tint while escorting
	match resolved_disposition():
		Disposition.Kind.HOSTILE:
			return CBPalette.hostile()
		Disposition.Kind.FRIENDLY:
			return CBPalette.friendly()
		_:
			return outline_color  # NEUTRAL — the export (black by default)

## True when this NPC currently treats `other` as an enemy. Two cases:
##   - other is the PLAYER ("Player" group): defer to today's is_hostile() (provoke + faction-rep
##     + standalone disposition). Player targeting is unchanged.
##   - other is another NPC: a personal grudge (it damaged us, tracked in `_npc_grudges`) makes us hostile
##     regardless of faction; otherwise BOTH must be factioned and this faction's relation to the other's
##     faction must be < 0 (FNV-style "<0 = enemies"). Absent a grudge, unaligned NPCs never fight other NPCs;
##     a provoked NPC still only sours toward the PLAYER (provoke drops player-rep), not peers.
## Self / null / non-NPC-non-player nodes are never hostile.
func is_hostile_to(other: Node) -> bool:
	if other == null or other == self or not is_instance_valid(other):
		return false
	if other.is_in_group(Groups.PLAYER):
		return is_hostile()
	var other_npc := other as NPC
	if other_npc == null:
		return false
	if other_npc in _npc_grudges:
		return true  # personal grudge: it damaged us, so we fight it regardless of faction relation
	return HostilityHelpers.npc_vs_npc_hostile(faction, other_npc.faction)

## Aggro this NPC: become hostile NOW, and — if factioned — drop the player's reputation with that
## faction so the whole faction sours (FNV-style). Idempotent; safe to call every hit. `attacker`
## is accepted so the damage hook can also turn us toward the source. `apply_rep` is false for a
## FACTION-WIDE aggro (e.g. an AlarmPanel) that applies the faction penalty ONCE itself — so flipping
## every member hostile doesn't multiply the reputation hit by the squad size (GA-3).
func provoke(_attacker: Node = null, apply_rep: bool = true) -> void:
	if not _provoked:
		_provoked = true
		if apply_rep and faction != null:
			var provoke_penalty: float = GameSettings.reputation.provoke_penalty
			# Capture the ACTUALLY-applied delta (add_reputation returns the new total, and streetwise
			# scaling + the [rep_min,rep_max] clamp can make it differ from -provoke_penalty), so
			# forgive_provoke() can reverse EXACTLY this hit and truly de-escalate the faction.
			var before := Reputation.get_reputation(faction)
			_provoke_rep_delta = Reputation.add_reputation(faction, -provoke_penalty) - before
		_apply_outline()  # now hostile — recolour the rim to red immediately
		_popup_icon(POPUP_NEGATIVE, false, -0.75)  # chest level, clear of the "!" alert at the head (no stacking)

## True while a holster de-escalation can still pardon this NPC's provoke — the single gate behind forgive_provoke()
## AND both tutorial hooks, so the lesson is never taught for a pardon that would be refused.
##
## MERCY EXEMPTION (GameSettings.npc_ai.fleeing_always_forgivable, default on): a FLEEING NPC is ALWAYS forgivable,
## spent latch or not. The betrayal one-shot exists to close the free-kill farm of spam-holstering a mob that keeps
## SHOOTING BACK — but a fleer never fires (GoapActionFireArmed/Unarmed are mirror-gated on `not is_fleeing()`), so
## refusing its stand-down buys no balance. It only leaves a terrified civilian, or a fighter PanicOnDamage broke
## mid-fight, sprinting from the player forever with no way to call it off. Note is_fleeing() is a one-way runtime
## flip (break_and_flee sets FLEE and nothing sets it back within a life), so this can't flicker on a live fighter.
func _holster_forgiveness_available() -> bool:
	if is_fleeing() and GameSettings.npc_ai.fleeing_always_forgivable:
		return true
	return not (_holster_forgiveness_spent and GameSettings.npc_ai.holster_forgiveness_once)

## Art for the SUCCESSFUL-pardon "+friend" cue: this NPC's authored popup_positive when a designer set one (so a
## special NPC's custom friend art reads the same at both "+friend" moments — rescue and pardon), else the shipped
## POPUP_POSITIVE. NEVER null, unlike the rescue cue: leaving popup_positive empty opts out of the RESCUE popup
## only, because de-escalation feedback that silently vanishes makes holstering look broken.
func _pardon_popup_texture() -> Texture2D:
	var authored := popup_positive as Texture2D
	return authored if authored != null else POPUP_POSITIVE

func show_holster_forgiveness_tutorial_for_attack(attacker: Node) -> void:
	if not _provoked or not _holster_forgiveness_available():
		return
	if attacker == null or not attacker.has_method(&"show_holster_forgiveness_tutorial"):
		return
	_holster_forgiveness_tutorial_active = true
	attacker.call(&"show_holster_forgiveness_tutorial", false)

func should_remind_holster_forgiveness_tutorial_on_player_death() -> bool:
	return _provoked and _holster_forgiveness_tutorial_active and _holster_forgiveness_available()

## FNV-style forgiveness: the player holstered their weapon, so if WE were provoked (a non-hostile NPC
## the player attacked) we drop the grudge — clear the provoke, RESTORE the exact faction rep the provoke
## dropped (so the whole faction re-reads above threshold and stands down), revert the rim to our real
## disposition, and let go of the player as a target. Genuinely-hostile NPCs (never provoked): no-op.
## Only a PROVOKE is forgiven — KILL penalties are never reversed here, so a faction soured by kills
## (not just a provoke) stays hostile.
##
## The pardon is ONE-SHOT per life (GameSettings.npc_ai.holster_forgiveness_once, default on): after we've
## stood down once, RE-ATTACKING us (which re-provokes via ProvokeOnAttack.react) makes the hostility
## PERMANENT — a second holster is refused and flashes our aggro cue instead of pacifying us. That closes the
## free-kill farm of spamming the holster toggle to keep resetting a mob you keep shooting. The ONE exception is
## a FLEEING NPC, which is always forgivable no matter how many pardons it has spent (fleeing_always_forgivable):
## it isn't shooting back, so there's nothing to farm — see _holster_forgiveness_available().
func forgive_provoke() -> void:
	if not _provoked:
		return
	# BETRAYAL one-shot: we already stood down once and the player shot us again, so we won't fall for the holster
	# a second time. Flash the aggro icon (same cue as provoke) so the refusal reads as intentional, not a bug —
	# the gun going away while we keep firing would otherwise look like holstering broke. Sits ON TOP of the
	# _provoked guard above, so a never-provoked (genuinely-hostile) NPC never reaches or sets the latch.
	if not _holster_forgiveness_available():
		_popup_icon(POPUP_NEGATIVE, false, -0.75)  # "won't fall for it twice" — chest level, matches provoke's aggro cue
		return
	_holster_forgiveness_spent = true
	_clear_provoke()
	# The pardon LANDED: pop the "+friend" cue at the same chest level (and same follow=false lifetime) the
	# provoke / refusal cues use, so "they stood down" reads as unmistakably as "they turned on you" — the two
	# outcomes of holstering are now symmetrical instead of only failure being telegraphed.
	_popup_icon(_pardon_popup_texture(), false, -0.75)
	# ...and say it out loud, so the pardon has a voice the way the provoke does (bark_aggro). A pardon that lands
	# while we're RUNNING gets its own alternative pool — that's the fleeing_always_forgivable case, and "you put
	# the gun away" reads completely differently mid-sprint. is_fleeing() is still accurate here: nothing on this
	# path touches threat_response (the panic flip is one-way within a life). Deliberately NOT in _clear_provoke —
	# the player-death settlement below is not the player talking anyone down, so it stays silent.
	if _voice != null:
		_voice.bark_pardon(_pardon_lines(is_fleeing()))

## The shared BODY of every stand-down path (the holster pardon above and the player-death settlement below):
## drop the provoked flag, RESTORE the exact faction rep the provoke took, revert the rim to our real
## disposition, and let go of the player as a target. Each caller owns the parts that DIFFER — its own
## eligibility gate, whether the betrayal one-shot is spent, and which popup cue (if any) plays. Assumes
## _provoked is already true (both callers guard on it), so it never touches a never-provoked NPC.
func _clear_provoke() -> void:
	_provoked = false
	_holster_forgiveness_tutorial_active = false
	# Undo the exact rep the provoke removed. adjust_unscaled (not add_reputation) so streetwise scaling
	# isn't re-applied to an already-scaled delta. Faction-wide + multi-member safe: the shared pool
	# restores, and each provoked member reverses only its own clamp-aware delta (the sum round-trips).
	if faction != null and _provoke_rep_delta != 0.0:
		Reputation.adjust_unscaled(faction, -_provoke_rep_delta)
	_provoke_rep_delta = 0.0
	_apply_outline()  # rim back to the (non-hostile) disposition colour
	# Drop the player if it was our target so we disengage; the AI re-scans and finds no hostile now.
	if is_instance_valid(_target) and _target.is_in_group(Groups.PLAYER):
		_set_target(null)
		_last_attacker = null
		_hide_laser()

## THE PLAYER DIED and a hostile NPC put them there, so a grudge that exists ONLY because they provoked us is
## SETTLED — we got even, drop it. Runs on their RESPAWN, not at the moment of death (Player banks the verdict in
## _on_killed_by and spends it in _settle_provoked_grudges), so the world calms down where the player can watch it.
## Same de-escalation as a holster pardon (_clear_provoke), with two deliberate differences:
##   * NO "+friend" popup. The pardon's cue answers a button the player just pressed, at one NPC they are looking
##     at. This is a group-wide sweep the instant they respawn — potentially dozens of world-space pops scattered
##     across a level they were just teleported away from. The single restored-standing toast the rep reversal
##     pushes onto the revived HUD is the readable feedback instead.
##   * The betrayal one-shot is NOT spent — dying isn't the player talking us down, so it must not burn the holster
##     pardon they may still need on the next life.
## Returns true only if we actually stood down (we were provoked), so the sweep can count. A genuinely/predisposed-
## hostile NPC was never provoked -> no-op, it keeps hunting. Called by HostilityHelpers.settle_provoked_grudges;
## the RULE (killer + toggle gates) is decided at death by HostilityHelpers.death_settles_grudges, so calling this
## directly de-escalates regardless of either gate.
func stand_down_on_player_death() -> bool:
	if not _provoked:
		return false
	_clear_provoke()
	return true

## True while this NPC will still let the player attempt a pickpocket — false once the player was CAUGHT stealing
## from it (react_to_caught_theft latches _pickpocket_caught). ANDed into the Talkable pickpocket gate, so a blown
## steal shuts this mark's pockets permanently (a caught NPC that later calms down is still off-limits). A fresh
## scene reload clears it (runtime-only, like _provoked).
func pickpocket_allowed() -> bool:
	return not _pickpocket_caught

## Latch the one-strike pickpocket lockout (see pickpocket_allowed). Public so a caller that can't reach
## react_to_caught_theft (a non-standard steal path / test) can still close this mark's pockets.
func mark_pickpocket_caught() -> void:
	_pickpocket_caught = true

## PICKPOCKET BLOWN — the player was caught with a hand in this NPC's pockets (LootScreen._on_pickpocket_caught).
## React: latch the one-strike lockout, then SNAP TO FACE the thief and engage (set them as our target + force
## Perception to ALERTED at their spot — the same turn-toward-the-source beat as taking a hit from them), so the
## victim visibly spins around instead of just silently souring. Finally rally WITNESSES: every OTHER living enemy
## (a nearby NPC already hostile to the player) within `witness_radius` turns to LOOK — investigate the thief's
## position with the "!" sting. The hostility FLIP itself is provoke() (called alongside in the caught handler);
## this owns the turn-to-face + the room's reaction. `witness_radius` <= 0 => only the victim reacts.
func react_to_caught_theft(thief: Node3D, witness_radius: float) -> void:
	mark_pickpocket_caught()
	var spot := thief.global_position if is_instance_valid(thief) else global_position
	# Turn toward + lock onto the thief (only once provoke() has made us hostile to them, so is_hostile_to reads
	# true), then alert_to spins us around and holds full awareness at their spot until we re-see or forget them.
	# _last_attacker pins the thief as the STICKY lock (mirrors _on_damaged_by): without it the next throttled
	# retarget scan could drift to a closer hostile — e.g. an NPC we were already fighting — and abandon the thief.
	if is_instance_valid(thief) and is_hostile_to(thief):
		_last_attacker = thief
		_set_target(thief)
	if _perception != null:
		_perception.alert_to(spot)
	if witness_radius <= 0.0 or not is_inside_tree():
		return
	# Only ENEMIES (NPCs already hostile to the player) turn to look — a caught thief draws the guards' eyes, not
	# every neutral bystander. investigate() is a no-op on one already DETECTING/ALERTED, so an engaged enemy isn't
	# disturbed. Radius-only (no LOS gate) — same as how a heard-noise investigation spreads.
	for n in get_tree().get_nodes_in_group(Groups.NPC):
		var other := n as NPC
		if other == null or other == self or other._dead or other.hp <= 0.0:
			continue
		if not other.is_hostile():
			continue
		if global_position.distance_to(other.global_position) <= witness_radius:
			other.investigate(spot, true)  # turn toward + come check the commotion (alerting: shows the "!")

## Taking a hit: (1) a PLAYER hit on a non-hostile NPC provokes it (flip hostile + drop faction rep);
## (2) turn toward the source so a shot in the back spins us around — no free backstabs. Wired from
## Character.take_damage. We only PROVOKE off the player (so an enemy's stray friendly-fire doesn't
## flip a neutral against the player), but we turn toward ANY localizable attacker. Overrides
## Character._on_damaged_by (a no-op there).
func _on_damaged_by(attacker: Node, _was_crit: bool = false, amount: float = 0.0) -> void:
	if attacker != null and attacker.is_in_group(Groups.PLAYER) and not (attacker is NPC):
		_hit_by_player = true  # remember the player hurt us (for the assist "thanks" on death)
	# Rescue reward: if the PLAYER just landed our killing blow while we were attacking ANOTHER NPC, the
	# player saved that NPC — credit reputation with the saved NPC's faction + pop a "+friend" cue.
	if hp <= 0.0 and not _save_rewarded and attacker != null and attacker.is_in_group(Groups.PLAYER) \
			and is_instance_valid(_target) and _target is NPC:
		_save_rewarded = true
		var saved := _target as NPC
		if saved.faction != null:
			Reputation.add_reputation(saved.faction, GameSettings.economy.save_rep_reward)
		saved._popup_icon(popup_positive)  # cue floats over the RESCUED NPC (the one we swayed), not our corpse
	# Player-attack provoke / friendly-forgiveness — the ProvokeOnAttack drop-in owns the hostility decision
	# (a NEUTRAL flips on the first player hit; a FRIENDLY forgives until friendly_aggro_threshold, then aggros
	# + stops following). Auto-built + enabled by default, so this is the old inline behaviour unchanged; set
	# its `enabled = false` for an NPC that never turns hostile from being hit.
	if _provoke_on_attack != null:
		_provoke_on_attack.react(self, attacker, amount)
	# NPC-vs-NPC retaliation: an NPC peer that DAMAGED us — one we don't already fight and aren't allied with
	# (a NEUTRAL relationship) — earns a personal grudge: we turn hostile to THAT attacker (not its whole
	# faction), so a neutral caught in crossfire rounds on whoever shot it. is_hostile_to honours the grudge,
	# so the target-lock below then engages it; allies are spared so a squad doesn't infight on stray splash.
	var atk_npc := attacker as NPC
	if atk_npc != null and atk_npc != self and not is_hostile_to(atk_npc) and not _is_ally_of(atk_npc):
		_npc_grudges.append(atk_npc)
	# Focus whoever just hit us (once we're hostile to them): lock them as the target NOW so a closer
	# bystander can't steal our attention. _acquire_target keeps favouring this attacker on its
	# throttled re-scans until it dies, flees out of sight_range, or stops being hostile.
	var atk := attacker as Node3D
	if is_instance_valid(atk) and is_hostile_to(atk):
		_last_attacker = atk
		_set_target(atk)
	if not _perception:
		return
	# Turn toward the source so a hit from any angle spins us around; fall back to the current
	# target's aim point for a hit we can't localize (preserving the old turn-toward-shooter behaviour).
	if is_instance_valid(atk):
		_perception.alert_to(atk.global_position)
	elif is_instance_valid(_target):
		_perception.alert_to(_aim_point())
	# Wounded-ally cry: a following ally that drops to/below HURT_BARK_HP_FRAC of its HP calls out, once.
	if is_following() and not _hurt_bark_said and hp > 0.0 and hp <= max_hp * GameSettings.npc_bark.hurt_bark_hp_frac:
		_hurt_bark_said = true
		_cry_wounded()
	elif hp > 0.0 and is_instance_valid(atk) and is_hostile_to(atk):
		_cry_wounded()
	# Hurt: the react-to-own-HP drop-ins handle the response. SelfHealer spends a carried medkit FIRST, then
	# PanicOnDamage may break + flee -- its fear roll reads the POST-heal HP, the same order the inlined code
	# ran in. Both are seeded to the old globals / `temperament` on auto-build, so default NPCs behave
	# identically; either can be retuned or disabled per-NPC by dropping a configured instance in the scene.
	if _self_healer != null:
		_self_healer.react(self)
	if _panic != null:
		_panic.react(self)

## No-op hit handler kept so the scene's `damaged -> _on_damaged` connection resolves. The hit
## freeze-frame rides the weapon's hitstop + the Damage child node; the aggro/turn-toward-shooter
## logic lives in _on_damaged_by (which gets the attacker identity take_damage passes).
func _on_damaged(_current_hp: float, _max_hp: float) -> void:
	pass

## The "underwater car door" felt-impact thud is the PLAYER's first-person hit feedback (2D, in your
## ear) — an NPC has its own positional Damage SFX and should never play it. Character gates the thud on
## the &"Player" group, which a recruited companion JOINS for enemy targeting (Feature #3); overriding it
## to a no-op here keeps that group membership "targeting only" so an ally taking a hit can't trigger the
## player's thud. Behaviour-preserving for every other NPC (none were ever in the Player group before).
func _play_damage_thud() -> void:
	pass

## Gunfire noise (GA-2), THROTTLED so a full-auto burst emits a steady pulse instead of a NoiseSource per bullet.
## Called right after the NPC pulls the trigger (npc_combat.gd). Thin facade onto the NoisePulser drop-in, which
## owns the spawn + throttle + the hearing_initiates inert-gate; no-ops off-tree (no _noise_pulser until _ready).
func _emit_gunfire_noise() -> void:
	if _noise_pulser != null:
		_noise_pulser.pulse(gunfire_noise_radius, true)  # throttled: fold rapid shots into one pulse

# --- WorldSnapshot exact-save tier (manual quicksave/slots) --------------------------------------------------
## POSITION-INDEPENDENT identity for the snapshot: an authored `save_id` is the whole key ("id:<x>"); else
## level|node_path. Deliberately NOT WorldSaveId.key_for — that folds the live POSITION into the fallback key, but
## an NPC MOVES, so a position-keyed capture (taken after it wandered / at its death spot) would never match the
## reloaded node sitting at its authored .tscn transform. node_path is what survives a same-scene reload (the
## PackedScene re-instantiates identical names); it also stays identical between our death (died.emit, in-tree) and
## the reload, so a dead NPC's recorded key matches the fresh spawn that must be suppressed.
func snapshot_key() -> String:
	if save_id != &"":
		return "id:%s" % String(save_id)
	var np: String = str(get_path()) if is_inside_tree() else String(name)
	return "%s|%s" % [GameState.current_level_path, np]

## Re-apply a WorldSnapshot's captured transform + hp onto this freshly-reloaded authored NPC (called by the
## GameRoot post-load push, deferred so our _ready has already seeded hp = max_hp and the wander anchor). Rewrites
## _spawn_position/_spawn_yaw too — the wander behaviour recenters on them, so without this it would drift us back
## to the authored spot.
func restore_snapshot_state(pos: Vector3, yaw: float, restored_hp: float) -> void:
	global_position = pos
	rotation.y = yaw
	hp = restored_hp
	_spawn_position = pos
	_spawn_yaw = yaw

## `died`-signal handler (connected in _ready): stamp our snapshot_key into GameState's live per-level death ledger.
## Runs during die() -> died.emit(), BEFORE queue_free(), so we're still in-tree and the key resolves. Bound method
## (not a lambda) per the freed-capture rule; is_inside_tree guard covers the off-tree edge.
func _record_snapshot_death() -> void:
	if not is_inside_tree():
		return
	if _pool != null or _dynamic_spawn:
		return  # a spawner-produced encounter NPC (pooled OR pool-less) is a DYNAMIC actor (excluded from the exact-save
		# tier); recording its ephemeral @-node_path as permanently dead would pollute the ledger and, on a re-spawn at
		# the same @path, suppress a legit enemy. Only authored (.tscn-placed) NPCs reach record_npc_death.
	GameState.record_npc_death(GameState.current_level_path, snapshot_key())

func _on_died() -> void:
	if _noise_pulser != null:
		_noise_pulser.pulse(death_noise_radius, false)  # a one-off death cry/thud allies can hear — never throttled
	if is_in_group(Groups.PLAYER):
		remove_from_group(Groups.PLAYER)
	# Cut our bark if it's OURS that's currently playing (SpeechTts guards on the source, so this never
	# silences another NPC's shout). Dialogue is a SEPARATE TTS player, ended by DialogueManager when its
	# speaker dies, so there's nothing to stop here for it.
	SpeechTts.stop_bark_from(self)
	# Assist thanks: if the player helped kill us while we were fighting another, non-hostile NPC, that
	# NPC thanks the player ("Hey, thanks!"). Covers both "player landed the kill" and "ally killed it,
	# player chipped in" (via _hit_by_player).
	if _hit_by_player and is_instance_valid(_target) and _target is NPC and not (_target as NPC).is_hostile():
		(_target as NPC).thank_for_assist()
	# Death-witness reactions: nearby NPCs comment when the PLAYER kills this one (a co-aligned peer cries
	# "Murderer!"). Gated on _hit_by_player so enemy infighting / environmental deaths stay quiet.
	if _hit_by_player:
		# Slice 6b: a SILENT takedown suppresses ONLY the audible witness bark (the "Murderer!" alert) — the kill
		# still credits the kill-quest / XP / faction rep below, and the Slice 5 corpse marker (outside this gate)
		# becomes the DELAYED cost. Without this, a "silent" takedown would loudly alert every witness in radius.
		if not _silent_death:
			_announce_death_to_witnesses()
		# Advance any KILL quest objective: keyed by the STABLE identity (Slice 3 — survives a claimed pet's runtime
		# rename and a display_name edit/localization), with the live display string passed as the legacy fallback so
		# already-authored quests targeting a display name (clear_the_block's &"Raider") keep matching unedited.
		GameState.notify_kill(identity_key(), StringName(display_name))
		_award_kill_xp()  # rank 29: a player kill grants XP (GameSettings.xp.xp_per_kill)
		# Killing a faction member sours the player's standing with that faction — even a hostile one
		# (you're still putting their people down). Unaligned NPCs (no faction) have no standing to lose; a
		# profile can opt out (sours_faction_on_death = false) for a "free kill" target. See death_sours_faction.
		if death_sours_faction():
			var kill_penalty: float = GameSettings.reputation.kill_penalty
			Reputation.add_reputation(faction, -kill_penalty)
	# Leave a lootable corpse holding our backpack, while it still exists (queue_free is deferred).
	_drop_loot()
	# Stealth body-discovery: drop a discoverable Corpse marker at the death spot so a nearby UNAWARE NPC that
	# SEES it gets spooked (investigates + calls out). Off by default — a quiet kill is free until the designer
	# flips GameSettings.npc_ai.body_discovery. Outside the _hit_by_player gate: ANY death (a stealth takedown
	# leaves no "hit by player" trail, yet its body must still be findable).
	_spawn_corpse_marker()
	# The kill-beat hitstop — a profile can opt out (pause_on_kill = false) for a trash-mob / swarm enemy
	# so the screen doesn't hitch on every kill; profile-less NPCs keep the pause. See death_pauses_game.
	if death_pauses_game():
		FreezeFrame.pause_briefly(0.015)

## Whether a PLAYER kill of this NPC sours its faction's reputation (the kill_penalty drop in _on_died): only
## a factioned NPC has standing to lose, and a profile can opt out (sours_faction_on_death = false) for a "free
## kill" target. Profile-less NPCs sour as before. Pure (no tree), so a unit test pins the profile/faction combos.
func death_sours_faction() -> bool:
	return faction != null and (profile == null or profile.sours_faction_on_death)

## Whether this NPC's death plays the kill-beat hitstop (FreezeFrame in _on_died): a profile can opt out
## (pause_on_kill = false) for a trash-mob / swarm enemy; profile-less NPCs keep the pause. Pure (no tree).
func death_pauses_game() -> bool:
	return profile == null or profile.pause_on_kill

## The NpcPool that OWNS this instance, or null for a normal (free-on-death) NPC. Set by NpcPool.adopt() before the
## NPC ever spawns; while set, die() returns the body to the pool instead of queue_free()-ing it, the death-freeze
## beat is skipped (death_freezes gate below), and the snapshot death-ledger recording is suppressed (a pooled
## encounter spawn is a DYNAMIC actor, excluded from the exact-save tier). Duck-typed as a plain reference so npc.gd
## needn't preload NpcPool (avoids a class-parse cycle); NpcPool.reclaim(self) is the only method called on it.
var _pool: Node = null

## True when an EncounterSpawner produced this body (pooled OR the pool-less default path). A spawner NPC is a DYNAMIC
## actor — excluded from the exact-save snapshot tier (its runtime @-generated node_path is ephemeral, so recording it
## as dead would pollute the per-level death ledger and, on a reuse at the same @path, could suppress a legit enemy).
## Authored NPCs placed directly in a level .tscn leave this false and ARE tracked. Set by EncounterSpawner / NpcPool.
var _dynamic_spawn: bool = false

## Called once by NpcPool.adopt() to bind this instance to its pool (and disable the free-on-death path).
func set_pool(pool: Node) -> void:
	_pool = pool

## Whether this NPC's death plays the freeze-in-place beat (EffectsSettings.death_freeze_duration in
## _begin_death): a profile can opt out (freeze_on_death = false) for a trash-mob / swarm enemy that should just
## pop instantly. Profile-less NPCs freeze. A POOLED NPC always skips it — _freeze_for_death DISABLES process_mode
## and its PROCESS_MODE_ALWAYS descendants irreversibly ("nothing needs restoring" — true only under free()), and
## arms a SceneTree timer that would re-fire gore()+die() on the reused body; skipping sidesteps both. Pure (reads
## only fields), so a unit test still pins the profile combos.
func death_freezes() -> bool:
	return _pool == null and (profile == null or profile.freeze_on_death)

## On-death override: hold the body FROZEN in place for a brief beat, THEN burst into gore — the "freeze then
## explode" kill pop. Falls straight back to Character's immediate gore()+die() when the beat doesn't apply:
## duration 0, this archetype opts out (freeze_on_death), we're off-tree (a unit test built us with load().new()),
## or the timescale "juice" is off (headless/tests) — so tests and profiled swarm mobs keep the old instant death.
func _begin_death() -> void:
	var dur: float = GameSettings.effects.death_freeze_duration
	if dur <= 0.0 or not death_freezes() or not is_inside_tree() or not GameSettings.allow_timescale_changes:
		super._begin_death()
		return
	_freeze_for_death(dur)

## Enter the death freeze: drop the aim beam, kill residual motion (so the later ragdoll launch inherits only the
## killing blow's blast, not our stale walk velocity), and DISABLE processing so the AI, locomotion, and gravity
## all halt — the body hangs exactly where it died. A SceneTree timer (unaffected by our own disabled process_mode,
## and by design NOT process_always so a menu pause holds the freeze rather than bursting mid-pause) fires
## _complete_death after the beat. Bound-method Callable, not a lambda, per the freed-capture rule.
func _freeze_for_death(dur: float) -> void:
	_hide_laser()
	velocity = Vector3.ZERO
	process_mode = Node.PROCESS_MODE_DISABLED
	_freeze_always_children(self)
	get_tree().create_timer(dur, false).timeout.connect(_complete_death)

## Disabling our own process_mode halts everything that INHERITS it, but a couple of animation drivers force
## themselves PROCESS_MODE_ALWAYS so they survive the dialogue tree-pause (BodyModelSwap's gait/breathing,
## NpcHeadLookMount's head swivel) — left alone they'd keep animating through this per-body freeze, so the pose
## wouldn't actually hold. Recurse and disable any descendant that opted ALWAYS. We're about to free, so nothing
## needs restoring; keyed off the OWN process_mode (not can_process) so it targets exactly the pause-survivors.
func _freeze_always_children(n: Node) -> void:
	for c in n.get_children():
		if c.process_mode == Node.PROCESS_MODE_ALWAYS:
			c.process_mode = Node.PROCESS_MODE_DISABLED
		_freeze_always_children(c)

## Fire the gore burst + removal once the freeze beat elapses (deferred from _begin_death). If we were freed during
## the freeze — a level unload — the timer's connection to us is already gone, so this never runs on a dead instance.
func _complete_death() -> void:
	gore()
	die()

## Death removal, pool-aware (overrides Character.die). We STILL emit `died` first — so the full death payload runs
## unchanged: _on_died (witness barks, kill-quest, XP, faction sour, loot corpse, corpse marker) and the Death
## child, PLUS every EncounterSpawner that tracks this spawn drops it from _alive and resolves its clear-gate. Only
## the FINAL disposal differs: a pooled NPC is parked back in its pool (reset + removed from the tree on the next
## activation) instead of freed. Non-pooled NPCs free exactly as before. Pooled NPCs never take the freeze-in-place
## path (death_freezes() is false for them), so process_mode is untouched here and the pool owns re-activation.
func die() -> void:
	died.emit()
	if _pool != null:
		_notify_peers_forget_me()  # a reused body is the SAME instance reborn — clear peers' stale refs to it FIRST
		_pool.reclaim(self)
	else:
		queue_free()

## Pooling: before this body is parked for reuse, tell every other NPC to drop any reference it holds to us. A freed
## (non-pooled) body's references lapse naturally — the next spawn is a NEW pointer that fails the stale match; a
## POOLED body is the SAME instance reborn, so a peer's grudge/target/last-attacker would resurrect against a fresh
## life that never provoked it (phantom feud / unprovoked aggro). Mirrors the liveness contract that already drops a
## dead PLAYER as a target — _npc_grudges, uniquely, isn't liveness-gated, so it needs the explicit sweep. O(N) over
## the npc group per pooled death; fine for authored encounter sizes.
func _notify_peers_forget_me() -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group(Groups.NPC):
		if n != self and is_instance_valid(n) and n.has_method(&"forget_dead_peer"):
			n.forget_dead_peer(self)

## Drop every reference we hold to `peer` (a pooled body about to be reused): our grudge against it, and our target /
## last-attacker if they point at it. Public so the dying peer can broadcast it (see _notify_peers_forget_me).
func forget_dead_peer(peer: Node) -> void:
	_npc_grudges.erase(peer)
	if _last_attacker == peer:
		_last_attacker = null
	if _target == peer:
		_set_target(null)

## PUBLIC WRITE SEAM — break off the CURRENT engagement without changing WHO we hate. Drops the combat target and
## the sticky attacker lock, wipes Perception back to UNAWARE, and puts the aim beam away, so the GOAP planner falls
## to its Idle floor (companion-follow / schedule / patrol / wander / return-to-post) on the very next tick. The
## give-up bark fires by itself the frame after, through the no-target branch's _settle_engagement_barks().
##
## Deliberately does NOT touch `_provoked`, the faction standing, or `_npc_grudges`: a guard you shot is still angry
## the next time it lays eyes on you — it has merely stopped fighting for now and gone back to its post. (Pool reuse
## is the place that clears all of those; see reset_for_reuse.) Called by the NpcHomeReturn leash (player death /
## off-screen reset) and safe for a cutscene or dialogue consequence to call directly.
func stand_down() -> void:
	_set_target(null)
	set_last_attacker(null)
	if _perception != null:
		_perception.forget()
	_hide_laser()

## Send this NPC back to its authored post NOW — facade onto the NpcHomeReturn child (npc_home_return.gd), which
## owns the leash rules. `force` skips the "never move a body the player can see" guard; leave it false to get a
## refusal (returns false) while the NPC or its post is on screen. Returns false off-tree / with the component
## disabled / while the NPC is exempt (companion, bodyguard, cutscene, mid-talk, dead).
func send_home(force: bool = false) -> bool:
	if _home_return == null:
		return false
	return bool(_home_return.call(&"return_home", force))

## NPC-pooling reuse reset (NpcPool): return this instance to its pristine post-_ready state so it can be re-spawned
## as a fresh combatant, WITHOUT rebuilding any child node or re-running _apply_stats / _build_* (that would add
## duplicate children and re-stamp strength ADDITIVELY into max_hp every cycle). Called by NpcPool.acquire() AFTER the
## body has been re-parented into the level and re-positioned, and BEFORE the spawner re-aggros. The pool is
## HOMOGENEOUS (one bucket per scene+profile+faction+weapon loadout), so appearance / stats / weapon identity are
## identical across lives and are NOT re-applied — only the DYNAMIC per-life state is cleared, and each stateful child
## component runs its own reset_for_reuse(). Keep this in sync with the fields _ready seeds; see docs/AUTHORING_GUIDE
## (NPC pool) and the reset-surface map that generated it. super() (Character) handles the base vitals/flash/process.
func reset_for_reuse() -> void:
	super()  # Character: _dead=false, hp=max_hp, limbs healed, blast/flash cleared, status effects dropped, process/visible restored
	# _identity_key is deliberately NOT reset: it's AUTHORED identity (NpcData.id / the ready-latched authored
	# display name), and the pool is homogeneous (same scene+profile), so every life shares the same stable key.
	# Re-anchor the wander/return-to-post centre on the NEW placement the pool just applied (the same re-stamp
	# restore_snapshot_state does on a save reload) — else a reused wanderer drifts back toward its old spot.
	_spawn_position = global_position
	_spawn_yaw = rotation.y
	# Targeting: drop every sticky reference (some may point at freed nodes) so we never engage a ghost on frame 1.
	_set_target(null)
	set_last_attacker(null)
	_npc_grudges.clear()
	# Follow/guard: a homogeneous encounter combatant is normally neither, but a prior life could have been recruited
	# (dialogue "join me") — undo it cleanly through the proper side-effect paths (rim, teleport, &"Player" group).
	if is_following():
		stop_following()
	if _guarding != null:
		stop_guarding()
	# Hostility / provoke bookkeeping.
	_provoked = false
	_provoke_rep_delta = 0.0
	_holster_forgiveness_tutorial_active = false
	_holster_forgiveness_spent = false  # betrayal one-shot — reset like _provoked, or a pooled body inherits a spent pardon and refuses to EVER stand down
	_pickpocket_caught = false  # per-life pickpocket lockout — reset like _provoked, or a reused body inherits closed pockets it never earned
	# Temperament panic: break_and_flee() flips the AUTHORED threat_response to FLEE for the rest of a life, so a body
	# that broke last life would come back a permanent coward — never firing again and permanently holster-forgivable.
	# Restore what it was authored/stamped with (skipped entirely when it never panicked).
	if _pre_panic_threat_response >= 0:
		threat_response = _pre_panic_threat_response as ThreatResponse
		_pre_panic_threat_response = -1
	_player_aggression = 0.0  # written by the ProvokeOnAttack child; the friendly-aggro accumulator lives here on the host
	# One-shot / per-life reaction + bark latches (each gates a once-per-life cue).
	_save_rewarded = false
	_hit_by_player = false
	_silent_death = false     # documented "never reset" — true only under free(); under pooling it MUST reset or the witness bark stays suppressed forever
	_hurt_bark_said = false
	_saw_combat = false
	_was_aware = false
	_was_distracted = false
	_scripted_investigating = false
	_alerted_allies = false
	_bark_until_msec = -100000
	# Combat wind-up (host-owned). _fire_timer seeds a FULL interval so the first shot CHARGES (not fires instantly).
	_fire_timer = _shot_interval()
	_charging = false
	_warned = false
	_shot_miss = false
	# Aim-sting de-dup, music attend, and the scan throttles.
	_last_aim_msec = 0
	_aim_sfx_delay = -1.0
	_aim_targeting_player = false
	_attending_radio = null
	_music_commented_radio = null
	_music_scan_t = 0.0
	_search_sweep_t = 0.0
	_distraction_scan_t = 0.0
	_retarget_timer = 0.0
	# Velocity intents + the stranded-nav diagnostic.
	_desired_velocity = Vector3.ZERO
	_avoid_velocity = Vector3.ZERO
	_avoid_ready = false
	_reset_stranded()
	_last_giveup_pos = Vector3.ZERO
	# Cutscene control (a stale _cutscene_control would leave the reused NPC's AI brain suppressed / inert).
	_cutscene_control = false
	_cutscene_has_walk = false
	_cutscene_has_face = false
	_cutscene_walk_target = Vector3.ZERO
	_cutscene_face_target = Vector3.ZERO
	# Weapon magazine: clear the cross-swap bookkeeping + refill the clip (free AI refill, not a reload that spends a
	# backpack clip). starts_unloaded is re-honoured AFTER the backpack re-equip below, NOT here.
	if _weapon != null and _weapon.ammo != null:
		_weapon.ammo.reset_for_reuse()
	# Backpack: WIPE the drifted contents (consumed-ammo delta + this life's loot-table drops that gore() rolled in —
	# the corpse only COPIED the bag, never emptied it) and re-seed the AUTHORED loadout. Never re-roll _roll_loot().
	if inventory != null:
		inventory.clear()
		_seed_carried_items()    # authored item_stacks (weapons duplicated to unique instances)
		_equip_initial_weapon()  # re-add the weapon item + starting clips + draw the strongest (rebuilds the hand view-model)
	# Honour starts_unloaded LAST — mirrors the _ready weapon branch, which zeroes AFTER _equip_initial_weapon. If the
	# body had SWAPPED to a different gun last life, the re-equip above fires weapon_changed -> Ammo.set_to_max_ammo
	# (the equipped WeaponData now differs, so equip() doesn't early-return), which would refill a clip zeroed earlier;
	# zeroing here, post-equip, keeps a reused dry ambusher actually dry.
	if _weapon != null and _weapon.ammo != null and starts_unloaded:
		_weapon.ammo.current_ammo = 0
	# Stair step-smoothing is per-life cosmetic state: clear the eased offset and restore the model's rest Y so a pooled
	# NPC never spawns with a leftover visual dip from a prior life's staircase.
	_step_smooth_y = 0.0
	if mesh != null and _mesh_rest_captured:
		mesh.position.y = _mesh_rest_y
	# Each stateful child owns its reset (component-owns-its-reset — avoids a central hand-list that drifts).
	if _perception != null:
		_perception.reset_for_reuse()
	if _locomotor != null:
		_locomotor.reset_for_reuse()
	if _locomotion != null:
		_locomotion.reset_for_reuse()
	if _executor != null:
		_executor.reset_for_reuse()
	if _combat != null:
		_combat.reset_for_reuse()
	if _stance != null:
		_stance.reset_for_reuse()  # clears engaged/stand-down + holsters the gun (post-_ready stowed state)
	if _outline != null:
		_outline.reset_for_reuse()
	if _laser != null:
		_laser.reset_for_reuse()
	if _scavenge != null:
		_scavenge.reset_for_reuse()     # drop a stale container-raid target (no wrong-way walk-off on spawn)
	if _voice != null:
		_voice.reset_for_reuse()        # rewind bark cooldowns so a quick respawn isn't muted
	if _self_healer != null:
		_self_healer.reset_for_reuse()  # rewind the medkit cooldown
	if _talk != null:
		_talk.reset_for_reuse()         # drop a leftover pre-talk walk-up
	if _home_return != null:
		_home_return.call(&"reset_for_reuse")  # clear the off-screen clock + any pending player-death return
	# Re-scan for a target now, mirroring the _acquire_target() at the tail of _ready.
	_acquire_target()

## Leave a lootable corpse holding our backpack — facade onto NpcMortality (npc_mortality.gd). Called from _on_died in
## its authored order; no-op off-tree (no _mortality until _ready), exactly as the old is_inside_tree guard behaved.
func _drop_loot() -> void:
	if _mortality != null:
		_mortality.drop_loot()

## Grant the player kill-XP — facade onto NpcMortality. No-op off-tree.
func _award_kill_xp() -> void:
	if _mortality != null:
		_mortality.award_kill_xp()

## Stealth body-discovery corpse marker — facade onto NpcMortality. No-op off-tree.
func _spawn_corpse_marker() -> void:
	if _mortality != null:
		_mortality.spawn_corpse_marker()

## Roll our profile's loot table INTO the backpack BEFORE gore() copies it into the (ragdoll) corpse, so the
## rolled drops land in the loot whether the body becomes a ragdoll corpse (GoreSpawner._attach_loot) or a
## free-standing one (_drop_loot). gore() runs once, on death (Character.take_damage at hp <= 0).
func gore() -> void:
	_roll_loot()
	super()

## Roll the effective loot table into the backpack (weapons as unique instances), ON TOP of what we carried.
## A profile's NpcData.loot wins when a profile is assigned (the all-or-nothing contract -- even if null);
## otherwise the inline `loot` export is used. No-op without a table or an inventory.
func _roll_loot() -> void:
	var table: LootTable = profile.loot if profile != null else loot
	if table == null or inventory == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	table.grant(inventory, rng)

## Off guard (eligible for the sneak-attack bonus) until fully ALERTED — i.e. while UNAWARE, still
## DETECTING, or INVESTIGATING a noise. Once it locks on and engages, no more free sneak damage.
## Civilian-safe: a no-Perception NPC (built off-tree, or before _ready) is never an ambush target.
func is_off_guard() -> bool:
	return _perception != null and _perception.state != Perception.State.ALERTED

## Slice 6b: flag the NEXT death as a silent takedown so _on_died suppresses the witness bark (see _on_died). Call
## this IMMEDIATELY before the lethal take_damage. One-shot; the NPC is about to die, so it's never cleared.
func mark_silent_takedown() -> void:
	_silent_death = true

## True while this NPC is actively fighting — it has a live hostile target AND has locked on
## (Perception ALERTED, gun up). A talk request is REFUSED while busy (see Talkable.start_talk /
## prompt_talk): you can't chat up an enemy mid-firefight — it only fights, it doesn't talk.
## Civilian-safe / pre-_ready-safe: no _perception (off-tree, before _ready) or no target => false,
## via the same null-guard pattern as is_off_guard().
func is_in_combat() -> bool:
	return _perception != null and is_instance_valid(_target) and _perception.state == Perception.State.ALERTED

## True while this NPC is locked onto the PLAYER specifically (ALERTED with the player — or a companion in the
## &"Player" group — as its live target). Distinct from is_in_combat(), which is target-AGNOSTIC: an NPC ALERTED
## on ANOTHER npc (an NPC-vs-NPC fight) IS in combat but has NOT spotted the player. Drives the DetectionStinger
## "you've been seen" cue, which must fire only on player detection. is_in_combat() already guarantees a valid
## _target, so the group read is safe.
func is_alerted_on_player() -> bool:
	return is_in_combat() and _target.is_in_group(Groups.PLAYER)

## True while the gun is DRAWN (out of the holster) for ANY reason -- engaged, first spotting you (DETECTING), the
## post-combat stand-down beat, or an out-of-combat reload. This reads the SAME holstered flag WeaponStance uses to
## show/hide the held gun model, so the arms hold the weapon exactly when the gun is VISIBLE -- not only while
## ALERTED (is_in_combat). A holstered / disarmed / dry NPC reads false, so the body-swap arms drop to the by-side
## pose (and a fists brawler, gun holstered, flails on a punch). Off-tree-safe: _weapon is null until the combatant
## path in _ready builds it, so a civilian / unit-test NPC returns false.
func is_holding_gun() -> bool:
	return _weapon != null and _weapon.attack != null and not _weapon.attack.holstered

## True while this NPC is squared up to fight UNARMED — in combat (ALERTED on a live target) AND with NO usable
## gun (a civilian brawler, or a disarmed / dry combatant). Drives the BodyModelSwap "fists out" arms-up pose so a
## fist enemy READS as armed-with-fists. Off-tree-safe via is_in_combat()'s null guard + _can_fight_with_gun().
func is_fists_out() -> bool:
	return is_in_combat() and not _can_fight_with_gun()

## True while this NPC is in combat OR actively HUNTING — locked on (ALERTED) or sweeping the last-known
## position (INVESTIGATING). The MusicDirector polls this so the combat music holds through a broken line
## of sight instead of fading out mid-search (MGS-style: the hunt is still the fight). Deliberately a
## SEPARATE predicate from is_in_combat, whose ALERTED-only meaning gates dialogue refusal + the reckless-
## fire remarks — an investigating NPC should still refuse none of those differently.
func is_hunting() -> bool:
	if _perception == null or not is_instance_valid(_target):
		return false
	return _perception.state == Perception.State.ALERTED or _perception.state == Perception.State.INVESTIGATING

## True once this NPC has genuinely NOTICED a foe — Perception past UNAWARE (detecting it, hunting it, or locked on)
## with a live target. DISTINCT from is_holding_gun() (gun merely DRAWN — a predisposed-hostile enemy keeps it out
## while still oblivious) and is_hunting() (which excludes the first-spotting DETECTING beat). Drives the
## BodyModelSwap raised-weapon arm pose so an NPC only brings its gun UP to aim once it can actually SENSE the foe,
## never at a player it hasn't seen (through a wall / behind its back / in the dark) — mirroring the head-look
## truthfulness (head_look_point). `_target` is acquired by pure PROXIMITY (NpcTargeting has no LOS), so the
## perception-state gate is what makes this honest. Off-tree-safe: no _perception / no _target -> false.
func has_sensed_foe() -> bool:
	return _perception != null and is_instance_valid(_target) and _perception.state != Perception.State.UNAWARE

## True only while the authored seated posture should be active. The export is an idle preference, not a hard
## stun: any aware/search/combat state, companion follow, or cutscene control stands it up. Dialogue keeps the
## authored seated pose; TalkApproach speaks in place instead of walking this NPC to the player.
func is_sitting() -> bool:
	if not sitting:
		return false
	if _cutscene_control:
		return false
	if is_following():
		return false
	return _perception == null or _perception.state == Perception.State.UNAWARE

## True if this NPC flees rather than fights (threat_response FLEE). A small typed helper so NpcVoice can gate
## the detection / combat-over barks without reaching the ThreatResponse enum across the class boundary.
func is_fleeing() -> bool:
	return threat_response == ThreatResponse.FLEE

## Break off and RUN: flip to FLEE and shout the "forget this!" bark. Called by the PanicOnDamage drop-in when
## a frightened NPC's fear roll trips mid-fight (the inlined temperament-flee used to do this directly). The flip is
## ONE-WAY within a life (nothing sets FIGHT back), so we stash the authored response for reset_for_reuse to restore —
## see _pre_panic_threat_response. Re-entrant-safe: PanicOnDamage re-rolls every hit but early-returns on is_fleeing().
func break_and_flee() -> void:
	if _pre_panic_threat_response < 0:
		_pre_panic_threat_response = int(threat_response)
	threat_response = ThreatResponse.FLEE
	if _voice != null:
		_voice.bark_flee()

## The Perception.State this NPC currently holds toward `who` — its live awareness when `who` is what it is
## tracking, else UNAWARE. Lets the stealth HUD (StealthStatus) read how detected the player is without
## reaching into the Perception child. Returns a Perception.State int; null-safe off-tree (no _perception).
func awareness_of(who: Node) -> int:
	if _perception == null or _perception.target != who:
		return Perception.State.UNAWARE
	return _perception.state

## How filled this NPC's detection meter is toward `who` (0..1), or 0 when it isn't tracking `who` / has no
## Perception. Mirrors awareness_of for the stealth HUD's detection "heat" bar (StealthStatus takes the worst
## across all NPCs). Off-tree safe: a bare NPC has no Perception child -> 0.
func detection_of(who: Node) -> float:
	if _perception == null or _perception.target != who:
		return 0.0
	return _perception.detection

# --- Companion contract (Feature I) — the dialogue "join me" option drives these ---
## True when this NPC may be recruited as a companion: it must currently treat the player as FRIENDLY
## (resolved_disposition FRIENDLY), so it's neither hostile/provoked nor merely neutral, and not
## already following someone. The dialogue option that offers to recruit gates on this.
func can_recruit() -> bool:
	return resolved_disposition() == Disposition.Kind.FRIENDLY and not is_following()

## Begin following `leader` (the player) as a companion: tail them at a standoff, defend them, and wear
## the blue companion rim. Idempotent re-targeting — calling again just re-points at a new leader. Clears
## any pre-talk approach (we're done parleying) and re-applies the outline so the blue rim shows at once.
func start_following(leader: Node3D) -> void:
	if leader == null:
		return
	_leader = leader
	# Feature #3: a companion is treated like the player by enemies — joining the &"Player" group makes
	# any player-hostile enemy's is_hostile_to() read true for us, so it acquires + shoots the ally. This
	# is targeting only: we do NOT become hostile to the player (our own resolved_disposition is unchanged,
	# so is_hostile_to(player) stays false), and NPC overrides the player-only damage thud so we don't also
	# play the player's felt-impact sound. Removed again in stop_following / on death (see _on_died).
	add_to_group(Groups.PLAYER)
	if _talk != null:
		_talk.abandon()  # abandon any in-progress talk approach; we're escorting now
	if _follow != null:
		_follow.reset_teleport_cooldown()  # don't blink the instant we're recruited
	_apply_outline()  # show the blue companion rim immediately (follow isn't a disposition change, so force it)

## Stop following and revert to standalone behaviour (wander / hold / fight as configured). Drops the blue
## rim back to the disposition colour. Also lets go of a defend-only target so the NPC stands down cleanly.
func stop_following() -> void:
	if _leader == null:
		return
	_leader = null
	remove_from_group(Groups.PLAYER)  # Feature #3: no longer a companion — stop reading as the player to enemies
	# Drop a target we were only holding to DEFEND the leader (not a real personal enemy), so we disengage.
	if is_instance_valid(_target) and not is_hostile_to(_target):
		_set_target(null)
		_last_attacker = null
		_hide_laser()
	_apply_outline()  # rim back to the disposition colour now that we're no longer a companion

## True while this NPC is following a (still-valid) leader. Self-heals if the leader was freed.
func is_following() -> bool:
	if _leader != null and not is_instance_valid(_leader):
		_leader = null
	return _leader != null

## The character this NPC currently DEFENDS (engages anyone hostile to it), or null. A player companion
## defends its leader; a standalone bodyguard defends whoever guard() set. Self-heals freed refs. This is
## the generic hook that makes the ally/bodyguard targeting work for ANY protectee, not just the player.
func _protectee() -> Node3D:
	if is_following():
		return _leader
	if _guarding != null and not is_instance_valid(_guarding):
		_guarding = null
	return _guarding

## Make this NPC a BODYGUARD for `character` (any character — need not be the player or player-aligned):
## it will engage anyone hostile to that character, the same way a companion defends its leader. Unlike
## start_following() this does NOT join the &"Player" group (that's player-companion-specific targeting).
func guard(character: Node3D) -> void:
	_guarding = character

## Stop bodyguarding; drop a target we were only holding to defend the charge so we stand down cleanly.
func stop_guarding() -> void:
	_guarding = null
	if is_instance_valid(_target) and not is_hostile_to(_target):
		_set_target(null)
		_last_attacker = null
		_hide_laser()

func _build_perception() -> void:
	_perception = Perception.new()
	_perception.sight_range = sight_range
	_perception.fov_degrees = fov_degrees
	_perception.crouch_sight_mult = crouch_sight_mult  # Slice 0b: was never copied -> silently stuck at 0.5
	_perception.time_to_detect = time_to_detect
	_perception.forget_time = forget_time
	_perception.pursuit_grace_time = pursuit_grace_time
	_perception.eye_height = eye_height
	_perception.hearing = hearing
	_perception.just_spotted.connect(_on_spotted)
	# Lock-on edge -> the charge-up telegraph. just_alerted fires once the detection meter fills to ALERTED,
	# which routinely happens while the enemy is still CHARGING IN from BEYOND its engage range (DETECTING only
	# faces, it doesn't close — and sight_range outranges every weapon's effective_range). Without this, the sting
	# was scheduled ONLY by _act_alerted's can_shoot branch, so it stayed silent for the whole run-in and the
	# FIRST charge at the player was missed for short-range enemies. _on_locked_on telegraphs it the instant of
	# lock-on instead, range-independent — the role just_alerted was always documented to drive.
	_perception.just_alerted.connect(_on_locked_on)
	add_child(_perception)

## First-noticed handler (wired to Perception.just_spotted in _build_perception). Plays the MGS "!" sting
## (NpcAudioCues, positional) and — gated on the SAME shared cooldown via the sting's return — pops the
## "!" head-icon. The audio child owns the FLEE-mute + cooldown so the sting and the popup stay in lockstep;
## the popup itself stays on the root (with POPUP_*). Off-tree (no _audio_cues) -> no sting, no popup.
func _on_spotted() -> void:
	if _dead or hp <= 0.0:
		return  # a one-shot kill (the hit forces the spot via _on_damaged_by) shouldn't still sting/popup/bark
	if _audio_cues != null and _audio_cues.on_spotted(global_position):
		_popup_icon(POPUP_EXCLAMATION, true)  # "!" over the head — follows us, in sync with the bark bubble; shares the sting's cooldown gate
	_try_detection_bark()  # Feature #7: a nearby hostile talker shouts "Over here!" the moment it spots you

## Feature #7 — detection bark: when an NPC spots a HOSTILE (the PLAYER, OR an enemy NPC) and it's a
## speaking character (has a Talkable child), it calls out — a short line shown as floating text above its
## head (like the "!" alert) AND spoken aloud via the in-game TTS (SpeechTts — positional, from the NPC).
## Gated on being near the PLAYER so a far-off callout isn't synthesized inaudibly + its world-space text
## stays readable. A fleer never barks (it's running). A per-NPC cooldown paces each NPC; there's NO shared
## throttle any more — multiple NPCs can shout AT ONCE (the addon mixes their voices through the Voice bus).
## The resolved bark lines for THIS NPC: a profile's BarkSet (NpcData.bark_set) when set, else the empty
## default — and each empty category falls back to the BARK_* consts below via _bark_pool. So a no-profile
## NPC uses the defaults, and a profiled NPC overrides only the categories its BarkSet fills.
var _voice: NpcVoice = null  ## bark / social-voice orchestration child (built in _build_components) — npc_voice.gd
var _targeting: NpcTargeting = null  ## target-acquisition child (built in _build_components) — npc_targeting.gd
var _locomotion: NpcLocomotion = null  ## non-combat movement child: idle / wander / flee — npc_locomotion.gd
var _scavenge: NpcScavenge = null  ## container raiding: walk to + take a better/first weapon nearby — npc_scavenge.gd
var _self_healer: SelfHealer = null  ## react-to-own-HP: spend a carried medkit when hurt (self_healer.gd); react()'d from _on_damaged_by
var _panic: PanicOnDamage = null  ## react-to-own-HP: break + flee when hurt mid-fight (panic_on_damage.gd); react()'d from _on_damaged_by
var _provoke_on_attack: ProvokeOnAttack = null  ## react-to-attack: a player hit flips a non-hostile NPC hostile (provoke_on_attack.gd); react()'d from _on_damaged_by
## react-to-cripple: the "Crippled X's arm" player toast + the NPC's own "My arm!" bark (cripple_callout.gd);
## react()'d from _on_limb_crippled. Typed `Node` (not `CrippleCallout`) and PATH-loaded in _build_components so
## this @tool root never names the new class_name — a bare-type ref to a not-yet-reimported class can break
## npc.gd's parse in the live editor (see the new-classname-cascade memory).
var _cripple_callout: Node = null
var _executor: GoapExecutor = null  ## the GOAP brain (built in _build_components); the NPC's sole AI decision layer
var _bark_ui: NpcBarkUi = null  ## head-popup presentation child (bark bubble + "!" / cue icons) — npc_bark_ui.gd

const BARK_LINES: Array[String] = []
const BARK_DISTANCE: float = 14.0         ## only bark when within this of the player — the listener (2D audio + world text)
const BARK_COOLDOWN_MS: int = 6000        ## per-NPC: each NPC barks at most this often (NpcVoice reads it)
var _bark_until_msec: int = -100000              ## while now < this, a bark of ours is still on screen -> suppress new ones
const THANKS_LINES: Array[String] = []

## Death-witness reactions (FNV-style): when the PLAYER kills an NPC, other NPCs within DEATH_WITNESS_RADIUS
## react. A co-aligned peer cries "Murderer!" (DEATH_ALLY_LINES); an unallied bystander remarks on a HOSTILE
## enemy's death by its OWN disposition — a friendly ally approves (DEATH_APPROVE_LINES), anyone else
## questions/shrugs (DEATH_QUESTION_LINES). Routed through react_remark, so each witness self-filters
## (non-hostile, out-of-combat, has a Talkable) and shares the per-NPC + spoken bark cooldowns.
const DEATH_WITNESS_RADIUS: float = 18.0
const DEATH_APPROVE_LINES: Array[String] = []
const DEATH_QUESTION_LINES: Array[String] = []
const DEATH_ALLY_LINES: Array[String] = []

## A wounded ally (companion) cries out ONCE when its HP drops to/below HURT_BARK_HP_FRAC of max. Played
## even mid-combat (via _cry_wounded, which bypasses react_remark's out-of-combat gate).
const HURT_BARK_HP_FRAC: float = 0.35
const HURT_LINES: Array[String] = []

## FNV-style hover greeting: a short line the NPC speaks when the player's crosshair first lands on it
## (non-hostile, idle NPCs only). Cooldown-gated so glancing back and forth doesn't spam it.
const GREET_COOLDOWN_MS: int = 9000
const GREET_LINES: Array[String] = []

## Combatant / sentry call-outs: a reload shout ("Reloading!") when the AI ducks to reload, a combat-over
## line ("Lost 'em.") when a fighter gives up the chase, and a softer LOST-INTEREST line ("Must be gone
## now.") when an NPC that only NOTICED you (heard/glimpsed, never engaged) gives up searching and goes idle.
## All reuse the bark cooldowns.
const RELOAD_LINES: Array[String] = []
const COMBAT_END_LINES: Array[String] = []
const LOST_INTEREST_LINES: Array[String] = []
## Active-search call-outs — muttered (cooldown-paced) WHILE an NPC hunts a lost target / a noise, between the
## "!" and the give-up line. A wary, hunting beat. Overridable per archetype via BarkSet.search.
const SEARCH_LINES: Array[String] = []
## Panic call-outs — said the moment a fighter BREAKS and flees (temperament flip under fire), instead of the
## silence a fleer otherwise keeps. Overridable per archetype via BarkSet.flee.
const FLEE_LINES: Array[String] = []
## Spotted-a-body call-outs — said the moment an UNAWARE NPC notices a discoverable corpse (stealth
## body-discovery). A wary "someone's been here" beat, not a combat shout. Overridable per archetype via
## BarkSet.check_body.
const CHECK_BODY_LINES: Array[String] = []

## Player-attack reactions (fired from _on_damaged_by via NpcVoice): a hit on a non-hostile NPC that does
## NOT flip it (an ally absorbing stray fire under friendly_aggro_threshold) draws the WARNING; the hit that
## DOES flip it (the threshold crossed, or a neutral's first hit) gets the AGGRO snap.
const WARN_ATTACK_LINES: Array[String] = []
const AGGRO_LINES: Array[String] = []

## The de-escalation tail of that arc: the player HOLSTERED and our provoke was PARDONED (forgive_provoke), so we
## drop the grudge out loud. PARDON_FLEEING is the ALTERNATIVE read for the specific case where the pardon caught us
## mid-RUN — an authored FLEE civilian, or a fighter PanicOnDamage broke — because "you put the gun away" hits very
## differently when the NPC was sprinting for its life. Resolution is the usual override-or-default per pool, then
## the fleeing pool overrides the standard one; an unauthored fleeing pool falls through to PARDON so filling only
## the standard category still covers both. Overridable per archetype via BarkSet.pardon / .pardon_fleeing; resolved
## by _pardon_lines and emitted by NpcVoice.bark_pardon. NOT tied to stand_down() (the combat disengage) or
## stand_down_on_player_death() (the death settlement) — neither of those is the player talking anyone down.
const PARDON_LINES: Array[String] = []
const PARDON_FLEEING_LINES: Array[String] = []

## Music reactions (jukebox): an idle NPC — friendly OR hostile — that can HEAR a playing radio (within its
## audible_radius) turns to face it and comments ONCE on the song/playlist QUALITY (a deterministic MusicQuality
## score of the radio's text, bucketed into a tier). Routed through NpcVoice.music_comment, so each NPC self-filters
## (out-of-combat, has a Talkable) + shares the bark cooldown — but a hostile idle NPC is NO LONGER filtered out
## (unlike react_remark). Ships ON (GameSettings.npc_ai.music_reactions). preload (not the bare class_name) so the
## suite resolves it before the editor scans the new script.
const MQ = preload("res://scripts/components/music_quality.gd")
const MUSIC_AWFUL_LINES: Array[String] = []
const MUSIC_MEH_LINES: Array[String] = []
const MUSIC_GOOD_LINES: Array[String] = []
const MUSIC_GREAT_LINES: Array[String] = []
var _attending_radio: Node3D = null        ## the playing radio an idle NPC is enjoying (its head-look target); null = none
var _music_commented_radio: Node3D = null  ## the radio we last commented on, so the bark fires once per attend
var _music_scan_t: float = 0.0             ## throttle for the &"music" scan (paced like the distraction scan)

## Resolve a bark pool: a profile's per-category override if it has any lines, else the built-in default.
static func _bark_pool(fallback: Array[String], override: Array[String]) -> Array[String]:
	return override if not override.is_empty() else fallback

## Pick one random line from the resolved pool (override-or-default); "" if somehow empty.
static func _pick_bark(fallback: Array[String], override: Array[String]) -> String:
	var pool := _bark_pool(fallback, override)
	return pool[randi() % pool.size()] if not pool.is_empty() else ""

## How long (ms) a bark's bubble stays on screen — its text-length-scaled hold beat plus the fade (matching
## _popup_text's tween) — so _emit_bark can suppress a second bark until this one has cleared.
func _bark_duration_ms(line: String) -> int:
	# Match the ACTUAL bubble lifetime (NpcBarkUi.show_text's tween, which uses the instance's @exports) so the
	# no-overlap gate lasts exactly as long as the bubble shows — a designer who tunes the hold on the _bark_ui child
	# must not get a stale gate. Read the live instance when we have one; fall back to the shipped consts off-tree
	# (no _bark_ui yet — unit tests / before _build_components) so the static reads still resolve.
	var hold_min: float = _bark_ui.popup_hold if _bark_ui != null else NpcBarkUi.POPUP_HOLD
	var hold_base: float = _bark_ui.bubble_hold_base if _bark_ui != null else NpcBarkUi.BUBBLE_HOLD_BASE
	var hold_per: float = _bark_ui.bubble_hold_per_char if _bark_ui != null else NpcBarkUi.BUBBLE_HOLD_PER_CHAR
	var fade: float = _bark_ui.popup_fade if _bark_ui != null else NpcBarkUi.POPUP_FADE
	var hold := maxf(hold_min, hold_base + float(line.length()) * hold_per)
	return int((hold + fade) * 1000.0)

## Emit a bark — float the bubble + (when near the player) speak it — after a tiny RANDOM reaction delay
## so NPCs don't react instantly (reads more natural). The bubble is world-space (distance-limits itself);
## the spoken line is gated on proximity to the player so a distant NPC's shout isn't synthesized inaudibly.
## Bails if we die during the brief delay; suppressed while a prior bark OF OURS is still showing.
func _emit_bark(line: String, voice: VoiceData) -> void:
	# Unauthored speech is SILENT: the *_LINES consts ship empty (bark text is authored content — fill a
	# BarkSet .tres per archetype, or the consts), and _pick_bark returns "" from an empty pool. Skip here
	# so no path shows an empty bubble or feeds empty text to TTS.
	if line.is_empty():
		return
	# One bark at a time: while our previous bubble is still on screen, drop the new one rather than stacking
	# two balloons / talking over ourselves. Gates EVERY bark path (combat, greet, witness, ...) since they all
	# funnel through here. Set before the reaction delay so two requests in the same beat can't both pass.
	var start := Time.get_ticks_msec()
	if start < _bark_until_msec:
		return
	_bark_until_msec = start + _bark_duration_ms(line)
	await get_tree().create_timer(randf_range(0.05, 0.08)).timeout
	if _dead or hp <= 0.0 or not is_inside_tree():
		return
	_popup_text(line)
	note_speaking(float(_bark_duration_ms(line)) / 1000.0)  # bob the head + flap the mouth for the bark's duration
	var player := _real_player()
	if player == null or global_position.distance_to(player.global_position) > GameSettings.npc_bark.bark_distance:
		return
	_speak_bark(line, voice)  # no shared throttle: different NPCs speak simultaneously (the Voice bus mixes them)

## Detection bark — facade onto NpcVoice. No-op off-tree (no _voice until _build_components).
func _try_detection_bark() -> void:
	if _voice != null:
		_voice._try_detection_bark()

## Spotted-a-body bark — facade onto NpcVoice (stealth body-discovery). No-op off-tree.
func _try_check_body_bark() -> void:
	if _voice != null:
		_voice.bark_check_body()

## Friendly/ally flavour reaction (reckless fire, aimed-at) — facade onto NpcVoice. Called from player.gd
## with RECKLESS_LINES / AIM_LINES; NpcVoice self-filters (non-hostile, out-of-combat speaker only).
func react_remark(lines: Array[String]) -> void:
	if _voice != null:
		_voice.react_remark(lines)

## A music comment keyed to a quality TIER (jukebox) -- routes the tier's line pool through NpcVoice.music_comment,
## which mirrors react_remark's out-of-combat / has-Talkable self-filter + bark cooldown but DROPS the non-hostile
## gate, so a HOSTILE idle NPC (a raider by its own radio, UNAWARE of any threat) reacts too. Called from
## _react_music. No-op off-tree (no _voice until _build_components).
func react_music(tier: int) -> void:
	if _voice != null:
		_voice.music_comment(_music_lines(tier))

func _music_lines(tier: int) -> Array[String]:
	# Layer the per-archetype BarkSet music override over the built-in defaults (override-or-default, like every
	# other bark category). _voice carries the resolved BarkSet (a profile's, or the shared default_barks); null
	# off-tree -> just the consts. An empty override category inherits the MUSIC_*_LINES default.
	var bs: BarkSet = _voice._bark_set if _voice != null else null
	var none: Array[String] = []
	match tier:
		MQ.Tier.AWFUL: return _bark_pool(MUSIC_AWFUL_LINES, bs.music_awful if bs != null else none)
		MQ.Tier.GOOD: return _bark_pool(MUSIC_GOOD_LINES, bs.music_good if bs != null else none)
		MQ.Tier.GREAT: return _bark_pool(MUSIC_GREAT_LINES, bs.music_great if bs != null else none)
		_: return _bark_pool(MUSIC_MEH_LINES, bs.music_meh if bs != null else none)

## The bark pool for a holster PARDON (forgive_provoke) — resolved HERE, like _music_lines, so NpcVoice only owns
## the gates + emission and this stays unit-testable off-tree. Two layers, then one more for the alternative:
##   1. the standard pool = BarkSet.pardon over PARDON_LINES (the usual override-or-default),
##   2. when `fleeing`, the runner variant (BarkSet.pardon_fleeing over PARDON_FLEEING_LINES) OVERRIDES it.
## An unauthored runner variant falls THROUGH to the standard pool instead of going silent, so a designer who fills
## only `pardon` still covers the fleeing case — the exact case fleeing_always_forgivable exists for, which would
## otherwise be the one moment with no line. _voice carries the resolved BarkSet (a profile's, or the shared
## default_barks); null off-tree -> just the consts.
func _pardon_lines(fleeing: bool) -> Array[String]:
	var bs: BarkSet = _voice._bark_set if _voice != null else null
	var none: Array[String] = []
	var standard := _bark_pool(PARDON_LINES, bs.pardon if bs != null else none)
	if not fleeing:
		return standard
	return _bark_pool(standard, _bark_pool(PARDON_FLEEING_LINES, bs.pardon_fleeing if bs != null else none))

## A wounded ally's cry ("I'm hurt...") — facade onto NpcVoice. Triggered once, below an HP fraction, from
## _on_damaged_by.
func _cry_wounded() -> void:
	if _voice != null:
		_voice._cry_wounded()

## Assist-thanks ("Hey, thanks!") — facade onto NpcVoice. Called from _on_died (and cross-NPC) when the
## player helped this NPC win its fight.
func thank_for_assist() -> void:
	if _voice != null:
		_voice.thank_for_assist()

## Reload call-out ("Reloading!") — facade onto NpcVoice. Fired from _act_alerted the instant the AI reloads.
func _try_reload_bark() -> void:
	if _voice != null:
		_voice._try_reload_bark()

## Combat-over call-out ("Lost 'em.") — facade onto NpcVoice. Fired once on the return to UNAWARE after a
## fighter was ALERTED.
func _try_combat_end_bark() -> void:
	if _voice != null:
		_voice._try_combat_end_bark()

## Lost-interest call-out ("Must be gone now.") — facade onto NpcVoice. Fired once on the return to UNAWARE
## for an NPC that only NOTICED a threat (never ALERTED).
func _try_lost_interest_bark() -> void:
	if _voice != null:
		_voice._try_lost_interest_bark()

## Active-search mutter ("Where are you?") — facade onto NpcVoice. Called every frame WHILE INVESTIGATING. Two gates
## pace it: a search-age grace here (the NPC must have been hunting for search_bark_delay seconds before the FIRST
## mutter, so a one-second loss of sight doesn't trigger an instant "still around here somewhere...") and the bark
## cooldown inside bark_searching (which paces every mutter after). search_elapsed() re-zeroes on each re-entry into
## INVESTIGATING, so a target that keeps flickering in and out of sight never banks enough age to bark.
func _try_search_bark() -> void:
	if _voice == null or _perception == null:
		return
	if _perception.search_elapsed() < GameSettings.npc_bark.search_bark_delay:
		return
	_voice.bark_searching()

## A co-aligned ally? Same faction (or a positive faction relation); unaligned NPCs have no allies. Facade
## onto HostilityHelpers. Used by the damage handler (don't aggro an ally that hit us) AND NpcVoice's
## death-witness reaction — a general alliance query, so it stays on the NPC.
func _is_ally_of(other: NPC) -> bool:
	if other == null or other == self:
		return false
	return HostilityHelpers.npc_vs_npc_allied(faction, other.faction)

## GA-1 alert propagation: on first-hand contact (we just went ALERTED), tell same-faction allies within
## alert_radius to converge on `point` via the shipped investigate(), so a squad reacts together instead of
## fighting as solo islands. Routed through investigate() (-> INVESTIGATING), which does NOT itself re-broadcast,
## and latched once per engagement (_alerted_allies) — so this fires only from first-hand ALERTED contacts, never
## a relay, bounding it to O(n) broadcasts (no alert storm). Off unless alert_radius > 0. In-tree group scan ->
## playtest-verified; the per-ally gate (should_alert_ally) carries the unit test.
func _alert_allies(point: Vector3) -> void:
	if alert_radius <= 0.0 or not is_inside_tree():
		return
	var allies: Array[NPC] = []
	for n in get_tree().get_nodes_in_group(Groups.NPC):
		var ally := n as NPC
		if ally == null or ally == self:
			continue
		if should_alert_ally(faction, global_position, alert_radius, ally.faction, ally.global_position, not ally._dead and ally.hp > 0.0):
			allies.append(ally)
	# GA-4 coordinated search: hand each ally a DIFFERENT sector (TAU*i/n) of the shared origin so the squad
	# sweeps different ground instead of all converging on the identical breadcrumb ring. investigate() does
	# NOT re-broadcast (no alert storm).
	var count := allies.size()
	for i in count:
		allies[i].investigate(point, false, TAU * float(i) / float(count))

## Pure GA-1 gate: should a source (faction `src_faction`, at `src_pos`, broadcast radius `radius`) alert an
## ally (faction `ally_faction`, at `ally_pos`, `ally_alive`)? Same-faction/allied + alive + within radius.
## Static + value-args so it unit-tests off-tree (the live scan in _alert_allies feeds it from the &"npc" group).
static func should_alert_ally(src_faction: Faction, src_pos: Vector3, radius: float, ally_faction: Faction, ally_pos: Vector3, ally_alive: bool) -> bool:
	if radius <= 0.0 or not ally_alive:
		return false
	if not HostilityHelpers.npc_vs_npc_allied(src_faction, ally_faction):
		return false
	return src_pos.distance_to(ally_pos) <= radius

## Death-witness announce — facade onto NpcVoice. Called from _on_died for a player-caused death so nearby
## NPCs react ("Murderer!"). The per-witness reaction lives in NpcVoice.
func _announce_death_to_witnesses() -> void:
	if _voice != null:
		_voice._announce_death_to_witnesses()

## A nearby NPC reacts to seeing the player kill `victim` — facade onto NpcVoice. Called cross-NPC from
## another NPC's _announce_death_to_witnesses.
func _witness_death(victim: NPC) -> void:
	if _voice != null:
		_voice._witness_death(victim)

## A crippled limb makes a talking NPC cry out "My leg!" etc. — floating text + spoken (when near the
## player, since the voice is 2D) — on top of the base cripple SFX + head-stagger hook (super).
func _on_limb_crippled(part: int, attacker: Node = null) -> void:
	super._on_limb_crippled(part, attacker)  # cripple SFX + head-stagger hook still play even on a lethal hit
	# The cripple callouts — the player-facing "Crippled X's arm" toast + the NPC's own "My arm!" bark — live on
	# the CrippleCallout drop-in (scripts/components/cripple_callout.gd), auto-built in _build_components. This
	# stays a shell because _on_limb_crippled is a dispatch-by-name Character virtual (the base owns the SFX above).
	# Null off-tree (a bare unit-test NPC never runs _ready), so the callouts are simply skipped there.
	if _cripple_callout != null:
		_cripple_callout.call(&"react", self, part, attacker)

## This NPC's Talkable child (the speak/parley component), or null. Shallow scan — it's a direct child.
func _find_talkable() -> Talkable:
	for c in get_children():
		var t := c as Talkable
		if t != null:
			return t
	return null

## FNV-style hover greeting — facade onto NpcVoice. Called from player.gd when the crosshair first lands on
## an idle, non-hostile NPC.
func greet() -> void:
	if _voice != null:
		_voice.greet()

## Speak a one-off bark via the in-game TTS (SpeechTts) — POSITIONAL, coming from this NPC and routed through
## the Voice bus, in the Talkable's VoiceData voice when set. Interrupts any prior bark; a no-op while dead.
## SpeechTts gates on Settings.tts_enabled and tracks the source so only OUR death cuts our shout.
func _speak_bark(text: String, voice: VoiceData) -> void:
	if _dead:
		return  # dead enemies don't talk
	SpeechTts.speak_bark(global_position, text, voice, self)

## Pulse the talking presentation — the head-bob + Tomodachi mouth-flap on this NPC's BodyModelSwap — for
## `seconds`, the length of the utterance. Called whenever the NPC speaks: a dialogue line (DialogueManager
## -> note_speaking) or a bark (_emit_bark). No-op for an NPC with no BodyModelSwap / talk_for surface.
func note_speaking(seconds: float) -> void:
	var swap := _find_body_swap()
	if swap != null and swap.has_method(&"talk_for"):
		swap.call(&"talk_for", seconds)

## Stop the talking presentation (head-bob + mouth) NOW, even if the last utterance's estimated duration hasn't run
## out. Called by DialogueManager the instant this NPC is no longer delivering a line — the response menu opened, or
## the conversation ended — so its head stops bobbing while the player reads the choices / as it returns to idle,
## instead of coasting on the leftover estimate. Duck-typed onto the BodyModelSwap like note_speaking; no-op without one.
func note_speaking_stop() -> void:
	var swap := _find_body_swap()
	if swap != null and swap.has_method(&"stop_talking"):
		swap.call(&"stop_talking")

## The human player (the bark's listener), NOT a companion — companions join the &"Player" group for
## enemy targeting (#3), so pick the group member that is NOT an NPC.
func _real_player() -> Node3D:
	return Groups.human_player(get_tree())  # M6: the one home for the human-vs-companion filter (was a local scan)

## Facade onto NpcBarkUi.show_text (the head speech bubble). No-op off-tree (no _bark_ui until _build_components).
func _popup_text(text: String) -> void:
	if _bark_ui != null:
		_bark_ui.show_text(text)

## Facade onto NpcBarkUi.clear: drop any lingering bark bubble (on entering dialogue) AND reset the no-overlap gate.
func _clear_bark_bubble() -> void:
	if _bark_ui != null:
		_bark_ui.clear()
	_bark_until_msec = 0

## Facade onto NpcBarkUi.show_icon — pop a billboarded head icon (the alert "!" / turn-hostile cue). follow=true
## tracks our movement; follow=false parents to the tree root so the cue survives our death. No-op off-tree, and
## callable cross-NPC (saved._popup_icon) since the host facade delegates to that NPC's own _bark_ui.
func _popup_icon(tex: Texture2D, follow: bool = false, extra_y: float = 0.0) -> void:
	if _bark_ui != null:
		_bark_ui.show_icon(tex, follow, extra_y)

## Lock-on telegraph (wired to Perception.just_alerted in _build_perception): schedule the charge sting the
## INSTANT we lock on, before we're necessarily in engage range — the range-independent cue just_alerted was
## always meant to drive. The per-shot _on_aim calls in _act_alerted still telegraph subsequent shots once we're
## in range; on a long run-in you get two cues (lock-on, then the first in-range shot), and when we lock on while
## ALREADY in range the aim_cooldown_ms throttle inside _on_aim collapses them to one. Ranged-only: melee/fists
## wind up silently by design, so they must not sting here. FLEE-mute, the throttle, and the
## off-tree _audio_cues null-guard are all handled inside _on_aim / _physics_process.
##
## READINESS-GATED: telegraph only a REAL imminent shot, never a reload. A combatant that locks on with an EMPTY
## clip (or one mid-reload/swap) can't fire yet — _act_alerted's can_shoot already withholds the per-shot sting
## during a reload, and stinging on the bare lock-on edge would falsely warn of an incoming shot the enemy can't
## take (the "it charged at me but was only reloading" tell). Require a LOADED, ready gun; once the reload
## finishes, _act_alerted's _on_aim re-stings as the real wind-up begins.
func _on_locked_on() -> void:
	if _can_fight_with_gun() and _current_weapon_uses_ranged_attack_telegraphs() \
			and not _weapon.is_busy() and _weapon.current_ammo > 0:
		_on_aim()

## Play the sniper charge sting from this NPC's position when it locks on to fire.
func _on_aim() -> void:
	if threat_response == ThreatResponse.FLEE:
		return  # fleers never aim or charge a shot, so no sniper-charge sting
	var now := Time.get_ticks_msec()
	if now - _last_aim_msec < GameSettings.npc_bark.aim_cooldown_ms:
		return
	_last_aim_msec = now
	# Capture whether we're locking onto the PLAYER right NOW (not 0.1s later when the sting actually plays):
	# in mixed combat the target can flicker in that window, which would otherwise drop the sting to the
	# near-silent vs-NPC volume — reading as "the charge sound didn't play".
	_aim_targeting_player = is_instance_valid(_target) and _target.is_in_group(Groups.PLAYER)
	# Schedule the charge sting a beat (AIM_SFX_DELAY) later instead of the same frame as the shot —
	# playing it instantly blurs the gunshot and the charge-up together. _physics_process fires it.
	_aim_sfx_delay = GameSettings.npc_bark.aim_sfx_delay

func _build_nav() -> void:
	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.5
	_nav.target_desired_distance = 1.0
	# RVO avoidance: NPCs route AROUND each other + dynamic obstacles (a thrown crate carries a NavBlocker AVOID)
	# instead of bumping. apply_velocity feeds this ONLY while actively moving (idle NPCs report stationary), so it
	# steers cleanly without the idle jitter the first attempt had. radius matches the capsule.
	_nav.avoidance_enabled = true
	_nav.radius = 0.6
	_nav.height = 1.9
	_nav.neighbor_distance = 6.0
	_nav.max_neighbors = 8
	_nav.max_speed = 12.0
	_nav.velocity_computed.connect(_on_avoidance_velocity)
	add_child(_nav)

## Build the Locomotor drop-in in DRIVEN mode and hand it OUR NavigationAgent3D (built by _build_nav just before this),
## so path queries + RVO run on the single agent CompanionFollow / soak read as host._nav — never a second agent. Driven
## (drive_body=false) => Locomotor only COMPUTES; apply_velocity stays the sole move_and_slide writer. face_travel=false
## => npc.gd's _face_yaw stays the sole facer (Locomotor's _face uses a different curve and would fight body.rotation).
## ORDERING INVARIANT: this MUST run AFTER _build_nav (so _nav exists to inject) — moving it earlier would make Locomotor
## build a SECOND agent, double-registering RVO. The _ready call site enforces this.
func _build_locomotor() -> void:
	_locomotor = Locomotor.new()
	_locomotor.external_nav = _nav
	_locomotor.drive_body = false
	_locomotor.face_travel = false
	_locomotor.enable_step_up = true  # NPCs auto-step stair risers (the Player has its own step-up; a bare mob leaves this off)
	add_child(_locomotor)

## RVO result for THIS frame's requested velocity (the collision-free steering). apply_velocity feeds the agent
## our intended velocity and adopts this while moving; in the open it ≈ the request, so it's a no-op with nothing near.
func _on_avoidance_velocity(safe_velocity: Vector3) -> void:
	_avoid_velocity = safe_velocity
	_avoid_ready = true

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return  # @tool: the AI tick never runs in the editor
	# Cutscene control overrides ALL AI: a CutsceneActor has the wheel, so the brain (perception / GOAP /
	# targeting) is suppressed and only the scripted walk/face + gravity run. CutscenePlayer._finish always
	# releases control, so the NPC can never get stuck frozen.
	if _cutscene_control:
		_tick_cutscene_movement(delta)
		super._physics_process(delta)  # gravity + locomotion consume _desired_velocity
		return
	# Keep the gun stance in step with combat: drawn while fighting, holstered (and topped up) out of
	# combat. Uses last frame's perception state — a 1-frame draw lag is imperceptible (first shot is
	# a full shot-interval away anyway), and it keeps this to a single call site.
	if _weapon != null:
		_reconcile_weapon_stance()
	# Pre-talk approach overrides ALL other AI: while walking up to the player to be framed for
	# dialogue, drive only the approach + locomotion, nothing else. This runs to completion BEFORE
	# DialogueManager.start freezes us — once frozen this loop stops.
	if _talk != null and _talk.is_approaching():
		_talk.tick(delta)
		super._physics_process(delta)  # gravity + locomotion move (consumes _desired_velocity)
		return
	# A charge sting scheduled by _on_aim plays a short beat AFTER the shot (so it doesn't blur into the
	# gunshot). Playback is still ranged-gated so a disarm / melee swap cannot leak a stale charge sound.
	if _aim_sfx_delay >= 0.0:
		_aim_sfx_delay -= delta
		if _aim_sfx_delay < 0.0 and _audio_cues != null \
				and _current_weapon_uses_ranged_attack_telegraphs():
			_audio_cues.play_charge_sting(_aim_targeting_player)
	_desired_velocity = Vector3.ZERO  # default: hold position; states below may drive it
	# Bleed the fire charge back down every frame by default; _act_alerted overcomes this only while it
	# has a clear, in-range shot. So whenever the enemy can't see or can't hit you, its wind-up decays
	# toward zero (break line of sight to reset the shot) instead of freezing mid-charge.
	_fire_timer = minf(_shot_interval(), _fire_timer + delta)
	# Re-acquire on a throttle, or immediately when a target we currently HOLD just went invalid (it died,
	# walked out of sight_range, or turned non-hostile). _should_immediately_retarget() is the O(1) pre-check: it
	# fires the same-frame re-acquire ONLY for a held-but-invalid target — a target-LESS NPC (most of the idle
	# cast) returns false and re-scans on the timer alone, so it never pays the full O(n) _acquire_target group
	# scan every physics frame (a new foe is still picked up within retarget_interval). A foe that FREES mid-fight
	# leaves is_instance_valid false, so re-acquisition waits for the timer too — the no-target branch below still
	# runs the same frame. (C8)
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or _should_immediately_retarget():
		_acquire_target()
		_retarget_timer = GameSettings.npc_ai.retarget_interval
	# Re-tint the rim if our attitude changed with no provoke (a faction-rep shift — Reputation has
	# no signal, so it must be polled). O(1) per frame; the material only rebuilds on a real change.
	# The NpcOutline child holds the last-tinted Kind + does the has_outline / _flash_material guard.
	if _outline != null:
		_outline.poll()
	if not is_instance_valid(_target):
		# No enemy: SENSE the environment first (stealth distraction + body-discovery), THEN let the planner act.
		# _react_unaware only senses now — on a noise/body it points Perception at it (-> INVESTIGATING); when
		# nothing applies it FORGETs any stale alert (so a just-lost target can't mislead the no-target tick into
		# targetless combat). The executor then owns the response: GoapActionSearch walks the INVESTIGATING
		# spot (off last_known_position — no target needed), else the Hold idle floor (companion-follow / wander /
		# return-to-post). So the planner drives ALL decisions, combat and idle alike.
		# FIRST, settle the give-up barks: an engagement that ended by the target VANISHING (it died / freed / fled
		# out of range) reaches this branch, not the has-target perception-drop path — so the latch reset must run
		# HERE too, or _saw_combat/_was_aware leak into the NEXT engagement and mis-fire a phantom combat-over bark.
		# No-op unless we were actually aware (the helper guards), so an already-idle NPC pays nothing. (C36)
		_settle_engagement_barks()
		_react_unaware(delta)
		if _executor != null:
			_executor.tick(self, delta)
		_react_music(delta)  # passive: turn to FACE + comment on a nearby playing radio (body yaw only, no travel). AFTER the executor so the face overrides the idle facing
		_hide_laser()
		super._physics_process(delta)
		return
	# We have a real target now: clear the no-target distraction flag so a noise/body investigation that got
	# PROMOTED into combat doesn't leave _was_distracted armed and mutter a phantom "lost interest" later.
	_was_distracted = false
	# Hostility gate: _acquire_target only ever returns a target we'd engage, so this stays true while
	# engaged; it cleanly idles a non-hostile NPC with no peers. _treats_as_enemy == is_hostile_to for a
	# non-following NPC, and additionally lets a COMPANION sense/lock the unaligned-hostile foe it's
	# defending its leader against (which is_hostile_to alone would gate out).
	_perception.is_hostile = _treats_as_enemy(_target)
	_perception.sense(delta)
	# Give-up barks: track that we NOTICED a threat (any non-UNAWARE state) and, separately, that we fully
	# ENGAGED it (ALERTED). On the return to idle, a fighter that engaged gives the combat-over taunt; one
	# that only noticed / searched (never ALERTED) gives the softer "lost interest" line.
	if _perception.state == Perception.State.ALERTED:
		_saw_combat = true
		_was_aware = true
		if not _alerted_allies:
			_alerted_allies = true               # GA-1: latch — broadcast ONCE per engagement (first-hand contact)
			_alert_allies(_aim_point())          # tell same-faction allies in radius to converge (off unless alert_radius > 0)
	elif _perception.state != Perception.State.UNAWARE:
		_was_aware = true  # DETECTING / INVESTIGATING — noticed something but hasn't locked on
		if _perception.state == Perception.State.INVESTIGATING:
			_try_search_bark()  # lost the player's trail -> mutter while hunting (co-occurs with the HUD [CAUTION])
	else:
		# Perception fell back to UNAWARE while a target is still in range: the engagement is over — fire the
		# give-up bark + clear the latches through the SHARED settle helper (its own _was_aware guard preserves
		# the old `elif _was_aware:` behaviour exactly). The no-target branch above calls the same helper, so a
		# target that dies/frees mid-fight can't leak _saw_combat/_was_aware into the next engagement. (C36)
		_settle_engagement_barks()
	# THE GOAP SEAM: the planner-driven executor is the sole decision layer. Reached ONLY with a valid _target
	# (the no-target case returned above), so the executor only ever
	# decides among target-valid states — DETECTING / ALERTED / INVESTIGATING (the narrow UNAWARE-with-target
	# window falls to the Idle floor). The library (_build_goap_actions/_goals) covers the full dispatch —
	# Idle/Detect/Investigate/Engage — and FLEE is the Survive goal + GoapActionFlee, which outranks Engage so a
	# fleer runs rather than fights. The null guard keeps a partially-constructed instance safe; _executor is
	# built for every NPC in _build_components, so it's non-null on any in-tree NPC.
	if _executor != null:
		_executor.tick(self, delta)
	# Music reaction ALSO runs on the has-target branch: _acquire_target locks the nearest foe by pure PROXIMITY
	# (no LOS/perception gate — NpcTargeting), so a HOSTILE NPC holds the player as _target the instant it's in
	# sight_range, even while it's still perception-UNAWARE (hasn't actually noticed them). Without this a raider
	# lounging by its radio would NEVER react once the player walked into range (it'd sit in the combat branch that
	# skips music). _react_music self-gates on state == UNAWARE, so it reacts only in that not-yet-noticed window and
	# snaps to null the moment perception escalates to DETECTING/ALERTED — the raider vibes, then fights. Runs AFTER
	# the executor (its face overrides the idle facing), mirroring the no-target branch.
	# Distraction sensing ALSO runs here (same proximity-target-while-UNAWARE reason as _react_music): a decoy or
	# hidden body must register while a hostile holds the player in range but hasn't noticed them yet (P0-4).
	_react_distraction(delta)
	_react_music(delta)
	super._physics_process(delta)  # gravity + blast + locomotion move (uses _desired_velocity)

## Settle the give-up bark bookkeeping at the END of an engagement — the ONE place the combat-over / lost-interest
## call-out fires AND the ONE place the engagement latches (_saw_combat / _was_aware / _alerted_allies) clear. Called
## from BOTH combat give-up paths: the perception-drop path (a still-valid target, but perception fell back to
## UNAWARE) AND the target-lost path (the target died/freed and the no-target branch runs). Centralising it here is
## the C36 fix: previously ONLY the has-target elif cleared the latches, so a target that FREES mid-fight skipped the
## reset and left _saw_combat/_was_aware latched — which then mis-fired a spurious "combat over" bark on the FIRST
## frame of the NEXT engagement (a proximity target acquired while perception was still UNAWARE). The internal
## _was_aware guard makes this a no-op unless we actually noticed a threat, so it fires at most once per engagement;
## the bark facades null-guard on _voice, so it's side-effect-free off-tree and when un-voiced.
func _settle_engagement_barks() -> void:
	if not _was_aware:
		return
	if _saw_combat:
		_try_combat_end_bark()   # a fighter that ALERTED gives the combat-over taunt
	else:
		_try_lost_interest_bark()  # only noticed / searched (never ALERTED) -> the softer "lost interest" line
	_saw_combat = false
	_was_aware = false
	_alerted_allies = false  # GA-1: engagement over — re-arm the ally broadcast for the next one

## No-enemy environmental SENSING (the stealth distraction + body-discovery feeler): with NO acquired target,
## scan the &"noise" channel (if hearing_initiates) and bodies (if body_discovery) and, on a stimulus, point
## Perception at it (-> INVESTIGATING) + age/expire the give-up clock. It NO LONGER walks: the GOAP executor's
## Investigate action drives the move+search off the INVESTIGATING state this sets, so stealth investigation is a
## planner decision. When NO sensing applies (both features off, or we're
## dead / fleeing / a follower / have no Perception) it FORGETs any stale alert from a just-lost target, so the
## no-target executor picks the Hold idle floor rather than a targetless combat action. In-tree (group scans +
## LOS) -> playtest-verified; the pure gates (Corpse.noticeable, NoiseSource.audible) carry the unit tests.
func _react_unaware(delta: float) -> void:
	_alerted_allies = false  # GA-1: no acquired target here -> any engagement is over, so re-arm the ally broadcast
	var noise_on: bool = _noise_initiates_on() and _perception != null and _perception.hearing
	var corpse_on: bool = _body_discovery_on() and _perception != null
	if _perception == null or _dead or hp <= 0.0 or is_fleeing() or is_following() or (not noise_on and not corpse_on):
		# No ambient sensing. A SCRIPTED investigate() (investigate()) winds down naturally over forget_time —
		# sense() with no target only decays the clock while the executor walks/searches the spot. Any OTHER
		# leftover (a stale ALERTED from a just-lost target) is a phantom: clear it instantly so the no-target
		# executor selects the Hold idle floor, not a targetless combat action.
		if _perception != null:
			# Wind an alert DOWN naturally (ALERTED coasts the pursuit grace, then INVESTIGATING drains over forget_time)
			# instead of HARD-forgetting it, for two cases: a scripted investigation, AND a FLEEING NPC. A fleer that
			# hard-forgets the frame it loses its attacker (attacker out of sight_range, or simply behind the running NPC)
			# drops to UNAWARE, which makes its Survive/Flee goal infeasible — so it stops dead and strolls calmly back
			# past its would-be killer. Decaying keeps it scared while it runs, then calms over forget_time (raise the
			# NPC's forget_time to make fear last longer). A non-fleeing, non-scripted leftover still hard-forgets below.
			var decay_not_forget := (_scripted_investigating and _perception.state == Perception.State.INVESTIGATING) \
					or (is_fleeing() and _perception.state != Perception.State.UNAWARE)
			if decay_not_forget:
				_perception.is_hostile = false
				_perception.sense(delta)
				if _perception.state != Perception.State.INVESTIGATING:
					_scripted_investigating = false
			else:
				_scripted_investigating = false
				_perception.forget()
		return
	# Age the give-up clock EVERY frame: sense() with no target reports nothing from either sense, so it only
	# winds an in-progress investigation down toward UNAWARE (a brand-new or refreshed one stays put below); it
	# also decays a stale alert from a just-lost target the same way (so it can't linger as a phantom combat state).
	_perception.is_hostile = false
	_perception.sense(delta)
	# (Re)point the investigation at the strongest LIVE stimulus (throttled scan). Shared with the has-target
	# branch via _react_distraction so a decoy/body registers while a hostile holds the player as a proximity
	# target but hasn't actually noticed them (UNAWARE) — see _scan_distractions / _react_distraction (P0-4).
	_scan_distractions(delta, noise_on, corpse_on)
	# Investigating now -> the executor's GoapActionSearch walks + searches off last_known_position (same
	# move it always did); we only keep the give-up bookkeeping so we mutter "must've been nothing" on expiry.
	if _perception.state == Perception.State.INVESTIGATING:
		_was_distracted = true
		_try_search_bark()  # mutter "where are you?" while hunting (the bark cooldown paces it)
	elif _was_distracted:
		_was_distracted = false
		_try_lost_interest_bark()  # the investigation just expired with nothing found

## The throttled &"noise"/body-discovery scan: (re)point Perception at the strongest LIVE stimulus. Noise first (an
## ongoing sound outranks a static body); a heard source re-points each scan it persists (investigate_point refreshes
## the clock) so we track a moving decoy. Shared by _react_unaware (no-target) and _react_distraction (has-target,
## UNAWARE) so a thrown decoy / hidden body registers in BOTH branches. Assumes _perception != null (both callers gate).
func _scan_distractions(delta: float, noise_on: bool, corpse_on: bool) -> void:
	_distraction_scan_t -= delta
	if _distraction_scan_t <= 0.0:
		_distraction_scan_t = GameSettings.npc_ai.distraction_scan_interval
		if noise_on:
			var src := _loudest_noise()
			if src != null:
				# alerting "!" — the player wants to see the lure land; seed the search ring from how LOUD it was
				# (a crash searches a wider area than a faint step), scaled by SearchSettings.noise_radius_scale.
				_perception.investigate_point(src.global_position, true, src.radius * GameSettings.search.noise_radius_scale)
		# Corpse discovery is PERSISTED (_discover_corpse -> GameState.mark_corpse_discovered) — so gate it on a
		# GENUINELY idle NPC (UNAWARE), not merely "not INVESTIGATING": a stale DETECTING/ALERTED beat from a
		# just-lost target must NOT permanently mark a body discovered with zero real investigation. sense() (called
		# by both callers this frame) decays that stale state toward UNAWARE, so discovery is DEFERRED (not lost)
		# until the NPC truly stands down. Noise (above) also outranks a body: if it set INVESTIGATING this scan,
		# state != UNAWARE, so the body waits for the noise to wind down. (C7)
		if _perception.state == Perception.State.UNAWARE and corpse_on:
			var corpse := _nearest_visible_corpse()
			if corpse != null:
				_discover_corpse(corpse)

## Distraction sensing for the HAS-target branch. _acquire_target locks the nearest foe by pure PROXIMITY (no
## LOS/perception gate — NpcTargeting), so a hostile holds the player as _target the instant they enter sight_range
## even while perception-UNAWARE. Without this, thrown decoys and hidden bodies did NOTHING exactly when the player
## was in range (P0-4). Mirrors _react_music: self-gates on state == UNAWARE, so a decoy only distracts a not-yet-
## noticing guard (escalating it to INVESTIGATING peels it toward the lure via GoapActionSearch); a foe it's already
## detecting/alerted-on always wins. sense() already ran this frame (has-target branch) — do NOT call it again here.
func _react_distraction(delta: float) -> void:
	if _perception == null or _dead or hp <= 0.0 or is_fleeing() or is_following():
		return
	if _perception.state != Perception.State.UNAWARE:
		return
	var noise_on: bool = _noise_initiates_on() and _perception.hearing
	var corpse_on: bool = _body_discovery_on()
	if noise_on or corpse_on:
		_scan_distractions(delta, noise_on, corpse_on)

## The loudest &"noise" source reaching us — facade onto NpcSenses (npc_senses.gd). Null off-tree (no _senses).
func _loudest_noise() -> NoiseSource:
	return _senses.loudest_noise() if _senses != null else null

## Passive MUSIC reaction: a calm, idle NPC — friendly OR hostile — that can HEAR a playing radio TURNS TO FACE it
## (a visible "look at the radio" beat) and comments ONCE on the song/playlist quality. Ships ON
## (GameSettings.npc_ai.music_reactions). Called from BOTH the no-target idle path AND the has-target branch (a
## hostile NPC locks the player as a proximity target the moment it's in sight_range, so gating on "no target" would
## hide the reaction the instant the player walked up); it self-gates on _perception.state == UNAWARE, so it only
## reacts while genuinely not-yet-noticing, and a foe or noise it's chasing always wins (it never abandons its post
## to walk over — the turn is a stationary body yaw, no locomotion). The radio SCAN is throttled like the distraction
## scan, but the FACE runs EVERY frame off the cached _attending_radio (the head-look's lowest-priority target) so
## the turn eases smoothly; it yields to an active schedule/patrol route (a guard mid-patrol keeps walking,
## head-tracking only). The bark self-throttles. In-tree only.
func _react_music(delta: float) -> void:
	if not GameSettings.npc_ai.music_reactions or _dead or hp <= 0.0 or is_following():
		_attending_radio = null
		return
	# Only a relaxed NPC enjoys music -- detecting / investigating / alerted all outrank it.
	if _perception != null and _perception.state != Perception.State.UNAWARE:
		_attending_radio = null
		return
	# (Re)scan for the nearest audible radio on the distraction-scan throttle; the FACE below + the one-shot comment
	# run off the cached _attending_radio, so a between-scan frame keeps facing (NO early-return before the turn).
	_music_scan_t -= delta
	if _music_scan_t <= 0.0:
		_music_scan_t = GameSettings.npc_ai.distraction_scan_interval
		var radio := _nearest_audible_radio()
		_attending_radio = radio
		if radio == null:
			_music_commented_radio = null  # out of range / switched off -> a fresh comment when we next attend one
		elif radio != _music_commented_radio:
			_music_commented_radio = radio
			react_music(MQ.tier(str(radio.call(&"quality_text")),
				GameSettings.npc_ai.music_tier_meh, GameSettings.npc_ai.music_tier_good, GameSettings.npc_ai.music_tier_great))
	# Turn the BODY to face the radio we're enjoying and hold still to listen — the visible "look at the radio" the
	# head-look (cone-clamped, so a radio BEHIND us never gets tracked) can't deliver on its own. Runs AFTER the idle
	# executor (so it overrides the wander/post facing) but YIELDS to a directed schedule/patrol route, so attending a
	# radio never freezes a guard mid-patrol. Gated by music_turn_body so a designer can keep the reaction head-only.
	# INTENDED SIDE EFFECT (design-signed-off): Perception inherits the body transform, so its view cone is the body's
	# forward. A HOSTILE posted sentry that turns to face the radio therefore also swings its DETECTION cone off its
	# authored watch spot — a deliberate "distracted by music" stealth opening the player can create by switching on a
	# radio behind a guard. This is NOT a player-awareness telegraph (the turn keys on _attending_radio, a radio, never
	# on _target / the player). The only opt-outs are global: music_turn_body off (all reactions head-only) or
	# music_reactions off (no reactions at all).
	if GameSettings.npc_ai.music_turn_body and is_instance_valid(_attending_radio) and not _on_directed_route():
		_desired_velocity = Vector3.ZERO  # stop roaming — stand and enjoy the song
		_face_point(_attending_radio.global_position, delta)

## The nearest PLAYING radio audible to us — facade onto NpcSenses. Null off-tree (no _senses).
func _nearest_audible_radio() -> Node3D:
	return _senses.nearest_audible_radio() if _senses != null else null

## Nearest fresh, undiscovered body this NPC can SEE — facade onto NpcSenses. Null off-tree (no _senses).
func _nearest_visible_corpse() -> Corpse:
	return _senses.nearest_visible_corpse() if _senses != null else null

## React to discovering a body: CLAIM it (so the neighbourhood doesn't pile onto one corpse), CALL OUT
## ("Hey — a body!"), and INVESTIGATE the spot QUIETLY. Reached from the no-target distraction pass
## (_react_unaware). The bark fires FIRST and the investigate is non-alerting (investigate_point's
## `alerting=false`), so a corpse never mislabels as an enemy "!" sighting and the combat "Enemy spotted!"
## detection bark can't win the bark cooldown and swallow the body line.
func _discover_corpse(c: Corpse) -> void:
	c.discovered = true
	GameState.mark_corpse_discovered(c.save_key())
	_try_check_body_bark()
	# quiet (NOT a fire-ready ALERTED); a body carries no radius of its own, so seed the search from how far the
	# NPC can see (the range it spotted the body at), scaled by SearchSettings.corpse_radius_frac.
	_perception.investigate_point(c.global_position, false, _perception.sight_range * GameSettings.search.corpse_radius_frac)

## Alerted (combatant only) ARMED body — thin facade onto NpcCombat (H2). The GOAP FireArmed action calls this on the
## host; the whole pursue/aim/telegraph/reload/charge/fire/dodge cluster lives in npc_combat.gd. No-op off-tree /
## before _build_components (no _combat yet).
func _act_alerted(delta: float) -> void:
	if _combat != null:
		_combat.act_alerted(delta)

## Unarmed melee (combatant with no usable gun, OR a civilian brawler) body — thin facade onto NpcCombat (H2). The
## GOAP FireUnarmed action calls this on the host; the close-to-reach / wind-up / punch cluster lives in npc_combat.gd.
func _act_unarmed(delta: float) -> void:
	if _combat != null:
		_combat.act_unarmed(delta)

# --- Locomotion: NavigationAgent3D pathing composed with the inherited knockback ---
## Upward velocity (m/s) for a hop to land `climb` metres above us. `base_velocity` (the jump_velocity export) is the
## MINIMUM pop; a higher target gets a stronger launch sized to reach its height plus a small apex clearance, so the
## NPC arrives onto the player's floor instead of stopping just short under it. Pure + static so it's unit-tested
## off-tree; a non-positive climb or g <= 0 (a zero-gravity area) falls back to the base pop, never dividing by zero.
static func jump_velocity_for_climb(climb: float, grav: float, base_velocity: float) -> float:
	return Locomotor.jump_velocity_for_climb(climb, grav, base_velocity)

## Pure nav-hop gate: caller supplies a vertical climb (usually floor-to-floor) and a horizontal distance to the
## step/raised target, plus the current grounded/cooldown state. There is NO upper climb bound — the NPC scales its
## launch to reach you (jump_velocity_for_climb), so a player perched up high is jumped AT, not given up on; a hop
## that still can't mount converts to give-up-and-hold via _update_stuck. Kept static so tests can pin the "clearable
## nearby climb yes, same-floor no, too-far no, civilian no" contract without needing a live NavigationAgent3D.
static func should_nav_hop(allow_hop: bool, hop_velocity: float, on_floor: bool, jump_cooldown: float, climb: float, horizontal_distance: float) -> bool:
	return Locomotor.should_nav_hop(allow_hop, hop_velocity, on_floor, jump_cooldown, climb, horizontal_distance)

static func should_stuck_recovery_hop(allow_hop: bool, hop_velocity: float, on_floor: bool, jump_cooldown: float, stuck_time: float, intended_speed: float) -> bool:
	return Locomotor.should_stuck_recovery_hop(allow_hop, hop_velocity, on_floor, jump_cooldown, stuck_time, intended_speed)

## Bottom Y of a character capsule if one is available. The player target passed into combat pursuit is its
## PlayerCollisionShape (a CollisionShape3D), while an NPC's own capsule is a direct child; support both forms.
## Falling back to fallback_y keeps generic Vector3 targets (patrol/search markers) on the old centre-point math.
static func collision_bottom_y(node: Node3D, fallback_y: float) -> float:
	return Locomotor.collision_bottom_y(node, fallback_y)

## Path toward `target` — now a SHELL onto the Locomotor nav brain (Phase B). `allow_hop` enables the combat nav-hop
## (vault onto a higher unreachable spot): pass true ONLY from threatening-pursuit callers (combat close-in, GOAP
## search, companion-follow); it defaults OFF so idle/wander/patrol/schedule/talk/scavenge/cutscene NPCs never pogo at
## a target above them (a civilian shouldn't pogo at you). Returns true while still travelling, false when arrived /
## given-up-hold — the exact bool the 9 callers (+ _tick_cutscene_movement) branch on.
func _move_toward(target: Vector3, allow_hop: bool = false, hop_target: Node3D = null) -> bool:
	# SHELL onto the Locomotor nav brain (Phase B). Locomotor owns the path-stepping, off-mesh recovery, straight-line
	# charge through an unreachable target, and the combat nav-hop (it writes body.velocity.y + arms its own _jump_cd /
	# _hopping). It writes THIS frame's steering into its desired_velocity, which we copy into _desired_velocity so
	# apply_velocity (the sole move_and_slide writer) consumes it exactly as before. Off-tree / pre-build -> false.
	if _locomotor == null:
		return false
	var moving := _locomotor.drive_move_to(target, allow_hop, hop_target)
	_desired_velocity = _locomotor.desired_velocity
	return moving

func _face_travel(delta: float) -> void:
	# Face where the body ACTUALLY moves, not the pre-avoidance nav request. While RVO deflects us around another agent,
	# or the anti-stuck side-step veers us along a wall, the body slides along _avoid_velocity / _unstick_dir while
	# _desired_velocity still points at the raw path node — facing that reads as a crab-walk / moonwalk (torso into the
	# wall while sliding sideways). velocity.x/z is this frame-1's post-RVO, post-unstick, eased result (a 1-frame lag is
	# invisible under the smoothed turn). Fall back to the nav request only when nearly stationary (move start / held).
	var actual := Vector2(velocity.x, velocity.z)
	if actual.length() > 0.15:
		_face_point(global_position + Vector3(actual.x, 0.0, actual.y), delta)
	elif _desired_velocity.length_squared() > 0.0001:
		_face_point(global_position + _desired_velocity, delta)

## Null-safe facades onto the Locomotor's blocked/stuck state, so drop-in components (GoapActionSearch, PatrolBehavior)
## read it without hard-referencing the Locomotor (keeps the component <-> NPC coupling loose + off-tree safe).
## _move_struggling: fighting a blocker it can't route past (accruing net-progress failures or in the give-up hold) —
## GoapActionSearch stops refreshing the investigate give-up clock while true, so it can expire on an unreachable spot.
func _move_struggling() -> bool:
	return _locomotor != null and _locomotor.is_struggling()

## _move_holding: in the post-give-up HOLD (blocked too long, standing still for a beat) as opposed to having ARRIVED —
## PatrolBehavior uses it to wait on the current waypoint instead of misreading the hold as a reached-post advance.
func _move_holding() -> bool:
	return _locomotor != null and _locomotor.is_holding()

## Non-combat idle update — facade onto NpcLocomotion (companion-tail -> wander -> return-to-post / hold).
## No-op off-tree (no locomotion child), matching the old behaviour (no follow / wanders / post there).
func _idle(delta: float, return_to_post: bool) -> void:
	if _locomotion != null:
		_locomotion._idle(delta, return_to_post)

## True while a DIRECTED idle route (an active ScheduleBehavior daily routine or PatrolBehavior path) is driving
## this NPC's idle movement — facade onto NpcLocomotion. The music-reaction body-turn (_react_music) yields to it so
## attending a radio never freezes a guard mid-patrol / an NPC mid-schedule (a plain wanderer / posted NPC has no
## route, so it DOES stop to face the radio). False off-tree / with no locomotion child.
func _on_directed_route() -> bool:
	return _locomotion.has_active_route() if _locomotion != null else false

## A random point on the disc of radius wander_radius around spawn (sqrt keeps it uniformly spread,
## not clustered at the centre).
func _pick_wander_point() -> Vector3:
	var ang := randf() * TAU
	var r := sqrt(randf()) * wander_radius
	var p := _spawn_position + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	return _snap_to_navmesh(p, wander_radius + 2.0)

## Snap a COMPUTED destination to the nearest point on the navmesh so an NPC never heads for an unreachable spot (off
## a ledge / on a disconnected island) and grinds toward it — the main cause of idle pacing even on a good bake.
## Returns the input UNCHANGED off-tree / with no agent / no valid map (keeps the off-tree unit tests pure), or when
## the nearest mesh point is implausibly far (> max_drift — a near-empty map can return its origin) so we degrade
## rather than teleport. Used by wander, flee, and return-to-post (all computed, not designer-authored, targets).
func _snap_to_navmesh(p: Vector3, max_drift: float) -> Vector3:
	if _nav == null or not is_inside_tree():
		return p
	var nav_map := _nav.get_navigation_map()
	# is_valid() alone isn't enough: querying a map BEFORE its first synchronization errors. iteration_id 0 = not yet
	# synced (early frames, or freshly (re)baked), so skip the query until the map is ready.
	if not NavigationUtils.is_nav_map_ready(nav_map):
		return p
	var nearest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, p)
	return nearest if nearest.distance_to(p) <= max_drift else p

## Our origin's height above the floor right now (via a short down-ray), so a follow-teleport can lift the
## snapped navmesh point by the same amount and land the body on the surface instead of half-buried.
## Falls back to 1.0 (~the 2 m capsule's half-height) if the ray finds no floor. World-guarded for tests.
func _height_above_floor() -> float:
	var world := get_world_3d()
	if world == null or not world.space.is_valid():
		return 1.0
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 3.0)
	query.exclude = [self]
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 1.0
	return maxf(0.0, global_position.y - (hit.position as Vector3).y)

## Flee — facade onto NpcLocomotion (run flee_distance ahead of the threat, never fire).
func _act_flee(delta: float) -> void:
	if _locomotion != null:
		_locomotion._act_flee(delta)

# --- Stair step-smoothing (cosmetic): see _smooth_stair_step. State is per-life, so reset_for_reuse clears it. ---
const STEP_SMOOTH_MAX := 0.6      ## clamp the eased visual offset — a whole flight reads as one glide, never a floor-clipping dip
const STEP_SMOOTH_DECAY := 14.0   ## exponential ease-rate of the visual step offset back to zero (higher = snappier catch-up)
var _step_smooth_y: float = 0.0   ## current cosmetic Y offset on `mesh` (negative right after a riser snap, eases toward 0)
var _mesh_rest_y: float = 0.0     ## `mesh`'s authored local Y, captured once so the offset rides ON TOP of it
var _mesh_rest_captured: bool = false

## Locomotion + knockback: ease horizontal velocity toward the desired (nav) velocity — which also
## bleeds off a blast and brakes to a stop when idle (a target-less NPC has _desired_velocity ZERO,
## so this move_toward doubles as the knockback friction) — then add the decaying blast impulse and
## slide, with the same fall-damage tail as Character.
func apply_velocity() -> void:
	# move_and_slide needs a live physics space; bail when we're not in one (e.g. a unit
	# test instantiates the NPC outside a World3D yet still ticks _physics_process).
	if not _has_live_physics_space():
		return
	# Anti-stuck override (state now on the Locomotor): while escaping a blocker (flagged by Locomotor.update_stuck
	# last frame), steer ALONG it instead of pressing straight at the path point. Only when actually trying to move.
	var unstick_t: float = _locomotor._unstick_t if _locomotor != null else 0.0
	var unstick_dir: Vector3 = _locomotor._unstick_dir if _locomotor != null else Vector3.ZERO
	var drop_committing := _locomotor != null and _locomotor.is_drop_committing()
	if not drop_committing and unstick_t > 0.0 and unstick_dir.length_squared() > 0.0001 and Vector2(_desired_velocity.x, _desired_velocity.z).length() > 0.1:
		_desired_velocity = unstick_dir * _current_move_speed()
	var horizontal := Vector2(velocity.x, velocity.z)
	var desired_h := Vector2(_desired_velocity.x, _desired_velocity.z)
	# RVO avoidance: steer around other agents + dynamic obstacles. ONLY while actively moving and NOT mid
	# anti-stuck side-step — so idle/clustered NPCs report stationary (others route around them) without nudging
	# each other into a jitter, and the wall-slide isn't fought. Uses the previous frame's collision-free velocity
	# (1-frame lag; ≈ the request in the open, so it's a no-op with nothing nearby).
	if _nav != null and _nav.avoidance_enabled:
		if drop_committing:
			_nav.velocity = Vector3.ZERO  # ledge commit is deliberate; don't let RVO route around the rim
		elif desired_h.length() > 0.3 and unstick_t <= 0.0:
			_nav.velocity = Vector3(desired_h.x, 0.0, desired_h.y)
			if _avoid_ready:
				desired_h = Vector2(_avoid_velocity.x, _avoid_velocity.z)
		else:
			_nav.velocity = Vector3.ZERO  # idle/stuck -> report stationary; don't nudge neighbors (kills the idle shimmy)
	var rate := move_accel if is_on_floor() else air_accel
	horizontal = desired_h if drop_committing else horizontal.move_toward(desired_h, rate * get_physics_process_delta_time())
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	velocity += explosion_velocity
	var pre_move_velocity := velocity
	var was_grounded := is_on_floor()
	# STAIR STEP-UP (mirrors the Player's apply_velocity): a CharacterBody3D can't climb a vertical riser via
	# move_and_slide, so when the Locomotor has step-up on and we're grounded + not rising, first try to auto-step the
	# riser we're pressing into. A successful step IS this frame's move (skip the slide), so fall-damage / push are skipped
	# too. When step-up is off (default) has_step_locomotor is false and this is the old bare move_and_slide path.
	var has_step_locomotor := _locomotor != null and _locomotor.enable_step_up
	var can_step_up := has_step_locomotor and was_grounded \
			and pre_move_velocity.y <= Locomotor.STEP_UPWARD_VELOCITY_EPS
	var delta := get_physics_process_delta_time()
	if can_step_up and _locomotor.try_step_up(self, global_transform, pre_move_velocity, delta):
		pass  # stepped up in place of sliding
	else:
		move_and_slide()
		if is_on_floor() and not was_grounded:
			_apply_fall_damage(-pre_move_velocity.y)
		_push_interactables(pre_move_velocity)
		# Post-slide: a riser reached DURING the slide gets one more step-up try; failing that, catch a descending tread
		# so the body walks DOWN stairs instead of launching off each nosing.
		var stepped_after_slide := can_step_up and _locomotor.try_step_up(self, global_transform, pre_move_velocity, delta)
		if has_step_locomotor and not stepped_after_slide:
			_locomotor.try_step_down(self, pre_move_velocity)
	velocity -= explosion_velocity / blast_damp_divisor
	# Anti-stuck bookkeeping LAST — after move_and_slide (fresh slide-collision normals + is_on_floor) and after the
	# blast decay (so a still-live blast bails). Now on the Locomotor; it writes _unstick_t/_unstick_dir for next frame
	# and calls back into _note_stranded / _reset_stranded (which own our _stranded_cycles). No-op off-tree / pre-build.
	if _locomotor != null:
		_locomotor.update_stuck(self, get_physics_process_delta_time())
	# Cosmetic: ease the visual model over any riser step-up the body just snapped (only try_step_up snaps set last_step_rise,
	# and only when can_step_up ran this frame). Runs every frame so the offset also DECAYS when no step occurred.
	_smooth_stair_step(_locomotor.last_step_rise if (can_step_up and _locomotor != null) else 0.0, delta)

## Cosmetic stair step-smoothing — the NPC counterpart of the Player's CameraEffects.step_smooth. The Locomotor's
## step-up SNAPS the body up a riser instantly (nav + collision must be exact), so without this the visual `mesh`
## teleports up ~0.5 m per step: a steppy ratchet. We push the model DOWN by the snap the frame it happens (its WORLD
## position doesn't move), then ease that offset back to zero so the model GLIDES up to the new height. Purely visual;
## physics/nav already placed the body correctly. Clamped so a whole flight reads as one smooth rise, never a dip deep
## enough to clip the floor. No-op without a `mesh` (a bare / mesh-less NPC) — and cheap in the common no-step frame.
func _smooth_stair_step(rise: float, delta: float) -> void:
	if mesh == null:
		return
	if not _mesh_rest_captured:
		_mesh_rest_y = mesh.position.y  # the model's authored local Y; the offset rides on top of it
		_mesh_rest_captured = true
	if rise > Locomotor.STEP_MIN_DELTA:
		_step_smooth_y = clampf(_step_smooth_y - rise, -STEP_SMOOTH_MAX, STEP_SMOOTH_MAX)
	if _step_smooth_y == 0.0:
		return  # no active ease (the common case — no recent step)
	_step_smooth_y = lerpf(_step_smooth_y, 0.0, clampf(STEP_SMOOTH_DECAY * delta, 0.0, 1.0))
	if absf(_step_smooth_y) < 0.001:
		_step_smooth_y = 0.0  # settled: snap the residue and restore the exact rest Y below
	mesh.position.y = _mesh_rest_y + _step_smooth_y

## Anti-stuck / wall-slide + the give-up state machine MIGRATED to Locomotor (Phase B) — see Locomotor.update_stuck,
## called LAST from apply_velocity. wall_slide_dir is a forwarding shell (below) so NPC.wall_slide_dir still resolves
## for the tests. These two host callbacks let Locomotor drive the STRANDED diagnostic, whose counter (_stranded_cycles)
## stays here because soak_harness reads host._stranded_cycles and test_ranged_behavior calls host._tick_stranded.

## Forwarding shell to Locomotor.wall_slide_dir (the body moved there with the anti-stuck machine in Phase B). Kept as
## a static on NPC so the test asserts (test_npc.gd calls NPC.wall_slide_dir) resolve unchanged. Pure steering math:
## the wall tangent toward the goal (the side with a non-negative dot to `want`).
static func wall_slide_dir(wall_normal: Vector3, want: Vector3) -> Vector3:
	return Locomotor.wall_slide_dir(wall_normal, want)

## Diagnostic only (NO behaviour change): when we keep hitting the give-up hold in the SAME spot, we're probably
## STRANDED on an unreachable navmesh island — a prop/car roof the bake shouldn't have made walkable. Warn ONCE,
## with the NPC name + position, so a playtest pinpoints which prop to carve. In-tree only (global_position).
## Called by Locomotor.update_stuck at the give-up point (body.call(&"_note_stranded")).
func _note_stranded() -> void:
	if not is_inside_tree():
		return
	var pos := global_position
	if _tick_stranded(pos) and not _stranded_warned:
		_stranded_warned = true
		push_warning("NPC '%s' looks STRANDED at (%.1f, %.1f, %.1f) — repeatedly stuck in one spot. Likely an unreachable navmesh island (a prop/car roof the bake made walkable). Carve that prop with a NavBlocker(CARVE) + re-bake, or File -> Run audit_navmesh.gd to locate it." % [display_name, pos.x, pos.y, pos.z])

## Made real progress -> not stranded; re-arm the one-shot warning for a future episode. Called by Locomotor.update_stuck
## on the progress path (body.call(&"_reset_stranded")); replaces the inline `_stranded_cycles = 0; _stranded_warned = false`.
func _reset_stranded() -> void:
	_stranded_cycles = 0
	_stranded_warned = false

## Pure counter (testable off-tree): same-spot give-ups accumulate; one far from the last resets the run. Returns
## true once the run of same-spot give-ups crosses the stranded threshold (3 ~= 10 s wedged in place).
func _tick_stranded(pos: Vector3) -> bool:
	if pos.distance_to(_last_giveup_pos) < 1.5:
		_stranded_cycles += 1
	else:
		_stranded_cycles = 1
	_last_giveup_pos = pos
	return _stranded_cycles >= 3

# --- Facing (smooth yaw; this model's front is +Z, so yaw = atan2(dx, dz)) ---
func _face_point(point: Vector3, delta: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	_face_yaw(atan2(to.x, to.z), delta)

func _face_yaw(target_yaw: float, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))

# --- Cutscene control facades (driven by a CutsceneActor; no-ops unless set_cutscene_control(true)) ---

## Hand scripted control of this NPC to a cutscene (true) or return it to the AI (false). While controlled the
## brain (perception / GOAP / targeting) is suppressed — see the gate atop _physics_process. Releasing clears
## the scripted move/face and the desired velocity, so the AI resumes cleanly from a standstill.
func set_cutscene_control(on: bool) -> void:
	_cutscene_control = on
	if not on:
		_cutscene_has_walk = false
		_cutscene_has_face = false
		_desired_velocity = Vector3.ZERO

## Walk to a world point under cutscene control — reuses the AI's navmesh move (_move_toward), so pathing and
## gravity still apply. Stores the target; the actual stepping happens in _tick_cutscene_movement.
func walk_to(point: Vector3) -> void:
	_cutscene_walk_target = point
	_cutscene_has_walk = true

## Turn to face a world point under cutscene control.
func face(point: Vector3) -> void:
	_cutscene_face_target = point
	_cutscene_has_face = true

## Per-frame scripted movement while under cutscene control: walk toward the stored target (facing the travel
## direction), or — once arrived / if only facing was asked — turn to the face target.
func _tick_cutscene_movement(delta: float) -> void:
	if _cutscene_has_walk:
		if _move_toward(_cutscene_walk_target):  # true while still travelling
			_face_travel(delta)
		else:
			_desired_velocity = Vector3.ZERO
			_cutscene_has_walk = false  # arrived (or can't path) — stop here
	elif _cutscene_has_face:
		_face_point(_cutscene_face_target, delta)

# --- Stealth-sense gates + investigate facade (rank 18) ---

## True when this NPC hears noise as an awareness initiator — the global GameSettings.npc_ai.hearing_initiates OR
## this NPC's own opt-in, so a designer can wake ONE guard's ears while the rest stay deaf.
func _hearing_initiates_on() -> bool:
	return GameSettings.npc_ai.hearing_initiates or hearing_initiates_opt_in

## True when ambient noise can pull this NPC into an investigation. For the simplified stealth loop, only NPCs
## currently hostile to the player react to the shared &"noise" channel; friendly/neutral bystanders ignore it.
func _noise_initiates_on() -> bool:
	return is_hostile() and _hearing_initiates_on()

## True when this NPC participates in body-discovery (leaves a corpse marker on death AND scans for others) —
## the global GameSettings.npc_ai.body_discovery OR this NPC's own opt-in.
func _body_discovery_on() -> bool:
	return GameSettings.npc_ai.body_discovery or body_discovery_opt_in

## Send this NPC to investigate a world point (a designer/trigger seam — an InvestigatePoint marker, a cutscene,
## a scripted noise). Routes through Perception (-> INVESTIGATING: walk there and search); `alerted` shows the
## "!" reaction sting. The no-target GOAP tick walks + searches the spot, and the scripted flag keeps
## _react_unaware from snapping it to idle before it gets there. No-op without a Perception.
func investigate(point: Vector3, alerted: bool = false, sector_phase: float = NAN) -> void:
	if _perception == null:
		return
	_perception.investigate_point(point, alerted, 0.0, sector_phase)  # sector_phase (GA-4) = a squad-coordinated sweep sector; NAN = per-NPC default
	_scripted_investigating = true

# --- Target acquisition ---
## Whether this NPC should ENGAGE `node` in combat. Normally this is exactly is_hostile_to() — so a
## non-following NPC's targeting/perception is completely unchanged. While FOLLOWING, it ALSO covers a
## generic unaligned-hostile attacker (the leader's assailant) so a companion can defend its leader
## against a foe it has no faction reason to hate, but still NEVER an ally/neutral (no faction conflict).
func _treats_as_enemy(node: Node) -> bool:
	if is_hostile_to(node):
		return true
	# While defending a protectee (a player companion OR a bodyguard for any character), also engage anyone
	# HOSTILE TO THAT PROTECTEE — even a foe we have no personal faction quarrel with — so an ally fights
	# the player's (or its charge's) enemies proactively, not just ones that have hit it. Never the
	# protectee itself, and never a neutral/ally (they aren't hostile to the protectee). This subsumes the
	# old unaligned-hostile-attacker case (such a foe is hostile to the protectee via is_hostile()).
	var prot := _protectee()
	if prot != null and node != prot:
		var other := node as NPC
		if other != null and is_instance_valid(other) and other.is_hostile_to(prot):
			return true
	return false

## Whether the retarget throttle must re-acquire THIS frame — facade onto NpcTargeting. True ONLY when we HOLD a
## target that just went invalid (a downed foe, an NPC ally that freed mid-combat, a target that walked out of
## sight_range); a target-LESS NPC returns false so the idle cast re-scans on the timer, not every frame, keeping it
## O(1)/frame (the C8 fix). False off-tree (no targeting child -> no scan).
func _should_immediately_retarget() -> bool:
	return _targeting._should_immediately_retarget() if _targeting != null else false

## Re-pick our target — facade onto NpcTargeting. Called from _ready and the retarget throttle; no-op
## off-tree (no targeting child yet).
func _acquire_target() -> void:
	if _targeting != null:
		_targeting._acquire_target()

## Bind a freshly-chosen target: cache its root + LOS body (the player exposes "PlayerCollisionShape";
## an NPC falls back to its root collider for the ray identity test), and feed both into Perception.
## Called by NpcTargeting once it has chosen; stays on the NPC because _target / _target_body are the
## shared state read by combat, movement, and barks.
func _set_target(node: Node3D) -> void:
	_target = node
	_target_body = _target.get_node_or_null(^"PlayerCollisionShape") if _target else null
	if not _target_body:
		_target_body = _target
	if _perception:
		_perception.target = _target
		_perception.target_body = _target_body

## Public setter for the sticky combat lock `_last_attacker` (who last hit us). NpcTargeting drives this through here
## rather than poking the private directly, so the write seam is greppable + rename-safe (M2 host-facade contract —
## see scripts/npc/README.md). null clears the lock. npc.gd's own damage/death paths set the private directly (same class).
func set_last_attacker(node: Node) -> void:
	_last_attacker = node

## The flee-only threat accessor — WHERE this NPC runs away FROM. Survives a TARGET-LESS flee, unlike the combat-hot
## _aim_point (which hard-derefs _target_body/_target and would null-crash). A scripted investigate() (a squad sweep
## or an alarm) sets perception INVESTIGATING with NO _target, yet GoapActionFlee.is_runtime_valid still passes
## (is_fleeing + state != UNAWARE), so the executor runs Flee -> _act_flee -> here with BOTH target handles null.
## Resolution order: (1) the live target body/root if we hold one (a normal combat flee), (2) else
## Perception.last_known_position — seeded by investigate_point / alert_to on any non-UNAWARE state reachable on a
## flee, so it points at the disturbance we're running from, (3) else our OWN position (no Perception at all -> the
## _act_flee "standing on the threat" branch then bolts spawn-ward). Kept DISTINCT from _aim_point on purpose:
## _aim_point stays lean for the hot combat paths (npc_combat / _alert_allies) that ALWAYS hold a target. (C6)
func _flee_threat_point() -> Vector3:
	var node: Node3D = _target_body if is_instance_valid(_target_body) else _target
	if is_instance_valid(node):
		return node.global_position + Vector3.UP * target_height
	if _perception != null:
		return _perception.last_known_position
	return global_position

## World point to aim at: the centre of the target's collision capsule (+ optional nudge).
func _aim_point() -> Vector3:
	var node: Node3D = _target_body if is_instance_valid(_target_body) else _target
	return node.global_position + Vector3.UP * target_height

## Distance from this NPC to its current target, or INF when it has no target. Read by BodyModelSwap to gate the
## raised-weapon arm pose on proximity (arms come up only when the foe is close); no target -> arms stay down.
func aim_distance() -> float:
	var node: Node3D = _target_body if is_instance_valid(_target_body) else _target
	if not is_instance_valid(node):
		return INF
	return global_position.distance_to(node.global_position)

## How far the aim ray / laser reaches — the equipped weapon's own effective range.
func _aim_range() -> float:
	var w: WeaponData = _weapon.equipped_weapon if _weapon else null
	if w == null:
		return LASER_MAX_LENGTH
	return w.effective_range if w.effective_range > 0.0 else GameSettings.npc_ai.unranged_aim_fallback

## The distance this NPC engages a target at — the standoff it closes to AND how far it will fire — so it
## SCALES with the equipped weapon: a shotgunner closes right in, a long-range weapon holds back. Unarmed
## uses the FISTS' reach; otherwise see _engage_range_for.
func _engage_range() -> float:
	if not _can_fight_with_gun():
		return FISTS.effective_range
	return _engage_range_for(_weapon.equipped_weapon if _weapon != null else null)

## Engage distance for weapon `w`: its own effective_range when it sets one (so the standoff scales with the
## gun, NOT capped by fire_range — a sniper actually snipes), else the fire_range fallback for a range-less
## weapon (e.g. the thrown rock, effective_range 0), held to GameSettings.npc_ai.unranged_aim_fallback as before.
func _engage_range_for(w: WeaponData) -> float:
	if w != null and w.effective_range > 0.0:
		return w.effective_range
	return minf(fire_range, GameSettings.npc_ai.unranged_aim_fallback)

## Seconds between this NPC's shots: the equipped WEAPON's own attack cadence (attack_speed) scaled by
## rate_of_fire_factor. The weapon is the single source of truth for the rate (this replaced the per-NPC
## fire_cooldown). Floored so the charge math never divides by zero; falls back to a 1s base pre-equip.
func _shot_interval() -> float:
	# Unarmed (disarmed / dry): pace to the FISTS cadence so the close-range wind-up applies to
	# a punch instead of a stale or absent gun.
	if not _can_fight_with_gun():
		return maxf(0.05, FISTS.attack_speed * rate_of_fire_factor)
	var w: WeaponData = _weapon.equipped_weapon if _weapon else null
	var base: float = w.attack_speed if w != null else 1.0
	return maxf(0.05, base * rate_of_fire_factor)

## Damage the player's threat indicator shows for our current attack: the equipped weapon's, or the FISTS'
## when we're fighting unarmed — so a winding-up punch reads as the weak threat it is, not a stale gun.
func _attack_damage() -> float:
	if not _can_fight_with_gun():
		return FISTS.damage
	return _weapon.equipped_weapon.damage if (_weapon != null and _weapon.equipped_weapon != null) else 0.0

## Deflect a shot wide so it clearly MISSES: rotate `dir` by a random angle in the tuned deflection range
## (GameSettings.npc_ai.miss_deflect_min/max_deg) around a random axis perpendicular to it. Used for an
## NPC's rolled miss (miss_chance) — see get_aim_direction.
func _deflect_for_miss(dir: Vector3) -> Vector3:
	var d := dir.normalized()
	var perp := d.cross(Vector3.UP)
	if perp.length() < 0.001:
		perp = d.cross(Vector3.RIGHT)  # aiming near-vertical: pick a different reference axis
	perp = perp.normalized().rotated(d, randf() * TAU)  # random direction around the aim axis
	return d.rotated(perp, deg_to_rad(randf_range(GameSettings.npc_ai.miss_deflect_min_deg, GameSettings.npc_ai.miss_deflect_max_deg)))

# --- Held weapon mesh ---
## Render the equipped weapon's own view-model in the NPC's hand and, if that model carries a
## "Muzzle" barrel marker, re-point the shot + laser origin onto it. The view-model is parented under
## the hand anchor (_muzzle, at muzzle_offset) so it inherits the NPC's yaw — the NPC already faces the
## target via _face_point, so the gun points the right way (after the corrective weapon_mesh_rotation).
## A weapon with no view_model simply shows nothing and keeps the bare-marker origin, same graceful
## fallback the player's GunMesh uses for an unassigned weapon.
func _build_weapon_mesh() -> void:
	# Clear any previous model so a RE-equip (a weapon the player gave a disarmed NPC) shows the CURRENT
	# weapon, not the one it spawned with. Reads the equipped weapon (== weapon_data at spawn), so the held
	# model always matches what it actually fires.
	if is_instance_valid(_weapon_mesh):
		if _weapon != null and _weapon.attack != null:
			_weapon.attack.shell_drop = null  # the old mesh's ShellDrop frees with it; don't leave Attack a stale ref
		_weapon_mesh.queue_free()
		_weapon_mesh = null
	var wd: WeaponData = _weapon.equipped_weapon if _weapon != null else null
	var vm: PackedScene = wd.view_model if wd != null else null
	if vm == null:
		return
	_weapon_mesh = vm.instantiate()
	_muzzle.add_child(_weapon_mesh)
	# Most view-models have a CLEAN root — identity (ak_472) or a centered uniform scale with no offset/tilt
	# (the pistol's 0.001) — so hanging them off the hand and correcting only yaw (weapon_mesh_rotation maps
	# their +X business-end onto the NPC's +Z forward) holds them right. But a view-model whose ROOT bakes a
	# first-person-only pose — the knife carries FP scale
	# 1.585, a Z-tilt, and a forward offset for the player's gun camera — would keep that baked scale + offset
	# here (setting rotation_degrees leaves scale/position untouched), so it floats off-hand and oversized.
	# When the weapon opts into an NPC hold override, place the model FRESH from its authored hand pose,
	# discarding the baked FP root transform entirely. Guns (no override) keep the original rotation-only mount.
	if wd != null and wd.npc_hold_override:
		_weapon_mesh.position = wd.npc_hold_position
		_weapon_mesh.rotation_degrees = wd.npc_hold_rotation
		_weapon_mesh.scale = Vector3.ONE * wd.npc_hold_scale
	else:
		_weapon_mesh.rotation_degrees = weapon_mesh_rotation
	# Resolve the gun's own barrel marker (case-insensitive, like GunMesh). When present, shots,
	# tracers, and the laser all originate from the barrel; otherwise they fall back to _muzzle.
	_gun_muzzle = _find_muzzle_marker(_weapon_mesh) as Marker3D
	if is_instance_valid(_gun_muzzle):
		# attack.muzzle / projectile_spawner.muzzle were wired to the bare hand anchor in setup() (which
		# ran before the model existed); re-point them at the barrel now so fire visibly leaves the gun.
		_weapon.attack.muzzle = _gun_muzzle
		_weapon.projectile_spawner.muzzle = _gun_muzzle
	_build_muzzle_fx()

## Muzzle FX on the held gun: the spark burst + ejected-casing scenes the player's rig also instances,
## parented under the gun's barrel marker (so a re-equip frees them with the old model and rebuilds) and
## fired by the SAME Attack signals (flash_muzzle / shell_particle) the player path uses. The spark gates
## itself on the equipped weapon's has_muzzle_flash via its `attack` ref; Attack resizes the casing per
## WeaponData.casing_size_scale through attack.shell_drop. Falls back to the weapon-mesh root when the
## model has no Muzzle marker.
func _build_muzzle_fx() -> void:
	var anchor: Node3D = _gun_muzzle if is_instance_valid(_gun_muzzle) else _weapon_mesh
	if anchor == null or _weapon == null or _weapon.attack == null:
		return
	# Untyped (like PlayerHud's SNIPER_GLINTS): SparkAttack's class_name is new, and typing it here would
	# fail to parse until the editor registers it in the global class cache.
	var spark = load(SPARK_FX_SCENE_PATH).instantiate()
	spark.attack = _weapon.attack
	anchor.add_child(spark)
	_weapon.attack.flash_muzzle.connect(spark._on_attack_flash_muzzle)
	var shell: ShellDrop = load(SHELL_FX_SCENE_PATH).instantiate()
	anchor.add_child(shell)
	_weapon.attack.shell_particle.connect(shell.emit)
	_weapon.attack.shell_drop = shell

## Find a marker named "Muzzle" anywhere under a node, case-insensitively. Copied (not imported) from
## GunMesh._find_muzzle_marker to keep the NPC self-contained — npc.gd deliberately avoids pulling in
## the view-model/GunMesh stack at load time (see the lazy weapon.tscn load() rationale above).
func _find_muzzle_marker(node: Node) -> Node3D:
	return NodeFinder.find_first_by_name(node, "muzzle")

# --- Laser sight (the beam VISUAL lives on the NpcLaser child; the RAY + clear-shot test stay here) ---
## Build the laser-sight child — combatant-only, from _ready. The beam-drawing (BoxMesh / additive
## shader / world-space stretch) + its LASER_ADD_BRIGHTNESS / NPC_LASER_SHADER live on NpcLaser.
func _build_laser() -> void:
	_laser = NpcLaser.new()
	_laser.host = self
	add_child(_laser)
	_laser.setup()

## Hide the laser beam — facade onto the NpcLaser child. Null off-tree / for a civilian (no beam built),
## where it's simply a no-op, exactly as the monolith's `if _laser:` guard was.
func _hide_laser() -> void:
	if _laser != null:
		_laser.hide_beam()

# --- Gun stance (combatants only) — the draw / holster / out-of-combat-reload state machine lives on
# the WeaponStance child; these are the thin facades the AI dispatch + locomotion call into. ---
## Reconcile the gun stance with combat once per frame — facade onto WeaponStance. Called from
## _physics_process behind the same `if _weapon != null` gate; _stance exists iff a combatant is in-tree.
func _reconcile_weapon_stance() -> void:
	if _stance != null:
		_stance.reconcile()

## Walk speed, slowed by a heavy DRAWN weapon — facade onto WeaponStance. Called from _move_toward. Null
## off-tree / for a civilian -> the bare move_speed, exactly what the monolith returned with _weapon null.
func _current_move_speed() -> float:
	var base: float = _stance.current_move_speed() if _stance != null else move_speed
	# crippled legs limp + over-encumbered slog + AGILITY (faster on foot per point) — mirrors the player's
	# target_speed chain in player.gd so an NPC's stat sheet actually drives its locomotion, not just the player's.
	return base * limb_move_multiplier() * encumbrance_move_multiplier() * stats_or_default().move_speed_mult(status_stat_modifier(&"agility")) * status_move_multiplier()

## Called by DialogueManager when this NPC becomes / stops being the one being talked to. While
## talking it's frozen, so its aim loop can't hide the laser itself; do it here. The AI re-shows
## the laser on its own once it unfreezes and re-acquires.
func set_in_dialogue(on: bool) -> void:
	if on:
		_hide_laser()
		_clear_bark_bubble()  # drop any lingering bark balloon so it doesn't hang over the conversation
		# Put the arms DOWN if they were raised (gun-hold / fists-out / airborne): dialogue pauses the world, which
		# freezes the BodyModelSwap gait, so a raised pose would hang for the whole conversation. Duck-typed onto the
		# swap child (like note_speaking); no-op for a non-swapped NPC. The AI re-raises them on its own once unfrozen.
		var swap := _find_body_swap()
		if swap != null and swap.has_method(&"lower_arms"):
			swap.call(&"lower_arms")

## "Prompt" (not force) this NPC to talk — facade onto the TalkApproach child, which owns the walk-up
## (acknowledge -> close into framing range -> run `on_ready`, the real DialogueManager.start). Called by
## the Talkable / DialogueNPC handler on interact, so a talk press is a REQUEST the NPC chooses to answer,
## not an instant dialogue box. The child refuses it while busy fighting / hostile, dedups a second prompt,
## and on a close-enough NPC just waits the talk-prompt buffer then speaks in place. Null off-tree -> no-op.
func prompt_talk(player: Node3D, on_ready: Callable) -> void:
	if _talk != null:
		_talk.prompt_talk(player, on_ready)

## Feed the player's aim indicator our position + how ready we are to fire (0 = just noticing you,
## 1 = locked / about to shoot), so a white radial points at us and ramps opaque.
func _report_aim(charge: float, clear_shot: bool = true) -> void:
	if is_instance_valid(_target) and _target.has_method(&"indicate_aimed_from"):
		var dmg := _attack_damage()
		# Blink the radial in the final pre-shot window. Clamp the lead BELOW the shot cadence so a fast weapon whose
		# beep_lead_time >= shot_interval (pistol/SMG) doesn't hold the warning on EVERY frame (constant strobe that stops
		# meaning "a shot is imminent"). The 0.9× cap leaves a visible off-gap between shots; a slow weapon (sniper) keeps
		# its full beep_lead_time window untouched (its interval dwarfs the lead, so the min picks beep_lead_time).
		var lead: float = minf(GameSettings.npc_ai.beep_lead_time, _shot_interval() * 0.9)
		var warning := _fire_timer <= lead
		# Report from our actual HEAD, not the body origin at the feet — so the sniper glint/flare the player
		# sees blooms at the NPC's head (the scope/eyes) instead of down at the ground. _head_position()
		# prefers the rigged "Head" bone, then the capsule top, then an eye_height offset (see its doc).
		_target.indicate_aimed_from(self, _head_position(), charge, dmg, warning, clear_shot)

## World position of this NPC's HEAD, for the sniper-glint origin (Feature #8). Resolves, in order:
##   1. the rigged "Head" bone on the mesh's Skeleton3D (Man.glb rigs one) — its live global pose, so
##      the glint tracks the head as the body animates/yaws, not a fixed guess off the feet;
##   2. the TOP of the collision capsule (origin + half-height) when there's no skeleton/bone;
##   3. the old eye_height offset as a last resort (an off-tree / mesh-less NPC).
## The bone lookup is cached (runs once via _resolve_head) so this stays cheap on the per-frame aim path.
func _head_position() -> Vector3:
	if is_instance_valid(_swapped_head):
		return _swapped_head.global_position  # the glint follows the swapped character's head, not the hidden Man.glb bone
	_resolve_head()
	if _head_bone >= 0 and is_instance_valid(_head_skeleton):
		# Bone pose is in the skeleton's local space; lift it to world through the skeleton's transform.
		return _head_skeleton.global_transform * _head_skeleton.get_bone_global_pose(_head_bone).origin
	var cap: Variant = _capsule_top()
	if cap != null:
		return cap
	return global_position + Vector3.UP * eye_height

## Find and cache the mesh's "Head" bone (once). No-op off-tree / without a `mesh`; leaves _head_bone
## at -1 (so _head_position falls back) when the model carries no Skeleton3D or no bone named "Head".
func _resolve_head() -> void:
	if _head_resolved:
		return
	_head_resolved = true
	if mesh == null:
		return
	_head_skeleton = _find_skeleton(mesh)
	if _head_skeleton != null:
		_head_bone = _head_skeleton.find_bone("Head")  # Man.glb's rig names it exactly "Head"

## First Skeleton3D anywhere under `node`, depth-first (the Man.glb rig sits a few nodes deep under the
## mesh root). Mirrors the recursive _find_muzzle_marker idiom so npc.gd stays self-contained.
func _find_skeleton(node: Node) -> Skeleton3D:
	return NodeFinder.find_first_of_class(node, Skeleton3D) as Skeleton3D

## --- Head-look accessors (READ-ONLY; for the drop-in NpcHeadLookMount component). They expose the visible head
## node + the current glance target so the head can track independently of the body, WITHOUT npc.gd growing any
## head-look behaviour branch -- mirroring the existing _aim_point accessor and changing no NPC state. ---

## The VISIBLE head node the head-look rotates: a BodyModelSwap component's swapped head if one registered (the
## unified character swap). Null when no custom head was swapped in (the head-look then no-ops; the glint falls
## back to the Man.glb "Head" bone via _head_position).
func head_visual() -> Node3D:
	return _swapped_head if is_instance_valid(_swapped_head) else null

## World position of this NPC's HEAD, as a PUBLIC seam over the private _head_position() (which resolves, in order:
## the swapped head node, the rigged "Head" bone, the capsule top, then an eye_height offset). DialogueManager's
## dialogue face light reads this to key a light onto the face of the NPC you're talking to. Thin alias so callers
## don't reach into the private helper (and so the seam is pinned by the speaker-contract test).
func head_world_position() -> Vector3:
	return _head_position()

## A BodyModelSwap component hands us its swapped head, so the head-look + sniper glint track IT instead of the
## Man.glb head bone. Called from the component at runtime (before our _ready runs).
func register_swapped_head(node: Node3D) -> void:
	_swapped_head = node

## Extend Character's outline-overlay pass: ALSO rim the swapped BodyModelSwap character parts (body/head/arms/
## legs). Once a custom model is swapped in, the Man.glb meshes that normally carry the rim are HIDDEN, so the
## outline would vanish without this. Each part wears its OWN copy of the outline (visually identical) chained in
## front of its OWN flash material -- that per-part flash pass is what lets just the struck limb flash on a hit
## (see _flash_damage). Mirrors Character's per-mesh look-at-highlight stash handling. No-op without a swap.
## Apply the damage-flash / outline overlay to the NPC's meshes — a virtual override Character dispatches BY NAME.
## H2b: runs the base whole-body pass (super), then delegates the per-swapped-part overlays to NpcOutline. super()
## MUST stay here (it's only valid inside the override); off-tree (no _outline yet) the base whole-body pass suffices.
func _apply_overlay_to_meshes(overlay: Material) -> void:
	super(overlay)
	if _outline != null:
		_outline.apply_part_overlays(overlay)

## The BodyModelSwap child (the drop-in character swap), or null -- duck-typed so npc.gd doesn't hard-depend on it.
func _find_body_swap() -> Node:
	for c in get_children():
		if c.has_method(&"character_parts"):
			return c
	return null

## Flash the SPECIFIC swapped part the shot hit — a virtual override Character dispatches BY NAME. H2b: delegates to
## NpcOutline (per-limb flash reusing body_part_at); off-tree (no _outline) falls back to the whole-body flash_red.
func _flash_damage(hit_pos: Vector3) -> void:
	if _outline != null:
		_outline.flash_damage(hit_pos)
	else:
		flash_red()

## Whole-body flash — a virtual override Character dispatches BY NAME. H2b: runs the base whole-body flash (super),
## then pulses EVERY swapped part via NpcOutline. super() MUST stay here (only valid inside the override).
func flash_red() -> void:
	super()
	if _outline != null:
		_outline.flash_all_parts()

## The WORLD POINT this NPC's head should glance at right now, or null when nothing warrants one (the head eases
## back to neutral). TRUTHFUL: the head only ever points where perception currently vouches for, so an NPC never
## craned to "look at" a player it can't actually see (through a wall, behind its back, in the dark) — the jarring
## tell that made stealth feel broken. Priority (resolved by NpcHeadLookMount.resolve_look_point): a foe we
## currently SEE (ALERTED) → its live position > any awareness (detecting / investigating / residual) → the last
## spot we actually sensed > an idle glance at a player we can GENUINELY see > a nearby radio we're enjoying.
## Read-only. Returns Variant so "nothing to look at" stays distinct from the world origin.
func head_look_point(include_player: bool) -> Variant:
	# `_target` is acquired by pure PROXIMITY within sight_range (NpcTargeting has no LOS/cone), so a valid target
	# does NOT mean we can see it. Only ALERTED means sense() confirmed sight THIS frame (it drops to INVESTIGATING
	# the instant we lose the line), so that's the sole state in which the head tracks the foe's LIVE position.
	var st: int = _perception.state if _perception != null else -1
	var foe_visible := is_instance_valid(_target) and st == Perception.State.ALERTED
	# Any awareness short of a live sighting → look at the last spot we sensed, not a foe's true position we've lost.
	var aware := st == Perception.State.DETECTING or st == Perception.State.INVESTIGATING or st == Perception.State.ALERTED
	var last_known: Vector3 = _perception.last_known_position if _perception != null else Vector3.ZERO
	# Idle ambient "notices you" glance: only when nothing above already claims the head, and only at a player we can
	# actually SEE (range + view cone + clear line of sight — never through a wall or behind our back). The player's
	# BODY eye stays put through a dialogue camera swing, so the head pitches up/down to it. Honours look_at_player.
	var can_glance := false
	var player_point := Vector3.ZERO
	if include_player and not foe_visible and not aware:
		var pl := _real_player()
		# This is the AMBIENT "townsfolk notice you" glance ONLY. If we'd treat this player as an ENEMY, the head is
		# governed entirely by Perception above (foe_visible / aware) — and reaching here means we're UNAWARE of them,
		# so a hostile must NOT glance: that would telegraph a player our detection deliberately hasn't noticed (one
		# beyond our crouch-reduced sight range, say). can_see_node still keeps the friendly glance honest — only at a
		# player in clear view, never through a wall or behind our back.
		if is_instance_valid(pl) and not _treats_as_enemy(pl) and pl.has_method(&"look_target_position") and can_see_node(pl):
			can_glance = true
			player_point = pl.call(&"look_target_position")
	var has_radio := is_instance_valid(_attending_radio)
	var radio_point: Vector3 = _attending_radio.global_position if has_radio else Vector3.ZERO
	return NpcHeadLookMount.resolve_look_point(
		foe_visible, _aim_point() if foe_visible else Vector3.ZERO,
		aware, last_known,
		can_glance, player_point,
		has_radio, radio_point)

## Max distance the head-look mount should allow for the CURRENT look target. Ambient glances keep the mount's
## shorter authored `look_range`; once this NPC is ALERTED on the player/player-side target, let the visible head
## keep tracking across normal combat range instead of easing neutral while the body is still locked on.
func head_look_max_range(base_range: float) -> float:
	if is_alerted_on_player():
		return maxf(maxf(base_range, sight_range), fire_range)
	return base_range

## True if this NPC can currently SEE `node` (range + view cone + line of sight), regardless of hostility -- used
## by the player's aim-remark so an NPC only says "watch where you're aiming" when it can actually see your gun
## on it (no reacting to a barrel pointed at its back / through a wall). False without a Perception.
func can_see_node(node: Node3D) -> bool:
	return _perception != null and _perception.can_see_node(node)

## Top of the NPC's collision capsule in world space (origin + the capsule's half-height up its Y), or
## null when there's no CollisionShape3D / CapsuleShape3D to read — the second-choice head anchor when
## the model has no rigged Head bone. Scanned shallowly (the shape is a direct child on enemy.tscn).
## Untyped return so the "no capsule" case can yield null (a Vector3-typed func can't), which
## _head_position() tests before falling through to the eye_height offset.
func _capsule_top() -> Variant:
	for c in get_children():
		var col := c as CollisionShape3D
		if col == null:
			continue
		var cap := col.shape as CapsuleShape3D
		if cap == null:
			continue
		# height spans the full capsule centred on its origin, so half-height reaches the top cap.
		return col.global_position + global_basis.y * (cap.height * 0.5)
	return null

## Point the laser from the muzzle toward `point` (capped at weapon range), glowing by `charge`
## (0..1). Returns the ray hit so callers can reuse it (e.g. the clear-shot test).
func _aim_laser_at(point: Vector3, charge: float, report_aim: bool = true) -> Dictionary:
	if report_aim:
		_report_aim(charge)  # warn the player (the white aim radial); ALERTED overrides with fire-readiness
	var origin := get_aim_origin()
	var dir := point - origin
	if dir.length() < 0.01:
		_hide_laser()
		return {}
	dir = dir.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * _aim_range())
	query.exclude = [self]
	# Guard the world: get_world_3d() is null for a frame if we're not in a live 3D scene (e.g. being
	# freed), and dereferencing .direct_space_state on null is a hard crash.
	var world := get_world_3d()
	if world == null:
		_hide_laser()
		return {}
	var hit := world.direct_space_state.intersect_ray(query)
	# Beam VISUAL hands off to the NpcLaser child. The show_laser export gate, no-beam case (civilian /
	# off-tree), and weapon has_laser_sight flag all hide here and return the ray; otherwise compute the
	# endpoint (where the ray hit, else the full reach) and let the child stretch + tint the beam.
	if not show_laser or _laser == null or not _current_weapon_has_laser_sight():
		_hide_laser()
		return hit
	var endpoint: Vector3 = hit.position if not hit.is_empty() else origin + dir * _aim_range()
	_laser.draw_beam(origin, endpoint, charge, _outline_color_for_disposition())
	return hit

# --- WeaponHost aim contract: from the muzzle toward the target, no camera ---
## Shot + laser origin: the held gun's barrel marker when one resolved, else the bare hand anchor
## (_muzzle), else the body origin. Both the hitscan ray (attack.gd) and the laser (_aim_laser_at)
## route through here, so preferring the barrel moves both onto the gun in one place.
func get_aim_origin() -> Vector3:
	if is_instance_valid(_gun_muzzle):
		return _gun_muzzle.global_position
	return _muzzle.global_position if _muzzle else global_position

func get_aim_direction() -> Vector3:
	if not is_instance_valid(_target) or not _muzzle:
		return global_basis.z
	var dir := (_aim_point() - get_aim_origin()).normalized()
	if _shot_miss:
		_shot_miss = false  # consume: this deflection applies only to the one shot we rolled to miss
		dir = _deflect_for_miss(dir)  # send it wide so it whiffs past the target
	return dir

func get_aim_basis() -> Basis:
	var dir := get_aim_direction()
	# Avoid a degenerate basis if we're ever aiming near-straight up/down.
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	return Basis.looking_at(dir, up)


## EDITOR: surface "multiple sources of truth" conflicts in the inspector, so a silently-overridden field is
## visible where you author it instead of a runtime surprise. Pure read of the @exports (@tool, editor-only).
func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if faction_id != "" and faction != null:
		w.append("Both faction_id (dropdown) and a faction resource are set — faction_id WINS at runtime and replaces the faction slot. Clear one.")
	if (faction_id != "" or faction != null) and not disposition_overrides_faction and disposition != Disposition.Kind.HOSTILE:
		w.append("A faction is set, so the standalone `disposition` is IGNORED (faction + reputation drive attitude). Tick disposition_overrides_faction to use `disposition` instead.")
	if profile != null and not profile_fills_blanks_only:
		w.append("`profile` (NpcData) is set with profile_fills_blanks_only OFF — the profile OVERWRITES this NPC's inline fields (HP, faction, weapon, carried items, perception, …) at spawn. Turn it ON to keep per-instance edits.")
	if profile != null and loot != null:
		w.append("Inline `loot` AND a `profile` are set — the profile's loot wins (even if the profile leaves it empty), so this inline `loot` is ignored. Put the table on the NpcData, or clear the profile.")
	return w
