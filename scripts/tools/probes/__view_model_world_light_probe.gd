extends SceneTree
## View-model WORLD-LIGHT probe (2026-09-14): does the first-person gun respond to the world's lighting at all?
## Measures the gun pass's own render target (alpha = weapon coverage, ViewModelCamera.coverage_texture) under:
##   00 shipped            fill 0.75 + whatever the world's lights add
##   01 sun_off            the sun hidden -> how much of the gun's brightness the sun was
##   02 slab_over_player   sun back on, a 30 m slab 4 m overhead on WORLD layer 1 -> does world geometry shadow the gun?
##   03 fill_off           fill 0 -> the gun lit by the world alone (the "black gun" the fill was built against)
##   04 fill_off_sun_off   fill 0 + sun off -> the floor
## Also measures the WORLD (composite, gun pixels masked out) in 00 vs 02 so the slab is proven to shadow the world.
## Run WINDOWED (not --headless — the GPU must light and shadow):
##   godot --path . -s scripts/tools/probes/__view_model_world_light_probe.gd -- --shots-dir=<dir>

const GAME := "res://scenes/game.tscn"
const WEAPON := "res://resources/weapons/pistol.tres"
const TIME_OF_DAY := 0.5
const DIAG_FOV_OFFSET := 45.0

var _dir := "user://view_model_world_light_probe"
var _started := false
var _done := false
var _rows: Array[Dictionary] = []


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--shots-dir="):
			_dir = String(a).trim_prefix("--shots-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _frames(5)
	change_scene_to_file(GAME)
	await _frames(180)
	_hide_boot_and_debug_overlays()

	var vm: Node = root.find_child("ViewModelCamera", true, false)
	if vm == null:
		print("QA_FAIL no ViewModelCamera")
		_finish(1)
		return
	var player: Node3D = _host_of(vm)
	var cam := vm.get_parent() as Camera3D
	if player == null or cam == null:
		print("QA_FAIL player=", player, " cam=", cam)
		_finish(1)
		return
	var clock: Node = root.get_node_or_null("/root/WorldClock")
	if clock != null:
		clock.set(&"day_length_seconds", 0.0)
		clock.call(&"set_time_of_day", TIME_OF_DAY)

	var inv: Object = null
	var attack: Object = null
	if player.get("weapon_system") != null:
		attack = player.weapon_system.attack
		inv = player.weapon_system.inventory
	if attack != null:
		attack.set_holstered(false)
	await _frames(90)
	if inv != null:
		inv.equip(load(WEAPON))
		await _frames(90)
		var gm: Node = player.find_child("GunMesh", true, false)
		if gm != null and gm.has_method("_equip_view_model"):
			gm.call("_equip_view_model")
			await _frames(40)
	var spawn := get_first_node_in_group(Groups.PLAYER_SPAWN) as Node3D
	if spawn != null:
		player.global_position = spawn.global_position + Vector3(0.0, 0.2, 0.0)
		await _frames(10)
	_face_the_open_view(player, cam)
	vm.set(&"fov_offset", DIAG_FOV_OFFSET)
	await _frames(150)

	var sun := _find_sun()
	var gun_cam := vm.get(&"_gun_camera") as Camera3D
	print("QA_SUN ", (sun.name if sun else "NONE"), " energy=", (sun.light_energy if sun else -1.0),
			" dir=", (-sun.global_transform.basis.z if sun else Vector3.ZERO), " shadow=", (sun.shadow_enabled if sun else false))
	print("QA_GUN_ENV ambient_energy=", gun_cam.environment.ambient_light_energy, " fill_knob=", vm.get(&"view_model_ambient_energy"),
			" gun_cull=", gun_cam.cull_mask, " main_cull=", cam.cull_mask)
	var dns: Node = get_first_node_in_group(Groups.DAY_NIGHT)
	if dns != null and dns.has_method(&"current_day_factor"):
		print("QA_DAY factor=", dns.current_day_factor())
	for l in _all_lights():
		if l is DirectionalLight3D:
			continue
		var d := (l as Node3D).global_position.distance_to(cam.global_position)
		if d < 15.0:
			print("QA_NEAR_LIGHT ", l.name, " d=", snappedf(d, 0.1), " energy=", l.light_energy, " visible=", l.visible)

	await _capture("00_shipped", vm)
	if sun != null:
		sun.visible = false
	await _capture("01_sun_off", vm)
	if sun != null:
		sun.visible = true
	var slab := _spawn_slab(cam)
	await _frames(20)
	await _capture("02_slab_over_player", vm)
	if is_instance_valid(slab):
		slab.queue_free()
	vm.set(&"view_model_ambient_energy", 0.0)
	await _capture("03_fill_off", vm)
	if sun != null:
		sun.visible = false
	await _capture("04_fill_off_sun_off", vm)
	if sun != null:
		sun.visible = true

	# --- THE HYPOTHESIS: Godot culls LIGHTS per camera by the light's own VisualInstance3D `layers` (not its
	# light_cull_mask). Every world light ships on layer 1; the gun camera's cull_mask is layer 3 only -> no world
	# light exists in the gun pass. Prove it by ORing layer 3 onto every light and re-measuring with the fill OFF.
	var touched: Array[Light3D] = []
	for l in _all_lights():
		if (l.layers & 4) == 0:
			l.layers |= 4
			touched.append(l)
	print("QA_LAYERED ", touched.size(), " lights given layer 3")
	await _capture("05_lights_on_layer3_fill_off", vm)
	var slab2 := _spawn_slab(cam)
	await _frames(20)
	await _capture("06_lights_on_layer3_fill_off_slab", vm)
	if is_instance_valid(slab2):
		slab2.queue_free()
	# The sun's own share: DayNightSky rewrites sun.visible EVERY frame (day_night_sky.gd:218), which is why row 01
	# above cannot have taken — pause the driver first, then hide the sun.
	if dns != null:
		dns.set_process(false)
		dns.set_physics_process(false)
	if sun != null:
		sun.visible = false
	await _capture("07_lights_on_layer3_fill_off_sun_off", vm)
	if sun != null:
		sun.visible = true
	if dns != null:
		dns.set_process(true)
		dns.set_physics_process(true)
	vm.set(&"view_model_ambient_energy", 0.75)
	await _capture("08_lights_on_layer3_fill_075", vm)
	vm.set(&"view_model_ambient_energy", 0.2)
	await _capture("09_lights_on_layer3_fill_020", vm)
	for l in touched:
		if is_instance_valid(l):
			l.layers &= ~4
	vm.set(&"view_model_ambient_energy", 0.75)
	_report()
	_finish(0)


## A 30x2x30 m slab 4 m above the eye on WORLD layer 1 (NOT the view-model layer), two-sided, casting shadows.
## The gun camera cannot see it (its cull mask is layer 3 only) — the question is whether it can be SHADOWED by it.
func _spawn_slab(cam: Camera3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(30.0, 2.0, 30.0)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.5, 0.5, 0.5)
	mi.material_override = mat
	mi.layers = 1
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Parented under the LIVE SCENE (never root's last child — that was a transient that got freed under the slab
	# on the first run, and the dangling queue_free aborted the whole probe coroutine).
	current_scene.add_child(mi)
	mi.global_position = cam.global_position + Vector3(0.0, 4.0, 0.0)
	return mi


func _capture(name: String, vm: Node) -> void:
	await _frames(8)
	await RenderingServer.frame_post_draw
	var composite := root.get_viewport().get_texture().get_image()
	_save(composite, name + "_composite")
	var stats := {}
	var world := {}
	var tex: Texture2D = vm.call(&"coverage_texture")
	if tex != null:
		var gun := tex.get_image()
		_save(gun, name + "_gun_pass")
		stats = _gun_stats(gun)
		world = _world_stats(composite, gun)
	print("QA_SHOT ", name, " gun=", stats, " world=", world)
	_rows.append({"name": name, "stats": stats, "world": world})


func _gun_stats(img: Image) -> Dictionary:
	var lums := PackedFloat32Array()
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				lums.append(0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
	return _stats_of(lums)


## The composite's LOWER HALF with the gun's pixels masked out — the street the gun is held over.
func _world_stats(composite: Image, gun: Image) -> Dictionary:
	var lums := PackedFloat32Array()
	var sx := float(gun.get_width()) / float(composite.get_width())
	var sy := float(gun.get_height()) / float(composite.get_height())
	for y in range(composite.get_height() / 2, composite.get_height()):
		for x in range(0, composite.get_width(), 2):
			var gx := mini(int(x * sx), gun.get_width() - 1)
			var gy := mini(int(y * sy), gun.get_height() - 1)
			if gun.get_pixel(gx, gy).a > 0.5:
				continue
			var c := composite.get_pixel(x, y)
			lums.append(0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
	return _stats_of(lums)


func _stats_of(lums: PackedFloat32Array) -> Dictionary:
	if lums.is_empty():
		return {"n": 0}
	lums.sort()
	var total := 0.0
	for v in lums:
		total += v
	var n := lums.size()
	return {"n": n, "mean": snappedf(total / float(n), 0.0001), "p10": snappedf(lums[int(n * 0.10)], 0.0001),
			"p50": snappedf(lums[int(n * 0.50)], 0.0001), "p90": snappedf(lums[int(n * 0.90)], 0.0001)}


func _report() -> void:
	print("QA_TABLE name | gun_px | gun_mean | gun_p10 | gun_p50 | gun_p90 || world_mean | world_p10 | world_p50")
	for r in _rows:
		var s: Dictionary = r["stats"]
		var w: Dictionary = r["world"]
		if int(s.get("n", 0)) == 0:
			print("QA_ROW ", r["name"], " | NO GUN PIXELS")
			continue
		print("QA_ROW ", r["name"], " | ", s["n"], " | ", s["mean"], " | ", s["p10"], " | ", s["p50"], " | ", s["p90"],
				" || ", w.get("mean", "?"), " | ", w.get("p10", "?"), " | ", w.get("p50", "?"))


func _find_sun() -> DirectionalLight3D:
	for l in _all_lights():
		if l is DirectionalLight3D:
			return l as DirectionalLight3D
	return null


func _all_lights() -> Array[Light3D]:
	var out: Array[Light3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Light3D:
			out.append(n as Light3D)
		stack.append_array(n.get_children())
	return out


func _save(img: Image, name: String) -> void:
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		print("QA_SHOT_FAIL ", path, " err=", err)


func _host_of(vm: Node) -> Node3D:
	var n: Node = vm
	while n != null:
		if n is Node3D and n.get("weapon_system") != null:
			return n as Node3D
		n = n.get_parent()
	return null


func _hide_boot_and_debug_overlays() -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasLayer and (String(n.name).begins_with("Debug") or String(n.name) == "AiEventLog"):
			(n as CanvasLayer).visible = false
		elif String(n.name) == "SkyTitle" and n is Node3D:
			n.queue_free()
			continue
		stack.append_array(n.get_children())


func _face_the_open_view(player: Node3D, cam: Camera3D) -> void:
	var space := player.get_world_3d().direct_space_state
	var eye := cam.global_position
	var best_dir := -player.global_transform.basis.z
	var best_d := -1.0
	for i in 24:
		var yaw := TAU * float(i) / 24.0
		var dir := Vector3(sin(yaw), 0.0, cos(yaw))
		var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * 60.0)
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		var d: float = (eye.distance_to(hit["position"] as Vector3) if not hit.is_empty() else 60.0)
		if d > best_d:
			best_d = d
			best_dir = dir
	player.look_at(player.global_position + best_dir, Vector3.UP)
	print("QA_POSE at ", player.global_position, " facing ", best_dir, " clear=", best_d, " m")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _finish(code: int) -> void:
	print("QA_DONE dir=", ProjectSettings.globalize_path(_dir))
	_done = true
	quit(code)
