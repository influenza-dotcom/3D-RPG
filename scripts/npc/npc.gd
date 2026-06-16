@tool
class_name NPC
extends Character

## Faction registry (preloaded, NOT class_name -> no test-suite global-class-cache dependency): resolves the
## faction_id dropdown to a Faction resource in _ready.
const Factions := preload("res://scripts/faction/factions.gd")

@export_group("Profile")
## An NPC ARCHETYPE profile. Assign one and it stamps ~40 tuning fields onto this NPC in _ready (see
## _apply_profile), so a raider / townsperson / sniper is ONE resource assignment instead of dozens of inline
## overrides. EITHER/OR: a profiled NPC is driven entirely by its profile; leave it null to tune inline as
## before (every existing scene does this, so they're unaffected).
@export var profile: NpcData = null
## EXPERIMENTAL: drive this NPC's AI with the GOAP planner (GoapExecutor) instead of the FSM. Default false =
## the FSM (the strangler-fig migration flips this per-NPC, goal-by-goal). Stamped from NpcData if a profile is set.
@export var use_goap: bool = false
## The GOAP goal-set + per-action cost overrides for this NPC (authored here or on NpcData); the executor reads
## it to build its action/goal library as goals migrate. Unused while use_goap is false.
@export var goap_profile: GoapProfile = null

@export_group("Body & Head")
## Parent node the instanced head is attached under in _ready (the head mesh becomes its child). Wire it to the body part that should carry the head (e.g. a neck/shoulders node).
@export var head_node: Node3D
## Optional head mesh instanced at spawn and parented under head_node. Leave null for a headless / pre-attached body. Set it to swap heads per NPC without editing the body scene.
@export var head_scene: PackedScene
## Marker3D whose local position places the instanced head_scene. Point it where the neck meets the head so the swapped head sits correctly.
@export var head_position: Marker3D

## The NPC's body mesh node. Its rotation seeds the instanced head's facing (head yaw = body yaw - 90 deg), keeping a swapped head aligned with the body's forward.
@export var body_scene: Node3D

@export_subgroup("Custom Models")
## Assign a reusable NpcLook .tres to drive ALL the per-NPC appearance overrides below from ONE shared resource
## (author a "raider look" / "townsperson look" once, reuse it across NPCs). When set it WINS over and HIDES the
## inline fields below; leave null to tune this NPC's look inline. BodyModelSwap reads it live (editor preview).
@export var look: NpcLook:
	set(value):
		look = value
		notify_property_list_changed()  # toggle whether the inline fields below show (see _validate_property)
## Per-NPC BODY swap: set a model here and THIS NPC's body becomes it -- live in the editor (its BodyModelSwap
## child reads these), overriding the shared default look. Null = keep the default. So you re-skin any NPC by
## just clicking it in the level, no "Editable Children" needed. Scale/offset/rotation place it (start scale ~ the
## default body's, e.g. 0.2, if the model comes in giant). Head swap is separate, just below.
@export var body_model: PackedScene
@export var body_model_scale: float = 1.0
@export var body_model_position: Vector3 = Vector3.ZERO
@export var body_model_rotation: Vector3 = Vector3.ZERO
## Re-SKIN this NPC's body WITHOUT swapping the mesh: a texture and/or a tint over whatever body is shown (the
## default one or a swapped one). Texture null + colour WHITE = keep the existing skin. Lives independent of
## Body Model above, so you can re-texture the default body alone.
@export var body_texture: Texture2D
@export var body_color: Color = Color.WHITE
## Per-NPC HEAD swap (same idea; null = keep the default head). The head-look + sniper glint retarget to it.
@export var head_model: PackedScene
@export var head_model_scale: float = 1.0
@export var head_model_position: Vector3 = Vector3.ZERO
@export var head_model_rotation: Vector3 = Vector3.ZERO
## Re-skin the HEAD: a texture and/or tint over whatever head is shown (default or swapped). Texture null + colour WHITE = keep its material.
@export var head_texture: Texture2D
@export var head_color: Color = Color.WHITE
## Tint THIS NPC's ARMS / LEGS (WHITE = keep the default tint). Their models aren't swappable from here yet (they
## swing with the gait), but the COLOUR is -- so you can recolour an NPC's limbs per instance, live in the editor.
@export var arm_color: Color = Color.WHITE
@export var leg_color: Color = Color.WHITE


## The single non-player actor class. One NPC spans everything from an inert townsperson to a ranged
## combatant — behaviour is DATA-DRIVEN, not subclassed:
##   - weapon_data == null -> CIVILIAN: no gun / laser / fire path, but still senses, wanders, flees,
##                            and turns when shot. Give it a faction / disposition to be neutral or
##                            friendly, and threat_response = FLEE to run rather than square up.
##   - weapon_data != null -> COMBATANT: wields the SAME Weapon component the player does, aimed by
##                            AI (Perception view-cone + line-of-sight + detection meter). It locks
##                            the NEAREST hostile (the player or a faction-opposed NPC, via
##                            is_hostile_to) then turns, aims, lasers, and fires once it has actually
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

## Master switch for this actor's combat outline. Off => flash-only overlay (no rim).
@export var has_outline: bool = true
## Outline rim colour. Combatants default to black; a friendly NPC can override per instance.
@export var outline_color: Color = Color.BLACK
## Outline thickness fed to the shader's `outline_width` uniform (shader scales it x4 in clip
## space). 2.0 is the standard combat rim every NPC scene ships. Was silently ignored pre-Phase-2
## because the old code set a non-existent `outline_thickness` uniform; the shader only exposes `outline_width`.
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
## When true, this NPC has been provoked (e.g. the player attacked it) and is hostile regardless
## of faction/disposition until something clears it. Runtime only — never authored in the editor.
var _provoked: bool = false
## Cumulative player damage taken WHILE FRIENDLY, counting toward friendly_aggro_threshold. Once it
## crosses, the NPC is provoked (hostile) and this no longer gates anything.
var _player_aggression: float = 0.0

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

@export_group("Inventory")
## Extra items this NPC CARRIES (a keycard, stims, junk), seeded into its backpack at spawn ON TOP of the
## weapon + ammo from weapon_data. Real carried items: pickpocketable + dropped on death (the corpse copies
## the bag). Add the SAME item twice for two of it. (The loot table is RANDOM drops; these are deterministic.)
@export var starting_items: Array[Item] = []
## EASY count-based carried items: "30 ammo, 2 stims" as rows (item + count) instead of repeating in
## starting_items. Seeded into the backpack alongside starting_items (pickpocketable + dropped on death too).
@export var item_stacks: Array[ItemStack] = []

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
## Eye height the sight / LOS rays start from.
@export var eye_height: float = 1.4
## Hear the player's noise (gunfire, fast movement) even outside the cone? Crouch is silent.
@export var hearing: bool = true
## How fast it rotates to face what it's looking at.
@export var turn_speed: float = 8.0

@export_group("Laser")
## Draw a laser sight that brightens as it detects / locks onto you (combatants only).
@export var show_laser: bool = true
## Laser sight colour.
@export var laser_color: Color = Color(1.0, 0.1, 0.1)

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
## Upward impulse for hopping ledges / the far end of an up navigation-link (m/s).
@export var jump_velocity: float = 10.0
## Combat dodge (Feature #5): while ALERTED on a live target, every dodge_interval seconds the enemy
## rolls dodge_chance to break into a brief lateral STRAFE (left or right relative to the target) for
## dodge_duration, instead of standing still — so it's a harder target without constant jittering. The
## strafe drives _desired_velocity at dodge_speed_fraction of move_speed through the normal locomotion
## (pathing is untouched — pursuit resumes the instant the burst ends). 0 chance disables it entirely.
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
## (temperament * fraction of HP lost), so a coward bolts as the fight turns against it. See _on_damaged_by.
@export var temperament: float = 0.0
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
const WEAPON_SCENE_PATH := "res://scenes/weapon.tscn"
## Muzzle FX on the held gun — the SAME authored scenes the player's rig instances (spark burst + ejected
## casing), loaded lazily like weapon.tscn so npc.gd stays light at parse time.
const SPARK_FX_SCENE_PATH := "res://scenes/effects/spark_attack.tscn"
const SHELL_FX_SCENE_PATH := "res://scenes/effects/shell_drop.tscn"
const LASER_MAX_LENGTH := 60.0
## --- Audio-cue timing the firing CADENCE owns (the sound ASSETS + mix live on the NpcAudioCues child) ---
## The shared (static) cooldown so a swarm spotting you at once plays one MGS "!" sting. Kept here (the
## child reads NPC.ALERT_COOLDOWN_MS) because a unit test pins it as NPC.ALERT_COOLDOWN_MS.
const ALERT_COOLDOWN_MS: int = 3000
## Sniper charge-sting de-dup window — only dedups near-simultaneous triggers (lock + an immediate first
## shot); the fire cadence is the real rhythm. Kept short so genuine per-shot lock-ons each sting — a longer
## window swallowed the telegraph on faster shooters. Drives the _on_aim throttle (which stays on the root
## so a unit test can poke _last_aim_msec / _aim_sfx_delay on a bare instance).
const AIM_COOLDOWN_MS: int = 120
## A short beat between a shot and its charge-up sting so the two don't blur together (see _on_aim). A
## unit test pins it as NPC.AIM_SFX_DELAY, and _on_aim writes it to _aim_sfx_delay, so it stays here.
const AIM_SFX_DELAY: float = 0.1
## How many seconds before a shot lands the warning beep plays — part of the root's firing cadence (it
## gates both the beep and the in-sync aim-radial blink), so it stays here, not on the audio child.
const BEEP_LEAD_TIME: float = 0.5

## Head-popup icons — billboarded Sprite3D built in code (no .tscn), held then faded + freed.
## EXCLAMATION pops on first alert (alongside the MGS sting); NEGATIVE pops the moment this NPC
## turns hostile / its faction is soured. Source res:// paths used directly (like MGS_ALERT) — the
## exclamation filename literally contains a space and "(1)", which is legal inside the string.
const POPUP_EXCLAMATION = preload("res://assets/textures/exclamation_1 (1).png")
const POPUP_NEGATIVE = preload("res://assets/textures/negativefriend.png")
## The "+friend" head-popup icon, floated over THIS NPC when the player rescues it by killing its attacker. Leave null for no rescue cue.
@export var popup_positive: Texture # = preload("res://assets/w_friend.png")  # "+friend": shown when you rescue an NPC by killing its attacker
var _save_rewarded: bool = false  # one-shot guard so a multi-pellet killing blow only rewards the rescue once
## Local Y to float the popup just above the ~2 m capsule's top cap (head is ~ local y +1.0), so a
## child at this height tracks the NPC and ignores its yaw.
const POPUP_HEAD_Y: float = 1.5
## Seconds the popup holds at full alpha before its alpha tweens to 0, then it frees (~1 s total).
const POPUP_HOLD: float = 0.35
const POPUP_FADE: float = 0.65
## Icon height in METRES above the head — converted to the Sprite3D's pixel_size per texture so the
## cue is the same world size regardless of the PNG's pixel dimensions. World-space (NOT fixed_size),
## so it stays planted over the head and shrinks with distance instead of screen-locking to the camera.
const POPUP_WORLD_HEIGHT: float = 0.7

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
var _head_instance: Node3D = null  # the instanced custom head mesh (head_scene) under head_node -- what the head-look rotates
var _swapped_head: Node3D = null   # a BodyModelSwap component's head, if one registered -- preferred over _head_instance
## Per-swapped-part flash materials (stable string key -> ShaderMaterial), so the SPECIFIC limb that's shot
## flashes alone. Keyed by string (not the part node) so a flash mid-tween survives outline re-applies / model
## rebuilds. Empty for a non-swapped (Man.glb) NPC -> the whole-body flash is used. And the running per-part
## flash tweens (key -> Tween) so a rapid second hit on the SAME part restarts its pulse.
var _part_flash: Dictionary = {}
var _part_flash_tweens: Dictionary = {}
var _target: Node3D
var _target_body: Node3D  # target's collision shape (centre tracks crouch); falls back to _target
var _last_attacker: Node3D = null  # most recent hostile that damaged us; favoured over the nearest in _acquire_target
var _npc_grudges: Array[NPC] = []  # NPC peers we now treat as enemies because they DAMAGED us (is_hostile_to honours it)
var _hit_by_player: bool = false   # the real player has damaged us (drives the "Hey, thanks!" assist bark on death)
var _hurt_bark_said: bool = false  # a wounded-ally cry has already fired this life (so it only plays once)
var _saw_combat: bool = false      # has been ALERTED since the last all-clear; drives the combat-over bark
var _was_aware: bool = false       # has NOTICED a threat (any non-UNAWARE state) since the last all-clear; drives the give-up barks
## The investigation look-around: once arrived at the last-known spot, the facing sweeps in a slow circle
## hunting for the target (rad/s — at 0.8 a full turn takes ~8s, so a 4s forget_time reads as a half-circle
## scan before giving up). Designer-tunable per NPC in the inspector, like the Perception ranges.
@export var search_sweep_rate: float = 0.8
var _search_sweep_t: float = 0.0  ## the sweep phase — just accumulates; only its derivative matters
var _was_distracted: bool = false  ## true while a NO-target NPC is investigating a noise/body (drives the give-up "lost interest" bark)
var _distraction_scan_t: float = 0.0  ## throttles the no-target noise/corpse group scans (GameSettings.npc_ai.distraction_scan_interval)
var _fire_timer: float = 0.0       # shared attack wind-up timer: gun shots AND unarmed punches (see _shot_interval)
var _charging: bool = false  # winding up a clear, in-range shot (drives the lock-on sting)
var _warned: bool = false    # the incoming-shot beep already played for the current charge
var _shot_miss: bool = false # this shot was rolled to MISS — get_aim_direction deflects it wide (consumed there)
## Combat-dodge bookkeeping (Feature #5, used only by a combatant in _act_alerted). _dodge_cd counts down
## to the next dodge ROLL; _dodge_t is the remaining time of an ACTIVE strafe burst (> 0 = mid-dodge);
## _dodge_dir is the chosen lateral world direction held for that burst.
var _dodge_cd: float = 0.0
var _dodge_t: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _spawn_yaw: float = 0.0
var _spawn_position: Vector3
var _desired_velocity: Vector3 = Vector3.ZERO
var _nav: NavigationAgent3D
## Anti-stuck steering: when the NPC is trying to move but barely progressing (a wall / prop / another NPC is
## blocking it), it veers ALONG the obstacle for a short burst so it slips around instead of grinding.
const STUCK_SPEED_FRAC := 0.35  ## actual horizontal speed below this fraction of the intended = "blocked"
const STUCK_TIME := 0.35        ## seconds blocked (pressed against something while trying to move) before steering
const UNSTICK_TIME := 0.7       ## seconds to veer along the blocker to slip free
var _stuck_t: float = 0.0
var _unstick_t: float = 0.0
var _unstick_dir: Vector3 = Vector3.ZERO
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

## Editor-only: populate the faction_id dropdown from the factions on disk (resources/factions/*.tres) so a new
## faction .tres appears automatically -- no hand-maintained suggestion string. @tool makes the editor honor this;
## every runtime lifecycle method (_ready, _physics_process) is is_editor_hint()-guarded so ONLY this hook runs in
## the editor -- the AI/weapon/nav/component build never executes there.
## The inline appearance fields hidden from the inspector when a `look` resource is assigned (it owns them then).
## Kept in sync with NpcLook's exports + the Custom Models subgroup above.
const _LOOK_FIELDS := ["body_model", "body_model_scale", "body_model_position", "body_model_rotation",
	"body_texture", "body_color", "head_model", "head_model_scale", "head_model_position", "head_model_rotation",
	"head_texture", "head_color", "arm_color", "leg_color"]

func _validate_property(property: Dictionary) -> void:
	if property.name == &"faction_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = Factions.ids_csv()
	elif look != null and property.name in _LOOK_FIELDS:
		property.usage &= ~PROPERTY_USAGE_EDITOR  # a look resource owns these -> hide the inline fields (value still stored)

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: in the editor only the faction_id dropdown (_validate_property) matters; never build the AI/components
	_apply_profile()  # stamp an assigned NpcData archetype onto our exports FIRST — before super() seeds hp from max_hp, and before the components / perception / weapon branch read the rest
	_resolve_faction()  # the faction_id dropdown (set here or stamped from the profile) -> the live Faction resource
	super()  # Character._ready(): set hp + build the flash overlay on the mesh tree.
	# A BodyModelSwap component owns the head when it registered one (set _swapped_head before our _ready); then
	# skip the legacy head_scene so we don't spawn two heads.
	if head_scene != null and not is_instance_valid(_swapped_head):
		_head_instance = head_scene.instantiate()
		_head_instance.position = head_position.position
		_head_instance.rotation_degrees = body_scene.rotation_degrees - Vector3(0.0,90.0,0.0)
		head_node.add_child(_head_instance)
		call_deferred(&"_hide_rig_head")  # a custom head is on -> shrink the Man.glb's own head away (deferred so the skeleton pose exists first)
	
	add_to_group(&"npc")  # so hostile NPCs can find us as a target (the _acquire_target scan enumerates this)
	# Behaviour children that EVERY NPC carries — built before _setup_outline so the outline child exists
	# (and after super(), so _flash_material is ready for it to chain onto). Senses + locomotion for every
	# NPC armed or not: wandering needs a nav agent, fleeing and the turn-when-shot both need a Perception.
	_build_components()
	_setup_outline()
	_spawn_yaw = rotation.y
	_spawn_position = global_position
	_build_perception()
	_build_nav()
	_seed_carried_items()  # carried items FIRST, so equip-the-strongest sees a weapon authored in starting_items
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

## Resolve the faction_id DROPDOWN pick into the live `faction` resource (via the Factions registry). A non-empty
## id wins over the `faction` slot; an empty id leaves the slot as-authored. Runs in _ready before any consumer
## (HostilityHelpers / Reputation / is_hostile_to) reads `faction`.
func _resolve_faction() -> void:
	if faction_id.is_empty():
		return
	var f := Factions.by_id(faction_id)
	if f != null:
		faction = f

## Stamp an assigned NpcData archetype's values onto our matching exports. Called as the FIRST line of _ready
## (before super() seeds hp from max_hp, before _build_components / _build_perception / the weapon branch read
## the rest). EITHER/OR: with a profile every field comes from it; with NO profile this is a no-op and the
## inline-authored exports stand, so existing scenes are unaffected. threat_response copies int -> the
## ThreatResponse enum (NpcData stores it as an int to avoid an NpcData <-> NPC class cycle).
func _apply_profile() -> void:
	if profile == null:
		return
	display_name = profile.display_name
	popup_positive = profile.popup_positive
	max_hp = profile.max_hp
	stats = profile.stats  # archetype stat sheet -> _apply_stats (in super() below) stamps endurance/strength
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
	starting_items = profile.starting_items
	item_stacks = profile.item_stacks
	sight_range = profile.sight_range
	fov_degrees = profile.fov_degrees
	crouch_sight_mult = profile.crouch_sight_mult
	time_to_detect = profile.time_to_detect
	forget_time = profile.forget_time
	eye_height = profile.eye_height
	hearing = profile.hearing
	turn_speed = profile.turn_speed
	search_sweep_rate = profile.search_sweep_rate
	show_laser = profile.show_laser
	laser_color = profile.laser_color
	move_speed = profile.move_speed
	move_accel = profile.move_accel
	air_accel = profile.air_accel
	engage_range_fraction = profile.engage_range_fraction
	jump_velocity = profile.jump_velocity
	dodge_interval = profile.dodge_interval
	use_goap = profile.use_goap
	goap_profile = profile.goap_profile
	dodge_chance = profile.dodge_chance
	dodge_duration = profile.dodge_duration
	dodge_speed_fraction = profile.dodge_speed_fraction
	threat_response = profile.threat_response as ThreatResponse
	temperament = profile.temperament
	wanders = profile.wanders
	wander_radius = profile.wander_radius
	wander_dwell_min = profile.wander_dwell_min
	wander_dwell_max = profile.wander_dwell_max
	flee_distance = profile.flee_distance
	talk_approach_distance = profile.talk_approach_distance
	talk_approach_timeout = profile.talk_approach_timeout

## Seed the backpack from the assigned weapon_data and DRAW it from the backpack, so a combatant NPC
## fights with an item it actually carries (and therefore drops it on death). If weapon_data isn't a
## registered ItemDb weapon-item, fall back to a direct equip so a custom-weapon NPC still fights (it
## just won't drop a backpack item). Called from _ready's weapon branch, right after _weapon.setup().
## The fallback melee an NPC throws when it has NOTHING equipped — a civilian brawler, or a combatant whose
## weapon was pickpocketed: a weak, short-reach "fists" weapon. Damage / reach / swing cadence are read from
## this WeaponData (tunable), but the hit is applied directly in _punch (no projectile / hitscan rig needed).
const FISTS: WeaponData = preload("res://resources/weapons/fists.tres")

func _equip_initial_weapon() -> void:
	var witem: Item = ItemDb.make_weapon_item(weapon_data)  # a UNIQUE item, so the dropped weapon is its own object
	if witem != null and inventory != null:
		inventory.add(witem)
	# Draw the STRONGEST weapon in the bag: weapon_data only SEEDS the backpack now — if starting_items
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

## Seed the NPC's backpack with its authored carried items (starting_items), ON TOP of the weapon + ammo
## above. Weapons are duplicated to UNIQUE instances (like the loot / pickup pipeline); stackables are added
## as the shared template (add the same item twice for two). Real carried items: pickpocketable + dropped on
## death because the corpse copies the bag. No-op without an inventory (off-tree) or with no carried items.
func _seed_carried_items() -> void:
	if inventory == null:
		return
	ItemStack.seed_into(inventory, item_stacks)  # the easy count-based carried items
	for it in starting_items:
		if it == null:
			continue
		if it.is_weapon():
			inventory.add(it.duplicate() as Item, 1)
		else:
			inventory.add(it, 1)

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

## A combatant wields its gun only while the equipped weapon-item is still in its backpack. Pickpocket the
## weapon out and equipped_item clears (CharacterInventory.remove) -> nothing to draw, so it fights unarmed.
## Civilians (never equipped a weapon item) and disarmed combatants both read false. Public — WeaponStance
## reads it to keep a disarmed NPC's gun holstered/hidden.
func is_armed() -> bool:
	return inventory != null and inventory.equipped_item != null and inventory.equipped_item.is_weapon()

var _last_medkit_msec: int = -100000

## Use a carried HEALING consumable when hurt — NPCs use their items: the same health packs the player
## loots off their corpse if they never get the chance. Any is_consumable() item with heal_amount, at or
## below the tuned HP fraction (GameSettings.npc_ai.medkit_hp_frac), throttled by medkit_cooldown_ms.
## Fired from _on_damaged_by on every hit taken.
func _try_use_medkit() -> void:
	if _dead or hp <= 0.0 or inventory == null:
		return
	if hp > max_hp * GameSettings.npc_ai.medkit_hp_frac:
		return
	var now := Time.get_ticks_msec()
	if now - _last_medkit_msec < GameSettings.npc_ai.medkit_cooldown_ms:
		return
	var kit := inventory.find_healing_consumable()
	if kit == null:
		return
	_last_medkit_msec = now
	heal(kit.heal_amount)
	inventory.remove(kit, 1)

## Whether the NPC can fight WITH its gun right now: it's actually wielded (is_armed) AND there's ammo to
## fire this instant or a spare clip to reload. Pickpocket the weapon OR all its ammo and this goes false,
## dropping it to the unarmed AI (squares up + closes, but can't shoot). _weapon is non-null whenever
## is_armed is true (only a combatant ever equips a weapon item), but it's guarded regardless.
func _can_fight_with_gun() -> bool:
	if not is_armed() or _weapon == null:
		return false
	if _weapon.current_ammo > 0:
		return true
	return _weapon.ammo != null and _weapon.ammo.has_reload_supply()

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
	_follow = CompanionFollow.new()
	_follow.host = self
	add_child(_follow)
	_voice = NpcVoice.new()  # bark / social-voice orchestration (npc_voice.gd); reaches back into us for data
	_voice.host = self
	add_child(_voice)
	if profile != null and profile.bark_set != null:
		_voice._bark_set = profile.bark_set
	_targeting = NpcTargeting.new()  # target acquisition (npc_targeting.gd); binds the chosen target via _set_target
	_targeting.host = self
	add_child(_targeting)
	_locomotion = NpcLocomotion.new()  # non-combat movement: idle / wander / flee (npc_locomotion.gd)
	_locomotion.host = self
	add_child(_locomotion)
	_scavenge = NpcScavenge.new()  # container raiding: grab a better/first weapon from a nearby crate
	_scavenge.host = self
	add_child(_scavenge)
	# Movement FEEDBACK like the player -- footstep SFX while walking + a landing thud/dust on touchdown. Auto-built
	# unless a configured LocomotionFx was already dropped under this NPC in the scene (then we leave that one to it).
	var has_loco_fx := false
	for c in get_children():
		if c is LocomotionFx:
			has_loco_fx = true
			break
	if not has_loco_fx:
		add_child(LocomotionFx.new())
	# The GOAP brain (drives the AI in place of the match when use_goap). Plain RefCounted, not a child Node.
	# The library is filled goal-by-goal as the FSM migrates (Phase 3); see _build_goap_actions/_goals.
	_executor = GoapExecutor.new()
	_executor.setup(_build_goap_actions(), _build_goap_goals())

## The GOAP action library — the planner's vocabulary, the FULL FSM combat dispatch migrated. Hold = the
## UNAWARE-at-seam idle/scavenge floor (also covers companion-follow via _idle, so "Escort" needs no separate
## action); Detect / Investigate = the DETECTING / INVESTIGATING arms; FireArmed / FireUnarmed = the ALERTED arm
## split on _can_fight_with_gun. The same library the decision-matrix + brain tests select over. Built for every
## NPC but INERT until use_goap — only stepped behind the seam. Costs are the actions' defaults unless the
## archetype's goap_profile.action_cost_overrides retunes one (designer-first; no code).
func _build_goap_actions() -> Array:
	var actions: Array = [
		GoapActionHold.new(),
		GoapActionDetect.new(),
		GoapActionInvestigate.new(),
		GoapActionFireArmed.new(),
		GoapActionFireUnarmed.new(),
		GoapActionFlee.new(),
	]
	if goap_profile != null:
		for a in actions:
			a.base_cost = maxf(goap_profile.cost_for(a.name, a.base_cost), 0.0)
	return actions

## The GOAP goal set — highest authored priority among the FEASIBLE goals wins (GoapPlanner.select_goal). Each
## combat goal is feasible only in its perception state (its action's precondition); Survive only while fleeing +
## a threat noticed; Idle is the always-feasible floor. Priority order: Survive (3.0, a fleer always runs rather
## than fights) > Engage (2.0, ALERTED) > Investigate (0.4) > Detect (0.3) > Idle (0.1). This reproduces the FSM
## FLEE pre-seam (which preempts the whole `match`) plus its per-state dispatch.
##
## "Escort" is deliberately NOT a goal: companion-follow is an idle sub-behaviour (NpcLocomotion._idle ->
## _follow.act), reached via the no-target early-return OR the Idle floor; "a following NPC with a target fights"
## falls out of Engage outranking Idle. Survive migrates the FLEE pre-seam under use_goap; the FIGHT->FLEE
## temperament flip works because the combat actions yield on is_fleeing. Priorities are the authored defaults
## unless the archetype's goap_profile.goal_priorities retunes one (raise Survive -> a coward; lower it -> a
## fearless fighter). NOTE: goap_profile.goals (an opt-in subset filter) is intentionally NOT applied yet —
## dropping a combat goal off a target-acquiring NPC would idle it mid-fight, a footgun to design deliberately.
func _build_goap_goals() -> Array:
	var goals: Array = [
		GoapGoal.new(&"Survive", 3.0, {&"fled": true}),
		GoapGoal.new(&"Engage", 2.0, {&"target_engaged": true}),
		GoapGoal.new(&"Investigate", 0.4, {&"spot_searched": true}),
		GoapGoal.new(&"Detect", 0.3, {&"threat_faced": true}),
		GoapGoal.new(&"Idle", 0.1, {&"idle_done": true}),
	]
	if goap_profile != null:
		for g in goals:
			g.base_priority = goap_profile.priority_for(g.name, g.base_priority)
	return goals

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
##   - other is another NPC: BOTH must be factioned and this faction's relation to the other's
##     faction must be < 0 (FNV-style "<0 = enemies"). Unaligned NPCs never fight other NPCs;
##     a provoked NPC still only sours toward the PLAYER (provoke drops player-rep), not peers.
## Self / null / non-NPC-non-player nodes are never hostile.
func is_hostile_to(other: Node) -> bool:
	if other == null or other == self or not is_instance_valid(other):
		return false
	if other.is_in_group(&"Player"):
		return is_hostile()
	var other_npc := other as NPC
	if other_npc == null:
		return false
	if other_npc in _npc_grudges:
		return true  # personal grudge: it damaged us, so we fight it regardless of faction relation
	return HostilityHelpers.npc_vs_npc_hostile(faction, other_npc.faction)

## Aggro this NPC: become hostile NOW, and — if factioned — drop the player's reputation with that
## faction so the whole faction sours (FNV-style). Idempotent; safe to call every hit. `attacker`
## is accepted so the damage hook can also turn us toward the source.
func provoke(_attacker: Node = null) -> void:
	if not _provoked:
		_provoked = true
		if faction != null:
			var provoke_penalty: float = GameSettings.reputation.provoke_penalty
			Reputation.add_reputation(faction, -provoke_penalty)
		_apply_outline()  # now hostile — recolour the rim to red immediately
		_popup_icon(POPUP_NEGATIVE, false, -0.75)  # chest level, clear of the "!" alert at the head (no stacking)

## FNV-style forgiveness: the player holstered their weapon, so if WE were provoked (a non-hostile NPC
## the player attacked) we drop the grudge — clear the provoke, revert the rim to our real disposition,
## and let go of the player as a target so we stand down. Genuinely-hostile NPCs (never provoked): no-op.
func forgive_provoke() -> void:
	if not _provoked:
		return
	_provoked = false
	_apply_outline()  # rim back to the (non-hostile) disposition colour
	# Drop the player if it was our target so we disengage; the AI re-scans and finds no hostile now.
	if is_instance_valid(_target) and _target.is_in_group(&"Player"):
		_set_target(null)
		_last_attacker = null
		_hide_laser()

## Taking a hit: (1) a PLAYER hit on a non-hostile NPC provokes it (flip hostile + drop faction rep);
## (2) turn toward the source so a shot in the back spins us around — no free backstabs. Wired from
## Character.take_damage. We only PROVOKE off the player (so an enemy's stray friendly-fire doesn't
## flip a neutral against the player), but we turn toward ANY localizable attacker. Overrides
## Character._on_damaged_by (a no-op there).
func _on_damaged_by(attacker: Node, _was_crit: bool = false, amount: float = 0.0) -> void:
	if attacker != null and attacker.is_in_group(&"Player") and not (attacker is NPC):
		_hit_by_player = true  # remember the player hurt us (for the assist "thanks" on death)
	# Rescue reward: if the PLAYER just landed our killing blow while we were attacking ANOTHER NPC, the
	# player saved that NPC — credit reputation with the saved NPC's faction + pop a "+friend" cue.
	if hp <= 0.0 and not _save_rewarded and attacker != null and attacker.is_in_group(&"Player") \
			and is_instance_valid(_target) and _target is NPC:
		_save_rewarded = true
		var saved := _target as NPC
		if saved.faction != null:
			Reputation.add_reputation(saved.faction, GameSettings.economy.save_rep_reward)
		saved._popup_icon(popup_positive)  # cue floats over the RESCUED NPC (the one we swayed), not our corpse
	if not is_hostile() and attacker != null and attacker.is_in_group(&"Player"):
		# A FRIENDLY ally forgives incidental damage (stray friendly-fire, a misclick) — it only turns on
		# you once you've hurt it ENOUGH (cumulative player damage past friendly_aggro_threshold), at which
		# point a companion stops following and it aggros. A NEUTRAL (not an ally) still flips on first hit.
		if resolved_disposition() == Disposition.Kind.FRIENDLY:
			_player_aggression += amount
			if _player_aggression >= friendly_aggro_threshold:
				if is_following():
					stop_following()
				provoke(attacker)
				if _voice != null:
					_voice.bark_aggro()  # the forgiveness ran out: "Alright, that does it!"
			elif _voice != null:
				_voice.warn_attack()  # hit but still FORGIVEN (under the threshold): "Cut that out!"
		else:
			provoke(attacker)
			if _voice != null:
				_voice.bark_aggro()  # a neutral flips on the first hit — and says so
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
	if is_following() and not _hurt_bark_said and hp > 0.0 and hp <= max_hp * HURT_BARK_HP_FRAC:
		_hurt_bark_said = true
		_cry_wounded()
	# Hurt: fumble for a carried medkit (any healing consumable in the backpack), throttled inside.
	_try_use_medkit()
	# Temperament: a frightened NPC may BREAK and flee once hurt mid-fight. The chance scales with how hurt
	# it is (temperament * fraction of HP lost), so a coward bolts as the fight turns against it; 0 = never.
	if temperament > 0.0 and threat_response != ThreatResponse.FLEE and is_in_combat():
		var fear := temperament * (1.0 - clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0))
		if randf() < fear:
			threat_response = ThreatResponse.FLEE
			if _voice != null:
				_voice.bark_flee()  # "Forget this!" — breaking and running rather than fighting back

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

## Pause-on-kill: briefly hard-pause the tree so the kill + ragdoll land. Runs on the FreezeFrame
## autoload (not us — we're about to be freed), and no-ops if already paused (dialogue). Wired from
## the scene's `died -> _on_died` connection. Also drops a dead companion out of the &"Player" group
## (Feature #3) the frame it dies — queue_free is deferred, so without this an enemy could still read
## the dying ally as the player for a frame before the body is actually freed.
func _on_died() -> void:
	if is_in_group(&"Player"):
		remove_from_group(&"Player")
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
		_announce_death_to_witnesses()
		# Killing a faction member sours the player's standing with that faction — even a hostile one
		# (you're still putting their people down). Unaligned NPCs (no faction) have no standing to lose.
		if faction != null:
			var kill_penalty: float = GameSettings.reputation.kill_penalty
			Reputation.add_reputation(faction, -kill_penalty)
	# Leave a lootable corpse holding our backpack, while it still exists (queue_free is deferred).
	_drop_loot()
	# Stealth body-discovery: drop a discoverable Corpse marker at the death spot so a nearby UNAWARE NPC that
	# SEES it gets spooked (investigates + calls out). Off by default — a quiet kill is free until the designer
	# flips GameSettings.npc_ai.body_discovery. Outside the _hit_by_player gate: ANY death (a stealth takedown
	# leaves no "hit by player" trail, yet its body must still be findable).
	_spawn_corpse_marker()
	FreezeFrame.pause_briefly(0.015)

## Leave a lootable corpse at the death spot holding a copy of our backpack — a PERSISTENT node, not the
## fading ragdoll, that the player loots with E (LootableCorpse mirrors the talk-handler surface). Spawned
## into our PARENT (the world), not under us, since queue_free is about to free this NPC. No-op when the
## bag is empty (nothing to loot) or we're off-tree.
func _drop_loot() -> void:
	# A skeleton corpse already carries the loot directly (GoreSpawner attaches a LootableCorpse to the
	# ragdoll), so only drop a free-standing lootable corpse for an NPC that has NO ragdoll to loot.
	if ragdoll_scene != null:
		return
	if not is_inside_tree():
		return
	# Drop a corpse when there's ANYTHING to loot — items OR the wallet (an empty-bagged NPC with zorkmids
	# must still leave a lootable body, or its cash is buried with it).
	if (inventory == null or inventory.is_empty()) and money <= 0.0:
		return
	var world := get_parent()
	if world == null:
		return
	var corpse := LootableCorpse.new()
	corpse.setup(inventory, display_name, money)
	world.add_child(corpse)
	corpse.global_position = global_position

## Stealth body-discovery: leave an invisible, discoverable Corpse marker at the death spot (separate from any
## ragdoll / LootableCorpse) so a nearby UNAWARE NPC can NOTICE the death and investigate. Off by default
## (GameSettings.npc_ai.body_discovery) -> nothing spawns, so stealth kills stay free until the designer opts
## in. Spawned into our PARENT (the world), since queue_free is about to take us; no-op off-tree.
func _spawn_corpse_marker() -> void:
	if not GameSettings.npc_ai.body_discovery:
		return
	if not is_inside_tree():
		return
	var world := get_parent()
	if world == null:
		return
	var marker := Corpse.new()
	marker.who = display_name
	world.add_child(marker)
	marker.global_position = global_position

## Roll our profile's loot table INTO the backpack BEFORE gore() copies it into the (ragdoll) corpse, so the
## rolled drops land in the loot whether the body becomes a ragdoll corpse (GoreSpawner._attach_loot) or a
## free-standing one (_drop_loot). gore() runs once, on death (Character.take_damage at hp <= 0).
func gore() -> void:
	_roll_loot()
	super()

## Roll the assigned profile's loot table into the backpack (weapons as unique instances), ON TOP of what we
## carried. No-op without a profile loot table or an inventory.
func _roll_loot() -> void:
	if profile == null or profile.loot == null or inventory == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	profile.loot.grant(inventory, rng)

## Off guard (eligible for the sneak-attack bonus) until fully ALERTED — i.e. while UNAWARE, still
## DETECTING, or INVESTIGATING a noise. Once it locks on and engages, no more free sneak damage.
## Civilian-safe: a no-Perception NPC (built off-tree, or before _ready) is never an ambush target.
func is_off_guard() -> bool:
	return _perception != null and _perception.state != Perception.State.ALERTED

## True while this NPC is actively fighting — it has a live hostile target AND has locked on
## (Perception ALERTED, gun up). A talk request is REFUSED while busy (see Talkable.start_talk /
## prompt_talk): you can't chat up an enemy mid-firefight — it only fights, it doesn't talk.
## Civilian-safe / pre-_ready-safe: no _perception (off-tree, before _ready) or no target => false,
## via the same null-guard pattern as is_off_guard().
func is_in_combat() -> bool:
	return _perception != null and is_instance_valid(_target) and _perception.state == Perception.State.ALERTED

## True while the gun is DRAWN (out of the holster) for ANY reason -- engaged, first spotting you (DETECTING), the
## post-combat stand-down beat, or an out-of-combat reload. This reads the SAME holstered flag WeaponStance uses to
## show/hide the held gun model, so the arms hold the weapon exactly when the gun is VISIBLE -- not only while
## ALERTED (is_in_combat). A holstered / disarmed / dry NPC reads false, so the body-swap arms drop to the by-side
## pose (and a fists brawler, gun holstered, flails on a punch). Off-tree-safe: _weapon is null until the combatant
## path in _ready builds it, so a civilian / unit-test NPC returns false.
func is_holding_gun() -> bool:
	return _weapon != null and _weapon.attack != null and not _weapon.attack.holstered

## True while this NPC is in combat OR actively HUNTING — locked on (ALERTED) or sweeping the last-known
## position (INVESTIGATING). The MusicDirector polls this so the combat music holds through a broken line
## of sight instead of fading out mid-search (MGS-style: the hunt is still the fight). Deliberately a
## SEPARATE predicate from is_in_combat, whose ALERTED-only meaning gates dialogue refusal + the reckless-
## fire remarks — an investigating NPC should still refuse none of those differently.
func is_hunting() -> bool:
	if _perception == null or not is_instance_valid(_target):
		return false
	return _perception.state == Perception.State.ALERTED or _perception.state == Perception.State.INVESTIGATING

## True if this NPC flees rather than fights (threat_response FLEE). A small typed helper so NpcVoice can gate
## the detection / combat-over barks without reaching the ThreatResponse enum across the class boundary.
func is_fleeing() -> bool:
	return threat_response == ThreatResponse.FLEE

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
	add_to_group(&"Player")
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
	remove_from_group(&"Player")  # Feature #3: no longer a companion — stop reading as the player to enemies
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
	_perception.eye_height = eye_height
	_perception.hearing = hearing
	_perception.just_spotted.connect(_on_spotted)
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
var _executor: GoapExecutor = null  ## the GOAP brain (built in _build_components); drives the AI in place of the match when use_goap

const BARK_LINES: Array[String] = ["Contact!", "Enemy spotted!", "Over there!", "There they are!", "Got a hostile!"]
const BARK_DISTANCE: float = 14.0         ## only bark when within this of the player — the listener (2D audio + world text)
const BARK_COOLDOWN_MS: int = 6000        ## per-NPC: each NPC barks at most this often (NpcVoice reads it)
var _bark_until_msec: int = -100000              ## while now < this, a bark of ours is still on screen -> suppress new ones
var _bark_bubble: Node3D = null                  ## the live bark speech bubble (force-cleared on entering dialogue)
const THANKS_LINES: Array[String] = ["Hey, thanks!", "Thanks for the help!", "Appreciate it!", "Nice shot!", "Good lookin' out!"]

## Death-witness reactions (FNV-style): when the PLAYER kills an NPC, other NPCs within DEATH_WITNESS_RADIUS
## react. A co-aligned peer cries "Murderer!" (DEATH_ALLY_LINES); an unallied bystander remarks on a HOSTILE
## enemy's death by its OWN disposition — a friendly ally approves (DEATH_APPROVE_LINES), anyone else
## questions/shrugs (DEATH_QUESTION_LINES). Routed through react_remark, so each witness self-filters
## (non-hostile, out-of-combat, has a Talkable) and shares the per-NPC + spoken bark cooldowns.
const DEATH_WITNESS_RADIUS: float = 18.0
const DEATH_APPROVE_LINES: Array[String] = ["Good riddance!", "Nice work.", "One less to worry about.", "Had it coming."]
const DEATH_QUESTION_LINES: Array[String] = ["Why'd you do that?", "Hmmph.", "Was that necessary?", "Hey — easy!"]
const DEATH_ALLY_LINES: Array[String] = ["Murderer!", "You killed them!", "Monster!"]

## A wounded ally (companion) cries out ONCE when its HP drops to/below HURT_BARK_HP_FRAC of max. Played
## even mid-combat (via _cry_wounded, which bypasses react_remark's out-of-combat gate).
const HURT_BARK_HP_FRAC: float = 0.35
const HURT_LINES: Array[String] = ["I'm hurt...", "Not sure I'm gonna make it...", "I'm hit!", "I can't take much more!"]

## FNV-style hover greeting: a short line the NPC speaks when the player's crosshair first lands on it
## (non-hostile, idle NPCs only). Cooldown-gated so glancing back and forth doesn't spam it.
const GREET_COOLDOWN_MS: int = 9000
const GREET_LINES: Array[String] = ["You need something?", "Hey there.", "What is it?", "Yeah?", "Hm?", "Can I help you?", "Good to see you."]

## Combatant / sentry call-outs: a reload shout ("Reloading!") when the AI ducks to reload, a combat-over
## line ("Lost 'em.") when a fighter gives up the chase, and a softer LOST-INTEREST line ("Must be gone
## now.") when an NPC that only NOTICED you (heard/glimpsed, never engaged) gives up searching and goes idle.
## All reuse the bark cooldowns.
const RELOAD_LINES: Array[String] = ["Reloading!", "Cover me, reloading!", "Changing mags!", "Reloading — hold on!", "Need a second!"]
const COMBAT_END_LINES: Array[String] = ["Where'd they go?", "Lost 'em.", "Must've run off.", "Guess that's it.", "Stay sharp.", "All clear."]
const LOST_INTEREST_LINES: Array[String] = ["Must be gone now.", "Nothing there.", "Must've imagined it.", "Probably nothing.", "Hm... guess it was nothing."]
## Panic call-outs — said the moment a fighter BREAKS and flees (temperament flip under fire), instead of the
## silence a fleer otherwise keeps. Overridable per archetype via BarkSet.flee.
const FLEE_LINES: Array[String] = ["Forget this!", "I'm out of here!", "Retreat!", "Too much — falling back!", "Nope, I'm done!", "Every man for himself!"]
## Spotted-a-body call-outs — said the moment an UNAWARE NPC notices a discoverable corpse (stealth
## body-discovery). A wary "someone's been here" beat, not a combat shout. Overridable per archetype via
## BarkSet.check_body.
const CHECK_BODY_LINES: Array[String] = ["Hey — a body!", "Someone's dead over here!", "What happened here?", "We've got a body!", "Oh no — is that...?", "Who did this?"]

## Player-attack reactions (fired from _on_damaged_by via NpcVoice): a hit on a non-hostile NPC that does
## NOT flip it (an ally absorbing stray fire under friendly_aggro_threshold) draws the WARNING; the hit that
## DOES flip it (the threshold crossed, or a neutral's first hit) gets the AGGRO snap.
const WARN_ATTACK_LINES: Array[String] = ["Cut that out!", "Hey! Watch it!", "Stop that!", "Watch your fire!", "Hey — careful!"]
const AGGRO_LINES: Array[String] = ["Alright, that does it!", "That does it!", "You asked for it!", "Now you've done it!"]

## Music reactions (jukebox): an idle, non-hostile NPC that can HEAR a playing radio (within its audible_radius)
## comments ONCE on the song/playlist QUALITY -- a deterministic MusicQuality score of the radio's text bucketed
## into a tier. Routed through react_remark, so each NPC self-filters (non-hostile, out-of-combat, has a Talkable)
## + shares the bark cooldown. OFF by default (GameSettings.npc_ai.music_reactions). preload (not the bare
## class_name) so the suite resolves it before the editor scans the new script.
const MQ = preload("res://scripts/components/music_quality.gd")
const MUSIC_AWFUL_LINES: Array[String] = ["Ugh, turn that off.", "My ears...", "What IS this racket?", "Awful. Just awful."]
const MUSIC_MEH_LINES: Array[String] = ["Eh, it's alright.", "Heard worse.", "Background noise, I guess.", "It'll do."]
const MUSIC_GOOD_LINES: Array[String] = ["Oh, nice tune.", "Now this is good.", "I like this one.", "Not bad at all."]
const MUSIC_GREAT_LINES: Array[String] = ["Oh I LOVE this song!", "Turn it UP!", "This is my JAM!", "Now we're talking!"]
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
	var hold := maxf(POPUP_HOLD, 0.8 + float(line.length()) * 0.09)
	return int((hold + POPUP_FADE) * 1000.0)

## Emit a bark — float the bubble + (when near the player) speak it — after a tiny RANDOM reaction delay
## so NPCs don't react instantly (reads more natural). The bubble is world-space (distance-limits itself);
## the spoken line is gated on proximity to the player so a distant NPC's shout isn't synthesized inaudibly.
## Bails if we die during the brief delay; suppressed while a prior bark OF OURS is still showing.
func _emit_bark(line: String, voice: VoiceData) -> void:
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
	var player := _real_player()
	if player == null or global_position.distance_to(player.global_position) > BARK_DISTANCE:
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

## A music comment keyed to a quality TIER (jukebox) -- routes the tier's line pool through react_remark, so the
## same non-hostile / out-of-combat / has-Talkable self-filter + bark cooldown apply. Called from _react_music.
func react_music(tier: int) -> void:
	react_remark(_music_lines(tier))

func _music_lines(tier: int) -> Array[String]:
	match tier:
		MQ.Tier.AWFUL: return MUSIC_AWFUL_LINES
		MQ.Tier.GOOD: return MUSIC_GOOD_LINES
		MQ.Tier.GREAT: return MUSIC_GREAT_LINES
		_: return MUSIC_MEH_LINES

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

## A co-aligned ally? Same faction (or a positive faction relation); unaligned NPCs have no allies. Facade
## onto HostilityHelpers. Used by the damage handler (don't aggro an ally that hit us) AND NpcVoice's
## death-witness reaction — a general alliance query, so it stays on the NPC.
func _is_ally_of(other: NPC) -> bool:
	if other == null or other == self:
		return false
	return HostilityHelpers.npc_vs_npc_allied(faction, other.faction)

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
	# When the PLAYER crippled a limb of ours, toast it to them by NAME + the part (e.g. "Crippled Kyle's
	# arm"). Fires for any crippled limb, even if the hit was lethal.
	if attacker != null and attacker.is_in_group(&"Player") and not (attacker is NPC):
		var part_name := _cripple_part_name(part)
		var p := _real_player()
		if not part_name.is_empty() and p != null and p.has_method(&"notify_toast"):
			var who: String = display_name if not display_name.is_empty() else "Enemy"
			p.notify_toast("Crippled %s's %s" % [who, part_name], Color(1.0, 0.82, 0.3))
	if _dead or hp <= 0.0:
		return  # but a dying NPC doesn't cry out "My leg!"
	var pname := _cripple_part_name(part)
	if pname.is_empty():
		return
	var talkable := _find_talkable()
	if talkable == null:
		return
	_emit_bark("My " + pname + "!", talkable.voice)

func _cripple_part_name(part: int) -> String:
	match part:
		BodyPart.HEAD:
			return "head"
		BodyPart.ARMS:
			return "arm"
		BodyPart.LEGS:
			return "leg"
	return ""

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

## The human player (the bark's listener), NOT a companion — companions join the &"Player" group for
## enemy targeting (#3), so pick the group member that is NOT an NPC.
func _real_player() -> Node3D:
	for p in get_tree().get_nodes_in_group(&"Player"):
		if p is Node3D and not (p is NPC):
			return p as Node3D
	return null

static var _bubble_bg_tex: ImageTexture

## A cached 1x1 white texture for the bark bubble's tinted background sprite.
static func _bubble_bg_texture() -> ImageTexture:
	if _bubble_bg_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_bubble_bg_tex = ImageTexture.create_from_image(img)
	return _bubble_bg_tex

## Float a short text callout above this NPC's head — the bark shown like the "!" alert. Mirrors
## _popup_icon exactly (billboarded, no-depth, parented to this NPC so it FOLLOWS our movement — and now is
## freed with us, which is fine — faded + freed on the same POPUP_HOLD/POPUP_FADE beats) but with a Label3D instead of a Sprite3D.
## Floats well above POPUP_HEAD_Y so the balloon + its tail clear the "!" alert icon at the head.
func _popup_text(text: String) -> void:
	if text.is_empty() or not is_inside_tree():
		return
	# A world-space SPEECH BUBBLE above the head (parented to this NPC so it follows us as we move): a black
	# panel + the bark text + a small downward "▼" tail. All Y-billboarded (BILLBOARD_FIXED_Y) so they yaw
	# to the camera TOGETHER as one upright card — the tail then stays dead-centre below the panel from any
	# angle instead of drifting (per-child FULL billboard tilted each by a different amount = the tail and
	# balloon "not syncing up"). Floated well above POPUP_HEAD_Y so it clears the "!" alert icon at the head.
	var bubble := Node3D.new()
	add_child(bubble)  # parented to US so the bubble tracks our movement as we walk
	_bark_bubble = bubble  # remember it so entering dialogue can force-clear it (see _clear_bark_bubble)
	bubble.position = Vector3(0.0, POPUP_HEAD_Y + 0.35, 0.0)  # just above the head (was +0.85 — sat too high)

	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y  # yaw-only so the whole bubble stays one upright card
	label.no_depth_test = true   # read through walls / our own mesh, like the "!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.font_size = 56
	label.pixel_size = 0.004     # world metres per font pixel
	label.modulate = Color.WHITE
	label.render_priority = 2    # draw the text OVER the bubble bg
	bubble.add_child(label)

	# Black bubble background, sized to the text (a length heuristic — padding absorbs proportional fonts).
	var w := maxf(float(text.length()) * 0.5 * label.font_size * label.pixel_size, 0.4) + 0.18
	var h := 1.25 * label.font_size * label.pixel_size + 0.12
	# Sprite3D bg — a 1x1 white texture tinted black, scaled to the text box. (A QuadMesh + billboard
	# material rendered edge-on / invisible; a Sprite3D billboards reliably.)
	var bg := Sprite3D.new()
	bg.texture = _bubble_bg_texture()
	bg.modulate = Color(0.0, 0.0, 0.0, 0.92)
	bg.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	bg.shaded = false
	bg.no_depth_test = true
	bg.pixel_size = 1.0
	bg.scale = Vector3(w, h, 1.0)  # 1x1 tex * pixel_size 1.0 = 1 m, scaled to w x h metres
	bg.render_priority = 1
	bubble.add_child(bg)

	# A small black tail under the bubble pointing down at us (a "▼"); same Y-billboard as the panel so it
	# tracks dead-centre below it instead of drifting.
	var tail := Label3D.new()
	tail.text = "▼"
	tail.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tail.no_depth_test = true
	tail.font_size = 48
	tail.pixel_size = 0.004
	tail.modulate = Color(0.0, 0.0, 0.0, 0.92)
	tail.render_priority = 1
	bubble.add_child(tail)
	tail.position = Vector3(0.0, -h * 0.6, 0.0)

	# Hold (longer for longer lines, so there's time to read), THEN fade the whole bubble out together + free.
	# NB: use .parallel() per fade, NOT set_parallel(true) after the interval — the latter runs the fades
	# in parallel with the interval (during the hold), which made the bg vanish early.
	var tween := bubble.create_tween()
	tween.tween_interval(maxf(POPUP_HOLD, 0.8 + float(text.length()) * 0.09))
	tween.tween_property(label, "modulate:a", 0.0, POPUP_FADE)
	tween.parallel().tween_property(bg, "modulate:a", 0.0, POPUP_FADE)
	tween.parallel().tween_property(tail, "modulate:a", 0.0, POPUP_FADE)
	# Label3D draws a separate text OUTLINE whose alpha modulate:a does NOT touch — without this the black
	# "▼" tail (and the text edge) keep their opaque outline after the panel has faded, which reads as the
	# arrow "not syncing up" on fade-out. Fade the outline alpha in lockstep with everything else.
	tween.parallel().tween_property(label, "outline_modulate:a", 0.0, POPUP_FADE)
	tween.parallel().tween_property(tail, "outline_modulate:a", 0.0, POPUP_FADE)
	tween.tween_callback(_on_bark_bubble_finished.bind(bubble))

## Natural end of a bark bubble's fade: free it + drop our handle (so _clear_bark_bubble has nothing stale).
func _on_bark_bubble_finished(bubble: Node3D) -> void:
	if _bark_bubble == bubble:
		_bark_bubble = null
	if is_instance_valid(bubble):
		bubble.queue_free()

## Immediately remove the current bark speech bubble (if any) and clear the no-overlap gate — called on
## entering dialogue so a lingering bark balloon doesn't hang over the conversation.
func _clear_bark_bubble() -> void:
	if is_instance_valid(_bark_bubble):
		_bark_bubble.queue_free()
	_bark_bubble = null
	_bark_until_msec = 0

## Pop a billboarded icon above this NPC's head, hold briefly, fade its alpha to 0, then free — built
## entirely in code (no scene). Used by the alert "!" and the turn-hostile "negativefriend" cue.
## Mirrors the fade-then-free idiom in effects/blood_splatter.gd (tween modulate:a -> 0, then free);
## the tween is created ON the sprite so it dies with it if this NPC is freed mid-fade.
## extra_y nudges the icon off the default head height so distinct cues don't stack on each other — e.g.
## the "negative" (turned-hostile) cue drops to chest level so it never overlaps the "!" alert.
func _popup_icon(tex: Texture2D, follow: bool = false, extra_y: float = 0.0) -> void:
	# Skip when off-tree (a unit-test NPC built via .new() with no add_child): create_tween() on an
	# orphan node errors and returns null. A real in-tree NPC is unaffected; mirrors the is_inside_tree
	# guards in character.gd / attack.gd / explosion_area.gd.
	if tex == null or not is_inside_tree():
		return
	var icon := Sprite3D.new()
	icon.texture = tex
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # always face the camera, like ambient_dust's motes
	icon.fixed_size = false      # world-space: planted above the head + scales with distance (NOT screen-locked)
	icon.no_depth_test = true    # read through walls / our own mesh so the cue is never occluded
	icon.shaded = false          # flat, unlit (Sprite3D default; set explicitly to match the house look)
	icon.pixel_size = POPUP_WORLD_HEIGHT / maxf(float(tex.get_height()), 1.0)  # ~POPUP_WORLD_HEIGHT m tall, any texture
	if follow:
		# Parent to US so the cue TRACKS our movement — keeps the "!" alert in step with the bark speech
		# bubble (which also follows us). Dies with us, which is fine: we're alive + moving while alerting.
		add_child(icon)
		icon.position = Vector3(0.0, POPUP_HEAD_Y + extra_y, 0.0)
	else:
		# Parent to the tree ROOT + world-position above the head, so the cue SURVIVES our death: one-shotting
		# a friendly still pops the "negative" icon even though we're freed / ragdolled this frame.
		get_tree().root.add_child(icon)
		icon.global_position = global_position + Vector3(0.0, POPUP_HEAD_Y + extra_y, 0.0)
	var tween := icon.create_tween()
	tween.tween_interval(POPUP_HOLD)
	tween.tween_property(icon, "modulate:a", 0.0, POPUP_FADE)
	tween.tween_callback(icon.queue_free)

## Play the sniper charge sting from this NPC's position when it locks on to fire.
func _on_aim() -> void:
	if threat_response == ThreatResponse.FLEE:
		return  # fleers never aim or charge a shot, so no sniper-charge sting
	var now := Time.get_ticks_msec()
	if now - _last_aim_msec < AIM_COOLDOWN_MS:
		return
	_last_aim_msec = now
	# Capture whether we're locking onto the PLAYER right NOW (not 0.1s later when the sting actually plays):
	# in mixed combat the target can flicker in that window, which would otherwise drop the sting to the
	# near-silent vs-NPC volume — reading as "the charge sound didn't play".
	_aim_targeting_player = is_instance_valid(_target) and _target.is_in_group(&"Player")
	# Schedule the charge sting a beat (AIM_SFX_DELAY) later instead of the same frame as the shot —
	# playing it instantly blurs the gunshot and the charge-up together. _physics_process fires it.
	_aim_sfx_delay = AIM_SFX_DELAY

func _build_nav() -> void:
	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.5
	_nav.target_desired_distance = 1.0
	add_child(_nav)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return  # @tool: the AI tick never runs in the editor
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
	# gunshot). Ticked here so it fires whatever AI state the NPC has reached by the time it elapses; the
	# countdown is the root's cadence, the playback (mix/pitch) is the audio child's.
	if _aim_sfx_delay >= 0.0:
		_aim_sfx_delay -= delta
		if _aim_sfx_delay < 0.0 and _audio_cues != null:
			_audio_cues.play_charge_sting(_aim_targeting_player)
	_desired_velocity = Vector3.ZERO  # default: hold position; states below may drive it
	# Bleed the fire charge back down every frame by default; _act_alerted overcomes this only while it
	# has a clear, in-range shot. So whenever the enemy can't see or can't hit you, its wind-up decays
	# toward zero (break line of sight to reset the shot) instead of freezing mid-charge.
	_fire_timer = minf(_shot_interval(), _fire_timer + delta)
	# Re-acquire on a throttle, or immediately when the current target is gone / dead / out of
	# range / no longer hostile. _target_invalid() keeps this an O(1) check most frames; the full
	# O(n) scan only runs on the timer or a genuine invalidation — never an every-frame O(n^2).
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or _target_invalid():
		_acquire_target()
		_retarget_timer = GameSettings.npc_ai.retarget_interval
	# Re-tint the rim if our attitude changed with no provoke (a faction-rep shift — Reputation has
	# no signal, so it must be polled). O(1) per frame; the material only rebuilds on a real change.
	# The NpcOutline child holds the last-tinted Kind + does the has_outline / _flash_material guard.
	if _outline != null:
		_outline.poll()
	if not is_instance_valid(_target):
		# Stealth distraction + body-discovery (no enemy): even with nothing to fight, an UNAWARE NPC can be
		# pulled toward a NOISE (the &"noise" channel) or a BODY and walk over to investigate. _react_unaware
		# is flag-gated + excludes followers, so it returns false instantly when the features are off and this
		# stays byte-identical idle. It runs HERE, before the GOAP seam, so it works on the FSM AND use_goap
		# paths with no GOAP action (and gives no-target body-discovery to both — closing that gap).
		if not _react_unaware(delta):
			# Nothing heard/seen: live a little instead of freezing - wander near spawn (if `wanders`) or just
			# hold position. The common case for a NEUTRAL/FRIENDLY NPC with no enemies. A recruited companion
			# tailing its leader follows via THIS path (_idle -> is_following -> _follow.act), not via GOAP — so
			# "Escort" is not a GOAP goal; follow is an idle sub-behaviour. The executor only ticks once _target
			# is valid (see the seam invariant below).
			_idle(delta, false)
		_react_music(delta)  # passive: glance at + comment on a nearby playing radio (no locomotion; gated OFF by default)
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
	elif _perception.state != Perception.State.UNAWARE:
		_was_aware = true  # DETECTING / INVESTIGATING — noticed something but hasn't locked on
	elif _was_aware:
		if _saw_combat:
			_try_combat_end_bark()
		else:
			_try_lost_interest_bark()
		_saw_combat = false
		_was_aware = false
	# A fleer runs from any threat it has noticed rather than fighting it (no aim, laser, or fire).
	# While still UNAWARE it falls through to the idle branch below, so a coward wanders until it
	# actually spots danger, then bolts. Under use_goap this is owned by the Survive goal + GoapActionFlee
	# instead (gated out here), so the planner — not this pre-seam — decides fleeing; the FSM path is unchanged.
	if not use_goap and threat_response == ThreatResponse.FLEE and _perception.state != Perception.State.UNAWARE:
		_act_flee(delta)
		_hide_laser()
		super._physics_process(delta)
		return
	# THE GOAP SEAM (strangler-fig): when use_goap, the planner-driven executor owns the decision; otherwise the
	# original FSM dispatch (_fsm_tick) runs verbatim. Default false on every scene -> behaviour-preserving.
	#
	# MIGRATION INVARIANT: reached ONLY with a valid _target (the no-target case returned above). The GOAP library
	# (_build_goap_actions/_goals) now covers the full FSM combat dispatch — Idle/Detect/Investigate/Engage — so a
	# target-acquiring NPC fights via the planner. use_goap still defaults false on every scene (this branch is
	# dead until flipped); flipping it per-archetype is gated on the manual-playtest A/B against the FSM, not on
	# more code. (FLEE is still owned by the pre-seam _act_flee above until a Survive goal migrates it.)
	if use_goap and _executor != null:
		_executor.tick(self, delta)
	else:
		_fsm_tick(delta)
	super._physics_process(delta)  # gravity + blast + locomotion move (uses _desired_velocity)

## The FSM decision dispatch (the pre-GOAP brain), extracted VERBATIM from _physics_process so the use_goap
## seam can run it as the byte-for-byte fallback. Migrated goal-by-goal into the GoapExecutor (Phase 3) and
## deleted at cutover (Phase 4); the per-state bodies it calls (_act_alerted/_act_unarmed/_idle/...) stay.
func _fsm_tick(delta: float) -> void:
	match _perception.state:
		Perception.State.UNAWARE:
			# Stealth body-discovery (has-target case): an enemy is in range but we can't see/hear it yet, and
			# we glimpse a fresh body -> investigate it (next frame's match). Off by default
			# (GameSettings.npc_ai.body_discovery) -> _nearest_visible_corpse() is null and the block below runs
			# UNCHANGED (byte-identical FSM). The NO-target case is handled earlier by _react_unaware.
			var corpse := _nearest_visible_corpse()
			if corpse != null:
				_discover_corpse(corpse)
			else:
				# No threat perceived: RAID a nearby container first when it holds a better gun than ours
				# (NpcScavenge owns that walk), else wander (if `wanders`) / return to post — the old default.
				if _scavenge == null or not _scavenge.act(delta):
					_idle(delta, true)
			_hide_laser()
		Perception.State.DETECTING:
			_face_point(_perception.last_known_position, delta)
			_hide_laser()  # detecting only — no laser until it's actually aiming to shoot (ALERTED)
		Perception.State.ALERTED:
			_ensure_armed_from_backpack()  # a disarmed NPC that's since been GIVEN a weapon draws it now
			if _can_fight_with_gun():
				_act_alerted(delta)
			else:
				# No usable gun: a civilian (weapon_data null), or a combatant whose weapon/ammo was
				# pickpocketed (disarmed, or dry with no spare clips). It closes in and throws weak FISTS —
				# the unarmed fallback melee. _act_alerted dereferences _weapon, so only the armed path takes it.
				_act_unarmed(delta)
		Perception.State.INVESTIGATING:
			_investigate_move(delta)
			_hide_laser()  # investigating a noise — not aiming to shoot, so no laser

## No-enemy environmental awareness (the shared engine for stealth distraction + body-discovery): with NO
## acquired target, scan the &"noise" channel (if hearing_initiates) and bodies (if body_discovery) and, on a
## stimulus, drive an INVESTIGATE toward it; age/expire the give-up clock; and walk+search while investigating.
## Returns true when it OWNS this frame's locomotion (we're investigating), so the no-target caller skips the
## plain idle. Returns false INSTANTLY when both features are off, or we're a follower / dead / fleeing / have
## no Perception -> the no-target idle is byte-identical. Runs pre-seam, so it serves the FSM AND use_goap
## paths (and gives no-target body-discovery to both). In-tree (group scans + LOS), so it's playtest-verified;
## the pure gates (Corpse.noticeable, NoiseSource.audible) carry the unit tests.
func _react_unaware(delta: float) -> bool:
	var noise_on: bool = GameSettings.npc_ai.hearing_initiates and _perception != null and _perception.hearing
	var corpse_on: bool = GameSettings.npc_ai.body_discovery and _perception != null
	if not noise_on and not corpse_on:
		return false
	if _perception == null or _dead or hp <= 0.0 or is_fleeing() or is_following():
		return false
	# Age the give-up clock EVERY frame: sense() with no target reports nothing from either sense, so it only
	# winds an in-progress investigation down toward UNAWARE (a brand-new or refreshed one stays put below).
	_perception.is_hostile = false
	_perception.sense(delta)
	# (Re)point the investigation at the strongest LIVE stimulus, but THROTTLE the expensive group scans + LOS
	# rays (the walk below still runs every frame off last_known_position). Noise first (an ongoing sound
	# outranks a static body); a heard source re-points each scan it persists (investigate_point refreshes the
	# clock), so we track a moving decoy / a still-shooting player. A body is the fallback when nothing's audible.
	_distraction_scan_t -= delta
	if _distraction_scan_t <= 0.0:
		_distraction_scan_t = GameSettings.npc_ai.distraction_scan_interval
		if noise_on:
			var src := _loudest_noise()
			if src != null:
				_perception.investigate_point(src.global_position)  # alerting "!" — the player wants to see the lure land
		if _perception.state != Perception.State.INVESTIGATING and corpse_on:
			var corpse := _nearest_visible_corpse()
			if corpse != null:
				_discover_corpse(corpse)
	# Investigating now -> walk + search, and remember it so we can mutter "must've been nothing" on giving up.
	if _perception.state == Perception.State.INVESTIGATING:
		_investigate_move(delta)
		_was_distracted = true
		return true
	if _was_distracted:
		_was_distracted = false
		_try_lost_interest_bark()  # the investigation just expired with nothing found
	return false

## The loudest &"noise" source currently reaching us, or null. Distance-based, with WALL occlusion folded in
## (Perception.hearing_attenuation cuts a source's effective radius when a wall sits between us and it — off by
## default, so it's distance-only as before). Picks by the OCCLUSION-ADJUSTED reach, so a clear soft source can
## beat a walled-off loud one. The player emits one live; thrown decoys / ambient machines add more.
func _loudest_noise() -> NoiseSource:
	var me := global_position
	var best: NoiseSource = null
	var best_reach := 0.0
	for n in get_tree().get_nodes_in_group(NoiseSource.GROUP):
		var src := n as NoiseSource
		if src == null:
			continue
		var reach := src.radius
		if _perception != null:
			reach *= _perception.hearing_attenuation(src.global_position)
		if not NoiseSource.audible(reach, src.global_position, me):
			continue
		if best == null or reach > best_reach:
			best = src
			best_reach = reach
	return best

## Passive MUSIC reaction (NO locomotion): a calm, idle NPC that can HEAR a playing radio turns its head toward it
## (via head_look_point) and comments ONCE on the song/playlist quality. Gated OFF by default
## (GameSettings.npc_ai.music_reactions); only runs in the no-target idle path and ONLY while UNAWARE -- a foe or a
## noise it's chasing always wins (it never abandons its post to walk over). Throttled like the distraction scan;
## the bark self-throttles. Sets _attending_radio (the head-look's lowest-priority target). In-tree only.
func _react_music(delta: float) -> void:
	if not GameSettings.npc_ai.music_reactions or _dead or hp <= 0.0 or is_following():
		_attending_radio = null
		return
	# Only a relaxed NPC enjoys music -- detecting / investigating / alerted all outrank it.
	if _perception != null and _perception.state != Perception.State.UNAWARE:
		_attending_radio = null
		return
	_music_scan_t -= delta
	if _music_scan_t > 0.0:
		return
	_music_scan_t = GameSettings.npc_ai.distraction_scan_interval
	var radio := _nearest_audible_radio()
	_attending_radio = radio
	if radio == null:
		_music_commented_radio = null  # out of range / switched off -> a fresh comment when we next attend one
		return
	if radio != _music_commented_radio:
		_music_commented_radio = radio
		react_music(MQ.tier(str(radio.call(&"quality_text")),
			GameSettings.npc_ai.music_tier_meh, GameSettings.npc_ai.music_tier_good, GameSettings.npc_ai.music_tier_great))

## The nearest PLAYING radio within its own audible_radius of us, or null. Duck-typed over the &"music" group (a
## radio joins it while on) so npc.gd never references the Radio class (radio.gd already references NPC -- a hard
## type both ways would be a cyclic class reference). In-tree (group scan + global_position).
func _nearest_audible_radio() -> Node3D:
	var me := global_position
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(&"music"):
		if not (n is Node3D) or not n.has_method(&"is_playing") or not n.has_method(&"quality_text"):
			continue
		var radio := n as Node3D
		if not bool(radio.call(&"is_playing")):
			continue
		var reach := float(radio.get(&"audible_radius"))
		var d := me.distance_to(radio.global_position)
		if d <= reach and d < best_d:
			best_d = d
			best = radio
	return best

## Walk to the last-known spot and, on arrival, SWEEP the view searching for the source. While traveling the
## give-up clock is held (refresh_investigation) so forget_time measures SEARCH time, not the walk — a distant
## source used to burn the whole budget en route and give up on arrival. Shared by the FSM INVESTIGATING arm
## and the no-target distraction pass (_react_unaware), so both read identically.
func _investigate_move(delta: float) -> void:
	if _move_toward(_perception.last_known_position):
		_face_travel(delta)
		_perception.refresh_investigation()
	else:
		_search_sweep_t += delta
		var sweep := Vector3(sin(_search_sweep_t * search_sweep_rate), 0.0, cos(_search_sweep_t * search_sweep_rate))
		_face_point(global_position + sweep * 4.0, delta)

## Nearest fresh, undiscovered body this NPC can SEE (range gate + a line-of-sight ray), or null. The SCAN
## half of stealth body-discovery; the caller decides the reaction (see _discover_corpse). Null when the
## feature is off (GameSettings.npc_ai.body_discovery) or we can't sense (dead / fleeing / no Perception).
func _nearest_visible_corpse() -> Corpse:
	if not GameSettings.npc_ai.body_discovery:
		return null
	if _perception == null or _dead or hp <= 0.0 or is_fleeing():
		return null
	var sight := _perception.sight_range
	var eye := global_position + Vector3.UP * _perception.eye_height
	for c in get_tree().get_nodes_in_group(Corpse.GROUP):
		if not (c is Corpse) or (c as Corpse).discovered:
			continue
		var cpos := (c as Node3D).global_position
		if not Corpse.noticeable(cpos, global_position, sight):
			continue
		if _corpse_occluded(eye, cpos):
			continue
		return c as Corpse
	return null

## React to discovering a body: CLAIM it (so the neighbourhood doesn't pile onto one corpse), CALL OUT
## ("Hey — a body!"), and INVESTIGATE the spot QUIETLY. Shared by the has-target FSM UNAWARE arm and the
## no-target distraction pass. The bark fires FIRST and the investigate is non-alerting (investigate_point's
## `alerting=false`), so a corpse never mislabels as an enemy "!" sighting and the combat "Enemy spotted!"
## detection bark can't win the bark cooldown and swallow the body line (a real bug on the has-target path).
func _discover_corpse(c: Corpse) -> void:
	c.discovered = true
	_try_check_body_bark()
	_perception.investigate_point(c.global_position, false)  # walk over + search — quiet, NOT a fire-ready ALERTED

## True when solid geometry sits between our eyes and the body — a WALL blocks the sighting. A ragdoll / loot
## corpse resting AT the death spot is NOT an occluder: the ray hits it right at the end (≈ full distance), so
## we only count a hit that lands well SHORT of the body. World-guarded so off-tree callers never raycast.
func _corpse_occluded(eye: Vector3, cpos: Vector3) -> bool:
	var world := get_world_3d()
	if world == null or not world.space.is_valid():
		return false
	var to := cpos + Vector3.UP * 0.3  # aim a touch above the floor (body height), not at the ground plane
	var q := PhysicsRayQueryParameters3D.create(eye, to)
	q.exclude = [self]
	var hit := world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var hit_pos: Vector3 = hit.get("position")
	return eye.distance_to(hit_pos) < eye.distance_to(to) - 0.5

## Alerted (combatant only): track the target, keep the laser hot, and fire on cadence while clear.
func _act_alerted(delta: float) -> void:
	var aim := _aim_point()
	# How close we WANT to be SCALES with the weapon (see _engage_range): close until comfortably inside that
	# engage range (engage_range_fraction pulls it just inside), then hold + fire. The SAME range gates the
	# fire below, so the NPC always closes to where it can actually shoot.
	var engage_dist := _engage_range()
	if global_position.distance_to(aim) > engage_dist * engage_range_fraction:
		_move_toward(aim)
	_face_point(aim, delta)  # keep aiming at the target even while strafing, so a dodge reads as a sidestep
	# Combat dodge (Feature #5): occasionally break into a brief lateral strafe instead of holding still.
	# Runs AFTER the close-in move so an active dodge overrides _desired_velocity (the strafe wins for its
	# short burst); facing still tracks the target above, so it keeps the gun on you mid-sidestep.
	_maybe_dodge(delta, aim)
	# Laser opacity AND the player's aim radial reflect the shot's charge: 0 right after firing,
	# ramping to 1 (opaque / about to fire) as the cooldown elapses.
	var charge := clampf(1.0 - _fire_timer / maxf(_shot_interval(), 0.001), 0.0, 1.0)
	var hit := _aim_laser_at(aim, charge)
	# Point-blank override: when the target is right on top of us the LOS ray starts INSIDE its collider and
	# registers NO hit (Godot rays ignore the shape they begin in), which used to read as "no clear shot" — so
	# an enemy crowded by the player, or one charged down by a melee NPC, just stood there holding fire. Within
	# point-blank range (GameSettings.npc_ai) we treat the shot as clear regardless (you're touching them;
	# you can pull the trigger).
	var clear: bool = (not hit.is_empty() and hit.get("collider") == _target) \
			or global_position.distance_to(aim) <= GameSettings.npc_ai.point_blank_range
	# Reload the instant we run dry — even with no clear shot or out of range — so the enemy ducks
	# and reloads behind cover instead of standing empty until you peek. AI has no reload input, so
	# trigger it directly; is_busy() then blocks the fire below until the fresh clip is up.
	if _weapon.current_ammo == 0 and not _weapon.is_busy() and _weapon.ammo != null and _weapon.ammo.has_reload_supply():
		_weapon.reload()
		_try_reload_bark()
	# A shot only winds up with a clear line, the target inside our engage range (which SCALES with the
	# weapon — see _engage_range, computed above), AND the weapon actually READY: not mid-reload/swap and
	# with ammo. Gating the WIND-UP on readiness (not just the fire) makes the NPC visibly pause to reload
	# instead of charging straight through the reload and firing the instant the fresh clip lands.
	var can_shoot: bool = clear and global_position.distance_to(aim) <= engage_dist \
			and not _weapon.is_busy() and _weapon.current_ammo != 0
	if can_shoot:
		if not _charging:
			_charging = true
			_on_aim()  # lock-on charge sting, now only once we can actually hit you
		# _physics_process bled the timer +delta this frame; subtract 2*delta to net the -delta wind-up.
		_fire_timer = maxf(0.0, _fire_timer - 2.0 * delta)
		# Incoming-shot warning: a beat before the shot, beep 2D so the player always hears it. The
		# BEEP_LEAD_TIME window is our firing cadence; the beep's mix/pitch is the audio child's.
		if not _warned and _fire_timer <= BEEP_LEAD_TIME \
				and is_instance_valid(_target) and _target.is_in_group(&"Player"):
			_warned = true
			if _audio_cues != null:
				_audio_cues.play_incoming_beep()
	else:
		# Lost the shot (LOS broken / out of range): the charge bleeds back down in _physics_process.
		# Re-arm the lock-on STING immediately so re-acquiring the target always re-telegraphs (this is why
		# the sting was sometimes missing); AIM_COOLDOWN_MS throttles it so a fast peek can't spam it. The
		# louder incoming BEEP still only re-arms on a FULL bleed, so it won't re-warn on every bob.
		_charging = false
		if _fire_timer >= _shot_interval():
			_warned = false
	if can_shoot and _fire_timer <= 0.0 and _weapon.current_ammo != 0:
		# Roll a miss only on shots AT THE PLAYER ("npcs firing at you"); on a miss the shot deflects wide
		# (get_aim_direction consumes _shot_miss) and a ricochet whiffs past. Default miss_chance 0 = never.
		_shot_miss = miss_chance > 0.0 \
				and is_instance_valid(_target) and _target.is_in_group(&"Player") \
				and randf() < miss_chance
		_weapon.attack.try_fire()
		if _shot_miss and _audio_cues != null:
			_audio_cues.play_miss()
		_fire_timer = _shot_interval()
		_warned = false  # re-arm the warning for the next shot
		# Drop back to "not charging" so the next shot's lock-on sting only re-fires if we're STILL in
		# range next frame. A melee swing that knocks the player out of range then won't phantom-charge
		# (and re-play the sting) the instant the attack finishes; it re-stings when it re-closes to range.
		_charging = false
	# Pass whether we can actually fire on the player RIGHT NOW: the glint clears the instant we lose the
	# clear shot, instead of lingering at our position through the post-shot / lost-LOS charge bleed.
	_report_aim(charge, can_shoot)

## Unarmed melee fallback (a combatant with no usable gun, OR a civilian brawler): close to fist reach, then
## wind up the punch with the SAME charge telegraph as a gun shot — the charging laser beam, the aim radial
## (_report_aim), the lock-on sting (_on_aim), and the incoming beep a beat before impact — so a melee reads
## like an incoming shot. Reuses _fire_timer + _shot_interval() (the fist's cadence while unarmed). The hit
## (_punch) applies directly via take_damage, so a struck neutral grudges us back.
func _act_unarmed(delta: float) -> void:
	# Unarmed and ALERTED: grabbing a nearby weapon beats punching — while NpcScavenge has a reachable
	# upgrade it owns the locomotion; the fists charge resumes the instant there's nothing to grab.
	if _scavenge != null and _scavenge.act(delta):
		return
	var aim := _aim_point()
	var dist := global_position.distance_to(aim)
	var reach := _engage_range()  # FISTS' reach while unarmed — same weapon-scaled engage logic as the gun
	if dist > reach * engage_range_fraction:
		_move_toward(aim)  # close the gap to fist reach
	_face_point(aim, delta)
	var charge := clampf(1.0 - _fire_timer / maxf(_shot_interval(), 0.001), 0.0, 1.0)
	# Draw the SAME charging beam a gun shot shows, so a winding-up punch telegraphs visually too (the beam
	# glows with the charge). A disarmed combatant still has its laser node; a civilian brawler has none and
	# simply shows no beam. (WeaponStance only hides the laser ONCE on disarm, so re-drawing here persists.)
	if _laser != null:
		_aim_laser_at(aim, charge)
	else:
		_hide_laser()
	var can_punch: bool = dist <= reach and is_instance_valid(_target)
	if can_punch:
		if not _charging:
			_charging = true
			_on_aim()  # lock-on charge sting, once we're actually in reach
		# _physics_process bled the timer +delta this frame; subtract 2*delta to net the -delta wind-up.
		_fire_timer = maxf(0.0, _fire_timer - 2.0 * delta)
		if not _warned and _fire_timer <= BEEP_LEAD_TIME \
				and is_instance_valid(_target) and _target.is_in_group(&"Player"):
			_warned = true
			if _audio_cues != null:
				_audio_cues.play_incoming_beep()
	else:
		# Out of reach: the wind-up bleeds back up (in _physics_process); re-arm the telegraph for re-closing.
		_charging = false
		if _fire_timer >= _shot_interval():
			_warned = false
	if can_punch and _fire_timer <= 0.0:
		_punch()
		_fire_timer = _shot_interval()
		_warned = false
		_charging = false
	_report_aim(charge, can_punch)

## Land one weak fist hit on the current target (player or NPC — both are Characters). Routed through
## take_damage, so it triggers the victim's hurt feedback and (for an NPC) the damage-grudge.
func _punch() -> void:
	var victim := _target as Character
	if victim != null:
		victim.take_damage(FISTS.damage, false, self, _aim_point())
	# Throw the fist-strike flail on the swapped arms (drop-in BodyModelSwap), if one's attached -- arms snap up
	# and over toward the target, then ease back to the side. Duck-typed; a non-swapped NPC just has no arms to flail.
	var swap := _find_body_swap()
	if swap != null and swap.has_method(&"strike"):
		swap.call(&"strike")

## Combat dodge (Feature #5): occasionally sidestep instead of standing still while ALERTED on a live
## target. Two phases sharing the dodge_* tuning: an ACTIVE burst (_dodge_t > 0) drives _desired_velocity
## sideways at dodge_speed_fraction of move_speed — overriding the hold/pursuit set by _act_alerted — and
## otherwise a cooldown (_dodge_cd) counts down to the next ROLL, which on success (dodge_chance) picks a
## fresh left/right lateral direction relative to the target and opens a dodge_duration burst. The strafe
## flows through the normal locomotion in apply_velocity() (no teleport, navmesh pathing untouched), so a
## subtle, cooldown-gated weave — not constant jitter. dodge_chance 0 disables it; only ever called with a
## live combat target (from _act_alerted), so it never fires while idle/searching.
func _maybe_dodge(delta: float, aim: Vector3) -> void:
	if _dodge_t > 0.0:
		# Mid-burst: keep driving the chosen lateral direction (overriding pursuit/hold) until it elapses.
		_dodge_t -= delta
		_desired_velocity = _dodge_dir * move_speed * dodge_speed_fraction
		return
	_dodge_cd -= delta
	if _dodge_cd > 0.0 or dodge_chance <= 0.0:
		return
	_dodge_cd = dodge_interval  # rolled this cycle — re-arm whether or not the dodge fires
	if randf() >= dodge_chance:
		return
	# Lateral = horizontal perpendicular to the flat us->target vector, flipped to a random side. Degenerate
	# (standing on the target) -> skip the dodge this cycle rather than strafe in a meaningless direction.
	var to := aim - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	var lateral := to.normalized().cross(Vector3.UP)  # perpendicular in the ground plane
	_dodge_dir = lateral if randf() < 0.5 else -lateral
	_dodge_t = dodge_duration
	_desired_velocity = _dodge_dir * move_speed * dodge_speed_fraction

# --- Locomotion: NavigationAgent3D pathing composed with the inherited knockback ---
## Path one step toward `target`: sets _desired_velocity along the next path point. Returns
## true while still travelling (false when arrived / no path). Verticality is handled by
## gravity + move_and_slide walking the baked navmesh surface.
func _move_toward(target: Vector3) -> bool:
	if not _nav:
		return false
	_nav.target_position = target
	var to_next: Vector3
	if not _nav.is_navigation_finished():
		# Normal: follow the baked navmesh path (routes around walls + obstacles).
		to_next = _nav.get_next_path_position() - global_position
		if Vector2(to_next.x, to_next.z).length() < 0.05:
			# Path won't advance — navmesh is missing/floating/disconnected under us, so the
			# agent can't route. Head straight at the target so pursuit still works. (Fix the
			# bake for proper wall-avoidance + verticality.)
			to_next = target - global_position
	elif not _nav.is_target_reachable():
		# No navmesh path to you (you dropped off a ledge / off the mesh): commit and head
		# straight for you, walking off the edge if pursuit demands it. Gravity does the fall.
		to_next = target - global_position
		if Vector2(to_next.x, to_next.z).length() < 0.5:
			return false
	else:
		return false  # genuinely arrived
	var climb := to_next.y
	to_next.y = 0.0
	# Hop up toward a higher path point — a ledge, or the far end of an up navigation-link.
	if climb > 0.6 and is_on_floor():
		velocity.y = jump_velocity
	if to_next.length() < 0.05:
		return false
	_desired_velocity = to_next.normalized() * _current_move_speed()
	return true

func _face_travel(delta: float) -> void:
	if _desired_velocity.length_squared() > 0.0001:
		_face_point(global_position + _desired_velocity, delta)

## Non-combat idle update — facade onto NpcLocomotion (companion-tail -> wander -> return-to-post / hold).
## No-op off-tree (no locomotion child), matching the old behaviour (no follow / wanders / post there).
func _idle(delta: float, return_to_post: bool) -> void:
	if _locomotion != null:
		_locomotion._idle(delta, return_to_post)

## A random point on the disc of radius wander_radius around spawn (sqrt keeps it uniformly spread,
## not clustered at the centre).
func _pick_wander_point() -> Vector3:
	var ang := randf() * TAU
	var r := sqrt(randf()) * wander_radius
	return _spawn_position + Vector3(cos(ang) * r, 0.0, sin(ang) * r)

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

## Locomotion + knockback: ease horizontal velocity toward the desired (nav) velocity — which also
## bleeds off a blast and brakes to a stop when idle (a target-less NPC has _desired_velocity ZERO,
## so this move_toward doubles as the knockback friction) — then add the decaying blast impulse and
## slide, with the same fall-damage tail as Character.
func apply_velocity() -> void:
	# move_and_slide needs a live physics space; bail when we're not in one (e.g. a unit
	# test instantiates the NPC outside a World3D yet still ticks _physics_process).
	var world := get_world_3d()
	if world == null or not world.space.is_valid():
		return
	# Anti-stuck: while escaping a blocker (flagged by _update_stuck last frame), steer ALONG it instead of
	# pressing straight at the path point. Only overrides when we're actually trying to move somewhere.
	if _unstick_t > 0.0 and _unstick_dir.length_squared() > 0.0001 and Vector2(_desired_velocity.x, _desired_velocity.z).length() > 0.1:
		_desired_velocity = _unstick_dir * _current_move_speed()
	var horizontal := Vector2(velocity.x, velocity.z)
	var desired_h := Vector2(_desired_velocity.x, _desired_velocity.z)
	var rate := move_accel if is_on_floor() else air_accel
	horizontal = horizontal.move_toward(desired_h, rate * get_physics_process_delta_time())
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	velocity += explosion_velocity
	var pre_move_velocity := velocity
	var was_grounded := is_on_floor()
	move_and_slide()
	if is_on_floor() and not was_grounded:
		_apply_fall_damage(-pre_move_velocity.y)
	_push_interactables(pre_move_velocity)
	velocity -= explosion_velocity / blast_damp_divisor
	_update_stuck(get_physics_process_delta_time())

## Anti-stuck: when the NPC WANTS to move but a WALL is eating its velocity (it's pressed against a near-
## vertical surface AND its actual speed is well below the intended), veer ALONG that wall toward the goal
## for UNSTICK_TIME so it slips around instead of grinding in place. apply_velocity applies the resulting
## _unstick_dir while _unstick_t is live; two NPCs pressing on each other get opposite contact normals, so
## they steer apart. CRITICAL: the floor a grounded NPC stands on is a slide collision too, so we ignore
## floor/ramp contacts (near-vertical normals only) — otherwise every grounded NPC reads as "stuck" and
## side-steps forever, which on a knocked-back NPC compounds with the blast and flings it away. Likewise we
## bail while a blast is still live so anti-stuck never fights knockback.
func _update_stuck(delta: float) -> void:
	if _unstick_t > 0.0:
		_unstick_t -= delta
	var intended := Vector2(_desired_velocity.x, _desired_velocity.z).length()
	# Not trying to move, airborne, or still being knocked back -> not "stuck" (don't fight a blast).
	if intended < 0.1 or not is_on_floor() or explosion_velocity.length() > 1.0:
		_stuck_t = 0.0
		return
	if Vector2(velocity.x, velocity.z).length() >= intended * STUCK_SPEED_FRAC:
		_stuck_t = 0.0
		return  # moving along fine — still making progress
	# Find a WALL we're jammed against (near-horizontal contact normal); skip the floor/ramp we stand on.
	var wall_normal := Vector3.ZERO
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if absf(n.y) < 0.7:
			wall_normal = n
			break
	if wall_normal == Vector3.ZERO:
		_stuck_t = 0.0
		return  # only touching the floor — not pressed against a wall
	_stuck_t += delta
	if _stuck_t < STUCK_TIME:
		return
	_stuck_t = 0.0
	var want := Vector3(_desired_velocity.x, 0.0, _desired_velocity.z).normalized()
	_unstick_dir = wall_slide_dir(wall_normal, want)  # steer along the wall, toward the goal
	_unstick_t = UNSTICK_TIME

## Pure steering math: given the contact normal of the WALL we're jammed against and the direction we WANT to
## head, return the unit horizontal direction ALONG that wall toward the goal — the wall tangent on the side
## with a non-negative dot to `want`. Split out static so _update_stuck's side-selection is unit-testable (the
## rest of _update_stuck is in-tree physics state — playtested).
static func wall_slide_dir(wall_normal: Vector3, want: Vector3) -> Vector3:
	var tangent := Vector3(-wall_normal.z, 0.0, wall_normal.x).normalized()
	return tangent if tangent.dot(want) >= 0.0 else -tangent

# --- Facing (smooth yaw; this model's front is +Z, so yaw = atan2(dx, dz)) ---
func _face_point(point: Vector3, delta: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	_face_yaw(atan2(to.x, to.z), delta)

func _face_yaw(target_yaw: float, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))

# --- Target acquisition ---
## True when `node` is an UNALIGNED-HOSTILE NPC — no faction, standalone disposition HOSTILE (today's
## plain enemy). A companion treats these as fair game when defending its leader even though is_hostile_to
## is false toward them (a FRIENDLY companion has no faction quarrel), without ever turning on a
## neutral/allied bystander. Player / null / non-NPC -> false.
func _is_unaligned_hostile(node: Node) -> bool:
	var npc := node as NPC
	if npc == null or not is_instance_valid(npc):
		return false
	return HostilityHelpers.is_unaligned_hostile(npc.faction, npc.disposition)

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

## Cheap per-frame test: is the current target no longer worth keeping? (gone, freed, out of
## sight_range, or it's no longer something we'd engage — e.g. a provoke wore off, rep shifted, or we
## stopped following so a defend-only target lapses). Forces a re-scan.
## Whether our current target is gone / out of range / no longer an enemy — facade onto NpcTargeting (the
## retarget throttle's O(1) pre-check). True off-tree (no targeting child -> treat as needing a target).
func _target_invalid() -> bool:
	return _targeting._target_invalid() if _targeting != null else true

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

## World point to aim at: the centre of the target's collision capsule (+ optional nudge).
func _aim_point() -> Vector3:
	var node: Node3D = _target_body if is_instance_valid(_target_body) else _target
	return node.global_position + Vector3.UP * target_height

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
	# Unarmed (disarmed / dry): pace to the FISTS cadence so the SAME wind-up + charge telegraph
	# (_act_unarmed / _report_aim) applies to a punch instead of a (stale / absent) gun.
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
	for c in node.get_children():
		if c is Node3D and str(c.name).to_lower() == "muzzle":
			return c as Node3D
		var nested := _find_muzzle_marker(c)
		if nested:
			return nested
	return null

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
	return base * limb_move_multiplier() * encumbrance_move_multiplier() * stats_or_default().move_speed_mult()

## Called by DialogueManager when this NPC becomes / stops being the one being talked to. While
## talking it's frozen, so its aim loop can't hide the laser itself; do it here. The AI re-shows
## the laser on its own once it unfreezes and re-acquires.
func set_in_dialogue(on: bool) -> void:
	if on:
		_hide_laser()
		_clear_bark_bubble()  # drop any lingering bark balloon so it doesn't hang over the conversation

## "Prompt" (not force) this NPC to talk — facade onto the TalkApproach child, which owns the walk-up
## (acknowledge -> close into framing range -> run `on_ready`, the real DialogueManager.start). Called by
## the Talkable / DialogueNPC handler on interact, so a talk press is a REQUEST the NPC chooses to answer,
## not an instant dialogue box. The child refuses it while busy fighting / hostile, dedups a second prompt,
## and on a close-enough NPC just waits TALK_BUFFER then speaks in place. Null off-tree -> no-op.
func prompt_talk(player: Node3D, on_ready: Callable) -> void:
	if _talk != null:
		_talk.prompt_talk(player, on_ready)

## Feed the player's aim indicator our position + how ready we are to fire (0 = just noticing you,
## 1 = locked / about to shoot), so a white radial points at us and ramps opaque.
func _report_aim(charge: float, clear_shot: bool = true) -> void:
	if is_instance_valid(_target) and _target.has_method(&"indicate_aimed_from"):
		var dmg := _attack_damage()
		# Blink the radial in sync with the incoming-shot beep — both fire in the final BEEP_LEAD_TIME window.
		var warning := _fire_timer <= BEEP_LEAD_TIME
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

## Shrink the Man.glb's OWN (skinned) head bone to ~nothing so only the swapped-in custom head (head_scene) is
## visible -- the rig's head verts collapse toward the bone origin. A tiny non-zero scale (not 0) avoids a
## degenerate skin matrix. No-op without a rigged "Head" bone (a non-Man.glb body keeps its head). Called deferred
## from _ready only when a custom head was attached, so it's naturally off for a head_scene-less NPC.
func _hide_rig_head() -> void:
	_resolve_head()
	if _head_bone >= 0 and is_instance_valid(_head_skeleton):
		_head_skeleton.set_bone_pose_scale(_head_bone, Vector3.ONE * 0.001)

## First Skeleton3D anywhere under `node`, depth-first (the Man.glb rig sits a few nodes deep under the
## mesh root). Mirrors the recursive _find_muzzle_marker idiom so npc.gd stays self-contained.
func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null

## --- Head-look accessors (READ-ONLY; for the drop-in NpcHeadLookMount component). They expose the visible head
## node + the current glance target so the head can track independently of the body, WITHOUT npc.gd growing any
## head-look behaviour branch -- mirroring the existing _aim_point accessor and changing no NPC state. ---

## The VISIBLE head node the head-look rotates: a BodyModelSwap component's swapped head if one registered (the
## unified character swap), else the legacy head_scene instance under head_node. Null if neither (headless body).
func head_visual() -> Node3D:
	return _swapped_head if is_instance_valid(_swapped_head) else _head_instance

## A BodyModelSwap component hands us its swapped head, so the head-look + sniper glint track IT instead of the
## legacy head_scene head / the Man.glb head bone. Called from the component at runtime (before our _ready runs).
func register_swapped_head(node: Node3D) -> void:
	_swapped_head = node

## Extend Character's outline-overlay pass: ALSO rim the swapped BodyModelSwap character parts (body/head/arms/
## legs). Once a custom model is swapped in, the Man.glb meshes that normally carry the rim are HIDDEN, so the
## outline would vanish without this. Each part wears its OWN copy of the outline (visually identical) chained in
## front of its OWN flash material -- that per-part flash pass is what lets just the struck limb flash on a hit
## (see _flash_damage). Mirrors Character's per-mesh look-at-highlight stash handling. No-op without a swap.
func _apply_overlay_to_meshes(overlay: Material) -> void:
	super(overlay)
	var swap := _find_body_swap()
	if swap == null:
		return
	var parts: Variant = swap.call(&"character_parts")
	if not (parts is Array):
		return
	for entry in parts:
		if not (entry is Dictionary):
			continue
		var key: String = entry.get("key", "")
		var root = entry.get("node", null)
		if key == "" or not (root is Node3D):
			continue
		var part_overlay := _build_part_overlay(overlay, _part_flash_material(key))
		var targets: Array[MeshInstance3D] = []
		_collect_mesh_instances(root, targets)
		for m in targets:
			if m.has_meta(&"talk_prev_overlay"):
				m.set_meta(&"talk_prev_overlay", part_overlay)
			else:
				m.material_overlay = part_overlay

## The overlay a swapped PART wears: the combat outline (a COPY, so its flash next_pass is per-part) chained in
## front of that part's own flash material -- so flashing one limb never lights the others. When there's no
## outline (the incoming overlay IS the bare _flash_material -- outlines disabled, or the initial flash-only
## setup pass), the part just wears its own flash material directly.
func _build_part_overlay(overlay: Material, pf: ShaderMaterial) -> Material:
	if overlay == null or overlay == _flash_material:
		return pf
	var copy := overlay.duplicate() as Material
	copy.next_pass = pf
	return copy

## Get-or-create the persistent flash material for a swapped part. Keyed by a stable string so it survives
## outline re-applies and model rebuilds (an in-flight pulse isn't lost). Same shader/params as the whole-body
## flash from _setup_overlay_chain, just one instance PER part so each can be driven on its own.
func _part_flash_material(key: String) -> ShaderMaterial:
	var pf: ShaderMaterial = _part_flash.get(key, null)
	if pf == null:
		pf = ShaderMaterial.new()
		pf.shader = FLASH_OVERLAY_SHADER
		pf.set_shader_parameter("flash_strength", 0.0)
		_part_flash[key] = pf
	return pf

## The BodyModelSwap child (the drop-in character swap), or null -- duck-typed so npc.gd doesn't hard-depend on it.
func _find_body_swap() -> Node:
	for c in get_children():
		if c.has_method(&"character_parts"):
			return c
	return null

## Flash only the SPECIFIC swapped part the shot hit (head / torso / nearer arm / nearer leg), reusing the same
## body_part_at classifier the limb-damage system uses (so the part that flashes is the part that gets crippled).
## Falls back to the whole-body flash for an unlocated hit, a non-swapped Man.glb body, or a part not modelled.
func _flash_damage(hit_pos: Vector3) -> void:
	if hit_pos.is_finite():
		var key := _hit_part_key(hit_pos)
		if key != "" and _part_flash.has(key):
			_flash_part(key)
			return
	flash_red()

## Map a world-space hit to the swapped-part KEY it struck. Head / torso map directly; arms / legs resolve to
## the nearer of the two mirrored instances by WORLD distance (frame-agnostic -- stays right however the body is
## posed/yawed). "" when there's no swap (so the caller falls back to the whole-body flash).
func _hit_part_key(hit_pos: Vector3) -> String:
	var swap := _find_body_swap()
	if swap == null:
		return ""
	match body_part_at(hit_pos):
		BodyPart.HEAD:
			return "head"
		BodyPart.TORSO:
			return "torso"
		BodyPart.ARMS:
			return _nearer_side_key(swap, hit_pos, "arm_l", "arm_r")
		BodyPart.LEGS:
			return _nearer_side_key(swap, hit_pos, "leg_l", "leg_r")
	return ""

## Of two mirrored parts (left/right arm or leg), the key of whichever is physically closer to the hit. Falls
## back to the modelled side if only one exists, or "" if neither does.
func _nearer_side_key(swap: Node, hit_pos: Vector3, key_l: String, key_r: String) -> String:
	var nl := _swap_part_node(swap, key_l)
	var nr := _swap_part_node(swap, key_r)
	if nl == null:
		return key_r if nr != null else ""
	if nr == null:
		return key_l
	return key_l if nl.global_position.distance_squared_to(hit_pos) <= nr.global_position.distance_squared_to(hit_pos) else key_r

## The swapped part NODE for a key (from the component's character_parts()), or null if that part isn't modelled.
func _swap_part_node(swap: Node, key: String) -> Node3D:
	var parts: Variant = swap.call(&"character_parts")
	if parts is Array:
		for entry in parts:
			if entry is Dictionary and entry.get("key", "") == key:
				var n = entry.get("node", null)
				return n if n is Node3D else null
	return null

## Pulse one swapped part's flash material. Kills any in-flight pulse on the SAME part (a rapid second hit
## restarts it); different parts flash independently on their own tweens.
func _flash_part(key: String) -> void:
	var pf: ShaderMaterial = _part_flash.get(key, null)
	if pf == null:
		return
	var prev: Tween = _part_flash_tweens.get(key, null)
	if prev != null and prev.is_valid():
		prev.kill()
	_part_flash_tweens[key] = _build_flash_tween(pf)

## Whole-body flash. Also pulses EVERY swapped part: an unlocated hit (explosion / fall) should light up the
## whole CUSTOM body, whose parts carry their own flash materials rather than the (hidden) Man.glb's shared one.
func flash_red() -> void:
	super()
	for key in _part_flash:
		_flash_part(key)

## The WORLD POINT this NPC's head should glance at right now, or null when nothing warrants one (the head eases
## back to neutral). Priority: the foe we're already turning the body toward > a nearby real player (only when
## `include_player`, honouring the component's look_at_player toggle) > a noise/corpse spot we're investigating.
## Read-only. Returns Variant so "nothing to look at" stays distinct from the world origin.
func head_look_point(include_player: bool) -> Variant:
	if is_instance_valid(_target):
		return _aim_point()
	if include_player:
		var pl := _real_player()
		if is_instance_valid(pl) and pl.has_method(&"look_target_position"):
			return pl.call(&"look_target_position")  # the player's BODY eye -- stays put through a dialogue camera swing, so the head pitches up/down to it
	if _perception != null and (_perception.state == Perception.State.DETECTING or _perception.state == Perception.State.INVESTIGATING or _perception.state == Perception.State.ALERTED):
		return _perception.last_known_position
	# Lowest priority: a playing radio this idle NPC is enjoying (set by _react_music). A real foe / player /
	# investigation above always wins the head, so it only stares at the radio when nothing else demands attention.
	if is_instance_valid(_attending_radio):
		return _attending_radio.global_position
	return null

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
func _aim_laser_at(point: Vector3, charge: float) -> Dictionary:
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
	# Beam VISUAL hands off to the NpcLaser child. The show_laser export gate + the no-beam case (civilian /
	# off-tree) still hide here and return the ray; otherwise compute the endpoint (where the ray hit, else
	# the full reach) and let the child stretch + tint the beam (it self-hides for a degenerate span).
	if not show_laser or _laser == null:
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
