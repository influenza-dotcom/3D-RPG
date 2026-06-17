class_name NpcAudioSettings
extends Resource

## Tuning for an NPC's combat-telegraph SOUND MIX (npc_audio_cues.gd): the per-cue volumes (dB) and the
## random pitch ranges for the charge sting, the incoming-shot beep, and the miss ricochet. The SFX ASSETS
## themselves stay as preloads on NpcAudioCues — this is just the mix a designer tunes for combat-audio feel.

@export_group("Charge Sting")
## Volume (dB) of the sniper charge-up sting when the NPC is aiming at the PLAYER. Below 0 so it doesn't blare.
@export var aim_sfx_volume_db: float = -17.0
## Much quieter charge sting when aiming at ANOTHER NPC (an NPC-vs-NPC trade is ambience, not an incoming-shot warning).
@export var aim_sfx_volume_db_vs_npc: float = -32.0
## Random pitch range on the charge sting per shot, so it doesn't blare identically every time.
@export var aim_sfx_pitch_min: float = 0.8
@export var aim_sfx_pitch_max: float = 1.25

@export_group("Incoming-Shot Beep")
## Volume (dB) of the warning beep a beat before the NPC fires AT the player (played 2D, always audible).
@export var beep_volume_db: float = -8.0
## Random pitch range on the beep per shot.
@export var beep_pitch_min: float = 0.8
@export var beep_pitch_max: float = 1.25

@export_group("Miss Ricochet")
## Volume (dB) of the "whiff past you" ricochet when a shot at the player was rolled to miss.
@export var miss_sfx_volume_db: float = -8.0
## Random pitch range on the miss ricochet.
@export var miss_sfx_pitch_min: float = 0.9
@export var miss_sfx_pitch_max: float = 1.1
