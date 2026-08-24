extends Node
## Muzzle-smoke QA screenshot harness — boots the REAL game, fires the equipped weapon's muzzle-FX signal,
## and photographs the barrel over the life of the trail so the effect can be judged BY EYE.
##
## WHY: "the smoke doesn't look good" is a LOOK bug and no unit test in this suite can see it — --headless
## never compiles a particle shader at all, so every property can round-trip perfectly and still render as
## garbage. This is the only honest verification, and it is what should have been run before shipping v1.
##
## Run from the project root as a REAL WINDOWED RUN — not --headless, the GPU must render:
##   godot --path . res://scripts/tools/muzzle_smoke_qa_shots.tscn -- --shots-dir="C:/some/dir"
## Without --shots-dir it writes to user://muzzle_smoke_qa_shots. Prints one QA_SHOT per capture.
##
## Driver-copy pattern, copied from flashlight_qa_shots.gd: this scene is the boot scene, but the run switches
## current_scene to game.tscn (which frees the current scene), so _ready re-attaches a COPY of this script on
## a bare Node parented to root, which survives the change and drives the run.
##
## (*) NEVER call a Settings.set_* here — those setters call save_settings() and would rewrite the developer's
## real user://settings.cfg. Read the live values, never write them.

var _dir := "user://muzzle_smoke_qa_shots"
var _smoke: GPUParticles3D = null
var _attack: Node = null
var _eye: Camera3D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "MuzzleSmokeQaDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _frames(5)

	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(150)   # level loads, ps1 applier walks, nav bakes, sky title fades
	_strip_overlays()

	var player: Node3D = Groups.human_player(get_tree())
	if player == null:
		print("QA_FAIL no Player in the tree")
		get_tree().quit(1)
		return
	_smoke = player.find_child("MuzzleSmoke", true, false) as GPUParticles3D
	var cam := player.find_child("Camera3D", true, false) as Camera3D
	_eye = cam
	if _smoke == null or cam == null:
		print("QA_FAIL smoke=", _smoke, " cam=", cam)
		get_tree().quit(1)
		return
	if player.get("weapon_system") != null:
		_attack = player.weapon_system.attack
		_attack.set_holstered(false)
	# The gun begins HOLSTERED and the draw is a tween behind a lock that can refuse — so wait for it and then
	# SAY whether it is actually out. A shot of an empty corner is not evidence that the smoke is broken.
	await _frames(90)
	var gun := player.find_child("GunMesh", true, false) as Node3D
	# ⭐EQUIP A GUN FIRST. The player spawns holding FISTS, whose has_muzzle_flash is false — so the smoke gate
	# correctly refuses and every shot photographs an empty barrel. A QA pass that skips this step is measuring
	# the gate, not the effect.
	var inv = player.weapon_system.inventory if player.get("weapon_system") != null else null
	if inv != null:
		inv.equip(load("res://resources/weapons/pistol.tres"))
		await _wait(1.5)   # the swap dip + re-draw is a tween; shooting mid-swap fires from a stowed muzzle
		# inventory.equip() only fires weapon_changed — the VIEW MODEL is re-instantiated on Attack.swap_finished,
		# which a direct equip never emits, so the rig would still be showing the fists and the muzzle marker
		# would still be the fists'. Ask the gun rig to re-equip its model directly.
		var gm := player.find_child("GunMesh", true, false)
		if gm != null and gm.has_method("_equip_view_model"):
			gm.call("_equip_view_model")
			await _wait(0.6)
	var wd = inv.equipped_weapon if inv != null else null
	print("QA_WEAPON ", (wd.resource_path if wd != null else "NONE"),
			" has_muzzle_flash=", (wd.has_muzzle_flash if wd != null else "?"),
			" muzzle_smoke_scale=", (wd.get("muzzle_smoke_scale") if wd != null else "?"),
			" player_dial=", Settings.muzzle_smoke_scale)
	print("QA_FPS ", Engine.get_frames_per_second())
	print("QA_VIEWMODEL restored=", _restore_view_model(), " main_cull_mask=", cam.cull_mask)
	print("QA_DRAW holstered=", (_attack.holstered if _attack != null else "?"),
			" gun_visible=", (gun.visible if gun != null else "?"),
			" muzzle_on_screen=", cam.unproject_position(_smoke.global_position),
			" in_front=", not cam.is_position_behind(_smoke.global_position))

	# Broad daylight: white smoke against a bright world is the hard case, and the one most likely to read
	# as a flat blob. Shot 09 repeats the best pose at night for the other half of the range.
	WorldClock.set_time_of_day(0.35)
	await _frames(10)

	print("QA_SMOKE path=", player.get_path_to(_smoke), " amount=", _smoke.amount, " life=", _smoke.lifetime,
			" fixed_fps=", _smoke.fixed_fps, " draw_order=", _smoke.draw_order, " local=", _smoke.local_coords)
	print("QA_DIST muzzle_to_eye=", _smoke.global_position.distance_to(cam.global_position),
			" muzzle=", _smoke.global_position, " eye=", cam.global_position)
	var pm := _smoke.process_material as ParticleProcessMaterial
	print("QA_INHERIT inherit_velocity_ratio=", pm.inherit_velocity_ratio, " amount_ratio=", _smoke.amount_ratio)
	print("QA_SHAPE angle=", pm.angle_min, "..", pm.angle_max, " quad=", _smoke.draw_pass_1.size,
			" grav=", pm.gravity, " life=", _smoke.lifetime, " amount=", _smoke.amount)
	print("QA_PROC color=", pm.color, " scale=", pm.scale_min, "..", pm.scale_max, " v=", pm.initial_velocity_min, "..", pm.initial_velocity_max)

	await _shot("01_eye_idle")

	# --- A DIAGNOSTIC camera parked beside the barrel. The first-person framing puts the muzzle in the
	# bottom corner at ~40 cm, which is the shipped read but a terrible one to JUDGE the effect from; this
	# one looks straight at the smoke from 0.75 m so its shape, density and edges are actually legible.
	var side := Camera3D.new()
	get_tree().root.add_child(side)

	# --- The life of one burst, from the eye and from the side.
	# ⭐The first shot is the DELAY check: a few frames after the bang the barrel must still be CLEAN. Smoke in
	# this frame means the delay is not working and the effect will read as part of the muzzle flash again.
	# ⭐The ONSET is what gets judged here, so photograph it densely. Frame 1 must still be clean (the delay),
	# and the frames after it must show the smoke SWELLING rather than a cluster appearing all at once.
	_fire(3)
	await _wait(0.03)
	await _shot("02a_onset_t0_03")
	await _side(side, "02b_onset_zoom_t0_03")
	await _wait(0.05)
	await _side(side, "02c_onset_zoom_t0_08")
	await _wait(0.07)
	await _side(side, "02d_onset_zoom_t0_15")
	await _wait(0.15)
	await _shot("03_eye_t0_30")
	await _side(side, "04_side_t0_30")
	await _wait(0.30)
	await _shot("05_eye_t0_60")
	await _side(side, "06_side_t0_60")
	await _wait(0.50)
	await _side(side, "07_side_t1_10")
	await _wait(2.0)
	await _shot("08_eye_spent")

	# --- THE TRAIL. Sustained fire while sweeping the aim, which is the whole point of a world-space
	# emitter: the smoke made a moment ago must stay where it was made.
	var swept := 0.0
	while swept < 0.9:
		player.rotate_y(deg_to_rad(-70.0) * get_process_delta_time())
		_fire(1)
		swept += get_process_delta_time()
		await get_tree().process_frame
	await _wait(0.1)
	await _shot("09_eye_trail_turning")
	await _side(side, "10_side_trail_turning")

	# --- WALKING FORWARD while firing. World-space particles are left behind the moment the shooter moves, so
	# "shoot while advancing and you never see it" is the default behaviour, not a bug you can tune away with
	# opacity. inherit_velocity_ratio is what carries the puffs along with the muzzle; this is the shot that
	# says whether it is enough. Position is driven directly rather than through input — the harness is
	# photographing the FX, and a movement key would drag in stamina, bhop and the whole locomotion stack.
	await _wait(2.0)
	var walked := 0.0
	while walked < 0.85:
		var d := get_process_delta_time()
		player.global_position += -player.global_transform.basis.z * 3.2 * d
		if walked < 0.40:
			_fire(1)
		walked += d
		if walked > 0.45 and walked - d <= 0.45:
			await _shot("13_walking_forward_t0_45")
		await get_tree().process_frame
	await _shot("14_walking_forward_t0_85")

	# --- Night, so the white reads against a dark world instead of a bright one.
	WorldClock.set_time_of_day(0.95)
	await _frames(20)
	_fire(4)
	await _wait(0.35)
	await _side(side, "11_side_night")

	# --- THE SHIPPED FRAME: back through the real post-process chain (posterize + Bayer dither + grain),
	# which is what the player actually looks through and can eat a soft gradient alive.
	WorldClock.set_time_of_day(0.35)
	if _restore_post_process():
		print("QA_POST post-process layer restored")
	else:
		print("QA_POST_FAIL no post-process CanvasLayer found — shot 11 is still a raw grab")
	await _frames(20)
	_fire(3)
	await _wait(0.45)
	await _shot("12_shipped_frame_post_process")

	# --- CONTROL. Absurdly large and fully opaque. If THIS frame is empty the emitter is not drawing at all
	# and no amount of tuning will ever help; if it is a wall of white, the pipeline is fine and the shipped
	# numbers are simply too faint. Every "it looks wrong" pass needs this shot before it retunes anything.
	var cpm := _smoke.process_material as ParticleProcessMaterial
	cpm.color = Color(1, 1, 1, 1)
	cpm.scale_min = 0.35
	cpm.scale_max = 0.5
	_fire(1)
	await _wait(0.3)
	print("QA_CTRL aabb=", _smoke.get_aabb(), " vis_aabb=", _smoke.visibility_aabb, " visible=", _smoke.visible,
			" layers=", _smoke.layers, " amount_ratio=", _smoke.amount_ratio, " emitting=", _smoke.emitting)
	await _shot("12_control_huge_opaque_eye")
	await _side(side, "13_control_huge_opaque_zoom")

	print("QA_DONE")
	get_tree().quit(0)


## Fire the muzzle-FX signal `n` times, one per frame. Deliberately the SIGNAL and not the trigger: this
## harness is photographing the FX, and going through Attack.attack() would drag in ammo, cadence, the fire
## timer and the draw gate, any of which could silently swallow the shot and make an empty frame read as
## "the smoke is broken".
func _fire(n: int) -> void:
	if _attack == null:
		return
	for i in n:
		_attack.flash_muzzle.emit()


## Shoot the SAME moment from the diagnostic camera beside the barrel, then hand the viewport straight back
## to the player's eye. Re-aimed on every call because the muzzle moves — the emitter is a child of the gun.
## The PLAYER's camera — cached at the start, because the diagnostic camera steals `current` and
## get_viewport().get_camera_3d() would then return the wrong one.
func _eye_cam() -> Camera3D:
	return _eye


func _side(cam: Camera3D, name: String) -> void:
	if not is_instance_valid(_smoke):
		return
	var eye := _eye_cam()
	if eye == null:
		return
	var m := _smoke.global_position
	# A ZOOM LENS, not a repositioned camera: sit exactly where the player's eye is (which can never be inside
	# geometry) and narrow the FOV onto the muzzle. Parking it 0.75 m to the side photographed a wall.
	cam.global_position = eye.global_position
	cam.look_at(m, Vector3.UP)
	cam.fov = 20.0
	cam.near = 0.02
	var prev := get_viewport().get_camera_3d()
	cam.current = true
	await _frames(2)
	await _shot(name)
	if is_instance_valid(prev):
		prev.current = true
	await _frames(1)


## Wait REAL SECONDS, not frames. The whole point of these shots is to land inside a 0.55 s emission
## window, and a frame count only means what you think it does at a frame rate you have not measured —
## at 20 fps "await _frames(20)" is 1.0 s and lands past the end of the burst, photographing nothing.
func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		left -= get_process_delta_time()
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	var live := "?"
	if is_instance_valid(_smoke):
		live = "emitting=%s alpha=%.3f" % [_smoke.emitting, (_smoke.process_material as ParticleProcessMaterial).color.a]
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path, "  ", live)


## Hide everything painted OVER the 3D frame — the boot sky title, the HUD, the debug tickers — so the shots
## read the barrel and not the reticle sitting on it. The last pass turns the post-process layer back on.
func _strip_overlays() -> void:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
		elif n.name == "SkyTitle" and n is Node3D:
			(n as Node3D).visible = false
		stack.append_array(n.get_children())


## Turn the POST-PROCESS layer back on and nothing else — found by walking for the shader rather than by node
## name, so renaming the HUD cannot silently turn the check off. Copied from flashlight_qa_shots.gd.
## Put the WEAPON back in frame. The main camera's cull_mask has the view-model layer (bit 3) REMOVED, so
## the gun is not drawn by the world pass at all — it is rendered in its own SubViewport and composited by a
## `ViewModelComposite` container living on the HUD CanvasLayer, which _strip_overlays() has just hidden.
## Without this the shots show smoke floating in mid-air beside an invisible gun, which is not the frame the
## player sees. Shows that layer again and hides only its OTHER children, so the reticle and panel stay off.
func _restore_view_model() -> bool:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == "ViewModelComposite":
			var layer: Node = n
			while layer != null and not (layer is CanvasLayer):
				layer = layer.get_parent()
			if layer == null:
				return false
			(layer as CanvasLayer).visible = true
			for c in (layer as CanvasLayer).get_children():
				if c != n and c is CanvasItem:
					(c as CanvasItem).visible = false
			return true
		stack.append_array(n.get_children())
	return false


func _restore_post_process() -> bool:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem:
			var mat := (n as CanvasItem).material as ShaderMaterial
			if mat != null and mat.shader != null and String(mat.shader.resource_path).contains("post_process"):
				var layer: Node = n
				while layer != null and not (layer is CanvasLayer):
					layer = layer.get_parent()
				if layer != null:
					(layer as CanvasLayer).visible = true
					return true
		stack.append_array(n.get_children())
	return false
