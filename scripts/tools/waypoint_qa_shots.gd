extends Node
## Waypoint QA screenshot harness — boots the real game and walks the REDESIGNED waypoint flows with REAL
## injected input where the routing itself is the question (the click, the drag-pan, the wheel), so the
## feature is judged by EYE and by the printed gesture outcomes, not only by off-tree tests. This harness is
## the reason the redesign exists: its first run proved the original click was dead and the layout broken.
##
## Run from the project root as a REAL WINDOWED RUN — not --headless, the GPU must render:
##   godot --path . res://scripts/tools/waypoint_qa_shots.tscn -- --shots-dir="C:/some/dir"
## Prints one QA_* line per step and quits.
##
## PROFILE SAFETY: arms GameState's debug save sandbox immediately, so every autosave a waypoint mutation
## queues lands in user://sandbox/ and the dev's real Continue profile is untouched. The one Settings row it
## moves (map zoom) is saved/restored around the shot, the menu_qa idiom.
##
## Driver-copy pattern, copied verbatim from minimap_qa_shots.gd.

var _dir := "user://qa_shots"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "WaypointQaDriver"
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
	GameState.enable_sandbox()
	await _frames(5)

	get_tree().change_scene_to_file("res://scenes/game.tscn")
	var player: Node = null
	for i in 600:
		await get_tree().process_frame
		player = Groups.human_player(get_tree())
		if player != null:
			break
	if player == null:
		print("QA_FAIL no player")
		get_tree().quit(1)
		return
	await _frames(60)
	var level: String = GameState.current_level_path
	GameState.clear_waypoints()
	var was_zoom: float = Settings.map_zoom

	# --- 1: the map tab must now FILL the panel -----------------------------------------------------
	MapScreen.open()
	await _frames(24)
	var map = MapScreen.get(&"_map")
	print("QA_TAB rect=", (map as Control).get_global_rect(), " decks=", map.deck_count())
	await _shot("01_map_fills_panel")

	# --- 2: a REAL click on empty plan -> the pin exists IMMEDIATELY, selected, card up --------------
	# Upper-right quadrant: the floating pin card occupies the map's bottom-LEFT once a pin is selected,
	# and a gesture aimed at the centre can land on it (it deliberately eats clicks). Round 2 proved it.
	var r := (map as Control).get_global_rect()
	var centre: Vector2 = r.get_center() + Vector2(r.size.x * 0.22, -r.size.y * 0.22)
	_click(centre + Vector2(30, -10))
	await _frames(8)
	print("QA_CLICK pins=", GameState.waypoints_for(level).size(),
			" selected=", MapScreen.get(&"_selected"),
			" card_visible=", (MapScreen.get(&"_card") as Control).visible if MapScreen.get(&"_card") != null else "n/a")
	await _shot("02_click_placed_quietly")
	# The stuck-box loop, end to end with REAL clicks: click the pin (card up) -> click empty (card GONE,
	# and NO pin minted by the dismissal).
	MapScreen._click_select(0)
	await _frames(4)
	var before_dismiss: int = GameState.waypoints_for(level).size()
	_click(centre + Vector2(-60, 20))
	await _frames(6)
	print("QA_DISMISS card_visible=", (MapScreen.get(&"_card") as Control).visible,
			" selected=", MapScreen.get(&"_selected"),
			" pins_unchanged=", GameState.waypoints_for(level).size() == before_dismiss)

	# --- 3: a REAL drag pans the view ---------------------------------------------------------------
	var off_before: Vector2 = map.view_offset
	_drag(centre, Vector2(-120, -60), 6)
	await _frames(8)
	print("QA_PAN offset_before=", off_before, " after=", map.view_offset)
	await _shot("03_dragged_view")

	# --- 4: a REAL wheel notch zooms ----------------------------------------------------------------
	var zoom_before: float = Settings.map_zoom
	_wheel(centre, zoom_before < Settings.MINIMAP_ZOOM_MAX - 0.01)  # notch INTO the clamp's open side
	await _frames(6)
	print("QA_WHEEL zoom_before=", zoom_before, " after=", Settings.map_zoom)

	# --- 5: click the pin, then click it AGAIN -> the EDIT card (first ever look at it) -------------
	# The target point comes from the widget's OWN projection (_marker_point with its live pad and
	# rim-pin decision) — a naive view*world here misses the glyph the moment a pan pushes the pin
	# off-box and the paint rim-pins it (round 3's stray 13th pin was this harness doing exactly that).
	var rec := GameState.waypoint_at(level, 0)
	if not rec.is_empty():
		var skin = MenuStyle.hud
		var q: Vector2 = map._marker_point(rec.get("pos") as Vector3, map.view_matrix(), skin,
				map.waypoint_pins_offscreen(rec), map._waypoint_pad(skin, map.waypoint_is_tracked(rec)))
		if q != Vector2.INF:
			var gq: Vector2 = q + (map as Control).get_global_rect().position
			_click(gq)   # select — and if the glyph was rim-pinned, the view FETCHES the pin (it moves!)
			await _frames(6)
			# Recompute: selection may have recentred the view, so the pin's screen point is new. Clicking
			# the OLD point would be empty plan — which now means dismiss, not edit.
			q = map._marker_point(rec.get("pos") as Vector3, map.view_matrix(), skin,
					map.waypoint_pins_offscreen(rec), map._waypoint_pad(skin, map.waypoint_is_tracked(rec)))
			_click(q + (map as Control).get_global_rect().position)   # the selected pin, clicked again = the editor
			await _frames(8)
		var prompt = MapScreen.get(&"_prompt")
		print("QA_EDIT card_open=", prompt != null and prompt.is_open())
		await _shot("04_edit_card")
		if prompt != null and prompt.is_open():
			prompt._on_cancel_pressed()
			await _frames(4)

	# --- 6: a lived-in map — icons, tints, declutter, rim pins --------------------------------------
	var here: Vector3 = (player as Node3D).global_position
	var spots: Array = [
		Vector3(6, 0, 4), Vector3(-10, 0, 8), Vector3(14, 0, -12), Vector3(-20, 0, -18),
		Vector3(9, 0, 6), Vector3(30, 0, 22), Vector3(-42, 0, 30),
		Vector3(90, 0, 60), Vector3(-120, 0, -80), Vector3(200, 0, 150), Vector3(-260, 0, 190),
	]
	for i in spots.size():
		GameState.add_waypoint(level, here + spots[i], "Pin %d" % (i + 2), "a note", i, i)
	GameState.set_tracked_waypoint(level, 3, true)
	await _frames(8)
	print("QA_TRACKED ", GameState.tracked_waypoint())
	await _shot("05_busy_map_tracked")

	Settings.set_map_zoom(was_zoom)
	MapScreen._apply_zoom()
	MapScreen.close()
	await _frames(10)

	# --- 7: gameplay — the HUD box must be CALM now (near pins + the tracked pin only) --------------
	await _shot("06_gameplay_hud")
	var hud_map := _find_hud_minimap()
	if hud_map != null:
		await _crop("07_hud_box_4x", hud_map, 4)
	# ...and the heading tape must carry the tracked pip: crop the top-centre strip.
	await _crop_rect("08_heading_tape_3x", Rect2(246, 0, 300, 40), 3)

	# --- 8: the X press — instant pin + track + toast -----------------------------------------------
	var marker = player.get(&"_waypoint_marker")
	if marker != null:
		var n_before: int = GameState.waypoints_for(level).size()
		marker._begin_mark()
		await _frames(10)
		print("QA_MARK pins_before=", n_before, " after=", GameState.waypoints_for(level).size(),
				" tracked=", GameState.tracked_waypoint())
		await _shot("09_x_marked_and_toast")
	print("QA_DONE")
	get_tree().quit(0)


func _click(canvas_pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = _to_window(canvas_pos)
		ev.global_position = ev.position
		Input.parse_input_event(ev)


## Press, several motion events (relative deltas in window px), release — a real pan gesture.
func _drag(canvas_from: Vector2, canvas_delta: Vector2, steps: int) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = _to_window(canvas_from)
	down.global_position = down.position
	Input.parse_input_event(down)
	var step := canvas_delta / float(steps)
	for i in steps:
		var mv := InputEventMouseMotion.new()
		mv.position = _to_window(canvas_from + step * float(i + 1))
		mv.global_position = mv.position
		mv.relative = _to_window(canvas_from + step) - _to_window(canvas_from)  # one step, window px
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mv)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = _to_window(canvas_from + canvas_delta)
	up.global_position = up.position
	Input.parse_input_event(up)


func _wheel(canvas_pos: Vector2, up: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.position = _to_window(canvas_pos)
	ev.global_position = ev.position
	Input.parse_input_event(ev)


func _to_window(canvas_pos: Vector2) -> Vector2:
	var canvas: Vector2 = get_viewport().get_visible_rect().size
	return canvas_pos * (Vector2(DisplayServer.window_get_size()) / canvas)


func _find_hud_minimap() -> Control:
	var tab_map = MapScreen.get(&"_map")
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n != tab_map and n.get_script() != null \
				and String(n.get_script().resource_path) == "res://scripts/ui/minimap.gd":
			return n as Control
		stack.append_array(n.get_children())
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(ProjectSettings.globalize_path(_dir.path_join(name + ".png")))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", name)


func _crop(name: String, ctl: Control, mult: int) -> void:
	await _crop_rect(name, ctl.get_global_rect().grow(6.0), mult)


func _crop_rect(name: String, r: Rect2, mult: int) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var canvas: Vector2 = get_viewport().get_visible_rect().size
	var px := Vector2(img.get_width(), img.get_height()) / canvas
	var cut := Rect2i(Vector2i(r.position * px), Vector2i(r.size * px))
	cut = cut.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if cut.size.x <= 0 or cut.size.y <= 0:
		print("QA_SHOT_FAIL empty crop ", name)
		return
	var sub := img.get_region(cut)
	sub.resize(sub.get_width() * mult, sub.get_height() * mult, Image.INTERPOLATE_NEAREST)
	var err := sub.save_png(ProjectSettings.globalize_path(_dir.path_join(name + ".png")))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", name)
