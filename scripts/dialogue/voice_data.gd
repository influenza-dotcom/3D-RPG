class_name VoiceData
extends Resource

## How a character's lines are read aloud by the in-game text-to-speech — the offline Flite "text_to_speech"
## addon, which (unlike the old OS speech) routes through a Godot bus and can play positionally. Assign one
## to a Talkable / DialogueNPC `voice`. `flite_voice` picks the synthesized voice PER CHARACTER; `rate` /
## `pitch` fine-tune the playback speed within it.

## The bundled Flite voices, by rough timbre. slt + fem read female; the rest read male. `voice_name()`
## maps the legacy `female` toggle onto these when no explicit voice is picked.
const MALE_DEFAULT := "cmu_us_aew"
const FEMALE_DEFAULT := "cmu_us_slt"

## The synthesized voice this character speaks in — one of the addon's bundled Flite voices. Leave blank to
## fall back to a male/female default from the legacy `female` toggle below (keeps old resources working).
@export_enum("cmu_us_aew", "cmu_us_ahw", "cmu_us_awb", "cmu_us_eey", "cmu_us_fem", "cmu_us_slp", "cmu_us_slt") var flite_voice: String = ""
## Speaking rate — 1.0 is normal, higher is faster. Flite scales the sample rate, so a faster rate also reads
## a touch higher-pitched (it has no independent tempo/pitch split).
@export_range(0.1, 4.0) var rate: float = 1.0
## Pitch nudge, FOLDED INTO the playback speed (Flite has no separate pitch knob): >1 sounds higher + a touch
## faster, <1 deeper + slower. For predictable control prefer `rate`; pitch is an approximate sweetener.
@export_range(0.1, 2.0) var pitch: float = 1.0
## DEPRECATED (the OS-TTS-era male/female toggle). Only consulted when `flite_voice` is blank, so existing
## VoiceData resources still pick a sensible male/female voice without re-authoring.
@export var female: bool = false

## The Flite voice name to synthesize with: the explicit per-character pick, or a male/female default derived
## from the legacy `female` toggle when none is set.
func voice_name() -> String:
	if not flite_voice.is_empty():
		return flite_voice
	return FEMALE_DEFAULT if female else MALE_DEFAULT

## The playback speed handed to the addon's say(): rate × pitch, since Flite folds tempo + pitch into one
## sample-rate scale. Clamped to the addon's sane range.
func speed() -> float:
	return clampf(rate * pitch, 0.1, 4.0)
