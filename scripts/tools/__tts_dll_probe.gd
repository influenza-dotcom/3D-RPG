extends SceneTree
## TTS extension probe (the __death_skip_probe idiom): drives the NATIVE TextToSpeech
## GDExtension class directly, headless — no autoloads, no audio device needed
## (speak_to_buffer is pure synthesis). Run:
##   godot --headless --path . -s scripts/tools/__tts_dll_probe.gd
## Prints one line per (voice, text): "<voice> <text#> <bytes> <hash>", then a voice-churn
## loop (the pattern that used to reload multi-MB voice blobs per switch), then PROBE OK.
## Used 2026-09-01 to verify the rebuilt private-heap DLL against the shipped one:
## identical buffer sizes/hashes = the audio pipeline is unchanged; surviving the churn
## loop = the voice-switch path is sound. Keep for future DLL upgrades.

const VOICES := [
	"cmu_us_aew", "cmu_us_ahw", "cmu_us_awb", "cmu_us_eey",
	"cmu_us_fem", "cmu_us_slp", "cmu_us_slt",
]
const LINES := [
	"Contact! Hostile spotted.",
	"The Ledger sees every debt, and tonight it collects yours with interest.",
	"One hundred percent dead by 4:51 PM on 12/31/2077.",
]

func _initialize() -> void:
	var tts = ClassDB.instantiate(&"TextToSpeech")
	if tts == null:
		printerr("PROBE FAIL: TextToSpeech class not registered (extension did not load)")
		quit(1)
		return
	for v in VOICES:
		var path := ProjectSettings.globalize_path("res://addons/text_to_speech/voices/%s.flitevox.res" % v)
		var err: int = tts.set_voice_path(path)
		if err != OK:
			printerr("PROBE FAIL: set_voice_path(%s) -> %d" % [v, err])
			quit(1)
			return
		for t in LINES.size():
			var buf: PackedByteArray = tts.speak_to_buffer(LINES[t])
			if buf.is_empty():
				printerr("PROBE FAIL: empty buffer for %s line %d" % [v, t])
				quit(1)
				return
			print("%s %d %d %d %d" % [v, t, buf.size(), hash(buf), tts.get_sample_rate()])
	# Churn: rapid voice alternation + synth — the exact pattern that used to drop+load
	# a 6-12 MB voice per switch. 60 switches; any heap fault fail-fasts the process.
	for i in 60:
		var v: String = VOICES[i % VOICES.size()]
		tts.set_voice_path(ProjectSettings.globalize_path("res://addons/text_to_speech/voices/%s.flitevox.res" % v))
		var buf: PackedByteArray = tts.speak_to_buffer("Switch %d." % i)
		if buf.is_empty():
			printerr("PROBE FAIL: churn synth %d empty" % i)
			quit(1)
			return
	print("PROBE OK")
	quit(0)
