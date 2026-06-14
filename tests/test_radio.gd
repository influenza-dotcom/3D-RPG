extends GutTest

## Off-tree surface tests for the Radio component. We never add_child it or run _ready (which builds the
## look-at outline and, with auto_fit_collider, touches global_transform — that fails GUT 9.6 off-tree).
## We build it with .new() and poke only the methods that don't need the tree. In-tree behaviour (the
## fallback player, the combat poll) is verified by manual playtest; the duck/settle logic is covered
## headlessly by test_radio_playback_state.gd.

const RADIO_SCRIPT := "res://scripts/components/radio.gd"

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
	assert_eq(r.playlist_uri, "", "no Spotify playlist by default (dormant until linked)")
	r.free()

func test_combat_poll_is_null_guarded_off_tree() -> void:
	# The combat scan reads get_tree(); a bare off-tree Radio has none. It must read "no combat", never crash
	# (mirrors MusicDirector's tree==null guard).
	var r := _make()
	assert_false(r._any_npc_fighting(), "no tree -> no combat, null-guarded")
	r.free()

func test_turn_on_falls_back_when_spotify_unavailable() -> void:
	# When Spotify is unavailable the radio must NOT engage it — it uses the local fallback, so _using_spotify
	# stays false. Force UNAVAILABLE by disabling Spotify for the test, regardless of any linked+enabled account
	# persisted in the env's settings.cfg (a real playtest link writes one). Set the var directly (not the
	# persisting setter) and restore, so settings.cfg is untouched.
	var prev_enabled := Settings.spotify_enabled
	Settings.spotify_enabled = false
	var r := _make()
	r.playlist_uri = "spotify:playlist:test"
	r._turn_on(null)  # null player -> toast guarded; no audio_player off-tree -> fallback play guarded
	assert_false(r._using_spotify, "Spotify disabled -> the radio uses the fallback, not Spotify")
	Settings.spotify_enabled = prev_enabled
	r.free()
