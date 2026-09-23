extends Node
## One-off probe (2026-09-16): capture consecutive frames while ADS-firing the SMG to see what strobes.
## Run windowed (shaders never compile headless):
##   godot --path "C:\Users\dalla\3D RPG\rpg" res://scripts/tools/probes/__smg_ads_strobe_probe.tscn

var _dir := "user://smg_ads_strobe"
var _frames_img: Array[Image] = []
var _frames_tag: Array[String] = []
var _shots: int = 0
var _ws = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "SmgAdsStrobeDriver"
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
	var player: Node3D = Groups.human_player(get_tree())
	if player == null:
		print("QA_FAIL no Player"); get_tree().quit(1); return
	for e in InputManager._modal_reg:
		if e.screen.is_open():
			print("QA_MODAL_OPEN ", e.screen)
	InputManager.close_all_modals()
	await _frames(5)
	print("QA_MODAL after_close any_open=", InputManager.any_modal_open(), " supp=", InputManager.gameplay_suppressed())
	var ws = player.get("weapon_system")
	_ws = ws
	var attack = ws.attack
	attack.set_holstered(false)
	await _frames(90)
	var inv = ws.inventory
	inv.equip(load("res://resources/weapons/smg.tres"))
	await _wait(1.5)
	ws.ammo.set_to_max_ammo()
	attack.flash_muzzle.connect(func() -> void: _shots += 1)
	DisplayServer.window_move_to_foreground()
	var gm := player.find_child("GunMesh", true, false)
	if gm != null and gm.has_method("_equip_view_model"):
		gm.call("_equip_view_model")
		await _wait(0.6)
	var cam := player.find_child("Camera3D", true, false) as Camera3D
	var wc = get_node_or_null("/root/WorldClock")
	if wc != null and wc.has_method("set_time_of_day"):
		wc.call("set_time_of_day", 0.5)
	var head := player.find_child("Head", true, false) as Node3D
	if head: head.rotation.x = deg_to_rad(3.0)
	await _frames(60)
	var mf := player.find_child("MuzzleFlashMesh", true, false) as Node3D
	var lf := player.find_child("LightFlash", true, false) as Node3D
	var shake := player.find_child("ScreenShake", true, false) as Node3D
	print("QA_TEST_PARSE ", load("res://tests/test_view_model_kick_ads.gd") != null, " ", load("res://tests/test_muzzle_flash_hold.gd") != null)
	print("QA_KICK_MULT ", GameSettings.effects.view_model_kick_ads_mult)
	print("QA_SETUP weapon=", inv.equipped_weapon.resource_path, " fov=", cam.fov, " mf=", mf, " lf=", lf, " shake=", shake)
	await _grab("hip", cam, gm, mf, lf, shake, 2)
	Input.action_press("Zoom")
	await _wait(1.2)
	await _grab("ads_idle", cam, gm, mf, lf, shake, 12)
	Input.action_press("Attack")
	await _grab("ads_fire", cam, gm, mf, lf, shake, 40)
	Input.action_release("Attack")
	await _wait(0.3)
	Input.action_release("Zoom")
	await _wait(1.0)
	Input.action_press("Attack")
	await _grab("hip_fire", cam, gm, mf, lf, shake, 24)
	Input.action_release("Attack")
	for i in _frames_img.size():
		var p := _dir.path_join("%02d_%s.png" % [i, _frames_tag[i]])
		_frames_img[i].save_png(ProjectSettings.globalize_path(p))
	print("QA_DONE ", ProjectSettings.globalize_path(_dir), " frames=", _frames_img.size())
	get_tree().quit(0)

func _grab(tag: String, cam: Camera3D, gm: Node3D, mf: Node3D, lf: Node3D, shake: Node3D, n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		_frames_img.append(get_viewport().get_texture().get_image())
		_frames_tag.append(tag)
		print("QA_F %s %02d fov=%.2f mf=%s lf=%s shake=%s gun=%s dt=%.4f shots=%d scoped=%s zoomheld=%s supp=%s holst=%s raised=%s ammo=%d cam=%s" % [tag, i, cam.fov,
			(mf.visible if mf else "?"), (lf.visible if lf else "?"),
			(shake.rotation_degrees if shake else Vector3.ZERO), (gm.position if gm else Vector3.ZERO),
			get_process_delta_time(), _shots, _ws.scope_in.is_scoped, Input.is_action_pressed("Zoom"),
			InputManager.gameplay_suppressed(), _ws.attack.holstered, _ws.attack.gun_raised, _ws.ammo.current_ammo,
			_ws.scope_in.camera != null])

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
