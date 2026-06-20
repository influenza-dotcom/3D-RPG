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
var _caption_layer: CanvasLayer
var _caption_label: Label
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
	if _caption_label != null and is_instance_valid(_caption_label):
		_caption_label.visible = false  # clear a held caption so it doesn't linger after the cutscene
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
		CutsceneAction.Type.CAPTION:
			await _caption(a)

## Ease (or snap) the cinematic camera to a new framing: position, FOV (a dolly zoom), and either a fixed
## rotation or a live look-at that keeps a moving subject centred. A `camera_follow` node makes the target
## position track that subject (camera_position is then the offset). One tween_method(0→1) computes the whole
## frame per tick so position/follow/look-at/FOV stay in sync; `camera_snap` cuts instantly.
func _camera_move(a: CutsceneAction) -> void:
	var cam := _ensure_cam()
	if cam == null:
		return
	cam.current = true
	var start_pos := cam.global_position
	var start_basis := cam.global_transform.basis
	var start_fov := cam.fov
	var target_fov := a.camera_fov if a.camera_fov > 0.0 else start_fov
	var look_node := get_node_or_null(a.camera_look_at) as Node3D
	var follow_node := get_node_or_null(a.camera_follow) as Node3D
	if a.camera_snap:
		_apply_camera_frame(cam, a, 1.0, start_pos, start_basis, start_fov, target_fov, look_node, follow_node)
		return
	var tw := create_tween()
	tw.set_ease(a.camera_ease)
	tw.set_trans(a.camera_trans)
	tw.tween_method(
		func(t: float) -> void: _apply_camera_frame(cam, a, t, start_pos, start_basis, start_fov, target_fov, look_node, follow_node),
		0.0, 1.0, maxf(0.01, a.duration))
	await tw.finished

## Compute the camera's framing at interpolation `t` (0→1): lerp position toward the target (a followed node's
## live position + offset, else the absolute camera_position), lerp the FOV, and either look at the live subject
## or slerp the rotation toward camera_rotation. Pure enough to unit-test directly.
func _apply_camera_frame(cam: Camera3D, a: CutsceneAction, t: float, start_pos: Vector3, start_basis: Basis, start_fov: float, target_fov: float, look_node: Node3D, follow_node: Node3D) -> void:
	var end_pos := a.camera_position
	if follow_node != null:
		end_pos = follow_node.global_position + a.camera_position  # camera_position is the offset from the followed subject
	cam.global_position = start_pos.lerp(end_pos, t)
	cam.fov = lerpf(start_fov, target_fov, t)
	if look_node != null:
		var to := look_node.global_position
		if cam.global_position.distance_to(to) > 0.001:
			cam.look_at(to, Vector3.UP)  # keep the subject centred each frame
	else:
		var end_basis := Basis.from_euler(a.camera_rotation * (PI / 180.0))
		cam.global_transform.basis = start_basis.slerp(end_basis, t)

func _fade_to(a: CutsceneAction) -> void:
	var rect := _ensure_fade()
	if rect == null:
		return
	var tw := create_tween()
	tw.tween_property(rect, "color", a.fade_color, maxf(0.01, a.duration))
	await tw.finished

## Show a centred caption ("Three days later…") for `duration` seconds, then clear it. duration <= 0 holds it
## until the cutscene ends (_finish clears it). No-op off-tree (the caption needs the CanvasLayer in the world).
func _caption(a: CutsceneAction) -> void:
	var lbl := _ensure_caption()
	if lbl == null:
		return
	lbl.text = a.caption_text
	lbl.add_theme_color_override(&"font_color", a.caption_color)
	lbl.visible = a.caption_text != ""
	if a.duration > 0.0:
		await get_tree().create_timer(a.duration).timeout
		lbl.visible = false

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

## Lazily build the caption overlay: an outlined, centred Label on its own CanvasLayer ABOVE the fade rect
## (layer 101 > 100), so a caption reads over a faded-black screen. Hidden until a CAPTION step shows it.
func _ensure_caption() -> Label:
	if _caption_label != null and is_instance_valid(_caption_label):
		return _caption_label
	if not is_inside_tree():
		return null
	_caption_layer = CanvasLayer.new()
	_caption_layer.layer = 101  # above the fade rect's layer (100)
	add_child(_caption_layer)
	_caption_label = Label.new()
	_caption_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption_label.add_theme_color_override(&"font_color", Color(1, 1, 1))
	_caption_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
	_caption_label.add_theme_constant_override(&"outline_size", 8)
	_caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_label.visible = false
	_caption_layer.add_child(_caption_label)
	return _caption_label

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
