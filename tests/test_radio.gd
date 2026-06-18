extends GutTest

## Off-tree surface tests for the Radio component. We never add_child it or run _ready (which builds the
## look-at outline and, with auto_fit_collider, touches global_transform — that fails GUT 9.6 off-tree).
## We build it with .new() and poke only the methods that don't need the tree. In-tree behaviour (the
## fallback player, the combat poll) is verified by manual playtest; the duck/settle logic is covered
## headlessly by test_radio_playback_state.gd.

const RADIO_SCRIPT := "res://scripts/components/radio.gd"

var _prev_music_folder: String

func before_each() -> void:
	# Neutralize any player music-folder override so the folder tests deterministically exercise the radio's
	# own curated res:// export. Set the var directly (not the persisting setter), restored in after_each.
	_prev_music_folder = Settings.music_folder
	Settings.music_folder = ""

func after_each() -> void:
	Settings.music_folder = _prev_music_folder

func _make() -> Radio:
	return load(RADIO_SCRIPT).new()

func test_is_a_look_at_interactable() -> void:
	var r := _make()
	assert_true(r is LookAtInteractable, "Radio plugs into the look-at interact system")
	assert_true(r.has_method("start_talk"), "exposes the talk-handler surface (start_talk)")
	assert_true(r.has_method("look_name"))
	assert_true(r.has_method("can_be_talked_to"))
	r.free()

func test_look_name_reflects_on_off() -> void:
	var r := _make()
	r.radio_name = "Jukebox"
	assert_eq(r.look_name(), "Turn on Jukebox", "Off -> prompts to turn on")
	r._state.set_playing(true)
	assert_eq(r.look_name(), "Turn off Jukebox", "On -> prompts to turn off")
	r.free()

func test_look_name_falls_back_to_generic_when_unnamed() -> void:
	var r := _make()
	assert_eq(r.look_name(), "Turn on radio", "An unnamed radio uses a generic label")
	r.free()

func test_always_interactable() -> void:
	var r := _make()
	assert_true(r.can_be_talked_to(), "A radio can always be toggled")
	r.free()

func test_owns_a_playback_state() -> void:
	var r := _make()
	assert_not_null(r._state, "Radio builds its duck/settle state machine at construction")
	assert_false(r._state.is_playing(), "and it starts switched off")
	r.free()

func test_export_defaults() -> void:
	# Pin the designer-facing defaults so an accidental edit is caught (same idea as the tuning-default tests).
	var r := _make()
	assert_eq(r.poll_interval, 0.3, "combat scan interval default")
	assert_eq(r.settle_cooldown, 3.0, "post-combat settle default")
	assert_eq(r.fade_pause_time, 0.4, "duck-out time default")
	assert_eq(r.fade_resume_time, 1.2, "ease-in time default")
	assert_eq(r.silent_db, -60.0, "silent floor default")
	assert_eq(r.fallback_volume_db, 0.0, "audible level default")
	assert_false(r.combat_strict, "defaults to the broad hunt predicate, matching MusicDirector")
	r.free()

func test_combat_poll_is_null_guarded_off_tree() -> void:
	# The combat scan reads get_tree(); a bare off-tree Radio has none. It must read "no combat", never crash
	# (mirrors MusicDirector's tree==null guard).
	var r := _make()
	assert_false(r._any_npc_fighting(), "no tree -> no combat, null-guarded")
	r.free()

# --- Folder playlist (Slice B) ---

func test_music_source_defaults() -> void:
	var r := _make()
	assert_eq(r.music_folder, "res://assets/audio/music", "default curated music folder")
	assert_false(r.shuffle, "shuffle off by default (on-disk order)")
	r.free()

func test_owns_a_playlist() -> void:
	var r := _make()
	assert_not_null(r._playlist, "Radio builds its track-ordering playlist at construction")
	assert_false(r._playlist.has_tracks(), "and it starts empty (nothing loaded until turn-on)")
	r.free()

func test_scan_finds_audio_in_curated_folder() -> void:
	# DirAccess works headless. The shipped res://assets/audio/music holds the curated tracks; the scan must
	# return only audio files (no .import/.remap sidecars), full-pathed under the folder, sorted.
	var r := _make()
	var found := r._scan_audio_folder("res://assets/audio/music")
	assert_gt(found.size(), 0, "the curated folder has at least one track")
	var prev := ""
	for path in found:
		assert_true(path.begins_with("res://assets/audio/music/"), "full res:// path under the folder: %s" % path)
		var ext: String = path.get_extension().to_lower()
		assert_true(ext == "mp3" or ext == "ogg" or ext == "wav", "only audio extensions: %s" % path)
		assert_false(path.ends_with(".import"), "no .import sidecar leaks through: %s" % path)
		assert_true(prev <= path, "results are sorted by name")
		prev = path
	r.free()

func test_scan_empty_and_bad_folders_return_empty() -> void:
	var r := _make()
	assert_eq(r._scan_audio_folder("").size(), 0, "a blank folder yields no tracks")
	assert_eq(r._scan_audio_folder("res://does/not/exist").size(), 0, "an unopenable folder yields no tracks (no crash)")
	r.free()

func test_load_playlist_populates_from_curated_folder() -> void:
	var r := _make()
	r._load_playlist()  # uses the default music_folder
	assert_true(r._playlist.has_tracks(), "turn-on loads the curated folder into the playlist")
	r.free()

func test_quality_text_is_track_name_with_playlist_else_radio_name() -> void:
	var r := _make()
	r.radio_name = "Alley Radio"
	assert_eq(r.quality_text(), "Alley Radio", "with no folder loaded, the scorer reads the radio name")
	r._load_playlist()
	var q := r.quality_text()
	assert_ne(q, "", "with a folder loaded, the scorer reads a track")
	var ext: String = q.get_extension().to_lower()
	assert_true(ext == "mp3" or ext == "ogg" or ext == "wav", "scorer reads the track FILENAME, not the radio name: %s" % q)
	r.free()

func test_playback_is_null_guarded_off_tree() -> void:
	# No _ready off-tree -> audio_player is null. Driving playback must no-op, never crash.
	var r := _make()
	r._load_playlist()
	r._play_current()       # audio_player null -> returns
	r._on_track_finished()  # not playing -> returns
	assert_true(true, "no crash driving playback off-tree")
	r.free()

# --- User folder override + external loading (Slice C) ---

func test_resolve_folder_prefers_player_override() -> void:
	var r := _make()
	assert_eq(r._resolve_folder("user://my_music", "res://curated"), "user://my_music", "a set player folder wins")
	assert_eq(r._resolve_folder("", "res://curated"), "res://curated", "blank override -> the radio's own folder")
	assert_eq(r._resolve_folder("   ", "res://curated"), "res://curated", "whitespace-only override is treated as blank")
	r.free()

func test_effective_folder_follows_settings_override() -> void:
	var r := _make()  # music_folder export defaults to the curated res:// folder
	assert_eq(r._effective_folder(), r.music_folder, "no override -> the radio's curated folder")
	Settings.music_folder = "user://player_tunes"
	assert_eq(r._effective_folder(), "user://player_tunes", "a player override takes precedence for every radio")
	Settings.music_folder = ""  # after_each also restores, but keep the rest of this test clean
	r.free()

func test_load_stream_handles_empty_and_missing() -> void:
	var r := _make()
	assert_null(r._load_stream(""), "empty path -> null")
	assert_null(r._load_stream("user://definitely_missing_track.mp3"), "a missing external file -> null (skipped), no crash")
	assert_null(r._load_external_stream("user://nope.ogg"), "missing external ogg -> null via the file-exists guard")
	r.free()

func test_track_finished_skip_loop_is_bounded_off_tree() -> void:
	# The dead-track-skip in _on_track_finished must TERMINATE even when nothing can play (audio_player null
	# off-tree): bounded by playlist size, it can't spin. Drives it with the radio "on" + a loaded playlist.
	var r := _make()
	r._state.set_playing(true)
	r._load_playlist()
	r._on_track_finished()  # loops at most size() times, plays nothing (no audio_player), returns — no hang/crash
	assert_true(true, "the dead-track-skip loop terminates off-tree")
	r.free()
