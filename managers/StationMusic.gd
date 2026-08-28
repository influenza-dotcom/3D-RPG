extends AudioStreamPlayer

## @system Audio
## @seam POLLS InputManager.any_station_music_open() every frame — deliberately NOT the screens' opened/closed signals, which fire on REFUSE paths too and therefore cannot be refcounted. A poll asks the CURRENT truth, so it self-heals across a refused open, the death sweep, a quickload and a level swap with no repair code, and it touches ZERO screen files.
## @seam is_bed_wanted() is the public tier flag: MusicDirector stands the combat score down for it (yield_to_station_music) and DialogueMusicBed steps aside for it (note_menu_music), exactly as both already do for a diegetic Radio.
## @seam is_screen_open() is the TIGHTER twin (no hold window): the conversation music duck stands down for it (DialogueManager.note_station_screen -> MusicDucker.note_station_radio), so a dialogue-hosted shop sounds identical to the same kiosk opened standing up.
## @risk PROCESS_MODE_ALWAYS is load-bearing: a station screen opened from a CONVERSATION opens under DialogueManager's tree pause, and a pausable AudioStreamPlayer silences itself ~15 ms in with nothing logged (the trap documented on StationSpeaker).
## @test res://tests/test_station_music.gd
##
## THE MACHINE'S OWN RADIO. While a self-serve terminal's screen is awake — shop counter, ATM, clinic kiosk,
## trainer, respec, chip bench, chess table — one looping shop theme plays out of the same forty-cent panel
## speaker that just chirped at you. It is a single 2D AudioStreamPlayer on the `station_music` bus, which
## clones the StationSpeaker chirp's filter chain parameter-for-parameter (⭐THE BUS *IS* THE TINNY SOUND —
## see scripts/components/station_speaker.gd) but sends into `music` so the Options MUSIC slider governs it.
##
## WHICH SCREENS: the `station_music = true` rows of InputManager's modal registry, which are exactly the
## seven screens that answer with a StationSpeaker.chirp() at their commit point. That identity is the design
## rule, not a coincidence — the bed plays through a clone of that speaker's cone, so the music is coming out
## of the thing that just chirped. The Pip-Boy tabs, Loot, Wait and Options are deliberately OUT: the player's
## own device, a corpse, a rooftop, and the volume sliders themselves.
##
## POLLED, NOT HOOKED, and that is the robustness core. `closed` fires on the REFUSE path for every station
## screen (so a dialogue-hosted open that suspended the conversation on that one-shot is never stranded) while
## `opened` fires only on success — so any refcount decrements without ever incrementing. Polling has no such
## accounting to get wrong.
##
## IT NEVER WRITES A BUS. The `music` bus has a single-owner protocol (DeathMix owns it during the death
## cinematic; MusicDucker and the ADS duck honour that), and a fourth claimant would break it. This node only
## ever moves its OWN volume_db — exactly like MusicDirector and DialogueMusicBed — so it stacks cleanly with
## every bus writer in the game. It does ASK the conversation duck to stand down while a screen is up
## (is_screen_open, below) — a request through MusicDucker's own facade, not a second hand on the fader.
##
## TUNING: GameSettings.station_music (resources/tuning/StationMusicSettings.tres) — playlist, level, fades,
## the station-to-station hold window, and the bus. An empty playlist makes the whole layer inert.

var _rng := RandomNumberGenerator.new()  ## its OWN generator, never the global one, so a shop visit can't perturb a gameplay roll
var _last_index: int = -1                ## index into cfg.tracks of what played last; deliberately NOT reset by anything, so "never twice in a row" spans separate visits, level changes and deaths
var _hold_t: float = 0.0                 ## the grace window after the last terminal closes — see StationMusicSettings.hold_seconds
var _wanted: bool = false                ## the tier flag other music layers read (is_bed_wanted); TRUE THROUGH THE HOLD WINDOW
var _screen_open: bool = false           ## a station screen is up RIGHT NOW *and* this layer can sound — the tighter flag the conversation DUCK stands down for (is_screen_open); false the instant the screen closes, hold window or not


func _ready() -> void:
	# See the @risk above — a dialogue-hosted station opens under the conversation's pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	autoplay = false
	volume_db = GameSettings.station_music.silent_db
	_rng.randomize()
	# Nothing plays from _ready. Boot silence is held by discipline here, the way the menu audio pool does it:
	# the first sound this node ever makes is a terminal opening.


func _process(delta: float) -> void:
	# Read the tuning group LIVE every frame, never cached in _ready: the CYBER SUNDAY Tuning dock retunes at
	# runtime, and a cached copy is the house "consumers must read live" trap.
	var cfg: StationMusicSettings = GameSettings.station_music
	# Engine.time_scale scales the _process delta, so the death cinematic's slow-mo would stretch a 1.2 s fade
	# into real seconds. Divide it back out — the move_toward equivalent of the death mix's
	# create_tween().set_ignore_time_scale(true). maxf() guards FreezeFrame's near-zero hit-stop; the fade
	# simply pauses for those ~50 ms, which is deliberate (you cannot take a hit with a station screen up),
	# not a divide-by-zero to "fix".
	var real: float = delta / maxf(Engine.time_scale, 0.001)
	var open_now: bool = cfg.enabled and InputManager.any_station_music_open()
	_hold_t = cfg.hold_seconds if open_now else maxf(0.0, _hold_t - real)
	# An UNAUTHORED playlist raises no tier flag at all, so MusicDirector and the dialogue bed behave EXACTLY
	# as they did before this node existed rather than standing down for a bed that will never be audible.
	var in_play: bool = open_now or _hold_t > 0.0
	# `and` SHORT-CIRCUITS, and that is load-bearing, not incidental: _playable_indices() allocates an Array
	# per call and this _process ticks forever — through the main menu, every level, every firefight. Keeping
	# the scan behind `in_play` means it only runs on the frames a terminal is actually in play.
	var audible: bool = in_play and not _playable_indices(cfg).is_empty()
	_wanted = audible
	_screen_open = audible and open_now
	# Asserted every frame rather than on the edge: the far side latches, so the call is idempotent and cheap,
	# and there is no ordering hazard between this poll and a conversation starting or ending.
	# TWO flags, because the two dialogue-side layers want different truths and collapsing them is a bug:
	#  • the BED reads _wanted — true through the hold window, so it doesn't stutter back in over the tail.
	#  • the conversation DUCK reads _screen_open — false the instant the screen closes, so the resumed line
	#    doesn't land over three seconds of full-level shop music. See MusicDucker.note_station_radio.
	DialogueManager.note_menu_music(_wanted)
	DialogueManager.note_station_screen(_screen_open)
	_route(cfg)
	# RISING EDGE, two cases — and the split IS the "close it and instantly re-open it" answer:
	#  • still playing (the hold window or the fade-out hasn't landed yet) -> do NOT restart and do NOT
	#    re-pick. The level simply reverses and swells back, so the same tune continues instead of stuttering
	#    onto its downbeat. This is also what makes shop -> ATM next door read as one visit.
	#  • stopped -> pick a fresh track and play() from 0. These are short shop loops with a real downbeat;
	#    joining one mid-track is the in-world RADIO's fiction, not a shop's.
	if _wanted and not playing:
		var s: AudioStream = _pick_stream(cfg)
		if s == null:
			return
		stream = s
		play()
	if not playing:
		return
	# MusicDirector's exact fade math, for the same reason: the step is normalised over the whole
	# silent -> audible span and the DIRECTION picks the time, so a rise and a fall never run at each other's
	# rate no matter how the two knobs are retuned.
	var target: float = cfg.volume_db if _wanted else cfg.silent_db
	var span: float = maxf(absf(cfg.volume_db - cfg.silent_db), 0.001)
	var time: float = cfg.fade_in if target > volume_db else cfg.fade_out
	volume_db = move_toward(volume_db, target, span / maxf(time, 0.001) * real)
	if not _wanted and volume_db <= cfg.silent_db + 0.01:
		stop()                        # only once the fade-out has LANDED — stopping up front cuts the tail dead
		volume_db = cfg.silent_db


## True while a station terminal's radio is audible or about to be. THE public seam: MusicDirector reads it to
## stand the dynamic combat score down, DialogueMusicBed steps aside for it, and the debug readout prints it.
## Reads the WANTED flag rather than this node's volume so the two fades run CONCURRENTLY — the handover is a
## real crossfade in both directions instead of a gap.
func is_bed_wanted() -> bool:
	return _wanted


## True while a station terminal's screen is open RIGHT NOW *and* this layer can actually sound. The TIGHTER
## twin of is_bed_wanted(): it drops the moment the screen closes, where is_bed_wanted() rides the
## hold_seconds grace window out. The conversation MUSIC DUCK reads THIS one
## (DialogueManager.note_station_screen -> MusicDucker.note_station_radio) so a dialogue-hosted shop plays at
## the same level as the identical kiosk two metres away, while the duck re-arms the instant the box comes
## back rather than three seconds later. Also what the `stationmusic` console readout prints beside the tier flag.
func is_screen_open() -> bool:
	return _screen_open


## Debug readout only (the `stationmusic` console command). Blank when nothing has ever played.
func current_track_name() -> String:
	return stream.resource_path.get_file() if stream != null else ""


## Point the player at the configured bus if it exists, else `music` — NOT `sfx`, and never Master. Re-resolved
## per poll so a live retune lands, and the warning only fires on the frame the routing actually changes.
## Falling back to `sfx` would silently re-file a music bed under the Effects slider; falling back to Master
## would escape every volume slider AND the death-cinematic world duck.
func _route(cfg: StationMusicSettings) -> void:
	var routed: StringName = cfg.bus if AudioServer.get_bus_index(cfg.bus) >= 0 else &"music"
	if bus != routed:
		if routed != cfg.bus:
			push_warning("StationMusic: audio bus '%s' does not exist — falling back to 'music'." % cfg.bus)
		bus = routed


## The indices of the non-null playlist slots. A designer clearing ONE slot must not make the bed play
## silence, and an empty (or all-null) playlist must make the layer inert rather than error.
func _playable_indices(cfg: StationMusicSettings) -> Array[int]:
	var live: Array[int] = []
	for i in cfg.tracks.size():
		if cfg.tracks[i] != null:
			live.append(i)
	return live


## One authored track, guaranteed to loop, never the one that played last. `live.find(_last_index)` returning
## -1 — a track edited out of the playlist under us — is exactly the case pick_next_index treats as a fair pick.
func _pick_stream(cfg: StationMusicSettings) -> AudioStream:
	var live: Array[int] = _playable_indices(cfg)
	if live.is_empty():
		return null
	var slot: int = pick_next_index(live.size(), live.find(_last_index), _rng.randf())
	_last_index = live[slot]
	return LoopableStream.looping_copy(cfg.tracks[_last_index], "StationMusic")


## Kept under its own name as a one-line delegation to the pure picker's real home
## (scripts/components/music_playlist.gd), which the wandering bed also calls — one copy of the rule, and
## test_station_music.gd's proofs against this surface still hold. See MusicPlaylist.pick_next_index.
static func pick_next_index(count: int, last: int, roll: float) -> int:
	return MusicPlaylist.pick_next_index(count, last, roll)
