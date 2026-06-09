extends GutTest

## VoiceData — how a character's lines map onto the Flite TTS addon (per-character voice + playback speed).
## Pure logic only (voice_name / speed); the actual synthesis lives in the SpeechTts autoload + the
## GDExtension, which a headless unit run can't exercise. VoiceData extends Resource (RefCounted), so
## instances are made with .new() and released with `= null` (NEVER .free()).

func test_voice_name_uses_explicit_pick() -> void:
	var v := VoiceData.new()
	v.flite_voice = "cmu_us_eey"
	assert_eq(v.voice_name(), "cmu_us_eey",
		"an explicit flite_voice is used verbatim")
	v.female = true  # legacy toggle is ignored once an explicit voice is set
	assert_eq(v.voice_name(), "cmu_us_eey",
		"the explicit per-character pick wins over the legacy female toggle")
	v = null


func test_voice_name_falls_back_to_legacy_female_toggle() -> void:
	var v := VoiceData.new()  # flite_voice blank by default
	assert_eq(v.voice_name(), VoiceData.MALE_DEFAULT,
		"blank flite_voice + female=false -> the male default voice (back-compat for old resources)")
	v.female = true
	assert_eq(v.voice_name(), VoiceData.FEMALE_DEFAULT,
		"blank flite_voice + female=true -> the female default voice")
	v = null


func test_speed_is_rate_times_pitch_clamped() -> void:
	var v := VoiceData.new()
	assert_almost_eq(v.speed(), 1.0, 0.0001,
		"default rate 1.0 x pitch 1.0 -> normal speed")
	v.rate = 1.5
	v.pitch = 1.2
	assert_almost_eq(v.speed(), 1.8, 0.0001,
		"speed folds rate x pitch into one knob (Flite scales the sample rate)")
	v.rate = 4.0
	v.pitch = 2.0  # 8.0 raw
	assert_almost_eq(v.speed(), 4.0, 0.0001,
		"speed clamps to the addon's sane max of 4.0")
	v.rate = 0.01
	v.pitch = 0.01  # 0.0001 raw
	assert_almost_eq(v.speed(), 0.1, 0.0001,
		"speed clamps to the addon's sane min of 0.1")
	v = null
