class_name MusicDucker
extends Node

## Fades the "music" audio bus down while a conversation is up and back up when it ends — the
## cinematic duck pulled out of DialogueManager. A code-built child of the manager (PROCESS_MODE_ALWAYS
## owner, so the duck tween runs through the paused world); caches its own bus in _ready. The manager
## drives it through TWO facades that COMPOSE:
##   • set_ducked(bool)          — a conversation is up / has ended (start() and _finish()).
##   • note_station_radio(bool)  — a STATION TERMINAL's screen is up right now and its own tinny radio is
##                                 audible (forwarded from the StationMusic autoload's per-frame poll).
## The duck is armed only while `talking AND NOT station radio`, because the duck's whole premise — a VOICE
## is being delivered and music must sit under it — is false while a dialogue-hosted Trade / Heal / Level Up /
## Install / Chess / Bank screen is up: that conversation is SUSPENDED (the box is hidden, nobody is speaking),
## and the only thing left on the music bus is the machine's own shop radio. Ducking it there made a
## person-vendor's shop play 12 dB quieter than the identical kiosk two metres away — the "person-vendor sounds
## exactly like a kiosk" rule that DialogueMusicBed.note_menu_music already enforces on the other music layer.
## The release is a real fade in both directions, and it re-arms the instant the screen CLOSES (not when
## StationMusic's hold window expires), so the resumed conversation's first line lands over ducked music.

# The duck depth (dB) + fade time are designer knobs on GameSettings.dialogue
# (music_duck_amount_db / music_duck_fade_duration).

const MUSIC_BUS: StringName = &"music"

var _music_bus: int = -1
var _music_prior_db: float = 0.0
var _music_ducked: bool = false  ## guards the duck so a rapid re-trigger can't re-enter the transition
var _music_tween: Tween
var _talking: bool = false        ## a conversation EXISTS (including one suspended behind a sub-menu) — set by set_ducked
var _station_radio: bool = false  ## a station terminal's screen is up and its radio is audible — set by note_station_radio

func _ready() -> void:
	_music_bus = AudioServer.get_bus_index(MUSIC_BUS)

## Fade the music bus down (true) while a conversation is up, back up (false) when it ends. One of the two
## composed inputs — see the class doc; a station terminal's radio overrides it while that screen is up.
func set_ducked(duck: bool) -> void:
	_talking = duck
	_apply()

## A station terminal's screen is open RIGHT NOW and this layer can actually sound (true), or it is not
## (false) — forwarded from StationMusic's per-frame poll via DialogueManager.note_station_screen(). While
## true the conversation duck stands down entirely: nobody is speaking behind a station screen, and the
## machine's radio must play at the same level it plays at on a bare kiosk.
##
## Deliberately NOT StationMusic's `is_bed_wanted()` tier flag, which stays true through the hold_seconds
## station-to-station grace window: the duck must re-arm the moment the screen closes and the box comes back,
## or the first resumed line would land over three seconds of full-level shop music. (The bed's OWN handover
## does read the hold flag — it must not stutter back in over the tail. The two signals differ on purpose.)
##
## Asserted every frame rather than pulsed on the edge, exactly like the bed's note_menu_music: _set_duck()
## below is idempotent, so a per-frame assert costs two bool compares and has no ordering hazard against a
## conversation starting or ending.
func note_station_radio(playing: bool) -> void:
	_station_radio = playing
	_apply()

func _apply() -> void:
	_set_duck(wants_duck(_talking, _station_radio))

## Is the duck ARMED right now? The debug readout's seam (via DialogueManager.is_music_ducked) — it reads the
## real latch rather than re-deriving it from the two inputs, which is the whole point: a readout that recomputes
## the answer it is meant to be checking cannot catch the case where the latch and the inputs have diverged.
func is_ducked() -> bool:
	return _music_ducked

## The composition rule, pulled out PURE so a test can pin it with no audio device, no autoloads and no tree —
## the radio.gd `_dialogue_suppresses` idiom. Armed only while a conversation exists AND no station terminal is
## playing its own radio over it; see the class doc for why the second term exists.
static func wants_duck(talking: bool, station_radio: bool) -> bool:
	return talking and not station_radio

func _set_duck(duck: bool) -> void:
	if _music_bus < 0:
		return
	# IDEMPOTENCE, and it is load-bearing now that note_station_radio asserts every frame: without this a
	# per-frame "still ducked" would kill and rebuild the tween each tick, so the fade would restart from its
	# current level every frame and crawl toward the target instead of landing in music_duck_fade_duration.
	if duck == _music_ducked:
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
	# in as "normal" and ratchets the music permanently quieter.
	# ACCEPTED TRADE-OFF: overlapping ducks no longer STACK (the last one to end restores to full rather than
	# to the other duck's level). That is strictly better than a ratchet that never recovers.
	if duck:
		_music_prior_db = Settings.current_bus_db(MUSIC_BUS)
	_music_ducked = duck
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
## death cinematic's world duck (DeathMix) is writing it every frame. Settling it instantly hands the bus to
## the cinematic cleanly.
## ⭐It clears the two COMPOSED INPUTS as well as the latch, not just the latch: StationMusic keeps asserting
## note_station_radio() every frame straight through the death cinematic, so a `_talking` left armed here
## would re-duck the bus the moment that assert flipped — which is precisely the second owner this reset
## exists to remove.
func reset() -> void:
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	if _music_ducked and _music_bus >= 0:
		AudioServer.set_bus_volume_db(_music_bus, Settings.current_bus_db(MUSIC_BUS))
	_music_ducked = false
	_talking = false
	_station_radio = false
