extends GutTest

## THE CONTEXTUAL F KEY, DRIVEN FOR REAL — not pinned as source text.
##
## test_flashlight.gd deliberately never puts flash_light.gd in a tree (its _process reads a parent transform and
## _ready walks ancestors for the wielder). The arbitration, though, is exactly the part that source-text pins
## cannot vouch for: "the word `pending_verb_actions` appears in the file" is not "the torch stands down". So this
## file builds the smallest rig the script will actually run in — a Node3D stub answering is_alive() and
## pending_verb_actions() — and presses real InputEventKeys through _unhandled_input.

const TORCH := preload("res://scenes/player/flash_light.gd")

## The minimum surface flash_light.gd duck-types off its wielder: liveness (the ancestor walk in _find_wielder
## looks for is_alive) and the contextual verb scan the deferral reads.
class WielderStub extends Node3D:
	var alive: bool = true
	var pending: Array[StringName] = []
	func is_alive() -> bool: return alive
	func pending_verb_actions() -> Array[StringName]: return pending

var _wielder: WielderStub = null
var _torch: SpotLight3D = null

func before_each() -> void:
	_wielder = WielderStub.new()
	add_child_autofree(_wielder)
	_torch = SpotLight3D.new()
	_torch.set_script(TORCH)
	# The click is an authored child the script reads with $FlashlightClick; give it one so the @onready resolves.
	var click := AudioStreamPlayer3D.new()
	click.name = "FlashlightClick"
	_torch.add_child(click)
	_wielder.add_child(_torch)

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	return e

func _press(code: Key) -> void:
	_torch._unhandled_input(_key(code))

func _lit() -> bool:
	return _torch.get(&"_light_on")


func test_f_toggles_the_torch_when_nothing_is_interactable() -> void:
	assert_false(_lit(), "the torch starts off")
	_press(KEY_F)
	assert_true(_lit(), "with no interact pending, F must fall through to the torch")
	_press(KEY_F)
	assert_false(_lit(), "F toggles — a second press puts it out")

func test_f_stands_down_while_an_interact_is_pending() -> void:
	_wielder.pending = [InputManager.action_pickup] as Array[StringName]
	_press(KEY_F)
	assert_false(_lit(),
		"aimed at something interactable, F belongs to Interact — the torch must NOT toggle under it")

func test_l_never_stands_down_even_with_an_interact_pending() -> void:
	# ⭐THE WHOLE REASON L IS STILL BOUND. interact_available() is true for the entire time you carry a prop, so
	# a torch that only answered F would be locked out for as long as your hands were full.
	_wielder.pending = [InputManager.action_pickup] as Array[StringName]
	_press(KEY_L)
	assert_true(_lit(), "L is the torch's alone and must toggle regardless of any pending interact")

func test_a_pending_verb_on_a_key_the_torch_does_not_share_is_ignored() -> void:
	# Takedown is pending on Q. That must not make an F press defer — only a verb sharing THIS event can.
	_wielder.pending = [InputManager.action_takedown] as Array[StringName]
	_press(KEY_F)
	assert_true(_lit(), "a verb waiting on a DIFFERENT key must not steal the torch's press")

func test_a_dead_player_cannot_flick_the_beam() -> void:
	_wielder.alive = false
	_press(KEY_L)
	assert_false(_lit(), "a dead player's torch key does nothing — it would flick over the death cinematic")

func test_an_unrelated_key_does_nothing() -> void:
	_press(KEY_J)
	assert_false(_lit(), "only the Light action toggles the torch")


func test_options_controls_advertises_the_key_the_player_will_actually_press() -> void:
	# ⭐THE DISCOVERABILITY HALF, and the reason this whole bug was reportable: when Interact took F, the torch
	# moved to L and NOTHING in the running game said so — the Options row was the only place it showed. F is
	# listed FIRST in project.godot on purpose, because get_action_binding() returns the first key event, so the
	# rebind row now reads the key a player reaches for rather than the fallback.
	assert_eq(InputManager.get_action_binding(InputManager.action_light), "F",
		"Options -> Controls must advertise Flashlight as F — order the [input] events F then L")
