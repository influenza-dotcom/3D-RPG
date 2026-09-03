extends GutTest

## Contract tests for the death cinematic's MIX (scripts/player/death_mix.gd) — the world duck the sting
## rides over. Covers the failures that are SILENT at runtime:
##   1. The ROUTING INVARIANT. The sting bus must exist, and must NOT be one of the buses the cinematic
##      ducks. Break either and the sting is simply inaudible (or worse, blares) with no error anywhere —
##      it is the one wiring mistake that un-does the whole feature.
##   2. The DELEGATION. Player's cinematic reaches DeathMix through exactly four seams, one of them on each
##      death-exit path. Dropping any single one leaves a GLOBAL bus ducked into the next life on exactly
##      one death mode — the nastiest shape this bug takes, because it reproduces on one branch only.
##      Pinned by source (the tests/test_npc_home_return.gd idiom): the cinematic is a long in-tree tween a
##      unit test must not run, and the Player's _ready() must never run in a test either.
## DeathMix itself is built OFF-TREE (.new() without add_child, so _ready never runs) — no audio device
## touched, no bus written.

const MIX_SCRIPT := preload("res://scripts/player/death_mix.gd")
const PLAYER_SOURCE := "res://scripts/player/player.gd"

# --- The routing invariant --------------------------------------------------------------------------

func test_the_sting_bus_exists_in_the_bus_layout() -> void:
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	assert_gte(AudioServer.get_bus_index(fb.death_sting_bus), 0,
		"death_sting_bus '%s' is not a bus in default_bus_layout.tres — the sting would fall back to Master" % fb.death_sting_bus)

func test_the_cinematic_does_not_duck_its_own_soundtrack() -> void:
	# THE load-bearing assert. Every bus chain in Godot terminates at Master, so the ONLY way a sound
	# survives the cinematic is to sit on a bus that is not in this list (nor a child of one).
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	assert_false(fb.death_cinematic_buses.has(fb.death_sting_bus),
		"death_sting_bus '%s' is also in death_cinematic_buses — the cinematic would duck its own soundtrack" % fb.death_sting_bus)

func test_every_ducked_bus_resolves() -> void:
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	assert_gt(fb.death_cinematic_buses.size(), 0,
		"death_cinematic_buses is empty — the death cinematic would duck nothing at all")
	for bus: StringName in fb.death_cinematic_buses:
		assert_gte(AudioServer.get_bus_index(bus), 0,
			"death_cinematic_buses names '%s', which is not a bus in default_bus_layout.tres" % bus)

func test_the_sting_slider_bus_is_a_real_slider_when_set() -> void:
	# Blank is legal (Master-only). A non-blank name must be a bus the Options menu actually exposes, or
	# DeathMix would fold a slider that can never move into the sting's level.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	if fb.death_sting_slider_bus == &"":
		pass_test("death_sting_slider_bus is blank — the sting is governed by Master only, which is legal")
		return
	assert_true(Settings.VOLUME_BUSES.has(fb.death_sting_slider_bus),
		"death_sting_slider_bus '%s' has no Options volume slider (Settings.VOLUME_BUSES)" % fb.death_sting_slider_bus)

func test_sting_timings_are_sane() -> void:
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	assert_gte(fb.death_sting_release, 0.0, "death_sting_release seconds cannot be negative (0 = ring out naturally)")
	assert_gte(fb.death_sting_sync_point, 0.0, "death_sting_sync_point seconds cannot be negative")
	assert_gte(fb.death_sting_fade_in, 0.0, "death_sting_fade_in seconds cannot be negative (0 = instant on)")
	if fb.death_sting != null and fb.death_sting_sync_point > 0.0:
		# The swell must finish long before the beat the whole cinematic is scored to, or the final chord
		# arrives while the sting is still ramping and lands under-level against the returning world.
		assert_lt(fb.death_sting_fade_in, fb.death_sting_sync_point,
			"the %.2fs swell must complete well before the %.2fs sync point (the final chord)"
			% [fb.death_sting_fade_in, fb.death_sting_sync_point])
		assert_lte(fb.death_sting_sync_point, fb.death_sting.get_length(),
			("death_sting_sync_point %.2fs is past the end of a %.2fs clip — the respawn would be held on a "
			+ "black screen listening to nothing (DeathMix clamps it, but the authored value is wrong)")
			% [fb.death_sting_sync_point, fb.death_sting.get_length()])
	assert_gte(fb.death_world_residue, 0.0, "death_world_residue is a 0..1 fraction of the world's configured level")
	assert_lte(fb.death_world_residue, 1.0, "death_world_residue above 1.0 would make the world LOUDER as you die")

# --- The sting must be heard IN FULL ----------------------------------------------------------------

func test_the_sting_does_not_start_on_the_killing_blow() -> void:
	# A slight offset, deliberately: landing on the same frame as the killing blow reads as part of the
	# gunshot rather than as a reaction to it.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	assert_gte(fb.death_sting_start_delay, 0.0, "death_sting_start_delay cannot be negative")
	if fb.death_sting != null:
		assert_gt(fb.death_sting_start_delay, 0.0,
			"a sting is authored but death_sting_start_delay is 0 — it would hit on the killing blow")

func test_the_screen_fade_in_lands_on_the_stings_sync_point() -> void:
	# THE beat the whole cinematic is scored to: the sting's final chord must attack on the same frame
	# _fade_in_from_black() starts. The card's hold is the only slack in the timeline, so this is really a
	# check that card_hold_seconds() solved it correctly — and it fails the moment anyone retunes
	# death_sequence_time / death_card_fade_time / death_card_gap without re-checking the arithmetic.
	var mix: DeathMix = MIX_SCRIPT.new()
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	var sync: float = mix.sting_sync_time()
	if sync <= 0.0:
		pass_test("no sync point in play (no clip, muted slider, or death_sting_sync_point opted out of)")
		mix.free()
		return
	var respawn_at: float = fb.death_sequence_time + maxf(fb.death_card_delay, 0.0) + fb.death_card_fade_time \
		+ mix.card_hold_seconds() + fb.death_card_fade_time + fb.death_card_gap
	# Only exact while the derived hold is above the respawn_delay floor; if the floor won, the cinematic is
	# simply too short to reach the chord and the alignment is impossible rather than wrong.
	if mix.card_hold_seconds() <= fb.respawn_delay:
		pass_test("respawn_delay floor dominates — the cinematic is shorter than the sync point, so no alignment")
		mix.free()
		return
	assert_almost_eq(respawn_at, sync, 0.01,
		("the screen starts fading in at %.3fs but the sting's sync point lands at %.3fs — the final chord "
		+ "would miss the fade-in by %.3fs") % [respawn_at, sync, respawn_at - sync])
	mix.free()

func test_the_sting_rings_on_past_the_respawn() -> void:
	# THE invariant this timing exists for: the game must come back UNDER a sting that is still finishing,
	# not after one that already stopped (a black screen waiting on silence) and not by cutting one off.
	# Asserted against the real authored clip length, so swapping in a longer clip fails here rather than in
	# a playtest.
	var mix: DeathMix = MIX_SCRIPT.new()
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	var sting_end: float = mix.sting_end_time()
	if sting_end <= 0.0:
		pass_test("no sting will play (no clip authored, or its slider is muted) — nothing to overlap")
		mix.free()
		return
	# The cinematic's own timeline: phase 1, the settle-on-black beat, card fade in, the hold, card fade
	# out, the black gap.
	var respawn_at: float = fb.death_sequence_time + maxf(fb.death_card_delay, 0.0) + fb.death_card_fade_time \
		+ mix.card_hold_seconds() + fb.death_card_fade_time + fb.death_card_gap
	var overlap: float = sting_end - respawn_at
	assert_gt(overlap, 0.0,
		("the sting ends at %.2fs, at or before the respawn at %.2fs — the world would fade back in over "
		+ "silence instead of under the clip's tail") % [sting_end, respawn_at])
	mix.free()

func test_the_sting_is_not_force_faded_by_default() -> void:
	# The clip's own decay IS the fade. A forced ramp to silence is perceptually over long before it
	# mathematically finishes, so it amputates the tail and reads as the audio being cut — the exact
	# complaint this default exists to answer. A designer may still opt in for a clip that overstays.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	assert_gte(fb.death_sting_release, 0.0, "death_sting_release seconds cannot be negative")
	if fb.death_sting_release <= 0.0:
		pass_test("death_sting_release is 0 — the sting rings out to its natural end, which is the default")
		return
	# If someone DOES opt in, the fade must at least cover the tail that is still to play, or it cuts.
	var mix: DeathMix = MIX_SCRIPT.new()
	var tail: float = mix.sting_end_time() - mix.sting_sync_time()
	assert_gte(fb.death_sting_release, tail,
		("death_sting_release %.2fs is shorter than the %.2fs of clip still to play at the respawn — the "
		+ "remainder would be cut off") % [fb.death_sting_release, tail])
	mix.free()

func test_the_card_hold_never_shortens_the_original_cinematic() -> void:
	# respawn_delay is a FLOOR, not a replacement: a short clip (or none) must leave the old snappy timing
	# exactly as it was.
	var mix: DeathMix = MIX_SCRIPT.new()
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	assert_gte(mix.card_hold_seconds(), fb.respawn_delay,
		"the derived card hold must never drop below respawn_delay")
	mix.free()

func test_sting_end_time_is_zero_when_nothing_will_play() -> void:
	# The cinematic stalls its card on this number, so a null clip MUST report 0 rather than a bare delay —
	# otherwise clearing death_sting would still stretch the death screen for a sting that never sounds.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	var kept: AudioStream = fb.death_sting
	fb.death_sting = null
	var mix: DeathMix = MIX_SCRIPT.new()
	var reported: float = mix.sting_end_time()
	var hold: float = mix.card_hold_seconds()
	fb.death_sting = kept  # restore before asserting, so a failure can't poison the rest of the suite
	mix.free()
	assert_eq(reported, 0.0, "with no clip authored the sting end time must be 0, not the bare start delay")
	assert_eq(hold, fb.respawn_delay, "with no clip authored the card must hold for exactly respawn_delay")

# --- The component's method surface -----------------------------------------------------------------

func test_death_mix_exposes_the_cinematic_seams() -> void:
	var mix: DeathMix = MIX_SCRIPT.new()
	for seam in ["begin", "set_world_duck", "restore_world", "begin_revive", "release_sting", "sting_end_time", "sting_sync_time", "card_hold_seconds"]:
		assert_true(mix.has_method(seam), "DeathMix must expose %s() — Player's cinematic calls it" % seam)
	mix.free()

func test_death_mix_starts_un_ducked() -> void:
	# _exit_tree() restores only when _ducked; a component that boots believing it owes a restore would
	# write the buses on any teardown that never dies.
	var mix: DeathMix = MIX_SCRIPT.new()
	assert_false(mix._ducked, "DeathMix must not believe it owes the world a restore before begin() runs")
	mix.free()

# --- Bus ownership: nothing else may write a bus the cinematic is animating -------------------------

func test_bus_ownership_starts_and_stays_clear() -> void:
	# A leaked `true` here would silence the ADS and conversation music ducks for the rest of the session,
	# so the static must read false whenever no death is in flight — including right now, in a fresh suite.
	for bus: StringName in GameSettings.player_feedback.death_cinematic_buses:
		assert_false(DeathMix.owns_bus(bus),
			"DeathMix claims to own '%s' with no death in flight — the static leaked" % bus)

func test_the_music_duckers_stand_down_while_the_cinematic_owns_the_bus() -> void:
	# Pinned by source: both duckers write absolute dB to the SAME bus DeathMix re-asserts every frame, and
	# the revive hands the player back input BEFORE the world finishes swelling — so ADSing (or opening a
	# conversation) across a respawn is reachable and would otherwise slam the music up and snap it back.
	var scope := FileAccess.get_file_as_string("res://scripts/player/scope_coordinator.gd")
	assert_true(scope.contains("DeathMix.owns_bus(SCOPE_MUSIC_BUS)"),
		"the ADS music duck must stand down while the death cinematic owns the music bus")
	var ducker := FileAccess.get_file_as_string("res://scripts/dialogue/music_ducker.gd")
	assert_true(ducker.contains("DeathMix.owns_bus(MUSIC_BUS)"),
		"the conversation music duck must stand down while the death cinematic owns the music bus")

func test_every_bus_the_cinematic_ducks_is_one_it_claims() -> void:
	# The guard is only sound if ownership covers exactly what _apply_duck writes — if the two lists ever
	# diverge, a ducker would stand down for a bus nobody owns, or fight one nobody guards.
	var src := FileAccess.get_file_as_string("res://scripts/player/death_mix.gd")
	assert_true(src.contains("_owned_buses = GameSettings.player_feedback.death_cinematic_buses.duplicate()"),
		"ownership must be claimed from the same designer list _apply_duck iterates")

# --- The SKIP and the song (a click fast-forwards the cinematic) --------------------------------------

func test_release_sting_is_inert_when_nothing_is_playing() -> void:
	# The opt-in release runs on skipped deaths where no sting was ever going to sound (no clip authored, or
	# a muted slider). It must be a silent no-op there, not a stop() on a dead player or a tween built
	# off-tree.
	var mix: DeathMix = MIX_SCRIPT.new()
	mix.release_sting(0.35)
	assert_false(mix.playing, "release_sting must leave a silent mix silent")
	assert_false(mix._ducked, "release_sting is about the sting alone — it must not touch the world duck")
	mix.free()

func test_a_skipped_death_plays_the_song_out_in_full() -> void:
	# THE DEFAULT, and the whole point of the knob shipping at 0: a click fast-forwards the PICTURES. The
	# sting runs on DeathMix's own wall-clock and cannot ride the tween the skip speeds up, so a release
	# would shorten no part of the death — it would only delete the back half of the track.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	assert_gte(fb.death_skip_sting_release, 0.0, "death_skip_sting_release seconds cannot be negative")
	if fb.death_skip_sting_release <= 0.0:
		pass_test("death_skip_sting_release is 0 — a skipped death lets the song play out in full")
		return
	# A designer who DOES opt in gets a get-out-of-the-way ramp, not a mix choice: the player is already back
	# in the world, so it has to be over before the world has finished arriving.
	assert_lte(fb.death_skip_sting_release, fb.spawn_fade_in_time,
		"an opted-in skip release must be gone by the time the world has finished fading back in")

func test_the_sting_release_is_gated_on_the_skip_and_the_knob() -> void:
	# TWO gates, both load-bearing. Drop the _death_skipped latch and EVERY death fades, reversing the
	# never-fade rule (test_the_sting_is_not_force_faded_by_default); drop the knob test and every SKIPPED
	# death fades, reversing this one. The knob test cannot move into the seam either: release_sting(0) means
	# CUT IT DEAD there, not "leave it alone", so the opt-out has to be read at the call site.
	var src := FileAccess.get_file_as_string(PLAYER_SOURCE)
	assert_true(src.contains("if _death_skipped and skip_release > 0.0:\n\t\t\t_death_mix.release_sting(skip_release)"),
		"the sting release must be gated on BOTH the skip latch and an opted-in death_skip_sting_release")
	var revive_at := src.find("_death_mix.begin_revive()")
	var release_at := src.find("_death_mix.release_sting(")
	assert_gt(release_at, revive_at,
		"release_sting must come AFTER begin_revive(), whose _kill_tweens() would otherwise cancel the fade")

# --- The delegation, pinned by source ---------------------------------------------------------------

func test_the_player_routes_the_whole_cinematic_through_death_mix() -> void:
	# One call per death-exit path. See the header: a dropped delegation leaves a global bus ducked on
	# exactly one death mode, which no in-tree test here can catch cheaply.
	var src := FileAccess.get_file_as_string(PLAYER_SOURCE)
	assert_true(src.contains("_death_mix = DeathMix.new()"),
		"the Player must BUILD the mix (a dropped add_child = a silent world and no sting, with no error)")
	assert_true(src.contains("_death_mix.begin()"),
		"the death sequence must hand the mix the duck + start the sting")
	assert_true(src.contains("_death_mix.set_world_duck(t)"),
		"phase 1 must drive the world duck from the cinematic's own 0..1 progress")
	assert_true(src.contains("_death_mix.restore_world()"),
		"_restore_death_audio must snap the ducked buses back — every RELOADING death exit calls it")
	assert_true(src.contains("_death_mix.begin_revive()"),
		"the in-place revive must cross-fade the world back up against the sting's release")
	assert_true(src.contains("_death_mix.card_hold_seconds()"),
		"the death card's hold must come from DeathMix, or a long sting is cut off by the respawn")

func test_the_player_no_longer_fades_the_master_bus_itself() -> void:
	# The regression this whole feature turns on: if anything re-introduces a Master fade during the
	# cinematic, the sting is swallowed again and nothing errors.
	var src := FileAccess.get_file_as_string(PLAYER_SOURCE)
	assert_false(src.contains('AudioServer.set_bus_volume_db(midx'),
		"Player must not write the Master bus during the death cinematic — DeathMix ducks the world buses instead")
