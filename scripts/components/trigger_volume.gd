@tool
class_name TriggerVolume
extends Area3D

## Drop-in spatial EVENT volume — the keystone "when X, do Y" primitive. When a body in `trigger_group` enters
## (or, optionally, exits) it fires a configurable set of independent actions: set a story flag (Slice 1), start
## a conversation, activate a disabled node (e.g. an EncounterSpawner you left switched off), play a sound, and/or
## call a named method on a target node. Doors, ambushes, objective triggers and cutscene cues all compose from
## this — all wired in the inspector, no code.
##
## SETUP: drop the `trigger_volume.tscn` prefab (a cylinder volume) into your level, set `trigger_group` to the
## group that activates it (the Player group by default — Groups.PLAYER == &"Player"), and fill in whichever
## actions you want. Every action is independent and INERT when left unset, so a bare trigger does nothing but
## emit `fired`.

## Emitted after a successful trigger, carrying the body that set it off — wire it to anything in the editor.
signal fired(activator: Node)

@export_group("Trigger")
## The group a body must belong to for this volume to fire (checked on entry). The PLAYER group by default
## (Groups.PLAYER == &"Player" — the human is in &"Player", NOT the dead lowercase "player").
@export var trigger_group: StringName = Groups.PLAYER
## Fire only ONCE, then stop monitoring — for one-shot story beats / ambushes. Off = fires every entry.
@export var trigger_once: bool = false
## Also fire on EXIT (leaving the zone), not just on enter. Off = enter only.
@export var fire_on_exit: bool = false

@export_group("Actions")
## Set this global story flag (GameState.set_flag) when fired. Empty = none. Pairs with the Slice-1 flag gates.
@export var set_flag: StringName = &""
## The value written for `set_flag`. Default true (the common "mark that this happened" case).
@export var set_flag_value: bool = true
## Start this conversation (DialogueManager.start) when fired, with the activator as the speaker. Empty = none.
@export var start_dialogue: DialogueResource
## Enable a node that was left switched OFF (process + physics + visibility) when fired — e.g. a dormant
## EncounterSpawner or another trigger. Empty = none.
@export var activate_node_path: NodePath
## Play this sound (positional, at the volume) when fired. Empty = none.
@export var play_audio: AudioStream
## The audio bus `play_audio` routes to, so the matching volume slider affects it. "world" (diegetic, gets
## the indoor room echo under a roof) by default; use "sfx" for a non-world cue that must stay dry.
@export var audio_bus: StringName = &"world"
## Show an on-screen toast (via the player's HUD) when fired. Empty = none.
@export var toast_text: String = ""
## Colour of the toast text.
@export var toast_color: Color = Color(1.0, 1.0, 1.0)
## The generic escape hatch: call this method NAME on `target` when fired (e.g. "trigger_spawn" on an
## EncounterSpawner). Empty = none.
@export var action: StringName = &""
## The node `action` is called on. Ignored when `action` is empty.
@export var target: NodePath

@export_group("Quest")
## Start this quest (GameState.start_quest) when fired. Empty = none.
@export var start_quest: Quest
## Complete this quest by id (GameState.complete_quest) when fired — the turn-in path. Empty = none.
@export var complete_quest_id: StringName = &""
## Advance objective `advance_objective_id` of quest `advance_quest_id` by one when fired. BOTH are needed.
@export var advance_quest_id: StringName = &""
@export var advance_objective_id: StringName = &""
## Notify quest ENTER_AREA objectives matching this area name when fired (GameState.notify_enter). Empty = none.
@export var quest_area_id: StringName = &""

var _spent: bool = false  ## a trigger_once volume that has already fired

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only the configuration warning runs in-editor; the signal wiring is runtime-only
	# Monitor every layer and filter by GROUP instead — so the trigger catches the player whatever physics layer
	# it sits on, without the designer matching mask numbers. Non-`trigger_group` bodies are rejected in _gate().
	collision_mask = 0xFFFFFFFF
	body_entered.connect(_on_body_entered)
	if fire_on_exit:
		body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	_gate(body)

func _on_body_exited(body: Node) -> void:
	_gate(body)

## Gate an enter/exit by the one-shot latch and the group filter, then fire. Split out so a test can drive it.
func _gate(body: Node) -> void:
	if _spent or body == null or not body.is_in_group(trigger_group):
		return
	var gate := BuildGate.of(self)
	if gate != null and not gate.passes(body):
		return  # a build requirement under this trigger isn't met — don't fire
	if trigger_once:
		_spent = true
		set_deferred(&"monitoring", false)  # stop watching once spent
	fire(body)

## Run the configured actions for `activator`, then emit `fired`. Public so a trigger can be fired manually
## (by another trigger, a cutscene, or a test). Each action is independent and skipped when its field is unset.
func fire(activator: Node) -> void:
	if set_flag != &"":
		GameState.set_flag(set_flag, set_flag_value)
	if not activate_node_path.is_empty():
		var n := get_node_or_null(activate_node_path)
		if n != null:
			_activate(n)
	if action != &"" and not target.is_empty():
		var t := get_node_or_null(target)
		if t == null:
			push_warning("TriggerVolume '%s': target %s did not resolve — action '%s' skipped." % [name, str(target), str(action)])
		elif not t.has_method(action):
			push_warning("TriggerVolume '%s': target '%s' has no method '%s' — action skipped." % [name, str(t.name), str(action)])
		else:
			t.call(action)
	if start_quest != null:
		GameState.start_quest(start_quest)
	if complete_quest_id != &"":
		GameState.complete_quest(complete_quest_id)
	if advance_quest_id != &"" and advance_objective_id != &"":
		GameState.advance_objective(advance_quest_id, advance_objective_id)
	if quest_area_id != &"":
		GameState.notify_enter(quest_area_id)
	if toast_text != "":
		UI.toast(toast_text, toast_color)
	if play_audio != null and is_inside_tree():
		AudioManager.play_sfx(global_position, play_audio, 0.0, 1.0, audio_bus)
	if start_dialogue != null:
		DialogueManager.start(start_dialogue, activator)
	fired.emit(activator)

## Switch a dormant node on: resume its processing and reveal it (Node3D / CanvasItem). The inverse of
## leaving a spawner/effect process-disabled + hidden in the editor until the trigger arms it.
func _activate(n: Node) -> void:
	n.set_process(true)
	n.set_physics_process(true)
	if n is Node3D:
		(n as Node3D).visible = true
	elif n is CanvasItem:
		(n as CanvasItem).visible = true

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	var has_shape := false
	for c in get_children():
		if c is CollisionShape3D or c is CollisionPolygon3D:
			has_shape = true
			break
	if not has_shape:
		w.append("TriggerVolume needs a CollisionShape3D child — the volume that detects bodies.")
	# action/target wiring (the generic escape hatch): both fields are needed, and the method must exist.
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
	if not activate_node_path.is_empty() and get_node_or_null(activate_node_path) == null:
		w.append("`activate_node_path` (%s) doesn't resolve to a node." % str(activate_node_path))
	if (advance_quest_id != &"") != (advance_objective_id != &""):
		w.append("Quest advance needs BOTH `advance_quest_id` and `advance_objective_id` — one is set without the other.")
	return w
