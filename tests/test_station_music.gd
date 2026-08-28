extends GutTest

## Contract tests for the STATION RADIO — the looping shop theme a self-serve machine plays out of its own
## panel speaker while its screen is awake (managers/StationMusic.gd + resources/tuning/StationMusicSettings.tres
## + the `station_music` bus + the `station_music` flag on InputManager's modal registry).
##
## Nothing here can HEAR a filter, so the tests pin the four things that break silently and are invisible in a
## playtest until someone happens to A/B them:
##   1. The registry SET — which screens play the bed. It must stay exactly the set that answers with a
##      StationSpeaker chirp; a new screen row that forgets the key would crash the gate outright.
##   2. The bus resolves, and the AUTHORED bus name in the tuning resource is a real bus (a typo drops the bed
##      onto the fallback with only a warning). Chain PARITY with `speaker` lives in test_audio_bus_hygiene.gd.
##   3. The no-immediate-repeat picker — pure and static precisely so it can be proven with no RNG, no audio
##      device and no tree.
##   4. The live autoload's resting posture: PROCESS_MODE_ALWAYS (a dialogue-hosted station opens under the
##      conversation's tree pause and a pausable player silences itself with nothing logged), silent, stopped,
##      and NOT claiming the tier flag at rest.
##
## The bed is an autoload, so the live-node checks read the real one rather than building a second; the pure
## logic is exercised off-tree, per the "don't run _ready() in a unit test" rule.

const STATION_MUSIC_SCRIPT := preload("res://managers/StationMusic.gd")

# --- The registry set: which screens count -----------------------------------------------------------

func test_the_station_music_set_is_exactly_the_screens_with_a_panel_speaker() -> void:
	# THE design rule, and the reason the flag lives in the registry beside blocks_tabs rather than in a
	# hand-written list next to the bed: the music plays through a clone of the StationSpeaker's filter chain,
	# so it must play under exactly the screens that answer with a StationSpeaker chirp. If those two sets ever
	# drift, a machine chirps and then plays nothing (or plays music without ever having spoken).
	var expected: Array = [ShopScreen, LevelUpScreen, RespecScreen, HealScreen, AtmScreen, ChipInstallScreen,
			WeaponBenchScreen, ChessScreen]
	InputManager._ensure_modal_reg()
	var actual: Array = []
	for e in InputManager._modal_reg:
		if e.station_music:
			actual.append(e.screen)
	assert_eq(actual.size(), expected.size(),
		"the station-radio set has %d screens but should have %d — if you added a station screen, say so in "
		% [actual.size(), expected.size()]
		+ "this test too; if you added a NON-station screen, it should be station_music = false")
	for screen in expected:
		assert_true(actual.has(screen),
			"a station screen is missing its `station_music = true` registry row — it will chirp at you and "
			+ "then sit in silence")

func test_every_registry_row_carries_the_station_music_key() -> void:
	# A row that omits the key throws on `e.station_music` the first time any station screen opens — i.e. the
	# crash lands on the next person to register a screen, far from the row they wrote. Catch it here instead.
	InputManager._ensure_modal_reg()
	for e in InputManager._modal_reg:
		assert_true(e.has("station_music"),
			"a modal registry row is missing the `station_music` key — every row must carry BOTH flags, and "
			+ "writing `false` with a one-line reason is how the next author sees why a screen was left out")

func test_station_music_screens_are_all_hand_owning_screens() -> void:
	# A screen that plays a shop theme but does NOT own the player's hands would let a Pip-Boy tab open over it,
	# stacking a second menu under the machine's music. Not a hard law of the universe, but every station screen
	# satisfies it today and a violation is far more likely to be an oversight than a design choice.
	InputManager._ensure_modal_reg()
	for e in InputManager._modal_reg:
		if e.station_music:
			assert_true(e.blocks_tabs,
				"a `station_music` screen that isn't `blocks_tabs` lets a Pip-Boy tab open over the terminal")

func test_the_gate_is_false_with_nothing_open() -> void:
	assert_false(InputManager.any_station_music_open(),
		"no menu is open in a headless suite — a true here means a screen's is_open() latch is stuck, which "
		+ "would leave the shop radio playing over the whole game")

# --- Routing -----------------------------------------------------------------------------------------

func test_the_authored_bus_name_is_a_real_bus() -> void:
	# A typo'd bus name doesn't error — it degrades to `music` with a push_warning, so the feature keeps
	# working and quietly loses the entire tinny character that IS the feature.
	var cfg: StationMusicSettings = GameSettings.station_music
	assert_gte(AudioServer.get_bus_index(cfg.bus), 0,
		"StationMusicSettings.bus '%s' is not a bus in default_bus_layout.tres — the bed falls back to a "
		% cfg.bus + "clean `music` bed with no panel-speaker filtering")

func test_the_tuning_group_is_registered_on_game_settings() -> void:
	assert_true(GameSettings.station_music is StationMusicSettings,
		"GameSettings.station_music must preload StationMusicSettings.tres — a missing group is a null-deref "
		+ "on the autoload's very first frame")

func test_fades_and_hold_are_non_negative_and_the_floor_is_below_the_level() -> void:
	var cfg: StationMusicSettings = GameSettings.station_music
	assert_gte(cfg.fade_in, 0.0, "fade_in seconds cannot be negative")
	assert_gte(cfg.fade_out, 0.0, "fade_out seconds cannot be negative")
	assert_gte(cfg.hold_seconds, 0.0, "hold_seconds cannot be negative")
	assert_lt(cfg.silent_db, cfg.volume_db,
		"silent_db must sit BELOW volume_db or 'fading in' is a no-op (equal) or actually fades DOWN")

# --- The authored playlist ---------------------------------------------------------------------------

func test_the_shipped_playlist_is_authored_and_every_slot_is_filled() -> void:
	# The project ships four placeholder shop themes. If they are ever purged for licensing (see ATTRIBUTION.md
	# §A) the layer goes inert BY DESIGN — at that point delete this test, don't weaken it.
	var tracks: Array[AudioStream] = GameSettings.station_music.tracks
	assert_gt(tracks.size(), 0, "StationMusicSettings.tres should author at least one station track")
	for i in tracks.size():
		assert_not_null(tracks[i],
			"station track slot %d is null — an empty slot is tolerated at runtime (it is filtered out) but "
			% i + "in the shipped resource it means an ext_resource failed to resolve")

func test_every_authored_track_can_be_forced_to_loop() -> void:
	# ⭐This is not theoretical: all four shipped tracks import with loop = false (Godot's default for .mp3),
	# so WITHOUT the forced loop every one of them stops dead 45-85 seconds into a shop visit. The force is
	# what makes a dropped-in file "just work" without the designer knowing about the Import dock.
	for t in GameSettings.station_music.tracks:
		if t == null:
			continue
		assert_true(LoopableStream.loops(LoopableStream.looping_copy(t, "test")),
			"'%s' could not be forced to loop — the bed would stop dead partway through a shop visit"
			% t.resource_path.get_file())

# --- The no-immediate-repeat picker (pure + static: no RNG, no audio, no tree) ------------------------

func test_the_picker_never_returns_the_track_that_just_played() -> void:
	# "One of these songs" with four tracks and a naive roll repeats a quarter of the time, and a listener
	# hears the repeat, not the randomness.
	for last in 4:
		for step in 20:
			var roll := float(step) / 20.0
			var got: int = STATION_MUSIC_SCRIPT.pick_next_index(4, last, roll)
			assert_ne(got, last, "pick_next_index(4, last=%d, roll=%.2f) returned the previous track" % [last, roll])
			assert_true(got >= 0 and got < 4,
				"pick_next_index(4, last=%d, roll=%.2f) returned %d, outside [0,4)" % [last, roll, got])

func test_the_picker_reaches_every_other_track() -> void:
	# The skip-past-last construction would be a bug if it made one index unreachable (a "random" playlist that
	# only ever alternates between two tracks).
	var seen := {}
	for step in 40:
		seen[STATION_MUSIC_SCRIPT.pick_next_index(4, 1, float(step) / 40.0)] = true
	assert_eq(seen.keys().size(), 3, "from last=1 the picker must reach all THREE other tracks, got %s" % str(seen.keys()))

func test_the_picker_degrades_on_the_edge_cases() -> void:
	# A one-track playlist has nowhere else to go; an empty one must report "nothing" rather than index 0.
	assert_eq(STATION_MUSIC_SCRIPT.pick_next_index(1, 0, 0.5), 0, "a single-track playlist must replay that track")
	assert_eq(STATION_MUSIC_SCRIPT.pick_next_index(0, -1, 0.5), -1, "an empty playlist must return -1, not an index")
	# last < 0 (first pick) and last out of range (a track edited out of the playlist under us) both mean
	# "the whole list is fair game" — never a clamp onto one end.
	for last in [-1, 99]:
		var seen := {}
		for step in 40:
			seen[STATION_MUSIC_SCRIPT.pick_next_index(4, last, float(step) / 40.0)] = true
		assert_eq(seen.keys().size(), 4,
			"with last=%d every track must be reachable, got %s" % [last, str(seen.keys())])

# --- The live autoload's resting posture --------------------------------------------------------------

func test_the_autoload_rests_silent_and_stopped() -> void:
	assert_not_null(StationMusic, "the StationMusic autoload must be registered in project.godot")
	assert_false(StationMusic.playing, "nothing is open in a headless suite — the bed must not be playing")
	assert_false(StationMusic.autoplay, "autoplay would start a shop theme over the main menu on boot")
	assert_false(StationMusic.is_bed_wanted(),
		"is_bed_wanted() must be false at rest — MusicDirector stands the combat score DOWN for it, so a "
		+ "stuck true silences the whole dynamic score")
	assert_eq(StationMusic.volume_db, GameSettings.station_music.silent_db,
		"the bed must rest at silent_db so its first fade-in starts from silence, not mid-level")

func test_the_autoload_survives_the_dialogue_tree_pause() -> void:
	# ⭐The trap this pins: a station screen opened from a CONVERSATION opens under DialogueManager's tree
	# pause, and a pausable AudioStreamPlayer silences itself ~15 ms in with no error and nothing logged.
	# Exactly the failure StationSpeaker's own voices are PROCESS_MODE_ALWAYS to avoid.
	assert_eq(StationMusic.process_mode, Node.PROCESS_MODE_ALWAYS,
		"StationMusic must be PROCESS_MODE_ALWAYS or a dialogue-hosted shop plays in silence")

func test_the_autoload_is_not_in_the_modal_registry() -> void:
	# It is an audio layer, not a screen: registering it would put it in close_all_modals' sweep and in the
	# don't-stack-a-menu guard, both nonsense for a music bed.
	InputManager._ensure_modal_reg()
	for e in InputManager._modal_reg:
		assert_ne(e.screen, StationMusic, "StationMusic is a music layer, not a modal screen — unregister it")

# --- Off-tree structure -------------------------------------------------------------------------------

func test_a_bare_instance_tolerates_an_empty_playlist() -> void:
	# The post-ATTRIBUTION-purge state: clearing `tracks` must make the layer inert, not error.
	var bed = STATION_MUSIC_SCRIPT.new()
	var empty := StationMusicSettings.new()
	assert_eq(bed._playable_indices(empty).size(), 0, "an empty playlist must yield no playable indices")
	assert_null(bed._pick_stream(empty), "an empty playlist must pick nothing rather than erroring")
	empty = null
	bed.free()

func test_a_bare_instance_skips_null_playlist_slots() -> void:
	# A designer clearing ONE row in the inspector must not make the machine play silence.
	var bed = STATION_MUSIC_SCRIPT.new()
	var cfg := StationMusicSettings.new()
	cfg.tracks = [null, AudioStreamMP3.new(), null] as Array[AudioStream]
	var live: Array[int] = bed._playable_indices(cfg)
	assert_eq(live, [1] as Array[int], "only the non-null slot is playable, got %s" % str(live))
	cfg = null
	bed.free()
