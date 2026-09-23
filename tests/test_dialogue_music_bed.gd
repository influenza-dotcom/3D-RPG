extends GutTest

## Contract tests for the dialogue music bed (scripts/dialogue/dialogue_music_bed.gd) — the looping track
## faded in under every conversation. Covers the four things that break SILENTLY:
##   1. The DialogueManager autoload actually BUILDS the bed as a child (a dropped add_child = no music, no error).
##   2. The authored track in DialogueSettings.tres is set to LOOP (a Disabled .wav import still plays, but
##      seams audibly on repeat — the exact regression a re-import can reintroduce).
##   3. The loop-flag probe reads BOTH stream shapes (AudioStreamWAV.loop_mode vs .mp3/.ogg `loop`).
##   4. The talk duck (the slight per-spoken-line dip under the voice): its two levels COMPOSE instead of
##      stomping one volume_db, a stale auto-release can't cut the next line's dip, and the pulse is inert
##      without a playing bed.
## Most beds are built OFF-TREE (.new() without add_child, so _ready never runs). The tests that need the fade tweens a
## call builds to be real (and run to their end) use an IN-TREE bed from _live_bed, whose _ready only READS
## GameSettings.dialogue; a knob one of them retunes goes through _retune and is put back in after_each.

const BED_SCRIPT := preload("res://scripts/dialogue/dialogue_music_bed.gd")

## [resource, property, previous value] for every shared GameSettings knob a test retuned, unwound in after_each.
var _retuned: Array = []

func _retune(res: Resource, prop: StringName, value: Variant) -> void:
	_retuned.append([res, prop, res.get(prop)])
	res.set(prop, value)

func after_each() -> void:
	for i in range(_retuned.size() - 1, -1, -1):
		var entry: Array = _retuned[i]
		(entry[0] as Resource).set(entry[1], entry[2])
	_retuned.clear()

func _make_bed() -> DialogueMusicBed:
	return BED_SCRIPT.new() as DialogueMusicBed

## A stand-in for an imported .wav: `seconds` of 8-bit mono silence at 44100 Hz (the fixture idiom already
## used by tests/test_audio_manager_spawn.gd). ⭐THE DATA IS THE POINT. A bare AudioStreamWAV.new() holds no
## frames, so get_length() is 0 — and _looping_copy derives the forced loop's range from
## get_length() * mix_rate, so over a data-less fixture that range comes back ZERO-LENGTH. A zero-length loop
## IS silence (the regression that once shipped), so the bed correctly refuses it, warns, and hands the
## authored stream back UNLOOPED for the finished-restart backstop — meaning a data-less fixture exercises
## that give-up path instead of the force-a-loop path these tests are about. 8-bit mono makes bytes == frames,
## so get_length() is exactly `seconds` and the derived loop_end lands on a whole frame count.
## Loop points are left at the Loop-Mode-Disabled import default (loop_begin == loop_end == 0) on purpose:
## filling those in is the code's job, and the contract under test.
func _silent_wav(seconds: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 44100
	wav.stereo = false
	var silence := PackedByteArray()
	silence.resize(int(44100.0 * seconds))  # 1 byte per frame at 8-bit mono; zero bytes = silence
	wav.data = silence
	return wav

# --- Settings surface -------------------------------------------------------------------------------

func test_dialogue_settings_exposes_music_bed_knobs() -> void:
	var cfg: DialogueSettings = GameSettings.dialogue
	assert_not_null(cfg, "GameSettings.dialogue must resolve to the DialogueSettings resource")
	# Every knob the bed reads in _ready / set_bed_playing / the talk duck must exist, or the bed hard-errors at runtime.
	for field in ["dialogue_music", "dialogue_music_volume_db", "dialogue_music_fade_in", "dialogue_music_fade_out", "dialogue_music_talk_duck_db", "dialogue_music_talk_duck_fade", "dialogue_music_bus"]:
		assert_true(field in cfg, "DialogueSettings must expose '%s' — the DialogueMusicBed reads it" % field)

func test_dialogue_music_fades_are_non_negative() -> void:
	var cfg: DialogueSettings = GameSettings.dialogue
	assert_gte(cfg.dialogue_music_fade_in, 0.0, "fade-in seconds cannot be negative")
	assert_gte(cfg.dialogue_music_fade_out, 0.0, "fade-out seconds cannot be negative")
	assert_gte(cfg.dialogue_music_talk_duck_fade, 0.0, "talk-duck fade seconds cannot be negative")

func test_authored_talk_duck_is_a_dip_not_a_boost() -> void:
	# The bed clamps a positive value to off at runtime (a "duck" that BOOSTS the bed over the voice is never
	# meant), but the authored resource should say what it does: at-or-below zero.
	assert_lte(GameSettings.dialogue.dialogue_music_talk_duck_db, 0.0,
		"dialogue_music_talk_duck_db must be <= 0 — more negative = a deeper dip under the voice; positive is clamped to off")

func test_dialogue_music_bus_exists_in_the_bus_layout() -> void:
	# Bus routing is load-bearing: a typo'd bus name silently drops the bed onto Master, escaping the
	# Options Music slider and the dialogue duck.
	var cfg: DialogueSettings = GameSettings.dialogue
	assert_gte(AudioServer.get_bus_index(cfg.dialogue_music_bus), 0,
		"dialogue_music_bus '%s' is not a bus in default_bus_layout.tres" % cfg.dialogue_music_bus)

# --- The authored track -----------------------------------------------------------------------------

func test_authored_dialogue_music_is_present() -> void:
	# The project ships a dialogue bed; if it is ever cleared this test should be deleted, not weakened.
	assert_not_null(GameSettings.dialogue.dialogue_music, "DialogueSettings.tres should author a dialogue_music track")

func test_the_bed_forces_a_non_looping_track_to_loop() -> void:
	# The whole point of the bed is that it does NOT stop dead partway through a long conversation, whatever
	# the track's import settings say. _looping_copy must hand back a looping stream — on a COPY, leaving the
	# authored resource other systems may share untouched.
	var bed := _make_bed()
	var authored := _silent_wav(1.0)  # a real import has SAMPLE FRAMES; without them there is no range to loop
	authored.loop_mode = AudioStreamWAV.LOOP_DISABLED
	var played := bed._looping_copy(authored)
	assert_true(bed._stream_loops(played), "the bed must force a non-looping track to loop")
	assert_ne(played, authored, "it must loop a COPY, not mutate the authored resource")
	assert_eq(authored.loop_mode, AudioStreamWAV.LOOP_DISABLED, "the authored resource must be left untouched")
	authored = null
	bed.free()

func test_the_forced_loop_gets_a_real_range_not_a_zero_length_one() -> void:
	# REGRESSION (this shipped silent once): a .wav imported with Loop Mode Disabled carries
	# loop_begin == loop_end == 0. Setting LOOP_FORWARD alone then loops a ZERO-LENGTH region, which plays
	# silence — the flag is set, every flag assertion passes, and you hear nothing. The range must be filled in.
	var bed := _make_bed()
	var authored := _silent_wav(1.0)  # one second at 44100 Hz, so the forced loop_end must land on 44100 frames
	authored.loop_mode = AudioStreamWAV.LOOP_DISABLED
	assert_eq(authored.loop_end, 0, "precondition: a Loop-Mode-Disabled import leaves loop_end at 0")
	var played: AudioStream = bed._looping_copy(authored)
	assert_gt(played.get("loop_end"), played.get("loop_begin"),
		"the forced loop must span a real range — loop_end == loop_begin is silence, not a loop")
	authored = null
	bed.free()

func test_stream_loops_rejects_a_flag_set_over_a_degenerate_range() -> void:
	# The probe must not be fooled by the flag alone, or _looping_copy hands back the silent stream unfixed.
	var bed := _make_bed()
	var wav := AudioStreamWAV.new()
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD  # flag on, but loop_begin == loop_end == 0
	assert_false(bed._stream_loops(wav), "LOOP_FORWARD over a zero-length range must NOT report as looping")
	wav = null
	bed.free()

func test_the_bed_reuses_an_already_looping_track_without_copying() -> void:
	var bed := _make_bed()
	var authored := AudioStreamWAV.new()
	authored.loop_mode = AudioStreamWAV.LOOP_FORWARD
	authored.loop_end = 44100  # a real range, as a correctly-imported looping .wav has
	assert_eq(bed._looping_copy(authored), authored, "an already-looping track needs no copy")
	assert_null(bed._looping_copy(null), "an unauthored bed stays null (no music, no error)")
	authored = null
	bed.free()

func test_the_live_beds_stream_loops() -> void:
	# End to end over the real authored track: whatever DialogueSettings.tres points at, what the bed is
	# actually holding after _ready must loop.
	var bed: Variant = DialogueManager.get(&"_music_bed")
	if bed == null or bed.stream == null:
		return  # no authored bed — covered by test_authored_dialogue_music_is_present
	assert_true(bed._stream_loops(bed.stream), "the live bed's stream must loop, or the music dies mid-conversation")

# --- The loop-flag probe ----------------------------------------------------------------------------

func test_stream_loops_reads_the_wav_loop_mode() -> void:
	var bed := _make_bed()
	var wav := AudioStreamWAV.new()
	wav.loop_end = 44100  # a real one-second range, so only the MODE is under test here
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	assert_false(bed._stream_loops(wav), "a LOOP_DISABLED AudioStreamWAV must report as non-looping")
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	assert_true(bed._stream_loops(wav), "a LOOP_FORWARD AudioStreamWAV over a real range must report as looping")
	wav = null
	bed.free()

func test_stream_loops_reads_the_compressed_loop_bool() -> void:
	# .mp3/.ogg carry a plain `loop` bool instead of the WAV's loop_mode enum — the probe must read both.
	var bed := _make_bed()
	var mp3 := AudioStreamMP3.new()
	mp3.loop = false
	assert_false(bed._stream_loops(mp3), "a non-looping AudioStreamMP3 must report as non-looping")
	mp3.loop = true
	assert_true(bed._stream_loops(mp3), "a looping AudioStreamMP3 must report as looping")
	mp3 = null
	bed.free()

# --- Manager wiring ---------------------------------------------------------------------------------

func test_dialogue_manager_builds_the_music_bed_child() -> void:
	# The bed is code-built in DialogueManager._ready alongside the view / ducker / face light. Losing that
	# add_child costs all dialogue music with no error anywhere — pin it.
	var bed: Variant = DialogueManager.get(&"_music_bed")
	assert_not_null(bed, "DialogueManager must build its _music_bed child")
	assert_true(bed is DialogueMusicBed, "_music_bed must be a DialogueMusicBed")
	if bed is Node:
		assert_eq((bed as Node).get_parent(), DialogueManager, "the bed must be parented to DialogueManager")
		assert_eq((bed as Node).process_mode, Node.PROCESS_MODE_ALWAYS,
			"the bed must be PROCESS_MODE_ALWAYS or the music stops dead when dialogue pauses the tree")

func test_bed_without_a_stream_is_inert() -> void:
	# An unauthored dialogue_music must leave set_bed_playing() a no-op (conversations play dry, the pre-bed
	# behaviour). IN-TREE, so the fade tween the call would build is real and can be run to its end: a bed that
	# got past the no-track guard would swell its envelope up to the authored level. The level is retuned well
	# above the silent floor so that swell cannot hide.
	_retune(GameSettings.dialogue, &"dialogue_music_volume_db", -12.0)
	var dry := _live_bed()
	dry.stream = null  # what _ready leaves when DialogueSettings authors no dialogue_music
	dry.set_bed_playing(true)
	_land(dry._fade)
	assert_almost_eq(dry.volume_db, DialogueMusicBed.SILENT_DB, 0.01,
		"a conversation opening with no authored track must leave the bed at its silent floor, not fade an empty player up")
	# CONTROL: the same in-tree bed holding a track does get past the guard and swells up to the authored level.
	var scored := _live_bed()
	scored.set_bed_playing(true)
	_land(scored._fade)
	assert_almost_eq(scored.volume_db, -12.0, 0.01,
		"control: a bed WITH a track fades up to dialogue_music_volume_db when a conversation opens")

# --- The talk duck ----------------------------------------------------------------------------------

func test_talk_duck_pulse_without_a_playing_bed_is_inert() -> void:
	# The manager pulses note_line_speech for EVERY spoken line, bed or no bed — with no stream (or the bed
	# not up yet) it must be a clean no-op: no tween, no timer, no volume write. Off-tree, so any accidental
	# create_tween/get_tree() reach here would error the test — that silence IS the contract.
	var bed := _make_bed()
	bed.note_line_speech(3.0)
	assert_eq(bed._speech_duck_db, 0.0, "a pulse with no playing bed must not duck anything")
	bed.note_line_speech_stop()  # the release side must be just as safe when nothing was ever ducked
	assert_eq(bed._speech_duck_db, 0.0, "a stop with nothing ducked stays at 0")
	bed.free()

func test_volume_is_the_sum_of_envelope_and_talk_duck() -> void:
	# The two fade tweens (conversation envelope vs talk duck) write SEPARATE levels composed in _apply_volume —
	# the design that lets the first line's dip run while the fade-in is still swelling, instead of the two
	# tweens stomping one volume_db. Pin the composition.
	var bed := _make_bed()
	bed._set_base_db(-10.0)
	assert_eq(bed.volume_db, -10.0, "with no duck, volume is the envelope alone")
	bed._set_speech_duck_db(-4.0)
	assert_eq(bed.volume_db, -14.0, "a spoken line sits duck dB UNDER the envelope")
	bed._set_base_db(-6.0)
	assert_eq(bed.volume_db, -10.0, "an envelope fade moving mid-dip keeps the duck offset intact")
	bed._set_speech_duck_db(0.0)
	assert_eq(bed.volume_db, -6.0, "releasing the duck returns to the envelope level")
	bed.free()

func test_a_stale_auto_release_does_not_cut_the_next_lines_dip() -> void:
	# A monologue: line 1 dips the bed and arms a timed release; line 2 is pulsed before that timer runs out. Line 1's
	# release expiring mid-line-2 must NOT swell the bed back up while the NPC is still talking. IN-TREE with two real
	# pulses, so every tween the calls build can be run to its end. The release each pulse arms is bound to the token
	# the pulse leaves behind, which is read here; the timers themselves (5 s) never fire inside the test, so each
	# release is invoked by hand at the moment its timer would.
	_retune(GameSettings.dialogue, &"dialogue_music_talk_duck_db", -4.0)
	var bed := _live_bed()
	bed.set_bed_playing(true)
	bed.note_line_speech(5.0)  # line 1
	_land(bed._duck_fade)
	assert_almost_eq(bed._speech_duck_db, -4.0, 0.01, "setup: line 1 dips the bed by the talk duck")
	var line_1_release: int = bed._speech_token
	bed.note_line_speech(5.0)  # line 2, before line 1's release is due
	_land(bed._duck_fade)
	bed._release_speech_duck(line_1_release)  # line 1's timer expires mid-line-2
	_land(bed._duck_fade)
	assert_almost_eq(bed._speech_duck_db, -4.0, 0.01,
		"line 1's release firing while line 2 is spoken must leave the dip alone")
	# CONTROL: the release line 2 armed does land, so the dip above held because that release was stale.
	bed._release_speech_duck(bed._speech_token)
	_land(bed._duck_fade)
	assert_almost_eq(bed._speech_duck_db, 0.0, 0.01,
		"control: the current line's own release swells the bed back up once its spoken time is over")

# --- The station-terminal handover (the THIRD summed level) -------------------------------------------

func test_three_levels_compose_into_one_volume() -> void:
	# A dialogue-hosted Trade / Heal / Bank suspends the conversation without ending it, so this bed keeps
	# playing while the station's OWN tinny radio starts. It steps aside rather than stopping — and its
	# handover level has to compose with the two that were already there, not stomp them. All three tweens can
	# be live at once: the conversation is still fading in, the NPC is mid-line, and you open the shop.
	var bed := _make_bed()
	bed._set_base_db(-10.0)
	bed._set_speech_duck_db(-4.0)
	bed._set_menu_duck_db(-60.0)
	assert_eq(bed.volume_db, -74.0, "all three levels must sum into volume_db")
	bed._set_menu_duck_db(0.0)
	assert_eq(bed.volume_db, -14.0, "closing the terminal restores exactly the envelope + talk duck")
	bed.free()

func test_the_menu_handover_is_latched_so_a_per_frame_assert_is_free() -> void:
	# StationMusic asserts note_menu_music() EVERY FRAME rather than on the edge — that is what removes the
	# ordering hazard between its poll and a conversation starting or ending. It is only affordable because the
	# latch makes a repeat call a no-op; without it every frame would kill and rebuild a tween.
	var bed := _make_bed()
	assert_false(bed._menu_ducked, "a fresh bed is not menu-ducked")
	bed.note_menu_music(false)
	assert_null(bed._menu_fade, "asserting the state it is already in must not build a tween")
	bed.free()

## An IN-TREE bed holding a real looping stream, so set_bed_playing is live rather than the null-stream no-op. Its
## _ready only READS GameSettings.dialogue; the authored stream it picked is swapped for a fixture so the test does
## not depend on the shipped track. Autofreed with the test.
func _live_bed() -> DialogueMusicBed:
	var bed := _make_bed()
	add_child_autofree(bed)
	var wav := _silent_wav(1.0)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 44100
	bed.stream = wav
	return bed

## Run a fade tween straight to its end (no real-time wait): the level writer lands on the fade's target.
func _land(t: Tween) -> void:
	if t != null and t.is_valid():
		t.custom_step(60.0)

func test_a_conversation_settles_the_menu_duck_on_the_way_in_and_out() -> void:
	# The symmetric trap to the talk duck's: a conversation that ENDED while a terminal was up would otherwise
	# freeze a -60 dB dip in and the NEXT conversation would open inaudible. set_bed_playing settles it both
	# directions; StationMusic simply re-asserts next frame if a terminal really is still open.
	var cfg: DialogueSettings = GameSettings.dialogue
	var bed := _live_bed()
	bed.note_menu_music(true)   # a station screen stepped the bed aside...
	_land(bed._menu_fade)
	assert_true(bed._menu_ducked, "setup: the terminal handover is latched")
	assert_lt(bed._menu_duck_db, 0.0,
		"control: the terminal handover really pulled the bed down, so the swell-back asserted below is a real change")

	bed.set_bed_playing(true)   # ...and a conversation opens with that dip still latched
	assert_false(bed._menu_ducked, "opening a conversation must drop the stale terminal latch so the swell-back runs")
	_land(bed._fade)
	_land(bed._menu_fade)
	assert_almost_eq(bed._menu_duck_db, 0.0, 0.01, "the stale terminal dip swells back out as the conversation opens")
	assert_almost_eq(bed.volume_db, cfg.dialogue_music_volume_db, 0.01,
		"the conversation's bed plays at the authored level, not buried under a frozen terminal dip")

	bed.note_menu_music(true)   # a dialogue-hosted shop opens mid-conversation...
	_land(bed._menu_fade)
	bed.set_bed_playing(false)  # ...and the conversation ends (the player dies) while it is still up
	assert_false(bed._menu_ducked, "closing the conversation must settle the terminal latch too")
	_land(bed._menu_fade)
	assert_almost_eq(bed._menu_duck_db, 0.0, 0.01,
		"the dip is released on the way out, so the NEXT conversation does not inherit it")
