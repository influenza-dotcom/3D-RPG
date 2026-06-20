@tool
class_name CutscenePlayer
extends Node

## Plays a Cutscene — runs its CutsceneActions in order (wait, set a flag, call a method, play dialogue, ease a
## cinematic camera, fade the screen) while player control is LOCKED, restoring control + the gameplay camera at
## the end or on skip (Escape). Drive it from a TriggerVolume (action = "play", target = this) or a dialogue.
##
## NOTE: playback is runtime/visual (cameras, tweens, the tree) and is PLAYTEST-verified; the unit tests cover the
## data resources, the control-lock state, and the no-op guards. Control lock is the static `is_active()` flag,
## which InputManager.gameplay_suppressed() reads (the sanctioned single place to register an overlay).

signal cutscene_started
signal cutscene_finished

## Player control is suppressed while ANY cutscene plays — InputManager.gameplay_suppressed() reads this static.
static var _active: bool = false
static func is_active() -> bool:
	return _active

@export var cutscene: Cutscene  ## the cutscene play() runs (so a TriggerVolume can fire it with no args)

var _cam: Camera3D
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _playing: bool = false
var _skip: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if _playing and event.is_action_pressed(&"ui_cancel"):
		_skip = true
		get_viewport().set_input_as_handled()

## Play this node's assigned cutscene (no-arg, for a TriggerVolume action).
func play() -> void:
	play_cutscene(cutscene)

## Run `c`'s actions in sequence, locking control for the duration. No-op if null / already playing / off-tree.
func play_cutscene(c: Cutscene) -> void:
	if c == null or _playing or not is_inside_tree():
		return
	_playing = true
	_skip = false
	_active = true
	cutscene_started.emit()
	for action in c.actions:
		if _skip:
			break
		if action != null:
			await _run_action(action)
	_finish()

func _finish() -> void:
	if _cam != null and is_instance_valid(_cam):
		_cam.current = false  # the gameplay camera reclaims `current`
	if _fade_rect != null and is_instance_valid(_fade_rect):
		_fade_rect.color.a = 0.0
	_active = false
	_playing = false
	cutscene_finished.emit()

func _run_action(a: CutsceneAction) -> void:
	match a.type:
		CutsceneAction.Type.WAIT:
			if a.duration > 0.0:
				await get_tree().create_timer(a.duration).timeout
		CutsceneAction.Type.SET_FLAG:
			if a.flag_name != &"":
				GameState.set_flag(a.flag_name, a.flag_value)
		CutsceneAction.Type.CALL_METHOD:
			var n := get_node_or_null(a.event_node_path)
			if n == null:
				push_warning("CutscenePlayer '%s': CALL_METHOD node %s did not resolve — step skipped." % [name, str(a.event_node_path)])
			elif a.event_method == &"" or not n.has_method(a.event_method):
				push_warning("CutscenePlayer '%s': node '%s' has no method '%s' — step skipped." % [name, str(n.name), str(a.event_method)])
			else:
				n.call(a.event_method)
		CutsceneAction.Type.DIALOGUE:
			if a.dialogue != null:
				DialogueManager.start(a.dialogue)
				await DialogueManager.dialogue_finished
		CutsceneAction.Type.CAMERA_MOVE:
			await _camera_move(a)
		CutsceneAction.Type.FADE:
			await _fade_to(a)
		CutsceneAction.Type.TOAST:
			if a.toast_text != "":
				UI.toast(a.toast_text, a.toast_color)

func _camera_move(a: CutsceneAction) -> void:
	var cam := _ensure_cam()
	if cam == null:
		return
	cam.current = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(cam, "global_position", a.camera_position, maxf(0.01, a.duration))
	tw.tween_property(cam, "global_rotation", a.camera_rotation * (PI / 180.0), maxf(0.01, a.duration))
	await tw.finished

func _fade_to(a: CutsceneAction) -> void:
	var rect := _ensure_fade()
	if rect == null:
		return
	var tw := create_tween()
	tw.tween_property(rect, "color", a.fade_color, maxf(0.01, a.duration))
	await tw.finished

## Lazily build the cinematic camera under the current scene (a Camera3D needs a spatial home in the world).
func _ensure_cam() -> Camera3D:
	if _cam != null and is_instance_valid(_cam):
		return _cam
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return null
	_cam = Camera3D.new()
	scene.add_child(_cam)
	return _cam

## Lazily build the full-screen fade overlay (its own CanvasLayer above the HUD).
func _ensure_fade() -> ColorRect:
	if _fade_rect != null and is_instance_valid(_fade_rect):
		return _fade_rect
	if not is_inside_tree():
		return null
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)
	return _fade_rect

## Editor warning: flag any CALL_METHOD step whose node path doesn't resolve or whose target lacks the named
## method (the wiring footgun — a typo'd method silently no-ops at runtime). An unassigned cutscene is fine (it
## may be set + played from code), so that draws no warning. NodePaths resolve relative to THIS player.
func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if cutscene == null:
		return w
	for a in cutscene.actions:
		if a == null or a.type != CutsceneAction.Type.CALL_METHOD:
			continue
		if a.event_node_path.is_empty() or a.event_method == &"":
			w.append("A CALL_METHOD step is missing its node path or method name.")
			continue
		var n := get_node_or_null(a.event_node_path)
		if n == null:
			w.append("CALL_METHOD node %s doesn't resolve to a node." % str(a.event_node_path))
		elif not n.has_method(a.event_method):
			w.append("CALL_METHOD target '%s' has no method `%s`." % [str(n.name), str(a.event_method)])
	return w
