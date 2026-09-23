extends GutTest

## Slice 9 (cutscenes): CutscenePlayer's control lock, its start guards, step dispatch and the finish / skip /
## teardown release paths, driven through a REAL in-tree player running small Cutscene resources. A CALL_METHOD
## step aimed at a Probe node snapshots state MID-cutscene, so "locked while running" and "released after" are
## both observed. Camera tweens and dialogue stay playtest-verified; the per-frame camera framing math is driven
## directly. CutscenePlayer is loaded by PATH (cache-independent).

const CP_PATH := "res://scripts/components/cutscene_player.gd"
const FLAG := &"__test_cutscene_set_flag_step"

## A CutsceneActor stand-in: records every order the player gives it.
class StubActor extends Node:
	var began := false
	var ended := false
	var walked_to = null
	var faced = null
	var anim: StringName = &""
	func begin() -> void:
		began = true
	func end() -> void:
		ended = true
	func walk_to(p: Vector3) -> void:
		walked_to = p
	func face(p: Vector3) -> void:
		faced = p
	func play_anim(n: StringName) -> void:
		anim = n

## A CALL_METHOD target: counts calls to fire() and runs `on_fire` so a test can snapshot state mid-cutscene.
class Probe extends Node:
	var calls := 0
	var on_fire: Callable
	func fire() -> void:
		calls += 1
		if on_fire.is_valid():
			on_fire.call()

func after_each() -> void:
	# The lock is a process-global static: a failed assert mid-cutscene must not leave later files input-locked.
	load(CP_PATH).set("_active", false)
	GameState.flags.erase(String(FLAG))

func _player():
	var p = load(CP_PATH).new()
	add_child_autofree(p)
	return p

func _probe() -> Probe:
	var probe := Probe.new()
	add_child_autofree(probe)
	return probe

func _cutscene(steps: Array) -> Cutscene:
	var c := Cutscene.new()
	for s in steps:
		c.actions.append(s)
	return c

func _wait_step(seconds: float) -> CutsceneAction:
	var a := CutsceneAction.new()
	a.type = CutsceneAction.Type.WAIT
	a.duration = seconds
	return a

func _call_step(p: Node, target: Node, method: StringName = &"fire") -> CutsceneAction:
	var a := CutsceneAction.new()
	a.type = CutsceneAction.Type.CALL_METHOD
	a.event_node_path = p.get_path_to(target)
	a.event_method = method
	return a

func _set_flag_step(value: bool) -> CutsceneAction:
	var a := CutsceneAction.new()
	a.type = CutsceneAction.Type.SET_FLAG
	a.flag_name = FLAG
	a.flag_value = value
	return a

func _actor_step(p: Node, type: CutsceneAction.Type, actor: Node) -> CutsceneAction:
	var a := CutsceneAction.new()
	a.type = type
	a.actor_path = p.get_path_to(actor)
	a.duration = 0.0  # fire-and-continue: no timer hold
	return a

func _visible_label_text(p: Node) -> String:
	for n in p.find_children("*", "Label", true, false):
		var lbl := n as Label
		if lbl.visible:
			return lbl.text
	return ""

func _fade_alpha(p: Node) -> float:
	var alpha := -1.0
	for n in p.find_children("*", "ColorRect", true, false):
		alpha = (n as ColorRect).color.a
	return alpha

# --- The control lock ---------------------------------------------------------------------------------------------

func test_control_is_locked_while_steps_run_and_released_when_the_cutscene_ends() -> void:
	var p = _player()
	var probe := _probe()
	var seen := {}
	probe.on_fire = func() -> void: seen["active"] = p.is_active()
	watch_signals(p)
	assert_false(p.is_active(), "no cutscene has played yet, so player control must start unlocked")
	p.play_cutscene(_cutscene([_call_step(p, probe)]))
	assert_eq(probe.calls, 1, "the cutscene's CALL_METHOD step must run")
	assert_true(seen.get("active", false), "player control must be LOCKED while a cutscene step runs")
	assert_false(p.is_active(), "control must be RELEASED after the last step, or gameplay input stays dead all session")
	assert_signal_emit_count(p, "cutscene_started", 1, "cutscene_started fires once per cutscene")
	assert_signal_emit_count(p, "cutscene_finished", 1, "cutscene_finished fires once the steps are done")

func test_a_second_start_while_a_cutscene_is_playing_is_refused() -> void:
	var p = _player()
	var probe := _probe()
	watch_signals(p)
	var second := _cutscene([_call_step(p, probe)])
	p.play_cutscene(_cutscene([_wait_step(0.05)]))
	assert_true(p.is_active(), "the first cutscene is mid-WAIT, so control is locked")
	p.play_cutscene(second)  # a trigger volume re-firing mid-cutscene
	assert_eq(probe.calls, 0, "a start while a cutscene is already playing must be refused, not run an overlapping cutscene")
	assert_signal_emit_count(p, "cutscene_started", 1, "only the first cutscene may start")
	assert_true(p.is_active(), "the refused start must not disturb the running cutscene's lock")
	var finished: bool = await wait_for_signal(p.cutscene_finished, 2.0)
	assert_true(finished, "the first cutscene runs to its end")
	assert_false(p.is_active(), "control is released when the first cutscene ends")
	# CONTROL: the very same start is accepted once nothing is playing, so the refusal above was the in-flight guard.
	p.play_cutscene(second)
	assert_eq(probe.calls, 1, "once the first cutscene has finished, the player accepts a new one")

func test_starting_with_no_cutscene_or_off_tree_never_takes_the_lock() -> void:
	var p = _player()
	watch_signals(p)
	p.play()  # in-tree, but no cutscene assigned
	assert_signal_not_emitted(p, "cutscene_started", "play() with no cutscene assigned must not start anything")
	assert_false(p.is_active(), "play() with no cutscene assigned leaves control unlocked")
	var off = load(CP_PATH).new()
	off.cutscene = _cutscene([_wait_step(0.0)])
	var started := {"n": 0}
	off.cutscene_started.connect(func() -> void: started["n"] += 1)
	off.play()
	assert_eq(started["n"], 0, "an OFF-TREE player must refuse to start its cutscene")
	assert_false(off.is_active(), "an off-tree start must not take the lock: its steps would bail and strand input locked with nothing on screen")
	# CONTROL: the same cutscene on an in-tree player starts, runs, and releases.
	p.cutscene = off.cutscene
	p.play()
	assert_signal_emit_count(p, "cutscene_started", 1, "the same cutscene starts on an in-tree player")
	assert_signal_emit_count(p, "cutscene_finished", 1, "and runs to its end")
	assert_false(p.is_active(), "and releases control when it ends")
	off.free()

func test_leaving_the_tree_mid_cutscene_releases_the_lock_and_staged_actors_and_stops_the_steps() -> void:
	var p = _player()
	var actor := StubActor.new()
	add_child_autofree(actor)
	var walk := _actor_step(p, CutsceneAction.Type.WALK_TO, actor)
	walk.actor_point = Vector3(1, 0, 1)
	walk.duration = 0.05  # the walk holds on a timer: the cutscene is in flight when the level goes away
	p.play_cutscene(_cutscene([walk, _set_flag_step(true)]))
	assert_true(p.is_active(), "mid-walk the cutscene holds the control lock")
	assert_true(actor.began, "the WALK_TO step took its actor under cutscene control")
	assert_false(actor.ended, "the actor stays under cutscene control while the cutscene runs")
	remove_child(p)  # a RELOAD respawn / level swap pulls the player out of the tree mid-cutscene
	assert_false(p.is_active(), "leaving the tree mid-cutscene must release the lock, or input is locked all session with no cutscene visible")
	assert_true(actor.ended, "leaving the tree mid-cutscene must hand the staged actor back to its AI")
	await wait_seconds(0.2)  # let the abandoned walk timer fire
	assert_false(GameState.has_flag(FLAG), "the abandoned cutscene must NOT keep running its remaining steps off-tree")
	assert_false(p.is_active(), "the abandoned coroutine resuming must not re-take the lock")

func test_escape_skips_the_remaining_steps_and_still_releases_control() -> void:
	var p = _player()
	var probe := _probe()
	var c := _cutscene([_wait_step(0.05), _call_step(p, probe)])
	# CONTROL: unskipped, the step after the wait runs.
	p.play_cutscene(c)
	var first_done: bool = await wait_for_signal(p.cutscene_finished, 2.0)
	assert_true(first_done, "the unskipped cutscene runs to its end")
	assert_eq(probe.calls, 1, "unskipped, the step after the wait runs")
	p.play_cutscene(c)
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	p._unhandled_input(esc)
	var second_done: bool = await wait_for_signal(p.cutscene_finished, 2.0)
	assert_true(second_done, "a skipped cutscene still finishes (restoring the camera, fade and actors)")
	assert_eq(probe.calls, 1, "Escape must skip every step after the one in progress")
	assert_false(p.is_active(), "a skipped cutscene must release player control")

# --- Step dispatch ------------------------------------------------------------------------------------------------

func test_set_flag_and_call_method_steps_act_on_the_world_in_order() -> void:
	var p = _player()
	var probe := _probe()
	var seen := {}
	probe.on_fire = func() -> void: seen["flag_at_call"] = GameState.has_flag(FLAG)
	p.play_cutscene(_cutscene([_set_flag_step(false), _call_step(p, probe)]))
	assert_true(GameState.has_flag(FLAG), "a SET_FLAG step must write its story flag")
	assert_eq(GameState.get_flag(FLAG, true), false, "a SET_FLAG step must write the step's VALUE (false), not just mark it set")
	assert_eq(probe.calls, 1, "a CALL_METHOD step must call its method on the node its path names")
	assert_true(seen.get("flag_at_call", false), "steps run IN ORDER: the flag set by step 1 is already visible to step 2")

func test_actor_steps_drive_the_resolved_actor_and_a_target_node_overrides_the_raw_point() -> void:
	var p = _player()
	var actor := StubActor.new()
	add_child_autofree(actor)
	var marker := Node3D.new()
	add_child_autofree(marker)
	marker.global_position = Vector3(7, 0, -3)
	var probe := _probe()
	var seen := {}
	probe.on_fire = func() -> void: seen["ended_mid"] = actor.ended
	var walk := _actor_step(p, CutsceneAction.Type.WALK_TO, actor)
	walk.actor_target = p.get_path_to(marker)
	walk.actor_point = Vector3(100, 0, 100)  # must be ignored: the live marker wins
	var face := _actor_step(p, CutsceneAction.Type.FACE, actor)
	face.actor_point = Vector3(0, 0, 9)
	var anim := _actor_step(p, CutsceneAction.Type.PLAY_ANIM, actor)
	anim.anim_name = &"wave"
	p.play_cutscene(_cutscene([walk, face, anim, _call_step(p, probe)]))
	assert_true(actor.began, "an actor step must take its actor under cutscene control")
	assert_eq(actor.walked_to, Vector3(7, 0, -3), "WALK_TO heads for the actor_target node's live position, not the raw actor_point")
	assert_eq(actor.faced, Vector3(0, 0, 9), "FACE with no target node turns toward the raw actor_point")
	assert_eq(actor.anim, &"wave", "PLAY_ANIM plays the step's animation on the actor")
	assert_false(seen.get("ended_mid", true), "the actor must stay under cutscene control between steps")
	assert_true(actor.ended, "the actor is handed back to its AI when the cutscene ends")

func test_a_held_caption_shows_during_the_cutscene_and_is_cleared_at_the_end() -> void:
	var p = _player()
	var probe := _probe()
	var seen := {}
	probe.on_fire = func() -> void: seen["caption"] = _visible_label_text(p)
	var cap := CutsceneAction.new()
	cap.type = CutsceneAction.Type.CAPTION
	cap.caption_text = "Three days later"
	cap.duration = 0.0  # hold until the cutscene ends
	p.play_cutscene(_cutscene([cap, _call_step(p, probe)]))
	assert_eq(seen.get("caption", ""), "Three days later", "a CAPTION step shows its text on screen for the following steps")
	assert_eq(_visible_label_text(p), "", "a held caption must be cleared when the cutscene ends, not linger over gameplay")

func test_a_fade_to_black_is_lifted_when_the_cutscene_ends() -> void:
	var p = _player()
	var probe := _probe()
	var seen := {}
	probe.on_fire = func() -> void: seen["alpha"] = _fade_alpha(p)
	var fade := CutsceneAction.new()
	fade.type = CutsceneAction.Type.FADE
	fade.fade_color = Color(0, 0, 0, 1)
	fade.duration = 0.02
	p.play_cutscene(_cutscene([fade, _call_step(p, probe)]))
	var done: bool = await wait_for_signal(p.cutscene_finished, 2.0)
	assert_true(done, "the fading cutscene runs to its end")
	var mid_alpha: float = seen.get("alpha", -1.0)
	assert_almost_eq(mid_alpha, 1.0, 0.01, "the FADE step eases the screen to opaque black before the next step runs")
	assert_almost_eq(_fade_alpha(p), 0.0, 0.001, "the fade must be lifted when the cutscene ends, or gameplay resumes behind a black screen")

func test_editor_warns_about_call_method_steps_that_would_silently_no_op() -> void:
	var p = _player()
	var probe := _probe()
	p.cutscene = _cutscene([_call_step(p, probe, &"fire")])
	assert_eq(p._get_configuration_warnings().size(), 0, "a correctly wired CALL_METHOD step draws no warning")
	p.cutscene = _cutscene([_call_step(p, probe, &"fier")])
	var typo: PackedStringArray = p._get_configuration_warnings()
	assert_eq(typo.size(), 1, "a CALL_METHOD step naming a method its target lacks must be flagged in the editor")
	var dangling := _call_step(p, probe)
	dangling.event_node_path = NodePath("NoSuchNode")
	p.cutscene = _cutscene([dangling])
	var unresolved: PackedStringArray = p._get_configuration_warnings()
	assert_eq(unresolved.size(), 1, "a CALL_METHOD step whose node path resolves to nothing must be flagged in the editor")

# --- Camera framing ------------------------------------------------------------------------------------------------

## The follow + FOV math at t=1 — driven directly (the full tween/camera staging is playtest-verified).
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

func test_camera_frame_with_a_look_at_subject_points_at_it_instead_of_the_authored_rotation() -> void:
	var p = _player()
	var cam := Camera3D.new()
	add_child_autofree(cam)
	var subject := Node3D.new()
	add_child_autofree(subject)
	subject.global_position = Vector3(10, 0, 0)
	var a := CutsceneAction.new()
	a.type = CutsceneAction.Type.CAMERA_MOVE
	a.camera_position = Vector3.ZERO
	a.camera_rotation = Vector3(0, 90, 0)  # a yaw of +90 degrees faces -X, away from the subject
	p._apply_camera_frame(cam, a, 1.0, Vector3.ZERO, Basis.IDENTITY, 60.0, 60.0, subject, null)
	var forward := -cam.global_transform.basis.z
	assert_lt(forward.distance_to(Vector3(1, 0, 0)), 0.01, "a look-at subject must be centred: the camera faces +X toward it, got %s" % forward)
	# CONTROL: with no look-at subject the same step turns to its authored rotation instead.
	p._apply_camera_frame(cam, a, 1.0, Vector3.ZERO, Basis.IDENTITY, 60.0, 60.0, null, null)
	forward = -cam.global_transform.basis.z
	assert_lt(forward.distance_to(Vector3(-1, 0, 0)), 0.01, "with no look-at subject a yaw of +90 faces -X, got %s" % forward)
	a = null

## _finish ALWAYS releases every staged actor — the "never leave an NPC frozen" guarantee.
func test_finish_releases_engaged_actors() -> void:
	var p = load(CP_PATH).new()
	add_child_autofree(p)
	var stub := StubActor.new()
	add_child_autofree(stub)
	p._actors.append(stub)
	p._finish()
	assert_true(stub.ended, "_finish releases every engaged actor")
