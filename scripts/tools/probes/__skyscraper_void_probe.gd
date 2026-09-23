extends Node
## SKYSCRAPER VOID probe (2026-09-17): does the level actually read as the roof of a tower? Boots the REAL game,
## drops a SkyscraperVoid on the live level, walks the player to the map's edge and shoots the three views the
## illusion lives or dies on — over the parapet, straight down, and mid-fall — plus the numbers a screenshot
## cannot settle.
##
## Run WINDOWED (shaders never compile headless, so a headless run proves nothing about this), from PowerShell:
##   & "C:\Users\dalla\bin\godot.cmd" --path "C:\Users\dalla\3D RPG\rpg" res://scripts/tools/probes/__skyscraper_void_probe.tscn
## Frames land in user://skyscraper_void_probe.
##
## ⭐It loads the component with `load()` + `.new()` instead of naming `SkyscraperVoid`: the class_name of a
## brand-new script is not in the editor's global class cache yet, and naming the type would fail this probe to
## PARSE on the very run that is supposed to prove the script works.
##
## What each printed line is for:
##   • `QA_FIT`   — what the auto fit measured: the level's AABB, the roofline it hung the facade from, and the
##                  footprint rect. THIS is the line that catches the failure mode in the component's @risk note
##                  (one stray far-away mesh dragging the footprint off the building).
##   • `QA_MESH`  — per built child: surfaces, vertices, and the material's shader. A facade surface wearing
##                  anything but facade_void.gdshader means Ps1Warp repainted the drop.
##   • `QA_VIEW`  — per frame: where the eye is, where it is looking, and how far below the eye the haze is
##                  total, so "the bottom is invisible" is a number and not an opinion.
##   • `QA_SHADER`— the compile verdict. A shader error prints to stderr as well, but this line says plainly
##                  whether the material came back with the parameters the component set.

const COMPONENT := "res://scripts/components/skyscraper_void.gd"

var _dir := "user://skyscraper_void_probe"
var _frames_img: Array[Image] = []
var _frames_tag: Array[String] = []
var _player = null
var _void_node: Node3D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "SkyscraperVoidDriver"
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

	_player = Groups.human_player(get_tree())
	var level: Node = Groups.level_node(get_tree())
	if _player == null or level == null:
		print("QA_FAIL player=", _player, " level=", level)
		get_tree().quit(1)
		return
	print("QA_LEVEL ", level.name, " scene=", level.scene_file_path)

	# --- build the drop on the live level -----------------------------------------------------------------
	var script: GDScript = load(COMPONENT)
	if script == null:
		print("QA_FAIL component did not load")
		get_tree().quit(1)
		return
	_void_node = script.new()
	_void_node.name = "SkyscraperVoid"
	level.add_child(_void_node)          # its _ready() builds everything
	await _frames(5)

	var loop: PackedVector2Array = _void_node.get(&"last_footprint")
	var roof_y: float = _void_node.get(&"last_roof_y")
	print("QA_FIT roof_y=%.2f points=%d rect=%s" % [roof_y, loop.size(), str(_rect_of(loop))])
	if loop.size() < 3:
		print("QA_FAIL nothing was built — the fit found no geometry")
		get_tree().quit(1)
		return
	for c in _void_node.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var shaders := PackedStringArray()
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var sh := mat as ShaderMaterial
			shaders.append(sh.shader.resource_path.get_file() if sh != null and sh.shader != null else str(mat))
		print("QA_MESH %s surfaces=%d verts=%d aabb=%s mats=[%s]" % [
			mi.name, mi.mesh.get_surface_count(), _vertex_count(mi.mesh), str(mi.mesh.get_aabb().size),
			", ".join(shaders)])
	# The facade and the fog plane are both OPTIONAL now (both ship off), so the uniform read below takes whatever
	# the component actually built rather than assuming a node name — a null here aborted the whole probe.
	var probe_mat: ShaderMaterial = null
	for child in _void_node.get_children():
		var m := child as MeshInstance3D
		if m != null and m.mesh != null and m.get_active_material(0) is ShaderMaterial:
			probe_mat = m.get_active_material(0) as ShaderMaterial
			break
	if probe_mat == null:
		print("QA_FAIL the component built nothing with a shader material")
		get_tree().quit(1)
		return
	print("QA_SHADER haze_full=%s floor_height=%s flat_fill=%s" % [
		str(probe_mat.get_shader_parameter("haze_full")),
		str(probe_mat.get_shader_parameter("floor_height")),
		str(probe_mat.get_shader_parameter("flat_fill"))])

	# --- stand on the edge, facing out over the drop ------------------------------------------------------
	# ⭐ THE FOOTPRINT EDGE IS NOT THE MAP'S EDGE. The fit is the level's AABB, and this map does not fill its own
	# bounding box, so standing at the rect's edge drops the player into the void (the first run of this probe
	# shot every frame in free fall). March out from where the player actually spawned toward the chosen edge and
	# stop at the LAST tile of real floor — that is the parapet the player would walk to.
	var edge := _longest_edge(loop)
	var mid: Vector2 = edge[0]
	var outward: Vector2 = edge[1]
	var target: Vector3 = _void_node.to_global(Vector3(mid.x, 0.0, mid.y))
	var stand := _walk_to_edge(_player.global_position, target)
	print("QA_EDGE spawn=(%.1f, %.1f, %.1f) aimed=(%.1f, %.1f) stand=(%.1f, %.1f, %.1f)" % [
		_player.global_position.x, _player.global_position.y, _player.global_position.z,
		target.x, target.z, stand.x, stand.y, stand.z])
	_player.global_position = stand
	_player.velocity = Vector3.ZERO
	_player.rotation.y = atan2(-outward.x, -outward.y)   # face outward (-Z forward)
	_player.head.rotation_degrees.x = -8.0
	await _wait(0.6)
	await _grab("01_over_the_parapet", 2)
	_player.head.rotation_degrees.x = -45.0
	await _wait(0.4)
	await _grab("02_looking_down", 2)
	_player.head.rotation_degrees.x = -85.0
	await _wait(0.4)
	await _grab("03_straight_down", 2)
	_player.head.rotation_degrees.x = 4.0
	await _wait(0.4)
	await _grab("04_skyline", 2)

	# --- and the payoff: the same view from partway down the building -------------------------------------
	# Teleported OUTSIDE the footprint so the eye is outside the skirt, the way a fall off the edge leaves you.
	for drop in [40.0, 160.0]:
		var air := stand + Vector3(outward.x, 0.0, outward.y) * 6.0
		air.y = stand.y - drop
		_player.global_position = air
		_player.velocity = Vector3.ZERO
		_player.head.rotation_degrees.x = -20.0
		await _frames(3)
		await _grab("05_falling_%dm" % int(drop), 2)

	for i in _frames_img.size():
		var p := _dir.path_join("%02d_%s.png" % [i, _frames_tag[i]])
		_frames_img[i].save_png(ProjectSettings.globalize_path(p))
	print("QA_DONE ", ProjectSettings.globalize_path(_dir), " frames=", _frames_img.size())
	get_tree().quit(0)

## Eye position + aim + the haze reach, per grabbed frame: the illusion is "nothing is visible more than
## `haze_full` metres below my eye", so the eye's height is the number every judgement is made against.
func _log(tag: String) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or _void_node == null:
		return
	var eye := cam.global_position
	var haze_full: float = _void_node.get(&"haze_full")
	var roof_y: float = _void_node.get(&"last_roof_y")
	print("QA_VIEW %-20s eye=(%.1f, %.1f, %.1f) pitch=%.0f haze_total_at_y=%.1f roof_y=%.2f" % [
		tag, eye.x, eye.y, eye.z, cam.global_rotation_degrees.x, eye.y - haze_full, roof_y])

static func _vertex_count(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n

static func _rect_of(loop: PackedVector2Array) -> Rect2:
	if loop.is_empty():
		return Rect2()
	var r := Rect2(loop[0], Vector2.ZERO)
	for p in loop:
		r = r.expand(p)
	return r

## [midpoint, outward unit normal] of the footprint's longest edge — the most open stretch of parapet, and so
## the best place to stand to judge the drop. The loop is wound CCW by the component, so the outward normal of
## edge a->b is its direction rotated -90°.
static func _longest_edge(loop: PackedVector2Array) -> Array:
	var best := 0.0
	var mid := Vector2.ZERO
	var outward := Vector2(0.0, 1.0)
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		var length := (b - a).length()
		if length > best:
			best = length
			mid = (a + b) * 0.5
			var dir := (b - a) / length
			outward = Vector2(dir.y, -dir.x)
	return [mid, outward]

func _grab(tag: String, n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		_frames_img.append(get_viewport().get_texture().get_image())
		_frames_tag.append(tag)
		_log(tag)

## The last point with solid floor under it on the way from `from` to `toward` (2 m steps, a 40 m down-cast per
## step), lifted 1 m so the player lands rather than clips. Falls back to `from` when the very first step is
## already over air.
func _walk_to_edge(from: Vector3, toward: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var flat := Vector3(toward.x - from.x, 0.0, toward.z - from.z)
	var total := flat.length()
	if total < 2.0 or space == null:
		return from
	var dir := flat / total
	var last := from
	var walked := 2.0
	while walked <= total:
		var at := from + dir * walked
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 4.0, 0.0), at + Vector3(0.0, -36.0, 0.0))
		var self_rid: RID = _player.get_rid()
		q.exclude = [self_rid]
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			break
		last = (hit.position as Vector3) + Vector3(0.0, 1.0, 0.0)
		walked += 2.0
	return last

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
