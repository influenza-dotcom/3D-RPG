extends Node
## NOISE RING QA screenshot harness — the visual half of tests/test_minimap_noise.gd. Those tests prove the
## maths and the idle gate off-tree; none of them can tell you whether the ring is LEGIBLE at 108 px, whether
## it sits under the markers, or what a 28 m gunshot actually looks like against a 54 px half-box.
##
## It drives the SHIPPED path end to end rather than poking the widget: it sets the Player's own
## noise_gunfire_radius and re-arms NoiseEmitter.gunfire() every frame, so the radius travels
## NoiseEmitter -> player.noise_radius -> Minimap._sample_noise_radius -> the snap -> the arc, exactly as in play.
##
## Run from the project root as a REAL WINDOWED RUN — not --headless, the GPU must render:
##   godot --path . res://scripts/tools/noise_ring_qa_shots.tscn -- --shots-dir="C:/some/dir"
##
## Driver-copy pattern, copied verbatim from minimap_qa_shots.gd — see that file's header for why.

var _dir := "user://qa_shots"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "NoiseRingQaDriver"
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
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _frames(5)

	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(90)
	var map := _find_minimap()
	var player := _find_player()
	if map == null or player == null:
		print("QA_FAIL map=", map, " player=", player)
		get_tree().quit(1)
		return
	print("QA_MAP rect=", map.get_global_rect(), " decks=", map.deck_count())
	print("QA_RING ring_noise=", map.ring_noise, " row=", Settings.minimap_show_noise,
			" ppm=", FloorplanSection.px_per_metre(map.size, map.effective_world_span(), map.effective_zoom()))

	# 00: silence. The ring must be ABSENT, not a dot — that is the read the whole design leans on.
	await _hold_noise(player, 0.0, 4)
	print("QA_SILENT noise_r=", map._noise_r, " (expect exactly 0.0)")
	await _crop("00_noise_silent", map)

	# The shipped ladder: walk, run, and the gunshot that overflows the box.
	for step in [
			{"n": "01_noise_walk_4m", "r": 4.0},
			{"n": "02_noise_run_6m", "r": 6.0},
			{"n": "03_noise_mid_14m", "r": 14.0},
			{"n": "04_noise_gunshot_28m", "r": 28.0}]:
		await _hold_noise(player, float(step["r"]), 4)
		print("QA_RING ", step["n"], " asked=", step["r"], " sampled=", map._noise_r)
		await _crop(str(step["n"]), map)

	# The DEV layer over the same frame — every live Groups.NOISE source, with radii and emitter names.
	map.debug_noise = true
	await _hold_noise(player, 18.0, 4)
	print("QA_DEV sources=", get_tree().get_nodes_in_group(Groups.NOISE).size())
	await _crop("05_noise_dev_layer", map)
	map.debug_noise = false

	# And the player's Options row: OFF must clear the ring from a canvas that is currently showing one.
	Settings.minimap_show_noise = false
	await _hold_noise(player, 28.0, 4)
	print("QA_ROW_OFF sampled=", map._noise_r, " (expect exactly 0.0)")
	await _crop("06_noise_row_off", map)
	Settings.minimap_show_noise = true

	print("QA_DONE")
	get_tree().quit(0)


## Pin the player's noise at `metres` for `n` frames by re-arming the gunfire spike every frame — NoiseEmitter
## decays it at noise_gunfire_decay m/s, so a single call would have faded before the capture.
func _hold_noise(player: Node, metres: float, n: int) -> void:
	player.set(&"noise_gunfire_radius", metres)
	for i in n:
		if metres > 0.0:
			player._noise.gunfire()
		else:
			player._noise._gunfire_noise = 0.0
		await get_tree().process_frame


func _find_minimap() -> Node:
	return _find_by_script("res://scripts/ui/minimap.gd")


func _find_player() -> Node:
	return Groups.human_player(get_tree())


func _find_by_script(path: String) -> Node:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_script() != null and String(n.get_script().resource_path) == path:
			return n
		stack.append_array(n.get_children())
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _crop(name: String, map: Node) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var canvas: Vector2 = get_viewport().get_visible_rect().size
	var px := Vector2(img.get_width(), img.get_height()) / canvas
	var r: Rect2 = (map as Control).get_global_rect().grow(6.0)
	var cut := Rect2i(Vector2i(r.position * px), Vector2i(r.size * px))
	cut = cut.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if cut.size.x <= 0 or cut.size.y <= 0:
		print("QA_SHOT_FAIL empty crop for ", name)
		return
	var sub := img.get_region(cut)
	sub.resize(sub.get_width() * 4, sub.get_height() * 4, Image.INTERPOLATE_NEAREST)
	var path := _dir.path_join(name + ".png")
	var err := sub.save_png(ProjectSettings.globalize_path(path))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path)
