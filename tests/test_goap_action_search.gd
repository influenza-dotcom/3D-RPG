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
