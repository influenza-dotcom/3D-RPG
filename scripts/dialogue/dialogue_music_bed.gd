class_name DialogueMusicBed
extends AudioStreamPlayer

## Plays a LOOPING music bed under conversations — fades in as the dialogue box opens, fades back out and
## stops when the conversation ends. A code-built child of DialogueManager (PROCESS_MODE_ALWAYS, so it keeps
## playing through the dialogue tree-pause exactly like the scene's Music / Ambience players); the manager
## drives it through the single set_bed_playing(bool) facade, mirroring MusicDucker.set_ducked(). (The name
## avoids `set_playing` — that would shadow the native AudioStreamPlayer `playing` property's setter, which the
## engine rejects with a warning this project treats as an error.)
##
## The track, level, fades, talk duck and bus are designer knobs on GameSettings.dialogue (dialogue_music /
## dialogue_music_volume_db / dialogue_music_fade_in / dialogue_music_fade_out / dialogue_music_talk_duck_db /
## dialogue_music_talk_duck_fade / dialogue_music_bus).
## Leave `dialogue_music` EMPTY for the old behaviour: conversations play with no bed at all.
##
## TWO THINGS THIS IS NOT:
## • Not the MusicDucker. That fades the whole `music` BUS down so whatever is already playing (a diegetic
##   Radio) sits under the voices. This ADDS a layer. Both run for the same conversation, and because the bed
##   defaults to the `music` bus the duck applies to it too — a CONSTANT offset, since the bed only ever plays
##   while a conversation is up. Tune by ear with dialogue_music_volume_db, but know that editing
##   music_duck_amount_db shifts this bed's level as well.
## • Not the MusicDirector score. That fades the scene's Music node in for COMBAT (and holds it there, ducked,
##   through the CAUTION hunt), while holding it SILENT during dialogue by default (swell_for_dialogue = false) —
##   which is why this loop is normally the only music you hear while talking. That suppression is load-bearing
##   now, not incidental: a conversation pauses the tree, so a searcher outside would otherwise hold the combat
##   bed under every line. Turn swell_for_dialogue ON and the two play TOGETHER — pick one or the other.
##
## LIFECYCLE mirrors the ducker exactly: on at start(), off at _finish(). A conversation merely SUSPENDED
## behind a sub-menu (Trade / Heal / Level Up / Install) keeps the bed playing — the conversation still
## EXISTS (is_engaged()), the box is just hidden, and cutting the music there would stutter the scene. It
## does, however, STEP ASIDE for that sub-menu's own music: those are STATION screens, and a station's
## machine plays its own tinny radio (managers/StationMusic.gd), which asserts note_menu_music(true) every
## frame it is up. The loop keeps its position and swells back when the sub-menu closes.
## The bed RESTARTS from the top each conversation, so a short loop always opens on its downbeat.
##
## THE TALK DUCK: on top of the conversation envelope, the bed dips SLIGHTLY (dialogue_music_talk_duck_db)
## while a line is actually being SPOKEN, so the loop seats under the voice and swells back while the player
## reads the response menu. The manager pulses note_line_speech(secs) per spoken line — the SAME estimated
## envelope that drives the speaker's head-bob (NPC.note_speaking) — and cuts it with note_line_speech_stop()
## when the menu goes up / the conversation ends. The dip and the conversation fades are SEPARATE levels
## (_base_db + _speech_duck_db) summed into volume_db, so the two tweens compose instead of fighting (the
## first line starts speaking while the fade-in is still swelling).

## The "off" floor the fades run from/to. Effectively inaudible; the bed is stop()ed once a fade-out lands,
## so nothing is left spinning between conversations.
const SILENT_DB: float = -60.0

var _bed_playing: bool = false  ## guards against a re-trigger restarting the loop mid-conversation, and stops the `finished` restart backstop from firing during/after the fade-out
var _fade: Tween
var _base_db: float = SILENT_DB   ## the conversation envelope (silence <-> authored level); one of the two levels summed into volume_db
var _speech_duck_db: float = 0.0  ## the talk-duck offset while a line is spoken (0 = un-ducked); the other summed level
var _speech_token: int = 0        ## bumped on every pulse/stop; a pending talk-duck auto-release only fires if its token still matches (so the next line's pulse extends the dip instead of being cut by the previous line's timer)
var _duck_fade: Tween
var _menu_duck_db: float = 0.0    ## the THIRD summed level: how far this bed steps aside while a station TERMINAL's own radio plays (StationMusic drives it) — see note_menu_music
var _menu_ducked: bool = false    ## latch mirroring the requested state, so StationMusic's per-frame assert is idempotent and only a CHANGE builds a tween
var _menu_fade: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep playing through the dialogue tree-pause
	var cfg: DialogueSettings = GameSettings.dialogue
	stream = _looping_copy(cfg.dialogue_music)
	bus = cfg.dialogue_music_bus
	volume_db = SILENT_DB  # start silent; set_bed_playing(true) fades up to the authored level
	autoplay = false
	if stream == null:
		return  # no authored bed — this node just sits inert (conversations play dry, the pre-bed behaviour)
	# Last-resort backstop: a stream shape we couldn't force to loop still gets restarted when it ends, so a
	# long conversation keeps its bed (with a seam at the join). A looping stream never emits `finished`, so
	# in the normal case this connection is inert.
	finished.connect(_on_finished)

## The stream the bed actually plays: the authored track, GUARANTEED to loop. A bed that stops dead partway
## through a conversation is never what a designer meant by "dialogue music", so rather than depend on the track's
## import settings being right we FORCE the loop flag here — on a duplicate, so we never mutate the shared
## resource other systems (or a future Radio playlist) may be holding. An already-looping track is used as-is,
## with no copy. Null in -> null out (an unauthored bed).
## Delegates to LoopableStream, the shared owner since the station-terminal bed (managers/StationMusic.gd)
## became a second consumer — the zero-length-WAV-range scar this reads around must live in exactly one place.
## Kept as an INSTANCE method under this exact name and signature: tests/test_dialogue_music_bed.gd calls it
## directly on a bare instance.
func _looping_copy(authored: AudioStream) -> AudioStream:
	return LoopableStream.looping_copy(authored, "DialogueMusicBed")

## Fade the dialogue bed in (true) as a conversation opens, out (false) when it ends. No-op without an
## authored track. Safe to call repeatedly — a redundant true won't restart the loop mid-conversation.
func set_bed_playing(play_bed: bool) -> void:
	if stream == null:
		return
	if play_bed == _bed_playing:
		return  # already in the requested state; never re-seek a loop that's already under the conversation
	_bed_playing = play_bed
	var cfg: DialogueSettings = GameSettings.dialogue
	if play_bed:
		# play() restarts at 0, so a short loop always opens on its downbeat — including a conversation that
		# re-opens while the previous fade-out is still running (the fade below then swells from wherever the
		# envelope currently sits, so it slides back up rather than popping).
		play()
	# Either direction settles the talk duck: a conversation must OPEN un-ducked (no stale dip inherited
	# across conversations), and the fade-out should carry the swell-back with it rather than freeze a dip in.
	# Its short fade runs in parallel with the envelope fade below — the two levels compose.
	note_line_speech_stop()
	# Same settle rule for the station-terminal handover, and for the same reason: a conversation must never
	# open (or close) with a stale -60 dB menu dip frozen in. StationMusic re-asserts every frame, so if a
	# terminal genuinely IS still up the dip is simply rebuilt on the next tick.
	note_menu_music(false)
	var target: float = cfg.dialogue_music_volume_db if play_bed else SILENT_DB
	var time: float = cfg.dialogue_music_fade_in if play_bed else cfg.dialogue_music_fade_out
	if _fade and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_method(_set_base_db, _base_db, target, maxf(time, 0.0))
	if not play_bed:
		# Stop only once the fade-out has actually landed — stopping up front would cut the tail dead.
		# Guarded on _bed_playing so a conversation that re-opens DURING the fade-out isn't silenced by
		# this stale callback (set_bed_playing(true) flipped the flag back before the tween finished).
		_fade.finished.connect(_stop_if_still_idle)

func _stop_if_still_idle() -> void:
	if not _bed_playing:
		stop()

## The manager's pulse that a line is being SPOKEN right now (the bed-side mirror of NPC.note_speaking):
## dip the bed slightly under the voice for the line's estimated spoken time, then swell back. A monologue
## re-pulses before the release lands, so consecutive lines hold ONE continuous dip rather than yo-yoing;
## the swell-back comes at the response menu (note_line_speech_stop) or, with auto-advance off, once the
## estimate elapses and the NPC falls silent. `seconds` is the same estimate the head-bob runs on — real TTS
## audio may overrun it slightly, exactly as the head-bob does. No-op without a playing bed.
func note_line_speech(seconds: float) -> void:
	if stream == null or not _bed_playing:
		return
	_speech_token += 1  # a still-pending release from the PREVIOUS line must not cut this line's dip short
	# A positive "duck" would BOOST the bed over the voice — clamp to off. Authored 0 = talk duck disabled:
	# no dip, no timer. But SETTLE (don't just skip) — the knob is read live per-pulse, so a mid-monologue
	# retune to 0 arrives with the previous line's dip still held and its release timer just invalidated by
	# the token bump above; a bare return here would freeze that dip in until the response menu.
	var duck: float = minf(GameSettings.dialogue.dialogue_music_talk_duck_db, 0.0)
	if duck >= 0.0:
		if _speech_duck_db != 0.0 or (_duck_fade and _duck_fade.is_valid()):
			_fade_speech_duck(0.0)
		return
	_fade_speech_duck(duck)
	# Token-guarded auto-release at the end of the spoken estimate; process_always so it ticks through the
	# dialogue tree-pause. Bound-method connect (not a lambda) per the freed-capture rule, though this node
	# is an autoload child and outlives every timer anyway.
	get_tree().create_timer(maxf(seconds, 0.0), true).timeout.connect(_release_speech_duck.bind(_speech_token))

## The line is no longer being delivered — the response menu went up, the conversation is ending, or the bed
## itself is turning over (set_bed_playing calls this both directions). Swells the dip back to level and
## invalidates any pending auto-release so it can't fire into the next line/conversation. Cheap no-op when
## nothing is ducked and nothing is in flight (also what keeps it safe on an off-tree bed: no tween is built).
func note_line_speech_stop() -> void:
	_speech_token += 1
	if _speech_duck_db == 0.0 and not (_duck_fade and _duck_fade.is_valid()):
		return
	_fade_speech_duck(0.0)

## A station TERMINAL's screen is up (true) or is not (false) — asserted EVERY FRAME by the StationMusic
## autoload rather than pulsed on the edge, because the latch below makes the call idempotent and a per-frame
## assert has no ordering hazard against a conversation starting or ending.
##
## While true this bed steps aside by dialogue_music_menu_duck_db (default -60 = a FULL handover) so a
## dialogue-hosted Trade / Heal / Level Up / Install / Chess / Bank plays ONE bed — the machine's — instead of
## two stacked ones. It is a DUCK, not a stop: the loop keeps its position and swells back when the sub-menu
## closes, the same reason a suspended conversation keeps the bed playing at all (see the LIFECYCLE note).
## This is why the feature behaves identically on a bare kiosk and on a person-vendor who hosts the shop
## inside a conversation.
func note_menu_music(under_menu: bool) -> void:
	if under_menu == _menu_ducked:
		return
	_menu_ducked = under_menu
	var cfg: DialogueSettings = GameSettings.dialogue
	# minf(.., 0.0): a duck can only ever pull DOWN — a positive knob must not make the bed louder than authored.
	var target: float = minf(cfg.dialogue_music_menu_duck_db, 0.0) if under_menu else 0.0
	if _menu_fade and _menu_fade.is_valid():
		_menu_fade.kill()
	_menu_fade = create_tween()
	_menu_fade.tween_method(_set_menu_duck_db, _menu_duck_db, target, maxf(cfg.dialogue_music_menu_duck_fade, 0.0))

func _set_menu_duck_db(db: float) -> void:
	_menu_duck_db = db
	_apply_volume()

## The spoken estimate elapsed with no advance (auto-advance off, player idling on the line): release the dip —
## unless the token moved, i.e. a newer line re-pulsed or a stop already settled it.
func _release_speech_duck(tok: int) -> void:
	if tok != _speech_token:
		return
	_fade_speech_duck(0.0)

func _fade_speech_duck(target: float) -> void:
	if _duck_fade and _duck_fade.is_valid():
		_duck_fade.kill()
	_duck_fade = create_tween()
	_duck_fade.tween_method(_set_speech_duck_db, _speech_duck_db, target, maxf(GameSettings.dialogue.dialogue_music_talk_duck_fade, 0.0))

func _set_base_db(db: float) -> void:
	_base_db = db
	_apply_volume()

func _set_speech_duck_db(db: float) -> void:
	_speech_duck_db = db
	_apply_volume()

## The ONE place the live volume is composed: the conversation envelope, plus the talk-duck offset, plus the
## station-terminal handover. All three fade tweens write their own level and meet here, so none ever stomps
## another's contribution (the conversation fade-in runs WHILE the first line dips, and a terminal can open
## mid-line).
func _apply_volume() -> void:
	volume_db = _base_db + _speech_duck_db + _menu_duck_db

## `finished` fires only for a stream that ISN'T set to loop (see _ready) — restart it so the bed covers a
## conversation longer than the track. Gated on _bed_playing so it can't resurrect the bed after the
## conversation ended (a short track finishing during the fade-out would otherwise start it up again).
func _on_finished() -> void:
	if _bed_playing:
		play()

## Delegates to LoopableStream.loops — see there for the zero-length-WAV-range trap this reads around. Kept
## under its exact old name/signature for the same reason as _looping_copy: the tests call it on an instance.
func _stream_loops(s: AudioStream) -> bool:
	return LoopableStream.loops(s)
