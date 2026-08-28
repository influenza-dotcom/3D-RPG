extends GutTest

## WaypointMarker (scripts/player/waypoint_marker.gd) — the in-world Mark Waypoint verb (X). The RAY is the
## only runtime surface left (it needs a physics frame and a real world); everything else the press does now
## happens inside the press, so it is pinned here: the guard ladder, the bare unit-stub inertness contract
## every player verb component shares, the two pure position answers, and the whole place-name-track-toast
## commit. Loaded BY PATH — the file deliberately carries no class_name.
##
## ⭐IT USED TO OPEN A NAME BOX. That is why these tests can exist at all: the verb no longer defers anything
## into a NameEntryDialog callback, so "press X" and "a tracked pin is in the ledger" are the same instant.
## Any test here that finds the ledger unchanged after _begin_mark() is also catching a regression back to a
## modal flow.
##
## ⭐THESE TESTS MUTATE A LIVE AUTOLOAD (GameState is the running profile) — the tests/test_waypoints.gd
## isolation rule: clear the ledger on the way in AND on the way out, and restore current_level_path directly
## rather than through set_current_level(), which has side effects.

const MARKER_SCRIPT := "res://scripts/player/waypoint_marker.gd"
const WAYPOINT_BOOK := "res://scripts/world/waypoint_book.gd"
## Never loaded — the ledger keys on the PATH STRING alone.
const LEVEL := "res://tests/_fake_level_marker.tscn"

var _saved_level: String = ""


func before_each() -> void:
	_saved_level = GameState.current_level_path
	GameState.waypoints.clear()
	GameState.current_level_path = LEVEL


func after_each() -> void:
	GameState.waypoints.clear()
	GameState.current_level_path = _saved_level


## The component with no host: every function under test here is host-independent (the ray degrades to a miss
## and the stand point to the origin), which is exactly why the placement flow is checkable off-tree.
func _marker():
	var m = load(MARKER_SCRIPT).new()
	autofree(m)
	return m


## How many pins across the WHOLE ledger carry the tracked flag. The invariant is "at most one, anywhere" —
## counting per level would pass a bug that left a second flag on another level's pin.
func _tracked_count() -> int:
	var n := 0
	var wb = load(WAYPOINT_BOOK)
	for lvl: Variant in GameState.waypoints:
		for rec: Variant in GameState.waypoints_for(String(lvl)):
			if rec is Dictionary and wb.is_tracked(rec):
				n += 1
	return n


## The Player builds this with .new() + host; a bare stub with NO host must be completely inert — the
## claim/pet/takedown components pin the same contract, and _physics_process runs every frame on a live one.
func test_bare_new_is_inert() -> void:
	var m = _marker()
	assert_not_null(m, "constructs with no tree and no host")
	assert_false(m._can_run(), "no host = never runs")
	m._physics_process(0.016)  # must bail on the host guard, touching neither Input nor GameState
	assert_eq(GameState.waypoints_for(LEVEL).size(), 0, "...and pins nothing on the way past")


func test_position_answers_degrade_off_tree() -> void:
	var m = _marker()
	assert_eq(m.aim_point(), Vector3.INF, "no host: the aim ray reports 'hit nothing' rather than erroring")
	assert_eq(m.stand_point(), Vector3.ZERO, "...and the stand fallback degrades to origin")
	# A host that is not a physics body (this bare Node) must degrade the same way, not crash on get_rid.
	var fake_host := Node.new()
	autofree(fake_host)
	m.host = fake_host
	assert_eq(m.aim_point(), Vector3.INF, "a non-CollisionObject3D host cannot cast, so the ray reports a miss")


## The guard ladder in order: the physics-suspension check exists for the F1 debug menu, which freezes the
## Player by hand (set_physics_process(false)) while staying OUTSIDE gameplay_suppressed — without it, typing
## the marker's letter into that menu's search field fires the verb underneath.
func test_can_run_honours_the_player_physics_suspension() -> void:
	var m = load(MARKER_SCRIPT).new()
	var host := Node3D.new()
	add_child_autofree(host)
	host.add_child(m)  # freed with the host
	m.host = host
	host.set_physics_process(false)
	assert_false(m._can_run(), "a physics-suspended host (the debug menu's suspend_player) suspends the verb too")


func test_ray_constants_are_sane() -> void:
	var m = load(MARKER_SCRIPT)
	assert_gt(float(m.RAY_REACH), 10.0, "the ray marks PLACES across a plaza, not arm's-length objects")
	assert_gt(float(m.SURFACE_OFFSET), 0.0, "the pin backs off the surface it hit — never inside the wall")
	assert_lt(float(m.SURFACE_OFFSET), 1.0, "...but only just")


# ---------------------------------------------------------------- one press, one nav point

## THE WHOLE FEATURE IN ONE ASSERT BLOCK: the press stores a pin, names it, and makes it the tracked one,
## with nothing left pending. With no host the ray misses, so the pin lands on the stand point — which is
## the fallback branch, tested here because it is the one a bare component can reach.
func test_the_press_pins_names_and_tracks_without_a_dialog() -> void:
	var m = _marker()
	m._begin_mark()
	assert_eq(GameState.waypoints_for(LEVEL).size(), 1,
			"the pin is in the ledger the moment the key is pressed — nothing waits on a name box")
	var rec := GameState.waypoint_at(LEVEL, 0)
	assert_eq(rec.get("pos"), Vector3.ZERO, "no ray hit = the spot the player is standing on")
	assert_eq(GameState.tracked_waypoint(), {"level": LEVEL, "index": 0},
			"X is the 'set nav point' gesture: the new pin is THE tracked one, so the tape pip is already up")


## The seeded name is SAVED PLAYER DATA, not chrome, so the [PH] placeholder marker must not survive into the
## record — the dog_pickup precedent. Numbered from the pin count, which is what makes two unnamed pins
## distinguishable at a glance.
func test_the_auto_name_is_numbered_and_carries_no_placeholder_marker() -> void:
	var m = _marker()
	m._begin_mark()
	m._begin_mark()
	var first := String(GameState.waypoint_at(LEVEL, 0).get("name", ""))
	var second := String(GameState.waypoint_at(LEVEL, 1).get("name", ""))
	assert_eq(first, PlayerText.strip_prefix(TextFormat.subst(PlayerText.WAYPOINT_DEFAULT_NAME, {"n": 1})),
			"the first pin takes the default name with the ordinal substituted")
	assert_false(first.contains(PlayerText.PH_PREFIX),
			"the [PH] marker never reaches the save file: %s" % first)
	assert_ne(first, second, "the ordinal counts the pins that already exist, so two presses are two names")


## Tracking is a MOVE, not a set. Two presses must leave ONE pip on the tape, or the instrument stops
## answering "where am I going" — GameState owns the sweep, and this pins that the verb actually uses it.
func test_a_second_press_moves_the_tracked_flag_rather_than_adding_one() -> void:
	var m = _marker()
	m._begin_mark()
	m._begin_mark()
	assert_eq(_tracked_count(), 1, "exactly one pin in the whole ledger is tracked after two presses")
	assert_eq(GameState.tracked_waypoint(), {"level": LEVEL, "index": 1},
			"...and it is the pin the player just placed, not the one they placed before")


## The cap refusal is checked BEFORE anything is composed or stored, and it must leave the tracked pin alone:
## a refused press cannot silently re-point the player's navigation marker.
func test_a_full_level_refuses_and_leaves_the_tracked_pin_where_it_was() -> void:
	var m = _marker()
	m._begin_mark()  # pin 0, tracked
	var cap: int = load(WAYPOINT_BOOK).MAX_PER_LEVEL
	while GameState.waypoints_for(LEVEL).size() < cap:
		GameState.add_waypoint(LEVEL, Vector3(1.0, 0.0, 0.0), "filler", "", 0, 0)
	assert_true(GameState.waypoints_full(LEVEL), "the level is at its cap before the refused press")
	m._begin_mark()
	assert_eq(GameState.waypoints_for(LEVEL).size(), cap, "a refused press stores nothing")
	assert_eq(GameState.tracked_waypoint(), {"level": LEVEL, "index": 0},
			"...and does not move the navigation marker off the pin that had it")


## A code-built LevelData records no path, so there is nowhere to file a pin. Its own refusal, and — the part
## that matters here — no orphan record under the empty key.
func test_a_level_with_no_path_files_nothing() -> void:
	GameState.current_level_path = ""
	var m = _marker()
	m._begin_mark()
	assert_eq(GameState.waypoints.size(), 0, "with no level loaded the press stores nothing at all")
	assert_eq(GameState.tracked_waypoint(), {}, "...and nothing becomes the tracked pin")


## The commit takes its LEVEL as an argument rather than re-reading GameState mid-press: the cap check, the
## add and the track must all name one level. Called directly with a non-current level to prove the argument
## is honoured (the per-level ledger stores non-current levels natively).
func test_the_commit_files_the_level_it_was_handed() -> void:
	var m = _marker()
	var other := "res://tests/_fake_level_marker_b.tscn"
	m._commit(other, Vector3(3.0, 0.0, 4.0), "Somewhere")
	assert_eq(GameState.waypoints_for(LEVEL).size(), 0, "the pin does NOT land on the level that happens to be current")
	assert_eq(GameState.waypoint_at(other, 0).get("pos"), Vector3(3.0, 0.0, 4.0), "...it lands on the one it was handed")
	assert_eq(GameState.tracked_waypoint(), {"level": other, "index": 0},
			"a pin marked on another level is still tracked — the tape simply draws no pip until you are there")
