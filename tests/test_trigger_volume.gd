extends GutTest

## Slice 2 (TriggerVolume): the gate logic — group filter, the trigger_once one-shot latch, and the `fired`
## signal. Built off-tree with all ACTION fields empty, so fire() only emits the signal (no autoload side
## effects). The toast action is observed through UI.toast's real routing (the first Player-group node with
## notify_toast); the flag / dialogue / audio / activate / call-method action wiring is thin and playtest-verified
## per the project's in-tree-behaviour convention.

func _player_body() -> Node:
	var n := Node.new()
	n.add_to_group(Groups.PLAYER)  # the REAL player group (&"Player") — exercises the shipped default, not the dead lowercase one
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

## Stands in for the live player's HUD: UI.toast delivers to the first Player-group node that has notify_toast.
class ToastSink extends Node:
	var received: Array = []
	func notify_toast(text: String, color: Color) -> void:
		received.append([text, color])

var _sink: ToastSink = null

func after_each() -> void:
	# The sink sits in the Player group while it is in the tree; never let it outlive its test.
	if is_instance_valid(_sink):
		_sink.free()
	_sink = null

func test_a_bare_trigger_shows_no_toast_but_an_authored_one_does() -> void:
	_sink = ToastSink.new()
	add_child(_sink)
	_sink.add_to_group(Groups.PLAYER)  # the sink is also the player body that walks in
	var bare := TriggerVolume.new()
	bare._gate(_sink)
	assert_eq(_sink.received.size(), 0,
		"a trigger with no toast_text must put nothing on the HUD — not even an empty toast")
	var authored := TriggerVolume.new()
	authored.toast_text = "The floor gives way"
	authored.toast_color = Color(1.0, 0.4, 0.2)
	authored._gate(_sink)
	assert_eq(_sink.received, [["The floor gives way", Color(1.0, 0.4, 0.2)]],
		"control: the same entry with toast_text authored shows exactly that text, in the authored colour")
	_sink.remove_from_group(Groups.PLAYER)
	bare.free()
	authored.free()
