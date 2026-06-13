extends GutTest

## GoapActionHold execution parity — proves the migrated Idle-floor action reproduces the FSM UNAWARE arm's
## call sequence VERBATIM: `if _scavenge == null or not _scavenge.act(delta): _idle(delta, true)` then
## `_hide_laser()`, staying RUNNING (holding is a steady state). The decision/selection is covered in
## test_goap_executor.gd; this pins act()'s host delegation with a duck-typed recording stub (no tree, no
## get_tree — off-tree safe), the testability the FSM's UNAWARE branch never had.
##
## NOTE on companion-follow ("Escort"): it is NOT a separate GOAP goal. With no target, follow is driven by
## npc.gd's `_target == null` early-return (`_idle(delta, false)`), OUTSIDE the GOAP seam. At the seam (target
## valid but perception UNAWARE) follow is the `_idle(delta, true)` branch this action delegates to — so Hold
## reproduces it. A following NPC with a target FIGHTS; that is the Engage goal's job, migrated later.

## Records the host calls GoapActionHold.act makes. `_scavenge` is the gate; `_idle` / `_hide_laser` are the
## delegated drives. Duck-typed (untyped host in act()), so a bare RefCounted with these members suffices.
class _IdleHostStub:
	extends RefCounted
	var _scavenge: Variant = null
	var idle_calls: Array = []
	var laser_hidden: int = 0
	func _idle(delta: float, return_to_post: bool) -> void:
		idle_calls.append([delta, return_to_post])
	func _hide_laser() -> void:
		laser_hidden += 1

## A scavenge component whose act() returns `busy` — true = actively raiding (owns the frame), false = nothing
## to raid (the host falls through to its idle behaviour).
class _ScavengeStub:
	extends RefCounted
	var busy: bool = true
	func act(_delta: float) -> bool:
		return busy

func test_hold_drives_idle_floor_when_no_scavenge() -> void:
	# host._scavenge == null -> short-circuits to host._idle(delta, true), exactly as the FSM UNAWARE arm.
	var host := _IdleHostStub.new()
	var hold := GoapActionHold.new()
	var status: int = hold.act(host, 0.016)
	assert_eq(status, GoapAction.Status.RUNNING, "holding is a steady state -> never SUCCEEDED, keeps the executor on it")
	assert_eq(host.idle_calls.size(), 1, "with no scavenge component, Hold drives the idle floor")
	assert_eq(host.idle_calls[0][1], true, "return_to_post=true, byte-for-byte the FSM UNAWARE branch (the no-target path passes false)")
	assert_eq(host.laser_hidden, 1, "and hides the laser, like UNAWARE")
	host = null

func test_hold_idles_when_scavenge_finds_nothing() -> void:
	# _scavenge.act() == false (no upgrade container / unreachable) -> fall through to host._idle(delta, true).
	var host := _IdleHostStub.new()
	var scav := _ScavengeStub.new()
	scav.busy = false
	host._scavenge = scav
	var hold := GoapActionHold.new()
	hold.act(host, 0.016)
	assert_eq(host.idle_calls.size(), 1, "scavenge found nothing -> idle floor runs")
	assert_eq(host.idle_calls[0][1], true, "return_to_post=true")
	assert_eq(host.laser_hidden, 1, "laser hidden unconditionally, like UNAWARE")
	host = null

func test_hold_yields_frame_to_active_scavenge() -> void:
	# _scavenge.act() == true (raiding a container) -> the raid OWNS the frame; idle floor is skipped, exactly
	# as the FSM `if _scavenge == null or not _scavenge.act(delta):` gate. Laser is still hidden afterwards.
	var host := _IdleHostStub.new()
	var scav := _ScavengeStub.new()
	scav.busy = true
	host._scavenge = scav
	var hold := GoapActionHold.new()
	var status: int = hold.act(host, 0.016)
	assert_eq(host.idle_calls.size(), 0, "scavenge owns the frame -> idle floor skipped, like the FSM UNAWARE gate")
	assert_eq(host.laser_hidden, 1, "laser still hidden after a scavenge frame")
	assert_eq(status, GoapAction.Status.RUNNING, "still a steady state while raiding")
	host = null
