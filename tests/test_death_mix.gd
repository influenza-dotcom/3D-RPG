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
	assert_gte(fb.death_sting_overlap, 0.0, "death_sting_overlap seconds cannot be negative")
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
	# The cinematic's own timeline: phase 1, card fade in, the hold, card fade out, the black gap.
	var respawn_at: float = fb.death_sequence_time + fb.death_card_fade_time \
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
	assert_gte(fb.death_sting_release, fb.death_sting_overlap,
		("death_sting_release %.2fs is shorter than the %.2fs of clip still to play at the respawn — the "
		+ "remainder would be cut off") % [fb.death_sting_release, fb.death_sting_overlap])
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

func test_death_mix_exposes_the_four_cinematic_seams() -> void:
	var mix: DeathMix = MIX_SCRIPT.new()
	for seam in ["begin", "set_world_duck", "restore_world", "begin_revive", "sting_end_time", "card_hold_seconds"]:
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
