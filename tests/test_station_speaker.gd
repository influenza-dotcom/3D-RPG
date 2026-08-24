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
##   * `applaud(station)` is the REWARD cue in the same static, null-safe shape — the machine clapping for you
##     out of the same panel. `Atm.deposit` fires it on the portion of a deposit that RETIRES DEBT. The two
##     cues own SEPARATE AudioStreamPlayer3Ds, which is the contract worth pinning here: one shared player
##     would mean re-opening the terminal mid-applause chopped the celebration off, and a per-cue volume trim
##     would be impossible.
##
## Speakers are exercised IN TREE (add_child_autofree): the AudioStreamPlayer3Ds are built in _ready, so an
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
	# applaud() is called from INSIDE Atm.deposit — a transaction that has already moved money and awarded
	# credit standing. A crash there would roll nothing back, so it has to be at least as forgiving as chirp.
	assert_false(StationSpeaker.applaud(null), "a null station never crashes the repayment path either")


func test_ensure_gives_a_bare_station_a_voice_and_is_idempotent() -> void:
	var host := _station()
	add_child_autofree(host)
	var sp := StationSpeaker.ensure(host)
	assert_not_null(sp, "ensure() builds the default panel voice")
	assert_eq(StationSpeaker.ensure(host), sp, "…and calling it again returns the SAME one (a station's _ready must never stack speakers)")
	assert_eq(StationSpeaker.find_speaker(host), sp, "…found by TYPE, so renaming the node in a scene can't silence the machine")
	assert_not_null(sp.open_sound, "the default voice ships with a clip assigned")
	assert_not_null(sp.applause_sound, "…and so does the reward clap, so a bare Atm applauds a repayment with zero authoring")
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


func test_a_live_speaker_applauds_and_reports_it() -> void:
	var host := _station()
	var sp := StationSpeaker.new()
	host.add_child(sp)
	add_child_autofree(host)
	assert_true(StationSpeaker.applaud(host), "a station with a voice claps for you, and says it did")
	var clap := sp.get_node_or_null("Applause") as AudioStreamPlayer3D
	assert_not_null(clap, "the applause has its OWN voice node, built at _ready beside the chirp's")
	assert_true(clap.playing, "…and applaud() actually started it")


func test_clearing_only_the_applause_leaves_the_chirp_alone() -> void:
	# ⭐The two cues are INDEPENDENT authoring choices, not one on/off switch. A designer who wants a terminal
	# that still wakes up with a chirp but takes your repayment without the fanfare clears `applause_sound`
	# alone — if either clip's null check reached the other player, that terminal would go completely silent.
	var host := _station()
	var sp := StationSpeaker.new()
	sp.applause_sound = null
	host.add_child(sp)
	add_child_autofree(host)
	assert_false(StationSpeaker.applaud(host), "a cleared clap is a mute celebration")
	assert_true(StationSpeaker.chirp(host), "…and the machine still chirps when its screen wakes")


func test_the_two_cues_never_cut_each_other() -> void:
	# ⭐WHY THEY GET SEPARATE PLAYERS. play() RESTARTS a player, so one shared voice would mean re-opening the
	# terminal mid-applause chopped the several-second celebration off with the chirp (and vice versa). The
	# self-cutting is only wanted WITHIN a cue — a second repayment restarts the clap rather than stacking one
	# crowd on another. This is the assertion that fails the day someone "simplifies" the two voices into one.
	var host := _station()
	var sp := StationSpeaker.new()
	host.add_child(sp)
	add_child_autofree(host)
	StationSpeaker.applaud(host)
	StationSpeaker.chirp(host)  # the player closed and re-opened the terminal while it was still clapping
	var clap := sp.get_node_or_null("Applause") as AudioStreamPlayer3D
	var chirp := sp.get_node_or_null("Player") as AudioStreamPlayer3D
	assert_true(clap.playing, "the applause survives an open cue landing on top of it")
	assert_true(chirp.playing, "…and the chirp still sounds — two voices, two cues, neither one yielding")
	assert_ne(clap, chirp, "the cues must not share a player, which is what makes the above possible")


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
	# The applause is MORE exposed to this than the chirp, not less: it runs for seconds rather than a blink,
	# so any pause the player triggers mid-celebration (opening a menu, dying to a shot they took while banking)
	# falls inside its clip. A voice built by a helper that forgot the flag would fail here, not in a playtest.
	var clap := sp.get_node_or_null("Applause") as AudioStreamPlayer3D
	assert_not_null(clap, "…and a second one for the reward clap")
	assert_eq(clap.process_mode, Node.PROCESS_MODE_ALWAYS,
		"the applause must process ALWAYS too — it is long enough that a pause almost certainly lands inside it")


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
	var clap := sp.get_node_or_null("Applause") as AudioStreamPlayer3D
	assert_eq(clap.bus, &"sfx", "…and BOTH voices take the same fallback — one routed cue and one orphan on Master would be worse than either")
