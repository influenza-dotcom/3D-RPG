extends GutTest

## Slice 2 (TriggerVolume): the gate logic — group filter, the trigger_once one-shot latch, and the `fired`
## signal. Built off-tree with all ACTION fields empty, so fire() only emits the signal (no autoload side
## effects); the flag / dialogue / audio / activate / call-method action wiring is thin and playtest-verified
## per the project's in-tree-behaviour convention.

func _player_body() -> Node:
	var n := Node.new()
	n.add_to_group(&"player")
	return n

func test_fires_for_matching_group_and_emits() -> void:
	var tv := TriggerVolume.new()
	watch_signals(tv)
	var body := _player_body()
	tv._gate(body)
	assert_signal_emitted(tv, "fired", "a body in trigger_group fires the volume")
	body.free()
	tv.free()

func test_ignores_wrong_group() -> void:
	var tv := TriggerVolume.new()
	watch_signals(tv)
	var body := Node.new()  # not in the "player" group
	tv._gate(body)
	assert_signal_not_emitted(tv, "fired", "a body outside trigger_group does not fire")
	body.free()
	tv.free()

func test_trigger_once_fires_only_once() -> void:
	var tv := TriggerVolume.new()
	tv.trigger_once = true
	watch_signals(tv)
	var body := _player_body()
	tv._gate(body)
	tv._gate(body)  # second entry — the volume is spent
	assert_signal_emit_count(tv, "fired", 1, "trigger_once fires exactly once")
	body.free()
	tv.free()

func test_repeatable_fires_each_entry() -> void:
	var tv := TriggerVolume.new()
	tv.trigger_once = false
	watch_signals(tv)
	var body := _player_body()
	tv._gate(body)
	tv._gate(body)
	assert_signal_emit_count(tv, "fired", 2, "a repeatable trigger fires on every entry")
	body.free()
	tv.free()
