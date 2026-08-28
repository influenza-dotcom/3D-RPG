extends GutTest

## Contract tests for the conversation music duck (scripts/dialogue/music_ducker.gd).
##
## The duck used to have ONE input — "a conversation is up" — and that was the bug this file now pins: a
## dialogue-hosted shop (talk to a merchant, pick Trade) leaves the conversation SUSPENDED behind the shop
## screen, so the duck stayed armed and the machine's own tinny radio played music_duck_amount_db (-12 dB)
## quieter than the identical kiosk two metres away, with nobody speaking over it. The duck now composes TWO
## inputs and stands down while a station screen is up.
##
## What breaks SILENTLY here, and is therefore what these tests cover:
##   1. The composition rule itself (pure, so it is pinned without an audio device).
##   2. The idempotence guard — note_station_radio() is asserted EVERY FRAME, and without the guard the tween
##      would be killed and rebuilt each tick, so the fade would crawl toward its target instead of landing.
##   3. reset() clearing the composed INPUTS, not just the latch: StationMusic keeps asserting through the
##      death cinematic, so a `_talking` left armed would re-duck the bus reset() just handed to DeathMix.
##   4. The two-call wiring (StationMusic -> DialogueManager -> ducker / bed) actually existing, and the two
##      station flags differing only by the hold window.
##
## The in-tree cases WRITE THE GLOBAL music bus (that is what a ducker does), so the bus level is saved and
## restored around every test — a leaked duck would quietly mis-level every later test in the suite.

const DUCKER_SCRIPT := preload("res://scripts/dialogue/music_ducker.gd")
const DIALOGUE_MANAGER_PATH := "res://scripts/dialogue/dialogue_manager.gd"

var _bus_idx: int = -1
var _bus_db: float = 0.0

func before_each() -> void:
	_bus_idx = AudioServer.get_bus_index(&"music")
	if _bus_idx >= 0:
		_bus_db = AudioServer.get_bus_volume_db(_bus_idx)

func after_each() -> void:
	if _bus_idx >= 0:
		AudioServer.set_bus_volume_db(_bus_idx, _bus_db)

## In the tree because create_tween() requires it — a ducker built off-tree would push an engine error the
## moment it actually transitioned, and GUT fails the suite on those.
func _make_ducker() -> MusicDucker:
	var d := DUCKER_SCRIPT.new() as MusicDucker
	add_child_autofree(d)
	return d

# --- The rule ---------------------------------------------------------------------------------------------

func test_wants_duck_is_talking_and_not_station_radio() -> void:
	assert_false(MusicDucker.wants_duck(false, false),
		"no conversation and no station screen: nothing to duck for")
	assert_true(MusicDucker.wants_duck(true, false),
		"a conversation with no station screen is the ORIGINAL case — the duck must still arm")
	assert_false(MusicDucker.wants_duck(true, true),
		"a dialogue-hosted station screen must RELEASE the duck: the conversation is suspended, nobody is speaking, and the machine's radio must play at the level it plays at on a bare kiosk")
	assert_false(MusicDucker.wants_duck(false, true),
		"a station screen opened standing up (no conversation) must not arm anything")

# --- The composed latch -----------------------------------------------------------------------------------

func test_station_screen_releases_and_rearms_the_duck_inside_one_conversation() -> void:
	var d := _make_ducker()
	d.set_ducked(true)
	assert_true(d._music_ducked,
		"a conversation with no station screen must arm the duck (the pre-existing behaviour must not regress)")
	d.note_station_radio(true)
	assert_false(d._music_ducked,
		"opening a station screen mid-conversation must release the duck — this is the shop-in-dialogue bug")
	d.note_station_radio(false)
	assert_true(d._music_ducked,
		"closing the station screen must RE-ARM the duck while the conversation is still up, so the resumed line lands over ducked music")
	d.set_ducked(false)
	assert_false(d._music_ducked,
		"ending the conversation must disarm the duck as it always did")

func test_a_conversation_started_under_a_station_screen_never_arms() -> void:
	# Reachable for real: close a kiosk and talk to someone standing beside it, or open a station screen
	# from the conversation's very first frame.
	var d := _make_ducker()
	d.note_station_radio(true)
	d.set_ducked(true)
	assert_false(d._music_ducked,
		"order must not matter — the duck composes both inputs rather than latching on whichever arrived last")
	d.note_station_radio(false)
	assert_true(d._music_ducked,
		"and it must arm on the release, which is where _music_prior_db is finally sampled")

func test_repeated_asserts_do_not_rebuild_the_tween() -> void:
	# THE PER-FRAME GUARD. StationMusic calls this every _process; without the `duck == _music_ducked`
	# early-out the tween is killed and recreated each tick, so it restarts from its current level every
	# frame and never lands on music_duck_amount_db.
	var d := _make_ducker()
	d.set_ducked(true)
	var first: Tween = d._music_tween
	assert_not_null(first, "arming the duck must build exactly one fade tween")
	d.note_station_radio(false)
	d.note_station_radio(false)
	d.set_ducked(true)
	assert_eq(d._music_tween, first,
		"a no-change assert must not kill and rebuild the fade — the per-frame poll would otherwise stall the duck mid-fade forever")

func test_reset_clears_the_composed_inputs_not_just_the_latch() -> void:
	# Player.die() calls this so the death cinematic (DeathMix) is the ONLY writer of the music bus. But
	# StationMusic keeps asserting note_station_radio() every frame straight through the cinematic, so a
	# `_talking` left armed here would re-duck the bus on the very next assert.
	var d := _make_ducker()
	d.set_ducked(true)
	d.reset()
	assert_false(d._music_ducked, "reset must drop the latch")
	d.note_station_radio(false)
	assert_false(d._music_ducked,
		"reset must also clear the 'a conversation is up' input, or StationMusic's next per-frame assert re-ducks the bus reset() just handed to the death cinematic")

# --- The wiring -------------------------------------------------------------------------------------------

func test_dialogue_manager_exposes_both_station_facades() -> void:
	var m = load(DIALOGUE_MANAGER_PATH).new()
	add_child_autofree(m)
	assert_true(m.has_method(&"note_menu_music"),
		"the BED's handover seam must exist — StationMusic calls it every frame")
	assert_true(m.has_method(&"note_station_screen"),
		"the DUCK's stand-down seam must exist — without it a dialogue-hosted shop plays ducked")
	# Both must be safe with no conversation in progress: a station screen opens standing up far more often
	# than it opens from a conversation, and the poll fires regardless.
	m.note_menu_music(false)
	m.note_station_screen(false)
	m.note_station_screen(true)
	m.note_station_screen(false)
	assert_false(m.is_engaged(),
		"the station asserts must not start or otherwise disturb a conversation")

func test_station_music_publishes_both_flags() -> void:
	assert_true(StationMusic.has_method(&"is_bed_wanted"),
		"the tier flag the dialogue BED and MusicDirector read must stay public")
	assert_true(StationMusic.has_method(&"is_screen_open"),
		"the tighter flag the conversation DUCK reads must be public — they differ by the hold window")
	assert_false(StationMusic.is_screen_open(),
		"is_screen_open() must be false at rest, or every conversation in the game runs un-ducked")
	# The invariant that keeps the two honest: `screen open` is the STRICTER of the pair, so it can never be
	# true while the tier flag is false. (At rest both are false; the implication is what matters.)
	assert_true(StationMusic.is_bed_wanted() or not StationMusic.is_screen_open(),
		"is_screen_open() must imply is_bed_wanted() — the hold window can only ever EXTEND the tier flag past the screen closing, never the reverse")
