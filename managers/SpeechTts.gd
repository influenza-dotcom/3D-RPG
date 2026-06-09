extends Node

## In-game text-to-speech, backed by the offline Flite "text_to_speech" addon — replaces the old OS
## DisplayServer.tts. Speech plays through Godot's audio engine (the "voice" bus, so the Voice volume slider
## applies natively) and can be POSITIONAL:
##   • DIALOGUE uses one reusable non-positional 1D player — you converse with one NPC at a time.
##   • BARKS (combat shouts / greetings) use a reused POOL of positional 3D players, so MULTIPLE NPCs can
##     shout AT ONCE (the bus mixes them), capped at MAX_BARK_PLAYERS voices.
##
## All players are built LAZILY on first use (and the bark pool grown on demand), so the addon doesn't spin
## up at all when TTS is off — and a test run that never speaks creates nothing.
##
## IMPORTANT — why a pool, not a node-per-bark: each addon player holds its synth engine (+ a voice manager)
## as a plain MEMBER node it never add_child's, so queue_free()ing a player does NOT free those — a fresh
## player per bark would leak two nodes every time. Pooling reuses a fixed set of players, so the node count
## stays bounded. All speech is gated on Settings.tts_enabled (OFF by default). Registered as the SpeechTts
## autoload; PROCESS_MODE_ALWAYS so a dialogue line keeps reading through the paused world.

const VOICE_BUS := "voice"
## Barks sit a touch below focused dialogue (which plays at the node's default 0 dB).
const BARK_VOLUME_DB := -4.0
## How many bark voices may play at once. A 9th simultaneous bark is dropped rather than cutting one off.
const MAX_BARK_PLAYERS := 8

var _dialogue: TextToSpeech1D = null         ## focused dialogue lines; built lazily on first use
var _bark_pool: Array[TextToSpeech3D] = []   ## reused positional bark players (grown lazily to MAX, never freed)
var _busy: Dictionary = {}                   ## bark player -> true while mid-utterance (so it isn't reused yet)
var _bark_owner: Dictionary = {}             ## bark player -> source instance_id (so only that source's death cuts it)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Nothing is built here — players (and their synth engines) are created lazily on first use, so the addon
	# stays dormant when TTS is off and a non-speaking test run leaks nothing.

## Boot-time warm-up (called deferred by PreloadManager): extract the bundled Flite voices to user:// in an
## EXPORTED build (idempotent; a no-op in the editor, which reads them from res://) so the first spoken line
## doesn't hitch doing the one-time install. The Flite engine itself warms on the first say().
func prewarm() -> void:
	var vm := VoiceManager.new()
	vm.ensure_voices_installed()
	vm.free()

## Read a focused dialogue `line` aloud in `voice` (the speaking character's VoiceData, or null for the
## default voice). Fire-and-forget: the addon's say() synthesizes + plays asynchronously and we deliberately
## DON'T await it, so the conversation flow isn't blocked. Cuts any line still playing first.
func speak_dialogue(line: String, voice: VoiceData) -> void:
	if not Settings.tts_enabled or line.is_empty():
		return
	if _dialogue == null:
		_dialogue = TextToSpeech1D.new()
		_dialogue.bus = VOICE_BUS
		add_child(_dialogue)
	_dialogue.stop()
	_dialogue.say(line, _voice_name(voice), _speed(voice))

## Stop the current dialogue line (the conversation advanced or ended).
func stop_dialogue() -> void:
	if _dialogue != null:
		_dialogue.stop()

## Speak a one-off NPC `bark` at `world_pos` in `voice`, attributed to `source`. Pulls a free player from the
## bark pool so DIFFERENT NPCs shout simultaneously (the Voice bus mixes them), up to MAX_BARK_PLAYERS. A new
## bark from the SAME source silences its previous one (no talking over itself); never touches another NPC's.
func speak_bark(world_pos: Vector3, bark: String, voice: VoiceData, source: Object = null) -> void:
	if not Settings.tts_enabled or bark.is_empty():
		return
	_silence_source(source)
	var p := _free_bark_player()
	if p == null:
		return  # all MAX voices already shouting — drop this one rather than cut someone off
	_busy[p] = true
	if source != null:
		_bark_owner[p] = source.get_instance_id()
	p.global_position = world_pos
	# Await the utterance, then RELEASE the player back to the pool — we never free it (the addon's engine is
	# a non-tree member a free() wouldn't release, so reuse, don't recreate).
	await p.say(bark, _voice_name(voice), _speed(voice))
	_busy.erase(p)
	_bark_owner.erase(p)

## Cut the playing bark for `source` (e.g. it just died) — only its own, never another NPC's.
func stop_bark_from(source: Object) -> void:
	_silence_source(source)

## An idle pooled player, else a freshly-grown one (up to MAX), else null when every voice is busy.
func _free_bark_player() -> TextToSpeech3D:
	for p in _bark_pool:
		if not _busy.get(p, false):
			return p
	if _bark_pool.size() < MAX_BARK_PLAYERS:
		var np := TextToSpeech3D.new()
		np.bus = VOICE_BUS
		np.volume_db = BARK_VOLUME_DB
		add_child(np)
		_bark_pool.append(np)
		return np
	return null

## Silence a source's bark (it died, or it's about to speak again). Stops the audio NOW; the player stays
## flagged busy until its say() coroutine unwinds (which avoids resuming that coroutine after a stop), then
## it returns to the pool. Touches only that source's player.
func _silence_source(source: Object) -> void:
	if source == null:
		return
	var id := source.get_instance_id()
	for p in _bark_owner.keys():
		if _bark_owner[p] == id:
			if is_instance_valid(p):
				p.stop()
			_bark_owner.erase(p)
			break

## The Flite voice name for `voice` (its per-character pick / legacy default), or the male default for a
## speaker with no VoiceData.
func _voice_name(voice: VoiceData) -> String:
	return voice.voice_name() if voice != null else VoiceData.MALE_DEFAULT

## The playback speed for `voice` (rate × pitch), or normal speed for a speaker with no VoiceData.
func _speed(voice: VoiceData) -> float:
	return voice.speed() if voice != null else 1.0
