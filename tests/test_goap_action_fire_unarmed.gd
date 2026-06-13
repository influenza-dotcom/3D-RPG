extends GutTest

## GoapActionFireUnarmed: arms-then-punches delegation + state/can-fight gating. act() must call
## _ensure_armed_from_backpack() BEFORE _act_unarmed (so a just-handed gun is drawn and the NEXT tick's planner
## switches to FireArmed), then return RUNNING. is_runtime_valid gates on live ALERTED + NOT
## _can_fight_with_gun(). Duck-typed recording host stub — the _act_unarmed body itself is manual-playtest.

class _PerceptionStub:
	extends RefCounted
	var state: int = Perception.State.ALERTED

class _FireHostStub:
	extends RefCounted
	var _perception = _PerceptionStub.new()
	var _can_fight: bool = false
	var _fleeing: bool = false
	var calls: Array = []
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

func test_fire_unarmed_arms_then_runs_unarmed_body_in_order() -> void:
	var host := _FireHostStub.new()
	var status: int = GoapActionFireUnarmed.new().act(host, 0.016)
	assert_eq(status, GoapAction.Status.RUNNING, "melee is sustained -> RUNNING")
	assert_eq(host.calls, [&"arm", &"unarmed"], "tries to draw a backpack gun FIRST, then throws fists (FSM order)")
	host = null

func test_fire_unarmed_runtime_valid_requires_alerted_and_no_gun() -> void:
	var host := _FireHostStub.new()
	var fire := GoapActionFireUnarmed.new()
	host._perception.state = Perception.State.ALERTED
	host._can_fight = false
	assert_true(fire.is_runtime_valid(host), "ALERTED + cannot fight with gun -> valid (fists)")
	host._can_fight = true
	assert_false(fire.is_runtime_valid(host), "re-armed (or reloaded) -> invalid -> replan to FireArmed")
	host._can_fight = false
	host._perception.state = Perception.State.DETECTING
	assert_false(fire.is_runtime_valid(host), "no longer ALERTED -> invalid -> replan to the matching arm")
	host._perception = null
	assert_false(fire.is_runtime_valid(host), "no perception child -> not valid")
	host = null

func test_fire_unarmed_yields_to_flee_on_temperament_flip() -> void:
	# Same as the armed arm: a coward that flips to FLEE while brawling must stop throwing fists and bolt. The
	# is_fleeing gate invalidates FireUnarmed so the executor replans to Survive/Flee the same tick.
	var host := _FireHostStub.new()
	var fire := GoapActionFireUnarmed.new()
	host._perception.state = Perception.State.ALERTED
	host._can_fight = false
	assert_true(fire.is_runtime_valid(host), "brawling while not fleeing")
	host._fleeing = true
	assert_false(fire.is_runtime_valid(host), "flipped to FLEE -> invalid -> replan to Flee")
	host = null
