extends GutTest

## GoapActionSearch execution + state-gating parity (action NAME &"Investigate"; class renamed from
## GoapActionInvestigate at Slice 8.2). act() is a VERBATIM transcription of the FSM INVESTIGATING arm, so these
## tests pin the parity-critical WRITE-ORDER off-tree: traveling -> _move_toward + _face_travel +
## refresh_investigation; arrived -> bump _search_sweep_t + face the swept point; then _hide_laser; always RUNNING.
## (Slice 8.3 grows the single-point sweep into a breadcrumb hunt; this remains the radius==0 / inert baseline.)
## Duck-typed recording host stub.

class _PerceptionStub:
	extends RefCounted
	var state: int = Perception.State.INVESTIGATING
	var last_known_position: Vector3 = Vector3(2.0, 0.0, 7.0)
	var refreshed: int = 0
	func refresh_investigation() -> void:
		refreshed += 1
	func searching_area() -> bool:
		return false  # inert: the parity tests exercise the legacy single-point _walk_point path

class _InvestigateHostStub:
	extends RefCounted
	var _perception = _PerceptionStub.new()
	var search_sweep_rate: float = 0.8
	var _search_sweep_t: float = 0.0
	var global_position: Vector3 = Vector3(1.0, 0.0, 1.0)
	var _move_result: bool = true  # true = still traveling; false = arrived (sweep)
	var moved_to: Array = []
	var faced_travel: int = 0
	var faced_points: Array = []
	var laser_hidden: int = 0
	func _move_toward(target: Vector3) -> bool:
		moved_to.append(target)
		return _move_result
	func _face_travel(_delta: float) -> void:
		faced_travel += 1
	func _face_point(point: Vector3, _delta: float) -> void:
		faced_points.append(point)
	func _hide_laser() -> void:
		laser_hidden += 1

func test_investigate_travels_and_holds_giveup_clock() -> void:
	var host := _InvestigateHostStub.new()
	host._move_result = true
	var status: int = GoapActionSearch.new().act(host, 0.016)
	assert_eq(status, GoapAction.Status.RUNNING, "investigating never succeeds -- RUNNING")
	assert_eq(host.moved_to.size(), 1, "paths toward the last-known spot")
	assert_eq(host.moved_to[0], Vector3(2.0, 0.0, 7.0), "the last-known position")
	assert_eq(host.faced_travel, 1, "faces travel direction while moving")
	assert_eq(host._perception.refreshed, 1, "holds the give-up clock OFF while traveling (refresh_investigation)")
	assert_eq(host.faced_points.size(), 0, "no sweep while still traveling")
	assert_almost_eq(host._search_sweep_t, 0.0, 0.0001, "sweep timer untouched while traveling")
	assert_eq(host.laser_hidden, 1, "laser hidden -- investigating, not aiming")
	host = null

func test_investigate_sweeps_on_arrival() -> void:
	var host := _InvestigateHostStub.new()
	host._move_result = false  # arrived: the else branch sweeps
	GoapActionSearch.new().act(host, 0.016)
	assert_eq(host.faced_travel, 0, "not traveling -> no face_travel")
	assert_eq(host._perception.refreshed, 0, "arrived -> the give-up clock is NOT refreshed (forget_time now ticks)")
	assert_almost_eq(host._search_sweep_t, 0.016, 0.0001, "sweep timer advanced by delta")
	assert_eq(host.faced_points.size(), 1, "faces the swept scan point")
	var t: float = host._search_sweep_t
	var expected: Vector3 = host.global_position + Vector3(sin(t * host.search_sweep_rate), 0.0, cos(t * host.search_sweep_rate)) * 4.0
	assert_lt(host.faced_points[0].distance_to(expected), 0.001, "swept point follows the sin/cos formula off global_position")
	assert_eq(host.laser_hidden, 1, "laser hidden on the sweep frame too")
	host = null

func test_investigate_runtime_valid_only_in_investigating() -> void:
	var host := _InvestigateHostStub.new()
	var inv := GoapActionSearch.new()
	host._perception.state = Perception.State.INVESTIGATING
	assert_true(inv.is_runtime_valid(host), "valid while INVESTIGATING")
	host._perception.state = Perception.State.DETECTING
	assert_false(inv.is_runtime_valid(host), "DETECTING -> invalid -> executor replans to Detect this tick")
	host._perception.state = Perception.State.ALERTED
	assert_false(inv.is_runtime_valid(host), "ALERTED -> invalid -> replan to the Fire arm")
	host._perception = null
	assert_false(inv.is_runtime_valid(host), "no perception child -> not valid (off-tree / teardown safe)")
	host = null

# --- Breadcrumb sweep path (Slice 8.3, feature dialed on) ------------------------------------------------------
# When Perception.searching_area() is true the action walks the breadcrumb ring instead of staring at one point.
# These pin the call sequence off-tree with a recording stub (the real motion + trail math are playtest / SearchState
# tests): walks the current crumb; while still approaching the area holds the give-up clock; once in the area ages
# the crumb-timeout instead; on arrival marks the area reached and advances to the next crumb.

class _SearchStateStub:
	extends RefCounted
	var reached_origin: bool = false
	var _target: Vector3 = Vector3(5.0, 0.0, 5.0)
	func current_target() -> Vector3:
		return _target

class _SearchPerceptionStub:
	extends RefCounted
	var state: int = Perception.State.INVESTIGATING
	var _search = _SearchStateStub.new()
	var refreshed: int = 0
	var crumb_ticked: int = 0
	var advanced: int = 0
	var dwell_ticked: int = 0
	var _dwell_done: bool = true
	func searching_area() -> bool:
		return true
	func refresh_investigation() -> void:
		refreshed += 1
	func tick_crumb_travel(_d: float) -> void:
		crumb_ticked += 1
	func advance_search() -> void:
		advanced += 1
	func dwell_elapsed(_d: float) -> bool:
		dwell_ticked += 1
		return _dwell_done

class _SearchHostStub:
	extends RefCounted
	var _perception = _SearchPerceptionStub.new()
	var _move_result: bool = true
	var search_sweep_rate: float = 0.8
	var _search_sweep_t: float = 0.0
	var global_position: Vector3 = Vector3.ZERO
	var moved_to: Array = []
	var faced_travel: int = 0
	var faced_points: Array = []
	var laser_hidden: int = 0
	func _move_toward(target: Vector3) -> bool:
		moved_to.append(target)
		return _move_result
	func _face_travel(_delta: float) -> void:
		faced_travel += 1
	func _face_point(point: Vector3, _delta: float) -> void:
		faced_points.append(point)
	func _hide_laser() -> void:
		laser_hidden += 1

func test_search_walks_crumb_and_holds_clock_before_reaching_area() -> void:
	var host := _SearchHostStub.new()
	host._move_result = true  # still traveling
	host._perception._search.reached_origin = false
	GoapActionSearch.new().act(host, 0.016)
	assert_eq(host.moved_to.size(), 1, "walks toward the current breadcrumb")
	assert_eq(host.moved_to[0], Vector3(5.0, 0.0, 5.0), "the active breadcrumb (current_target)")
	assert_eq(host.faced_travel, 1, "faces travel while walking the ring")
	assert_eq(host._perception.refreshed, 1, "holds the give-up clock while still walking OVER to the search area")
	assert_eq(host._perception.crumb_ticked, 0, "does NOT run the crumb timeout before reaching the area")
	assert_eq(host.laser_hidden, 1, "laser hidden -- searching, not aiming")
	host = null

func test_search_ages_crumb_timeout_after_reaching_area() -> void:
	var host := _SearchHostStub.new()
	host._move_result = true  # still traveling, but now within the area
	host._perception._search.reached_origin = true
	GoapActionSearch.new().act(host, 0.016)
	assert_eq(host._perception.crumb_ticked, 1, "in the area: ages the crumb-travel timeout (to skip a stuck point)")
	assert_eq(host._perception.refreshed, 0, "no longer holds the clock once searching the area (it ticks down to give up)")
	host = null

func test_search_advances_to_next_crumb_after_dwell() -> void:
	var host := _SearchHostStub.new()
	host._move_result = false  # arrived (or unreachable-and-close)
	host._perception._dwell_done = true  # dwell satisfied -> move on this frame
	GoapActionSearch.new().act(host, 0.016)
	assert_true(host._perception._search.reached_origin, "arrival marks the search area reached")
	assert_eq(host._perception.dwell_ticked, 1, "ages the dwell timer on arrival")
	assert_eq(host._perception.advanced, 1, "dwell satisfied -> advances to the next breadcrumb")
	assert_eq(host.faced_points.size(), 1, "looks around (in-place sweep) while at the crumb")
	assert_eq(host.laser_hidden, 1, "laser hidden on the arrival frame too")
	host = null

func test_search_dwells_in_place_before_advancing() -> void:
	var host := _SearchHostStub.new()
	host._move_result = false  # arrived
	host._perception._dwell_done = false  # still dwelling
	GoapActionSearch.new().act(host, 0.016)
	assert_eq(host._perception.dwell_ticked, 1, "ages the dwell timer")
	assert_eq(host._perception.advanced, 0, "does NOT advance while still dwelling (lingers at the crumb)")
	assert_eq(host.faced_points.size(), 1, "keeps looking around in place while dwelling")
	host = null


## GUARD: the stub hosts above mask the real contract — GoapActionSearch.act() advances host._search_sweep_t and
## reads host.search_sweep_rate off the REAL NPC. Assert the NPC still exposes them, so deleting them as "unused"
## (npc.gd never references _search_sweep_t itself) can't silently crash a searching NPC again.
func test_real_npc_exposes_the_search_sweep_members() -> void:
	var npc = load("res://scripts/npc/npc.gd").new()  # .new() only — never _ready in a unit test
	assert_true("_search_sweep_t" in npc, "NPC must keep _search_sweep_t — goap_action_search.gd advances it off the host")
	assert_true("search_sweep_rate" in npc, "NPC must keep search_sweep_rate — goap_action_search.gd reads it off the host")
	npc.free()
