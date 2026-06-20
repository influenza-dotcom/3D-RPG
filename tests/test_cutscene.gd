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
