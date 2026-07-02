extends GutTest

## GoapActionDetect execution + state-gating parity. act() reproduces the former FSM DETECTING arm (now GOAP-driven):
## _face_point(last_known) + _hide_laser(), no fire, always RUNNING. is_runtime_valid re-checks the LIVE
## Perception.State.DETECTING so a state flip forces the executor to replan to the matching arm. Pure / off-tree
## via a duck-typed recording host stub — no real NPC (per CLAUDE.md: never run an NPC's _ready in a unit test).

class _PerceptionStub:
	extends RefCounted
	var state: int = Perception.State.DETECTING
	var last_known_position: Vector3 = Vector3(3.0, 0.0, 5.0)

class _DetectHostStub:
	extends RefCounted
	var _perception = _PerceptionStub.new()
	var faced: Array = []
	var laser_hidden: int = 0
	func _face_point(point: Vector3, _delta: float) -> void:
		faced.append(point)
	func _hide_laser() -> void:
		laser_hidden += 1

func test_detect_faces_last_known_and_hides_laser() -> void:
	var host := _DetectHostStub.new()
	var detect := GoapActionDetect.new()
	var status: int = detect.act(host, 0.016)
	assert_eq(status, GoapAction.Status.RUNNING, "detecting never succeeds -- always RUNNING")
	assert_eq(host.faced.size(), 1, "faces exactly once")
	assert_eq(host.faced[0], Vector3(3.0, 0.0, 5.0), "faces the last-known position, like the FSM DETECTING arm")
	assert_eq(host.laser_hidden, 1, "hides the laser -- no aim until ALERTED")
	host = null

func test_detect_runtime_valid_only_in_detecting() -> void:
	var host := _DetectHostStub.new()
	var detect := GoapActionDetect.new()
	host._perception.state = Perception.State.DETECTING
	assert_true(detect.is_runtime_valid(host), "valid while DETECTING")
	host._perception.state = Perception.State.ALERTED
	assert_false(detect.is_runtime_valid(host), "ALERTED -> invalid -> executor replans to the Engage arm this tick")
	host._perception.state = Perception.State.INVESTIGATING
	assert_false(detect.is_runtime_valid(host), "INVESTIGATING -> invalid -> replan to Investigate")
	host = null

func test_detect_runtime_valid_guards_null_perception() -> void:
	var host := _DetectHostStub.new()
	host._perception = null
	var detect := GoapActionDetect.new()
	assert_false(detect.is_runtime_valid(host), "no perception child -> not valid (off-tree / teardown safe)")
	host = null
