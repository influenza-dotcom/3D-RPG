extends Node
## THIRD-PERSON probe (2026-09-17): the pull-out camera + the character it reveals. Drives the REAL game — boot,
## equip, toggle to third person, then walk / look down / crouch / back into a wall — shooting a PNG per beat and
## printing the numbers no screenshot can settle: how far the lens actually got, how the body was fitted, whether
## the feet are on the floor and the head on the lens, and whether the first-person cosmetics really left.
##
## Run WINDOWED (shaders never compile headless), from PowerShell:
##   & "<godot exe>" --path "C:\Users\dalla\3D RPG\rpg" res://scripts/tools/probes/__third_person_probe.tscn
## Frames land in user://third_person_probe.
##
## ⭐It writes `Settings.third_person_camera` DIRECTLY rather than through `set_third_person_camera`, and puts it
## back at the end: the setter persists to user://settings.cfg, and a probe must not leave the player's own
## preference flipped.
##
## What each printed line is for:
##   • `QA_F`     — per frame: blend, how far back the lens actually got, the fitted body scale, the soles'
##                  clearance over the floor, the head's error against the lens, and whether the first-person
##                  view model / legs are still on screen.
##   • `QA_TREE`  — every node under the rig with its `visible` flag and render layers. ⭐THIS IS THE LINE THAT
##                  FOUND THE ORIGINAL BUG: with the swap named "Body", every real `Cube` mesh read
##                  `vis=false` while the swap and its tint duplicates read visible, so the character was
##                  present and correctly placed and simply never drawn (see `ThirdPersonBody.RIG_NAME`).
##   • `QA_RIG`   — what the rig actually renders, in player-local metres and then in screen pixels. The size
##                  question ("is the character too small?") is only answerable against these two numbers.
##   • `QA_SPRING`— the wall test, run TWICE: 8 m of arm in open air (which must stay 8 m) and the same ask with
##                  the character turned to face a building (which must collapse to under a metre). One reading
##                  alone proves nothing — an open street looks exactly like a spring that never casts.
## It also lights the character with a work lamp from the first third-person frame on: the street is dark and
## heavily colour-graded, and an unlit character is a silhouette in which no pose question can be settled.

var _dir := "user://third_person_probe"
var _frames_img: Array[Image] = []
var _frames_tag: Array[String] = []
var _player = null
var _ws = null
var _gm = null
var _arm = null
var _tp = null
var _was_third: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "ThirdPersonDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _frames(5)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(150)
	_player = Groups.human_player(get_tree())
	if _player == null:
		print("QA_FAIL no Player"); get_tree().quit(1); return
	InputManager.close_all_modals()
	await _frames(5)
	_ws = _player.get("weapon_system")
	_gm = _player.find_child("GunMesh", true, false)
	_arm = _player.head.camera_arm
	_tp = _player.tp_body
	print("QA_WIRE arm=%s tp_body=%s gun=%s" % [_arm != null, _tp != null, _gm != null])
	if _arm == null or _tp == null:
		print("QA_FAIL the rig is missing the third-person parts"); get_tree().quit(1); return
	_was_third = Settings.third_person_camera
	var wc = get_node_or_null("/root/WorldClock")
	if wc != null and wc.has_method("set_time_of_day"):
		wc.call("set_time_of_day", 0.5)
	_ws.attack.set_holstered(false)
	_ws.inventory.equip(load("res://resources/weapons/smg.tres"))
	await _wait(1.5)
	_gm.call("_equip_view_model")
	await _wait(0.5)
	_player.rotation.y += PI  # face the open street rather than the spawn's fence line
	await _wait(0.5)

	# --- FIRST person baseline: the gun is out, the FP body is the thing under the lens.
	await _grab("01_first_person", 2)

	# --- The toggle. Frames straight through the ease so the pull-out itself can be judged, not just its end.
	Settings.third_person_camera = true
	for i in 6:
		await _grab("02_pulling_out", 1)
		await _wait(0.06)
	await _wait(1.0)
	await _grab("03_third_person_idle", 2)
	_dump_rig()
	# A work light on the character for the rest of the run. The street is dark and the look is heavily
	# colour-graded, so an unlit character is a silhouette and every framing/pose question is unanswerable.
	var lamp := OmniLight3D.new()
	lamp.light_energy = 6.0
	lamp.omni_range = 6.0
	_player.add_child(lamp)
	lamp.position = Vector3(0.0, 0.6, 1.2)  # behind + above the character, between them and the lens
	await _wait(0.5)
	await _grab("03b_lit_idle", 1)

	# --- Walking: the gait, the held weapon, and whether the legs steer with travel.
	Input.action_press("forward")
	await _wait(1.2)
	await _grab("04_walking", 3)
	Input.action_release("forward")
	await _wait(0.8)

	# --- Look UP and DOWN: the held gun's barrel should follow the aim; the character should not.
	_player.head.rotation_degrees.x = 35.0
	await _wait(0.6)
	await _grab("05_look_up", 1)
	_player.head.rotation_degrees.x = -40.0
	await _wait(0.6)
	await _grab("06_look_down", 1)
	_player.head.rotation_degrees.x = 0.0
	await _wait(0.4)

	# --- CROUCH: the fit is derived from the live eye height, so the character must duck with the capsule and
	# keep its soles on the floor (no animation exists — this is the whole crouch story).
	Input.action_press("Crouch")
	await _wait(1.2)
	await _grab("07_crouched", 2)
	Input.action_release("Crouch")
	await _wait(1.2)

	# --- FRAMING SWEEP. The resting FOV is 120 degrees, which is very wide, and the character is only 1.15 m
	# tall (fitted to a 1.0 m eye — the same reason FirstPersonBody scales its rig to 0.60), so "how far back"
	# is not a number to reason about: at 2.2 m they are 15% of the frame height, which reads as a doll in the
	# distance. Shoot the candidates and pick by sight.
	var authored_distance: float = _arm.distance
	for d in [1.6, 2.2, 2.8, 3.4]:
		Settings.set_third_person_distance(d)
		await _wait(0.9)
		await _grab("08_dist_%.1f" % d, 1)
	Settings.set_third_person_distance(authored_distance)
	await _wait(0.8)

	# --- The WHEEL owns the distance while the view is out. Sent as REAL notches through the input stack, so
	# this also proves the hotbar yields them instead of cycling a weapon underneath.
	var before_wheel: float = _arm.distance
	var slot_before = _ws.inventory.equipped_weapon
	for i in 4:
		_notch(MOUSE_BUTTON_WHEEL_DOWN)
		await get_tree().process_frame
	await _wait(0.6)
	print("QA_WHEEL 4 notches out: %.2f -> %.2f m, equipped weapon %s" % [before_wheel, _arm.distance,
		"UNCHANGED (hotbar yielded)" if _ws.inventory.equipped_weapon == slot_before else "CHANGED (the bar stole the notch)"])
	await _grab("08c_wheeled_out", 1)
	for i in 4:
		_notch(MOUSE_BUTTON_WHEEL_UP)
		await get_tree().process_frame
	await _wait(0.6)
	print("QA_WHEEL back in: %.2f m" % [_arm.distance])

	# --- FREE LOOK: the held-middle-mouse orbit. Driven through the arm's own seam (MouseInput would need a
	# captured mouse to generate motion), with the hold latched the way a real press latches it.
	_arm.set("_press_us", Time.get_ticks_usec() - 1_000_000)  # a press that is already long past the tap window
	await _wait(0.3)
	print("QA_FREELOOK active=%s" % [_arm.free_look_active()])
	for i in 8:
		_arm.orbit(Vector2(28.0, 0.0))
		await get_tree().process_frame
	await _wait(0.3)
	await _grab("08d_free_look_yaw", 1)
	for i in 6:
		_arm.orbit(Vector2(0.0, -20.0))
		await get_tree().process_frame
	await _wait(0.3)
	await _grab("08e_free_look_pitch", 1)
	var cam_up: Vector3 = _player.camera_effects.global_basis.y
	print("QA_FREELOOK orbit=%s aim_dir=%s head_fwd=%s (must match while free-looking)" % [
		_arm.get("_orbit"), _player.get_aim_direction().normalized(), (-_player.head.global_basis.z).normalized()])
	# A swung camera must not ROLL: yaw belongs about the world up and pitch about the resulting local right, so
	# the camera's RIGHT vector stays horizontal. `right.y` is that test in one number — the horizon tipping is
	# otherwise indistinguishable from wide-FOV distortion in a screenshot.
	print("QA_FREELOOK camera right.y=%+.4f (roll: must be ~0)   up=%s" % [
		_player.camera_effects.global_basis.x.y, cam_up])
	print("QA_FREELOOK camera height above the eye=%+.2f m (mouse was pushed UP: must be POSITIVE)" % [
		_player.camera_effects.global_position.y - _player.head.global_position.y])
	_arm.set("_press_us", -1)
	_arm.set("_free_looking", false)
	await _wait(1.2)
	await _grab("08f_orbit_returned", 1)
	print("QA_FREELOOK after release orbit=%s (must be ~zero)" % [_arm.get("_orbit")])

	# ...and the WALL CHECK, forced rather than walked into: ask for 8 m of arm in a street that has nothing like
	# 8 m of clear air behind the player. If the spring is doing its job, the lens stops short of the ask.
	Settings.set_third_person_distance(Settings.TP_DISTANCE_MAX)
	await _wait(1.2)
	await _grab("08_wall_open_air", 1)
	print("QA_SPRING open air: asked %.2f m, lens settled at %.2f m" % [Settings.TP_DISTANCE_MAX, _lens_back()])
	# ...and the same ask with the character TURNED AROUND, so the arm reaches into the building front they were
	# facing. This is the one that proves the cast: a lens that still lands 8 m out here is a spring doing nothing.
	_player.rotation.y += PI
	await _wait(1.2)
	await _grab("08b_wall_pullin", 1)
	print("QA_SPRING against the wall: asked %.2f m, lens settled at %.2f m (must be far shorter)" % [
		Settings.TP_DISTANCE_MAX, _lens_back()])
	_player.rotation.y -= PI
	await _wait(0.8)
	Settings.set_third_person_distance(authored_distance)
	await _wait(1.0)

	# --- WHAT IS ACTUALLY ON SCREEN: the two halves, separately.
	await _grab("09_lit_both", 1)
	var hand: Node3D = _tp.get("_hand")
	if hand != null:
		hand.visible = false
	await _wait(0.4)
	await _grab("10_lit_body_only", 1)
	if hand != null:
		hand.visible = true
	var swap_node: Node3D = _tp.get("_swap")
	if swap_node != null:
		swap_node.visible = false
	await _wait(0.4)
	await _grab("11_lit_gun_only", 1)
	if swap_node != null:
		swap_node.visible = true
	await _wait(0.5)

	# --- HOLSTERED, then unarmed: the character's hands must empty, and the FP fists must not come back.
	_ws.attack.set_holstered(true)
	await _wait(1.0)
	await _grab("09_holstered", 1)
	_ws.attack.set_holstered(false)
	await _wait(0.8)

	# --- ADS drops back to first person for the sight picture, and the view model comes straight back with it.
	Input.action_press("Zoom")
	await _wait(1.2)
	await _grab("10_ads_back_to_first", 2)
	Input.action_release("Zoom")
	await _wait(1.2)
	await _grab("11_third_person_again", 1)

	lamp.queue_free()
	Settings.third_person_camera = _was_third
	await _wait(1.0)
	await _grab("12_back_to_first", 1)

	for i in _frames_img.size():
		var p := _dir.path_join("%02d_%s.png" % [i, _frames_tag[i]])
		_frames_img[i].save_png(ProjectSettings.globalize_path(p))
	print("QA_DONE ", ProjectSettings.globalize_path(_dir), " frames=", _frames_img.size())
	get_tree().quit(0)

## Everything a still cannot answer, per frame. `head_err` is the one that matters most: the character's head
## must land ON the camera pivot (the eye), because that is the point the lens orbits.
func _log(tag: String) -> void:
	var head = _player.head
	var cam = _player.camera_effects
	var swap = _tp.get("_swap")
	var body_k := 0.0
	var soles := 0.0
	var head_err := 0.0
	if swap != null:
		body_k = swap.scale.y
		soles = swap.position.y - _tp.FEET_BELOW_ORIGIN * body_k - _tp.get("_floor_y")
		head_err = swap.position.y + _tp.HEAD_ABOVE_ORIGIN * body_k - head.position.y
	var back := 0.0
	if cam != null:
		back = head.global_position.distance_to(cam.global_position)
	print("QA_F %-22s blend=%.2f lens_back=%.2f  body_scale=%.3f soles_above_floor=%+.3f head_above_eye=%+.3f  shown=%s gun_vm=%s fp_legs=%s eye_y=%+.3f" % [
		tag, _arm.blend, back, body_k, soles, head_err,
		_tp.is_shown(), (_gm.visible if _gm != null else false),
		_fp_legs_visible(), head.position.y])

## What the rig ACTUALLY renders, in PLAYER-LOCAL metres: every visual under the swap with its own vertical
## extent, plus the union. The fit arithmetic is only as good as the two model constants it is built on
## (HEAD_ABOVE_ORIGIN / FEET_BELOW_ORIGIN), and this is the measurement that says whether they are true.
func _dump_rig() -> void:
	var swap = _tp.get("_swap")
	if swap == null:
		print("QA_RIG no swap"); return
	var lo := INF
	var hi := -INF
	for n in _walk(swap):
		print("QA_TREE   %-26s %-18s vis=%s layers=%d" % [n.name, n.get_class(),
			(n as Node3D).visible if n is Node3D else "-",
			(n as VisualInstance3D).layers if n is VisualInstance3D else -1])
	for n in _walk(swap):
		var vi := n as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var ab := vi.get_aabb()
		var inv: Transform3D = (_player as Node3D).global_transform.affine_inverse()
		var xf: Transform3D = inv * vi.global_transform
		var a: float = (xf * ab.position).y
		var b: float = (xf * (ab.position + ab.size)).y
		print("QA_RIG   %-28s y %+.3f .. %+.3f" % [vi.name, minf(a, b), maxf(a, b)])
		lo = minf(lo, minf(a, b))
		hi = maxf(hi, maxf(a, b))
	var head_node: Node3D = _player.head
	print("QA_RIG TOTAL y %+.3f .. %+.3f  (height %.3f m)  floor=%+.3f eye=%+.3f" % [
		lo, hi, hi - lo, float(_tp.get("_floor_y")), head_node.position.y])
	# ...and where that lands ON SCREEN, so a still can be read against a number instead of by eye.
	var cam: Camera3D = _player.camera_effects
	var body: Node3D = _player
	var p_lo := cam.unproject_position(body.to_global(Vector3(0.0, lo, 0.0)))
	var p_hi := cam.unproject_position(body.to_global(Vector3(0.0, hi, 0.0)))
	print("QA_RIG SCREEN feet=%s head=%s  (%d px tall of %d)" % [
		p_lo, p_hi, int(absf(p_lo.y - p_hi.y)), get_viewport().get_visible_rect().size.y])

func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

## Push a REAL wheel notch through the input stack (press + release), so the whole ownership chain runs —
## ThirdPersonCamera consuming it and the hotbar yielding — rather than just calling the setter.
func _notch(button: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)

func _lens_back() -> float:
	var head_node: Node3D = _player.head
	var cam: Camera3D = _player.camera_effects
	return head_node.global_position.distance_to(cam.global_position)

func _fp_legs_visible() -> bool:
	var fp = _player.fp_body
	if fp == null:
		return false
	var legs = fp.get("_fp_legs")
	return legs != null and is_instance_valid(legs) and legs.visible

func _grab(tag: String, n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		_frames_img.append(get_viewport().get_texture().get_image())
		_frames_tag.append(tag)
		_log(tag)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
