extends SceneTree
## TEMPORARY DIAGNOSTIC: how close behind cover can an actor stand before InkOutline's occlusion test
## stops noticing it is hidden? That distance is set by mask_occlusion_bias, and the answer decides
## whether the remaining "hidden NPCs still show faintly" is a tuning problem or a precision one.
##
## Five identical actors sit behind one wall at increasing gaps, each behind its own vertical rib (a rib
## puts INK LINES on the wall's face — a flat wall carries none, so there would be nothing to punch a
## hole in). Three frames are shot: occlusion off, occlusion on, and a REFERENCE with every hidden actor
## taken off the mask layer, which is what the frame should look like. Each actor's screen band is then
## diffed against the reference: 0 differing pixels = that gap is detected, anything else = it is not.
##
## Run: godot --path <abs project> -s scripts/tools/__ink_gap_probe.gd -- --shots-dir=<dir>

const INK_PATH := "res://scripts/effects/ink_outline.gd"
const GAPS := [0.02, 0.05, 0.10, 0.20, 0.40]  ## CLEAR AIR between the wall's back face and the actor's front face
const SLOTS := [-6.0, -3.0, 0.0, 3.0, 6.0] ## world x for each gap's actor + rib
const WALL_Z := -6.0
const SETTLE := 40
const BETWEEN := 12

var _frame := 0
var _shot := 0
var _wait := 0
var _dir := "user://ink_gap_probe"
var _ink: MeshInstance3D = null
var _ink_script: Variant = null
var _hidden: Array[MeshInstance3D] = []
var _cam: Camera3D = null

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
	# Set, wait, THEN shoot — InkOutline pushes its uniforms from its own _process.
	match _shot:
		0: _ink.set(&"occlusion_aware_mask", false)
		1:
			_save("off")
			_ink.set(&"occlusion_aware_mask", true)
		2:
			_save("on")
			for m in _hidden:
				m.layers = 1  # off the mask entirely -> the reference
		3:
			_save("ref")
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

## An actor dressed exactly as the game dresses one since the inverted hull was deleted (2026-08-27):
## an opaque body on render layer 1 PLUS the ink-mask layer, wearing InkOutline's screen-space ring at
## the neutral (black) id. The ring is what this probe's scene needs to be REPRESENTATIVE — the mask's
## depth is what it actually measures, and that comes from the opaque body either way, but an actor with
## no outline at all is not the thing being shipped.
func _actor(pos: Vector3, size: Vector3) -> MeshInstance3D:
	var mi := _box(pos, size, Color(0.75, 0.2, 0.2))
	mi.layers = 1 | int(_ink_script.ACTOR_INK_MASK_LAYER)
	_ink_script.apply_tint_mesh(mi, int(_ink_script.TINT_ID_NEUTRAL))
	return mi

func _build() -> void:
	_ink_script = load(INK_PATH)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	root.add_child(light)

	# One continuous wall, thin so an actor can stand right behind it.
	root.add_child(_box(Vector3(0.0, 0.0, WALL_Z), Vector3(20.0, 8.0, 0.2), Color(0.5, 0.5, 0.55)))
	for i in SLOTS.size():
		# A rib standing proud of the wall: its two vertical edges are the ink lines a hidden actor eats.
		root.add_child(_box(Vector3(SLOTS[i], 0.0, WALL_Z + 0.35), Vector3(0.7, 8.0, 0.5),
			Color(0.4, 0.41, 0.46)))
		# ⭐ Measure from the actor's FRONT FACE, not its origin. The actor is 0.6 m deep, so placing its
		# CENTRE one gap behind the wall pushed its front face THROUGH the wall at small gaps — it was
		# genuinely visible, and the probe read that as the fix failing.
		var a := _actor(Vector3(SLOTS[i], 0.0, WALL_Z - 0.1 - float(GAPS[i]) - 0.3), Vector3(3.0, 3.4, 0.6))
		_hidden.append(a)
		root.add_child(a)

	_cam = Camera3D.new()
	_cam.fov = 70.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.72, 0.78, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_cam.environment = env
	_cam.position = Vector3(0.0, 0.0, 0.0)
	_cam.current = true
	root.add_child(_cam)
	_ink = _ink_script.new()
	_cam.add_child(_ink)
	print("[gap] bias=%.4f  search_px=%.1f" % [
		_ink.get(&"mask_occlusion_bias"), _ink.get(&"mask_rim_search_px")])

var _imgs := {}

func _save(key: String) -> void:
	var img := root.get_texture().get_image()
	_imgs[key] = img
	img.save_png("%s/%s.png" % [_dir, key])

func _dark(c: Color) -> bool:
	return c.r < 0.18 and c.g < 0.18 and c.b < 0.18

## Ink pixels inside a screen band that differ from the reference frame.
func _band_diff(a: Image, b: Image, x0: int, x1: int) -> int:
	var n := 0
	for y in a.get_height():
		for x in range(maxi(0, x0), mini(a.get_width(), x1)):
			if _dark(a.get_pixel(x, y)) != _dark(b.get_pixel(x, y)):
				n += 1
	return n

func _report() -> void:
	var ref: Image = _imgs["ref"]
	var w := ref.get_width()
	var half := w / 2
	# Screen x of each slot: NDC = (x / |z|) / tan(hfov/2), hfov from the 70-degree vertical fov.
	var tan_h := tan(deg_to_rad(35.0)) * (float(w) / float(ref.get_height()))
	print("\n gap(m) | screen band |  OFF diff |   ON diff  | verdict")
	print("--------+-------------+-----------+------------+---------------------------")
	for i in SLOTS.size():
		var z: float = absf(WALL_Z - 0.1 - float(GAPS[i]) - 0.3)
		var ndc: float = (float(SLOTS[i]) / z) / tan_h
		var cx := int(round(float(half) + ndc * float(half)))
		var x0 := cx - 70
		var x1 := cx + 70
		var d_off := _band_diff(_imgs["off"], ref, x0, x1)
		var d_on := _band_diff(_imgs["on"], ref, x0, x1)
		var verdict := "DETECTED (ink fully restored)" if d_on == 0 else (
			"partial (%d px still wrong)" % d_on if d_on < d_off else "NOT detected")
		print("  %5.3f | %4d..%-4d  |    %4d   |    %4d    | %s" % [
			GAPS[i], x0, x1, d_off, d_on, verdict])
	print("\nThe smallest gap whose ON diff is 0 is how close an actor may stand to cover")
	print("and still be recognised as hidden, at ~%.1f m from the camera.\n" % absf(WALL_Z))
