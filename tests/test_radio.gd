extends GutTest

## Off-tree surface tests for the Radio component. We never add_child it or run _ready (which builds the
## look-at outline and, with auto_fit_collider, touches global_transform — that fails GUT 9.6 off-tree).
## We build it with .new() and poke only the methods that don't need the tree. In-tree behaviour (the
## fallback player, the combat poll) is verified by manual playtest; the duck/settle logic is covered
## headlessly by test_radio_playback_state.gd.

const RADIO_SCRIPT := "res://scripts/components/radio.gd"

## Test doubles for the pause-freeze contract. The Radio is PROCESS_MODE_ALWAYS so its AUDIO DUCK survives a
## dialogue/menu tree-pause, but the note particles + the bounce (visual offset + rigid-body impulse) must FREEZE
## with the paused world — else notes keep spitting through a pause, and (worse) upward impulses PILE UP in a frozen
## RigidBody's linear_velocity and launch it (and anything standing on it) on unpause. Actually setting
## get_tree().paused inside a GUT run is unsafe (it freezes the runner — see test_dialogue.gd), so we override the
## two seams the freeze branches read (`_effects_frozen` = "world paused", `is_playing_music` = "music on") and drive
## _process / _physics_process OFF-TREE. Music is forced "on" so the effects WOULD run if the freeze didn't gate them.
class _FrozenRadio extends Radio:
	func _effects_frozen() -> bool: return true
	func is_playing_music() -> bool: return true

class _LiveRadio extends Radio:
	func _effects_frozen() -> bool: return false
	func is_playing_music() -> bool: return true

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
	assert_eq(r.look_name(), "[PH] Turn on Jukebox", "Off -> prompts to turn on")
	r._state.set_playing(true)
	assert_eq(r.look_name(), "[PH] Turn off Jukebox", "On -> prompts to turn off")
	r.free()

func test_look_name_falls_back_to_generic_when_unnamed() -> void:
	var r := _make()
	assert_eq(r.look_name(), "[PH] Turn on radio", "An unnamed radio uses a generic label")
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
	assert_false(r.duck_for_combat, "by default the radio takes precedence over the combat score (plays through a fight)")
	assert_false(r.duck_for_dialogue, "by default the radio plays THROUGH dialogue (only the gentle music-bus duck applies), never hiding")
	assert_true(r.show_music_note, "playing radios launch note particles by default")
	assert_eq(r.note_glyph, "♪", "the default particle glyph is a music note")
	assert_true(r.note_rainbow, "note particles cycle bright colors by default")
	assert_gt(r.note_height, 0.0, "note particles spawn above the radio")
	assert_gt(r.note_rise, 0.0, "note particles rise before disappearing")
	assert_gt(r.note_spread, 0.0, "note particles drift outward from the radio")
	assert_gt(r.note_emit_interval, 0.0, "note particles emit on a paced interval")
	assert_gt(r.note_lifetime, 0.0, "note particles self-free after a short life")
	assert_true(r.vibration_enabled, "playing radios bounce by default")
	assert_gt(r.vibration_visual_bounce, 0.0, "non-physics targets have a visible bounce amplitude")
	assert_gt(r.vibration_visual_side, 0.0, "non-physics targets have a tunable side wobble")
	assert_gt(r.vibration_rate, 0.0, "vibration rate must be positive")
	assert_gt(r.vibration_impulse, 0.0, "rigid-body radios get a tiny upward impulse while music plays")
	assert_gt(r.vibration_side_impulse, 0.0, "rigid-body vibration includes a small side jitter")
	r.free()

func test_playing_music_requires_a_live_audio_player() -> void:
	var r := _make()
	assert_false(r.is_playing_music(), "off-tree before _ready: no AudioStreamPlayer3D means no active note/bounce effect")
	r._state.set_playing(true)
	assert_false(r.is_playing_music(), "radio state alone is not enough for note particles/bounce; a stream must actually be playing")
	r.free()

func test_precedence_default_does_not_feed_combat_into_duck() -> void:
	# By default (duck_for_combat off) the radio takes precedence over the combat score: _process must NOT feed
	# combat into the duck state machine — it plays through the fight (MusicDirector mutes the bed instead).
	# Force the "a scan saw a fight" flag, then tick: the no-duck branch clears it back to false. Off-tree the
	# audio_player is null (guarded) and no NPCs are needed.
	var r := _make()
	r._state.set_playing(true)
	r._combat_now = true  # pretend a prior scan saw a fight
	r._process(0.1)
	assert_false(r._combat_now, "duck_for_combat off -> _process never arms combat (the radio plays through)")
	r.free()


func test_opt_in_combat_duck_still_scans() -> void:
	# Flip to the old behaviour: the scan runs again. Off-tree _any_npc_fighting reads "no combat" (null-guarded),
	# so _combat_now lands false here — but via the SCAN, not the skip. We assert the poll timer was consumed.
	var r := _make()
	r.duck_for_combat = true
	r._poll_t = 0.0
	r._process(0.1)
	assert_almost_eq(r._poll_t, r.poll_interval, 0.0001, "duck_for_combat on -> the combat scan runs and re-arms the poll timer")
	r.free()


func test_combat_poll_is_null_guarded_off_tree() -> void:
	# The combat scan reads get_tree(); a bare off-tree Radio has none. It must read "no combat", never crash
	# (mirrors MusicDirector's tree==null guard).
	var r := _make()
	assert_false(r._any_npc_fighting(), "no tree -> no combat, null-guarded")
	r.free()


func test_dialogue_duck_is_opt_in() -> void:
	# The radio no longer HIDES itself during a conversation: by default it plays through and only dips with the
	# music bus (the MusicDucker, since the &"radio" bus sends into &"music"). _dialogue_suppresses is the pure
	# gate _process feeds into the duck state machine — off by default, on only when the designer opts in.
	var r := _make()
	assert_false(r._dialogue_suppresses(true), "duck_for_dialogue off (default) -> an open conversation does NOT hide the radio")
	r.duck_for_dialogue = true
	assert_true(r._dialogue_suppresses(true), "duck_for_dialogue on -> restores the old behaviour: the radio ducks out for dialogue")
	assert_false(r._dialogue_suppresses(false), "no conversation -> no dialogue duck regardless of the toggle")
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

# --- Pinned single track (a specific song on a specific radio) ---

func test_pinned_track_wins_over_folder_and_player_override() -> void:
	# A pinned `track` is the highest-precedence source: it must resolve as the stream and SKIP the folder scan,
	# even when the player has set their own music folder in Options (Settings.music_folder).
	var r := _make()
	var found := r._scan_audio_folder("res://assets/audio/music")
	assert_gt(found.size(), 0, "need a shipped track to pin for this test")
	var song: AudioStream = load(found[0])
	assert_not_null(song, "a shipped track loads")
	r.track = song
	assert_eq(r._resolve_stream(), song, "a pinned track is the resolved stream (beats the folder)")
	r._load_playlist()
	assert_false(r._playlist.has_tracks(), "a pinned track skips the folder scan — the playlist stays empty")
	Settings.music_folder = "res://assets/audio/music"  # simulate the player picking their own folder
	r._load_playlist()
	assert_false(r._playlist.has_tracks(), "a pinned track also beats the player's Settings.music_folder override")
	assert_eq(r._resolve_stream(), song, "and still resolves to the pinned track")
	r.free()

func test_pinned_track_quality_text_is_the_song_filename() -> void:
	# NPCs score the actual SONG: a pinned track reports its own filename (not the radio name) to the scorer.
	var r := _make()
	r.radio_name = "Story Radio"
	var found := r._scan_audio_folder("res://assets/audio/music")
	assert_gt(found.size(), 0)
	r.track = load(found[0])
	assert_eq(r.quality_text(), found[0].get_file(), "a pinned track scores by its filename, not the radio name")
	r.free()

func test_pinned_track_clears_the_silent_warning() -> void:
	# With no folder tracks and no fallback a radio is "silent" (config warning); a pinned track clears it.
	var r := _make()
	r.music_folder = "res://does/not/exist"  # scans empty
	r.fallback_audio = null
	assert_gt(r._get_configuration_warnings().size(), 0, "no track/folder/fallback -> the silent warning fires")
	r.track = AudioStreamMP3.new()
	assert_eq(r._get_configuration_warnings().size(), 0, "a pinned track clears the silent warning")
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

# --- Pause-freeze: only the audio duck runs through a tree-pause; notes + bounce freeze with the world ---

func test_effects_frozen_is_false_off_tree() -> void:
	# The freeze predicate is is_inside_tree()-guarded FIRST: a bare off-tree instance (unit tests, or _process
	# driven before the node enters the tree) has no tree to be paused, so it reads false and the effects run as
	# before. Guards against "simplifying" it to a bare get_tree().paused, which would crash every off-tree driver.
	var r := _make()
	assert_false(r._effects_frozen(), "off-tree -> no tree to be paused -> effects not frozen (null-safe)")
	r.free()

func test_paused_world_freezes_note_emission_and_physics_bounce() -> void:
	# BUG 1 (notes spat out during a pause) + BUG 2 (radio builds up upward velocity and launches the player):
	# while the world is frozen, _process must NOT advance note emission and _physics_process must NOT run the
	# rigid-body vibration (each apply_central_impulse into a frozen body accumulates and fires on unpause).
	var r := _FrozenRadio.new()  # _effects_frozen()->true, is_playing_music()->true
	var rb := RigidBody3D.new()
	r.vibration_target = rb
	r._physics_vibration_phase = 1.25
	r._physics_process(0.05)
	assert_eq(r._physics_vibration_phase, 1.25,
		"frozen world -> _physics_process returns before the vibration: no impulse pumped, wave phase not advanced (BUG 2)")
	r._note_emit_t = 0.05
	r._process(0.1)
	assert_eq(r._note_emit_t, 0.05,
		"frozen world -> _process skips note emission: the emit timer is frozen, no ♪ spawned through the pause (BUG 1)")
	rb.free()
	r.free()

func test_unpaused_world_runs_note_emission_and_physics_bounce() -> void:
	# Contrapositive: with the SAME forced "music on" but NOT frozen, _process/_physics_process DO drive the
	# effects — proving the freeze guard (not some other condition) is what suppresses them above. The wave is
	# pre-seeded positive so the tick advances the phase WITHOUT crossing zero (no apply_central_impulse, which
	# would log a tracked engine error on an off-tree body).
	var r := _LiveRadio.new()  # _effects_frozen()->false, is_playing_music()->true
	var rb := RigidBody3D.new()
	r.vibration_target = rb
	r._physics_vibration_phase = 1.25
	r._physics_vibration_wave = 1.0  # already positive -> this tick can't zero-cross -> no impulse fired
	r._physics_process(0.05)
	assert_gt(r._physics_vibration_phase, 1.25,
		"unpaused + playing + RigidBody target -> _physics_process runs the vibration (wave phase advances)")
	r._note_emit_t = 0.05
	r._process(0.1)
	assert_ne(r._note_emit_t, 0.05,
		"unpaused + playing -> _process drives note emission (the emit timer moves)")
	rb.free()
	r.free()

func test_visual_bounce_also_freezes_with_the_world() -> void:
	# The SAME _process freeze guard covers the NON-RigidBody visual bounce (a table/shelf radio, where
	# _update_visual_vibration nudges the prop's local position instead of applying a physics impulse). A plain
	# Node3D target takes that visual path (RigidBody targets are handled by _physics_process instead). Frozen ->
	# _process skips it (phase held); live -> the phase advances. Closes the visual half of the cosmetic-freeze guard.
	var frozen := _FrozenRadio.new()  # _effects_frozen()->true
	var vt_frozen := Node3D.new()
	frozen.vibration_target = vt_frozen
	frozen._visual_vibration_phase = 0.5
	frozen._process(0.1)
	assert_eq(frozen._visual_vibration_phase, 0.5,
		"frozen world -> _process skips the visual bounce (phase held, prop frozen mid-wobble)")
	frozen.free()
	vt_frozen.free()

	var live := _LiveRadio.new()  # _effects_frozen()->false
	var vt_live := Node3D.new()
	live.vibration_target = vt_live
	live._visual_vibration_phase = 0.5
	live._process(0.1)
	assert_gt(live._visual_vibration_phase, 0.5,
		"unpaused + playing + non-RigidBody target -> _process runs the visual bounce (phase advances)")
	live.free()
	vt_live.free()

func test_target_grounded_is_false_off_tree() -> void:
	# The bounce impulse only fires while the body is grounded (_target_grounded). Off-tree there is no physics
	# world to query, so it must read false (skip the impulse) rather than deref a null world/space. Guards the
	# is_inside_tree() short-circuit that also keeps the existing off-tree vibration tests from touching physics.
	var r := _make()
	var rb := RigidBody3D.new()
	assert_false(r._target_grounded(rb), "off-tree RigidBody -> not grounded (no physics world); the kick safely skips")
	rb.free()
	r.free()
