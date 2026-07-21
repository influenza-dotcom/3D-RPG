class_name TextToSpeechEngine
extends Node

var tts: TextToSpeech = TextToSpeech.new()
var voice_manager = VoiceManager.new()
var current_voice_path
var _say_token: int = 0

func cancel() -> void:
	_say_token += 1

func load_voice(voice_path, token: int) -> bool:
	voice_manager.ensure_voices_installed()
	await voice_manager.wait_for_voice(voice_path)
	if token != _say_token:
		return false
	tts.set_voice_path(voice_path)
	current_voice_path = voice_path
	return true

func say(player, text: String, voice: String, speed: float) -> void:
	_say_token += 1
	var token := _say_token
	var voice_path = voice_manager.get_voice_path(voice)
	if current_voice_path != voice_path:
		var loaded: bool = await load_voice(voice_path, token)
		if not loaded:
			return
	elif token != _say_token:
		return

	var pcm: PackedByteArray = tts.speak_to_buffer(text)
	if token != _say_token:
		return

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.mix_rate = tts.get_sample_rate() * speed
	wav.data = pcm

	player.stream = wav
	await Engine.get_main_loop().process_frame
	if token != _say_token:
		return
	player.play()
	
	var samples := pcm.size() / 2  # 16-bit samples → 2 bytes
	var duration := float(samples) / wav.mix_rate

	await Engine.get_main_loop().create_timer(duration).timeout
