extends SceneTree
## TEMPORARY DIAGNOSTIC for "the culling seems like scattered around the body".
##
## THE SUSPECTED MECHANISM. The hull's vertex shader sizes its extrusion by VIEWPORT_SIZE, and the mask
## viewport renders at HALF the main 3D buffer's resolution — so the rim in the MASK is twice as wide, in
## screen terms, as the rim you actually see. That leaves a band around every actor where the mask claims
## coverage but the surface actually on screen is plain WORLD. The band has always been there; it used to
## be suppressed uniformly (the old halo). Now the occlusion test judges it per pixel against whatever
## world happens to be there — and around a standing actor that world is FLOOR below (nearer than the
## actor, so "occluded", ink released) and BACKGROUND above (farther, so suppressed). Split verdicts
## across one thin band = scattered culling around the body.
##
## Every previous probe missed it because the actor stood against a FLAT wall, where the band's verdict is
## uniform. This one puts a plainly VISIBLE actor on a floor with a distant backdrop, so the band straddles
## both. Any OFF->ON difference here is the artefact: nothing about a visible actor should change.
##
## Run: godot --path <abs project> -s scripts/tools/__ink_band_probe.gd -- --shots-dir=<dir>

const INK_PATH := "res://scripts/effects/ink_outline.gd"
const HULL_PATH := "res://resources/shaders/outline.gdshader"
const SETTLE := 40
const BETWEEN := 12

var _frame := 0
var _shot := 0
var _wait := 0
var _dir := "user://ink_band"
var _ink: MeshInstance3D = null
var _ink_script: Variant = null
var _imgs := {}
var _actor: MeshInstance3D = null

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		for a in OS.get_cmdline_user_args():
			if String(a).begins_with("--shots-dir="):
				_dir = String(a).trim_prefix("--shots-dir=")
		DirAccess.make_dir_recursive_absolute(_dir)
		_build()
		_wait = SETTLE
		return false
	_wait -= 1
	if _wait > 0:
		return false
	match _shot:
		0: _ink.set(&"occlusion_aware_mask", false)
		1:
			_imgs["off"] = root.get_texture().get_image()
			_ink.set(&"occlusion_aware_mask", true)
		2:
			_imgs["on"] = root.get_texture().get_image()
			# HALO MEASUREMENT (the docs' own metric): take the actor OFF the mask layer so the world's ink
			# comes out whole, while the actor still stands exactly where it was and occludes exactly what it
			# occluded. Ink present there and MISSING in the masked frame is suppression, and how far that
			# reaches past the actor's own silhouette is the halo.
			_actor.layers = 1
		3:
			_imgs["ref"] = root.get_texture().get_image()
			_report()
			quit()
			return true
	_shot += 1
	_wait = BETWEEN
	return false

func _box(pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	mi.position = pos
	return mi

func _build() -> void:
	_ink_script = load(INK_PATH)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -25.0, 0.0)
	root.add_child(light)

	# Floor running away from the camera, and a backdrop far behind the actor. The point is that the world
	# immediately AROUND the actor's silhouette is NEARER below (floor) and FARTHER above (backdrop).
	root.add_child(_box(Vector3(0.0, -0.5, -14.0), Vector3(40.0, 1.0, 32.0), Color(0.5, 0.5, 0.55)))
	root.add_child(_box(Vector3(0.0, 4.0, -26.0), Vector3(40.0, 9.0, 0.5), Color(0.42, 0.43, 0.48)))
	# A couple of props near the actor so the band also straddles hard depth steps, not just the floor.
	root.add_child(_box(Vector3(-1.6, 0.4, -4.2), Vector3(0.5, 0.8, 0.5), Color(0.38, 0.4, 0.44)))
	root.add_child(_box(Vector3(1.6, 0.4, -4.2), Vector3(0.5, 0.8, 0.5), Color(0.38, 0.4, 0.44)))

	# THE ACTOR — plainly visible, standing on the floor. Nothing about it may change between the shots.
	var actor := _box(Vector3(0.0, 0.9, -5.0), Vector3(0.7, 1.8, 0.5), Color(0.75, 0.2, 0.2))
	var hull := ShaderMaterial.new()
	hull.shader = load(HULL_PATH)
	hull.set_shader_parameter("outline_color", Color.BLACK)
	hull.set_shader_parameter("outline_width", 2.0)
	actor.material_overlay = hull
	actor.layers = 1 | int(_ink_script.ACTOR_INK_MASK_LAYER)
	root.add_child(actor)
	_actor = actor

	var cam := Camera3D.new()
	cam.fov = 70.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.72, 0.78, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	cam.position = Vector3(0.0, 1.6, 0.0)
	cam.current = true
	root.add_child(cam)
	_ink = _ink_script.new()
	cam.add_child(_ink)

func _dark(c: Color) -> bool:
	return c.r < 0.18 and c.g < 0.18 and c.b < 0.18

func _report() -> void:
	var off: Image = _imgs["off"]
	var on: Image = _imgs["on"]
	var ref: Image = _imgs["ref"]
	on.save_png("%s/1_on.png" % _dir)
	var w := on.get_width()
	var h := on.get_height()
	var changed := 0
	for y in h:
		for x in w:
			if _dark(off.get_pixel(x, y)) != _dark(on.get_pixel(x, y)):
				changed += 1
	print("[band] OFF->ON changed %d ink px around a VISIBLE actor  [must be 0]" % changed)

	# The actor's own silhouette, from its distinctive albedo in the masked frame.
	var ax0 := w
	var ay0 := h
	var ax1 := -1
	var ay1 := -1
	for y in h:
		for x in w:
			var c := on.get_pixel(x, y)
			if c.r > 0.35 and c.g < 0.30 and c.b < 0.30:
				ax0 = mini(ax0, x)
				ay0 = mini(ay0, y)
				ax1 = maxi(ax1, x)
				ay1 = maxi(ay1, y)
	# Ink the world HAS when nothing suppresses, and LOSES when the actor is masked.
	var lx0 := w
	var ly0 := h
	var lx1 := -1
	var ly1 := -1
	var lost := 0
	for y in h:
		for x in w:
			if _dark(ref.get_pixel(x, y)) and not _dark(on.get_pixel(x, y)):
				lost += 1
				lx0 = mini(lx0, x)
				ly0 = mini(ly0, y)
				lx1 = maxi(lx1, x)
				ly1 = maxi(ly1, y)
	print("[band] actor silhouette : (%d,%d)..(%d,%d)" % [ax0, ay0, ax1, ay1])
	print("[band] suppressed ink   : (%d,%d)..(%d,%d)  (%d px)" % [lx0, ly0, lx1, ly1, lost])
	if lx1 >= 0 and ax1 >= 0:
		print("[band] HALO past the actor, in px of the 792-wide screen: left %d, right %d, top %d, bottom %d" % [
			ax0 - lx0, lx1 - ax1, ay0 - ly0, ly1 - ay1])
		print("[band] the rim you SEE is outline_width*2 = 4 px of the 1584 buffer = 2 px here;")
		print("[band] the mask draws its rim at 4 px of the 792 MASK, so it claims twice that.")
	print("[band] wrote to %s" % _dir)
