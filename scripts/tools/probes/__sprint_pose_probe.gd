extends Node
## One-off probe (2026-09-16): the view-model SPRINT pose + "you can't shoot while sprinting". Drives the real game:
## walk, sprint, pull the trigger mid-sprint, and logs the sprint blend / fire gate / lockout per frame, plus PNGs.
## Run WINDOWED (shaders never compile headless), from PowerShell:
##   & "<godot exe>" --path "C:\Users\dalla\3D RPG\rpg" res://scripts/tools/probes/__sprint_pose_probe.tscn
## Frames land in user://sprint_pose_probe.

var _dir := "user://sprint_pose_probe"
var _frames_img: Array[Image] = []
var _frames_tag: Array[String] = []
var _shots: int = 0
var _last_shot_msec: int = 0
var _player = null
var _ws = null
var _gm = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "SprintPoseDriver"
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
	print("QA_MODAL any_open=", InputManager.any_modal_open(), " supp=", InputManager.gameplay_suppressed())
	_ws = _player.get("weapon_system")
	_ws.attack.set_holstered(false)
	_ws.attack.flash_muzzle.connect(func() -> void:
		_shots += 1
		_last_shot_msec = Time.get_ticks_msec())
	_gm = _player.find_child("GunMesh", true, false)
	var wc = get_node_or_null("/root/WorldClock")
	if wc != null and wc.has_method("set_time_of_day"):
		wc.call("set_time_of_day", 0.5)
	_player.rotation.y += PI  # face away from the spawn's fence line, toward open street
	await _frames(90)

	# --- SMG (automatic): walk, sprint, hold the trigger mid-sprint, then keep Run held and watch sprint resume.
	await _equip("res://resources/weapons/smg.tres")
	Input.action_press("forward")
	await _wait(1.0)
	await _grab("smg_walk", 1)
	Input.action_press("Run")
	await _wait(1.0)
	await _grab("smg_sprint", 2)
	var press := Time.get_ticks_msec()
	var shots_before := _shots
	Input.action_press("Attack")
	for i in 12:
		await _grab("smg_fire", 1)
	print("QA_RESULT smg first shot %d ms after the trigger pull" % [(_last_shot_msec - press) if _shots > shots_before else -1])
	Input.action_release("Attack")
	var release := Time.get_ticks_msec()
	var resumed := -1
	for i in 120:
		await get_tree().process_frame
		if resumed < 0 and _player.is_sprinting():
			resumed = Time.get_ticks_msec() - _last_shot_msec
		if i % 6 == 0:
			_log("smg_after", i)
	print("QA_RESULT smg sprint resumed %d ms after the last shot (lockout %.2f s); release was %d ms after the last shot" % [
		resumed, GameSettings.player_movement.sprint_attack_lockout, release - _last_shot_msec])

	# --- Pistol (semi-auto): a ONE-FRAME tap mid-sprint must still fire, once the gun is up.
	await _equip("res://resources/weapons/pistol.tres")
	await _wait(1.0)
	await _grab("pistol_sprint", 1)
	press = Time.get_ticks_msec()
	shots_before = _shots
	Input.action_press("Attack")
	await get_tree().process_frame
	await get_tree().physics_frame
	Input.action_release("Attack")
	for i in 20:
		await _grab("pistol_tap", 1)
	print("QA_RESULT pistol tap shots=%d first shot %d ms after the tap" % [_shots - shots_before,
		(_last_shot_msec - press) if _shots > shots_before else -1])
	await _wait(1.0)

	# --- Knife + spray can + shotgun: the pose on the other view models.
	for path in ["res://resources/weapons/melee.tres", "res://resources/weapons/spray_paint.tres", "res://resources/weapons/shotgun.tres"]:
		await _equip(path)
		await _wait(1.0)
		await _grab("sprint_" + path.get_file().get_basename(), 1)

	# --- Fists: a punch mid-sprint swings at once (no sprint pose to come up out of) and still ends the sprint.
	await _equip("res://resources/weapons/fists.tres")
	await _wait(1.0)
	press = Time.get_ticks_msec()
	shots_before = _shots
	Input.action_press("Attack")
	for i in 10:
		await get_tree().process_frame
		_log("fists_punch", i)
	Input.action_release("Attack")
	print("QA_RESULT fists punch shots=%d first swing %d ms after the click" % [_shots - shots_before,
		(_last_shot_msec - press) if _shots > shots_before else -1])

	Input.action_release("Run")
	Input.action_release("forward")
	for i in _frames_img.size():
		var p := _dir.path_join("%02d_%s.png" % [i, _frames_tag[i]])
		_frames_img[i].save_png(ProjectSettings.globalize_path(p))
	print("QA_DONE ", ProjectSettings.globalize_path(_dir), " frames=", _frames_img.size())
	get_tree().quit(0)

func _equip(path: String) -> void:
	_ws.inventory.equip(load(path))
	await _wait(1.5)
	_gm.call("_equip_view_model")  # the swap's own re-mount can land late; mount it now so the frames show THIS weapon
	await _wait(0.3)
	_refill()
	if _ws.ammo.has_method("set_to_max_ammo"):
		_ws.ammo.set_to_max_ammo()
	print("QA_EQUIP ", path, " mounted=", _gm.mounted_weapon().resource_path if _gm.mounted_weapon() else "none")

## Full stamina and no exhaustion lockout, so each phase starts able to sprint. Never called mid-phase: that would
## also wipe the post-attack lockout the phase is measuring.
func _refill() -> void:
	_player._set_stamina(_player.stamina_max())
	_player._stamina_mgr._sprint_lockout_left = 0.0

func _log(tag: String, i: int) -> void:
	var pose = _gm.get("_pose")
	print("QA_F %s %02d sprinting=%s can=%s held=%s t=%.3f lowered=%s raised=%s shots=%d speed=%.2f on_floor=%s gun_pos=%s gun_rot=%s" % [
		tag, i, _player.is_sprinting(), _player.can_sprint(), pose.get("_sprint_held"), pose.get("_sprint_t"),
		_ws.attack.sprint_lowered, _ws.attack.gun_raised, _shots,
		Vector2(_player.velocity.x, _player.velocity.z).length(), _player.is_on_floor(), _gm.position, _gm.rotation_degrees])

func _grab(tag: String, n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		_frames_img.append(get_viewport().get_texture().get_image())
		_frames_tag.append(tag)
		_log(tag, i)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
