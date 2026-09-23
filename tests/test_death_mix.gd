extends GutTest

## Contract tests for the death cinematic's MIX (scripts/player/death_mix.gd) — the world duck the sting
## rides over. Covers the failures that are SILENT at runtime:
##   1. The ROUTING INVARIANT. The sting bus must exist, and must NOT be one of the buses the cinematic
##      ducks. Break either and the sting is simply inaudible (or worse, blares) with no error anywhere —
##      it is the one wiring mistake that un-does the whole feature.
##   2. BUS OWNERSHIP. While the cinematic animates the world buses it claims them, and the ADS duck
##      (ScopeCoordinator) and the conversation duck (MusicDucker) stand down instead of fighting it. Driven for
##      real: a mix claims, a real ducker tries to write, the bus is read back.
##   3. The SKIP and the SONG. The revive leaves the sting ringing unless a release is authored, an opted-in
##      release must not cancel the world swell, and release_sting(0) is a hard cut.
##   4. The DELEGATION. Player's cinematic reaches DeathMix on every death-exit path. Dropping one leaves a
##      GLOBAL bus ducked into the next life on exactly one death mode. The routes a unit test can reach are
##      driven off-tree (the off-tree death exit, phase one's duck); the rest live in Player._ready() and the long
##      in-tree tween chain, which a test must never run, so those few call sites stay pinned by source.
##
## Every test that writes a bus, the ownership static, Engine.time_scale or a PlayerFeedbackSettings knob has it
## snapshotted in before_each and put back in after_each — the buses and GameSettings are global, and a leaked
## duck would quietly mis-level every later test in the suite.

const MIX_SCRIPT := preload("res://scripts/player/death_mix.gd")
const PLAYER_SOURCE := "res://scripts/player/player.gd"

## A level no bus is ever authored or configured at, so "this bus was not written" reads unambiguously.
const SENTINEL_DB: float = -33.0
## The death_world_residue the mechanism tests pin: one tenth of the world's AMPLITUDE, so a fully ducked bus
## sits exactly 20 dB under its configured level whatever residue the game ships with. -20 dB is also far from
## both music ducks (-6 ADS, -12 conversation), so a ducker that fails to stand down cannot hide inside it.
const TEST_RESIDUE: float = 0.1
const TEST_RESIDUE_DB: float = -20.0

## PlayerFeedbackSettings fields the mechanism tests retune.
const TUNED_FIELDS: Array[String] = ["death_world_residue", "spawn_fade_in_time", "death_sting",
	"death_sting_start_delay", "death_sting_fade_in", "death_sting_release", "death_sting_slider_bus",
	"death_sting_sync_point", "death_card_holds_for_sting", "death_sequence_time", "death_card_delay",
	"death_card_fade_time", "death_card_gap", "respawn_delay"]

var _saved_bus_db: Array[float] = []
var _saved_fields: Dictionary = {}
var _saved_time_scale: float = 1.0

## Records which seams Player routes a death through, then does the real work — so a test sees both the order of
## the calls and their effect on the buses.
class RecordingMix extends DeathMix:
	var calls: Array = []

	func begin() -> void:
		calls.append(&"begin")
		super()

	func set_world_duck(t: float) -> void:
		calls.append(&"set_world_duck")
		super(t)

	func restore_world() -> void:
		calls.append(&"restore_world")
		super()

func before_each() -> void:
	_saved_bus_db.clear()
	for i in AudioServer.bus_count:
		_saved_bus_db.append(AudioServer.get_bus_volume_db(i))
	_saved_fields.clear()
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	for field in TUNED_FIELDS:
		_saved_fields[field] = fb.get(field)
	_saved_time_scale = Engine.time_scale

func after_each() -> void:
	DeathMix._owned_buses = []
	for i in mini(_saved_bus_db.size(), AudioServer.bus_count):
		AudioServer.set_bus_volume_db(i, _saved_bus_db[i])
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	for field in _saved_fields:
		fb.set(field, _saved_fields[field])
	Engine.time_scale = _saved_time_scale

func _bus_db(bus: StringName) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))

func _set_bus_db(bus: StringName, db: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), db)

## remove_child() runs _exit_tree() synchronously, which is the teardown several tests are about.
func _free_in_tree(node: Node) -> void:
	remove_child(node)
	node.free()

## Seconds of 8-bit silence: a clip the sting tests own outright, so they run whatever is authored into
## death_sting (null included — the one-field rollback) and never depend on an imported asset.
func _silent_clip(seconds: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 8000
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(int(8000.0 * seconds))
	wav.data = data
	return wav

## An IN-TREE mix whose sting is already sounding, started through the real begin(). The start delay and the
## swell are zeroed so the sting is up within a frame, and the slider bus is blanked so a muted music slider on
## the machine running the suite cannot silence it.
func _mix_with_a_playing_sting() -> DeathMix:
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	fb.death_sting = _silent_clip(4.0)
	fb.death_sting_start_delay = 0.0
	fb.death_sting_fade_in = 0.0
	fb.death_sting_slider_bus = &""
	var mix: DeathMix = MIX_SCRIPT.new()
	add_child(mix)
	mix.begin()
	await wait_process_frames(3)
	return mix

## A sting and a death timeline authored outright in round numbers, so the card's hold is solved against values this
## file owns rather than whatever clip and beats the game ships with: a `clip_seconds` clip on no slider, starting
## 0.5 s after death with its chord `sync_point` s into the clip, and 2.5 s of beats around the hold (1.0 phase one +
## 0.5 settle-on-black + 0.25 card fade in + 0.25 card fade out + 0.5 black gap), floored at a 1.0 s respawn_delay.
func _author_a_scored_death(clip_seconds: float, sync_point: float) -> void:
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	fb.death_sting = _silent_clip(clip_seconds)
	fb.death_sting_slider_bus = &""
	fb.death_sting_start_delay = 0.5
	fb.death_sting_sync_point = sync_point
	fb.death_card_holds_for_sting = true
	fb.death_sequence_time = 1.0
	fb.death_card_delay = 0.5
	fb.death_card_fade_time = 0.25
	fb.death_card_gap = 0.5
	fb.respawn_delay = 1.0

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
	# _fade_in_from_black() starts. Player's one death tween runs phase one, the settle-on-black beat (skipped when
	# death_card_delay is not positive), the card's fade in, the HOLD, the card's fade out and the black gap, in that
	# order; the hold is the only slack, so card_hold_seconds() solves it. Worked example on the authored timeline:
	# the chord lands 6.5 s after death (0.5 s start delay + 6.0 s into the clip) and the beats around the hold take
	# 2.5 s, so the card must hold for exactly 4.0 s.
	_author_a_scored_death(10.0, 6.0)
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	var mix: DeathMix = MIX_SCRIPT.new()
	assert_almost_eq(mix.card_hold_seconds(), 4.0, 0.001,
		"a chord 6.5 s after death behind 2.5 s of surrounding beats needs a 4.0 s card hold — any other hold misses the fade-in")
	# Retuning a beat around the hold must hand that time back out of the hold, so the chord stays on the fade-in
	# without anyone re-checking the arithmetic. death_card_fade_time is ONE knob for BOTH card fades, so it counts twice.
	for beat: Array in [["death_sequence_time", 1.0], ["death_card_delay", 1.0], ["death_card_fade_time", 2.0], ["death_card_gap", 1.0]]:
		var field: String = beat[0]
		var kept: float = fb.get(field)
		fb.set(field, kept + 0.3)
		var expected: float = 4.0 - 0.3 * float(beat[1])
		assert_almost_eq(mix.card_hold_seconds(), expected, 0.001,
			"lengthening %s by 0.3 s must shorten the hold to %.2f s, or the fade-in drifts off the chord by the retune"
			% [field, expected])
		fb.set(field, kept)
	# Player skips the settle-on-black beat outright for a non-positive delay, so a negative one takes no time: the
	# hold is the one for a 2.0 s surround, not a longer one that would push the fade-in 0.5 s past the chord.
	fb.death_card_delay = -0.5
	assert_almost_eq(mix.card_hold_seconds(), 4.5, 0.001,
		"a negative death_card_delay must count as no settle beat — Player never waits a negative interval")
	fb.death_card_delay = 0.5
	# The chord moves the hold with it: a sting that starts later lands its chord later.
	fb.death_sting_start_delay = 0.9
	assert_almost_eq(mix.card_hold_seconds(), 4.4, 0.001,
		"a sting that starts 0.4 s later puts its chord 0.4 s later, so the hold must grow by exactly 0.4 s")
	fb.death_sting_start_delay = 0.5
	# A sync point authored past the end of the clip aligns to the clip's last sample (0.5 + 10.0 s), never beyond it,
	# or the respawn would be held on a black screen listening to nothing.
	fb.death_sting_sync_point = 12.0
	assert_almost_eq(mix.card_hold_seconds(), 8.0, 0.001,
		"a sync point past a 10 s clip must align the fade-in to the clip's end (an 8.0 s hold), not to silence 2 s later")
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
	# SHIP DECISION: the revive leaves the sting alone. The clip's own decay IS the fade; a forced ramp to silence is
	# perceptually over long before it mathematically finishes, so it amputates the tail and reads as the audio being
	# cut. Driven with the SHIPPED death_sting_release (deliberately not overridden here): a sounding sting must still
	# be sounding, at the level it had, well after the revive. The designer's opt-in fade is driven in
	# test_the_revive_leaves_the_sting_ringing_unless_a_release_is_authored.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	var mix: DeathMix = await _mix_with_a_playing_sting()
	assert_true(mix.playing, "precondition: begin() must have started the sting")
	var level: float = mix.volume_db
	mix.begin_revive()
	await wait_seconds(0.3)
	assert_true(mix.playing,
		("SHIP DECISION: the revive must leave the sting ringing out to its natural end, but the shipped "
		+ "death_sting_release (%.2f s) stopped it") % fb.death_sting_release)
	assert_almost_eq(mix.volume_db, level, 0.05,
		("SHIP DECISION: the revive must not fade the sting, but the shipped death_sting_release (%.2f s) started "
		+ "ramping it down — the clip's tail would be cut") % fb.death_sting_release)
	_free_in_tree(mix)

func test_the_card_hold_never_shortens_the_original_cinematic() -> void:
	# respawn_delay is a FLOOR, not a replacement: a chord too early for the card to reach must leave the original
	# snappy hold exactly as it was — never a shorter one, and never a negative one.
	_author_a_scored_death(10.0, 2.4)
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	var mix: DeathMix = MIX_SCRIPT.new()
	# The chord lands 2.9 s after death, 0.4 s past the 2.5 s of surrounding beats: less than the 1.0 s floor.
	assert_almost_eq(mix.card_hold_seconds(), fb.respawn_delay, 0.001,
		"a chord that only leaves 0.4 s of hold must not shorten the card below respawn_delay")
	# A chord that lands before the card has even faded in (1.5 s after death) would solve to a NEGATIVE hold.
	fb.death_sting_sync_point = 1.0
	assert_almost_eq(mix.card_hold_seconds(), fb.respawn_delay, 0.001,
		"a chord earlier than the card's own fade-in must leave the hold at respawn_delay, not a negative interval")
	# Control: a chord 5.5 s after death leaves 3.0 s of hold, past the floor, and the card stretches to it — so the
	# two holds above are the floor at work, not a hold that ignores the sting.
	fb.death_sting_sync_point = 5.0
	assert_almost_eq(mix.card_hold_seconds(), 3.0, 0.001,
		"a chord that leaves 3.0 s of hold must stretch the card to 3.0 s — the floor only ever lengthens the beat")
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

# --- The teardown backstop: _exit_tree() restores a death in flight, and nothing else -----------------

func test_a_mix_torn_down_without_a_death_never_writes_the_world_buses() -> void:
	# Every scene change and every Load Game frees a Player that never died. The _exit_tree() restore is the
	# backstop for a teardown MID-cinematic only; firing it here would stomp whatever level another system had
	# just put on the world buses.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	var mix: DeathMix = MIX_SCRIPT.new()
	add_child(mix)
	for bus: StringName in fb.death_cinematic_buses:
		_set_bus_db(bus, SENTINEL_DB)
	_free_in_tree(mix)
	for bus: StringName in fb.death_cinematic_buses:
		assert_almost_eq(_bus_db(bus), SENTINEL_DB, 0.01,
			"freeing a mix that never began a death rewrote the '%s' bus — every plain scene change would stomp the world's level" % bus)

func test_a_mix_torn_down_mid_cinematic_restores_the_world_and_lets_go() -> void:
	# The control for the test above, and the hole it closes: Options -> Main Menu / Load Game change scene
	# straight out from under a dying player, and the buses are global, so nothing else would put them back.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	var mix: DeathMix = MIX_SCRIPT.new()
	add_child(mix)
	mix.begin()
	for bus: StringName in fb.death_cinematic_buses:
		_set_bus_db(bus, SENTINEL_DB)  # stands in for "ducked": any level that is not the configured one
	_free_in_tree(mix)
	for bus: StringName in fb.death_cinematic_buses:
		assert_almost_eq(_bus_db(bus), Settings.current_bus_db(bus), 0.05,
			"a Player freed mid-cinematic left the '%s' bus ducked — the next scene boots near-silent" % bus)
		assert_false(DeathMix.owns_bus(bus),
			"a mix freed mid-cinematic still claims '%s' — every music duck in the game would stay silenced" % bus)

func test_a_mix_torn_down_mid_revive_swell_restores_the_world_and_lets_go() -> void:
	# The revive hands control back BEFORE the world has finished swelling up, so Options -> Main Menu / Load Game can
	# free the Player mid-swell. The swell's tween dies with the node and its _end_world_fade() never runs, so the
	# teardown backstop is all that is left to put the global buses back and drop the static claim — a leaked claim
	# silences the ADS and conversation music ducks for the rest of the session.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	fb.death_world_residue = TEST_RESIDUE
	fb.death_sting = null  # the world swell alone; no clip is started
	fb.spawn_fade_in_time = 2.0
	var mix: DeathMix = MIX_SCRIPT.new()
	add_child(mix)
	mix.begin()
	mix.set_world_duck(1.0)
	mix.begin_revive()
	await wait_process_frames(2)
	for bus: StringName in fb.death_cinematic_buses:
		assert_true(DeathMix.owns_bus(bus), "precondition: '%s' must still be claimed while the revive swell runs" % bus)
		assert_lt(_bus_db(bus), Settings.current_bus_db(bus) - 3.0,
			"precondition: '%s' must still be under its configured level while the revive swell runs" % bus)
	_free_in_tree(mix)
	for bus: StringName in fb.death_cinematic_buses:
		assert_almost_eq(_bus_db(bus), Settings.current_bus_db(bus), 0.05,
			"a Player freed mid revive swell left the '%s' bus part-ducked — the next scene boots quiet" % bus)
		assert_false(DeathMix.owns_bus(bus),
			"a mix freed mid revive swell still claims '%s' — every music duck in the game would stay silenced" % bus)

# --- Bus ownership: nothing else may write a bus the cinematic is animating -------------------------

func test_the_cinematic_claims_exactly_the_buses_it_ducks() -> void:
	# The stand-down guard is only sound if ownership covers exactly what the duck writes: a bus written but not
	# claimed gets fought over, a bus claimed but not written silences a ducker for nothing. Both reloading
	# (restore_world) and off-tree revive exits must hand every claim back.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	fb.death_world_residue = TEST_RESIDUE
	var outside: Array[StringName] = [&"Master", fb.death_sting_bus]
	for bus: StringName in outside:
		_set_bus_db(bus, SENTINEL_DB)
	var mix: DeathMix = MIX_SCRIPT.new()  # off-tree: no sting, no per-frame re-assert, just the claim + the writes
	mix.begin()
	mix.set_world_duck(1.0)
	for bus: StringName in fb.death_cinematic_buses:
		assert_true(DeathMix.owns_bus(bus),
			"the cinematic ducks '%s' without claiming it — the ADS / conversation ducks would fight it every frame" % bus)
		assert_almost_eq(_bus_db(bus), Settings.current_bus_db(bus) + TEST_RESIDUE_DB, 0.05,
			"'%s' is claimed but not ducked to death_world_residue of its configured level" % bus)
	for bus: StringName in outside:
		assert_false(DeathMix.owns_bus(bus), "the cinematic claims '%s', a bus it must never duck" % bus)
		assert_almost_eq(_bus_db(bus), SENTINEL_DB, 0.01,
			"the cinematic wrote '%s' — the sting routes through it, so the sting would be ducked with the world" % bus)
	mix.restore_world()
	for bus: StringName in fb.death_cinematic_buses:
		assert_false(DeathMix.owns_bus(bus), "restore_world() kept its claim on '%s'" % bus)
		assert_almost_eq(_bus_db(bus), Settings.current_bus_db(bus), 0.05,
			"restore_world() did not land '%s' back on its configured level — a reload would boot a quiet world" % bus)
	mix.begin()
	mix.set_world_duck(1.0)
	mix.begin_revive()  # off-tree there is no clock to swell on, so it must land and let go at once
	for bus: StringName in fb.death_cinematic_buses:
		assert_false(DeathMix.owns_bus(bus), "an off-tree begin_revive() kept its claim on '%s'" % bus)
		assert_almost_eq(_bus_db(bus), Settings.current_bus_db(bus), 0.05,
			"an off-tree begin_revive() left '%s' ducked" % bus)
	mix.free()

func test_the_conversation_duck_stands_down_while_the_cinematic_owns_the_music_bus() -> void:
	# The revive hands input back BEFORE the world finishes swelling, so starting a conversation across a respawn
	# is reachable. The mix is OFF-TREE on purpose: it claims and writes the buses but never re-asserts them per
	# frame, so a write by the ducker stays visible instead of being papered over on the next frame.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	fb.death_world_residue = TEST_RESIDUE
	var mix: DeathMix = MIX_SCRIPT.new()
	mix.begin()
	mix.set_world_duck(1.0)
	var ducked_db: float = _bus_db(&"music")
	var ducker := MusicDucker.new()
	add_child_autofree(ducker)
	ducker.set_ducked(true)
	assert_false(ducker.is_ducked(),
		"a conversation started while the death cinematic owns the music bus must not arm its duck")
	await wait_seconds(GameSettings.dialogue.music_duck_fade_duration + 0.15)
	assert_almost_eq(_bus_db(&"music"), ducked_db, 0.05,
		"the conversation duck wrote the music bus the death cinematic is animating — two writers slam the music every frame")
	# Control: once the cinematic lets go, the SAME conversation ducks as it always did (StationMusic's per-frame
	# assert re-applies the rule), so the stand-down above is the claim's doing, not a ducker that cannot duck here.
	mix.restore_world()
	ducker.note_station_radio(false)
	assert_true(ducker.is_ducked(), "once the cinematic releases the music bus, the conversation duck must arm")
	await wait_seconds(GameSettings.dialogue.music_duck_fade_duration + 0.15)
	assert_almost_eq(_bus_db(&"music"), Settings.current_bus_db(&"music") + GameSettings.dialogue.music_duck_amount_db, 0.3,
		"after the release the conversation duck must bring the music down by music_duck_amount_db")
	ducker.reset()
	mix.free()

func test_the_ads_duck_stands_down_while_the_cinematic_owns_the_music_bus() -> void:
	# Same window as the conversation duck: the player is alive and free to ADS for the whole revive swell.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	fb.death_world_residue = TEST_RESIDUE
	var mix: DeathMix = MIX_SCRIPT.new()
	mix.begin()
	mix.set_world_duck(1.0)
	var ducked_db: float = _bus_db(&"music")
	# An off-tree Player as host (its _ready never runs): on_scoped_in only touches its null HUD / camera refs.
	var player = load(PLAYER_SOURCE).new()
	var scope := ScopeCoordinator.new()
	scope.host = player
	add_child_autofree(scope)
	scope.on_scoped_in(true)
	await wait_seconds(GameSettings.camera.scope_music_duck_time + 0.15)
	assert_almost_eq(_bus_db(&"music"), ducked_db, 0.05,
		"ADSing while the death cinematic owns the music bus wrote it anyway — the music would slam up toward the scope duck and snap back")
	# Control: after the release the same scope-in ducks the music by scope_music_duck_db.
	mix.restore_world()
	scope.on_scoped_in(true)
	await wait_seconds(GameSettings.camera.scope_music_duck_time + 0.15)
	assert_almost_eq(_bus_db(&"music"), Settings.current_bus_db(&"music") + GameSettings.camera.scope_music_duck_db, 0.3,
		"after the release, ADS must duck the music by scope_music_duck_db as it always did")
	scope.reset()
	mix.free()
	player.free()

# --- The SKIP and the song (a click fast-forwards the cinematic) --------------------------------------

func test_release_sting_is_inert_when_nothing_is_playing() -> void:
	# The opt-in release can run on a skipped death where no sting was ever going to sound (no clip authored, or a
	# muted slider). It must be a silent no-op there: no fade built on an idle player. In-tree, because off-tree a
	# release could never build a fade, guard or no guard.
	var idle: DeathMix = MIX_SCRIPT.new()
	add_child(idle)
	idle.volume_db = SENTINEL_DB  # a level nothing in DeathMix writes, so a fade that ran is unmistakable
	idle.release_sting(0.1)
	await wait_seconds(0.25)
	assert_almost_eq(idle.volume_db, SENTINEL_DB, 0.01,
		"release_sting built a fade on a mix with nothing playing — it must be a no-op when no sting is sounding")
	_free_in_tree(idle)
	# Control: the SAME release on an in-tree mix whose sting IS sounding fades it all the way down and stops it, so
	# the untouched level above is the not-playing guard's doing, not a release that cannot fade in this harness.
	var sounding: DeathMix = await _mix_with_a_playing_sting()
	assert_true(sounding.playing, "precondition: begin() must have started the sting")
	sounding.release_sting(0.1)
	await wait_seconds(0.25)
	assert_false(sounding.playing, "control: a release on a sounding sting must fade it out and stop it")
	assert_almost_eq(sounding.volume_db, DeathMix.SILENT_DB, 0.01,
		"control: a release on a sounding sting must land it on SILENT_DB before it stops")
	_free_in_tree(sounding)

func test_a_skipped_death_plays_the_song_out_in_full() -> void:
	# SHIP DECISION, and the whole point of the knob shipping at 0: a click fast-forwards the PICTURES. The sting runs
	# on DeathMix's own wall-clock and cannot ride the tween the skip speeds up, so a release would shorten no part of
	# the death — it would only delete the back half of the track. The knob's only gameplay reader is the gate in
	# Player._respawn_at_checkpoint (pinned in test_the_sting_release_is_gated_on_the_skip_and_the_knob), which a unit
	# test cannot run, so the shipped value itself is pinned: at 0 that gate never calls release_sting.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	assert_eq(fb.death_skip_sting_release, 0.0,
		("SHIP DECISION: death_skip_sting_release ships at 0 so a skipped death plays the song out in full — at %.2f s "
		+ "every skipped death fades the back half of the track out over the life the player just clicked back into")
		% fb.death_skip_sting_release)

func test_the_revive_leaves_the_sting_ringing_unless_a_release_is_authored() -> void:
	# The respawn is timed onto the sting's final chord so its tail rings on over the world fading back in; a
	# forced fade amputates that decay and sounds like a cut. death_sting_release > 0 is the designer's opt-in.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	fb.spawn_fade_in_time = 0.2
	fb.death_sting_release = 0.0
	var mix: DeathMix = await _mix_with_a_playing_sting()
	assert_true(mix.playing, "precondition: begin() must have started the sting")
	mix.begin_revive()
	for bus: StringName in fb.death_cinematic_buses:
		assert_true(DeathMix.owns_bus(bus),
			"the revive swell is still animating '%s', so it must stay claimed — this is the window the music ducks stand down in" % bus)
	await wait_seconds(0.4)
	assert_true(mix.playing,
		"with death_sting_release at 0 the revive must leave the sting ringing into the new life, not fade it out")
	for bus: StringName in fb.death_cinematic_buses:
		assert_false(DeathMix.owns_bus(bus), "the revive swell finished but '%s' is still claimed" % bus)
		assert_almost_eq(_bus_db(bus), Settings.current_bus_db(bus), 0.05,
			"the revive swell must land '%s' on its configured level" % bus)
	# Control: the same revive with a release authored does fade the sting out and stop it.
	mix.begin()
	await wait_process_frames(3)
	assert_true(mix.playing, "precondition: a second begin() must restart the sting")
	fb.death_sting_release = 0.15
	mix.begin_revive()
	await wait_seconds(0.4)
	assert_false(mix.playing, "an authored death_sting_release must fade the sting out on the revive and stop it")
	_free_in_tree(mix)

func test_release_sting_at_zero_cuts_the_sting_dead() -> void:
	# Why the skip's opt-out must be read at Player's call site and not passed through: release_sting(0) is not
	# "leave it alone", it is a hard stop. A release with a fade, by contrast, is still sounding when it is asked.
	var mix: DeathMix = await _mix_with_a_playing_sting()
	assert_true(mix.playing, "precondition: begin() must have started the sting")
	mix.release_sting(0.5)
	assert_true(mix.playing, "a release with a fade must ramp the sting out, not stop it on the spot")
	mix.release_sting(0.0)
	assert_false(mix.playing,
		"release_sting(0) must cut the sting dead — which is why Player only calls it when death_skip_sting_release > 0")
	_free_in_tree(mix)

func test_an_opted_in_skip_release_fades_the_sting_without_cancelling_the_world_swell() -> void:
	# Player's order on a skipped death: begin_revive() first (its _kill_tweens() would cancel an earlier fade),
	# THEN the opted-in release. The release must kill only the sting's own tween — killing the revive's too would
	# strand the world ducked and claimed with no swell left to bring it back.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	fb.spawn_fade_in_time = 0.2
	fb.death_sting_release = 0.0
	var mix: DeathMix = await _mix_with_a_playing_sting()
	assert_true(mix.playing, "precondition: begin() must have started the sting")
	mix.set_world_duck(1.0)
	mix.begin_revive()
	mix.release_sting(0.15)
	await wait_seconds(0.4)
	assert_false(mix.playing, "the opted-in skip release must fade the sting out and stop it")
	for bus: StringName in fb.death_cinematic_buses:
		assert_false(DeathMix.owns_bus(bus),
			"the skip release cancelled the world swell — '%s' is still claimed, so the music ducks stay silenced" % bus)
		assert_almost_eq(_bus_db(bus), Settings.current_bus_db(bus), 0.05,
			"the skip release cancelled the world swell — '%s' never came back up from the death duck" % bus)
	_free_in_tree(mix)

func test_the_sting_release_is_gated_on_the_skip_and_the_knob() -> void:
	# Pinned by SOURCE: the gate lives in Player._respawn_at_checkpoint, which only runs at the end of the in-tree
	# cinematic of a Player whose _ready() a test must never run. TWO gates, both load-bearing. Drop the
	# _death_skipped latch and EVERY death fades, reversing the never-fade rule; drop the knob test and every
	# SKIPPED death is cut dead (test_release_sting_at_zero_cuts_the_sting_dead). Indentation is normalised away.
	var lines := PackedStringArray()
	for line in FileAccess.get_file_as_string(PLAYER_SOURCE).split("\n"):
		lines.append(line.strip_edges())
	var src := "\n".join(lines)
	assert_true(src.contains("if _death_skipped and skip_release > 0.0:\n_death_mix.release_sting(skip_release)"),
		"the sting release must be gated on BOTH the skip latch and an opted-in death_skip_sting_release")
	var revive_at := src.find("_death_mix.begin_revive()")
	var release_at := src.find("_death_mix.release_sting(")
	assert_gt(release_at, revive_at,
		"release_sting must come AFTER begin_revive(), whose _kill_tweens() would otherwise cancel the fade")

# --- The delegation ---------------------------------------------------------------------------------

func test_an_off_tree_death_ducks_then_restores_the_world_through_the_mix() -> void:
	# The one death exit a unit test can drive end to end: off-tree, _run_death_sequence() hands the mix its duck
	# and takes the reload branch at once (_restart_scene -> _restore_death_audio). A reloading exit that skipped
	# the restore boots the next life with the world ducked and claimed; a restore before begin() is undone by it.
	var player = load(PLAYER_SOURCE).new()
	var mix := RecordingMix.new()
	player._death_mix = mix
	player._run_death_sequence()
	assert_eq(mix.calls, [&"begin", &"restore_world"],
		"an off-tree death must duck the world through DeathMix.begin() and then restore it before the reload")
	for bus: StringName in GameSettings.player_feedback.death_cinematic_buses:
		assert_false(DeathMix.owns_bus(bus), "the reloading death exit left '%s' claimed into the next life" % bus)
		assert_almost_eq(_bus_db(bus), Settings.current_bus_db(bus), 0.05,
			"the reloading death exit left '%s' off its configured level" % bus)
	mix.free()
	player.free()

func test_phase_one_ducks_the_world_in_step_and_never_touches_master() -> void:
	# The regression the whole feature turns on: the cinematic used to fade MASTER, which every bus chain (the
	# sting's included) ends at, so the sting was swallowed with no error anywhere. Phase one is where that fade
	# lived and _death_step is its per-frame body — driven off-tree here with a real mix, begun the way
	# _run_death_sequence begins it.
	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	fb.death_world_residue = TEST_RESIDUE
	var player = load(PLAYER_SOURCE).new()
	var mix: DeathMix = MIX_SCRIPT.new()
	player._death_mix = mix
	mix.begin()
	_set_bus_db(&"Master", SENTINEL_DB)
	_set_bus_db(fb.death_sting_bus, SENTINEL_DB)
	player._death_step(0.5)
	var halfway := {}
	for bus: StringName in fb.death_cinematic_buses:
		halfway[bus] = _bus_db(bus)
	player._death_step(1.0)
	for bus: StringName in fb.death_cinematic_buses:
		var configured: float = Settings.current_bus_db(bus)
		assert_lt(halfway[bus], configured - 0.5,
			"halfway through phase one '%s' is not ducking yet — the world must drain in step with the vignette" % bus)
		assert_gt(halfway[bus], configured + TEST_RESIDUE_DB + 0.5,
			"halfway through phase one '%s' is already fully ducked — the duck is not following the cinematic's progress" % bus)
		assert_almost_eq(_bus_db(bus), configured + TEST_RESIDUE_DB, 0.05,
			"at the end of phase one '%s' must sit at death_world_residue of its configured level" % bus)
	assert_almost_eq(_bus_db(&"Master"), SENTINEL_DB, 0.01,
		"phase one wrote the MASTER bus — the sting routes through Master, so a Master fade swallows it again")
	assert_almost_eq(_bus_db(fb.death_sting_bus), SENTINEL_DB, 0.01,
		"phase one wrote the sting's own bus — the death sting would duck along with the world")
	mix.restore_world()
	mix.free()
	player.free()

func test_the_in_tree_cinematic_seams_are_wired() -> void:
	# Pinned by SOURCE, and only for the calls a unit test cannot reach: _ready() builds the mix (a Player's
	# _ready must never run in a test), and the card hold and the revive live inside the long in-tree tween chain
	# and _respawn_at_checkpoint. The off-tree death exit and phase one's duck are driven for real above.
	var src := FileAccess.get_file_as_string(PLAYER_SOURCE)
	assert_true(src.contains("_death_mix = DeathMix.new()"),
		"the Player must BUILD the mix — without it the world never ducks and no sting plays, with no error")
	assert_true(src.contains("add_child(_death_mix)"),
		"the Player must parent the mix — off-tree it can never start the sting or swell the world back")
	assert_true(src.contains("_death_mix.card_hold_seconds()"),
		"the death card's hold must come from DeathMix, or a long sting is cut off by the respawn")
	assert_true(src.contains("_death_mix.begin_revive()"),
		"the in-place revive must swell the world back up through DeathMix, or the next life stays ducked")
