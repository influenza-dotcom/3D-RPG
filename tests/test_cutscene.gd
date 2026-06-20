extends GutTest

## Slice 9 (cutscenes): the data resources + CutscenePlayer's control-lock state + no-op guards. Actual playback
## (camera eases, fades, dialogue, the action sequence) drives cameras + the tree and is PLAYTEST-verified, not
## unit-tested. CutscenePlayer is loaded by PATH (cache-independent).

const CP_PATH := "res://scripts/components/cutscene_player.gd"

func test_action_defaults() -> void:
	var a := CutsceneAction.new()
	assert_eq(a.type, CutsceneAction.Type.WAIT, "an action defaults to WAIT")
	assert_almost_eq(a.duration, 1.0, 0.001, "default duration is 1s")
	assert_true(a.flag_value, "set-flag value defaults true")
	a = null

func test_cutscene_defaults() -> void:
	var c := Cutscene.new()
	assert_true(c.actions.is_empty(), "no actions by default")
	c = null

func test_is_active_default_and_null_play_is_noop() -> void:
	var p = load(CP_PATH).new()
	assert_false(p.is_active(), "no cutscene active until one plays")
	p.play()  # no cutscene assigned (and off-tree) -> no-op
	assert_false(p.is_active(), "play() with no cutscene leaves control unlocked")
	p.free()

func test_toast_action_type_and_fields() -> void:
	var a := CutsceneAction.new()
	a.type = CutsceneAction.Type.TOAST
	assert_eq(a.type, CutsceneAction.Type.TOAST, "TOAST is a valid CutsceneAction type (rank 23)")
	assert_eq(a.toast_text, "", "toast_text defaults empty")
	assert_eq(a.toast_color, Color(1, 1, 1, 1), "toast_color defaults white")
	a = null

func test_caption_action_type_and_fields() -> void:
	var a := CutsceneAction.new()
	a.type = CutsceneAction.Type.CAPTION
	assert_eq(a.type, CutsceneAction.Type.CAPTION, "CAPTION is a valid CutsceneAction type (rank 13)")
	assert_eq(a.caption_text, "", "caption_text defaults empty")
	assert_eq(a.caption_color, Color(1, 1, 1, 1), "caption_color defaults white")
	a = null

func test_camera_move_fields_default() -> void:
	var a := CutsceneAction.new()
	a.type = CutsceneAction.Type.CAMERA_MOVE
	assert_eq(a.camera_fov, 0.0, "camera_fov defaults 0 (unchanged)")
	assert_false(a.camera_snap, "camera_snap defaults off")
	assert_eq(a.camera_ease, Tween.EASE_IN_OUT, "default ease is in-out")
	assert_eq(a.camera_trans, Tween.TRANS_SINE, "default trans is sine")
	assert_true(a.camera_look_at.is_empty(), "no look-at by default")
	assert_true(a.camera_follow.is_empty(), "no follow by default")
	a = null

## The follow + FOV math at t=1 (rank 12) — driven directly (the full tween/camera staging is playtest-verified).
func test_apply_camera_frame_follow_and_fov() -> void:
	var p = load(CP_PATH).new()
	add_child_autofree(p)
	var cam := Camera3D.new()
	add_child_autofree(cam)
	var subject := Node3D.new()
	add_child_autofree(subject)
	subject.global_position = Vector3(10, 0, 0)
	var a := CutsceneAction.new()
	a.type = CutsceneAction.Type.CAMERA_MOVE
	a.camera_position = Vector3(0, 2, 5)  # offset from the followed subject
	p._apply_camera_frame(cam, a, 1.0, Vector3.ZERO, cam.global_transform.basis, 60.0, 40.0, null, subject)
	assert_almost_eq(cam.global_position.x, 10.0, 0.01, "follows subject + offset on x at t=1")
	assert_almost_eq(cam.global_position.z, 5.0, 0.01, "follows subject + offset on z at t=1")
	assert_almost_eq(cam.fov, 40.0, 0.01, "FOV eased to the target at t=1")
	a = null
