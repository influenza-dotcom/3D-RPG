extends GutTest

## Contract tests for the dialogue music bed (scripts/dialogue/dialogue_music_bed.gd) — the looping track
## faded in under every conversation. Covers the three things that break SILENTLY:
##   1. The DialogueManager autoload actually BUILDS the bed as a child (a dropped add_child = no music, no error).
##   2. The authored track in DialogueSettings.tres is set to LOOP (a Disabled .wav import still plays, but
##      seams audibly on repeat — the exact regression a re-import can reintroduce).
##   3. The loop-flag probe reads BOTH stream shapes (AudioStreamWAV.loop_mode vs .mp3/.ogg `loop`).
## The bed itself is built OFF-TREE (.new() without add_child, so _ready never runs) — no audio device, no
## GameSettings mutation, per the "don't run _ready() in a unit test" rule.

const BED_SCRIPT := preload("res://scripts/dialogue/dialogue_music_bed.gd")

func _make_bed() -> DialogueMusicBed:
	return BED_SCRIPT.new() as DialogueMusicBed

# --- Settings surface -------------------------------------------------------------------------------

func test_dialogue_settings_exposes_music_bed_knobs() -> void:
	var cfg: DialogueSettings = GameSettings.dialogue
	assert_not_null(cfg, "GameSettings.dialogue must resolve to the DialogueSettings resource")
	# Every knob the bed reads in _ready / set_bed_playing must exist, or the bed hard-errors at runtime.
	for field in ["dialogue_music", "dialogue_music_volume_db", "dialogue_music_fade_in", "dialogue_music_fade_out", "dialogue_music_bus"]:
		assert_true(field in cfg, "DialogueSettings must expose '%s' — the DialogueMusicBed reads it" % field)

func test_dialogue_music_fades_are_non_negative() -> void:
	var cfg: DialogueSettings = GameSettings.dialogue
	assert_gte(cfg.dialogue_music_fade_in, 0.0, "fade-in seconds cannot be negative")
	assert_gte(cfg.dialogue_music_fade_out, 0.0, "fade-out seconds cannot be negative")

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
	var authored := AudioStreamWAV.new()
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
	var authored := AudioStreamWAV.new()
	authored.mix_rate = 44100
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
	# behaviour) rather than erroring on a null stream. Off-tree: _ready never ran, so stream is null.
	var bed := _make_bed()
	assert_null(bed.stream, "an off-tree bed has no stream until _ready reads the settings")
	bed.set_bed_playing(true)
	assert_false(bed.playing, "set_bed_playing(true) with no authored track must not start playback")
	bed.set_bed_playing(false)
	bed.free()
