@tool
class_name Radio
extends LookAtInteractable

## Drop-in in-world RADIO. Aim + Interact toggles it on/off; while on it DUCKS OUT during combat (and dialogue),
## breathing back in after a short settle once the fight ends. Combat is detected with the same poll/linger as
## MusicDirector (any "npc" hunting), and like MusicDirector this node runs PROCESS_MODE_ALWAYS so the duck
## keeps moving through a pausing menu instead of freezing.
##
## SOURCE: cycles a FOLDER of tracks (`music_folder`) through a child AudioStreamPlayer3D on the music bus —
## spatial, in-engine, diegetic, classic-radio style: auto-advances on track end and loops the folder (optional
## per-radio shuffle). An empty/unset folder falls back to a single shipped `fallback_audio` track. (A later
## Options setting lets the player point ALL radios at their OWN folder, overriding music_folder.)
## The radio joins the &"music" group while on, so nearby NPCs notice + react (gated by GameSettings.npc_ai.music_reactions).
##
## SETUP: drop it under a radio prop (or set highlight_target), size its CollisionShape3D to the body you aim
## at, point music_folder at a folder of tracks (or set fallback_audio for a single track), and name it.

@export_group("Radio")
## Hover/label name; blank -> "radio".
@export var radio_name: String = ""
## Folder of audio tracks (mp3/ogg/wav) this radio cycles through — auto-advance + loop, classic-radio style.
## Default: the shipped music folder. Empty / no audio files inside -> the single `fallback_audio` track instead.
## (A later Options setting lets the player override this with their OWN folder, for all radios.)
@export_dir var music_folder: String = "res://assets/audio/music":
	set(value):
		music_folder = value
		update_configuration_warnings()
## true -> play the folder in a per-radio-deterministic shuffled order; false -> on-disk (alphabetical) order.
@export var shuffle: bool = false
## A single shipped, royalty-free track, used when `music_folder` has no audio files. Null + empty folder -> silent.
@export var fallback_audio: AudioStream:
	set(value):
		fallback_audio = value
		update_configuration_warnings()
## The spatial player the audio comes out of. Leave unset to auto-create a child AudioStreamPlayer3D on the music bus.
@export var audio_player: AudioStreamPlayer3D

@export_group("Combat duck")
## false -> duck through the whole hunt (matches the music system); true -> only duck in an active firefight.
@export var combat_strict: bool = false
## Seconds between combat scans of the "npc" group (a per-frame scan would be waste).
@export var poll_interval: float = 0.3
## Seconds the radio stays ducked after the last enemy disengages, so it doesn't flap at a fight's ragged edge.
@export var settle_cooldown: float = 3.0
## Seconds to duck OUT when combat hits (fast).
@export var fade_pause_time: float = 0.4
## Seconds to ease back IN once the coast clears.
@export var fade_resume_time: float = 1.2
## The ducked/off floor (dB) — effectively inaudible while the stream still plays underneath.
@export var silent_db: float = -60.0
## The on/audible volume (dB) for the player.
@export var fallback_volume_db: float = 0.0

@export_group("Click SFX")
## Played once when the radio is switched ON (a physical click / clunk). Null -> silent.
@export var click_on: AudioStream
## Played once when switched OFF. Null -> silent (a designer may reuse click_on for both).
@export var click_off: AudioStream
## Volume (dB) of the on/off click.
@export var click_volume_db: float = 0.0
## The player the click comes out of. Leave unset to auto-create a child AudioStreamPlayer3D on the SFX bus, so the combat music-duck never touches it.
@export var click_player: AudioStreamPlayer3D

@export_group("Music reactions")
## How far (m) a nearby NPC can "hear" this radio and react (turn to face it + comment by quality). Only matters
## when GameSettings.npc_ai.music_reactions is on; otherwise a playing radio is inert to NPCs.
@export var audible_radius: float = 12.0

var _state := RadioPlaybackState.new()
var _playlist := MusicPlaylist.new()
var _poll_t: float = 0.0
var _combat_now: bool = false

## Editor warning: a radio with neither a folder of tracks NOR a fallback track is silent. Surface it at edit time.
func _get_configuration_warnings() -> PackedStringArray:
	if fallback_audio == null and _scan_audio_folder(music_folder).is_empty():
		return PackedStringArray([
			"No tracks — `music_folder` has no audio files and `fallback_audio` is unset, so this radio is silent. "
			+ "Point `music_folder` at a folder of mp3/ogg/wav tracks, or assign a royalty-free `fallback_audio`.",
		])
	return PackedStringArray()

func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_fit_hitbox()  # preview the auto-fit hitbox in-editor (resizes an existing collider; safe)
		return  # @tool: only _get_configuration_warnings runs in-editor; the audio/outline setup is runtime-only
	# Look-at hitbox on the talk layer (like the other interactables) + the hover outline.
	collision_layer = TalkHelpers.TALK_LAYER
	collision_mask = 0
	_build_outline()
	if auto_fit_collider:
		_fit_hitbox_to_host()
	# Keep ducking through a pausing menu / dialogue tree-pause, exactly like MusicDirector (music_director.gd:35).
	process_mode = Node.PROCESS_MODE_ALWAYS
	if audio_player == null:
		audio_player = AudioStreamPlayer3D.new()
		audio_player.bus = &"music"
		add_child(audio_player)
	# A SEPARATE, non-looping player for the on/off click on the SFX bus (the music player loops the track and is
	# volume-driven every frame, so a click must never share it).
	if click_player == null:
		click_player = AudioStreamPlayer3D.new()
		click_player.bus = &"sfx"
		add_child(click_player)
	# Auto-advance the playlist when a track ends (looping the folder); a lone fallback track just repeats.
	if not audio_player.finished.is_connected(_on_track_finished):
		audio_player.finished.connect(_on_track_finished)
	audio_player.stream = fallback_audio
	_state.configure(fallback_volume_db, silent_db, fade_pause_time, fade_resume_time, settle_cooldown)
	audio_player.volume_db = silent_db

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return  # @tool: _state + the autoloads (DialogueManager, ...) don't exist in-editor; the duck brain is runtime-only
	# Combat scan on an interval (mirrors music_director.gd:54-79), then drive the duck/settle brain.
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = poll_interval
		_combat_now = _any_npc_fighting()
	var dialogue_active: bool = DialogueManager.is_active()
	_state.tick(delta, _combat_now, dialogue_active, false)
	if audio_player != null:
		audio_player.volume_db = _state.current_db
		# Fully stop a switched-off radio once it's faded down, so "off" isn't a silent running stream.
		if not _state.is_playing() and _state.at_silent() and audio_player.playing:
			audio_player.stop()

## True while any NPC is fighting — hunting (ALERTED/INVESTIGATING) by default, or only an active firefight
## when combat_strict. Null-guarded for a bare off-tree instance (no tree -> no combat). Mirrors MusicDirector.
func _any_npc_fighting() -> bool:
	# is_inside_tree() FIRST — calling get_tree() while off-tree itself logs a tracked engine error (which
	# fails GUT 9.6), so guard on tree membership rather than get_tree() == null.
	if not is_inside_tree():
		return false
	for n in get_tree().get_nodes_in_group(&"npc"):
		if not (n is NPC):
			continue
		var npc := n as NPC
		var fighting: bool = npc.is_in_combat() if combat_strict else npc.is_hunting()
		if fighting:
			return true
	return false


# ---------------------------------------------------------------------------
# Behaviour (talk-handler surface)
# ---------------------------------------------------------------------------

## Interact pressed while aimed at us: toggle the radio on/off.
func start_talk(player: Node) -> void:
	if _state.is_playing():
		_turn_off(player)
	else:
		_turn_on(player)

func _turn_on(player: Node) -> void:
	_play_click(click_on)
	_state.set_playing(true)
	add_to_group(&"music")  # a playing radio NPCs can hear + react to (gated by GameSettings.npc_ai.music_reactions)
	_load_playlist()
	_play_current()
	_toast(player, "on")

func _turn_off(player: Node) -> void:
	_play_click(click_off)
	_state.set_playing(false)  # _process stops the stream once it's faded to silent
	remove_from_group(&"music")  # off -> NPCs stop hearing it
	_toast(player, "off")

## Build the playlist from the effective folder (scan -> audio paths -> seeded order). An empty/unset folder
## leaves the playlist empty, so _play_current falls back to the single `fallback_audio` track. Re-scanned on
## every turn-on so dropping new files into the folder (or the player changing Settings.music_folder) is picked up.
func _load_playlist() -> void:
	_playlist.set_tracks(_scan_audio_folder(_effective_folder()), shuffle, radio_name.hash(), true)

## The folder this radio actually scans: the player's OWN folder (Settings.music_folder) when they've set one,
## else this radio's curated `music_folder` export. Runtime-only (reads the Settings autoload, absent in-editor).
func _effective_folder() -> String:
	return _resolve_folder(Settings.music_folder, music_folder)

## Pure precedence: a non-blank player override wins, else the radio's own folder. Split out so it's unit-testable
## without the autoload.
func _resolve_folder(override_dir: String, fallback: String) -> String:
	return override_dir if not override_dir.strip_edges().is_empty() else fallback

## Start the current track: the playlist's current track if the folder has any, else the single fallback. No-op
## off-tree (audio_player is null until _ready), so a bare test instance never sounds.
func _play_current() -> void:
	if audio_player == null:
		return
	var stream := _resolve_stream()
	if stream == null:
		return
	audio_player.stream = stream
	audio_player.play()

## A track ended: while the radio is ON, roll to the next folder track (looping) — the lone fallback just
## repeats. Ignored when off (turn-off stop()s the player, and stop() doesn't emit `finished` anyway).
## We SKIP tracks that fail to decode so one bad file in the player's own folder doesn't freeze the loop
## (a non-playing player never re-emits `finished`). Bounded by size() so an all-undecodable folder gives up
## after one pass instead of spinning within a frame.
func _on_track_finished() -> void:
	if not _state.is_playing():
		return
	if not _playlist.has_tracks():
		_play_current()  # no folder -> the lone fallback just repeats
		return
	var attempts: int = _playlist.size()
	while attempts > 0:
		_playlist.advance()  # wraps back to the first past the end (loop)
		var stream := _load_stream(_playlist.current())
		if stream == null and fallback_audio != null:
			stream = fallback_audio
		if stream != null and audio_player != null:
			audio_player.stream = stream
			audio_player.play()
			return
		attempts -= 1
	# Nothing playable this whole pass: fall back if we have one (its `finished` re-tries the folder next beat).
	if fallback_audio != null:
		_play_current()

## The AudioStream to play right now: the playlist's current folder track (loaded from disk) if available, else
## the designer's single fallback_audio. A track that fails to load drops to the fallback for that beat.
func _resolve_stream() -> AudioStream:
	if _playlist.has_tracks():
		var s := _load_stream(_playlist.current())
		if s != null:
			return s
	return fallback_audio

## Load a track by path. A res:// path is an imported asset -> load() returns the ready stream. A path OUTSIDE
## res:// (the player's own folder — user:// or an OS path) has no import pipeline, so it's decoded from raw
## bytes by extension. Undecodable / unreadable -> null (that track is skipped for this beat).
func _load_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		return load(path) as AudioStream
	return _load_external_stream(path)

## Decode an audio file from outside res:// from raw bytes by extension (mp3 via AudioStreamMP3.data; ogg/wav
## via their load_from_file). Returns null for an unreadable file or an unsupported/undecodable codec.
func _load_external_stream(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null  # guard FIRST: load_from_file / get_file_as_bytes on a missing file logs a tracked engine error
	var ext := path.get_extension().to_lower()
	if ext == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	if ext == "wav":
		return AudioStreamWAV.load_from_file(path)
	if ext == "mp3":
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			return null
		var s := AudioStreamMP3.new()
		s.data = bytes
		return s
	return null

## Scan `folder` for audio files (mp3/ogg/wav), returning their full paths sorted by name. The extension
## whitelist skips Godot's `.import`/`.remap` sidecars. Returns empty for a blank/unopenable folder. NOTE: a
## res:// scan sees the SOURCE files when running from the editor (the user's workflow); the player's own
## folder (Slice C, user:// or an OS path) is always real files.
func _scan_audio_folder(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	if folder.is_empty():
		return out
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	var base := folder.trim_suffix("/")
	for f in dir.get_files():
		var ext := f.get_extension().to_lower()
		if ext == "mp3" or ext == "ogg" or ext == "wav":
			out.append(base + "/" + f)
	out.sort()
	return out

## One-shot on/off click out of the dedicated SFX-bus player (never the looping music player). No-op if unset --
## including off-tree tests, which never run _ready, so click_player stays null.
func _play_click(stream: AudioStream) -> void:
	if stream == null or click_player == null:
		return
	click_player.stream = stream
	click_player.volume_db = click_volume_db
	click_player.play()

## True while the radio is switched on -- read by the NPC music-reaction scan.
func is_playing() -> bool:
	return _state.is_playing()

## The text the song-quality scorer reads for THIS radio (the NPC music-reaction scan): the current track's
## filename when a folder playlist is active (so an NPC scores the actual SONG), else the radio name. The same
## string always scores the same, so reactions are stable per track.
func quality_text() -> String:
	if _playlist.has_tracks():
		var n := _playlist.current_name()
		if not n.is_empty():
			return n
	return radio_name

func _toast(player: Node, state_word: String) -> void:
	if player != null and player.has_method(&"notify_toast"):
		var where: String = radio_name if not radio_name.is_empty() else "Radio"
		player.notify_toast("%s %s" % [where, state_word], Color(0.5, 0.8, 1.0))

## Hover readout reflects the on/off state.
func look_name() -> String:
	var where: String = radio_name if not radio_name.is_empty() else "radio"
	return "Turn off %s" % where if _state.is_playing() else "Turn on %s" % where

## Always interactable (toggling is always allowed; a radio with no source just stays silent).
func can_be_talked_to() -> bool:
	return true
