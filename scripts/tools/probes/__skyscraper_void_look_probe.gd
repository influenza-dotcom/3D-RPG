extends Node
## SKYSCRAPER VOID — LOOK probe (2026-09-17). The drop, and nothing else: a bare 60 m roof slab, this project's
## real sky (a WorldEnvironment in the `world_environment` group, which StarSky repaints exactly as it does in a
## level) and one SkyscraperVoid. No HUD, no sky title, no level — so what lands in the PNG is the facade's own
## palette and the haze, which is the only way to tune either.
##
## Run WINDOWED (shaders never compile headless), from PowerShell:
##   & "C:\Users\dalla\bin\godot.cmd" --path "C:\Users\dalla\3D RPG\rpg" res://scripts/tools/probes/__skyscraper_void_look_probe.tscn
## Frames land in user://skyscraper_void_look.
##
## The six views are the whole judgement:
##   00 parapet     — standing at the edge, looking slightly down: is there a BUILDING under the floor?
##   01 down45      — the money shot: storeys receding into haze.
##   02 straight    — over the toes. Must find fog, never sky and never a bottom edge.
##   03 skyline     — level gaze: neighbours' roofs must all sit BELOW the horizon line of the eye.
##   04 fall_60     — 60 m down the side, outside the footprint: the view during a fall off the edge.
##   05 fall_400    — 400 m down: everything above and below must already be haze (proves "bottomless").
##   06/07          — the same parapet views with the SKY re-graded cold, because the drop's palette and this
##                    project's amber horizon glow cannot both be right in one frame.
##   08/09/10       — along the wall from a corner (the reference's own framing), and one looking UP at the
##                    overcast deck, which no other view in this probe can see.
## The two fall views sit 12 m OUT from the wall, not 4: pressed against the facade, perspective skews the grid
## into diagonals and nothing about the palette can be judged.
## `QA_PIX` prints, per frame, the mean luminance of the lower half of the image plus the share of pixels that
## are within 2% of the pure haze colour: "too dark to read" and "already total haze" are numbers here, not taste.

const VOID := preload("res://scripts/components/skyscraper_void.gd")

var _dir := "user://skyscraper_void_look"
var _cam: Camera3D = null
var _void: Node3D = null
var _imgs: Array[Image] = []
var _tags: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "LookDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var stage := Node3D.new()
	stage.name = "LookStage"
	get_tree().root.add_child(stage)

	# The project's own sky: StarSky paints any WorldEnvironment entering the tree in this group, so the backdrop
	# here is the same horizon sky + night ambient a level gets — the drop has to sit against THAT, not a grey void.
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	we.environment = env
	we.add_to_group(Groups.WORLD_ENVIRONMENT)
	stage.add_child(we)

	# The roof: a 60 m slab whose TOP is y = 0, so the parapet edge is at z = +30.
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(60.0, 2.0, 60.0)
	slab.mesh = box
	var slab_mat := StandardMaterial3D.new()
	slab_mat.albedo_color = Color(0.12, 0.12, 0.13)
	slab.material_override = slab_mat
	slab.position = Vector3(0.0, -1.0, 0.0)
	stage.add_child(slab)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.35
	sun.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	stage.add_child(sun)

	_void = VOID.new()
	_void.name = "SkyscraperVoid"
	_void.set(&"fit_to_level", false)
	_void.set(&"footprint_size", Vector2(60.0, 60.0))
	_void.set(&"auto_haze_from_fog", false)
	stage.add_child(_void)

	# Weather is its own drop-in (scripts/components/rain_fall.gd), not part of the drop — it rides the camera,
	# so it needs no particular parent. Loaded by PATH for the same reason the void is: a brand-new class_name is
	# not in the editor's class cache yet, and naming the type would fail this probe to parse.
	var rain: Node = load("res://scripts/components/rain_fall.gd").new()
	rain.name = "RainFall"
	rain.set(&"stop_when_sheltered", false)   # the bare stage has no roof colliders to probe against
	stage.add_child(rain)

	_cam = Camera3D.new()
	_cam.fov = 90.0
	stage.add_child(_cam)
	_cam.make_current()

	await _frames(20)   # let StarSky paint + the shader compile before the first grab

	# ⭐ A Godot camera looks along its own -Z, so the viewpoints sit on the -Z parapet with yaw 0 and face OUT
	# over the drop. Placed on the +Z edge with the same yaw (the first pass) every shot looks back across the
	# roof instead, and the "the drop is invisible" reading that produced was the roof slab filling the frame.
	# ⭐ THE TWO "LOOK DOWN" VIEWS SIT JUST PAST THE EDGE (z = -30.4 against a wall at -30), i.e. LEANING OVER.
	# From inside the parapet the wall directly below you is only visible past about -70 degrees of pitch — a
	# camera a metre back photographs its own roof and says nothing about the drop (the first pass shot four
	# frames of roof slab and read them as "the facade is invisible").
	await _shot("00_parapet", Vector3(0.0, 1.6, -28.0), -15.0)
	await _shot("01_down45", Vector3(0.0, 1.6, -30.4), -50.0)
	await _shot("02_straight", Vector3(0.0, 1.6, -30.4), -80.0)
	await _shot("03_skyline", Vector3(0.0, 1.6, -28.0), 0.0)
	# ⭐ THE REFERENCE'S OWN FRAMING: leaning out at a CORNER, looking diagonally ALONG the wall rather than
	# straight off it. Perpendicular to a wall you are standing on top of, the facade is a thin grazing sliver at
	# the bottom of the frame; along it, it fills half the view and takes the perspective all the way down. This
	# is the frame to judge the drop by.
	await _shot("08_corner_along_wall", Vector3(-29.0, 1.6, -30.6), -40.0, 35.0)
	# The fall views look BACK at the wall (yaw 180): the point of them is the facade streaming past, and a
	# camera facing away from the building during a fall shows only fog.
	await _shot("04_fall_60", Vector3(0.0, -60.0, -42.0), -25.0, 180.0)
	await _shot("05_fall_400", Vector3(0.0, -400.0, -42.0), -25.0, 180.0)

	# --- THE SKY QUESTION -------------------------------------------------------------------------------
	# The drop is deep blue-teal (the Peripeteia reference); this project's sky hangs an AMBER light-pollution
	# glow on the horizon (horizon_sky.gdshader). Those two do not belong in the same frame, and the choice
	# between them is the level designer's, not this component's — so the last two frames re-grade the sky cool
	# and shoot the same two views, to show what the drop looks like against a sky that matches it.
	_cool_sky()
	await _shot("06_coolsky_parapet", Vector3(0.0, 1.6, -28.0), -15.0)
	await _shot("07_coolsky_down45", Vector3(0.0, 1.6, -30.4), -50.0)
	await _shot("09_coolsky_corner", Vector3(-29.0, 1.6, -30.6), -40.0, 35.0)
	# The overcast deck is only judgeable by LOOKING UP at it — every other view in this probe points at or below
	# the horizon, which is exactly where a cloud lid is invisible.
	await _shot("10_coolsky_overcast", Vector3(0.0, 1.6, -20.0), 38.0)
	# ⭐ THE SAME VIEW AGAIN, SECONDS LATER. A still cannot show drift, and "the uniform is set" is not the same
	# claim as "the pixels moved" — so the probe shoots the overcast twice from one camera and prints how much of
	# the sky actually changed between them.
	await _wait(4.0)
	await _shot("11_coolsky_overcast_later", Vector3(0.0, 1.6, -20.0), 38.0)
	_report_drift()

	for i in _imgs.size():
		_imgs[i].save_png(ProjectSettings.globalize_path(_dir.path_join("%s.png" % _tags[i])))
	print("QA_DONE ", ProjectSettings.globalize_path(_dir), " frames=", _imgs.size())
	get_tree().quit(0)

## Re-grade the live sky to the reference's cold palette. Writes the horizon_sky uniforms StarSky already
## painted, so nothing is saved and the level's own authored sky is untouched — this is a PREVIEW of a decision,
## not a change to the game.
func _cool_sky() -> void:
	for n in get_tree().get_nodes_in_group(Groups.WORLD_ENVIRONMENT):
		var we := n as WorldEnvironment
		if we == null or we.environment == null or we.environment.sky == null:
			continue
		var mat := we.environment.sky.sky_material as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter("zenith_color", Color(0.04, 0.09, 0.13))
		mat.set_shader_parameter("horizon_color", Color(0.10, 0.24, 0.29))
		# ⭐ THE GROUND BAND IS THE VOID UNDER THE PARAPET, AND IT MUST EQUAL THE COMPONENT'S `haze_deep_color`.
		# That equality is what makes the drop bottomless: a surface fogged all the way to the deep colour is then
		# the same colour as the empty air beside it, so its silhouette — and its foot — stop existing.
		mat.set_shader_parameter("ground_color", _void.get(&"haze_deep_color"))
		mat.set_shader_parameter("haze_color", Color(0.20, 0.42, 0.45))
		mat.set_shader_parameter("haze_strength", 0.35)
		mat.set_shader_parameter("sun_glow", 0.2)
		print("QA_SKY re-graded cool on ", we.name)

func _shot(tag: String, at: Vector3, pitch: float, yaw: float = 0.0) -> void:
	_cam.position = at
	_cam.rotation_degrees = Vector3(pitch, yaw, 0.0)
	# ⭐ A FULL SECOND, NOT THREE FRAMES. Anything that RIDES the camera — the rain field especially — is empty
	# for the moment after a teleport: its emitter has moved but the air it filled is back where the camera used
	# to be, and a drop needs spawn_height / fall_speed to fall into frame. Shooting three frames after the jump
	# photographed a downpour as four specks.
	await _wait(1.0)
	await _frames(2)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_imgs.append(img)
	_tags.append(tag)
	_measure(tag, img)

## The two numbers taste cannot settle: how bright the bottom half of the frame actually is (a facade nobody can
## see is not a facade), and how much of it has already collapsed to the flat haze colour.
func _measure(tag: String, img: Image) -> void:
	var haze: Color = _void.get(&"haze_color")
	var sum := 0.0
	var hazed := 0
	var n := 0
	var y0 := int(img.get_height() * 0.5)
	for y in range(y0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			sum += c.get_luminance()
			if absf(c.r - haze.r) < 0.02 and absf(c.g - haze.g) < 0.02 and absf(c.b - haze.b) < 0.02:
				hazed += 1
			n += 1
	print("QA_PIX %-14s lower_half_luma=%.4f pure_haze=%.1f%% eye_y=%.1f pitch=%.0f" % [
		tag, sum / float(maxi(n, 1)), 100.0 * float(hazed) / float(maxi(n, 1)),
		_cam.global_position.y, _cam.rotation_degrees.x])

## Mean absolute luminance difference between the last two frames, over the UPPER half (where the deck is).
## 0 means nothing moved; a few thousandths means the clouds are sliding.
func _report_drift() -> void:
	if _imgs.size() < 2:
		return
	var a: Image = _imgs[_imgs.size() - 2]
	var b: Image = _imgs[_imgs.size() - 1]
	var total := 0.0
	var n := 0
	for y in range(0, int(a.get_height() * 0.5), 4):
		for x in range(0, a.get_width(), 4):
			total += absf(a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance())
			n += 1
	print("QA_DRIFT mean_abs_luma_change=%.5f over %d samples (0 = the deck never moved)" % [
		total / float(maxi(n, 1)), n])

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
