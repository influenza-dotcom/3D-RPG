extends GutTest

## GoapActionFireArmed: arms-then-fires delegation + state/can-fight gating. act() must call
## _ensure_armed_from_backpack() BEFORE _act_alerted (the former FSM order, arm-then-fire), then return
## RUNNING. is_runtime_valid gates on live ALERTED + _can_fight_with_gun() so a disarm/dry-out or perception
## change forces a replan. Duck-typed recording host stub — the heavy _act_alerted body itself is manual-playtest.

class _PerceptionStub:
	extends RefCounted
	var state: int = Perception.State.ALERTED

class _FireHostStub:
	extends RefCounted
	var _perception = _PerceptionStub.new()
	var _can_fight: bool = true
	var _fleeing: bool = false
	var calls: Array = []  # ordered record of the host calls act() makes
	func _ensure_armed_from_backpack() -> void:
		calls.append(&"arm")
	func _act_alerted(_delta: float) -> void:
		calls.append(&"alerted")
	func _act_unarmed(_delta: float) -> void:
		calls.append(&"unarmed")
	func _can_fight_with_gun() -> bool:
		return _can_fight
	func is_fleeing() -> bool:
		return _fleeing

func test_fire_armed_arms_then_runs_alerted_body_in_order() -> void:
	var host := _FireHostStub.new()
	var status: int = GoapActionFireArmed.new().act(host, 0.016)
	assert_eq(status, GoapAction.Status.RUNNING, "firing is sustained -> RUNNING")
	assert_eq(host.calls, [&"arm", &"alerted"], "draws a backpack gun FIRST, then runs the armed-combat body (FSM order)")
	host = null

func test_fire_armed_runtime_valid_requires_alerted_and_can_fight() -> void:
	var host := _FireHostStub.new()
	var fire := GoapActionFireArmed.new()
	host._perception.state = Perception.State.ALERTED
	host._can_fight = true
	assert_true(fire.is_runtime_valid(host), "ALERTED + can fight with gun -> valid")
	host._can_fight = false
	assert_false(fire.is_runtime_valid(host), "dried out mid-fight -> invalid -> replan to FireUnarmed")
	host._can_fight = true
	host._perception.state = Perception.State.INVESTIGATING
	assert_false(fire.is_runtime_valid(host), "lost the target (INVESTIGATING) -> invalid -> replan to Investigate")
	host._perception = null
	assert_false(fire.is_runtime_valid(host), "no perception child -> not valid")
	host = null

func test_fire_armed_yields_to_flee_on_temperament_flip() -> void:
	# A temperament FIGHT->FLEE flip fires while ALERTED, so FireArmed is the current action and perception/ammo
	# don't change -- without the is_fleeing gate is_runtime_valid would stay true and the coward would keep
	# firing forever. It must go invalid the instant is_fleeing flips so the executor replans to Survive/Flee.
	var host := _FireHostStub.new()
	var fire := GoapActionFireArmed.new()
	host._perception.state = Perception.State.ALERTED
	host._can_fight = true
	assert_true(fire.is_runtime_valid(host), "engaging while not fleeing")
	host._fleeing = true
	assert_false(fire.is_runtime_valid(host), "flipped to FLEE -> invalid -> executor replans to Flee this tick")
	host = null
