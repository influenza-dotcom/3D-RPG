class_name NpcAudioCues
extends Node

## The combatant's four telegraph SOUNDS — pulled off NPC so the root keeps only the firing CADENCE
## that TIMES them, while this child owns the assets + mix (volumes, pitches, the shared spot cooldowns):
##   - the MGS "!" sting when the NPC first NOTICES something: played 2D (in your ear, NO distance falloff —
##     heard perfectly from ANY distance) when what it noticed is the PLAYER, so being detected is never missed;
##     played POSITIONALLY at the NPC (atmospheric, faint from afar) when it noticed ANOTHER NPC / a decoy / a
##     bare point. Two static cooldowns (player-detection, ambient) so a swarm spotting at once = one sting, and
##     an ambient contact can never mask YOUR detection cue;
##   - the sniper CHARGE sting, played 2D a beat after a shot fires (so it doesn't blur into the gunshot),
##     quieter + randomly pitched, and much quieter still for an NPC-vs-NPC trade (ambience, not a warning);
##   - the incoming-shot BEEP, played 2D a beat before the NPC fires AT the player so it's always audible;
##   - the MISS ricochet, played 2D when a shot at the player was rolled to whiff past.
##
## Host-coupled: NPC builds it in _ready (for every NPC — even an unarmed fighter spots + stings) and sets
## `host` right after .new(); on_spotted() reads host.threat_response to mute a fleer. Off-tree (a unit-test
## NPC built via .new() with no add_child) this child never exists, so NPC's _on_spotted / charge-sting /
## beep call sites all null-guard it — matching the monolith, which simply wouldn't have reached audio there.
## NOTE: the charge-sting SCHEDULING (_on_aim writing _last_aim_msec / _aim_sfx_delay) stays on the ROOT —
## a unit test pokes those fields on a bare instance — so this child only PLAYS the scheduled sting.

## MGS-style "!" alert played once when a combatant first notices something (Perception UNAWARE -> anything).
const MGS_ALERT = preload("uid://gm6sdfatmc64")
## Two cooldown stamps, both STATIC (shared across every NPC) and both paced by npc_bark.alert_cooldown_ms:
##  - `_last_alert_msec` — the PLAYER-detection (2D) sting: a swarm spotting YOU at once = one sting.
##  - `_last_ambient_alert_msec` — the positional NPC-vs-NPC / decoy / point sting, throttled by BOTH stamps.
## ASYMMETRIC on purpose: an ambient sting is swallowed by a recent player sting AND by a recent ambient one, but a
## player sting is throttled ONLY by other player stings — so two factions trading "!"s across the street can never
## mask the cue for the guard that just spotted YOU (nor its "!" popup, which rides on_spotted's return).
static var _last_alert_msec: int = 0
static var _last_ambient_alert_msec: int = 0
## Sniper "charging aim" sting (Nuclear Throne), played a beat after a shot fires. Played 2D so the
## player reliably hears an incoming shot wherever it comes from.
const AIM_SFX = preload("uid://c04i5r1df6cvs")
## Incoming-shot warning beep, played 2D (always audible) a beat before this NPC fires AT the player.
const SHOT_WARNING_SFX = preload("uid://dy6uyrwr3trfk")
## A shot rolled to MISS the player plays this "whiff past you" ricochet 2D (always audible). TEMPORARY
## asset — a sniper ricochet, per the request; swap for a dedicated miss whiff later.
const MISS_SFX = preload("uid://c1f7xax46usqc")
# The per-cue VOLUMES (dB) + random PITCH ranges moved to the GameSettings.npc_audio tuning group
# (resources/tuning/NpcAudioSettings.tres) so the combat-audio mix is designer-tunable, not hardcoded here.

## The NPC this plays for — set right after .new() in NPC._ready. READ-only here (we read its
## threat_response to mute a fleer); the canonical state stays on the host.
var host: NPC

## Play the MGS "!" sting when the NPC first notices something. `targeting_player` = WHAT it noticed is the PLAYER
## (or a companion in the &"Player" group — the same reading as the charge sting's targeting_player /
## is_alerted_on_player; the host derives it from Perception.noticed, NOT from its proximity-locked _target): then
## it's YOU being detected, so the sting is played 2D — in your ear, no distance attenuation — and heard perfectly
## wherever the spotter is (a roof sniper 60 m out is as loud as a guard at your back). Otherwise (it noticed
## ANOTHER NPC, a thrown decoy, a scripted point — nobody in particular) it plays POSITIONALLY at `world_pos`,
## sounding from the NPC so a far-off contact is faint: an atmospheric cue, not a warning. Neither is the
## incoming-shot warning (the charge sting is that). A fleeing civilian noticing danger isn't a combat "!" alert,
## so it's muted. Throttled by the two static cooldowns above (player-detection stings only de-dup among
## themselves; ambient stings yield to either). Returns true iff the sting actually played, so the host can gate
## the matching "!" head-popup on the SAME throttle. Volumes ride GameSettings.npc_audio (alert_volume_db /
## alert_volume_db_vs_npc).
func on_spotted(world_pos: Vector3, targeting_player: bool) -> bool:
	if host.threat_response == NPC.ThreatResponse.FLEE:
		return false  # a fleeing civilian noticing danger isn't a combat "!" alert
	var now := Time.get_ticks_msec()
	var cooldown: int = GameSettings.npc_bark.alert_cooldown_ms
	var s := GameSettings.npc_audio
	if targeting_player:
		if now - _last_alert_msec < cooldown:
			return false  # a swarm spotting you at once = one sting (never gated by an ambient contact)
		_last_alert_msec = now
		AudioManager.play_2d_sfx(MGS_ALERT, s.alert_volume_db, 1.0, &"sfx", false)  # 2D — YOU were seen: audible from any distance
	else:
		if now - _last_alert_msec < cooldown or now - _last_ambient_alert_msec < cooldown:
			return false  # ambience yields to a recent player sting AND de-dups among itself
		_last_ambient_alert_msec = now
		AudioManager.play_sfx(world_pos, MGS_ALERT, s.alert_volume_db_vs_npc, 1.0, &"sfx", AudioManager.DEFAULT_MAX_DB, false)  # positional — sounds from the NPC
	return true

## Play the scheduled sniper charge sting 2D — quiet + randomly pitched so it stays a subtle telegraph,
## not an in-your-ear blare, and substantially quieter when aiming at ANOTHER NPC (an NPC-vs-NPC trade is
## ambience, not an incoming-shot warning). The host calls this once the _aim_sfx_delay beat it scheduled
## in _on_aim elapses (in _physics_process), passing whether the current target is the player.
func play_charge_sting(targeting_player: bool) -> void:
	var s := GameSettings.npc_audio
	var pitch := randf_range(s.aim_sfx_pitch_min, s.aim_sfx_pitch_max)
	var aim_vol := s.aim_sfx_volume_db if targeting_player else s.aim_sfx_volume_db_vs_npc
	AudioManager.play_2d_sfx(AIM_SFX, aim_vol, pitch, &"sfx", false)

## Play the incoming-shot warning beep 2D (always audible), quieter than full + randomly pitched per
## shot like the charge sting. The host fires this a beat (GameSettings.npc_ai.beep_lead_time) before a shot
## lands AT the player — that lead-time window is the root's firing cadence, so it lives there, not here.
func play_incoming_beep() -> void:
	var s := GameSettings.npc_audio
	AudioManager.play_2d_sfx(SHOT_WARNING_SFX, s.beep_volume_db, randf_range(s.beep_pitch_min, s.beep_pitch_max), &"sfx", false)

## Play the "missed you" ricochet 2D when an NPC's shot at the player was rolled to miss (miss_chance).
func play_miss() -> void:
	var s := GameSettings.npc_audio
	AudioManager.play_2d_sfx(MISS_SFX, s.miss_sfx_volume_db, randf_range(s.miss_sfx_pitch_min, s.miss_sfx_pitch_max), &"sfx", false)
