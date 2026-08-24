extends GutTest

## Contract tests for the WANDERING BED — the quiet exploration score
## (scripts/components/wander_music.gd + resources/tuning/WanderMusicSettings.tres + the WanderMusic node in
## scenes/game.tscn), and for the shared soundscape scan it and the combat score now both read
## (scripts/audio/soundscape.gd).
##
## Nothing here can HEAR a fade, a level or a bus send — that is playtest territory, and the `wandermusic`
## console command exists for it. What IS pinned is the set of things that break SILENTLY and stay invisible
## until someone happens to A/B them:
##   1. The COMPLEMENT contract. This bed and MusicDirector's score are inverses of each other, so their two
##      envelopes have to interlock. A retune that lets the bed linger into a firefight, or come back under a
##      fight breathing out, is inaudible-looking in a diff and obvious in a playtest — pin the arithmetic.
##   2. WHO OWNS THE MOMENT and in what order. Five suppressors, one of them (dialogue) load-bearing for
##      correctness rather than taste.
##   3. The shared scan's degenerate inputs (null tree) and its radio distance gate.
##   4. The extraction itself: StationMusic.pick_next_index must still answer exactly as it did before the
##      picker moved to MusicPlaylist, and LoopableStream must now force the loop flag in BOTH directions.
##   5. The live node's resting posture — PROCESS_MODE_ALWAYS (a conversation pauses the tree and a pausable
##      AudioStreamPlayer silences itself with nothing logged), silent, stopped, claiming nothing.

const DIRECTOR_SCRIPT := preload("res://scripts/components/music_director.gd")
## Where wandering tracks must live. NOT res://assets/audio/music — see the radio-scan test below.
const WANDER_DIR := "res://assets/audio/music/wander"


## A minimal stand-in for a playing in-world Radio: a Node3D in the MUSIC group reporting is_playing() and
## carrying an audible_radius — exactly the surface Soundscape.radio_audible_to duck-types over. Avoids pulling
## in radio.gd, whose _ready builds a look-at outline / touches global_transform off the rig (GUT 9.6).
class StubRadio extends Node3D:
	var audible_radius: float = 12.0
	var on: bool = true
	func is_playing() -> bool:
		return on


## The bed with every EXTERNAL oracle forced, so a headless run needs no live DialogueManager conversation, no
## open station screen and no real Player. The NPC half is left real: an in-tree rig has an empty `npc` group,
## which is genuinely CALM.
class StubbedBed extends WanderMusic:
	var dialogue: bool = false
	var station: bool = false
	var listener: Node3D = null
	func _dialogue_active() -> bool:
		return dialogue
	func _station_music_wanted() -> bool:
		return station
	func _real_player() -> Node3D:
		return listener


## A duck-typed stand-in for the .mp3/.ogg shape LoopableStream probes: a `loop` BOOL and no `loop_mode`.
## A real AudioStreamMP3 cannot be built in a test — it re-runs its decoder on duplicate() and dies with
## "Failed to decode mp3 file" — so this is how the branch the shipped .mp3 path takes gets covered at all.
class StubLoopStream extends AudioStream:
	@export var loop: bool = true


func _make_bed() -> StubbedBed:
	var bed := StubbedBed.new()
	add_child_autofree(bed)          # _ready runs: process_mode, silent floor, the `finished` connection
	bed.set_process(false)           # the ENGINE must not also drive it — every test below steps _process by hand
	return bed


var _saved_cfg: WanderMusicSettings = null


func after_each() -> void:
	# ALWAYS restore, and restore in after_each rather than at the end of each test: GUT runs this even when a
	# test fails its assert, so a failure can never leak a doctored playlist into the next test or the rest of
	# the suite. Nothing is ever written to disk — the swap is a live field on the autoload.
	if _saved_cfg != null:
		GameSettings.wander_music = _saved_cfg
		_saved_cfg = null


## A VALID, silent, self-contained stream. Built in code rather than borrowed from the project so these tests
## keep working whatever the shipped playlist holds, and never depend on an asset that ATTRIBUTION.md has
## slated for deletion. The DATA matters: an AudioStreamWAV with an empty buffer (like a hand-built
## AudioStreamMP3) errors inside play(), and GUT reports an engine error as a failed test.
func _silent_stream(seconds: float = 2.0) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var buf := PackedByteArray()
	buf.resize(int(22050.0 * seconds))   # resize() zero-fills -> silence
	wav.data = buf
	return wav


## Temporarily install a playlist on the LIVE tuning group, restored by after_each. THE SHIPPED PLAYLIST IS
## EMPTY — the layer ships inert on purpose — so without this the pacing tests below would pass vacuously and
## cheerfully report a broken gate as healthy. A DUPLICATE is installed; the real resource is never mutated.
func _install_playlist(tracks: Array[AudioStream]) -> WanderMusicSettings:
	_saved_cfg = GameSettings.wander_music
	var tmp: WanderMusicSettings = _saved_cfg.duplicate() as WanderMusicSettings
	tmp.tracks = tracks
	GameSettings.wander_music = tmp
	return tmp


# --- 1. The complement contract: the two envelopes must interlock ----------------------------------------

func test_the_bed_is_out_of_the_way_before_the_combat_score_arrives() -> void:
	# The bed fades DOWN while MusicDirector fades UP, starting from the same 0.3 s poll. If the bed's fade_out
	# is slower than the score's fade_in, the two overlap at audible levels and the moment a fight starts lands
	# on a muddy chord instead of a hit. This is the single most retune-sensitive number in the feature.
	var cfg: WanderMusicSettings = GameSettings.wander_music
	var director := DIRECTOR_SCRIPT.new()
	var score_fade_in: float = director.fade_in_time
	director.free()
	assert_lt(cfg.fade_out, score_fade_in,
		"WanderMusicSettings.fade_out (%.2fs) must stay UNDER MusicDirector.fade_in_time (%.2fs) so the "
		% [cfg.fade_out, score_fade_in]
		+ "wandering bed is gone before the combat score is loud — otherwise a fight starts on two stacked beds")

func test_the_bed_does_not_creep_back_in_under_a_fight_breathing_out() -> void:
	# MusicDirector holds FULL for combat_linger and THEN fades out over fade_out_time, so the combat score is
	# still audible for (linger + fade) seconds after the last enemy disengages. resume_delay must cover that
	# whole tail or the wandering bed swells up underneath the fight's own exhale.
	var cfg: WanderMusicSettings = GameSettings.wander_music
	var director := DIRECTOR_SCRIPT.new()
	var linger: float = director.combat_linger
	var score_fade_out: float = director.fade_out_time
	director.free()
	var tail: float = linger + score_fade_out
	assert_gte(cfg.resume_delay, tail,
		"WanderMusicSettings.resume_delay (%.1fs) must cover MusicDirector's whole tail — combat_linger %.1fs + "
		% [cfg.resume_delay, linger]
		+ "fade_out_time %.1fs = %.1fs — or the wandering bed rises under a fight that is still fading out"
		% [score_fade_out, tail])

func test_the_bed_sits_well_under_the_combat_score() -> void:
	# "Quietly plays while exploring" is the entire brief. The combat score's node is authored at 0 dB on the
	# `music` bus in game.tscn; a wandering bed at or near that level is not a wandering bed, it is a soundtrack.
	var cfg: WanderMusicSettings = GameSettings.wander_music
	assert_lt(cfg.volume_db, -6.0,
		"WanderMusicSettings.volume_db (%.1f dB) is too close to the combat score's authored 0 dB — the "
		% cfg.volume_db + "exploration bed is supposed to be noticed only if you listen for it")
	assert_gt(cfg.volume_db, cfg.silent_db + 1.0,
		"volume_db must sit meaningfully above silent_db or the fade-in is a no-op and the bed never arrives")

func test_the_fades_and_the_rest_window_are_sane() -> void:
	var cfg: WanderMusicSettings = GameSettings.wander_music
	assert_gt(cfg.fade_in, 0.0, "fade_in must be positive — the bed should seep in, not pop in")
	assert_gt(cfg.fade_out, 0.0, "fade_out must be positive")
	assert_gte(cfg.rest_seconds_max, cfg.rest_seconds_min,
		"rest_seconds_max (%.0f) must not be below rest_seconds_min (%.0f) — the randf_range clamps it, but a "
		% [cfg.rest_seconds_max, cfg.rest_seconds_min] + "designer reading the inspector should not have to know that")
	assert_gte(cfg.rest_seconds_min, 0.0, "a negative rest is meaningless")


# --- 2. The playlist is actually authored -----------------------------------------------------------------

func test_an_empty_playlist_makes_the_layer_completely_inert() -> void:
	# THE CONTRACT THE SHIPPED STATE RELIES ON. `tracks` is empty on purpose right now, so this layer must be
	# indistinguishable from not existing: no tier flag, no playback, no drift off the silent floor, no matter
	# how long the world stays calm. Asserted against an EXPLICITLY empty playlist rather than against whatever
	# is authored, so it keeps holding the day somebody does add a track.
	var cfg := _install_playlist([] as Array[AudioStream])
	var bed := _make_bed()
	for i in 20:
		bed._process(1.0)          # 20 seconds — far past resume_delay
	assert_false(bed.is_bed_wanted(), "an empty playlist must never raise the tier flag")
	assert_false(bed.playing, "...must never start playback")
	assert_almost_eq(bed.volume_db, cfg.silent_db, 0.0001, "...and must never move off the silent floor")

func test_no_playlist_slot_is_null() -> void:
	# The bed skips null slots, so a half-cleared playlist degrades quietly rather than erroring — which is
	# exactly why a slot nobody meant to clear is worth catching here.
	var cfg: WanderMusicSettings = GameSettings.wander_music
	for i in cfg.tracks.size():
		assert_not_null(cfg.tracks[i],
			"wander playlist slot %d is null — the bed skips null slots, but a slot nobody meant to clear is a "
			% i + "track that silently stopped playing")
	# The playlist SHIPS EMPTY (the layer is inert by design), so the loop above is vacuous today and re-arms
	# the moment somebody authors a track. Assert the thing that is true either way: the folder the docs tell
	# you to drop tracks into still exists, and still carries the note explaining why it is a subfolder.
	assert_true(FileAccess.file_exists(WANDER_DIR + "/README.md"),
		"%s/README.md is missing — that folder and its note are where the non-recursive-radio-scan rule lives; "
		% WANDER_DIR + "without it the next person drops a track in assets/audio/music/ and every radio starts "
		+ "playing the exploration cue")

func test_the_authored_bus_exists() -> void:
	# A typo drops the bed onto the `music` fallback with only a push_warning, which nobody reads.
	var cfg: WanderMusicSettings = GameSettings.wander_music
	assert_gte(AudioServer.get_bus_index(cfg.bus), 0,
		"WanderMusicSettings.bus '%s' is not a bus in default_bus_layout.tres — the bed will fall back to "
		% cfg.bus + "'music' with only a warning")

func test_the_radio_folder_scan_cannot_see_the_wandering_folder() -> void:
	# ⭐LOAD-BEARING PLACEMENT, not tidiness. Radio.music_folder defaults to res://assets/audio/music and its
	# scan is NON-recursive, so a track left FLAT in that folder gets shuffled into every in-world radio and
	# every thrown radio-grenade. The station themes live in music/station/ for the same reason.
	#
	# Asserted against Radio's REAL scan rather than against the playlist's contents, because the playlist ships
	# empty: a contents-only check would pass vacuously and the rule would quietly stop being enforced exactly
	# while nobody is looking. Built off-tree with no add_child, per the house rule — radio.gd's _ready touches
	# global_transform and builds a look-at outline.
	var radio = load("res://scripts/components/radio.gd").new()
	var scanned: PackedStringArray = radio._scan_audio_folder("res://assets/audio/music")
	radio.free()
	for path in scanned:
		assert_false(path.begins_with(WANDER_DIR),
			"Radio's non-recursive scan of res://assets/audio/music returned '%s' — a wandering track has " % path
			+ "leaked into the flat music folder and every in-world radio will now shuffle it")
	# And the positive half: whatever IS authored must resolve into the wander folder.
	var cfg: WanderMusicSettings = GameSettings.wander_music
	for track in cfg.tracks:
		if track == null or track.resource_path.is_empty():
			continue
		assert_eq(track.resource_path.get_base_dir(), WANDER_DIR,
			"'%s' must live in %s/ — left flat in res://assets/audio/music/ it would be picked up by every "
			% [track.resource_path, WANDER_DIR] + "in-world Radio's non-recursive folder scan")


# --- 3. Who owns the moment, and in what order ------------------------------------------------------------

func test_an_empty_world_is_nobody_s_moment() -> void:
	var bed := _make_bed()
	assert_eq(bed._scan_owner(), WanderMusic.OWNER_NONE,
		"with no NPCs, no conversation, no station screen and no radio, nobody owns the moment — the bed may play")

func test_a_conversation_takes_the_moment() -> void:
	# NOT a taste gate. A conversation PAUSES THE TREE, so NPC Perception stops sensing and a polled alert tier
	# would latch for the whole conversation; and DialogueMusicBed is already the music for talking.
	var bed := _make_bed()
	bed.dialogue = true
	assert_eq(bed._scan_owner(), WanderMusic.OWNER_DIALOGUE,
		"an engaged conversation must take the moment, or the wandering bed stacks under DialogueMusicBed")

func test_a_station_terminal_takes_the_moment() -> void:
	var bed := _make_bed()
	bed.station = true
	assert_eq(bed._scan_owner(), WanderMusic.OWNER_STATION,
		"an open terminal is already playing its own tinny radio at you — the wandering bed stands down")

func test_an_audible_radio_takes_the_moment_and_a_distant_one_does_not() -> void:
	# The distance gate is the whole point: a radio across the map is already near-silent from its own 3D
	# attenuation and must not silence the score over here.
	var bed := _make_bed()
	var listener := Node3D.new()
	add_child_autofree(listener)
	bed.listener = listener
	var radio := StubRadio.new()
	radio.audible_radius = 12.0
	add_child_autofree(radio)
	radio.add_to_group(Groups.MUSIC)

	radio.global_position = listener.global_position + Vector3(5.0, 0.0, 0.0)
	assert_eq(bed._scan_owner(), WanderMusic.OWNER_RADIO,
		"standing inside a playing radio's audible_radius, the radio owns the moment")

	radio.global_position = listener.global_position + Vector3(50.0, 0.0, 0.0)
	assert_eq(bed._scan_owner(), WanderMusic.OWNER_NONE,
		"a radio 50 m away is out of earshot and must NOT mute the wandering bed over here")

	radio.global_position = listener.global_position + Vector3(5.0, 0.0, 0.0)
	radio.on = false
	assert_eq(bed._scan_owner(), WanderMusic.OWNER_NONE,
		"a radio that is switched OFF owns nothing, however close you stand to it")

func test_dialogue_outranks_a_station_and_a_radio() -> void:
	# Order matters for the READOUT, not for the outcome (any owner suppresses), and the readout is how anyone
	# will ever debug "why is it quiet". Pin the precedence so the answer stays the most informative one.
	var bed := _make_bed()
	bed.dialogue = true
	bed.station = true
	assert_eq(bed._scan_owner(), WanderMusic.OWNER_DIALOGUE,
		"a conversation hosting a station screen should report the conversation, not the terminal")


# --- 4. Pacing: the calm clock and the rest window ---------------------------------------------------------

func test_the_bed_waits_out_resume_delay_before_it_comes_back() -> void:
	var cfg := _install_playlist([_silent_stream()] as Array[AudioStream])
	var bed := _make_bed()
	bed._process(cfg.resume_delay * 0.5)
	assert_false(bed.is_bed_wanted(),
		"half of resume_delay of calm is not enough — the bed must not creep in under a fight fading out")
	bed._process(cfg.resume_delay)
	assert_true(bed.is_bed_wanted(),
		"after resume_delay of unbroken calm the bed is wanted and starts playing")

func test_any_interruption_resets_the_calm_clock_to_zero() -> void:
	# ACCUMULATED, not latched. The bed needs resume_delay of UNBROKEN calm; a fight that flickers for one poll
	# must cost the bed the whole wait again, not merely that instant.
	var cfg := _install_playlist([_silent_stream()] as Array[AudioStream])
	var bed := _make_bed()
	bed._process(cfg.resume_delay * 2.0)
	assert_true(bed.is_bed_wanted(), "precondition: the bed is up")
	bed.dialogue = true
	bed._poll_t = 0.0                      # force the next _process to re-scan rather than reuse the cache
	bed._process(0.1)
	assert_false(bed.is_bed_wanted(), "an interruption drops the flag immediately")
	assert_almost_eq(bed.calm_seconds(), 0.0, 0.0001, "and it resets the calm clock to zero, not merely pauses it")
	bed.dialogue = false
	bed._poll_t = 0.0
	bed._process(cfg.resume_delay * 0.5)
	assert_false(bed.is_bed_wanted(),
		"so half of resume_delay after the interruption clears is still not enough — the wait starts over")

func test_a_track_that_plays_through_schedules_a_rest_but_one_that_was_taken_away_does_not() -> void:
	var cfg: WanderMusicSettings = GameSettings.wander_music
	var bed := _make_bed()

	bed._wanted = false
	bed._on_track_finished()
	assert_almost_eq(bed.rest_remaining(), 0.0, 0.0001,
		"a stop() forced by something taking the moment must NOT schedule a rest — the fight already cost the "
		+ "bed a full resume_delay, and charging it a second silence on top is how a layer goes quiet for good")

	bed._wanted = true
	bed._on_track_finished()
	assert_gte(bed.rest_remaining(), cfg.rest_seconds_min,
		"a track that played through rests at least rest_seconds_min")
	assert_lte(bed.rest_remaining(), cfg.rest_seconds_max,
		"...and at most rest_seconds_max")

func test_the_rest_burns_down_in_real_seconds_under_slow_motion() -> void:
	# Engine.time_scale scales the _process delta, so the death cinematic's slow-mo would otherwise stretch a
	# 90 s rest into minutes of real silence. Same divide-it-back-out contract as StationMusic.
	var bed := _make_bed()
	bed._wanted = true
	bed._on_track_finished()
	var before := bed.rest_remaining()
	var prior := Engine.time_scale
	Engine.time_scale = 0.25
	bed._process(0.25)     # a 0.25 s scaled delta == 1.0 real second
	Engine.time_scale = prior
	assert_almost_eq(bed.rest_remaining(), before - 1.0, 0.05,
		"the rest must count REAL seconds — at time_scale 0.25 a 0.25 s delta is one real second")


# --- 5. The shared scan (Soundscape) -----------------------------------------------------------------------

func test_a_null_tree_is_calm_and_hears_no_radio() -> void:
	# A bare off-tree instance in a unit test must degrade to "nobody is aware of anything", never crash.
	var seen := Soundscape.scan(null)
	assert_false(bool(seen["combat"]), "a null tree reports no combat")
	assert_false(bool(seen["caution"]), "a null tree reports no caution")
	assert_eq(Soundscape.alert_level(null), Soundscape.Alert.CALM, "and collapses to CALM")
	assert_false(Soundscape.radio_audible_to(null, null), "and hears no radio")

func test_a_null_listener_hears_no_radio() -> void:
	# No listener, no yield — the seam MusicDirector and WanderMusic both rely on when there is no live Player.
	assert_false(Soundscape.radio_audible_to(get_tree(), null),
		"with no human player in the tree, no radio can be 'audible to' anyone")

func test_alert_level_collapses_the_pair_worst_first() -> void:
	# The pair and the collapsed tier must not disagree — MusicDirector reads the pair, the wandering bed reads
	# the tier, and they are complements of each other.
	assert_eq(Soundscape.alert_level(get_tree()), Soundscape.Alert.CALM,
		"an empty npc group is CALM, matching scan()'s two false flags")
	assert_gt(Soundscape.Alert.COMBAT, Soundscape.Alert.CAUTION, "COMBAT must outrank CAUTION in the enum order")
	assert_gt(Soundscape.Alert.CAUTION, Soundscape.Alert.CALM, "CAUTION must outrank CALM")


# --- 6. The extractions must not have changed any answer ---------------------------------------------------

func test_station_music_still_picks_exactly_as_it_did_before_the_picker_moved() -> void:
	# The picker moved to MusicPlaylist so the wandering bed could reuse it instead of copying it. StationMusic
	# kept the NAME as a delegation; this pins that the delegation is not merely present but identical.
	for count in [1, 2, 3, 5]:
		for last in [-1, 0, 1, 99]:
			for roll in [0.0, 0.17, 0.5, 0.83, 0.999]:
				assert_eq(StationMusic.pick_next_index(count, last, roll),
					MusicPlaylist.pick_next_index(count, last, roll),
					"StationMusic.pick_next_index must delegate identically (count=%d last=%d roll=%.3f)"
					% [count, last, roll])

func test_the_picker_never_repeats_when_it_has_a_choice() -> void:
	for last in [0, 1, 2]:
		for roll in [0.0, 0.3, 0.6, 0.99]:
			var got := MusicPlaylist.pick_next_index(3, last, roll)
			assert_ne(got, last, "with 3 tracks the picker must never return `last` (last=%d roll=%.2f)" % [last, roll])
			assert_true(got >= 0 and got < 3, "...and must stay in range (got %d)" % got)

func test_loopable_stream_forces_the_flag_in_both_directions() -> void:
	# non_looping_copy is what keeps the REST WINDOW honest: an AudioStreamPlayer whose stream loops never emits
	# `finished`, so one tick of the Import dock's Loop checkbox would silently turn "play, then leave the player
	# alone" into "loop forever" with nothing logged.
	# The .mp3/.ogg branch — a `loop` BOOL and no `loop_mode` — via the duck-typed stub, because a hand-built
	# AudioStreamMP3 holds no data and dies inside duplicate(). This is the shape a dropped-in .mp3 takes.
	var looping := StubLoopStream.new()
	looping.loop = true
	assert_true(LoopableStream.loops(looping), "precondition: the stub reads as looping")
	assert_false(LoopableStream.loops(LoopableStream.non_looping_copy(looping, "test")),
		"a looping .mp3-shaped stream must come back non-looping, or `finished` never fires and the rest "
		+ "window between tracks silently never happens")
	assert_true(looping.loop, "...on a COPY — the shared authored resource other systems hold is never mutated")

	var flat := StubLoopStream.new()
	flat.loop = false
	assert_same(LoopableStream.non_looping_copy(flat, "test"), flat,
		"an already-non-looping stream is returned as-is, with no needless duplicate")
	assert_true(LoopableStream.loops(LoopableStream.looping_copy(flat, "test")),
		"and the mirror still works: continuous mode forces the flag ON")
	assert_false(flat.loop, "...again on a copy")

	# The .wav branch uses the loop_mode ENUM rather than the mp3/ogg `loop` bool, and carries the
	# zero-length-range scar (LOOP_FORWARD over loop_begin == loop_end plays SILENCE), so give it a real range.
	var wav := AudioStreamWAV.new()
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = 1000
	assert_true(LoopableStream.loops(wav), "precondition: a WAV with a real loop range reads as looping")
	assert_false(LoopableStream.loops(LoopableStream.non_looping_copy(wav, "test")),
		"a looping WAV must come back non-looping")
	assert_eq(wav.loop_mode, AudioStreamWAV.LOOP_FORWARD,
		"...on a COPY — the authored WAV must never be mutated")


# --- 7. The live node's resting posture --------------------------------------------------------------------

func test_the_bed_rests_silent_stopped_and_claiming_nothing() -> void:
	var cfg: WanderMusicSettings = GameSettings.wander_music
	var bed := _make_bed()
	assert_eq(bed.process_mode, Node.PROCESS_MODE_ALWAYS,
		"PROCESS_MODE_ALWAYS is load-bearing: a conversation pauses the tree, and a PAUSABLE AudioStreamPlayer "
		+ "silences itself ~15 ms in with nothing logged — the bed must FADE out of a conversation, not vanish")
	assert_false(bed.autoplay, "the bed picks and plays its own track; autoplay would start an unpicked one")
	assert_false(bed.playing, "nothing plays from _ready — the first note waits out resume_delay")
	assert_almost_eq(bed.volume_db, cfg.silent_db, 0.0001, "and it rests on the silent floor")
	assert_false(bed.is_bed_wanted(), "and claims no tier flag at rest")
	assert_eq(bed.current_track_name(), "", "and names no track before it has ever played one")

func test_the_bed_is_authored_in_the_game_scene() -> void:
	# The whole feature is one authored node. A refactor that drops it leaves every test above green and the
	# game silent — this is the only check that would notice.
	var text := FileAccess.get_file_as_string("res://scenes/game.tscn")
	assert_true(text.contains("res://scripts/components/wander_music.gd"),
		"scenes/game.tscn must author a WanderMusic node — without it the exploration bed never exists in game")
	assert_true(text.contains('name="WanderMusic"'),
		"the node should still be called WanderMusic — the debug command finds it by TYPE, but the docs and the "
		+ "scene tree both name it")
	assert_true(text.contains('parent="Player"'),
		"the WanderMusic node should hang off Player beside the combat score's Music player")
