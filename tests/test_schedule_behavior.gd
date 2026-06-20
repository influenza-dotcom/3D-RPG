extends GutTest

## Rank 28b: ScheduleBehavior.is_active / _destination (the schedule -> phase -> marker resolution). act() drives
## an in-tree NPC and the NpcLocomotion._idle hook is verified by playtest; these pin the activation logic.
## (WorldClock.Phase: NIGHT = 0, DAY = 1.)

const ScheduleBehaviorScript = preload("res://scripts/components/schedule_behavior.gd")

func _schedule(phase: int, group: StringName) -> Schedule:
	var s := Schedule.new()
	var e := ScheduleEntry.new()
	e.phase = phase
	e.location_group = group
	var entries: Array[ScheduleEntry] = [e]
	s.entries = entries
	return s

func test_inactive_without_schedule() -> void:
	var sb = ScheduleBehaviorScript.new()
	add_child_autofree(sb)
	assert_false(sb.is_active(), "no schedule -> inactive (falls through to normal idle)")

func test_inactive_when_disabled() -> void:
	var sb = ScheduleBehaviorScript.new()
	sb.enabled = false
	sb.schedule = _schedule(1, &"sched_test_market")
	var marker := Node3D.new()
	marker.add_to_group("sched_test_market")
	add_child_autofree(marker)
	add_child_autofree(sb)
	var prev = WorldClock._phase
	WorldClock._phase = 1
	assert_false(sb.is_active(), "disabled -> inactive even with a matching marker")
	WorldClock._phase = prev

func test_resolves_destination_for_current_phase() -> void:
	var prev = WorldClock._phase
	var sb = ScheduleBehaviorScript.new()
	sb.schedule = _schedule(1, &"sched_test_market")  # DAY -> market
	var marker := Node3D.new()
	marker.add_to_group("sched_test_market")
	add_child_autofree(marker)
	add_child_autofree(sb)
	WorldClock._phase = 1  # DAY (synchronous test — _process can't run mid-test to overwrite it)
	assert_true(sb.is_active(), "DAY + a market marker + a DAY->market schedule -> active")
	assert_eq(sb._destination(), marker, "_destination resolves the marker in the phase's group")
	WorldClock._phase = 0  # NIGHT — the schedule has no NIGHT entry
	assert_false(sb.is_active(), "NIGHT (no entry) -> inactive, falls through to normal idle")
	WorldClock._phase = prev
