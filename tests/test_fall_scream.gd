extends GutTest

## FallScream (scripts/components/fall_scream.gd) — the drop-in that yells ONCE per long fall. Its whole logic is
## a polled timer, so it pins cleanly by driving _process by hand against a duck-typed host stub:
##   * the poll fires every POLL_INTERVAL, and the FIRST poll waits a full interval (a 0 start over-credited
##     ~0.2 s of fall before the actor had fallen at all);
##   * airborne AND descending faster than min_fall_speed for min_fall_time -> one positional one-shot through
##     AudioManager.play_sfx (observed as the ONE_SHOT_META player it parks under root), latched so a fall yells
##     once, re-armed on landing (or on slowing under the gate) so the NEXT fall yells again;
##   * a slow slide never screams, `enabled = false` never polls, a null scream is inert, and a non-Node3D host
##     has no position to yell from.

const SCRIPT_PATH := "res://scripts/components/fall_scream.gd"
const SCENE_PATH := "res://scenes/components/fall_scream.tscn"
## One hand-driven frame. FallScream credits the ELAPSED time at each poll (not a fixed interval), so with any
## POLL_INTERVAL <= STEP every tick polls and "seconds fallen" == ticks * STEP.
const STEP := 0.2

var _players: Array[Node] = []  ## one-shot players a scream parked under root — freed in after_each


## Duck-typed host: FallScream reads `velocity` and calls `is_on_floor()` by name, never a CharacterBody3D type.
class HostStub extends Node3D:
	var velocity: Vector3 = Vector3.ZERO
	var floored: bool = false
	func is_on_floor() -> bool:
		return floored


## A host with NO is_on_floor at all (try_call_bool's default = not grounded), only a velocity.
class MuteHost extends Node3D:
	var velocity: Vector3 = Vector3.ZERO


## A host that is not a Node3D — nowhere to place a positional yell.
class FlatHost extends Node:
	var velocity: Vector3 = Vector3(0, -9, 0)
	func is_on_floor() -> bool:
		return false


func after_each() -> void:
	for p in _players:
		if is_instance_valid(p):
			p.free()
	_players.clear()


func _one_shots() -> int:
	var n := 0
	for c in get_tree().root.get_children():
		if c.has_meta(AudioManager.ONE_SHOT_META):
			n += 1
			if not _players.has(c):
				_players.append(c)
	return n


func _rig(host: Node):
	add_child_autofree(host)
	var fs = load(SCRIPT_PATH).new()
	fs.scream = AudioStreamWAV.new()  # a real (silent) stream, so the scream path runs without touching disk
	host.add_child(fs)
	return fs


func _tick(fs, ticks: int) -> void:
	for i in ticks:
		fs._process(STEP)


## The most recently parked AudioManager one-shot under root (play_sfx appends it last), or null.
func _newest_one_shot() -> Node:
	var kids := get_tree().root.get_children()
	for i in range(kids.size() - 1, -1, -1):
		if kids[i].has_meta(AudioManager.ONE_SHOT_META):
			if not _players.has(kids[i]):
				_players.append(kids[i])
			return kids[i]
	return null


func test_a_bare_drop_in_ships_audible_and_enabled() -> void:
	var fs = load(SCRIPT_PATH).new()
	assert_not_null(fs.scream, "SHIP DECISION: the component ships with a placeholder scream so a bare drop-in is audible")
	assert_true(fs.enabled, "SHIP DECISION: a dropped-in FallScream is live without touching the inspector")
	fs.free()


## The SHIPPED gates judged by what they let through, not by their numbers: a jump (rising, then hanging at the
## apex) never counts as falling, a step off a ledge (~0.6 s airborne even at full plummet speed) never yells, and a
## real plummet does.
func test_default_gates_ignore_a_jump_and_a_step_off_but_catch_a_plummet() -> void:
	var host := HostStub.new()
	var fs = _rig(host)
	var base := _one_shots()
	host.velocity = Vector3(0, 6, 0)  # airborne and RISING
	_tick(fs, 10)
	host.velocity = Vector3.ZERO  # airborne at the apex, not descending
	_tick(fs, 10)
	assert_eq(fs._fall_time, 0.0, "rising or hanging at a jump's apex is not falling — no fall time may accrue")
	assert_eq(_one_shots(), base, "a jump never yells")
	host.velocity = Vector3(0, -9, 0)  # step off a ledge
	_tick(fs, 3)  # 0.6 s airborne at plummet speed
	host.floored = true
	_tick(fs, 1)
	assert_eq(_one_shots(), base, "a step-off / one-storey drop (0.6 s airborne) must not yell")
	host.floored = false
	_tick(fs, 15)  # a 3 s plummet
	assert_eq(_one_shots(), base + 1, "a 3 s plummet must yell")


## The designer knobs are honoured, proven with values the DEFAULTS would judge the other way: a stricter speed gate
## ignores a descent the default gate counts, a shorter time gate yells where the default would still be silent
## (0.6 s, the step-off above), and the yell plays at the authored volume from the host's position.
func test_retuned_gates_and_volume_are_honoured() -> void:
	var host := HostStub.new()
	var fs = _rig(host)
	host.position = Vector3(3, 40, -2)
	fs.min_fall_speed = 12.0
	fs.min_fall_time = 0.5
	fs.volume_db = -9.0
	var base := _one_shots()
	host.velocity = Vector3(0, -9, 0)  # a plummet by the default speed gate, a drift by a 12 m/s one
	_tick(fs, 20)
	assert_eq(fs._fall_time, 0.0, "min_fall_speed = 12: a 9 m/s descent is under the retuned gate, so no fall accrues")
	assert_eq(_one_shots(), base, "min_fall_speed = 12: a 9 m/s descent never yells")
	host.velocity = Vector3(0, -20, 0)
	_tick(fs, 3)  # 0.6 s past the speed gate
	assert_eq(_one_shots(), base + 1, "min_fall_time = 0.5: a 0.6 s fall yells")
	var yell := _newest_one_shot() as AudioStreamPlayer3D
	assert_true(yell != null, "the yell is a positional AudioStreamPlayer3D one-shot")
	if yell != null:
		assert_almost_eq(yell.volume_db, -9.0, 0.001, "the yell plays at the authored volume_db")
		assert_lt(yell.global_position.distance_to(host.global_position), 0.001, "the yell plays from the falling host's position")


func test_the_first_poll_waits_a_full_interval() -> void:
	var host := HostStub.new()
	host.velocity = Vector3(0, -9, 0)
	var fs = _rig(host)
	fs._process(0.1)
	assert_eq(fs._fall_time, 0.0, "0.1 s in: no poll yet, so no fall credited")
	fs._process(0.1)
	assert_almost_eq(fs._fall_time, 0.2, 0.0001, "the first poll lands at 0.2 s and credits exactly the elapsed interval")


func test_a_long_fall_screams_once_then_re_arms_on_landing() -> void:
	var host := HostStub.new()
	host.velocity = Vector3(0, -9, 0)
	var fs = _rig(host)
	var base := _one_shots()
	_tick(fs, 5)  # 1.0 s fallen
	assert_false(fs._screamed, "1.0 s of falling is under the 1.1 s gate — no scream yet")
	assert_eq(_one_shots(), base, "no one-shot player parked before the gate")
	_tick(fs, 1)  # 1.2 s
	assert_true(fs._screamed, "1.2 s of falling crosses the gate — scream latched")
	assert_eq(_one_shots(), base + 1, "exactly one positional one-shot parked under root by AudioManager.play_sfx")
	_tick(fs, 10)  # keep falling
	assert_eq(_one_shots(), base + 1, "a continuing fall must NOT yell again — one scream per fall")
	host.floored = true
	_tick(fs, 1)
	assert_false(fs._screamed, "landing clears the latch")
	assert_eq(fs._fall_time, 0.0, "landing resets the fall timer")
	host.floored = false
	_tick(fs, 6)  # a second fall of 1.2 s
	assert_eq(_one_shots(), base + 2, "the NEXT fall yells again")


func test_a_slow_descent_never_screams() -> void:
	var host := HostStub.new()
	host.velocity = Vector3(0, -1.0, 0)  # slower than min_fall_speed 1.5
	var fs = _rig(host)
	var base := _one_shots()
	_tick(fs, 20)  # 4 s
	assert_false(fs._screamed, "a slope slide under min_fall_speed is not a plummet")
	assert_eq(fs._fall_time, 0.0, "the timer stays reset while the speed gate fails")
	assert_eq(_one_shots(), base, "no one-shot spawned")


func test_slowing_mid_fall_resets_the_timer() -> void:
	var host := HostStub.new()
	host.velocity = Vector3(0, -9, 0)
	var fs = _rig(host)
	_tick(fs, 4)  # 0.8 s
	host.velocity = Vector3(0, -0.5, 0)  # caught on something
	_tick(fs, 1)
	assert_eq(fs._fall_time, 0.0, "dropping under the speed gate resets the accumulated fall — it has to be CONTINUOUS falling")
	host.velocity = Vector3(0, -9, 0)
	_tick(fs, 5)  # 1.0 s of fresh falling
	assert_false(fs._screamed, "the fresh fall counts from zero, so 1.0 s is still under the gate")


func test_disabled_never_polls() -> void:
	var host := HostStub.new()
	host.velocity = Vector3(0, -9, 0)
	var fs = _rig(host)
	fs.enabled = false
	var base := _one_shots()
	_tick(fs, 20)
	assert_eq(fs._poll_t, fs.POLL_INTERVAL, "the master switch stops the countdown itself, not just the scream")
	assert_eq(fs._fall_time, 0.0, "disabled: no fall credited")
	assert_eq(_one_shots(), base, "disabled: nothing plays")


func test_a_null_scream_is_inert_but_still_tracks_the_fall() -> void:
	var host := HostStub.new()
	host.velocity = Vector3(0, -9, 0)
	var fs = _rig(host)
	fs.scream = null
	var base := _one_shots()
	_tick(fs, 10)
	assert_gt(fs._fall_time, 1.1, "the fall timer still runs with no stream")
	assert_false(fs._screamed, "no stream = no latch (and no error)")
	assert_eq(_one_shots(), base, "no stream = no one-shot")


func test_a_host_without_is_on_floor_reads_as_airborne() -> void:
	var host := MuteHost.new()
	host.velocity = Vector3(0, -9, 0)
	var fs = _rig(host)
	var base := _one_shots()
	_tick(fs, 6)
	assert_true(fs._screamed, "no is_on_floor method -> try_call_bool default false (not grounded) -> velocity alone decides")
	assert_eq(_one_shots(), base + 1, "the yell still plays")


func test_a_non_node3d_host_has_nowhere_to_yell_from() -> void:
	var host := FlatHost.new()
	var fs = _rig(host)
	var base := _one_shots()
	_tick(fs, 10)
	assert_false(fs._screamed, "a plain-Node host has no global_position: no scream, no latch, no error")
	assert_eq(_one_shots(), base, "nothing played")


func test_a_parentless_component_is_a_no_op() -> void:
	var fs = load(SCRIPT_PATH).new()
	fs.scream = AudioStreamWAV.new()
	_tick(fs, 10)
	assert_eq(fs._fall_time, 0.0, "no host = nothing to poll, nothing credited, no error")
	fs.free()


func test_scene_is_a_bare_node_running_the_script() -> void:
	var ps := load(SCENE_PATH) as PackedScene
	assert_not_null(ps, "fall_scream.tscn (the drop-in) must load")
	if ps == null:
		return
	var n := ps.instantiate()
	assert_eq((n.get_script() as Script).resource_path, SCRIPT_PATH, "the drop-in scene runs fall_scream.gd")
	assert_eq(n.get_child_count(), 0, "the drop-in is a single bare Node — it needs no children")
	assert_true(n.enabled, "the authored scene ships enabled")
	n.free()
