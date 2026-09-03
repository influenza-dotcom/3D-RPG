extends Node

## In-game text-to-speech, backed by the offline Flite "text_to_speech" addon — replaces the old OS
## DisplayServer.tts. Speech plays through Godot's audio engine (the "voice" bus, so the Voice volume slider
## applies natively) and can be POSITIONAL:
##   • DIALOGUE uses a small pool of non-positional 1D players, one PINNED per voice — you still converse
##     with one NPC at a time (only one ever plays; stop_dialogue cuts the ACTIVE one), the pool exists so
##     a conversation's speaker change never re-voices a live engine (see _dialogue_player).
##   • BARKS (combat shouts / greetings) use a reused POOL of positional 3D players, so MULTIPLE NPCs can
##     shout AT ONCE (the bus mixes them), capped at MAX_BARK_PLAYERS voices.
##
## All players are built LAZILY on first use (and both pools grown on demand), so the addon doesn't spin
## up at all when TTS is switched off — and a test run that never speaks creates nothing. The one piece of
## boot-time work is prewarm() (voice extraction + loading every bundled voice into the DLL's process-wide
## voice cache), gated on the same tts_enabled switch and skipped on the headless renderer, so an opted-out
## session and a headless test run still create nothing native.
##
## IMPORTANT — why a pool, not a node-per-bark: each addon player holds its synth engine (+ a voice manager)
## as a plain MEMBER node it never add_child's, so queue_free()ing a player does NOT free those — a fresh
## player per bark would leak two nodes every time. Pooling reuses a fixed set of players, so the node count
## stays bounded. All speech is gated on Settings.tts_enabled (ON by default since 2026-09-01 — players must
## hear an NPC when they talk to them; the Options row is the opt-OUT). Registered as the SpeechTts
## autoload; PROCESS_MODE_ALWAYS so a dialogue line keeps reading through the paused world.

const VOICE_BUS := "voice"
## Barks sit a touch below focused dialogue (which plays at the node's default 0 dB).
const BARK_VOLUME_DB := -4.0
## How many bark voices may play at once. A 9th simultaneous bark is dropped rather than cutting one off.
const MAX_BARK_PLAYERS := 8
## A bundled voice file is `<voice_name>` + this suffix (the addon's own naming; VoiceManager.get_voice_path
## appends the same). bundled_voice_names() strips it to recover the names the pools speak in.
const VOICE_FILE_SUFFIX := ".flitevox.res"
## The throwaway line prewarm synthesises into a DISCARDED buffer to run flite's first-utterance init at boot.
## Never played, never painted — developer plumbing, not player-facing copy (so not PlayerText).
const PREWARM_UTTERANCE := "ok"

signal dialogue_speech_finished(token: int)

var _dialogue_pool: Dictionary = {}          ## Flite voice name -> TextToSpeech1D, each PINNED to that voice (see _dialogue_player)
var _dialogue_active: TextToSpeech1D = null  ## the player speaking the current line — the one stop_dialogue cuts
var _bark_pool: Array[TextToSpeech3D] = []   ## reused positional bark players (grown lazily to MAX, never freed)
var _busy: Dictionary = {}                   ## bark player -> true while mid-utterance (so it isn't reused yet)
var _bark_owner: Dictionary = {}             ## bark player -> source instance_id (so only that source's death cuts it)
var _vm: VoiceManager = null                 ## pure path resolution (no engine), to route a bark to a player already on its voice
var _dialogue_token: int = 0                 ## increments on every dialogue start/stop so stale async completions are ignored

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# No speech engines are built here — the players (and their synth engines) are created lazily on first use,
	# so the addon stays dormant when TTS is off and a non-speaking test run leaks nothing. The VoiceManager is
	# pure path resolution (no native TTS, no print) — used to prefer a pool player already on the bark's voice.
	_vm = VoiceManager.new()
	add_child(_vm)

## Boot-time warm-up (called deferred by PreloadManager). Two halves:
##   1. Extract the bundled Flite voices to user:// in an EXPORTED build (idempotent; a no-op in the editor,
##      which reads them from res://) so the first spoken line doesn't hitch doing the one-time install.
##   2. Load EVERY bundled voice into the DLL's PROCESS-WIDE voice cache through one throwaway native engine,
##      then run one tiny synthesis on the default voice. The 2026-09-01 rebuilt DLL caches voices process-wide
##      (never delete_voice), so after this a set_voice_path on ANY pool player — the first bark of each voice,
##      a dialogue speaker change, a re-voiced bark player at MAX — is an instant cache hit instead of a 6-12 MB
##      synchronous main-thread load, and the first speak_to_buffer has flite's one-time init behind it. Before
##      this the engine warmed on the first say(): the first witness bark of a kill, or the aggro shout when the
##      player was first shot at — the "first time I get shot" hitch. Nothing is PLAYED (speak_to_buffer only
##      returns PCM), so the audible behaviour is unchanged.
## The engine half is skipped on the headless renderer (GUT's test_smoke calls this) and gated on
## Settings.tts_enabled like every other speech path (the header's dormant-when-off contract; a mid-session
## opt-in then just pays the old per-voice first-bark load). Every native call is guarded, so a build without
## the extension degrades to the extraction alone.
func prewarm() -> void:
	var vm := VoiceManager.new()
	vm.ensure_voices_installed()
	if DisplayServer.get_name() != "headless" and Settings.tts_enabled:
		_prewarm_voice_cache(vm)
	vm.free()

## Load every bundled voice into the native DLL's process-wide cache + one throwaway synthesis (see prewarm).
## The engine is a BARE native TextToSpeech — no TextToSpeech3D/1D, no audio player, nothing added to the
## tree — built through ClassDB so a build without the extension is a no-op instead of a parse error, and
## discarded at the end: the cache lives in the DLL, not in the engine instance. Voices resolve through
## `vm.get_voice_path` exactly as the addon's engine resolves them (res:// in the editor, the user:// extraction
## in an export), and a path that is not on disk is skipped rather than handed to the DLL. The default voice is
## loaded LAST so the synthesis exercises the one an unvoiced bark will use.
func _prewarm_voice_cache(vm: VoiceManager) -> void:
	if vm == null or not ClassDB.class_exists(&"TextToSpeech"):
		return
	var engine = ClassDB.instantiate(&"TextToSpeech")  # untyped on purpose: an extension class has no GDScript type
	if engine == null:
		return
	if engine.has_method(&"set_voice_path") and engine.has_method(&"speak_to_buffer"):
		var default_path: String = vm.get_voice_path(VoiceData.MALE_DEFAULT)
		for voice_name in bundled_voice_names():
			var path: String = vm.get_voice_path(voice_name)
			if path == default_path or not FileAccess.file_exists(path):
				continue
			engine.set_voice_path(path)
		if FileAccess.file_exists(default_path):
			engine.set_voice_path(default_path)
			engine.speak_to_buffer(PREWARM_UTTERANCE)
	# A RefCounted engine frees itself when the local drops; a plain Object must be freed by hand.
	if engine is Object and not (engine is RefCounted):
		engine.free()

## The bundled Flite voice names — every `<name>.flitevox.res` under VoiceManager.VOICE_DIR_RES, sorted. The same
## directory walk ensure_voices_installed extracts from, so the warm set can never drift from the shipped set
## (VoiceData's @export_enum is the designer-facing copy of this list). Empty when the folder is missing.
static func bundled_voice_names() -> PackedStringArray:
	var names := PackedStringArray()
	var d := DirAccess.open(VoiceManager.VOICE_DIR_RES)
	if d == null:
		return names
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(VOICE_FILE_SUFFIX):
			names.append(fname.trim_suffix(VOICE_FILE_SUFFIX))
		fname = d.get_next()
	d.list_dir_end()
	names.sort()
	return names

## Read a focused dialogue `line` aloud in `voice` (the speaking character's VoiceData, or null for the
## default voice). Fire-and-forget: the addon's say() synthesizes + plays asynchronously; the returned token
## is emitted via dialogue_speech_finished when the real generated audio duration elapses. Returns 0 when no
## speech was started, so callers can fall back to estimated timing. Cuts any line still playing first.
func speak_dialogue(line: String, voice: VoiceData) -> int:
	stop_dialogue()
	if not Settings.tts_enabled or line.is_empty():
		return 0
	var p := _dialogue_player(_voice_name(voice))
	_dialogue_active = p
	_dialogue_token += 1
	var token := _dialogue_token
	_speak_dialogue_async(p, line, voice, token)
	return token

func _speak_dialogue_async(p: TextToSpeech1D, line: String, voice: VoiceData, token: int) -> void:
	await p.say(line, _voice_name(voice), _speed(voice))
	if token == _dialogue_token:
		dialogue_speech_finished.emit(token)

## The dialogue player PINNED to `voice` (a Flite voice name), built lazily on first use. One player per
## voice — NOT one shared player — so a conversation's speaker change never re-voices a live engine:
## set_voice_path makes the DLL drop + load a 6-12 MB .flitevox blob on its own native heap, the addon's
## heaviest alloc/free churn, and the 08/28-29 playtest crashes were heap-corruption fail-fasts at a free()
## INSIDE this DLL (the bark pool's grow-don't-revoice rule in _free_bark_player exists for the same reason).
## With pinning, each voice loads at most ONCE per pool per session — and since the 2026-09-01 DLL rebuild
## (process-wide voice cache) + prewarm(), that load is a cache hit; the pinning stays as belt-and-braces
## (it also spares the "Voice loaded" console spam). Bounded by construction: the key space
## is the bundled voice set (7 + the default), each entry holding one loaded voice — the same worst case the
## bark pool already accepts; players are children of this autoload and are never freed (the engine-member
## leak note in the header).
func _dialogue_player(voice: String) -> TextToSpeech1D:
	var p: TextToSpeech1D = _dialogue_pool.get(voice)
	if p == null:
		p = TextToSpeech1D.new()
		p.bus = VOICE_BUS
		add_child(p)
		_dialogue_pool[voice] = p
	return p

## Stop the current dialogue line (the conversation advanced or ended). Cuts only the ACTIVE player — the
## other pinned voices are already idle (speak_dialogue always stops the previous line before starting one).
func stop_dialogue() -> void:
	_dialogue_token += 1
	if _dialogue_active != null and is_instance_valid(_dialogue_active):
		_dialogue_active.cancel_speech()
		_dialogue_active.stop()
	_dialogue_active = null

## Speak a one-off NPC `bark` at `world_pos` in `voice`, attributed to `source`. Pulls a free player from the
## bark pool so DIFFERENT NPCs shout simultaneously (the Voice bus mixes them), up to MAX_BARK_PLAYERS. A new
## bark from the SAME source silences its previous one (no talking over itself); never touches another NPC's.
func speak_bark(world_pos: Vector3, bark: String, voice: VoiceData, source: Object = null) -> void:
	if not Settings.tts_enabled or bark.is_empty():
		return
	_silence_source(source)
	var p := _free_bark_player(_voice_name(voice))
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

## A free bark player for `voice`. PREFERS an idle player that ALREADY has this voice loaded so the (native)
## Flite engine doesn't re-load the voice file -- a reload prints "Voice loaded", and reloading on every bark as
## the male/female voices alternated through the shared pool was the repeated console spam. With no match it
## GROWS the pool (up to MAX) before it will RE-VOICE an idle player, so each player stays pinned to one voice.
## Why grow-first: a re-voice makes the DLL drop + load a 6-12 MB .flitevox blob on its own native heap — the
## addon's heaviest alloc/free churn, and the 08/28-29 playtest crashes were heap-corruption fail-fasts at a
## free() INSIDE this DLL (all its calls are synchronous main-thread; the GDScript cancel/stop path never even
## enters it) — so every reload avoided is crash exposure removed. Steady-state barks now reload ~never (7
## bundled voices ≤ MAX 8 players); worst-case pool size/memory is unchanged — 8 players each holding a voice
## was always reachable via 8 simultaneous barks, we just settle there sooner. Since the 2026-09-01 DLL rebuild
## the DLL caches voices process-wide and prewarm() fills that cache at boot, so even the step-3 re-voice is a
## cache hit; the grow-first rule stays as belt-and-braces. Null when every voice is shouting.
func _free_bark_player(voice: String) -> TextToSpeech3D:
	var want_path: String = _vm.get_voice_path(voice) if _vm != null else ""
	# 1) an idle player already on this exact voice -> no reload, no print.
	if want_path != "":
		for p in _bark_pool:
			if not _busy.get(p, false) and p.text_to_speech_engine != null \
					and p.text_to_speech_engine.current_voice_path == want_path:
				return p
	# 2) grow the pool (the new player loads `voice` once; step 1 then keeps that voice's barks on it).
	if _bark_pool.size() < MAX_BARK_PLAYERS:
		var np := TextToSpeech3D.new()
		np.bus = VOICE_BUS
		np.volume_db = BARK_VOLUME_DB
		add_child(np)
		_bark_pool.append(np)
		return np
	# 3) pool at MAX: re-voice any idle player — the one remaining native voice-reload path.
	for p in _bark_pool:
		if not _busy.get(p, false):
			return p
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
				p.cancel_speech()
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
