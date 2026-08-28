extends Node
## THROWAWAY windowed probe for the 2026-08-27 outline migration: does the FIRST-PERSON WEAPON actually
## wear InkOutline's ring now that its inverted hull is deleted?
##
## Nothing headless can answer that. `--headless` never compiles a .gdshader, the ring needs the whole ink
## pass (a camera plus two SubViewports), and the view model renders through ViewModelCamera's OWN
## SubViewport composited on the HUD layer — so the only honest check is a real windowed frame with the
## weapon DRAWN. The player boots holstered, hence the Attack.set_holstered(false) below.
##
## It also prints the tint-duplicate census under the GunMesh subtree, because the two failure modes look
## identical in a dark screenshot: "no duplicates" (the dress pass missed) and "duplicates but no ring"
## (a projection or LUT problem). Counting them separates those in one run.
##
## Run from the project root, NOT headless:
##   godot --path . res://scripts/tools/__viewmodel_ring_shot.tscn -- --shots-dir="C:/some/dir"
##
## The presentation_qa_shots.gd driver-copy pattern: this scene is the boot scene, but the run switches
## current_scene to game.tscn (freeing this scene), so _ready re-attaches a COPY of this script on a bare
## Node under root, which survives the change and drives the run.

var _dir := "user://viewmodel_ring_shot"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "ViewModelRingDriver"
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
	get_window().borderless = true
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(Vector2i.ZERO)
	await _frames(5)

	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(120)  # level load + the deferred mask/tint viewport build + shader compiles

	var player := _find_by_script("res://scripts/player/player.gd") as Node3D
	if player == null:
		print("VM_RING no player")
		get_tree().quit(1)
		return

	# Draw the weapon (the player boots holstered — see holster-deescalation / begins-holstered).
	var attack := _find_child_by_script(player, "res://scripts/combat/attack.gd")
	if attack != null and attack.has_method(&"set_holstered"):
		attack.call(&"set_holstered", false)
	await _frames(90)  # the draw tween + a few frames of the ink pass pushing uniforms

	var gun := _find_by_script("res://scripts/effects/gun_mesh.gd") as Node3D
	if gun != null:
		var meshes := 0
		var dups := 0
		var ids: Array[float] = []
		var stack: Array[Node] = [gun]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			var mi := n as MeshInstance3D
			if mi != null:
				if mi.has_meta(&"npc_tint_dup"):
					dups += 1
					var v: Variant = mi.get_meta(&"npc_tint_base", -1.0)
					ids.append(float(v))
				else:
					meshes += 1
			for c in n.get_children():
				stack.append(c)
		print("VM_RING gun meshes=", meshes, " tint_dups=", dups, " ids=", ids)
	else:
		print("VM_RING no GunMesh")

	var vm := _find_by_script("res://scripts/camera/view_model_camera.gd")
	if vm != null:
		print("VM_RING view_model_camera enabled=", vm.get(&"enabled"), " fov_offset=", vm.get(&"fov_offset"))

	var ink := _find_by_script("res://scripts/effects/ink_outline.gd")
	if ink != null and ink.has_method(&"ring_enabled"):
		print("VM_RING ink ring_enabled=", ink.call(&"ring_enabled"),
			" highlight_width_px=", ink.get(&"highlight_width_px"),
			" visible=", ink.get(&"visible"))

	await _shot("viewmodel_drawn")

	# ⭐ THE SHOT THAT ACTUALLY PROVES IT. The shipped view-model ring is BLACK on a night level's 3-20/255
	# walls, which is undetectable by eye and by differencing alike (the round-8 lesson: the flicker probe
	# had to switch the ink to GREEN to measure anything). Re-shoot with the view-model LUT slot forced to
	# MAGENTA and the weapon's silhouette either lights up or the stamp is not reaching the frame. Session
	# state on a runtime node, restored below — nothing authored is touched.
	if ink != null:
		var was: Variant = ink.get(&"highlight_view_model")
		ink.set(&"highlight_view_model", Color(1.0, 0.0, 1.0))
		await _frames(6)  # InkOutline pushes uniforms from its OWN _process: set, WAIT, then shoot
		await _shot("viewmodel_drawn_magenta")
		ink.set(&"highlight_view_model", was)
	print("VM_RING DONE")
	get_tree().quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_dir, name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("VM_RING SHOT ", path, " ", img.get_size())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find_by_script(path: String) -> Node:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var s: Variant = n.get_script()
		if s != null and String(s.get(&"resource_path")) == path:
			return n
		for c in n.get_children():
			stack.append(c)
	return null


func _find_child_by_script(root: Node, path: String) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var s: Variant = n.get_script()
		if s != null and String(s.get(&"resource_path")) == path:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
