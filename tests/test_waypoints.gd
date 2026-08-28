extends GutTest

## The WAYPOINT LEDGER on GameState — storage, the per-level keying, the cap refusal, the paint-stamp
## revision, THE TRACKED PIN (at most one across the whole ledger) and the [waypoints] save round trip. The
## pure record rules live next door in tests/test_waypoint_book.gd; what is pinned HERE is the part that
## touches a real autoload and a real file.
##
## ⭐THESE TESTS MUTATE A LIVE AUTOLOAD. GameState is the running profile, so every test clears the ledger it
## touches on the way in and on the way out — the autoload-split isolation rule. Nothing here calls
## save_to_disk against the REAL save path; the round-trip test writes to its own user:// scratch file and
## removes it.

const WAYPOINT_BOOK := "res://scripts/world/waypoint_book.gd"
const LEVEL := "res://tests/_fake_level_a.tscn"   ## never loaded — the ledger keys on the PATH STRING alone
const LEVEL_B := "res://tests/_fake_level_b.tscn"
const SCRATCH_SAVE := "user://test_waypoints_roundtrip.cfg"

var _saved_level: String = ""

func _wb():
	return load(WAYPOINT_BOOK)

func before_each() -> void:
	_saved_level = GameState.current_level_path
	GameState.waypoints.clear()

func after_each() -> void:
	GameState.waypoints.clear()
	GameState.current_level_path = _saved_level  # written directly: set_current_level() has side effects
	if FileAccess.file_exists(SCRATCH_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SAVE))


func test_add_returns_the_index_and_stores_the_record() -> void:
	assert_eq(GameState.add_waypoint(LEVEL, Vector3(1, 2, 3), "Door", "locked", 2, 3), 0,
		"the first pin on a level is index 0")
	assert_eq(GameState.add_waypoint(LEVEL, Vector3(4, 0, 0), "Other", "", 0, 0), 1, "...and the next is 1")
	var rec := GameState.waypoint_at(LEVEL, 0)
	assert_eq(rec.get("pos"), Vector3(1, 2, 3), "the marked point is stored")
	assert_eq(rec.get("name"), "Door", "...and the label")
	assert_eq(rec.get("icon"), 2, "...and the icon ordinal")


## Every field goes through WaypointBook.make on the way in, so a caller cannot store an over-long label or a
## control character even by calling the ledger directly.
func test_add_clamps_through_the_record_rules() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "bad\tname", "note\there", 0, 0)
	assert_eq(GameState.waypoint_at(LEVEL, 0).get("name"), "bad name",
		"the ledger clamps on the way in — a caller can never bypass the record rules")


func test_add_refuses_an_empty_level_path() -> void:
	assert_eq(GameState.add_waypoint("", Vector3.ZERO, "orphan", "", 0, 0), -1,
		"with no level loaded there is nowhere to file a pin — a boot must not accumulate orphans")
	assert_eq(GameState.waypoints.size(), 0, "...and nothing is stored under the empty key")


func test_waypoints_are_kept_per_level() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	GameState.add_waypoint(LEVEL_B, Vector3.ZERO, "b", "", 0, 0)
	assert_eq(GameState.waypoints_for(LEVEL).size(), 1, "level A holds only its own pin")
	assert_eq(GameState.waypoints_for(LEVEL_B).size(), 1, "...and level B only its own")
	assert_eq(GameState.waypoints_for("res://nowhere.tscn").size(), 0,
		"an unvisited level answers an EMPTY array, never null — the paint sites iterate it every frame")


func test_update_re_authors_but_never_moves_a_pin() -> void:
	GameState.add_waypoint(LEVEL, Vector3(5, 6, 7), "old", "old note", 0, 0)
	assert_true(GameState.update_waypoint(LEVEL, 0, "new", "new note", 3, 2), "a valid edit reports success")
	var rec := GameState.waypoint_at(LEVEL, 0)
	assert_eq(rec.get("name"), "new", "the label is re-authored")
	assert_eq(rec.get("icon"), 3, "...and the icon")
	assert_eq(rec.get("pos"), Vector3(5, 6, 7),
		"...but the POSITION is immutable: a pin is a place you marked, so 'rename' and 're-place' stay different gestures")


func test_update_and_remove_refuse_a_bad_index() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "only", "", 0, 0)
	assert_false(GameState.update_waypoint(LEVEL, 9, "x", "", 0, 0), "an out-of-range edit reports failure")
	assert_false(GameState.update_waypoint(LEVEL, -1, "x", "", 0, 0), "...and so does a negative one")
	assert_false(GameState.remove_waypoint(LEVEL, 9), "an out-of-range delete reports failure")
	assert_eq(GameState.waypoints_for(LEVEL).size(), 1, "and nothing was touched")


## The screens tell "deleted" from "there was nothing there" by this return value, and answer the second with
## a denial cue rather than reporting a delete that never happened.
func test_remove_prunes_a_level_that_empties() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "only", "", 0, 0)
	assert_true(GameState.remove_waypoint(LEVEL, 0), "the delete reports success")
	assert_false(GameState.waypoints.has(LEVEL),
		"an emptied level is dropped from the ledger, so neither it nor the save section carries empty arrays")


func test_the_per_level_cap_refuses_rather_than_dropping() -> void:
	var cap: int = int(_wb().MAX_PER_LEVEL)
	for i in cap:
		assert_gte(GameState.add_waypoint(LEVEL, Vector3(i, 0, 0), "p", "", 0, 0), 0,
			"pin %d is inside the cap" % i)
	assert_true(GameState.waypoints_full(LEVEL), "the level now reports full — the screens ask BEFORE opening their entry box")
	assert_eq(GameState.add_waypoint(LEVEL, Vector3.ZERO, "one too many", "", 0, 0), -1,
		"past the cap the ledger REFUSES (-1) — a silently-dropped pin reads exactly like a broken map")
	assert_eq(GameState.waypoints_for(LEVEL).size(), cap, "...and the list did not grow")


func test_clear_waypoints_reports_what_it_removed() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	GameState.add_waypoint(LEVEL, Vector3.ONE, "b", "", 0, 0)
	GameState.add_waypoint(LEVEL_B, Vector3.ZERO, "c", "", 0, 0)
	assert_eq(GameState.clear_waypoints(LEVEL), 2, "clearing one level reports its own count")
	assert_eq(GameState.waypoints_for(LEVEL_B).size(), 1, "...and leaves the other level alone")
	assert_eq(GameState.clear_waypoints(), 1, "clearing everything reports the rest")
	assert_eq(GameState.waypoints.size(), 0, "...and empties the ledger")
	assert_eq(GameState.clear_waypoints(), 0, "clearing nothing reports 0, so a 'clear all' affordance can stay silent")


# --- The paint stamp -----------------------------------------------------------------------------------
## waypoints_rev is what the minimap's idle gate compares each frame. A CanvasItem repaints ONLY on
## queue_redraw, and that gate deliberately withholds it from a standing player — so a mutation that fails to
## move this number is a pin that never appears (or never leaves) until something unrelated moves.

func test_every_mutation_moves_the_paint_stamp() -> void:
	var r0: int = GameState.waypoints_rev
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	assert_gt(GameState.waypoints_rev, r0, "an ADD must ask the map for a repaint")
	var r1: int = GameState.waypoints_rev
	GameState.update_waypoint(LEVEL, 0, "b", "", 1, 1)
	assert_gt(GameState.waypoints_rev, r1, "an EDIT must too — the glyph's shape and colour just changed")
	var r2: int = GameState.waypoints_rev
	GameState.remove_waypoint(LEVEL, 0)
	assert_gt(GameState.waypoints_rev, r2, "a DELETE most of all: without this the dot stays painted forever")


## A level swap changes WHICH pins are on the map without touching any pin. The deck rebake usually forces a
## repaint on that frame, but it is keyed off the navmesh region's instance id — and two consecutive levels
## that both lack a region both read 0, so nothing would ask.
func test_a_level_change_moves_the_paint_stamp() -> void:
	GameState.current_level_path = LEVEL
	var r0: int = GameState.waypoints_rev
	GameState.set_current_level(LEVEL_B)
	assert_gt(GameState.waypoints_rev, r0, "walking into a new level must repaint the map's pins")
	var r1: int = GameState.waypoints_rev
	GameState.set_current_level(LEVEL_B)
	assert_eq(GameState.waypoints_rev, r1,
		"...but re-stamping the SAME path (a death reload) must not, or the gate pays for nothing")


func test_the_changed_signal_fires_on_a_mutation() -> void:
	watch_signals(GameState)
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	assert_signal_emitted(GameState, "waypoints_changed",
		"the Map tab re-validates its selected index on this rather than trusting it across a mutation")


# --- The save round trip -------------------------------------------------------------------------------

func test_waypoints_survive_a_save_load_round_trip() -> void:
	GameState.add_waypoint(LEVEL, Vector3(3, 1, 4), "Front Door", "watch the guard", 2, 3)
	GameState.add_waypoint(LEVEL, Vector3(9, 1, 2), "Stash", "", 4, 1)
	var before: Array = GameState.waypoints_for(LEVEL).duplicate(true)
	assert_eq(GameState.save_to_disk(SCRATCH_SAVE), OK, "the scratch profile writes")
	GameState.waypoints.clear()
	assert_true(GameState.load_from_disk(SCRATCH_SAVE), "...and loads back")
	var after: Array = GameState.waypoints_for(LEVEL)
	assert_eq(after.size(), before.size(), "both pins come back")
	# Dictionary == is BY VALUE in Godot 4, so this compares the records rather than their identities.
	assert_eq(after, before, "...byte-for-byte, through ConfigFile, including the icon and palette indices")


func test_a_profile_with_no_pins_writes_no_section() -> void:
	GameState.waypoints.clear()
	assert_eq(GameState.save_to_disk(SCRATCH_SAVE), OK, "the scratch profile writes")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(SCRATCH_SAVE), OK, "...and parses")
	assert_false(cfg.has_section("waypoints"),
		"a profile that never used the feature carries no [waypoints] section at all")


func test_a_load_moves_the_paint_stamp_even_when_the_content_matches() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	assert_eq(GameState.save_to_disk(SCRATCH_SAVE), OK, "the scratch profile writes")
	var r0: int = GameState.waypoints_rev
	assert_true(GameState.load_from_disk(SCRATCH_SAVE), "...and loads back")
	assert_gt(GameState.waypoints_rev, r0,
		"a load REPLACES the ledger wholesale, so the stamp must move even when the new content happens to match")


# --- THE TRACKED PIN -------------------------------------------------------------------------------------
## Exactly one pin per profile may carry the "tracked" flag: the active navigation marker the HUD corner box
## always rim-pins and the heading tape draws a pip for. Kept in ONE section (behaviour and persistence
## together) because the whole feature is the invariant, and the two places it can silently break are a
## record REBUILD (update_waypoint runs it through the five-field make()) and a fold from a hand-edited file.

## How many pins in the whole ledger claim the flag. The invariant is "1 or 0", so every test here checks the
## count as well as the identity — a second flag would be invisible to tracked_waypoint(), which answers with
## the first one it walks past.
func _tracked_count() -> int:
	var n := 0
	for lvl: Variant in GameState.waypoints:
		for rec: Variant in GameState.waypoints_for(String(lvl)):
			if _wb().is_tracked(rec):
				n += 1
	return n

## Write the flag straight into a stored record — the doubled-up shape a hand-edited save file can carry and
## the API deliberately cannot produce (set_tracked_waypoint MOVES the flag, it never adds a second).
func _force_tracked(level_path: String, index: int) -> void:
	var rec: Dictionary = GameState.waypoint_at(level_path, index)
	rec["tracked"] = true


func test_track_sets_the_flag_and_reports_the_pin() -> void:
	GameState.add_waypoint(LEVEL, Vector3(1, 0, 1), "goal", "", 0, 0)
	assert_true(GameState.set_tracked_waypoint(LEVEL, 0, true), "a valid index reports success")
	# Dictionary == is BY VALUE in Godot 4, so this compares the pair rather than its identity.
	assert_eq(GameState.tracked_waypoint(), {"level": LEVEL, "index": 0},
		"the tracked pin answers as a level+index PAIR — the tape only draws a pip for the current level's marker, so the level is half the answer")
	assert_eq(_tracked_count(), 1, "...and exactly one pin carries the flag")


func test_only_one_pin_is_tracked_across_the_whole_ledger() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	GameState.add_waypoint(LEVEL, Vector3.ONE, "b", "", 0, 0)
	GameState.add_waypoint(LEVEL_B, Vector3.ZERO, "c", "", 0, 0)
	GameState.set_tracked_waypoint(LEVEL, 0, true)
	GameState.set_tracked_waypoint(LEVEL, 1, true)
	assert_eq(GameState.tracked_waypoint(), {"level": LEVEL, "index": 1}, "tracking a second pin MOVES the flag")
	assert_eq(_tracked_count(), 1, "...it never adds one")
	GameState.set_tracked_waypoint(LEVEL_B, 0, true)
	assert_eq(GameState.tracked_waypoint(), {"level": LEVEL_B, "index": 0},
		"the invariant spans LEVELS, not lists — tracking a pin in the next district drops the one behind you")
	assert_eq(_tracked_count(), 1, "...still exactly one marker in the whole ledger")


func test_untrack_erases_the_key_rather_than_storing_a_false() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	GameState.set_tracked_waypoint(LEVEL, 0, true)
	assert_true(GameState.set_tracked_waypoint(LEVEL, 0, false), "untracking a real pin reports success")
	assert_eq(GameState.tracked_waypoint(), {}, "nothing is tracked — the resting state, answered as an empty pair")
	assert_false(GameState.waypoint_at(LEVEL, 0).has("tracked"),
		"the key is ERASED: absent IS the false case, so a stored false would grow every save by a key that means nothing")


func test_set_tracked_refuses_a_bad_index_without_moving_the_flag() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "only", "", 0, 0)
	GameState.set_tracked_waypoint(LEVEL, 0, true)
	assert_false(GameState.set_tracked_waypoint(LEVEL, 9, true), "an out-of-range track reports failure")
	assert_false(GameState.set_tracked_waypoint(LEVEL, -1, true), "...and so does a negative one")
	assert_false(GameState.set_tracked_waypoint("res://nowhere.tscn", 0, true), "...and so does an unvisited level")
	assert_eq(GameState.tracked_waypoint(), {"level": LEVEL, "index": 0},
		"a REFUSAL must leave the flag where it was — the sweep runs for a pin that turned out not to exist otherwise")


## An edit rebuilds the record through WaypointBook.make, which is five-field on purpose. Without the
## explicit carry in update_waypoint, fixing a typo in your destination's name would quietly take it off the
## compass — a bug the player would read as the tape being broken, not as the rename.
func test_an_edit_preserves_the_tracked_flag() -> void:
	GameState.add_waypoint(LEVEL, Vector3(5, 6, 7), "old", "", 0, 0)
	GameState.set_tracked_waypoint(LEVEL, 0, true)
	assert_true(GameState.update_waypoint(LEVEL, 0, "renamed", "new note", 3, 2), "the edit succeeds")
	assert_eq(GameState.waypoint_at(LEVEL, 0).get("name"), "renamed", "the label really was re-authored")
	assert_eq(GameState.tracked_waypoint(), {"level": LEVEL, "index": 0},
		"...and the pin is STILL the tracked one")


func test_deleting_the_tracked_pin_clears_the_tracking() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	GameState.add_waypoint(LEVEL, Vector3.ONE, "b", "", 0, 0)
	GameState.set_tracked_waypoint(LEVEL, 1, true)
	assert_true(GameState.remove_waypoint(LEVEL, 1), "the delete succeeds")
	assert_eq(GameState.tracked_waypoint(), {},
		"the flag left with the record — nothing may keep aiming a compass pip at a pin that is gone")
	assert_eq(_tracked_count(), 0, "...and no neighbour inherited it")


## tracked_waypoint() WALKS the ledger instead of caching an index, exactly because a delete BELOW the
## tracked pin renumbers it — a cached index would silently start pointing at its neighbour.
func test_a_delete_below_the_tracked_pin_renumbers_it() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	GameState.add_waypoint(LEVEL, Vector3.ONE, "b", "", 0, 0)
	GameState.set_tracked_waypoint(LEVEL, 1, true)
	assert_true(GameState.remove_waypoint(LEVEL, 0), "the pin BELOW the tracked one is deleted")
	assert_eq(GameState.tracked_waypoint(), {"level": LEVEL, "index": 0},
		"the tracked pin reports its NEW index")
	assert_eq(GameState.waypoint_at(LEVEL, 0).get("name"), "b", "...and it is still the pin that was tracked")


func test_tracking_moves_the_paint_stamp_and_notifies() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	watch_signals(GameState)
	var r0: int = GameState.waypoints_rev
	GameState.set_tracked_waypoint(LEVEL, 0, true)
	assert_gt(GameState.waypoints_rev, r0,
		"the ring and the compass pip only appear if the idle gate is told to repaint — the tracked flag is a painted fact")
	assert_signal_emitted(GameState, "waypoints_changed",
		"...and it routes through the same write barrier as every other mutation, synchronously")
	var r1: int = GameState.waypoints_rev
	GameState.set_tracked_waypoint(LEVEL, 0, true)
	assert_eq(GameState.waypoints_rev, r1,
		"re-tracking the pin that is already tracked is a genuine no-op — no stamp, and no autosave behind it")
	var r2: int = GameState.waypoints_rev
	GameState.set_tracked_waypoint(LEVEL, 0, false)
	assert_gt(GameState.waypoints_rev, r2, "an untrack must repaint too, or the ring stays on the box forever")


func test_the_tracked_flag_survives_a_save_load_round_trip() -> void:
	GameState.add_waypoint(LEVEL, Vector3(3, 1, 4), "Front Door", "watch the guard", 2, 3)
	GameState.add_waypoint(LEVEL, Vector3(9, 1, 2), "Stash", "", 4, 1)
	GameState.set_tracked_waypoint(LEVEL, 1, true)
	assert_eq(GameState.save_to_disk(SCRATCH_SAVE), OK, "the scratch profile writes")
	GameState.waypoints.clear()
	assert_true(GameState.load_from_disk(SCRATCH_SAVE), "...and loads back")
	assert_eq(GameState.tracked_waypoint(), {"level": LEVEL, "index": 1},
		"the destination is part of the profile — a reload must not silently un-set where the player was going")
	assert_eq(_tracked_count(), 1, "...and still exactly one pin carries it")


## The API cannot mint two markers, but a text editor can. FIRST WINS rather than "none" or "whichever the
## walk reaches last": a deterministic winner is what stops the same doctored file loading differently twice.
func test_a_save_with_two_tracked_pins_on_one_level_keeps_the_first() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "first", "", 0, 0)
	GameState.add_waypoint(LEVEL, Vector3.ONE, "second", "", 0, 0)
	_force_tracked(LEVEL, 0)
	_force_tracked(LEVEL, 1)
	assert_eq(GameState.save_to_disk(SCRATCH_SAVE), OK, "the doctored profile writes")
	GameState.waypoints.clear()
	assert_true(GameState.load_from_disk(SCRATCH_SAVE), "...and loads back")
	assert_eq(_tracked_count(), 1, "the load fold enforces ONE navigation marker")
	assert_eq(GameState.tracked_waypoint(), {"level": LEVEL, "index": 0}, "...and it is the FIRST one in the list")


func test_the_one_tracked_rule_spans_levels_on_load() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	GameState.add_waypoint(LEVEL_B, Vector3.ZERO, "b", "", 0, 0)
	_force_tracked(LEVEL, 0)
	_force_tracked(LEVEL_B, 0)
	assert_eq(GameState.save_to_disk(SCRATCH_SAVE), OK, "the doctored profile writes")
	GameState.waypoints.clear()
	assert_true(GameState.load_from_disk(SCRATCH_SAVE), "...and loads back")
	assert_eq(_tracked_count(), 1,
		"the invariant is LEDGER-wide: two levels each claiming a marker still load exactly one, because every consumer only ever sees the first")


## The fold reads the flag through WaypointBook.is_tracked, so the hand-edited junk cases degrade rather than
## erroring — and the junk key itself is not carried into memory to be written back out on the next save.
func test_a_junk_typed_tracked_flag_loads_as_untracked() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	var rec: Dictionary = GameState.waypoint_at(LEVEL, 0)
	rec["tracked"] = "absolutely"
	assert_eq(GameState.save_to_disk(SCRATCH_SAVE), OK, "the doctored profile writes")
	GameState.waypoints.clear()
	assert_true(GameState.load_from_disk(SCRATCH_SAVE), "...and loads back")
	assert_eq(GameState.tracked_waypoint(), {}, "a junk flag means untracked, never a crash on the fold")
	assert_false(GameState.waypoint_at(LEVEL, 0).has("tracked"), "...and the junk key is dropped rather than round-tripped")
