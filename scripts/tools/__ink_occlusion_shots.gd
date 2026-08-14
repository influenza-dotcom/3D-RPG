extends SceneTree
## QA probe for the ink pass's ACTOR OCCLUSION (InkOutline.occlusion_aware_mask). Builds a bare scene
## with one hull-rimmed actor IN THE OPEN and one HIDDEN BEHIND a pillar, and shoots the same frame
## twice — occlusion off, then on — so the two can be diffed by eye and by pixel count.
##
## The bug it exists to catch: the mask viewport renders only actors, so nothing in it occludes them.
## A hidden actor stamped its silhouette into the mask anyway and bit that shape out of every ink line
## it overlapped — clean circles punched through the pillar's straight black edges, with nobody visibly
## there. The pillar is deliberately a hard vertical silhouette against empty sky, because that is the
## shape the artefact is most obvious on (the report came from stair nosings and building corners).
##
## WINDOWED on purpose — headless never compiles shaders, so a headless shot shows fallback materials
## and proves nothing. This is also the only check that the two .gdshader files compile at all.
##
## Run (from the project root):
##   & "C:\Users\dalla\bin\godot.cmd" --path . -s scripts/tools/__ink_occlusion_shots.gd -- --shots-dir=<dir>
##
## ⭐A `-s` script COMPILES BEFORE AUTOLOADS REGISTER, so anything autoloaded must be reached through
## /root at runtime rather than named as an identifier (the house harness gotcha).

## ⭐ load() AT RUNTIME, never preload. A compile-time preload of ink_outline.gd drags in ViewModelCamera
## -> groups.gd -> player.gd, which names the GameSettings autoload — and under `-s` that identifier does
## not exist yet, so the whole harness fails to compile with an error that names none of this.
const INK_PATH := "res://scripts/effects/ink_outline.gd"
const HULL_PATH := "res://resources/shaders/outline.gdshader"

var _ink_script: Variant = null
var _hull_shader: Shader = null
const SETTLE := 40   ## frames before the first shot: shader compiles + the deferred mask build
const BETWEEN := 12  ## frames between the two shots, so the toggled uniform is definitely on screen

var _frame := 0
var _shot := 0
var _wait := 0
var _dir := "user://ink_occlusion_shots"
var _ink: MeshInstance3D = null

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
	# ⭐ SET, WAIT, THEN SHOOT — never set and shoot in the same frame. InkOutline pushes its uniforms from
	# its OWN _process, which may not have run yet this frame, so a shot taken immediately after flipping
	# the export captures the PREVIOUS state and silently swaps the two labels. (It did exactly that.)
	match _shot:
		0:
			_ink.set(&"occlusion_aware_mask", false)
		1:
			_shoot("0_occlusion_OFF")
			_ink.set(&"occlusion_aware_mask", true)
		2:
			_shoot("1_occlusion_ON")
		_:
			print("[ink-shots] wrote both frames to %s" % _dir)
			quit()
			return true
	_shot += 1
	_wait = BETWEEN
	return false

## A hull-rimmed actor exactly as Character/NPC dress one: an opaque body carrying outline.gdshader as a
## material_overlay, on render layer 1 PLUS the ink mask layer.
func _actor(pos: Vector3, size: Vector3, rim: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var base := StandardMaterial3D.new()
	base.albedo_color = Color(0.75, 0.2, 0.2)
	mi.material_override = base
	var hull := ShaderMaterial.new()
	hull.shader = _hull_shader
	hull.set_shader_parameter("outline_color", rim)
	hull.set_shader_parameter("outline_width", 2.0)  # NpcData's authored rim
	mi.material_overlay = hull
	mi.layers = 1 | int(_ink_script.ACTOR_INK_MASK_LAYER)
	mi.position = pos
	return mi

func _box(pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	mi.position = pos
	return mi  # layer 1 only: WORLD geometry, invisible to the mask camera

func _build() -> void:
	_ink_script = load(INK_PATH)
	_hull_shader = load(HULL_PATH)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	root.add_child(light)

	# THE OCCLUDER, shaped like the case that was reported: a wall whose FACE carries ink lines, not just
	# a silhouette. A flat wall has no ink on it at all (no depth step, no normal change), so a hidden
	# actor behind one has nothing to punch a hole in — the artefact only shows where lines cross the
	# thing hiding them, which is exactly why stair nosings and building corners were where it was seen.
	root.add_child(_box(Vector3(0.0, 0.0, -6.0), Vector3(9.0, 7.0, 0.4), Color(0.5, 0.5, 0.55)))
	# Four steps standing proud of that wall: each one draws a depth-step line down the wall's face.
	for i in 4:
		root.add_child(_box(
			Vector3(-1.8 + float(i) * 1.2, -1.0 + float(i) * 0.7, -5.4),
			Vector3(1.0, 4.0, 0.5), Color(0.42, 0.43, 0.48)))

	# HIDDEN: dead behind the wall, 3 m further out, right where those step lines cross the frame.
	# Nothing of it can be seen — but its silhouette used to bite a person-shaped hole in every one.
	root.add_child(_actor(Vector3(0.0, 0.0, -9.0), Vector3(3.0, 3.4, 0.6), Color.BLACK))
	# VISIBLE control, out in the open in FRONT of the wall — its rim must stay clean and un-doubled in
	# BOTH shots. This is the half of the contract the fix must not break.
	root.add_child(_actor(Vector3(-3.4, -0.6, -4.0), Vector3(1.2, 2.6, 0.6), Color.BLACK))

	var cam := Camera3D.new()
	cam.fov = 70.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.72, 0.78, 0.85)  # flat sky, so silhouette ink reads at full contrast
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	cam.position = Vector3(0.0, 0.6, 0.0)
	cam.current = true
	root.add_child(cam)

	_ink = _ink_script.new()
	cam.add_child(_ink)
	print("[ink-shots] InkOutline attached: %s  mask layer bit %d" % [
		is_instance_valid(_ink), int(_ink_script.ACTOR_INK_MASK_LAYER)])

func _shoot(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [_dir, name]
	img.save_png(path)
	# Count near-black pixels: the ink is the only black in this scene, so a DROP from the OFF shot to
	# the ON shot would mean the fix ate lines, and a RISE means it restored the ones the hidden actor
	# was eating. Reported because a PNG alone cannot tell you which way it moved.
	var black := 0
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.r < 0.18 and p.g < 0.18 and p.b < 0.18:
				black += 1
	print("[ink-shots] %s -> %s   ink-ish pixels: %d" % [name, path, black])
