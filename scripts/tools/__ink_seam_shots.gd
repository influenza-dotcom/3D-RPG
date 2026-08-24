extends SceneTree
## QA probe for the ink pass's SEAM MERGE (InkOutline.crease_min_feature_px) and JUNCTION DIAL
## (InkOutline.concave_crease_strength) — the permanent A/B, the __ink_occlusion_shots idiom. Builds a
## bare scene of the joins a box-built level is made of and shoots the same frame under each setting so
## they can be diffed by eye and by pixel count:
##   FLUSH    — faces exactly coincident, tops coplanar (the ideal blockout join; must draw ONE silhouette)
##   OVERLAP  — the two boxes interpenetrate 0.5 m (the usual hand-authored join; same)
##   GAP      — 2 cm of air between them (a crack you can see through: the DEPTH term's business, untouched)
##   STEP     — the second box is 2 cm taller: the sub-pixel sliver that inked like a corner. THE artefact
##              the seam merge exists for — its dotted line must be gone at the default (camera B shows it)
##   STACK    — a slab lying on top of another, offset (the sketch's 3D case). Two knobs meet here: the
##              CONCAVE junction goes with concave_crease_strength, and the depth STEP between the two
##              slabs goes with contact_merge_m — a stack of these is a staircase, which is the frame the
##              user reported ("not where the two actually are touching")
##   DETAIL   — pilasters 8 cm proud of a wall at ~27 m: ~2 px reveals, BELOW the default min feature, so
##              their interior lines go — the documented collateral, here so it is seen, not discovered
##   CHAMFER  — a 30-degree strip on a wall: a SHALLOW crease that must NOT dim under the merge (the ratio
##              rule; the first version dimmed it to 22%)
##   RAMP     — a 30-degree wedge on a floor: the same shallow crease, concave, on the ground
##   STAIRS   — four 0.5 m risers seen edge-on: each step is a PURE depth step (no normal change), the
##              case the user reported. Only contact_merge_m merges these; both crease knobs leave them
##
## WINDOWED on purpose — headless never compiles a shader, so a headless shot shows fallback materials and
## proves nothing (and a broken .gdshader passes every test in this project). This is also the only check
## that the seam-merge / junction-dial edits COMPILE at all.
##
## Run (from the project root):
##   & "C:\Users\dalla\bin\godot.cmd" --path . -s scripts/tools/__ink_seam_shots.gd -- --shots-dir=<dir> [--cam=B]
## Camera A (default) frames the whole row; camera B is the tighter view that rasterises the STEP sliver.
##
## ⭐ A `-s` script compiles BEFORE autoloads register, so ink_outline.gd is load()ed at RUNTIME.

const INK_PATH := "res://scripts/effects/ink_outline.gd"

const SETTLE := 60  ## frames before the first shot: shader compiles + the deferred mask build
const BETWEEN := 12

## The sweep: [name, crease_min_feature_px, concave_crease_strength]. feature_00 is the pre-seam-merge
## behaviour and is the reference every other shot is read against.
## [name, crease_min_feature_px, concave_crease_strength, contact_merge_m]
const VARIANTS := [
	["before", 0.0, 1.0, 0.0],        # every term as it was before 2026-08-18
	["default", 4.0, 1.0, 1.0],       # what ships
	["concave_00", 4.0, 0.0, 1.0],    # junction dial off: only convex edges + silhouettes
	["contact_00", 4.0, 1.0, 0.0],    # contact merge off: every step draws its own line again
]

var _frame := 0
var _step := 0
var _wait := 0
var _dir := "user://ink_seam_shots"
var _ink: MeshInstance3D = null
## ⭐ SET, WAIT, THEN SHOOT — InkOutline pushes uniforms from its OWN _process, so a shot taken the same
## frame a knob moves captures the PREVIOUS value and silently swaps the labels.
var _pending := ""
## Camera C (`--cam=C`) stands at walking height on the STAIRS case; A/B look down at the whole row.
var _eye_level := false

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
	if _pending != "":
		_shoot(_pending)
		_pending = ""
		_step += 1
		_wait = 1
		return false
	if _step >= VARIANTS.size():
		print("[seam-shots] done -> %s" % _dir)
		quit()
		return true
	var v: Array = VARIANTS[_step]
	_ink.set(&"crease_min_feature_px", v[1])
	_ink.set(&"concave_crease_strength", v[2])
	_ink.set(&"contact_merge_m", v[3])
	_pending = v[0]
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

## One L-shaped pair centred on `cx`. `dx` shifts the second box along X (0 = flush, negative =
## interpenetrating, positive = a gap); `dy` raises its top.
func _pair(cx: float, dx: float, dy: float) -> void:
	var col := Color(0.62, 0.62, 0.66)
	# arm along X
	root.add_child(_box(Vector3(cx - 1.0, 1.0, -1.0), Vector3(4.0, 2.0, 2.0), col))
	# arm along Z, butted against its +X face
	root.add_child(_box(
		Vector3(cx + 2.0 + dx, 1.0 + dy * 0.5, 0.0),
		Vector3(2.0, 2.0 + dy, 4.0), col))

func _build() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	root.add_child(light)
	var col := Color(0.62, 0.62, 0.66)

	_pair(-14.0, 0.0, 0.0)     # FLUSH
	_pair(-7.0, -0.5, 0.0)     # OVERLAP
	_pair(0.0, 0.02, 0.0)      # GAP 2 cm
	_pair(7.0, 0.0, 0.02)      # STEP 2 cm

	# STACK: a slab lying on top of another, offset — the 3D half of the sketch.
	root.add_child(_box(Vector3(14.0, 0.5, 0.0), Vector3(5.0, 1.0, 2.5), col))
	root.add_child(_box(Vector3(15.0, 1.5, -1.0), Vector3(5.0, 1.0, 2.5), col))

	# DETAIL: a wall with a pilaster standing 8 cm proud of it. This is the half of the contract the
	# seam merge must NOT break — a small feature that is genuinely there keeps its interior lines.
	root.add_child(_box(Vector3(21.0, 2.0, -2.0), Vector3(6.0, 4.0, 0.5), col))
	root.add_child(_box(Vector3(20.0, 2.0, -1.71), Vector3(0.5, 4.0, 0.08), col))
	root.add_child(_box(Vector3(22.0, 2.0, -1.71), Vector3(0.5, 4.0, 0.08), col))

	# CHAMFER: a wall with a 30-degree chamfer strip along its top — a SHALLOW crease (|dN| = 0.52) that
	# must stay as strong as it was before the seam merge (the review found the first version dimmed it).
	# RAMP: a 30-degree wedge meeting the floor — the same shallow crease, concave, on the ground.
	var wall := _box(Vector3(29.0, 1.5, 0.0), Vector3(6.0, 3.0, 0.5), col)
	root.add_child(wall)
	var chamfer := _box(Vector3(29.0, 3.0, 0.15), Vector3(6.0, 0.4, 0.5), col)
	chamfer.rotation_degrees = Vector3(30.0, 0.0, 0.0)
	root.add_child(chamfer)
	var floor_slab := _box(Vector3(37.0, -0.25, 0.0), Vector3(6.0, 0.5, 4.0), col)
	root.add_child(floor_slab)
	var ramp := _box(Vector3(37.0, 0.0, 0.0), Vector3(3.0, 0.3, 3.0), col)
	ramp.rotation_degrees = Vector3(30.0, 0.0, 0.0)
	root.add_child(ramp)

	# STAIRS: four 0.5 m risers — the level's authored module and the case the user reported. Seen from
	# this eye the risers are edge-on, so each step is a PURE depth discontinuity between two treads (no
	# normal change at all): crease knobs cannot touch it, contact_merge_m is what merges the flight into
	# one stepped solid.
	# Each step is a solid block from the ground up: top at 0.5*(i+1), 1.2 m tread.
	for i in 5:
		var top := 0.5 * float(i + 1)
		root.add_child(_box(
			Vector3(45.0, top * 0.5, 2.0 - float(i) * 1.2),
			Vector3(5.0, top, 1.2), col))

	var cam := Camera3D.new()
	cam.fov = 70.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.75, 0.80, 0.86)  # flat sky, so silhouette ink reads at full contrast
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	# Two viewpoints: A (default) frames the whole row wide; B is the tighter original that rasterises the
	# 2 cm STEP sliver as a visible line, which A does not — pass `-- --cam=B` to verify the merge on it.
	cam.position = Vector3(19.0, 12.0, 20.0)
	for a in OS.get_cmdline_user_args():
		if String(a) == "--cam=B":
			cam.fov = 60.0
			cam.position = Vector3(2.0, 11.0, 17.0)
		if String(a) == "--cam=C":
			# ⭐ STANDING ON THE TOP STEP, LOOKING DOWN THE FLIGHT — the frame the user reported, and the
			# only pose that reproduces it. From up high the risers FACE the camera and each step is a
			# CREASE (both crease knobs act, contact_merge_m does nothing); looking down the flight they go
			# edge-on and each step becomes a PURE depth discontinuity between two treads, which only
			# contact_merge_m can merge. Measured at this pose: before 2639 ink px, default 1924 (-27%),
			# and contact_00 comes back to 2639 exactly — i.e. the whole difference is this one knob.
			cam.fov = 90.0
			cam.position = Vector3(45.6, 3.6, -4.6)
			cam.rotation_degrees = Vector3(-16.0, 180.0, 0.0)
			_eye_level = true
	if not _eye_level:
		cam.rotation_degrees = Vector3(-30.0, 0.0, 0.0)
	cam.current = true
	root.add_child(cam)

	_ink = load(INK_PATH).new()
	cam.add_child(_ink)
	print("[seam-shots] ink attached: %s" % [is_instance_valid(_ink)])

func _shoot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [_dir, name])
	# ⭐ NEAREST x3 for viewing — the render-probe resolution trap: never raise content_scale_size to
	# make the lines legible, upscale the saved PNG instead.
	var big := Image.new()
	big.copy_from(img)
	big.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	big.save_png("%s/%s_x3.png" % [_dir, name])
	var black := 0
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.r < 0.18 and p.g < 0.18 and p.b < 0.18:
				black += 1
	print("[seam-shots] %s  ink-ish pixels: %d" % [name, black])
