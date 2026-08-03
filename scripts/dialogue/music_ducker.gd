class_name MusicDucker
extends Node

## Fades the "music" audio bus down while a conversation is up and back up when it ends — the
## cinematic duck pulled out of DialogueManager. A code-built child of the manager (PROCESS_MODE_ALWAYS
## owner, so the duck tween runs through the paused world); caches its own bus in _ready. The manager
## drives it through the single set_ducked(bool) facade.

# The duck depth (dB) + fade time are designer knobs on GameSettings.dialogue
# (music_duck_amount_db / music_duck_fade_duration).

const MUSIC_BUS: StringName = &"music"

var _music_bus: int = -1
var _music_prior_db: float = 0.0
var _music_ducked: bool = false  ## guards the duck so a rapid re-trigger can't re-enter the transition
var _music_tween: Tween

func _ready() -> void:
	_music_bus = AudioServer.get_bus_index(MUSIC_BUS)

## Fade the music bus down (true) while a conversation is up, back up (false) when it ends.
func set_ducked(duck: bool) -> void:
	if _music_bus < 0:
		return
	# Stand down while the death cinematic owns the music bus — the exact twin of the guard in
	# ScopeCoordinator._duck_music_for_scope, and for the same reason: DeathMix re-asserts that bus every
	# frame, the player is alive and free to start a conversation during the revive swell, and two owners
	# writing absolute dB to one bus fight per-frame into an audible slam. Returning BEFORE the latch means
	# the conversation simply runs un-ducked for that window rather than leaving a duck armed with no restore.
	if DeathMix.owns_bus(MUSIC_BUS):
		return
	# The restore target is derived from Settings (authored base + the player's slider — the exact value
	# apply_audio writes), NEVER sampled from the live bus. Sampling the live bus is how a duck taken while
	# ANOTHER duck is up — the ADS duck (ScopeCoordinator), or the death cinematic's world duck cross-fading
	# back up over spawn_fade_in_time while the player is already alive and talking — bakes a transient level
	# in as "normal" and ratchets the music permanently quieter. Still latched on the un-ducked -> ducked
	# transition so a re-trigger can't restart the fade from a ducked position.
	# ACCEPTED TRADE-OFF: overlapping ducks no longer STACK (the last one to end restores to full rather than
	# to the other duck's level). That is strictly better than a ratchet that never recovers.
	if duck:
		if not _music_ducked:
			_music_prior_db = Settings.current_bus_db(MUSIC_BUS)
			_music_ducked = true
	else:
		if not _music_ducked:
			return
		_music_ducked = false
	var target: float = _music_prior_db + GameSettings.dialogue.music_duck_amount_db if duck else _music_prior_db
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_method(_set_music_db, AudioServer.get_bus_volume_db(_music_bus), target, GameSettings.dialogue.music_duck_fade_duration)

func _set_music_db(db: float) -> void:
	AudioServer.set_bus_volume_db(_music_bus, db)

## Hard-restore the music bus and drop the duck latch, with NO fade. The exact twin of
## ScopeCoordinator.reset(), and called from the same place for the same reason: Player.die() aborts any live
## conversation, and the abort's normal 0.4 s restore FADE would still be writing the music bus while the
## death cinematic's world duck (DeathMix) is writing it every frame — two owners fighting over the first
## quarter-second of the death. Settling it instantly hands the bus to the cinematic cleanly.
func reset() -> void:
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	if _music_ducked and _music_bus >= 0:
		AudioServer.set_bus_volume_db(_music_bus, Settings.current_bus_db(MUSIC_BUS))
	_music_ducked = false
