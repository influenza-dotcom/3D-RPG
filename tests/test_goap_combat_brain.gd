extends GutTest

## The combat brain end-to-end, driven through GoapExecutor.tick() (not decide() directly) with the FULL combat
## library + goals and a duck-typed RECORDING host stub. This is the capstone parity test: it exercises the
## executor's replan-ONLY-on-invalid policy across live perception changes, the path the pure decide() matrix in
## test_goap_combat_selection.gd can't reach. It proves (1) each perception state dispatches to the FSM-matching
## arm, (2) a state flip selects AND runs the new arm the SAME tick (the fatal-flaw regression), and (3) the
## FireArmed<->FireUnarmed swap on a can-fight flip. No tree / get_tree — the stub only records host calls.

class _PerceptionStub:
	extends RefCounted
	var state: int = Perception.State.UNAWARE
	var last_known_position: Vector3 = Vector3(2.0, 0.0, 7.0)
	var refreshed: int = 0
	func refresh_investigation() -> void:
		refreshed += 1
	func searching_area() -> bool:
		return false  # Slice 8.3: this parity stub drives GoapActionSearch's legacy single-point _walk_point path

## Satisfies BOTH GoapExecutor._build_world_state (target/hp/perception/can-fight) and every combat action's
## act()/is_runtime_valid. `ran` records a marker per delegated body so a test can prove which arm actually ran.
class _BrainHostStub:
	extends RefCounted
	var _target: Object = RefCounted.new()
	var hp: float = 10.0
	var max_hp: float = 10.0
	var temperament: float = 0.0  # sensed into the &"temperament" world-fact (GOAP dynamic-priority knob)
	var _perception = _PerceptionStub.new()
	var _can_fight: bool = true
	var _fleeing: bool = false
	var _scavenge: Variant = null
	var search_sweep_rate: float = 0.8
	var _search_sweep_t: float = 0.0
	var global_position: Vector3 = Vector3.ZERO
	var _move_result: bool = true
	var ran: Array = []
	func _can_fight_with_gun() -> bool:
		return _can_fight
	func is_fleeing() -> bool:
		return _fleeing
	func _act_flee(_d: float) -> void:
		ran.append(&"flee")
	func _idle(_d: float, _rtp: bool) -> void:
		ran.append(&"idle")
	func _hide_laser() -> void:
		ran.append(&"hide_laser")
	func _face_point(_pt: Vector3, _d: float) -> void:
		ran.append(&"face_point")
	func _move_toward(_pos: Vector3, _allow_hop: bool = false) -> bool:
		ran.append(&"move")
		return _move_result
	func is_hostile() -> bool:
		return true  # GoapActionSearch reads this to gate its nav-hop; true keeps the Investigate "move" path running
	func _face_travel(_d: float) -> void:
		ran.append(&"face_travel")
	func _ensure_armed_from_backpack() -> void:
		ran.append(&"arm")
	func _act_alerted(_d: float) -> void:
		ran.append(&"alerted")
	func _act_unarmed(_d: float) -> void:
		ran.append(&"unarmed")

func _brain() -> GoapExecutor:
	var ex := GoapExecutor.new()
	ex.setup(
		[GoapActionDetect.new(), GoapActionSearch.new(), GoapActionFireArmed.new(), GoapActionFireUnarmed.new(), GoapActionFlee.new(), GoapActionHold.new()],
		[GoapGoal.new(&"Survive", 3.0, {&"fled": true}),
		 GoapGoal.new(&"Engage", 2.0, {&"target_engaged": true}),
		 GoapGoal.new(&"Investigate", 0.4, {&"spot_searched": true}),
		 GoapGoal.new(&"Detect", 0.3, {&"threat_faced": true}),
		 GoapGoal.new(&"Idle", 0.1, {&"idle_done": true})])
	return ex

func test_tick_dispatches_each_perception_state_like_the_fsm() -> void:
	var host := _BrainHostStub.new()
	var ex := _brain()
	host._perception.state = Perception.State.UNAWARE
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"Hold", "UNAWARE + valid target -> the Idle floor (FSM UNAWARE arm)")
	host._perception.state = Perception.State.DETECTING
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"Detect", "DETECTING -> Detect")
	host._perception.state = Perception.State.ALERTED
	host._can_fight = true
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"FireArmed", "ALERTED + can fight with gun -> FireArmed")
	host._perception.state = Perception.State.INVESTIGATING
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"Investigate", "INVESTIGATING -> Investigate")
	host._perception.state = Perception.State.UNAWARE
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"Hold", "gave up the search -> back to the Idle floor")
	ex = null
	host = null

func test_state_flip_runs_the_new_arm_the_same_tick() -> void:
	# Fatal-flaw regression: the executor replans ONLY when the current action is invalid. Because each action's
	# is_runtime_valid re-checks live perception, an ALERTED->INVESTIGATING flip invalidates the running FireArmed
	# and the executor selects AND steps Investigate in the SAME tick — it must NOT keep firing at a lost target.
	var host := _BrainHostStub.new()
	var ex := _brain()
	host._perception.state = Perception.State.ALERTED
	host._can_fight = true
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"FireArmed", "engaging")
	host.ran.clear()
	host._perception.state = Perception.State.INVESTIGATING  # target broke line of sight
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"Investigate", "lost LOS -> Investigate selected the same tick")
	assert_true(host.ran.has(&"move"), "the Investigate body actually RAN this tick")
	assert_false(host.ran.has(&"alerted"), "the stale FireArmed body did NOT run after the flip")
	ex = null
	host = null

func test_fire_armed_unarmed_swap_on_can_fight_flip() -> void:
	var host := _BrainHostStub.new()
	var ex := _brain()
	host._perception.state = Perception.State.ALERTED
	host._can_fight = true
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"FireArmed", "armed engage")
	host.ran.clear()
	host._can_fight = false  # weapon/ammo pickpocketed mid-fight
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"FireUnarmed", "can no longer fight with gun -> fists, same tick")
	assert_true(host.ran.has(&"unarmed"), "the unarmed body ran")
	assert_false(host.ran.has(&"alerted"), "the stale armed body did not run")
	host.ran.clear()
	host._can_fight = true  # found a clip / re-armed
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"FireArmed", "re-armed -> FireArmed, same tick")
	assert_true(host.ran.has(&"alerted"), "the armed body ran")
	ex = null
	host = null

func test_idle_floor_unsticks_when_a_target_is_noticed() -> void:
	# Direct regression for the Hold-stickiness bug this capstone exposed: Hold's base is_runtime_valid was always
	# true, so once the floor ran the executor never replanned and the NPC idled through a fight starting. Hold
	# now yields on any combat perception state.
	var host := _BrainHostStub.new()
	var ex := _brain()
	host._perception.state = Perception.State.UNAWARE
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"Hold", "nothing noticed yet -> idling")
	host.ran.clear()
	host._perception.state = Perception.State.DETECTING  # the target enters view; detection meter starts
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"Detect", "noticed -> Detect the same tick (no longer stuck on Hold)")
	assert_true(host.ran.has(&"face_point"), "the Detect body ran")
	assert_false(host.ran.has(&"idle"), "the stale Hold idle body did NOT run")
	ex = null
	host = null

func test_temperament_flip_switches_from_fighting_to_fleeing_same_tick() -> void:
	# The bug the Survive/Flee parity workflow caught: a FIGHT NPC flips to FLEE mid-combat (only while ALERTED,
	# so FireArmed is the current action; perception/ammo don't change). The combat action's is_runtime_valid
	# must yield on is_fleeing so the executor replans to Flee THAT tick -- else the coward fires forever.
	var host := _BrainHostStub.new()
	var ex := _brain()
	host._perception.state = Perception.State.ALERTED
	host._can_fight = true
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"FireArmed", "fighting before the flip")
	host.ran.clear()
	host._fleeing = true  # _on_damaged_by temperament flip
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"Flee", "flipped to FLEE -> Survive/Flee selected the same tick")
	assert_true(host.ran.has(&"flee"), "the flee body ran this tick")
	assert_false(host.ran.has(&"alerted"), "the stale FireArmed body did NOT run after the flip")
	ex = null
	host = null

func test_archetype_fleer_flees_over_fighting_then_idles_when_threat_lost() -> void:
	var host := _BrainHostStub.new()
	host._fleeing = true
	var ex := _brain()
	host._perception.state = Perception.State.ALERTED
	host._can_fight = true
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"Flee", "a fleer with a noticed threat runs, never fights (Survive 3.0 > Engage 2.0)")
	host._perception.state = Perception.State.UNAWARE
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"Hold", "fleer that lost the threat (UNAWARE) falls to the Idle floor, like the FSM")
	ex = null
	host = null

func test_unarmed_combatant_flips_to_flee_same_tick() -> void:
	# Companion to the armed-flip regression: a disarmed coward brawling (FireUnarmed) that flips to FLEE must
	# bolt the same tick, not throw another fist. Pins the executor replanning the UNARMED arm on is_fleeing.
	var host := _BrainHostStub.new()
	var ex := _brain()
	host._perception.state = Perception.State.ALERTED
	host._can_fight = false  # disarmed -> FireUnarmed
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"FireUnarmed", "brawling before the flip")
	host.ran.clear()
	host._fleeing = true
	ex.tick(host, 0.016)
	assert_eq(ex.current_action().name, &"Flee", "flipped to FLEE -> Flee the same tick")
	assert_true(host.ran.has(&"flee"), "the flee body ran")
	assert_false(host.ran.has(&"unarmed"), "the stale FireUnarmed body did NOT run")
	ex = null
	host = null
