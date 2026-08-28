@tool
class_name Switch
extends LookAtInteractable


## Aim-and-press SWITCH / LEVER / button — the MANUAL counterpart to the spatial TriggerVolume. On Interact it
## fires a focused action set: set a story flag, call a method on a target node (the universal escape hatch:
## "open" on a Door, "trigger_spawn" on an EncounterSpawner, even "fire" on a TriggerVolume to run its WHOLE
## bundle), show a toast, and play a clunk. Gate it with a BuildGate child (a key/stat/perk/ability requirement,
## like a Lock) and it won't throw until the requirement is met. Every action is independent + inert when unset.
##
## SETUP: attach to an Area3D over a lever / button / panel mesh (add a CollisionShape3D, or enable
## auto_fit_collider), then wire the actions in the inspector. PickupRay sees it via the LookAtInteractable base.

signal used(activator: Node)

## Hover label shown while aimed at it ("Pull the lever", "Press the button").
@export var verb: String = PlayerText.PROMPT_USE
## Fire only ONCE, then go inert (a lever that stays thrown). Off = usable repeatedly.
@export var one_shot: bool = false
## Toast shown when a BuildGate child blocks the use (the requirement isn't met). Empty = silent.
@export var locked_toast: String = PlayerText.TOAST_IT_WONT_BUDGE

@export_group("Actions")
## Set this story flag (GameState.set_flag) on use. Empty = none. Pairs with the Slice-1 flag gates.
@export var set_flag: StringName = &""
@export var set_flag_value: bool = true
## Call this method NAME on `target` on use — the universal escape hatch: "open" on a Door, "trigger_spawn" on a
## spawner, or "fire" on a TriggerVolume to run its full action bundle. Empty = none.
@export var action: StringName = &""
@export var target: NodePath
## On-screen toast on use (via the player's HUD). Empty = none.
@export var toast_text: String = ""
@export var toast_color: Color = Color(1.0, 1.0, 1.0)
## Clunk / click sound on use (positional, at the switch). Empty = none.
@export var play_audio: AudioStream
@export var audio_bus: StringName = &"world"

var _spent: bool = false  ## a one_shot switch that has already thrown

# No _ready override: pure talk-layer wiring + the @tool editor hitbox preview are inherited from
# LookAtInteractable._ready (its own Engine.is_editor_hint() base guard handles the editor early-out). XC1.

## Interact pressed while aimed at us (the duck-typed talk-handler surface). Gate-check, then run the actions.
func start_talk(player: Node) -> void:
	if _spent:
		return
	var gate := BuildGate.of(self)
	if gate != null and not gate.passes(player):
		if locked_toast != "":
			UI.toast(locked_toast, Color(0.85, 0.85, 0.85))
		return
	if one_shot:
		_spent = true
	if set_flag != &"":
		GameState.set_flag(set_flag, set_flag_value)
	if action != &"" and not target.is_empty():
		var t := get_node_or_null(target)
		if t == null:
			push_warning("Switch '%s': target %s didn't resolve — action '%s' skipped." % [name, str(target), str(action)])
		elif not t.has_method(action):
			push_warning("Switch '%s': target '%s' has no method '%s' — skipped." % [name, str(t.name), str(action)])
		else:
			# Pass the activator when the method takes an argument (e.g. TriggerVolume.fire(activator)), else call
			# bare (e.g. Door.open()). A zero-arg call to a method that REQUIRES an arg errors AND aborts the rest of
			# start_talk (the toast / audio / used.emit below would be skipped) — so dispatch by the method's arity.
			if t.get_method_argument_count(action) > 0:
				t.call(action, player)
			else:
				t.call(action)
	if toast_text != "":
		UI.toast(toast_text, toast_color)
	if play_audio != null and is_inside_tree():
		AudioManager.play_sfx(global_position, play_audio, 0.0, 1.0, audio_bus)
	used.emit(player)

## A thrown one_shot lever is inert (the hover prompt + the ray skip it).
func can_be_talked_to() -> bool:
	return not _spent

func look_name() -> String:
	return verb

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if action != &"" and target.is_empty():
		w.append("`action` ('%s') is set but `target` is empty — nothing will be called." % str(action))
	elif not target.is_empty() and action == &"":
		w.append("`target` is set but `action` is empty — the target is never called.")
	elif action != &"" and not target.is_empty():
		var t := get_node_or_null(target)
		if t == null:
			w.append("`target` (%s) doesn't resolve to a node." % str(target))
		elif not t.has_method(action):
			w.append("`target` '%s' has no method `%s` — the call will be skipped at runtime." % [str(t.name), str(action)])
	return w
