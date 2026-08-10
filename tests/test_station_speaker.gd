extends GutTest

## StationSpeaker — the shared PANEL VOICE every self-serve station answers with (shop / heal / level-up /
## respec / chip-install / chess / atm). It replaced the Atm's bespoke speaker when the chirp stopped being an
## ATM feature, so the contract worth pinning is the SEAM, not the sound:
##
##   * `chirp(station)` is STATIC, type-agnostic and null-safe — a screen calls it on a plain Node and never
##     branches. It RETURNS whether it spoke, and the screens feed that straight into
##     `ModalMenu.grab_mouse(not chirped)` so a machine with a voice replaces the generic UI sting instead of
##     doubling it. If chirp() ever returned true for a mute station, every kiosk would open in silence.
##   * `ensure(station)` gives a bare prefab a default voice but NEVER overwrites an authored one — that is the
##     whole designer surface: drop a StationSpeaker child to retune, or drop one with `open_sound` cleared to
##     MUTE the machine. A greedy ensure() would make the mute switch impossible.
##
## Speakers are exercised IN TREE (add_child_autofree): the AudioStreamPlayer3D is built in _ready, so an
## off-tree instance is deliberately mute — which is itself one of the cases below.


func _station() -> Node3D:
	return Node3D.new()  # a stand-in for any station component — the seam is type-agnostic by design


func test_a_station_with_no_speaker_is_silent_and_says_so() -> void:
	var host := _station()
	add_child_autofree(host)
	assert_null(StationSpeaker.find_speaker(host), "a bare station has no voice")
	assert_false(StationSpeaker.chirp(host), "…so chirp() reports false — which is what makes the screen play its generic sting instead")


func test_the_static_seam_is_null_safe() -> void:
	# Every station screen calls chirp() on a duck-typed Node it only checked for validity. A freed or null
	# station must be a quiet no-op, not a crash on the open path.
	assert_false(StationSpeaker.chirp(null), "a null station never crashes the open path")
	assert_null(StationSpeaker.find_speaker(null), "…and finding on null is null")


func test_ensure_gives_a_bare_station_a_voice_and_is_idempotent() -> void:
	var host := _station()
	add_child_autofree(host)
	var sp := StationSpeaker.ensure(host)
	assert_not_null(sp, "ensure() builds the default panel voice")
	assert_eq(StationSpeaker.ensure(host), sp, "…and calling it again returns the SAME one (a station's _ready must never stack speakers)")
	assert_eq(StationSpeaker.find_speaker(host), sp, "…found by TYPE, so renaming the node in a scene can't silence the machine")
	assert_not_null(sp.open_sound, "the default voice ships with a clip assigned")
	assert_eq(sp.bus, &"speaker", "…on the tinny speaker bus — the filter chain IS the cheap-plastic sound")


func test_an_authored_speaker_always_wins_which_is_the_mute_switch() -> void:
	# ⭐The designer surface. A hand-placed StationSpeaker is never replaced, so clearing its clip is how you
	# author a deliberately silent terminal. If ensure() overwrote it, muting a machine would be impossible.
	var host := _station()
	var authored := StationSpeaker.new()
	authored.open_sound = null
	host.add_child(authored)
	add_child_autofree(host)
	assert_eq(StationSpeaker.ensure(host), authored, "ensure() adopts the authored speaker rather than adding a second")
	assert_false(StationSpeaker.chirp(host), "…and a cleared clip is a MUTE station: chirp() reports false, so the screen falls back to the generic sting")


func test_a_live_speaker_chirps_and_reports_it() -> void:
	var host := _station()
	var sp := StationSpeaker.new()
	host.add_child(sp)
	add_child_autofree(host)
	assert_true(StationSpeaker.chirp(host), "a station with a voice speaks, and says it did — that return is what suppresses the duplicate UI sting")


func test_the_player_processes_through_a_pause() -> void:
	# ⭐The trap this component was extracted with. A PAUSABLE AudioStreamPlayer3D fades itself to silence on
	# NOTIFICATION_PAUSED — measured at ~15 ms in, with no error and nothing logged. The station screens are
	# real-time now, but one opened from a CONVERSATION still runs under DialogueManager's pause, so the player
	# must be ALWAYS or that path silently loses the chirp.
	var host := _station()
	var sp := StationSpeaker.new()
	host.add_child(sp)
	add_child_autofree(host)
	var voice := sp.get_node_or_null("Player") as AudioStreamPlayer3D
	assert_not_null(voice, "the speaker builds its AudioStreamPlayer3D at _ready")
	assert_eq(voice.process_mode, Node.PROCESS_MODE_ALWAYS,
		"the voice must process ALWAYS — a dialogue-hosted station opens under the conversation's pause and a pausable player dies mid-chirp")


func test_a_missing_bus_degrades_to_sfx_rather_than_master() -> void:
	# A renamed or deleted bus would otherwise land the chirp on Master, where no Options slider and no
	# death-cinematic duck reach it — the loudest possible failure mode for the quietest possible sound.
	var host := _station()
	var sp := StationSpeaker.new()
	sp.bus = &"a_bus_that_does_not_exist"
	host.add_child(sp)
	add_child_autofree(host)
	var voice := sp.get_node_or_null("Player") as AudioStreamPlayer3D
	assert_eq(voice.bus, &"sfx", "a missing bus falls back to sfx (with a warning), never Master")
