class_name Radio
extends LookAtInteractable

## Drop-in in-world RADIO. Aim + Interact toggles it on/off; while on it DUCKS OUT during combat (and dialogue),
## breathing back in after a short settle once the fight ends. Combat is detected with the same poll/linger as
## MusicDirector (any "npc" hunting), and like MusicDirector this node runs PROCESS_MODE_ALWAYS so the duck
## keeps moving through a pausing menu instead of freezing.
##
## SOURCE: if the player has linked their Spotify (Premium) and set playlist_uri, interacting plays that
## playlist on their OWN account and the combat duck routes through SpotifyController.pause()/resume()
## (edge-triggered). Otherwise it plays the shipped fallback_audio out of a child AudioStreamPlayer3D — the ONLY
## spatial, in-engine audio. Only the OWNING radio drives Spotify (SpotifyController's owner token); it stops the
## external playback on turn-off / scene-exit / a play failure, cleanly falling back to the local track.
##
## SETUP: drop it under a radio prop (or set highlight_target), size its CollisionShape3D to the body you aim
## at, set fallback_audio (a shipped, royalty-free track), and name it.

@export_group("Radio")
## Hover/label name; blank -> "radio".
@export var radio_name: String = ""
## The shipped, royalty-free track this radio plays when Spotify isn't the source (not linked / not Premium / offline). Null -> silent.
@export var fallback_audio: AudioStream
## The spatial player the fallback comes out of. Leave unset to auto-create a child AudioStreamPlayer3D on the music bus.
@export var audio_player: AudioStreamPlayer3D
## The designer's chosen Spotify playlist (spotify:playlist:...). Played on the player's OWN account when they've linked Spotify (Premium); else the fallback.
@export var playlist_uri: String = ""
## Pause the linked Spotify when the listener walks this far (m) from the radio, so it isn't left playing across the
## map. 0 = never. Spotify-only — the local fallback is a real 3D source and attenuates on its own.
@export var walk_away_pause_range: float = 25.0

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
## The on/audible volume (dB) for the fallback player.
@export var fallback_volume_db: float = 0.0

var _state := RadioPlaybackState.new()
var _poll_t: float = 0.0
var _combat_now: bool = false
var _using_spotify: bool = false    ## true while THIS radio drives the linked Spotify (vs the local fallback)
var _spotify_started: bool = false  ## has play_playlist(uri) been issued yet (vs a resume after a combat duck)?
var _listener: Node3D = null        ## the player who turned it on — measured for the walk-away pause
var _away_latched: bool = false     ## walk-away hysteresis: latched once out of range, until well back inside
var _spotify_want_play: bool = false  ## the duck state wants Spotify audible (tracked from its edges)
var _spotify_is_playing: bool = false ## we've issued play/resume and not since paused (so pause/resume each fire once)

func _ready() -> void:
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
	audio_player.stream = fallback_audio
	_state.configure(fallback_volume_db, silent_db, fade_pause_time, fade_resume_time, settle_cooldown)
	audio_player.volume_db = silent_db
	# A Spotify failure (not Premium / no active device / offline) falls THIS radio back to its shipped track.
	if not SpotifyController.playback_error.is_connected(_on_spotify_error):
		SpotifyController.playback_error.connect(_on_spotify_error)

func _process(delta: float) -> void:
	# Combat scan on an interval (mirrors music_director.gd:54-79), then drive the duck/settle brain.
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = poll_interval
		_combat_now = _any_npc_fighting()
	var dialogue_active: bool = DialogueManager.is_active()
	# Walk-away pauses the linked Spotify (so it's not left playing across the map); the local fallback is 3D and
	# attenuates on its own. Combat / dialogue duck through the same state.
	var away: bool = _using_spotify and walk_away_pause_range > 0.0 and _too_far()
	_state.tick(delta, _combat_now, dialogue_active, away)
	if _using_spotify:
		# Track what the duck state WANTS (audible vs ducked) from its edges, then act once per change below.
		var edge := _state.external_edge()
		if edge > 0:
			_spotify_want_play = true
		elif edge < 0:
			_spotify_want_play = false
		# Start/resume Spotify only once the game's COMBAT MUSIC has fully cleared, so the player's track and the
		# combat swell never overlap (the post-combat fade-out tail used to bleed over the resumed Spotify). Pause
		# is immediate. play_playlist starts it the first time; resume() continues where the duck paused.
		if _spotify_want_play and not _spotify_is_playing:
			if not _game_music_audible():
				if _spotify_started:
					SpotifyController.resume()
				else:
					SpotifyController.play_playlist(playlist_uri)
					_spotify_started = true
				_spotify_is_playing = true
		elif not _spotify_want_play and _spotify_is_playing:
			SpotifyController.pause()
			_spotify_is_playing = false
	elif audio_player != null:
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

## True once the listener (who turned the radio on) has walked beyond walk_away_pause_range — with a hysteresis
## band (must come back within 85% to un-latch) so hovering at the edge doesn't flap pause/resume.
func _too_far() -> bool:
	if not is_instance_valid(_listener):
		_away_latched = false
		return false
	var d := global_position.distance_to(_listener.global_position)
	if _away_latched:
		_away_latched = d > walk_away_pause_range * 0.85
	else:
		_away_latched = d > walk_away_pause_range
	return _away_latched

## True while the game's own dynamic music (MusicDirector — the combat swell) is currently audible. The radio
## holds Spotify's start/resume until this clears, so the player's track and the combat music never overlap.
func _game_music_audible() -> bool:
	for m in get_tree().get_nodes_in_group(&"music_director"):
		if m.has_method(&"is_audible") and m.is_audible():
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
	_state.set_playing(true)
	_listener = player as Node3D  # measured for the walk-away pause
	_using_spotify = false
	_spotify_started = false
	_spotify_want_play = false
	_spotify_is_playing = false
	# Prefer the player's linked Spotify (a designer playlist on their OWN account); else the shipped fallback.
	# When Spotify is chosen, _process starts/ducks it via the edge system (so a turn-on mid-combat waits for calm).
	if not playlist_uri.is_empty() and SpotifyController.can_use_spotify() and SpotifyController.acquire(self):
		_using_spotify = true
	else:
		_play_fallback()
	_toast(player, "on")

func _turn_off(player: Node) -> void:
	_state.set_playing(false)  # _process stops the fallback stream once it's faded to silent
	if _using_spotify:
		SpotifyController.stop()  # pause external playback + release the owner token
		_using_spotify = false
		_spotify_started = false
		_spotify_want_play = false
		_spotify_is_playing = false
	_toast(player, "off")

## Start the local fallback track (the source whenever Spotify isn't linked/available).
func _play_fallback() -> void:
	if audio_player != null and audio_player.stream != null and not audio_player.playing:
		audio_player.play()

## A Spotify command failed (not Premium / no device / offline). If WE were driving it and are still switched
## on, drop the link and fall back to the shipped track. Fires for every radio, but only the OWNER is _using_spotify.
func _on_spotify_error(message: String) -> void:
	if _using_spotify and _state.is_playing():
		_using_spotify = false
		_spotify_started = false
		_spotify_want_play = false
		_spotify_is_playing = false
		SpotifyController.release(self)
		_play_fallback()
		# Surface WHY Spotify dropped (Premium / no device / offline / 4xx) — a silent fall-back to the local
		# track was un-diagnosable. Toast the listener who turned us on.
		if is_instance_valid(_listener) and _listener.has_method(&"notify_toast"):
			_listener.notify_toast("Spotify: %s" % message, Color(1.0, 0.5, 0.4))

## Scene change / death / freed: stop the external playback we started so the account isn't left playing.
func _exit_tree() -> void:
	# Disconnect FIRST so an in-flight playback_error can't invoke _on_spotify_error on this tearing-down node.
	if SpotifyController.playback_error.is_connected(_on_spotify_error):
		SpotifyController.playback_error.disconnect(_on_spotify_error)
	if _using_spotify and SpotifyController.owns(self):
		SpotifyController.stop()
		_using_spotify = false
		_spotify_started = false
		_spotify_want_play = false
		_spotify_is_playing = false

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
