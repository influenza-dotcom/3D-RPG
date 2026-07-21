extends GutTest

## GroundMovement.compute_target_speed — the per-frame speed multiplier chain extracted verbatim out of
## Player._physics_process (M13). Driven off-tree via a Player SUBCLASS stub (no _ready — the sanctioned actor-in-a-
## test pattern) whose god-object multipliers are neutralised, so we can pin the pure speed math: direction
## (forward / backpedal / strafe), the crouch blend, and the scope slow. Assertions are RELATIVE (output vs the same
## GameSettings knob) so they hold whatever the designer tunes the multipliers to. The Landing half of M13 (byte-order
## landing/footstep feedback + its Player.tscn wiring) is deferred to an editor-open playtest, not unit-tested here.


## A Player we can build off-tree: the state-reading multipliers become no-ops (return 1.0 / 0.0) so compute_target_speed
## exercises only the direction / crouch / scope math. stats_or_default() returns a cached bare CharacterStats so the
## AGILITY term is a single deterministic factor common to every assertion.
class _StubPlayer extends Player:
	var _stats := CharacterStats.new()
	func limb_move_multiplier() -> float: return 1.0
	func encumbrance_move_multiplier() -> float: return 1.0
	func status_move_multiplier() -> float: return 1.0
	func status_stat_modifier(_stat: StringName) -> float: return 0.0
	func stats_or_default() -> CharacterStats: return _stats


func _make_stub() -> _StubPlayer:
	Input.action_release(InputManager.action_run)
	var p := _StubPlayer.new()
	p.crouch = Crouch.new()  # crouch_t defaults 0.0 (standing); weapon_system stays null (compute guards it)
	return p


func _free_stub(p: _StubPlayer) -> void:
	Input.action_release(InputManager.action_run)
	if p.crouch != null:
		p.crouch.free()
	p.free()


func _press_run() -> void:
	Input.action_press(InputManager.action_run)


func test_backpedal_applies_backward_mult() -> void:
	# Forward = the full neutral chain; backpedal replaces only the BASE with max_speed * backward_mult, so the
	# ratio is exactly backward_mult whatever the other factors are.
	var p := _make_stub()
	_press_run()
	var fwd := GroundMovement.compute_target_speed(p, Vector2(0, -1))
	var back := GroundMovement.compute_target_speed(p, Vector2(0, 1))
	assert_almost_eq(back, fwd * GameSettings.player_movement.backward_mult, 0.001, "backpedal scales the base by backward_mult")
	_free_stub(p)


func test_strafe_applies_strafe_mult() -> void:
	var p := _make_stub()
	_press_run()
	var fwd := GroundMovement.compute_target_speed(p, Vector2(0, -1))
	var strafe := GroundMovement.compute_target_speed(p, Vector2(1, 0))
	assert_almost_eq(strafe, fwd * GameSettings.player_movement.strafe_mult, 0.001, "pure strafe scales the base by strafe_mult")
	_free_stub(p)


func test_full_crouch_blends_to_crouch_speed() -> void:
	# crouch_t lerps target toward target * crouch.speed_mult; at crouch_t = 1.0 the whole speed is scaled by it.
	var p := _make_stub()
	_press_run()
	var standing := GroundMovement.compute_target_speed(p, Vector2(0, -1))
	p.crouch.crouch_t = 1.0
	var crouched := GroundMovement.compute_target_speed(p, Vector2(0, -1))
	assert_almost_eq(crouched, standing * GameSettings.player_crouch.speed_mult, 0.001, "full crouch scales speed by the crouch speed_mult")
	_free_stub(p)


func test_scope_applies_scope_slow() -> void:
	var p := _make_stub()
	_press_run()
	var hipfire := GroundMovement.compute_target_speed(p, Vector2(0, -1))
	p._is_scoped = true
	var scoped := GroundMovement.compute_target_speed(p, Vector2(0, -1))
	assert_almost_eq(scoped, hipfire * GameSettings.weapon_general.scope_speed_mult, 0.001, "scoping in scales speed by scope_speed_mult")
	_free_stub(p)


func test_sprint_lockout_uses_walk_speed_tier() -> void:
	var p := _make_stub()
	_press_run()
	var sprint := GroundMovement.compute_target_speed(p, Vector2(0, -1))
	p._begin_sprint_lockout()
	var locked := GroundMovement.compute_target_speed(p, Vector2(0, -1))
	assert_almost_eq(locked, sprint * GameSettings.player_movement.walk_speed_mult, 0.001,
		"sprint lockout falls back to the existing walk-speed tier")
	_free_stub(p)


func test_run_modifier_raises_default_walk_to_run_speed() -> void:
	var p := _make_stub()
	var walking := GroundMovement.compute_target_speed(p, Vector2(0, -1))
	_press_run()
	var running := GroundMovement.compute_target_speed(p, Vector2(0, -1))
	assert_almost_eq(walking, running * GameSettings.player_movement.walk_speed_mult, 0.001,
		"movement defaults to the walk tier; holding Run raises it to full speed")
	_free_stub(p)
