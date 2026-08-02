class_name DialogueMusicBed
extends AudioStreamPlayer

## Plays a LOOPING music bed under conversations — fades in as the dialogue box opens, fades back out and
## stops when the conversation ends. A code-built child of DialogueManager (PROCESS_MODE_ALWAYS, so it keeps
## playing through the dialogue tree-pause exactly like the scene's Music / Ambience players); the manager
## drives it through the single set_bed_playing(bool) facade, mirroring MusicDucker.set_ducked(). (The name
## avoids `set_playing` — that would shadow the native AudioStreamPlayer `playing` property's setter, which the
## engine rejects with a warning this project treats as an error.)
##
## The track, level, fades and bus are designer knobs on GameSettings.dialogue (dialogue_music /
## dialogue_music_volume_db / dialogue_music_fade_in / dialogue_music_fade_out / dialogue_music_bus).
## Leave `dialogue_music` EMPTY for the old behaviour: conversations play with no bed at all.
##
## TWO THINGS THIS IS NOT:
## • Not the MusicDucker. That fades the whole `music` BUS down so whatever is already playing (a diegetic
##   Radio) sits under the voices. This ADDS a layer. Both run for the same conversation, and because the bed
##   defaults to the `music` bus the duck applies to it too — a CONSTANT offset, since the bed only ever plays
##   while a conversation is up. Tune by ear with dialogue_music_volume_db, but know that editing
##   music_duck_amount_db shifts this bed's level as well.
## • Not the MusicDirector score. That fades the scene's Music node in for COMBAT and holds it SILENT during
##   dialogue by default (swell_for_dialogue = false), which is why this loop is normally the only music you
##   hear while talking. Turn swell_for_dialogue ON and the two play TOGETHER — pick one or the other.
##
## LIFECYCLE mirrors the ducker exactly: on at start(), off at _finish(). A conversation merely SUSPENDED
## behind a sub-menu (Trade / Heal / Level Up / Install) keeps the bed playing — the conversation still
## EXISTS (is_engaged()), the box is just hidden, and cutting the music there would stutter the scene.
## The bed RESTARTS from the top each conversation, so a short loop always opens on its downbeat.

## The "off" floor the fades run from/to. Effectively inaudible; the bed is stop()ed once a fade-out lands,
## so nothing is left spinning between conversations.
const SILENT_DB: float = -60.0

var _bed_playing: bool = false  ## guards against a re-trigger restarting the loop mid-conversation, and stops the `finished` restart backstop from firing during/after the fade-out
var _fade: Tween

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
func _looping_copy(authored: AudioStream) -> AudioStream:
	if authored == null or _stream_loops(authored):
		return authored
	var copy: AudioStream = authored.duplicate() as AudioStream
	# Same two shapes the probe reads: the WAV's loop_mode enum, or the .mp3/.ogg `loop` bool.
	if copy.get(&"loop_mode") != null:
		copy.set(&"loop_mode", AudioStreamWAV.LOOP_FORWARD)
		# The RANGE matters as much as the flag. A .wav imported with Loop Mode Disabled carries
		# loop_begin = loop_end = 0, and LOOP_FORWARD over a zero-length region plays SILENCE, not a loop —
		# so give it the whole sample. loop_end is in frames: seconds * mix_rate (get_length() already
		# accounts for the compressed format, so this is exact for QOA/IMA-ADPCM as well as raw PCM).
		if int(copy.get(&"loop_end")) <= int(copy.get(&"loop_begin")):
			copy.set(&"loop_begin", 0)
			copy.set(&"loop_end", int(copy.get_length() * float(copy.get(&"mix_rate"))))
	elif copy.get(&"loop") != null:
		copy.set(&"loop", true)
	if not _stream_loops(copy):
		# An unrecognised stream shape — fall back to the `finished` restart backstop and say so, since that
		# repeat has an audible gap at the join.
		push_warning("DialogueMusicBed: could not force '%s' (%s) to loop — falling back to a restart-on-finish repeat, which seams audibly." % [authored.resource_path, authored.get_class()])
		return authored
	return copy

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
		# volume currently sits, so it slides back up rather than popping).
		play()
	var target: float = cfg.dialogue_music_volume_db if play_bed else SILENT_DB
	var time: float = cfg.dialogue_music_fade_in if play_bed else cfg.dialogue_music_fade_out
	if _fade and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, ^"volume_db", target, maxf(time, 0.0))
	if not play_bed:
		# Stop only once the fade-out has actually landed — stopping up front would cut the tail dead.
		# Guarded on _bed_playing so a conversation that re-opens DURING the fade-out isn't silenced by
		# this stale callback (set_bed_playing(true) flipped the flag back before the tween finished).
		_fade.finished.connect(_stop_if_still_idle)

func _stop_if_still_idle() -> void:
	if not _bed_playing:
		stop()

## `finished` fires only for a stream that ISN'T set to loop (see _ready) — restart it so the bed covers a
## conversation longer than the track. Gated on _bed_playing so it can't resurrect the bed after the
## conversation ended (a short track finishing during the fade-out would otherwise start it up again).
func _on_finished() -> void:
	if _bed_playing:
		play()

## True when the stream is authored to loop seamlessly. Duck-typed rather than branched on class, because the
## loop flag lives under a different name per stream type (AudioStreamWAV.loop_mode enum vs the .mp3/.ogg
## `loop` bool) and a designer may drop in any of them. An unknown stream type reports true, so we warn only
## when we're actually sure it won't loop.
func _stream_loops(s: AudioStream) -> bool:
	var loop_mode: Variant = s.get(&"loop_mode")  # AudioStreamWAV: 0 = Disabled
	if loop_mode != null:
		# The flag ALONE is not enough: a WAV also needs a non-degenerate range. LOOP_FORWARD with
		# loop_begin == loop_end (what a Loop-Mode-Disabled import leaves behind: both 0) loops a
		# zero-length region, which is silence — audibly identical to a broken bed, and the exact bug
		# that shipped the first time this component was written.
		return int(loop_mode) != 0 and int(s.get(&"loop_end")) > int(s.get(&"loop_begin"))
	var loops: Variant = s.get(&"loop")  # AudioStreamMP3 / AudioStreamOggVorbis
	if loops != null:
		return bool(loops)
	return true
