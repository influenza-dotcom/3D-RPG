class_name WanderMusic
extends AudioStreamPlayer

## @system Audio
## @seam Reads the SHARED soundscape scan (scripts/audio/soundscape.gd) plus the two flags the other layers already publish (StationMusic.is_bed_wanted, DialogueManager.is_engaged), so this bed and MusicDirector's combat score can never disagree about whose moment it is — they are complements computed from one answer.
## @risk PROCESS_MODE_ALWAYS is load-bearing: a conversation PAUSES THE TREE, and a pausable AudioStreamPlayer silences itself ~15 ms in with nothing logged (the trap documented on StationSpeaker). This bed must FADE out of a conversation, not vanish into one.
## @test res://tests/test_wander_music.gd
##
## THE WANDERING BED — the quiet non-diegetic music that plays while you are just exploring. It is the EXACT
## COMPLEMENT of the dynamic combat score (scripts/components/music_director.gd): MusicDirector's track plays
## constantly but sits SILENT during exploration and swells for a fight, and this one does the reverse. Between
## them the score is never absent and never doubled.
##
## IT STANDS DOWN FOR FOUR THINGS, and every one of them is somebody else already owning the moment:
##   COMBAT / CAUTION  — anybody in the world is fighting or hunting. The combat score is taking this.
##   DIALOGUE          — a conversation is engaged. Talking gets DialogueMusicBed, or deliberate silence.
##   STATION MUSIC     — a terminal screen is up and the machine is playing its own tinny radio at you.
##   A DIEGETIC RADIO  — the player stands inside a playing Radio's audible_radius. Real music beats scored music.
## The first is read from the same one scan MusicDirector polls; the rest are published flags. Nothing here
## re-derives an answer another layer already computed.
##
## WHERE IT LIVES: an authored node in scenes/game.tscn under Player, beside the combat score's Music player —
## NOT an autoload. That is deliberate: an autoload would need an "am I even in the game world?" gate to keep
## itself out of the main menu, and a scene node simply does not exist there. It also dies with the scene, so
## there is no boot-silence discipline to maintain (contrast managers/StationMusic.gd, which must be an
## autoload because a station menu can be open anywhere).
##
## TUNING: GameSettings.wander_music (resources/tuning/WanderMusicSettings.tres) — playlist, level, fades, the
## rest window between plays, and the bus. An EMPTY playlist makes the whole layer inert.
##
## IT NEVER WRITES A BUS. The `music` bus has a single-owner protocol (DeathMix owns it during the death
## cinematic; MusicDucker and the ADS duck honour that). This node only ever moves its OWN volume_db — exactly
## like MusicDirector, DialogueMusicBed and StationMusic — so it stacks cleanly with every bus writer, and the
## death cinematic's world duck reaches it for free.

## Seconds between soundscape polls. Matched to MusicDirector.POLL_INTERVAL ON PURPOSE, not coincidentally:
## two complementary layers reading the same world on different clocks would hand over at slightly different
## instants, which is exactly the gap-or-overlap this design exists to prevent. Both walks are O(npcs), and a
## per-frame group scan would be waste.
const POLL_INTERVAL: float = 0.3

## Debug-readout names for whoever currently owns the moment; OWNER_NONE means nobody does (we are wandering).
const OWNER_NONE := &""
const OWNER_COMBAT := &"combat"
const OWNER_CAUTION := &"caution"
const OWNER_DIALOGUE := &"dialogue"
const OWNER_STATION := &"station"
const OWNER_RADIO := &"radio"

var _rng := RandomNumberGenerator.new()  ## its OWN generator, never the global one, so a track pick can't perturb a gameplay roll
var _last_index: int = -1   ## index into cfg.tracks of what played last; never reset, so "not twice in a row" spans deaths and level swaps
var _poll_t: float = 0.0    ## countdown to the next soundscape scan
var _owner: StringName = OWNER_NONE  ## cached poll result — who owns the moment
var _calm_t: float = 0.0    ## seconds of UNBROKEN calm; must reach cfg.resume_delay before the bed returns
var _rest_t: float = 0.0    ## the silence between tracks (see WanderMusicSettings.rest_seconds_min)
var _wanted: bool = false   ## the published tier flag


func _ready() -> void:
	# See the @risk above — a conversation pauses the tree and a pausable player goes silent on its own.
	process_mode = Node.PROCESS_MODE_ALWAYS
	autoplay = false
	volume_db = GameSettings.wander_music.silent_db
	_rng.randomize()
	# The rest window is scheduled off `finished`, which is why cfg.continuous forces the loop flag OFF at play
	# time: an accidentally loop-imported track would never emit this and would quietly become wallpaper.
	finished.connect(_on_track_finished)
	# Nothing plays from _ready, and nothing needs to: resume_delay alone holds the first note back past the
	# SkyTitle card, and the fade-in eases it under the ambience rather than announcing a boot.


func _process(delta: float) -> void:
	# Read the tuning group LIVE every frame, never cached in _ready: the CYBER SUNDAY Tuning dock retunes at
	# runtime, and a cached copy is the house "consumers must read live" trap.
	var cfg: WanderMusicSettings = GameSettings.wander_music
	# Engine.time_scale scales the _process delta, so bullet-time or the death cinematic's slow-mo would stretch
	# a 4 s fade into real seconds and a 90 s rest into minutes. Divide it back out — the move_toward equivalent
	# of the death mix's set_ignore_time_scale(true). maxf() guards FreezeFrame's near-zero hit-stop.
	var real: float = delta / maxf(Engine.time_scale, 0.001)
	# The rest burns down in REAL time whether or not we are allowed to play. A long firefight therefore SPENDS
	# the silence rather than banking it — you come out of a fight and the bed is ready, not sulking.
	_rest_t = maxf(0.0, _rest_t - real)
	_poll_t -= real
	if _poll_t <= 0.0:
		_poll_t = POLL_INTERVAL
		_owner = _scan_owner()
	# An UNAUTHORED (or disabled) playlist is inert, and inert has to mean "as if this node were not here" —
	# no flag, no fade, no picked stream.
	var live: Array[int] = _playable_indices(cfg)
	var calm: bool = cfg.enabled and not live.is_empty() and _owner == OWNER_NONE
	# ACCUMULATED, not latched: any interruption resets the clock to zero, so the bed needs resume_delay of
	# UNBROKEN calm — not merely a calm instant — before it comes back. That is what keeps it from creeping in
	# under a firefight breathing out, and from flapping during the lull between two rooms of the same fight.
	_calm_t = (_calm_t + real) if calm else 0.0
	_wanted = calm and _calm_t >= cfg.resume_delay and _rest_t <= 0.0
	_route(cfg)
	# RISING EDGE. Unlike the station bed there is no "same track continues" case to protect: this layer is
	# taken away by a FIGHT, not by a menu, and a fight is long enough that resuming a half-finished phrase
	# afterwards would read as a glitch rather than as continuity. So a fresh rise always picks fresh and starts
	# at the downbeat — and snaps to the floor FIRST, because a natural track end leaves volume_db sitting at
	# the audible level with the player stopped, which would otherwise punch the next track in at full volume
	# with no fade at all.
	if _wanted and not playing:
		var s: AudioStream = _pick_stream(cfg)
		if s == null:
			return
		stream = s
		volume_db = cfg.silent_db
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


## WHO OWNS THE MOMENT, worst-first, or OWNER_NONE when nobody does and we are free to play. Split out of
## _process and returning a NAME rather than a bool so the `wandermusic` debug command can print WHY the bed is
## quiet — "why isn't it playing" is the single most likely thing anyone will ever ask this layer.
func _scan_owner() -> StringName:
	# if/elif rather than `match`: a match PATTERN must be a compile-time constant expression, and an enum
	# member reached through another script's class_name is exactly the shape that is fiddly there. Two
	# comparisons cost nothing and cannot surprise the parser.
	var alert: int = Soundscape.alert_level(get_tree())
	if alert == Soundscape.Alert.COMBAT:
		return OWNER_COMBAT
	if alert == Soundscape.Alert.CAUTION:
		return OWNER_CAUTION
	# A conversation FREEZES THE WORLD, so NPC Perception stops sensing entirely and a polled alert tier would
	# LATCH for the whole conversation. Asked directly, and asked with is_engaged() rather than is_active():
	# is_active() reports a conversation SUSPENDED behind a sub-menu (Trade / Heal / Level Up) as inactive so
	# that menu is allowed to open, but THE TREE IS STILL PAUSED through it. MusicDirector gates on exactly the
	# same call for exactly this reason.
	if _dialogue_active():
		return OWNER_DIALOGUE
	if _station_music_wanted():
		return OWNER_STATION
	if _radio_audible_to_player():
		return OWNER_RADIO
	return OWNER_NONE


## A track played through. Start the silence — the whole point of the rest window is that a wandering theme
## which never stops stops being music and becomes wallpaper.
##
## Guarded on `_wanted` because a MANUAL stop() may or may not emit `finished` depending on the engine build,
## and an unguarded handler would let a fight schedule a 45-120 s silence on top of the resume_delay it already
## costs. If we were not wanted, the track did not end — it was taken from us.
func _on_track_finished() -> void:
	if not _wanted:
		return
	var cfg: WanderMusicSettings = GameSettings.wander_music
	var lo: float = maxf(0.0, cfg.rest_seconds_min)
	_rest_t = _rng.randf_range(lo, maxf(lo, cfg.rest_seconds_max))
	volume_db = cfg.silent_db  # the next rise re-snaps this anyway; keeping it tidy makes a debug readout honest


## True while the wandering bed is audible or about to be. The public seam, mirroring StationMusic.is_bed_wanted
## — nothing reads it today (this layer yields to every other one and is yielded to by none), but a future layer
## that must stand down for exploration music should read this FLAG rather than this node's volume, so the
## handover is a real crossfade instead of a gap.
func is_bed_wanted() -> bool:
	return _wanted


## Debug readout only (the `wandermusic` console command). Blank when nothing has ever played.
func current_track_name() -> String:
	return stream.resource_path.get_file() if stream != null else ""


## Debug readout only: who currently owns the moment (OWNER_NONE = nobody, we are wandering).
func owner_of_the_moment() -> StringName:
	return _owner


## Debug readout only: seconds of silence still owed before the bed may pick a new track. 0 = ready now.
func rest_remaining() -> float:
	return _rest_t


## Debug readout only: seconds of unbroken calm so far, against WanderMusicSettings.resume_delay.
func calm_seconds() -> float:
	return _calm_t


## Point the player at the configured bus if it exists, else `music` — NOT `sfx`, and never Master. Re-resolved
## per frame so a live retune lands, and the warning only fires on the frame the routing actually changes.
## Falling back to `sfx` would silently re-file a music bed under the Effects slider; falling back to Master
## would escape every volume slider AND the death-cinematic world duck.
func _route(cfg: WanderMusicSettings) -> void:
	var routed: StringName = cfg.bus if AudioServer.get_bus_index(cfg.bus) >= 0 else &"music"
	if bus != routed:
		if routed != cfg.bus:
			push_warning("WanderMusic: audio bus '%s' does not exist — falling back to 'music'." % cfg.bus)
		bus = routed


## The indices of the non-null playlist slots. A designer clearing ONE slot must not make the bed play silence,
## and an empty (or all-null) playlist must make the layer inert rather than error.
func _playable_indices(cfg: WanderMusicSettings) -> Array[int]:
	var live: Array[int] = []
	for i in cfg.tracks.size():
		if cfg.tracks[i] != null:
			live.append(i)
	return live


## One authored track, never the one that played last, with its loop flag FORCED to match cfg.continuous — in
## BOTH directions, so the behaviour is decided by the knob and not by whether anyone ticked Loop in the Import
## dock. `live.find(_last_index)` returning -1 — a track edited out of the playlist under us — is exactly the
## case pick_next_index treats as a fair pick.
func _pick_stream(cfg: WanderMusicSettings) -> AudioStream:
	var live: Array[int] = _playable_indices(cfg)
	if live.is_empty():
		return null
	var slot: int = MusicPlaylist.pick_next_index(live.size(), live.find(_last_index), _rng.randf())
	_last_index = live[slot]
	var authored: AudioStream = cfg.tracks[_last_index]
	if cfg.continuous:
		return LoopableStream.looping_copy(authored, "WanderMusic")
	return LoopableStream.non_looping_copy(authored, "WanderMusic")


## True while a conversation EXISTS AT ALL — see the is_engaged/is_active note in _scan_owner. Wrapped in one
## overridable method, not inlined, so a unit test can force it without driving a live DialogueManager
## conversation in a headless run (mirrors the test-double seams on MusicDirector and Radio).
func _dialogue_active() -> bool:
	return DialogueManager.is_engaged()


## True while a station terminal's own radio is playing (or about to be). Overridable for the same reason.
func _station_music_wanted() -> bool:
	return StationMusic.is_bed_wanted()


## True when the human player stands within a playing in-world Radio's audible_radius. Delegates to the shared
## Soundscape scan so this and MusicDirector cannot drift; the seam kept here is _real_player, so a test can
## place a stub listener beside a stub radio.
func _radio_audible_to_player() -> bool:
	return Soundscape.radio_audible_to(get_tree(), _real_player())


## The HUMAN player (the non-NPC member of the Player group), or null. Overridable test seam — mirrors
## MusicDirector._real_player. Tree-guarded for a bare off-tree instance.
func _real_player() -> Node3D:
	return Groups.human_player(get_tree())
