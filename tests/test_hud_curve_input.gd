extends GutTest

## THE CURVED HUD MUST NOT MAKE THE PANEL DEAF.
##
## ui.gd renders the `_weighted` carrier — HP, ammo, money, toasts, minimap, clock and the HOTBAR — through a
## SubViewport so a barrel shader can bow it (`_apply_hud_curve`). A SubViewport only receives input from
## whoever hands it some: the root Window pumps ONLY its own `_unhandled_input` group, and a
## `SubViewportContainer` is what normally forwards into a nested one. This composite is hand-built (a ColorRect
## sampling the render target), so there is no container — and when the carrier first moved inside, every child
## on it went deaf. Nothing errored, nothing rendered wrong, and no off-tree test could notice: the Hotbar simply
## stopped answering keys 1-0 and the weapon wheel, because those live in `_unhandled_input`. The curve defaults
## ON (HudSettings.hud_curve_amount is a non-zero designer default x Settings.hud_curve_scale 1.0 — don't cite
## the number here, it drifts), so that shipped as "the hotbar is broken" with the bar still rendering perfectly.
##
## These are BEHAVIOURAL, not source-text pins: they push a real InputEvent at the real main window and ask
## whether a real Control on the real carrier heard it — the only phrasing that can catch a regression which is
## invisible to every off-tree assertion. BOTH curve states are pinned, because "OFF IS THE OLD TREE" is the
## promise the whole curve block is built on, and that promise has to cover WHICH KEYS WORK, not just the pixels.

const UI_SCRIPT := preload("res://scripts/ui/ui.gd")

## A carrier passenger that listens exactly the way Hotbar does.
class CarrierListener extends Control:
	var hits: int = 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			hits += 1

## Consumes the event the way Hotbar does, and records whether the SubViewport registered the consumption.
class ConsumingListener extends Control:
	var hits: int = 0
	var saw_handled: bool = false
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			hits += 1
			get_viewport().set_input_as_handled()
			saw_handled = get_viewport().is_input_handled()


var _ui: CanvasLayer = null
var _saved_curve_scale: float = 1.0


func before_each() -> void:
	_saved_curve_scale = Settings.hud_curve_scale
	_ui = UI_SCRIPT.new()
	add_child_autofree(_ui)
	await wait_process_frames(2)

func after_each() -> void:
	# Put the player's real dial back: settings.cfg is the SHIPPED file, and a suite that writes Settings
	# without restoring it silently rewrites the user's options.
	Settings.hud_curve_scale = _saved_curve_scale
	_ui = null


## Force the curve to a strength and let ui.gd's live poll act on it. Returns the carrier.
func _set_curve(scale: float) -> Node:
	Settings.hud_curve_scale = scale
	_ui.call(&"_apply_hud_curve")
	var carrier: Node = _ui.get(&"_weighted")
	assert_not_null(carrier, "ui.gd must have built the _weighted carrier in _ready")
	return carrier

## Pump a key press at the MAIN WINDOW, exactly as the platform layer does, and let it settle.
func _press(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	get_tree().root.push_input(ev)
	await wait_process_frames(1)


func test_carrier_hears_the_keyboard_while_the_curve_is_up() -> void:
	var carrier := _set_curve(1.0)
	var vp: Node = _ui.get(&"_curve_viewport")
	assert_not_null(vp, "a non-zero HUD curve must stand the SubViewport up")
	assert_eq(carrier.get_parent(), vp,
			"the carrier must be INSIDE the curve viewport, or this test proves nothing")
	var listener := CarrierListener.new()
	carrier.add_child(listener)
	await _press(KEY_1)
	assert_eq(listener.hits, 1,
			"a Control on the CURVED carrier must still receive _unhandled_input — these are the hotbar slot keys")
	listener.queue_free()

func test_carrier_still_hears_the_keyboard_with_the_curve_off() -> void:
	# OFF tears the viewport down and hands the carrier back to the layer. The pre-curve tree always worked;
	# this is the control case proving the test above measures the forwarder and not the pump itself.
	var carrier := _set_curve(0.0)
	assert_null(_ui.get(&"_curve_viewport"), "curve 0 must tear the SubViewport down, not run an identity pass")
	assert_eq(carrier.get_parent(), _ui, "curve 0 must hand the carrier back to the layer")
	var listener := CarrierListener.new()
	carrier.add_child(listener)
	await _press(KEY_2)
	assert_eq(listener.hits, 1, "the pre-curve tree must keep hearing the keyboard")
	listener.queue_free()

func test_a_consumer_inside_the_curve_still_stops_the_event() -> void:
	# Hotbar calls get_viewport().set_input_as_handled() so a slot key does not ALSO reach the gameplay consumers
	# behind it. Inside the SubViewport that marks the SUBVIEWPORT handled, so ui.gd's forwarder has to carry the
	# flag back out — otherwise every hotbar press would double-fire into whatever else reads the same key.
	var carrier := _set_curve(1.0)
	var consumer := ConsumingListener.new()
	carrier.add_child(consumer)
	# A listener OUTSIDE the curve, forced EARLIER in tree order than the UI. The unhandled-input group is walked
	# in REVERSE tree order, so earlier-in-tree = visited AFTER the UI — which is where the real gameplay consumers
	# sit (Player.tscn orders RayCast, Weapon, MouseInput and JumpBuffer all before the UI child). If the forwarder
	# fails to re-raise the flag, THIS is what double-fires, so this is the assertion with teeth.
	var outer := CarrierListener.new()
	var host := _ui.get_parent()
	host.add_child(outer)
	host.move_child(outer, 0)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_3
	ev.keycode = KEY_3
	ev.pressed = true
	get_tree().root.push_input(ev)
	# Read the OUTER viewport's flag NOW, before another frame's events reset it.
	var root_handled := get_tree().root.is_input_handled()
	await wait_process_frames(1)
	assert_eq(consumer.hits, 1, "the consumer must have seen the event")
	assert_true(consumer.saw_handled,
			"set_input_as_handled() inside the curve viewport must land on the SubViewport ui.gd re-reads")
	assert_true(root_handled,
			"ui.gd must RE-RAISE the flag on the MAIN viewport — this is the half the inner asserts cannot see")
	assert_eq(outer.hits, 0,
			"a consumer behind the curve must be shielded: without the re-raise every hotbar press double-fires")
	outer.queue_free()
	consumer.queue_free()
