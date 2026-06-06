class_name NPC
extends Character

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

## This NPC's display name — shown as the speaker label in dialogue (DialogueManager uses it when a
## DialogueLine leaves `speaker` blank). Empty => unnamed, and the dialogue name label stays hidden.
@export var display_name: String = ""

## Master switch for this actor's combat outline. Off => flash-only overlay (no rim).
@export var has_outline: bool = true
## Outline rim colour. Combatants default to black; a friendly NPC can override per instance.
@export var outline_color: Color = Color.BLACK
## Outline thickness fed to the shader's `outline_width` uniform (shader scales it x4 in clip
## space). 0.085 reproduces the intended enemy rim. Was silently ignored pre-Phase-2 because the
## old code set a non-existent `outline_thickness` uniform; the shader only exposes `outline_width`.
@export var outline_width: float = 0.085
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
## The faction this NPC belongs to. NULL => UNALIGNED: the NPC uses its standalone `disposition`
## below instead of faction + player-reputation. Set this to a Faction .tres (e.g. raiders,
## townsfolk) to make the NPC's attitude track the player's reputation with that faction.
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
## Won't shoot past this distance to the target (separate from how far it can SEE). Kept as an NPC stat
## because not every enemy weapon sets an effective_range (e.g. the thrown rock leaves it at 0).
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

@export_group("Perception")
## How far the NPC can see.
@export var sight_range: float = 25.0
## Full view-cone angle (degrees). Outside this off its facing it simply can't see you.
@export var fov_degrees: float = 110.0
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
@export_range(0.0, 1.0) var dodge_chance: float = 0.5
@export var dodge_duration: float = 0.35
@export var dodge_speed_fraction: float = 1.0

@export_group("Behavior")
## How this NPC reacts to a hostile target it has noticed. FIGHT = engage and shoot (the default,
## i.e. today's enemy). FLEE = run away from the threat and never fire (a civilian / coward). Pair
## FLEE + `wanders` + a NEUTRAL/FRIENDLY disposition for a townsperson who only bolts when attacked.
enum ThreatResponse { FIGHT, FLEE }
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
const LASER_MAX_LENGTH := 60.0
## Engagement range a combatant falls back to when its weapon reports 0 effective_range - a
## projectile weapon like the rock / rocket launcher, whose damage rides the projectile rather than
## a hitscan ray. Without this the AI's aim ray would be zero-length, so it never reads a clear shot
## and just walks into your face instead of firing.
const UNRANGED_AIM_FALLBACK := 15.0
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
## A rolled MISS deflects the shot wide by a random angle in this range so it clearly whiffs past you.
const MISS_DEFLECT_MIN_DEG: float = 5.0
const MISS_DEFLECT_MAX_DEG: float = 12.0

## Head-popup icons — billboarded Sprite3D built in code (no .tscn), held then faded + freed.
## EXCLAMATION pops on first alert (alongside the MGS sting); NEGATIVE pops the moment this NPC
## turns hostile / its faction is soured. Source res:// paths used directly (like MGS_ALERT) — the
## exclamation filename literally contains a space and "(1)", which is legal inside the string.
const POPUP_EXCLAMATION = preload("res://assets/textures/exclamation_1 (1).png")
const POPUP_NEGATIVE = preload("res://assets/textures/negativefriend.png")
const POPUP_FRIEND = preload("res://assets/w_friend.png")  # "+friend": shown when you rescue an NPC by killing its attacker
## Reputation gained with a saved NPC's faction when the player kills an NPC that was attacking it.
const SAVE_REP_REWARD: float = 15.0
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
## Target re-acquisition throttle. We do NOT scan every frame (that would be O(n^2) across all NPCs).
## Instead we re-scan every RETARGET_INTERVAL seconds, or immediately when the current target becomes
## invalid / dies / leaves sight_range (handled in _physics_process).
const RETARGET_INTERVAL: float = 0.5

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
var _target: Node3D
var _target_body: Node3D  # target's collision shape (centre tracks crouch); falls back to _target
var _last_attacker: Node3D = null  # most recent hostile that damaged us; favoured over the nearest in _acquire_target
var _hit_by_player: bool = false   # the real player has damaged us (drives the "Hey, thanks!" assist bark on death)
var _hurt_bark_said: bool = false  # a wounded-ally cry has already fired this life (so it only plays once)
var _last_greet_msec: int = -100000  # cooldown for the look-at hover greeting (greet())
var _fire_timer: float = 0.0
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
var _retarget_timer: float = 0.0
## Wander bookkeeping (used only when `wanders`): the current roam destination + a dwell pause.
var _wander_target: Vector3
var _has_wander_target: bool = false
var _wander_dwell: float = 0.0
## The leader this NPC is escorting, or null when not following. Set by start_following() (the dialogue
## "join me" option calls it), cleared by stop_following(). CANONICAL state kept on the root because the
## root's own targeting (_acquire_target / _pick_defend_target) reads it; the FOLLOW BEHAVIOUR (tailing +
## the hidden teleport) lives on the _follow child, which reads this field. While set, the NPC tails the
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

func _ready() -> void:
	super()  # Character._ready(): set hp + build the flash overlay on the mesh tree.
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
		_equip_initial_weapon()  # seed the backpack from weapon_data, then draw it FROM the backpack
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

## Seed the backpack from the assigned weapon_data and DRAW it from the backpack, so a combatant NPC
## fights with an item it actually carries (and therefore drops it on death). If weapon_data isn't a
## registered ItemDb weapon-item, fall back to a direct equip so a custom-weapon NPC still fights (it
## just won't drop a backpack item). Called from _ready's weapon branch, right after _weapon.setup().
func _equip_initial_weapon() -> void:
	var witem: Item = ItemDb.weapon_item_for(weapon_data)
	if witem != null and inventory != null:
		inventory.add(witem)
		inventory.equip_item(witem)  # -> equip_weapon_requested -> _on_equip_weapon_requested below
	elif _weapon != null and _weapon.inventory != null:
		_weapon.inventory.equip(weapon_data)

## The backpack asked to draw `weapon` (from _equip_initial_weapon now, or a looted weapon later). Hand
## it straight to the NPC's weapon hub — an AI needs no swap animation. Overrides Character's no-op hook.
func _on_equip_weapon_requested(weapon: WeaponData) -> void:
	if _weapon != null and _weapon.inventory != null:
		_weapon.inventory.equip(weapon)

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
	return HostilityHelpers.npc_vs_npc_hostile(faction, other_npc.faction)

## Aggro this NPC: become hostile NOW, and — if factioned — drop the player's reputation with that
## faction so the whole faction sours (FNV-style). Idempotent; safe to call every hit. `attacker`
## is accepted so the damage hook can also turn us toward the source.
func provoke(_attacker: Node = null) -> void:
	if not _provoked:
		_provoked = true
		if faction != null:
			Reputation.add_reputation(faction, -Reputation.PROVOKE_REP_PENALTY)
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
			Reputation.add_reputation(saved.faction, SAVE_REP_REWARD)
		saved._popup_icon(POPUP_FRIEND)  # cue floats over the RESCUED NPC (the one we swayed), not our corpse
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
		else:
			provoke(attacker)
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
	# Temperament: a frightened NPC may BREAK and flee once hurt mid-fight. The chance scales with how hurt
	# it is (temperament * fraction of HP lost), so a coward bolts as the fight turns against it; 0 = never.
	if temperament > 0.0 and threat_response != ThreatResponse.FLEE and is_in_combat():
		var fear := temperament * (1.0 - clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0))
		if randf() < fear:
			threat_response = ThreatResponse.FLEE

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
	# Cut our bark ONLY if it's OURS that's currently playing — the OS TTS has no per-utterance stop, so a
	# blanket stop would also silence other NPCs' barks. And never during a conversation (that's the
	# dialogue's own TTS, ended only by the SPEAKER dying, handled in DialogueManager).
	if _bark_speaker == self and not DialogueManager.is_active():
		DisplayServer.tts_stop()
		_bark_speaker = null
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
			Reputation.add_reputation(faction, -Reputation.KILL_REP_PENALTY)
	# Leave a lootable corpse holding our backpack, while it still exists (queue_free is deferred).
	_drop_loot()
	FreezeFrame.pause_briefly(0.015)

## Leave a lootable corpse at the death spot holding a copy of our backpack — a PERSISTENT node, not the
## fading ragdoll, that the player loots with E (LootableCorpse mirrors the talk-handler surface). Spawned
## into our PARENT (the world), not under us, since queue_free is about to free this NPC. No-op when the
## bag is empty (nothing to loot) or we're off-tree.
func _drop_loot() -> void:
	if inventory == null or inventory.is_empty() or not is_inside_tree():
		return
	var world := get_parent()
	if world == null:
		return
	var corpse := LootableCorpse.new()
	corpse.setup(inventory, display_name)
	world.add_child(corpse)
	corpse.global_position = global_position

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
## head (like the "!" alert) AND spoken aloud via OS TTS. Gated on being near the PLAYER (the listener):
## the voice is 2D and the text is world-space, so a far-off callout would blare in your ear / float
## unreadably tiny. A fleer never barks (it's running). Per-NPC cooldown so each calls out on its own beat;
## a SHARED cooldown additionally limits the SPOKEN line to one voice at a time (the text still shows
## per-NPC) so a squad doesn't garble the TTS.
const BARK_LINES: Array[String] = ["Contact!", "Enemy spotted!", "Over there!", "There they are!", "Got a hostile!"]
const BARK_DISTANCE: float = 14.0         ## only bark when within this of the player — the listener (2D audio + world text)
const BARK_COOLDOWN_MS: int = 6000        ## per-NPC: each NPC barks at most this often
const BARK_SPEAK_COOLDOWN_MS: int = 1800  ## SHARED: at most one SPOKEN bark this often (text still shows); avoids TTS garble
var _last_bark_msec: int = -100000               ## per-NPC cooldown
static var _last_spoken_bark_msec: int = -100000 ## shared across NPCs so overlapping voices don't garble
static var _bark_speaker: NPC = null             ## the NPC whose bark TTS is currently playing (clean interrupt-on-death)
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

## Emit a bark — float the bubble + (when near the player) speak it — after a tiny RANDOM reaction delay
## so NPCs don't react instantly (reads more natural). The bubble is world-space (distance-limits itself);
## the SPOKEN line is 2D, so it's gated on proximity to the player AND the shared cooldown (so a squad
## doesn't garble). Bails if we die during the brief delay.
func _emit_bark(line: String, voice: VoiceData) -> void:
	await get_tree().create_timer(randf_range(0.05, 0.08)).timeout
	if _dead or hp <= 0.0 or not is_inside_tree():
		return
	_popup_text(line)
	var player := _real_player()
	if player == null or global_position.distance_to(player.global_position) > BARK_DISTANCE:
		return
	var now := Time.get_ticks_msec()
	if now - _last_spoken_bark_msec >= BARK_SPEAK_COOLDOWN_MS:
		_last_spoken_bark_msec = now
		_speak_bark(line, voice)

func _try_detection_bark() -> void:
	if threat_response == ThreatResponse.FLEE or _dead or hp <= 0.0:
		return
	if not (is_instance_valid(_target) and is_hostile_to(_target)):
		return  # bark for ANY hostile it spotted — the player OR an enemy NPC
	var talkable := _find_talkable()
	if talkable == null:
		return  # only a speaking character (a Talkable) barks; a mute drone stays silent
	var player := _real_player()
	if player == null or global_position.distance_to(player.global_position) > BARK_DISTANCE:
		return  # keep it near the listener — the voice is 2D and the text would be unreadably far
	var now := Time.get_ticks_msec()
	if now - _last_bark_msec < BARK_COOLDOWN_MS:
		return
	_last_bark_msec = now
	_emit_bark(BARK_LINES[randi() % BARK_LINES.size()], talkable.voice)

## Friendly/ally flavour reaction (#2 reckless fire, #3 aimed-at): float + speak a random line — but only
## if this NPC is a non-hostile, out-of-combat speaker (has a Talkable). Reuses the detection-bark cooldowns
## (per-NPC + the shared spoken gate) so reactions never spam or talk over each other.
func react_remark(lines: Array[String]) -> void:
	if lines.is_empty() or is_hostile() or is_in_combat() or _dead or hp <= 0.0:
		return
	var talkable := _find_talkable()
	if talkable == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bark_msec < BARK_COOLDOWN_MS:
		return
	_last_bark_msec = now
	_emit_bark(lines[randi() % lines.size()], talkable.voice)

## A wounded ALLY cries out (e.g. "I'm hurt..."). Unlike react_remark this does NOT gate on being
## out-of-combat (a hurt ally calls out mid-firefight) — it just needs a Talkable + the per-NPC bark
## cooldown. Bark only; the trigger (once, below an HP fraction) lives in _on_damaged_by.
func _cry_wounded() -> void:
	if _dead or hp <= 0.0:
		return
	var talkable := _find_talkable()
	if talkable == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bark_msec < BARK_COOLDOWN_MS:
		return
	_last_bark_msec = now
	_emit_bark(HURT_LINES[randi() % HURT_LINES.size()], talkable.voice)

## Said by an NPC the player just helped (the player damaged the enemy it was fighting, which then died):
## "Hey, thanks!". Non-hostile speakers with a Talkable only; reuses the bark cooldown + reaction delay.
func thank_for_assist() -> void:
	if is_hostile() or _dead or hp <= 0.0:
		return
	var talkable := _find_talkable()
	if talkable == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bark_msec < BARK_COOLDOWN_MS:
		return
	_last_bark_msec = now
	_emit_bark(THANKS_LINES[randi() % THANKS_LINES.size()], talkable.voice)

## A co-aligned ally? Same faction (or a positive faction relation); unaligned NPCs have no allies. Facade
## onto HostilityHelpers (the rules live there). Drives the "Murderer!" death-witness reaction.
func _is_ally_of(other: NPC) -> bool:
	if other == null or other == self:
		return false
	return HostilityHelpers.npc_vs_npc_allied(faction, other.faction)

## Tell every nearby NPC that the player just killed THIS one, so each can react (see _witness_death).
## Called from _on_died ONLY for a player-caused death, so enemy infighting / environmental deaths stay quiet.
func _announce_death_to_witnesses() -> void:
	for n in get_tree().get_nodes_in_group(&"npc"):
		var witness := n as NPC
		if witness == null or witness == self:
			continue
		if global_position.distance_to(witness.global_position) > DEATH_WITNESS_RADIUS:
			continue
		witness._witness_death(self)

## React to having just seen the player kill `victim`: a co-aligned peer is outraged ("Murderer!"),
## while an unallied bystander only remarks on a HOSTILE enemy's death — a friendly ally cheers it,
## everyone else questions/shrugs. react_remark self-filters (a hostile or in-combat witness stays silent,
## a mute has no Talkable) and throttles via the shared bark cooldowns. Bark only — no auto-aggro here.
func _witness_death(victim: NPC) -> void:
	if victim == null or victim == self or _dead or hp <= 0.0:
		return
	if _is_ally_of(victim):
		react_remark(DEATH_ALLY_LINES)
		return
	if victim.is_hostile() and resolved_disposition() == Disposition.Kind.FRIENDLY:
		react_remark(DEATH_APPROVE_LINES)
	else:
		react_remark(DEATH_QUESTION_LINES)

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

## Speak a short greeting when the player's crosshair first lands on this (non-hostile, idle) NPC — the
## FNV-style hover greeting. Cooldown-gated so glancing back and forth doesn't spam it. Routed through the
## bark system (shows the bubble + speaks via TTS near the player). No-op for a mute/hostile/busy/dead NPC.
func greet() -> void:
	if is_hostile() or is_in_combat() or _dead or hp <= 0.0:
		return
	var now := Time.get_ticks_msec()
	if now - _last_greet_msec < GREET_COOLDOWN_MS:
		return
	var talkable := _find_talkable()
	if talkable == null:
		return
	_last_greet_msec = now
	_emit_bark(GREET_LINES[randi() % GREET_LINES.size()], talkable.voice)

## Speak a one-off bark via OS text-to-speech, using the Talkable's VoiceData pitch/rate when set, else a
## default English voice. Interrupts any prior bark; a silent no-op when TTS is unavailable/disabled.
func _speak_bark(text: String, voice: VoiceData) -> void:
	if _dead:
		return  # dead enemies don't talk
	var voices := DisplayServer.tts_get_voices_for_language("en")
	if voices.is_empty():
		return
	var pitch: float = voice.pitch if voice != null else 1.0
	var rate: float = voice.rate if voice != null else 1.0
	# Volume tracks the Voice bus (× Master) like dialogue, scaled to 0.6 so barks stay a touch below
	# focused dialogue — OS TTS can't route through a Godot bus, so the slider is applied here.
	DisplayServer.tts_speak(text, String(voices[0]), TtsSpeaker.voice_tts_volume(0.6), pitch, rate, 0, true)
	_bark_speaker = self  # remember who's speaking so only OUR death cuts this bark (see _on_died)

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
	tween.tween_callback(bubble.queue_free)

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
		_retarget_timer = RETARGET_INTERVAL
	# Re-tint the rim if our attitude changed with no provoke (a faction-rep shift — Reputation has
	# no signal, so it must be polled). O(1) per frame; the material only rebuilds on a real change.
	# The NpcOutline child holds the last-tinted Kind + does the has_outline / _flash_material guard.
	if _outline != null:
		_outline.poll()
	if not is_instance_valid(_target):
		# Nothing hostile around: live a little instead of freezing - wander near spawn (if `wanders`)
		# or just hold position. This is the common case for a NEUTRAL/FRIENDLY NPC with no enemies.
		_idle(delta, false)
		_hide_laser()
		super._physics_process(delta)
		return
	# Hostility gate: _acquire_target only ever returns a target we'd engage, so this stays true while
	# engaged; it cleanly idles a non-hostile NPC with no peers. _treats_as_enemy == is_hostile_to for a
	# non-following NPC, and additionally lets a COMPANION sense/lock the unaligned-hostile foe it's
	# defending its leader against (which is_hostile_to alone would gate out).
	_perception.is_hostile = _treats_as_enemy(_target)
	_perception.sense(delta)
	# A fleer runs from any threat it has noticed rather than fighting it (no aim, laser, or fire).
	# While still UNAWARE it falls through to the idle branch below, so a coward wanders until it
	# actually spots danger, then bolts.
	if threat_response == ThreatResponse.FLEE and _perception.state != Perception.State.UNAWARE:
		_act_flee(delta)
		_hide_laser()
		super._physics_process(delta)
		return
	match _perception.state:
		Perception.State.UNAWARE:
			# No threat perceived: wander (if `wanders`), else walk back to post if knocked away
			# then watch the spawn direction - the unchanged default for a plain enemy.
			_idle(delta, true)
			_hide_laser()
		Perception.State.DETECTING:
			_face_point(_perception.last_known_position, delta)
			_hide_laser()  # detecting only — no laser until it's actually aiming to shoot (ALERTED)
		Perception.State.ALERTED:
			if _weapon != null:
				_act_alerted(delta)
			else:
				# Unarmed NPC (weapon_data null) that still fights: square up and close, but there's
				# no gun to fire. _act_alerted dereferences _weapon, so it's combatant-only.
				var aim := _aim_point()
				if global_position.distance_to(aim) > 2.0:
					_move_toward(aim)
				_face_point(aim, delta)
				_hide_laser()
		Perception.State.INVESTIGATING:
			# Go check the last-known spot; face where it walks, then look around once there.
			if _move_toward(_perception.last_known_position):
				_face_travel(delta)
			else:
				_face_point(_perception.last_known_position, delta)
			_hide_laser()  # investigating a noise — not aiming to shoot, so no laser
	super._physics_process(delta)  # gravity + blast + locomotion move (uses _desired_velocity)

## Alerted (combatant only): track the target, keep the laser hot, and fire on cadence while clear.
func _act_alerted(delta: float) -> void:
	var aim := _aim_point()
	# Close until the target is comfortably inside our weapon's effective range, then hold + fire.
	if global_position.distance_to(aim) > _aim_range() * engage_range_fraction:
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
	var clear: bool = not hit.is_empty() and hit.get("collider") == _target
	# Reload the instant we run dry — even with no clear shot or out of range — so the enemy ducks
	# and reloads behind cover instead of standing empty until you peek. AI has no reload input, so
	# trigger it directly; is_busy() then blocks the fire below until the fresh clip is up.
	if _weapon.current_ammo == 0 and not _weapon.is_busy():
		_weapon.reload()
	# A shot only winds up with a clear line, the target inside our WEAPON's reach (capped by
	# fire_range, NOT merely sight), AND the weapon actually READY: not mid-reload/swap and with ammo.
	# Gating the WIND-UP on readiness (not just the fire) makes the NPC visibly pause to reload instead
	# of charging straight through the reload and firing the instant the fresh clip lands.
	var engage_dist := minf(fire_range, _aim_range())
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

## Non-combat idle update. A recruited COMPANION tails its leader (overriding wander/hold); otherwise
## wanderers roam near spawn, and a plain NPC either returns to its post (return_to_post, when knocked
## away) or holds still — the prior target-less behaviour, so a non-following FIGHT combatant is unchanged.
func _idle(delta: float, return_to_post: bool) -> void:
	if is_following() and _follow != null:
		_follow.act(delta)  # tail the leader (+ the hidden teleport) — the CompanionFollow child owns the drive
		return
	if wanders:
		_wander(delta)
		return
	if not return_to_post:
		return
	if _move_toward(_spawn_position):
		_face_travel(delta)
	else:
		_face_yaw(_spawn_yaw, delta)

## Roam: walk to a random point within wander_radius of spawn, dwell a beat on arrival, then pick a
## fresh one. Reuses the same navmesh pathing + facing as combat pursuit, so it routes around walls.
func _wander(delta: float) -> void:
	if _wander_dwell > 0.0:
		_wander_dwell -= delta  # lingering at a stop, standing where we arrived
		return
	if not _has_wander_target:
		_wander_target = _pick_wander_point()
		_has_wander_target = true
	if _move_toward(_wander_target):
		_face_travel(delta)
	else:
		# Arrived, or the navmesh wouldn't route there: pause, then choose a new spot next time.
		_has_wander_target = false
		_wander_dwell = randf_range(wander_dwell_min, wander_dwell_max)

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

## Flee: each frame, head for a point flee_distance straight away from the threat. Recomputed every
## frame so the destination keeps running ahead of us; we face the way we run and never fire.
func _act_flee(delta: float) -> void:
	var away := global_position - _aim_point()
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(sin(_spawn_yaw), 0.0, cos(_spawn_yaw))  # standing on the threat: bolt spawn-ward
	var flee_to := global_position + away.normalized() * flee_distance
	if _move_toward(flee_to):
		_face_travel(delta)
	else:
		_face_point(flee_to, delta)

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
func _target_invalid() -> bool:
	if not is_instance_valid(_target):
		return true
	if global_position.distance_to(_target.global_position) > sight_range:
		return true
	return not _treats_as_enemy(_target)

## Pick the nearest hostile node: the player plus every NPC peer, filtered by _treats_as_enemy()
## and sight_range, nearest wins. Defaults to the player when it's the only/nearest hostile, so a
## lone player-hostile enemy behaves exactly as before. Throttled by the caller (RETARGET_INTERVAL)
## so this O(n) scan is not an every-frame cost. Also binds Perception to whatever we locked.
## _treats_as_enemy is is_hostile_to() for a non-following NPC, so its targeting is unchanged; a
## FOLLOWING companion additionally defends its leader (see the defend pass first).
func _acquire_target() -> void:
	# Protector duty FIRST: an NPC defending a protectee (a player companion OR a bodyguard) prioritises
	# whoever is threatening its charge (the charge's own attacker if exposed, else a hostile near it) over
	# its own nearest foe — so it peels off to protect them. Skipped entirely for an NPC with no protectee.
	if _protectee() != null:
		var defend := _pick_defend_target()
		if defend != null:
			_last_attacker = null  # a defend target isn't "who hit us"; don't let the attacker-lock fight it
			_set_target(defend)
			return
	# Stay locked on the last character that actually attacked us — while it's still a valid, engageable,
	# in-range threat — instead of being pulled toward whoever is merely nearest (no easy distraction).
	if is_instance_valid(_last_attacker) and _treats_as_enemy(_last_attacker) and global_position.distance_to(_last_attacker.global_position) <= sight_range:
		_set_target(_last_attacker)
		return
	_last_attacker = null  # the aggressor died / fled out of sight_range / is no longer engageable — drop it
	var best: Node3D = null
	var best_d := INF
	# Every member of the &"Player" group is a candidate — the real player AND any recruited COMPANION,
	# which joins that group so a player-hostile enemy targets it too (Feature #3). Iterate them all (not
	# just the first) so adding an ally to the group can never displace the real player from the scan; each
	# gets the same hostility + range test as any NPC. (A companion is ALSO in the npc loop below, but it's
	# friendly there so only a player-hostile enemy ever engages it — and at the same distance, so harmless.)
	for pnode in get_tree().get_nodes_in_group(&"Player"):
		var player := pnode as Node3D
		if not is_instance_valid(player) or not _treats_as_enemy(player):
			continue
		var pd := global_position.distance_to(player.global_position)
		if pd <= sight_range and pd < best_d:
			best = player
			best_d = pd
	for node in get_tree().get_nodes_in_group(&"npc"):
		var npc := node as NPC
		if npc == null or npc == self or not is_instance_valid(npc):
			continue
		if not _treats_as_enemy(npc):
			continue
		var d := global_position.distance_to(npc.global_position)
		if d <= sight_range and d < best_d:
			best = npc
			best_d = d
	_set_target(best)

## Companion defence (Feature I): the foe a following NPC should engage to protect its leader, or null
## if none qualifies. Prefers the leader's MOST-RECENT attacker when the leader exposes one (NPC leaders
## carry `_last_attacker`; the player doesn't), else the nearest hostile-to-the-leader within our sight.
## Every candidate is filtered through _treats_as_enemy so we only ever fight a genuine enemy / an
## unaligned-hostile assailant — NEVER an ally or neutral the leader merely bumped into (no faction conflict).
func _pick_defend_target() -> Node3D:
	var prot := _protectee()
	if not is_instance_valid(prot):
		return null
	# 1) The protectee's own latest attacker, if it publishes one (NPC leaders carry _last_attacker; the
	#    player doesn't). Engage it only if it's in our sight and we'd actually treat it as an enemy.
	var la := prot.get(&"_last_attacker") as Node3D
	if is_instance_valid(la) and _treats_as_enemy(la) \
			and global_position.distance_to(la.global_position) <= sight_range:
		return la
	# 2) Otherwise, the nearest NPC that is hostile TOWARD the protectee and within our reach — i.e. someone
	#    actively menacing our charge. Nearest to US wins so we grab the closest threat first.
	var best: Node3D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(&"npc"):
		var npc := node as NPC
		if npc == null or npc == self or not is_instance_valid(npc):
			continue
		if not npc.is_hostile_to(prot):
			continue  # only step in for foes actually hostile to our charge
		if not _treats_as_enemy(npc):
			continue  # and only ones we'd engage (now includes anyone hostile to the protectee)
		var d := global_position.distance_to(npc.global_position)
		if d <= sight_range and d < best_d:
			best = npc
			best_d = d
	return best

## Bind a freshly-chosen target: cache its root + LOS body (the player exposes "PlayerCollisionShape";
## an NPC falls back to its root collider for the ray identity test), and feed both into Perception.
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
	return w.effective_range if w.effective_range > 0.0 else UNRANGED_AIM_FALLBACK

## Seconds between this NPC's shots: the equipped WEAPON's own attack cadence (attack_speed) scaled by
## rate_of_fire_factor. The weapon is the single source of truth for the rate (this replaced the per-NPC
## fire_cooldown). Floored so the charge math never divides by zero; falls back to a 1s base pre-equip.
func _shot_interval() -> float:
	var w: WeaponData = _weapon.equipped_weapon if _weapon else null
	var base: float = w.attack_speed if w != null else 1.0
	return maxf(0.05, base * rate_of_fire_factor)

## Deflect a shot wide so it clearly MISSES: rotate `dir` by a random 5–12° around a random axis
## perpendicular to it. Used for an NPC's rolled miss (miss_chance) — see get_aim_direction.
func _deflect_for_miss(dir: Vector3) -> Vector3:
	var d := dir.normalized()
	var perp := d.cross(Vector3.UP)
	if perp.length() < 0.001:
		perp = d.cross(Vector3.RIGHT)  # aiming near-vertical: pick a different reference axis
	perp = perp.normalized().rotated(d, randf() * TAU)  # random direction around the aim axis
	return d.rotated(perp, deg_to_rad(randf_range(MISS_DEFLECT_MIN_DEG, MISS_DEFLECT_MAX_DEG)))

# --- Held weapon mesh ---
## Render the equipped weapon's own view-model in the NPC's hand and, if that model carries a
## "Muzzle" barrel marker, re-point the shot + laser origin onto it. The view-model is parented under
## the hand anchor (_muzzle, at muzzle_offset) so it inherits the NPC's yaw — the NPC already faces the
## target via _face_point, so the gun points the right way (after the corrective weapon_mesh_rotation).
## A weapon with no view_model simply shows nothing and keeps the bare-marker origin, same graceful
## fallback the player's GunMesh uses for an unassigned weapon.
func _build_weapon_mesh() -> void:
	var vm: PackedScene = weapon_data.view_model
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
	return base * limb_move_multiplier()  # crippled legs limp (locational damage)

## Called by DialogueManager when this NPC becomes / stops being the one being talked to. While
## talking it's frozen, so its aim loop can't hide the laser itself; do it here. The AI re-shows
## the laser on its own once it unfreezes and re-acquires.
func set_in_dialogue(on: bool) -> void:
	if on:
		_hide_laser()

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
		var dmg := _weapon.equipped_weapon.damage if (_weapon and _weapon.equipped_weapon) else 0.0
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
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null

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
