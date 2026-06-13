extends GutTest

## Pure-logic tests for RadioPlaybackState — the Radio's duck/settle brain. RefCounted, no tree/transform,
## so these run headless without tripping the GUT engine-error wall (MEMORY: off-tree transform reads fail).

const STATE_SCRIPT := "res://scripts/components/radio_playback_state.gd"

func _make() -> RadioPlaybackState:
	var s: RadioPlaybackState = load(STATE_SCRIPT).new()
	s.configure(0.0, -60.0, 0.4, 1.2, 3.0)  # audible 0 dB, silent -60, fast duck, slower resume, 3s settle
	return s

func test_starts_off_and_silent() -> void:
	var s := _make()
	assert_false(s.is_playing(), "A fresh radio is OFF")
	assert_false(s.wants_audible(), "An off radio never wants to be audible")
	assert_almost_eq(s.current_db, -60.0, 0.001, "An off radio sits at the silent floor")
	s = null

func test_turning_on_fades_up_to_audible() -> void:
	var s := _make()
	s.set_playing(true)
	for i in range(60): s.tick(0.1, false, false)  # ~6s of calm
	assert_true(s.wants_audible(), "On + no combat -> wants audible")
	assert_almost_eq(s.current_db, 0.0, 0.001, "Calm playback eases up to the audible level")
	s = null

func test_combat_ducks_then_settles_back() -> void:
	var s := _make()
	s.set_playing(true)
	for i in range(60): s.tick(0.1, false, false)  # warm up to audible
	for i in range(10): s.tick(0.1, true, false)   # combat hits -> duck out fast
	assert_false(s.wants_audible(), "Combat suppresses the radio")
	assert_lt(s.current_db, -30.0, "Combat ducks the volume well down")
	s.tick(0.1, false, false)
	assert_false(s.wants_audible(), "Still ducked during the post-combat settle linger")
	for i in range(50): s.tick(0.1, false, false)  # outlast the 3s settle, then ease back in
	assert_true(s.wants_audible(), "Resumes once the settle linger expires")
	assert_almost_eq(s.current_db, 0.0, 0.001, "Eases back up to audible after the fight")
	s = null

func test_resumes_when_combat_simply_stops_reporting() -> void:
	# The "last enemy died while ALERTED" case: combat just stops being reported (the group scan returns
	# false) rather than transitioning cleanly. The settle still expires and the radio resumes.
	var s := _make()
	s.set_playing(true)
	for i in range(10): s.tick(0.1, true, false)   # in combat
	assert_false(s.wants_audible(), "Ducked during combat")
	for i in range(50): s.tick(0.1, false, false)  # combat reports stop entirely (no clean transition)
	assert_true(s.wants_audible(), "Resumes after the freed-combatant case")
	s = null

func test_dialogue_suppresses_then_releases() -> void:
	var s := _make()
	s.set_playing(true)
	for i in range(60): s.tick(0.1, false, false)
	s.tick(0.1, false, true)
	assert_false(s.wants_audible(), "An open dialogue/menu suppresses the radio")
	for i in range(30): s.tick(0.1, false, false)
	assert_true(s.wants_audible(), "Resumes when dialogue closes")
	s = null

func test_external_edges_are_single_shot() -> void:
	var s := _make()
	s.set_playing(true)
	s.tick(0.1, false, false)
	assert_eq(s.external_edge(), 1, "Becoming audible reports a +1 (resume) edge")
	s.tick(0.1, false, false)
	assert_eq(s.external_edge(), 0, "No further edge while it stays audible")
	s.tick(0.1, true, false)
	assert_eq(s.external_edge(), -1, "Combat reports a -1 (pause) edge")
	s.tick(0.1, true, false)
	assert_eq(s.external_edge(), 0, "No further edge while it stays paused")
	s = null

func test_turning_off_clears_settle_and_silences() -> void:
	var s := _make()
	s.set_playing(true)
	for i in range(10): s.tick(0.1, true, false)  # combat -> settle armed
	s.set_playing(false)
	for i in range(30): s.tick(0.1, false, false)
	assert_false(s.wants_audible(), "An off radio never wants audible")
	assert_true(s.at_silent(), "An off radio fades to the silent floor")
	s = null

func test_configure_clamps_zero_fade_time() -> void:
	var s: RadioPlaybackState = load(STATE_SCRIPT).new()
	s.configure(0.0, -60.0, 0.0, 0.0, 0.0)  # zero fades must not divide-by-zero
	s.set_playing(true)
	s.tick(0.1, false, false)
	assert_true(is_finite(s.current_db), "Zero fade time is clamped — no divide-by-zero / NaN")
	s = null

func test_works_with_nonzero_levels() -> void:
	# Both audible and silent non-zero: the span math (audible - silent) must still fade correctly.
	var s: RadioPlaybackState = load(STATE_SCRIPT).new()
	s.configure(-6.0, -40.0, 0.4, 1.2, 3.0)
	s.set_playing(true)
	for i in range(60): s.tick(0.1, false, false)
	assert_almost_eq(s.current_db, -6.0, 0.001, "Eases up to the non-zero audible level")
	for i in range(30): s.tick(0.1, true, false)
	assert_almost_eq(s.current_db, -40.0, 0.001, "Ducks down to the non-zero silent floor")
	s = null

func test_volume_never_drops_below_the_silent_floor() -> void:
	var s := _make()
	s.set_playing(true)
	for i in range(60): s.tick(0.1, false, false)   # warm up to audible
	for i in range(200): s.tick(0.1, true, false)   # a very long fight
	assert_almost_eq(s.current_db, -60.0, 0.001, "A long fight ducks exactly to the floor, never past it")
	s = null

func test_turning_on_during_combat_stays_ducked() -> void:
	var s := _make()
	s.set_playing(true)
	for i in range(10): s.tick(0.1, true, false)
	assert_false(s.wants_audible(), "Switched on mid-fight, the radio stays ducked")
	assert_lt(s.current_db, -30.0, "and never pops up to audible while combat continues")
	s = null

func test_renewed_combat_rearms_the_settle() -> void:
	var s := _make()
	s.set_playing(true)
	for i in range(10): s.tick(0.1, true, false)    # a fight
	for i in range(10): s.tick(0.1, false, false)   # ~1s lull — the 3s settle is still ticking
	assert_false(s.wants_audible(), "Still ducked during the lull")
	s.tick(0.1, true, false)                        # renewed contact re-arms the FULL settle
	for i in range(20): s.tick(0.1, false, false)   # ~2s since re-arm — still inside the 3s settle
	assert_false(s.wants_audible(), "Renewed combat re-armed the settle, so it stays ducked")
	for i in range(20): s.tick(0.1, false, false)   # now well past the re-armed settle
	assert_true(s.wants_audible(), "Resumes once the re-armed settle finally expires")
	s = null

func test_pause_edge_on_turn_off() -> void:
	var s := _make()
	s.set_playing(true)
	s.tick(0.1, false, false)
	assert_eq(s.external_edge(), 1, "Becoming audible is a +1 resume edge")
	s.set_playing(false)
	s.tick(0.1, false, false)
	assert_eq(s.external_edge(), -1, "Switching the radio off reports a -1 (pause) edge to the Spotify path")
	s = null

func test_walk_away_suppresses_without_settle() -> void:
	# The walk-away pause is the 4th tick() input: it suppresses immediately and resumes immediately (no combat
	# settle linger), unlike combat.
	var s := _make()
	s.set_playing(true)
	for i in range(60): s.tick(0.1, false, false)
	assert_true(s.wants_audible(), "audible when present + calm")
	s.tick(0.1, false, false, true)            # walked out of range
	assert_false(s.wants_audible(), "walking away suppresses immediately")
	s.tick(0.1, false, false, false)           # walked back in
	assert_true(s.wants_audible(), "walking back resumes immediately — walk-away has no combat settle")
	s = null
