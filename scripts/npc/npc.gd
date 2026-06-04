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

@export_group("Hostility")
## The faction this NPC belongs to. NULL => UNALIGNED: the NPC uses its standalone `disposition`
## below instead of faction + player-reputation. Set this to a Faction .tres (e.g. raiders,
## townsfolk) to make the NPC's attitude track the player's reputation with that faction.
@export var faction: Faction = null
## Standalone attitude, used ONLY when `faction` is null (unaligned). Defaults to HOSTILE so a
## combatant with no faction set behaves exactly like today's enemy (aggressive on sight).
@export var disposition: Disposition.Kind = Disposition.Kind.HOSTILE
## When true, this NPC has been provoked (e.g. the player attacked it) and is hostile regardless
## of faction/disposition until something clears it. Runtime only — never authored in the editor.
var _provoked: bool = false

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
## Seconds between shots once alerted (the weapon's own cooldown still applies on top).
@export var fire_cooldown: float = 1.5
## Won't shoot past this distance to the target (separate from how far it can SEE).
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

@export_group("Behavior")
## How this NPC reacts to a hostile target it has noticed. FIGHT = engage and shoot (the default,
## i.e. today's enemy). FLEE = run away from the threat and never fire (a civilian / coward). Pair
## FLEE + `wanders` + a NEUTRAL/FRIENDLY disposition for a townsperson who only bolts when attacked.
enum ThreatResponse { FIGHT, FLEE }
@export var threat_response: ThreatResponse = ThreatResponse.FIGHT
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
## before speaking, so the conversation is adequately framed (see prompt_talk / _act_talk_approach).
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
## MGS-style "!" alert played once when a combatant first spots the player (Perception DETECTING).
## The cooldown is shared across all NPCs (static) so a swarm spotting you at once = one sting.
const MGS_ALERT = preload("res://assets/413641__djlprojects__metal-gear-solid-inspired-alert-surprise-sfx.wav")
const ALERT_COOLDOWN_MS: int = 3000
static var _last_alert_msec: int = 0
## Sniper "charging aim" sting (Nuclear Throne), played when a combatant locks on AND at the start of
## each shot's charge. Short cooldown only dedups near-simultaneous triggers (e.g. lock + an immediate
## first shot); the fire cadence is the real rhythm.
const AIM_SFX = preload("res://assets/audio/sndSniperTarget.wav")
const AIM_COOLDOWN_MS: int = 250
## A short beat between a shot and its charge-up sting so the two don't blur together (see _on_aim).
const AIM_SFX_DELAY: float = 0.1
## The charge sting plays a touch quieter than full + at a slight random pitch each shot, so it
## doesn't blare identically every time (playtesters found the unvaried full-volume sting annoying).
const AIM_SFX_VOLUME_DB: float = -17.0
## Much quieter charge sting when this NPC is targeting ANOTHER NPC instead of the player — a distant
## NPC-vs-NPC trade shouldn't blare a full-volume 2D telegraph in the player's ear.
const AIM_SFX_VOLUME_DB_VS_NPC: float = -32.0
const AIM_SFX_PITCH_MIN: float = 0.8
const AIM_SFX_PITCH_MAX: float = 1.25
## Incoming-shot warning beep, played 2D (always audible) a beat before this NPC fires AT the player.
const SHOT_WARNING_SFX = preload("res://resources/weapons/beep.mp3")
## How many seconds before a shot lands the warning beep plays.
const BEEP_LEAD_TIME: float = 0.5
## The beep is also quieter than full + randomly pitched per shot, like the charge sting.
const BEEP_VOLUME_DB: float = -8.0
const BEEP_PITCH_MIN: float = 0.8
const BEEP_PITCH_MAX: float = 1.25

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
## Target re-acquisition throttle. We do NOT scan every frame (that would be O(n^2) across all NPCs).
## Instead we re-scan every RETARGET_INTERVAL seconds, or immediately when the current target becomes
## invalid / dies / leaves sight_range (handled in _physics_process).
const RETARGET_INTERVAL: float = 0.5

var _weapon: Weapon
var _muzzle: Marker3D        # hand/grip anchor the gun model hangs off (at muzzle_offset)
var _weapon_mesh: Node3D     # the equipped weapon's instantiated view-model, held at the hand
var _gun_muzzle: Marker3D    # the held gun's own "Muzzle" barrel marker; null => shots/laser fall back to _muzzle
var _perception: Perception
var _target: Node3D
var _target_body: Node3D  # target's collision shape (centre tracks crouch); falls back to _target
var _last_attacker: Node3D = null  # most recent hostile that damaged us; favoured over the nearest in _acquire_target
var _laser: MeshInstance3D
var _fire_timer: float = 0.0
var _charging: bool = false  # winding up a clear, in-range shot (drives the lock-on sting)
var _warned: bool = false    # the incoming-shot beep already played for the current charge
var _spawn_yaw: float = 0.0
var _spawn_position: Vector3
var _desired_velocity: Vector3 = Vector3.ZERO
var _nav: NavigationAgent3D
var _retarget_timer: float = 0.0
## Last Disposition.Kind the outline was tinted for, so _physics_process only rebuilds the rim
## material on an actual attitude CHANGE (rep shift with no provoke), not every frame. -1 is never
## a Kind, so the first tick always syncs. Cached as int (Disposition.Kind is int-backed).
var _last_outline_kind: int = -1
## Wander bookkeeping (used only when `wanders`): the current roam destination + a dwell pause.
var _wander_target: Vector3
var _has_wander_target: bool = false
var _wander_dwell: float = 0.0
## Pre-talk approach (the "talk requested" flow): set while the NPC is walking up to the player to be
## framed for dialogue. _talk_target is the player to close on; _talk_on_ready opens the actual
## dialogue once in range; _talk_timeout bleeds down so a blocked approach still speaks (gives up).
## All cleared the instant the approach resolves — _talk_target == null means "not approaching".
var _talk_target: Node3D = null
var _talk_on_ready: Callable = Callable()
var _talk_timeout: float = 0.0

func _ready() -> void:
	super()  # Character._ready(): set hp + build the flash overlay on the mesh tree.
	add_to_group(&"npc")  # so hostile NPCs can find us as a target (the _acquire_target scan enumerates this)
	_setup_outline()
	# Senses + locomotion for EVERY NPC, armed or not: wandering needs a nav agent, fleeing and the
	# turn-when-shot both need a Perception. (A purely decorative NPC carries them unused but cheap.)
	_spawn_yaw = rotation.y
	_spawn_position = global_position
	_build_perception()
	_build_nav()
	# Weapon + laser ONLY for a combatant (weapon_data set). A null weapon_data is a civilian: no gun,
	# no laser, no fire path — _physics_process gates the ALERTED branch on `_weapon != null`.
	if weapon_data != null:
		_fire_timer = fire_cooldown  # seed a full wind-up so the first shot charges instead of firing instantly
		_muzzle = Marker3D.new()
		add_child(_muzzle)
		_muzzle.position = muzzle_offset
		_weapon = load(WEAPON_SCENE_PATH).instantiate()
		add_child(_weapon)
		# No camera -> ScopeIn no-ops (no ADS) and the input-driven parts are disabled.
		_weapon.setup(self, null, _muzzle)
		_weapon.inventory.equip(weapon_data)
		if starts_unloaded and _weapon.ammo:
			_weapon.ammo.current_ammo = 0  # keep the gun dry: the AI reloads before it can fire
		_build_weapon_mesh()  # render the equipped gun in the hand and re-point shots/laser at its barrel
		_build_laser()
	_acquire_target()

## Chain the configured outline pass in front of the flash material and re-apply the combined
## overlay to the mesh tree. No-op if outlines are disabled or the flash overlay wasn't built
## (no `mesh`). Built once; toggling appearance later would re-run _apply_overlay_to_meshes.
func _setup_outline() -> void:
	if not has_outline or _flash_material == null:
		return
	_apply_outline()  # initial build from the current disposition

## Rebuild the outline pass from the CURRENT resolved_disposition() colour (HOSTILE red / FRIENDLY
## green / NEUTRAL the export) and chain it in front of the flash overlay. Safe to call repeatedly —
## re-applied on provoke and on a rep-driven attitude change (the _physics_process Kind-compare).
## Each call builds a fresh ShaderMaterial; the old overlay is simply replaced (Godot frees it).
## NOTE: if the player is currently look-at-highlighting this NPC, TalkHelpers has stashed the real
## outline in meta and put a white highlight in the overlay slot; re-applying here would be clobbered
## on look-away. That's a rare provoke-mid-conversation case and self-heals on the next Kind-compare.
func _apply_outline() -> void:
	if not has_outline or _flash_material == null:
		return
	var outline := TalkHelpers.make_outline_material(_outline_color_for_disposition(), outline_width)
	outline.next_pass = _flash_material
	_apply_overlay_to_meshes(outline)
	_last_outline_kind = resolved_disposition()  # seed so the poll only rebuilds on a real change

## Resolve this NPC's CURRENT attitude toward the player, in priority order:
##   1. provoked  -> HOSTILE (a hit always aggros, overriding everything)
##   2. factioned -> Reputation's disposition for that faction (faction baseline + player rep)
##   3. unaligned -> the standalone `disposition` export
func resolved_disposition() -> Disposition.Kind:
	if _provoked:
		return Disposition.Kind.HOSTILE
	if faction != null:
		return Reputation.disposition_for(faction)
	return disposition

## True when this NPC currently treats the player as an enemy. The combat AI (this NPC's own
## Perception loop) gates ALL hostile behaviour — detect, aim, fire — on this. A non-hostile NPC
## keeps gravity / idle / wander but never engages the player until provoked.
func is_hostile() -> bool:
	return resolved_disposition() == Disposition.Kind.HOSTILE

## The outline rim colour for the CURRENT resolved_disposition(): HOSTILE -> red, FRIENDLY -> green,
## NEUTRAL -> the `outline_color` export (black by default, and the per-instance override hook).
func _outline_color_for_disposition() -> Color:
	match resolved_disposition():
		Disposition.Kind.HOSTILE:
			return OUTLINE_HOSTILE
		Disposition.Kind.FRIENDLY:
			return OUTLINE_FRIENDLY
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
	if other_npc == null or faction == null or other_npc.faction == null:
		return false
	return faction.relation_to(other_npc.faction.id) < 0.0

## Aggro this NPC: become hostile NOW, and — if factioned — drop the player's reputation with that
## faction so the whole faction sours (FNV-style). Idempotent; safe to call every hit. `attacker`
## is accepted so the damage hook can also turn us toward the source.
func provoke(_attacker: Node = null) -> void:
	if not _provoked:
		_provoked = true
		if faction != null:
			Reputation.add_reputation(faction, -Reputation.PROVOKE_REP_PENALTY)
		_apply_outline()  # now hostile — recolour the rim to red immediately
		_popup_icon(POPUP_NEGATIVE)  # we just turned on the player / soured the faction

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
func _on_damaged_by(attacker: Node, _was_crit: bool = false) -> void:
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

## No-op hit handler kept so the scene's `damaged -> _on_damaged` connection resolves. The hit
## freeze-frame rides the weapon's hitstop + the Damage child node; the aggro/turn-toward-shooter
## logic lives in _on_damaged_by (which gets the attacker identity take_damage passes).
func _on_damaged(_current_hp: float, _max_hp: float) -> void:
	pass

## Pause-on-kill: briefly hard-pause the tree so the kill + ragdoll land. Runs on the FreezeFrame
## autoload (not us — we're about to be freed), and no-ops if already paused (dialogue). Wired from
## the scene's `died -> _on_died` connection.
func _on_died() -> void:
	FreezeFrame.pause_briefly(0.015)

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

## Play the MGS "!" sting POSITIONALLY when this NPC first notices its target — it sounds from the NPC,
## so a far-off spot is faint: an atmospheric detection cue, not the player's incoming-shot warning
## (the charge sting is that). Throttled by a shared cooldown so a group spotting at once doesn't stack it.
func _on_spotted() -> void:
	if threat_response == ThreatResponse.FLEE:
		return  # a fleeing civilian noticing danger isn't a combat "!" alert
	var now := Time.get_ticks_msec()
	if now - _last_alert_msec < ALERT_COOLDOWN_MS:
		return
	_last_alert_msec = now
	AudioManager.play_sfx(global_position, MGS_ALERT, 0.0, 1.0)  # positional — sounds from the NPC
	_popup_icon(POPUP_EXCLAMATION)  # "!" over the head, sharing the sting's cooldown gate

## Pop a billboarded icon above this NPC's head, hold briefly, fade its alpha to 0, then free — built
## entirely in code (no scene). Used by the alert "!" and the turn-hostile "negativefriend" cue.
## Mirrors the fade-then-free idiom in effects/blood_splatter.gd (tween modulate:a -> 0, then free);
## the tween is created ON the sprite so it dies with it if this NPC is freed mid-fade.
func _popup_icon(tex: Texture2D) -> void:
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
	# Parent to the tree ROOT (not us) + world-position above the head, so the cue SURVIVES our death:
	# one-shotting a friendly still pops the "negative" icon even though we're freed / ragdolled this frame.
	get_tree().root.add_child(icon)
	icon.global_position = global_position + Vector3(0.0, POPUP_HEAD_Y, 0.0)
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
	# Schedule the charge sting a beat (AIM_SFX_DELAY) later instead of the same frame as the shot —
	# playing it instantly blurs the gunshot and the charge-up together. _physics_process fires it.
	_aim_sfx_delay = AIM_SFX_DELAY

func _build_nav() -> void:
	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.5
	_nav.target_desired_distance = 1.0
	add_child(_nav)

func _physics_process(delta: float) -> void:
	# Pre-talk approach overrides ALL other AI: while walking up to the player to be framed for
	# dialogue (prompt_talk set _talk_target), drive only the approach + locomotion, nothing else.
	# This runs to completion BEFORE DialogueManager.start freezes us — once frozen this loop stops.
	if _talk_target != null:
		_act_talk_approach(delta)
		super._physics_process(delta)  # gravity + locomotion move (consumes _desired_velocity)
		return
	# A charge sting scheduled by _on_aim plays a short beat AFTER the shot (so it doesn't blur into the
	# gunshot). Ticked here so it fires whatever AI state the NPC has reached by the time it elapses.
	if _aim_sfx_delay >= 0.0:
		_aim_sfx_delay -= delta
		if _aim_sfx_delay < 0.0:
			# ALWAYS 2D so you reliably hear an incoming shot wherever it comes from, but quiet +
			# randomly pitched per shot so it stays a subtle telegraph, not an in-your-ear blare.
			# Substantially quieter when we're aiming at ANOTHER NPC (not the player): an NPC-vs-NPC
			# trade is ambience, not an incoming-shot warning, so it shouldn't blare at full volume.
			var pitch := randf_range(AIM_SFX_PITCH_MIN, AIM_SFX_PITCH_MAX)
			var aim_vol := AIM_SFX_VOLUME_DB if (is_instance_valid(_target) and _target.is_in_group(&"Player")) else AIM_SFX_VOLUME_DB_VS_NPC
			AudioManager.play_2d_sfx(AIM_SFX, aim_vol, pitch)
	_desired_velocity = Vector3.ZERO  # default: hold position; states below may drive it
	# Bleed the fire charge back down every frame by default; _act_alerted overcomes this only while it
	# has a clear, in-range shot. So whenever the enemy can't see or can't hit you, its wind-up decays
	# toward zero (break line of sight to reset the shot) instead of freezing mid-charge.
	_fire_timer = minf(fire_cooldown, _fire_timer + delta)
	# Re-acquire on a throttle, or immediately when the current target is gone / dead / out of
	# range / no longer hostile. _target_invalid() keeps this an O(1) check most frames; the full
	# O(n) scan only runs on the timer or a genuine invalidation — never an every-frame O(n^2).
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or _target_invalid():
		_acquire_target()
		_retarget_timer = RETARGET_INTERVAL
	# Re-tint the rim if our attitude changed with no provoke (a faction-rep shift — Reputation has
	# no signal, so it must be polled). O(1) per frame; the material only rebuilds on a real change.
	# Skipped entirely when there's no outline to retint (outlines off / no mesh -> no _flash_material).
	if has_outline and _flash_material != null and resolved_disposition() != _last_outline_kind:
		_apply_outline()
	if not is_instance_valid(_target):
		# Nothing hostile around: live a little instead of freezing - wander near spawn (if `wanders`)
		# or just hold position. This is the common case for a NEUTRAL/FRIENDLY NPC with no enemies.
		_idle(delta, false)
		_hide_laser()
		super._physics_process(delta)
		return
	# Hostility gate: _acquire_target only ever returns a hostile target, so this stays true while
	# engaged; it cleanly idles a non-hostile NPC with no peers.
	_perception.is_hostile = is_hostile_to(_target)
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
	_face_point(aim, delta)
	# Laser opacity AND the player's aim radial reflect the shot's charge: 0 right after firing,
	# ramping to 1 (opaque / about to fire) as the cooldown elapses.
	var charge := clampf(1.0 - _fire_timer / maxf(fire_cooldown, 0.001), 0.0, 1.0)
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
		# Incoming-shot warning: a beat before the shot, beep 2D so the player always hears it.
		if not _warned and _fire_timer <= BEEP_LEAD_TIME \
				and is_instance_valid(_target) and _target.is_in_group(&"Player"):
			_warned = true
			AudioManager.play_2d_sfx(SHOT_WARNING_SFX, BEEP_VOLUME_DB, randf_range(BEEP_PITCH_MIN, BEEP_PITCH_MAX))
	else:
		# Lost the shot (LOS broken / out of range): the charge bleeds back down in _physics_process.
		# Only DROP the locked-on state once it's FULLY bled, so briefly peeking in and out of cover
		# doesn't reset the lock and re-trigger the charge sting + beep every time you bob out.
		if _fire_timer >= fire_cooldown:
			_charging = false
			_warned = false
	if can_shoot and _fire_timer <= 0.0 and _weapon.current_ammo != 0:
		_weapon.attack.try_fire()
		_fire_timer = fire_cooldown
		_warned = false  # re-arm the warning for the next shot
		# Drop back to "not charging" so the next shot's lock-on sting only re-fires if we're STILL in
		# range next frame. A melee swing that knocks the player out of range then won't phantom-charge
		# (and re-play the sting) the instant the attack finishes; it re-stings when it re-closes to range.
		_charging = false
	# Pass whether we can actually fire on the player RIGHT NOW: the glint clears the instant we lose the
	# clear shot, instead of lingering at our position through the post-shot / lost-LOS charge bleed.
	_report_aim(charge, can_shoot)

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
	_desired_velocity = to_next.normalized() * move_speed
	return true

func _face_travel(delta: float) -> void:
	if _desired_velocity.length_squared() > 0.0001:
		_face_point(global_position + _desired_velocity, delta)

## Non-combat idle update. Wanderers roam near spawn; otherwise the NPC either returns to its post
## (return_to_post, when knocked away) or just holds still - the prior target-less behaviour, so a
## plain FIGHT combatant is completely unchanged.
func _idle(delta: float, return_to_post: bool) -> void:
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

## Pre-talk approach: walk toward the player and open the dialogue ONLY once every condition holds —
## in framing range, on the GROUND (not mid-knockback / airborne), and actually FACING them. Combat
## PREEMPTS the parley (a busy NPC only fights): if a fight starts, the player is gone, or the approach
## times out, it abandons the prompt and opens NO dialogue. The callback + target are cleared BEFORE
## the call so a re-entrant prompt_talk during dialogue start can't double-fire.
func _act_talk_approach(delta: float) -> void:
	_desired_velocity = Vector3.ZERO  # default hold; _move_toward below drives it while travelling
	_talk_timeout -= delta
	# Abandon the parley if a fight started (only-fights-while-busy), the player vanished, or we took
	# too long: drop the prompt and open NO dialogue, returning to normal behaviour.
	if is_in_combat() or not is_instance_valid(_talk_target) or _talk_timeout <= 0.0:
		_talk_target = null
		_talk_on_ready = Callable()
		return
	var to_player := _talk_target.global_position - global_position
	var flat := Vector3(to_player.x, 0.0, to_player.z)
	if flat.length() > talk_approach_distance:
		# Still closing: path toward the player, facing the way we travel (else straight at them).
		if _move_toward(_talk_target.global_position):
			_face_travel(delta)
		else:
			_face_point(_talk_target.global_position, delta)
		return
	# In range: square up, then open the box ONLY once grounded AND FULLY facing them (our +Z front
	# within ~8 deg, so the NPC finishes its turn-to-face before talking instead of speaking mid-pivot).
	# Otherwise hold and keep turning until we are (or the timeout above gives up).
	_face_point(_talk_target.global_position, delta)
	var fwd := global_transform.basis.z
	fwd.y = 0.0
	var facing := flat.length_squared() > 0.0001 and fwd.length_squared() > 0.0001 \
			and fwd.normalized().dot(flat.normalized()) >= 0.99
	if is_on_floor() and facing:
		var cb := _talk_on_ready
		_talk_target = null
		_talk_on_ready = Callable()
		if cb.is_valid():
			cb.call()

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
## Cheap per-frame test: is the current target no longer worth keeping? (gone, freed, out of
## sight_range, or hostility lapsed — e.g. a provoke wore off or rep shifted). Forces a re-scan.
func _target_invalid() -> bool:
	if not is_instance_valid(_target):
		return true
	if global_position.distance_to(_target.global_position) > sight_range:
		return true
	return not is_hostile_to(_target)

## Pick the nearest hostile node: the player plus every NPC peer, filtered by is_hostile_to()
## and sight_range, nearest wins. Defaults to the player when it's the only/nearest hostile, so a
## lone player-hostile enemy behaves exactly as before. Throttled by the caller (RETARGET_INTERVAL)
## so this O(n) scan is not an every-frame cost. Also binds Perception to whatever we locked.
func _acquire_target() -> void:
	# Stay locked on the last character that actually attacked us — while it's still a valid, hostile,
	# in-range threat — instead of being pulled toward whoever is merely nearest (no easy distraction).
	if is_instance_valid(_last_attacker) and is_hostile_to(_last_attacker) and global_position.distance_to(_last_attacker.global_position) <= sight_range:
		_set_target(_last_attacker)
		return
	_last_attacker = null  # the aggressor died / fled out of sight_range / is no longer hostile — drop it
	var best: Node3D = null
	var best_d := INF
	# The player is just another candidate — same hostility + range test as any NPC.
	var player := get_tree().get_first_node_in_group(&"Player") as Node3D
	if is_instance_valid(player) and is_hostile_to(player):
		var pd := global_position.distance_to(player.global_position)
		if pd <= sight_range:
			best = player
			best_d = pd
	for node in get_tree().get_nodes_in_group(&"npc"):
		var npc := node as NPC
		if npc == null or npc == self or not is_instance_valid(npc):
			continue
		if not is_hostile_to(npc):
			continue
		var d := global_position.distance_to(npc.global_position)
		if d <= sight_range and d < best_d:
			best = npc
			best_d = d
	_set_target(best)

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

# --- Laser sight ---
## How bright the additive laser beam adds at full charge (its disposition hue x this). Higher = a more
## intense glow; the per-frame charge then scales the amount actually added (fading it to invisible).
const LASER_ADD_BRIGHTNESS: float = 3.0
const NPC_LASER_SHADER := preload("res://resources/shaders/npc_laser.gdshader")

func _build_laser() -> void:
	_laser = MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(0.02, 0.02, 1.0)
	_laser.mesh = beam
	_laser.top_level = true  # ignore our own (rotating) transform; placed in world space
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Dedicated ADDITIVE beam shader (blend_add in its render_mode = unambiguously additive, unlike a
	# StandardMaterial3D blend_mode which can still alpha-blend and darken). Brightness rises with the
	# shot's charge (set in _aim_laser_at); at strength 0 it adds nothing and is simply invisible.
	var mat := ShaderMaterial.new()
	mat.shader = NPC_LASER_SHADER
	var hue := _outline_color_for_disposition()
	mat.set_shader_parameter(&"beam_color", Vector3(hue.r, hue.g, hue.b))
	mat.set_shader_parameter(&"strength", 0.0)
	_laser.material_override = mat
	# Parent to US, not the tree root: adding to root during our _ready races the scene's own child
	# setup (the "parent is busy setting up children" error when we're spawned mid-frame). As a DIRECT
	# child we're still a sibling of `mesh`, so the outline + look-at-highlight sweeps (which only walk
	# under `mesh`) skip the see-through beam; top_level keeps it world-placed. Auto-freed with us.
	add_child(_laser)
	_laser.visible = false

func _hide_laser() -> void:
	if _laser:
		_laser.visible = false

## Called by DialogueManager when this NPC becomes / stops being the one being talked to. While
## talking it's frozen, so its aim loop can't hide the laser itself; do it here. The AI re-shows
## the laser on its own once it unfreezes and re-acquires.
func set_in_dialogue(on: bool) -> void:
	if on:
		_hide_laser()

## "Prompt" (not force) this NPC to talk: it acknowledges the player, walks into framing range, and
## only THEN runs `on_ready` (which performs the real DialogueManager.start). Called by the Talkable /
## DialogueNPC handler on interact, so a talk press is a REQUEST the NPC chooses to answer, not an
## instant dialogue box. Refused outright while busy fighting or hostile (you can't parley mid-fight),
## and ignored if already mid-approach so spamming interact can't queue multiple openings. When close
## enough already (or approach disabled), just waits TALK_BUFFER then speaks in place — the buffer is
## the beat between the press and the reply. Robustness (player walking off / timeout) lives in
## _act_talk_approach. The approach turns the NPC itself, so the handler must NOT also face_player.
func prompt_talk(player: Node3D, on_ready: Callable) -> void:
	if _talk_target != null:
		return  # already gathering toward an earlier prompt — don't queue a second
	if is_hostile() or is_in_combat() or player == null or not on_ready.is_valid():
		return  # a hostile / fighting NPC won't talk; nothing to do without a player or callback
	# Close enough (or framing disabled): hold the buffer beat, then speak from here. The timer is
	# created on the tree (not us) so it survives even if our processing is otherwise quiet.
	if talk_approach_distance <= 0.0 or global_position.distance_to(player.global_position) <= talk_approach_distance:
		get_tree().create_timer(TalkHelpers.TALK_BUFFER).timeout.connect(on_ready)
		return
	# Otherwise walk into range first; _act_talk_approach (driven from _physics_process) runs on_ready
	# once we arrive (or the approach times out). The buffer is folded into the walk-up time here.
	_talk_target = player
	_talk_on_ready = on_ready
	_talk_timeout = talk_approach_timeout

## Feed the player's aim indicator our position + how ready we are to fire (0 = just noticing you,
## 1 = locked / about to shoot), so a white radial points at us and ramps opaque.
func _report_aim(charge: float, clear_shot: bool = true) -> void:
	if is_instance_valid(_target) and _target.has_method(&"indicate_aimed_from"):
		var dmg := _weapon.equipped_weapon.damage if (_weapon and _weapon.equipped_weapon) else 0.0
		# Blink the radial in sync with the incoming-shot beep — both fire in the final BEEP_LEAD_TIME window.
		var warning := _fire_timer <= BEEP_LEAD_TIME
		_target.indicate_aimed_from(self, global_position, charge, dmg, warning, clear_shot)

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
	if not show_laser or not _laser:
		_hide_laser()
		return hit
	var endpoint: Vector3 = hit.position if not hit.is_empty() else origin + dir * _aim_range()
	var dist := origin.distance_to(endpoint)
	if dist < 0.01:
		_hide_laser()
		return hit
	# Beam basis by hand: Z column = direction * length (so the unit box stretches ALONG the
	# aim); X/Y kept unit + perpendicular so it stays thin. Centred at the midpoint it spans
	# exactly muzzle -> endpoint.
	var bdir := (endpoint - origin) / dist
	var x := bdir.cross(Vector3.UP)
	if x.length_squared() < 0.000001:
		x = bdir.cross(Vector3.FORWARD)
	x = x.normalized()
	var y := x.cross(bdir).normalized()
	_laser.visible = true
	_laser.global_transform = Transform3D(Basis(x, y, bdir * dist), (origin + endpoint) * 0.5)
	var mat := _laser.material_override as ShaderMaterial
	if mat:
		# Brightness (additive strength) ramps with the charge: invisible while merely noticing you,
		# bright the instant it's locked — fading DOWN just adds less light, never darkens to black.
		# Hue tracks our disposition (red hostile, green friendly), so the beam reads our attitude.
		var c := _outline_color_for_disposition()
		mat.set_shader_parameter(&"beam_color", Vector3(c.r, c.g, c.b))
		mat.set_shader_parameter(&"strength", clampf(charge, 0.0, 1.0) * LASER_ADD_BRIGHTNESS)
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
	return (_aim_point() - get_aim_origin()).normalized()

func get_aim_basis() -> Basis:
	var dir := get_aim_direction()
	# Avoid a degenerate basis if we're ever aiming near-straight up/down.
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	return Basis.looking_at(dir, up)
