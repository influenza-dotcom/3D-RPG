class_name TtsSpeaker
extends Node

## Reads dialogue lines aloud via the OS text-to-speech — the TTS layer pulled out of DialogueManager.
## A code-built child of the manager (PROCESS_MODE_ALWAYS owner, so speech keeps going through the paused
## world; OS speech is GPU/OS-level anyway). Caches + classifies the OS voices in its own _ready. The
## manager drives it through speak(text, voice) / stop(); the spoken volume tracks the "voice" Godot bus
## (+ Master) since OS speech can't route through a bus.

var _voice: String = ""  ## cached OS text-to-speech voice; empty if TTS is unavailable/disabled
var _male_voice: String = ""    ## OS voice ids classified by name, for VoiceData's male/female toggle
var _female_voice: String = ""
var _voice_bus: int = -1  ## the "voice" bus whose level scales the TTS (OS speech can't use a Godot bus)

func _ready() -> void:
	# Cache a TTS voice (prefer English) so speak() can read each line aloud. Needs the
	# "audio/general/text_to_speech" project setting; the tts_* calls are silent no-ops without it.
	var en := DisplayServer.tts_get_voices_for_language("en")
	if not en.is_empty():
		_voice = en[0]  # default (prefer English)
	# Classify the voices into a male + female pick for VoiceData's toggle. Godot's TTS API exposes
	# no gender, so go by name (Windows ships "...David..." = male, "...Zira..." = female).
	for v in DisplayServer.tts_get_voices():
		var id := String(v.get("id", ""))
		if id.is_empty():
			continue
		if _voice.is_empty():
			_voice = id  # no English voice found — fall back to the first available
		if _is_female_name(String(v.get("name", ""))):
			if _female_voice.is_empty():
				_female_voice = id
		elif _male_voice.is_empty():
			_male_voice = id
	_voice_bus = AudioServer.get_bus_index("voice")

## Read `text` aloud, cutting any line still being spoken (interrupt). Uses the speaking character's
## VoiceData if set (its own voice id / pitch / rate), else the default cached voice.
func speak(text: String, voice: VoiceData) -> void:
	if text.is_empty():
		return
	var vid := _voice
	var pitch := 1.0
	var rate := 1.0
	if voice != null:
		var chosen := _female_voice if voice.female else _male_voice
		if not chosen.is_empty():
			vid = chosen
		pitch = voice.pitch
		rate = voice.rate
	if vid.is_empty():
		return
	DisplayServer.tts_speak(text, vid, _tts_volume(), pitch, rate, 0, true)

## Stop reading the current line aloud. A synchronous OS call that can stall a frame, so the manager
## cuts the line during the still-paused teardown to hide the stall behind the frozen world.
func stop() -> void:
	DisplayServer.tts_stop()

## TTS volume (0-100) derived from the "voice" bus (+ Master), since OS text-to-speech can't route
## through a Godot bus — this lets a Voice volume slider scale the spoken lines independently.
func _tts_volume() -> int:
	if _voice_bus < 0:
		return 100
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.is_bus_mute(_voice_bus) or (master >= 0 and AudioServer.is_bus_mute(master)):
		return 0
	var lin := db_to_linear(AudioServer.get_bus_volume_db(_voice_bus))
	if master >= 0:
		lin *= db_to_linear(AudioServer.get_bus_volume_db(master))
	return clampi(int(round(lin * 100.0)), 0, 100)

## Best-effort gender-by-name (Godot's TTS API exposes no gender). Covers common Windows / SAPI
## voice names; treats anything unrecognised as male.
func _is_female_name(voice_name: String) -> bool:
	var n := voice_name.to_lower()
	for hint in ["zira", "hazel", "susan", "catherine", "linda", "heera", "eva", "female", "woman", "samantha", "victoria", "karen", "aria", "jenny", "michelle", "hortense", "caroline"]:
		if n.contains(hint):
			return true
	return false
