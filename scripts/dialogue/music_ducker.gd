class_name MusicDucker
extends Node

## Fades the "music" audio bus down while a conversation is up and back up when it ends — the
## cinematic duck pulled out of DialogueManager. A code-built child of the manager (PROCESS_MODE_ALWAYS
## owner, so the duck tween runs through the paused world); caches its own bus in _ready. The manager
## drives it through the single set_ducked(bool) facade.

const MUSIC_DUCK_DB: float = -12.0      # how far the music bus drops while a conversation is up
const MUSIC_DUCK_TIME: float = 0.4      # fade time for the music duck / restore

var _music_bus: int = -1
var _music_prior_db: float = 0.0
var _music_ducked: bool = false  ## guards _music_prior_db so a rapid re-trigger can't cache the already-ducked level as the baseline
var _music_tween: Tween

func _ready() -> void:
	_music_bus = AudioServer.get_bus_index("music")

## Fade the music bus down (true) while a conversation is up, back up (false) when it ends.
func set_ducked(duck: bool) -> void:
	if _music_bus < 0:
		return
	# Capture the pre-duck level ONLY on the un-ducked -> ducked transition. A rapid re-trigger
	# (or a new conversation opening while the prior restore fade is still running) would otherwise
	# snapshot the already-ducked level as the baseline, leaving the music permanently quieter.
	if duck:
		if not _music_ducked:
			_music_prior_db = AudioServer.get_bus_volume_db(_music_bus)
			_music_ducked = true
	else:
		if not _music_ducked:
			return
		_music_ducked = false
	var target: float = _music_prior_db + MUSIC_DUCK_DB if duck else _music_prior_db
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_method(_set_music_db, AudioServer.get_bus_volume_db(_music_bus), target, MUSIC_DUCK_TIME)

func _set_music_db(db: float) -> void:
	AudioServer.set_bus_volume_db(_music_bus, db)
