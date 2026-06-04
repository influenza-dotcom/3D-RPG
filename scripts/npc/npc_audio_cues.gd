class_name NpcAudioCues
extends Node

## The combatant's three telegraph SOUNDS — pulled off NPC so the root keeps only the firing CADENCE
## that TIMES them, while this child owns the assets + mix (volumes, pitches, the shared spot cooldown):
##   - the MGS "!" sting played POSITIONALLY when the NPC first spots its target (atmospheric, faint
##     from afar), shared across all NPCs via a static cooldown so a swarm spotting at once = one sting;
##   - the sniper CHARGE sting, played 2D a beat after a shot fires (so it doesn't blur into the gunshot),
##     quieter + randomly pitched, and much quieter still for an NPC-vs-NPC trade (ambience, not a warning);
##   - the incoming-shot BEEP, played 2D a beat before the NPC fires AT the player so it's always audible.
##
## Host-coupled: NPC builds it in _ready (for every NPC — even an unarmed fighter spots + stings) and sets
## `host` right after .new(); on_spotted() reads host.threat_response to mute a fleer. Off-tree (a unit-test
## NPC built via .new() with no add_child) this child never exists, so NPC's _on_spotted / charge-sting /
## beep call sites all null-guard it — matching the monolith, which simply wouldn't have reached audio there.
## NOTE: the charge-sting SCHEDULING (_on_aim writing _last_aim_msec / _aim_sfx_delay) stays on the ROOT —
## a unit test pokes those fields on a bare instance — so this child only PLAYS the scheduled sting.

## MGS-style "!" alert played once when a combatant first spots the player (Perception DETECTING). The
## cooldown is shared across all NPCs (static) so a swarm spotting you at once = one sting.
const MGS_ALERT = preload("res://assets/413641__djlprojects__metal-gear-solid-inspired-alert-surprise-sfx.wav")
static var _last_alert_msec: int = 0
## Sniper "charging aim" sting (Nuclear Throne), played a beat after a shot fires. Played 2D so the
## player reliably hears an incoming shot wherever it comes from.
const AIM_SFX = preload("res://assets/audio/sndSniperTarget.wav")
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
## The beep is also quieter than full + randomly pitched per shot, like the charge sting.
const BEEP_VOLUME_DB: float = -8.0
const BEEP_PITCH_MIN: float = 0.8
const BEEP_PITCH_MAX: float = 1.25

## The NPC this plays for — set right after .new() in NPC._ready. READ-only here (we read its
## threat_response to mute a fleer); the canonical state stays on the host.
var host: NPC

## Play the MGS "!" sting POSITIONALLY at `world_pos` when the NPC first notices its target — it sounds
## from the NPC, so a far-off spot is faint: an atmospheric detection cue, not the incoming-shot warning
## (the charge sting is that). A fleeing civilian noticing danger isn't a combat "!" alert, so it's muted.
## Throttled by the shared (static) cooldown so a group spotting at once doesn't stack it. Returns true
## iff the sting actually played, so the host can gate the matching "!" head-popup on the SAME cooldown.
func on_spotted(world_pos: Vector3) -> bool:
	if host.threat_response == NPC.ThreatResponse.FLEE:
		return false  # a fleeing civilian noticing danger isn't a combat "!" alert
	var now := Time.get_ticks_msec()
	if now - _last_alert_msec < NPC.ALERT_COOLDOWN_MS:
		return false
	_last_alert_msec = now
	AudioManager.play_sfx(world_pos, MGS_ALERT, 0.0, 1.0)  # positional — sounds from the NPC
	return true

## Play the scheduled sniper charge sting 2D — quiet + randomly pitched so it stays a subtle telegraph,
## not an in-your-ear blare, and substantially quieter when aiming at ANOTHER NPC (an NPC-vs-NPC trade is
## ambience, not an incoming-shot warning). The host calls this once the _aim_sfx_delay beat it scheduled
## in _on_aim elapses (in _physics_process), passing whether the current target is the player.
func play_charge_sting(targeting_player: bool) -> void:
	var pitch := randf_range(AIM_SFX_PITCH_MIN, AIM_SFX_PITCH_MAX)
	var aim_vol := AIM_SFX_VOLUME_DB if targeting_player else AIM_SFX_VOLUME_DB_VS_NPC
	AudioManager.play_2d_sfx(AIM_SFX, aim_vol, pitch)

## Play the incoming-shot warning beep 2D (always audible), quieter than full + randomly pitched per
## shot like the charge sting. The host fires this a beat (BEEP_LEAD_TIME) before a shot lands AT the
## player — that lead-time window is the root's firing cadence, so it lives there, not here.
func play_incoming_beep() -> void:
	AudioManager.play_2d_sfx(SHOT_WARNING_SFX, BEEP_VOLUME_DB, randf_range(BEEP_PITCH_MIN, BEEP_PITCH_MAX))
