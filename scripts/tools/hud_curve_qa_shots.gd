extends Node
## HUD-curve QA screenshot harness — boots the real game and photographs the instrument panel at a sweep of
## bend strengths, so the curved-glass pass can be judged by EYE. No unit test in this suite can see a curve:
## --headless never compiles a .gdshader at all, so a broken hud_curve.gdshader load()s clean and passes
## everything, and even a CORRECT one has no assertable output. This is the only honest verification.
##
## It also proves the three STRUCTURAL claims the curve rests on, printed as QA_STRUCT lines:
##   1. the carrier really moves inside the SubViewport when the bend is on, and really comes back out at 0
##      (OFF is the old tree, not an identity pass);
##   2. the SubViewport tracks the live canvas rather than a hardcoded 792x444;
##   3. hide_hud_for_death() still takes the panel down as ONE unit through the composite — the sweep walks
##      direct CanvasItem children, and a SubViewport is not one.
##
## Run from the project root as a REAL WINDOWED RUN — not --headless, the GPU must render:
##   godot --path . res://scripts/tools/hud_curve_qa_shots.tscn -- --shots-dir="C:/some/dir"
## Without --shots-dir it writes to user://hud_curve_qa_shots. Prints one QA_SHOT per capture (~25s).
##
## Driver-copy pattern, copied from minimap_qa_shots.gd: this scene is the boot scene, but the run switches
## current_scene to game.tscn (which frees the current scene), so _ready re-attaches a COPY of this script on
## a bare Node parented to root, which survives the change and drives the run.
##
## (*) NEVER call a Settings.set_* here: those setters call save_settings() and would rewrite the developer's
## real user://settings.cfg. The plain var is assigned directly instead (ui.gd polls it live), and the
## authored amount is pushed onto the in-memory HudSettings, which is never written back to disk.

var _dir := "user://hud_curve_qa_shots"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "HudCurveQaDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	# Windowed rather than the project's exclusive fullscreen so the run does not take over the desktop.
	# 1280x720 is 16:9, so the canvas is the true 792x444.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _frames(5)

	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(120)   # the level settles, the player spawns, the HUD builds, the navmesh bakes
	var ui := _find_ui()
	if ui == null:
		print("QA_FAIL no UI layer in the tree")
		get_tree().quit(1)
		return
	print("QA_CANVAS=", get_viewport().get_visible_rect().size)

	# --- control: the bend OFF. This shot is the pre-curve HUD, and every later shot is read against it ---
	await _set_curve(ui, 0.0, 1.0, 0.12, 0.0)
	print("QA_STRUCT off  ", _struct(ui))
	await _shot("01_curve_off_control")

	# --- the shipped look, then the range either side of it, all CYLINDRICAL (axis_ratio 0) ---
	await _set_curve(ui, 0.08, 0.0, 0.12, 0.0)
	print("QA_STRUCT ship ", _struct(ui))
	await _shot("02_curve_shipped_0080_cylinder")

	await _set_curve(ui, 0.05, 0.0, 0.12, 0.0)
	await _shot("03_curve_0050_cylinder_subtle")

	await _set_curve(ui, 0.14, 0.0, 0.12, 0.0)
	await _shot("04_curve_0140_cylinder_strong")

	# --- the shape knob: 1 = spherical, both axes bowing (the eye/fishbowl read) ---
	await _set_curve(ui, 0.08, 1.0, 0.12, 0.0)
	await _shot("05_curve_0080_spherical")

	# --- the trimmings, at a strength where they are legible ---
	await _set_curve(ui, 0.06, 1.0, 0.45, 0.0)
	await _shot("06_edge_fade_heavy")

	await _set_curve(ui, 0.06, 1.0, 0.12, 0.35)
	await _shot("07_chroma_fringe")

	# --- back to shipped, then prove the death sweep still takes the panel down through the composite ---
	await _set_curve(ui, 0.08, 0.0, 0.12, 0.0)
	ui.hide_hud_for_death()
	await _frames(4)
	print("QA_STRUCT dead ", _struct(ui))
	await _shot("08_death_sweep_panel_down")
	ui.restore_hud_after_death()
	await _frames(4)
	print("QA_STRUCT back ", _struct(ui))
	await _shot("09_death_sweep_restored")

	# --- and prove OFF really is the old tree: the carrier back on the layer, no viewport left behind ---
	await _set_curve(ui, 0.0, 1.0, 0.12, 0.0)
	print("QA_STRUCT torn ", _struct(ui))
	await _shot("10_curve_off_after_teardown")

	print("QA_DONE")
	get_tree().quit(0)


## Push one curve configuration and let it reach the screen. The apply and the capture are deliberately
## SPLIT ACROSS FRAMES: a uniform written this frame is not on screen until the next, and a probe that shoots
## in the same frame silently captures the PREVIOUS variant — the failure where every image in the set looks
## right but is labelled one row off.
func _set_curve(ui: Node, amount: float, ratio: float, fade: float, chroma: float) -> void:
	GameSettings.hud.hud_curve_amount = amount
	GameSettings.hud.hud_curve_axis_ratio = ratio
	GameSettings.hud.hud_curve_edge_fade = fade
	GameSettings.hud.hud_curve_chroma = chroma
	Settings.hud_curve_scale = 1.0   # the plain var, NOT set_hud_curve_scale — see the header
	await _frames(6)


## The three structural claims, as one greppable line.
func _struct(ui: Node) -> String:
	var carrier: Node = ui.get(&"_weighted")
	var sv: Node = ui.get(&"_curve_viewport")
	var rect: Node = ui.get(&"_curve_rect")
	var parent := "<null>"
	if carrier != null and is_instance_valid(carrier) and carrier.get_parent() != null:
		parent = carrier.get_parent().get_class() + ":" + String(carrier.get_parent().name)
	var sv_size := "-"
	if sv != null and is_instance_valid(sv):
		sv_size = str((sv as SubViewport).size)
	var vis := "-"
	if rect != null and is_instance_valid(rect):
		vis = str((rect as CanvasItem).visible)
	return "carrier_parent=%s viewport=%s composite_visible=%s canvas=%s" % [
		parent, sv_size, vis, str(get_viewport().get_visible_rect().size)]


## The player's HUD layer, wherever it hangs.
func _find_ui() -> Node:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_script() != null and String(n.get_script().resource_path) == "res://scripts/ui/ui.gd":
			return n
		stack.append_array(n.get_children())
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path)
