extends SceneTree
## QA probe for BrushZFightClean — the permanent before/after A/B, the __ink_seam_shots idiom. Loads the live
## level's FuncGodotMap subtree alone (no game boot), finds the biggest UP-facing brush overlaps with
## `overlap_report`, parks a camera over each at a grazing angle, and shoots the same frame with the pass OFF and
## then ON. In the OFF shot the slab shows a curved boundary where the depth tie switches winners (and a
## texture mix along it); in the ON shot one texture covers the slab continuously. Same camera, same frame count.
##
## WINDOWED on purpose — a z-fight is a depth-test artefact and headless renders nothing.
##
## Run (from the project root):
##   & "C:\Users\dalla\bin\godot.cmd" --path . -s scripts/tools/__zfight_shots.gd -- --shots-dir=<dir>
## Writes before_camN.png / after_camN.png and prints the pair counts + the clean() tally to stdout.
##
## ⭐ Everything is built on the FIRST _process frame, not in _initialize: nodes added there are not yet inside
## the tree, so global_transform reads (the census) and look_at raise engine errors and return identity.

const SETTLE := 30
var _dir := "."
var _frame := 0
var _phase := 0
var _holder: Node3D
var _cams: Array[Camera3D] = []
var _cleaner: Node
var _shot := 0


var _built := false


func _build() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--shots-dir="):
			_dir = String(a).trim_prefix("--shots-dir=")
	var ps: PackedScene = load("res://scenes/levels/trenchboom_test_level.tscn")
	var level := ps.instantiate()
	var map: Node = level.find_child("FuncGodotMap", true, false)
	map.get_parent().remove_child(map)
	level.free()
	_holder = Node3D.new()
	root.add_child(_holder)
	_holder.add_child(map)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.4, 0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.6
	env.environment = e
	_holder.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.2
	_holder.add_child(sun)
	_cleaner = load("res://scripts/components/brush_zfight_clean.gd").new()
	var rep: Dictionary = _cleaner.overlap_report(_holder, 6)
	print("[zf-shots] before: %d pairs %.1f m2" % [rep.pairs, rep.area_m2])
	# one camera per big overlap, hovering over its centre at a grazing angle
	var picked := 0
	for p in rep.top:
		if p.normal.y < 0.9 or picked >= 3:
			continue
		print("[zf-shots] cam %d -> %.1f m2 at %s (%s)" % [picked, p.area, p.at, p.materials])
		var cam := Camera3D.new()
		_holder.add_child(cam)
		var at: Vector3 = p.at
		cam.look_at_from_position(at + Vector3(6, 3, 8), at, Vector3.UP)
		cam.fov = 60
		cam.current = false
		_cams.append(cam)
		picked += 1
	if _cams.is_empty():
		print("[zf-shots] no up-facing overlap to shoot"); quit(1)
	_cams[0].current = true


func _process(_delta: float) -> bool:
	if not _built:
		_built = true
		_build()   # nodes must be INSIDE the tree: global_transform / look_at are tree-only
		return false
	_frame += 1
	if _frame < SETTLE:
		return false
	var cam_i := _shot % _cams.size()
	var state := "before" if _phase == 0 else "after"
	if _frame == SETTLE:
		_cams[cam_i].current = true
		return false
	if _frame == SETTLE + 3:
		var img := root.get_texture().get_image()
		img.save_png("%s/%s_cam%d.png" % [_dir, state, cam_i])
		print("[zf-shots] saved %s_cam%d (%dx%d)" % [state, cam_i, img.get_width(), img.get_height()])
		_shot += 1
		_frame = SETTLE - 1
		if _shot == _cams.size() and _phase == 0:
			_phase = 1
			var rep: Dictionary = _cleaner.clean(_holder)
			print("[zf-shots] cleaned: %d pairs, %d clipped, %d ms" % [rep.pairs, rep.tris_clipped, rep.ms])
		elif _shot == _cams.size() * 2:
			_cleaner.free()
			quit(0)
			return true
		for c in _cams:
			c.current = false
		_cams[_shot % _cams.size()].current = true
	return false
