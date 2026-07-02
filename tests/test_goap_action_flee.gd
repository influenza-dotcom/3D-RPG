extends GutTest

## GoapActionFlee execution + gating parity. act() reproduces the former FSM FLEE pre-seam (now the GOAP Survive path):
## _act_flee + _hide_laser, always RUNNING. is_runtime_valid keeps it valid across DETECTING/ALERTED/
## INVESTIGATING while fleeing and yields on UNAWARE (lost the threat -> replan to the Idle floor) or when not
## fleeing. Duck-typed recording host stub — the _act_flee body (NpcLocomotion) is manual-playtest.

class _PerceptionStub:
	extends RefCounted
	var state: int = Perception.State.ALERTED

class _FleeHostStub:
	extends RefCounted
	var _perception = _PerceptionStub.new()
	var _fleeing: bool = true
	var fled: int = 0
	var laser_hidden: int = 0
	func is_fleeing() -> bool:
		return _fleeing
	func _act_flee(_delta: float) -> void:
		fled += 1
	func _hide_laser() -> void:
		laser_hidden += 1

func test_flee_runs_away_and_hides_laser() -> void:
	var host := _FleeHostStub.new()
	var status: int = GoapActionFlee.new().act(host, 0.016)
	assert_eq(status, GoapAction.Status.RUNNING, "fleeing is sustained -> RUNNING")
	assert_eq(host.fled, 1, "delegates to _act_flee (run from the threat, never fire)")
	assert_eq(host.laser_hidden, 1, "hides the laser, like the FSM pre-seam")
	host = null

func test_flee_runtime_valid_while_fleeing_and_noticed() -> void:
	var host := _FleeHostStub.new()
	var flee := GoapActionFlee.new()
	host._fleeing = true
	for s in [Perception.State.DETECTING, Perception.State.ALERTED, Perception.State.INVESTIGATING]:
		host._perception.state = s
		assert_true(flee.is_runtime_valid(host), "valid while fleeing + a threat noticed (state %s)" % s)
	host._perception.state = Perception.State.UNAWARE
	assert_false(flee.is_runtime_valid(host), "lost the threat (UNAWARE) -> invalid -> replan to the Idle floor")
	host = null

func test_flee_runtime_invalid_when_not_fleeing() -> void:
	var host := _FleeHostStub.new()
	var flee := GoapActionFlee.new()
	host._perception.state = Perception.State.ALERTED
	host._fleeing = false
	assert_false(flee.is_runtime_valid(host), "not fleeing -> invalid (a fighter never flees via this action)")
	host._fleeing = true
	host._perception = null
	assert_false(flee.is_runtime_valid(host), "no perception child -> not valid (off-tree / teardown safe)")
	host = null
