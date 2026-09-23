extends Node
## RAIN — LOOK probe (2026-09-22). Two questions, one stage: does the rain still read as rain when you look UP,
## and does it stop when something is over your head?
##
## Run WINDOWED (shaders never compile headless), from PowerShell:
##   & "C:\Users\dalla\bin\godot.cmd" --path "C:\Users\dalla\3D RPG\rpg" res://scripts/tools/probes/__rain_look_probe.tscn
## Frames land in user://rain_look.
##
## ⭐ THE ZENITH FRAME IS THE WHOLE POINT. A camera-facing billboard draws every drop as a vertical line in SCREEN
## space, so looking straight up used to give a wall of parallel verticals — which is what the bug report was.
## Velocity-aligned streaks instead FORESHORTEN as the view swings onto the line of fall. That is a NUMBER here,
## not taste: `QA_STREAK` walks the lit pixels into blobs and prints how long they are on screen. ⭐ LENGTH, NOT
## ANGLE — the first pass of this probe measured streak angles and could not tell the two looks apart at all,
## because rain leaning 12 degrees photographs as tilted lines either way. Frames 08 and 09 are the decisive
## pair: rain falling dead straight down, camera pointed dead straight up it.
##
## The shelter half stands the camera under a roof slab 18 m up — ABOVE the 6 m ceiling scan that
## `IndoorAmbienceDucker` uses for `Player.is_indoors`, which is exactly the geometry rain used to fall straight
## through. ⭐ Frame 06 is the one that matters there: under the roof, LOOKING OUT past the eave. Dry in front of
## you and raining beyond it, in the same frame. The all-or-nothing cutoff that preceded per-drop occlusion made
## that whole frame dry, which is what "we can't see the world rain" meant. `QA_SHELTER` prints the shelter
## verdict, whether the emitter is still running (with occlusion on it should never stop) and the height the
## heightfield says rain stops at over the camera, so none of that is a squint at a PNG.

var _dir := "user://rain_look"
var _cam: Camera3D = null
var _rain: Node = null
var _imgs: Array[Image] = []
var _tags: Array[String] = []

## Where the roof slab stands, and how high its underside is. 18 m clears the player's own indoors scan three
## times over — under this, the code that trusted `Player.is_indoors` rained on your head.
const ROOF_AT := Vector3(60.0, 0.0, 0.0)
const ROOF_Y := 18.0

## And a low awning somewhere else on the stage. ⭐ The 18 m slab is the right geometry for the shelter-probe
## regression and the wrong geometry for a PHOTOGRAPH of an eave: at eye level it is off the top of the frame,
## so a frame under it looks like open sky that happens not to be raining. An awning you can see the underside
## of is what makes "dry here, raining four metres that way" legible in one image.
const AWNING_AT := Vector3(-60.0, 0.0, 0.0)
const AWNING_Y := 4.0
const AWNING_SPAN := 24.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "RainLookDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var stage := Node3D.new()
	stage.name = "RainStage"
	get_tree().root.add_child(stage)

	# The project's own sky, so the streaks are judged against the backdrop they will actually smear.
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	we.environment = env
	we.add_to_group(Groups.WORLD_ENVIRONMENT)
	stage.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.35
	sun.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	stage.add_child(sun)

	_ground(stage)
	_cover(stage, ROOF_AT, ROOF_Y, 40.0)
	_cover(stage, AWNING_AT, AWNING_Y, AWNING_SPAN)

	_rain = load("res://scripts/components/rain_fall.gd").new()
	_rain.name = "RainFall"
	_rain.set(&"use_default_sound", false)   # a probe has nothing to say about the bed, and it would loop for a minute
	stage.add_child(_rain)

	_cam = Camera3D.new()
	_cam.fov = 75.0
	stage.add_child(_cam)
	_cam.make_current()

	await _frames(20)   # let StarSky paint and the particle shader compile before the first grab

	# --- THE ORIENTATION HALF: one spot, four pitches, out under open sky. ------------------------------------
	await _shot("00_open_level", Vector3.ZERO, 0.0)
	await _shot("01_open_up45", Vector3.ZERO, 45.0)
	await _shot("02_open_zenith", Vector3.ZERO, 88.0)
	await _shot("03_open_down45", Vector3.ZERO, -45.0)

	# --- THE SHELTER HALF: under a roof the player would not call indoors. ------------------------------------
	await _shot("04_roof_up45", ROOF_AT, 45.0, 0.0, 2.6)
	await _shot("05_roof_zenith", ROOF_AT, 88.0, 0.0, 2.6)
	# ⭐ THE FRAME PER-DROP OCCLUSION EXISTS FOR. Under the awning, a third of the way in, looking OUT along -X
	# and tipped up enough to catch its underside: everything nearer than the eave must be dry and everything
	# past it must be raining, in ONE image. The all-or-nothing cutoff this replaced made the whole frame dry,
	# weather and all — a dry city seen from a doorway.
	# Standing OUT in the rain looking AT the shelter is the clearest of the three: rain in front of you, rain
	# behind it, and a dry void under it. The first pass shot this from underneath at a 22-degree tip and got a
	# frame of ceiling, which says nothing — an eave photographs best from the wet side.
	await _shot("06_awning_from_outside", AWNING_AT + Vector3(20.0, 0.0, 0.0), 0.0, 90.0, 2.6)
	# Then from underneath, looking out along it: dry ground near, the curtain past the eave.
	await _shot("06b_awning_looking_out", AWNING_AT + Vector3(8.0, 0.0, 0.0), 0.0, 90.0, 2.6)
	# And straight up under it, where there must be nothing but awning.
	await _shot("06c_awning_zenith", AWNING_AT, 88.0, 0.0, 2.6)
	# And back out, because a cutoff that never releases is the same bug wearing a different hat.
	await _shot("07_back_out_up45", Vector3.ZERO, 45.0, 0.0, 2.6)

	# --- THE MECHANISM, PROVED. ------------------------------------------------------------------------------
	# ⭐ THE FRAME THAT CANNOT BE ARGUED WITH. Rebuild the rain falling DEAD straight down, then look dead
	# straight up it: every drop is now travelling exactly along the view axis, so a velocity-aligned quad is
	# edge-on and the sky should go nearly EMPTY. A screen-locked billboard cannot do that — it draws the same
	# wall of full-length verticals whatever the pitch, which is frame 09. 07 against 09 is the fix.
	_rain.set(&"lean_degrees", 0.0)
	_rain._ready()
	await _shot("08_proof_nolean_zenith", Vector3.ZERO, 90.0, 0.0, 2.6)

	# --- THE CONTROL: the same views with the pre-fix look put back. ------------------------------------------
	# One zenith frame proves nothing on its own; the two looks only separate side by side. So the probe puts the
	# emitter back the way it was BEFORE (material billboard on, node alignment off, lean as a sprite roll) and
	# shoots the same cameras again.
	_restore_old_look()
	await _shot("09_control_nolean_zenith", Vector3.ZERO, 90.0, 0.0, 2.6)
	_rain.set(&"lean_degrees", 12.0)
	_rain._ready()
	_restore_old_look()
	await _shot("10_control_zenith", Vector3.ZERO, 88.0, 0.0, 2.6)
	await _shot("11_control_up45", Vector3.ZERO, 45.0, 0.0, 2.6)

	for i in _imgs.size():
		_imgs[i].save_png(ProjectSettings.globalize_path(_dir.path_join("%s.png" % _tags[i])))
	print("QA_DONE ", ProjectSettings.globalize_path(_dir), " frames=", _imgs.size())
	get_tree().quit(0)

## Put the pre-fix look back on the LIVE emitter: a plain billboarded StandardMaterial3D on the drop quad, no
## velocity alignment on the node, and the lean back to a roll of the sprite. It REBUILDS the material rather
## than flipping a flag on it, because the fixed drop is drawn by rain_drop.gdshader and a ShaderMaterial has no
## billboard flag to turn on. Nothing is saved — this is the control frame's configuration, not a change to the
## component.
func _restore_old_look() -> void:
	_rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	var quad := _rain.draw_pass_1 as QuadMesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	quad.material = mat
	var pm := _rain.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.angle_min = _rain.get(&"lean_degrees")
	pm.angle_max = _rain.get(&"lean_degrees")
	print("QA_CONTROL pre-fix look restored (material billboard ON, transform_align OFF)")

## A dark floor, so the frame has a horizon and the streaks have something other than sky behind them.
func _ground(stage: Node3D) -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.10, 0.11)
	floor_mesh.material_override = mat
	floor_mesh.position = Vector3(0.0, -0.5, 0.0)
	stage.add_child(floor_mesh)

## A slab with a REAL collider, because BOTH probes are raycasts and a visual-only brush is invisible to them
## (the component's own @risk note). `under_at` is where its underside sits.
func _cover(stage: Node3D, at: Vector3, under_at: float, span: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(span, 1.0, span)
	shape.shape = box
	body.add_child(shape)
	var vis := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	vis.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.15, 0.14)
	vis.material_override = mat
	body.add_child(vis)
	body.position = at + Vector3(0.0, under_at + 0.5, 0.0)
	stage.add_child(body)

func _shot(tag: String, at: Vector3, pitch: float, yaw: float = 0.0, settle: float = 1.2) -> void:
	_cam.position = at + Vector3(0.0, 1.6, 0.0)
	_cam.rotation_degrees = Vector3(pitch, yaw, 0.0)
	# ⭐ A FULL SECOND AT LEAST. The field RIDES the camera, so after a teleport the emitter has moved but the air
	# it filled is back where the camera used to be; a drop needs spawn_height / fall_speed to fall into frame.
	# The shelter frames wait longer still, because stopping the emitter leaves a whole lifetime of drops in the
	# air on purpose (a doorway tails off, it does not switch off).
	await _wait(settle)
	await _frames(2)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_imgs.append(img)
	_tags.append(tag)
	_measure(tag, img)

## The numbers that settle this, per frame:
##  - QA_SHELTER: the component's own verdict plus the share of lit pixels, so "the rain stopped under the roof"
##    is countable rather than a squint at a PNG.
##  - QA_STREAK: how LONG the streaks are on screen, as the mean major axis of each lit blob. ⭐ Length is the
##    measurement that separates the two looks, and angle is not: a screen-locked billboard draws every drop at
##    its full length whatever the pitch, while a velocity-aligned one foreshortens as the view swings onto the
##    line of fall — to nothing at all when you look straight up rain that falls straight down.
func _measure(tag: String, img: Image) -> void:
	var lit := _lit_mask(img)
	var count := 0
	for b: int in lit:
		count += b
	# `roof` is what the sky heightfield says rain stops at over the camera: a big negative number means open
	# sky. With occlusion on, `emitting` should stay true even while `sheltered` is — that is the fix.
	var roof: float = _rain.sky_height_at(_cam.global_position)
	print("QA_SHELTER %-24s sheltered=%s emitting=%s roof_over_cam=%s lit=%.3f%% pitch=%.0f" % [
		tag, str(_rain.get(&"_sheltered")), str(_rain.emitting),
		"open" if roof < -1000.0 else "%.1f m" % roof,
		100.0 * float(count) / float(maxi(lit.size(), 1)), _cam.rotation_degrees.x])
	_report_streaks(tag, lit)

## Grid size of the sampled mask (the frame at half resolution in each axis), kept as members so the blob walk
## can index the mask without re-deriving them.
var _grid_w := 0
var _grid_h := 0

## Pixels meaningfully brighter than the frame's own median — the rain, additive over whatever is behind it.
## Sampled on a 2 px grid: this runs on the main thread between shots and a full 1280x720 scan is not free.
func _lit_mask(img: Image) -> PackedByteArray:
	_grid_w = img.get_width() / 2
	_grid_h = img.get_height() / 2
	var lum := PackedFloat32Array()
	lum.resize(_grid_w * _grid_h)
	var i := 0
	for gy in _grid_h:
		for gx in _grid_w:
			lum[i] = img.get_pixel(gx * 2, gy * 2).get_luminance()
			i += 1
	var sorted := lum.duplicate()
	sorted.sort()
	var cut: float = sorted[sorted.size() / 2] + 0.06
	var mask := PackedByteArray()
	mask.resize(lum.size())
	for j in lum.size():
		mask[j] = 1 if lum[j] > cut else 0
	return mask

## Walk the mask into blobs (one streak, mostly) and report how long they are. The major axis comes from each
## blob's own covariance, which is stable for a thin line and needs no threshold of its own.
func _report_streaks(tag: String, mask: PackedByteArray) -> void:
	var seen := PackedByteArray()
	seen.resize(mask.size())
	var stack := PackedInt32Array()
	var lengths := PackedFloat32Array()
	for seed in mask.size():
		if mask[seed] == 0 or seen[seed] == 1:
			continue
		stack.clear()
		stack.append(seed)
		seen[seed] = 1
		var xs := PackedFloat32Array()
		var ys := PackedFloat32Array()
		while not stack.is_empty():
			var idx: int = stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var cx: int = idx % _grid_w
			var cy: int = idx / _grid_w
			xs.append(float(cx))
			ys.append(float(cy))
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + d.x
				var ny: int = cy + d.y
				if nx < 0 or ny < 0 or nx >= _grid_w or ny >= _grid_h:
					continue
				var n: int = ny * _grid_w + nx
				if mask[n] == 1 and seen[n] == 0:
					seen[n] = 1
					stack.append(n)
		if xs.size() >= 4:
			lengths.append(_major_axis(xs, ys))
	if lengths.is_empty():
		print("QA_STREAK %-24s blobs=   0  (nothing lit — an empty sky)" % tag)
		return
	var total := 0.0
	var longest := 0.0
	for l: float in lengths:
		total += l
		longest = maxf(longest, l)
	print("QA_STREAK %-24s blobs=%4d mean_major=%5.1f px longest=%5.1f px (grid is %d px tall)" % [
		tag, lengths.size(), total / float(lengths.size()), longest, _grid_h])

## Length of a blob along its own principal axis: 4 sigma of the projection onto the dominant eigenvector, in
## closed form for the 2x2 case.
func _major_axis(xs: PackedFloat32Array, ys: PackedFloat32Array) -> float:
	var n := float(xs.size())
	var mx := 0.0
	var my := 0.0
	for i in xs.size():
		mx += xs[i]
		my += ys[i]
	mx /= n
	my /= n
	var xx := 0.0
	var yy := 0.0
	var xy := 0.0
	for i in xs.size():
		var dx: float = xs[i] - mx
		var dy: float = ys[i] - my
		xx += dx * dx
		yy += dy * dy
		xy += dx * dy
	xx /= n
	yy /= n
	xy /= n
	var half := (xx + yy) * 0.5
	var root := sqrt(maxf((xx - yy) * (xx - yy) * 0.25 + xy * xy, 0.0))
	return 4.0 * sqrt(maxf(half + root, 0.0))

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
