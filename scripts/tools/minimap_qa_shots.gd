extends Node
## Minimap QA screenshot harness — boots the real game and captures the top-right corner, so the
## authored-scene conversion can be checked against the shipped look by EYE rather than only by unit test.
## Every GUT test around this widget runs off-tree; none of them can tell you whether the box still lands in
## the corner, still clips, and still draws the plan under its markers.
##
## It also proves the ART SANDWICH end to end: pass 2 injects a magenta node into %MapUnder and a green ring
## into %MapOver, so the shots answer the one question the tests cannot — does %MapUnder really render BEHIND
## the code-drawn plan, and %MapOver really in front of the markers and the rim?
##
## Doubles as the UI-ARTIST reference pack for this widget: shot 01 is the box as shipped, at the true runtime
## canvas, ready to trace art over (upscale with NEAREST — the canvas is deliberately low-res, and a smooth
## upscale misrepresents the pixel look).
##
## Run from the project root as a REAL WINDOWED RUN — not --headless, the GPU must render:
##   godot --path . res://scripts/tools/minimap_qa_shots.tscn -- --shots-dir="C:/some/dir"
## Without --shots-dir it writes to user://qa_shots. Prints one QA_SHOT line per capture and quits (~20s).
##
## Driver-copy pattern, copied verbatim from menu_qa_shots.gd: this scene is the boot scene, but the run
## switches current_scene to game.tscn (change_scene_to_file frees the current scene), so _ready re-attaches
## a COPY of this script on a bare Node parented to root, which survives the scene change and drives.

var _dir := "user://qa_shots"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "MinimapQaDriver"
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
	print("QA_CANVAS=", get_viewport().get_visible_rect().size)

	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(90)   # the level settles, the navmesh region registers, bake_delay elapses, decks slice
	var map := _find_minimap()
	if map == null:
		print("QA_FAIL no Minimap in the HUD — ui.gd did not instance the authored scene")
		get_tree().quit(1)
		return
	# THE BODY CHANNEL IS IMPLANT-GATED NOW (Minimap._sample_scan_range): a chip-less player sees no NPC dots at
	# all, so without this every shot below would document the map with one whole channel missing. Granted at
	# runtime; the grant path emits mechanic_unlocked, which only ChipInstallScreen listens for, so this driver
	# still writes nothing to user://.
	var qa_player := Groups.human_player(get_tree())
	if qa_player != null:
		qa_player.call(&"unlock_mechanic", &"deep_scanner")
	else:
		print("QA_WARN no human player — the body-dot channel will be blank in these shots")
	print("QA_MAP rect=", map.get_global_rect(), " decks=", map.deck_count(),
			" band_floor=", map.active_band_floor())
	print("QA_MAP slots under=", map.get_node_or_null(^"%MapUnder") != null,
			" over=", map.get_node_or_null(^"%MapOver") != null,
			" preview_hidden=", not (map.get_node_or_null(^"%EditorPreview") as CanvasItem).visible)

	await _shot("01_minimap_shipped")
	await _crop("02_minimap_shipped_zoom", map)

	# --- PASS 2: the art sandwich, with stand-in art in both slots -------------------------------
	# Deliberately garish and obviously layered: a full-box magenta fill UNDER (it must be hidden by the
	# plan's own backing until that backing's alpha is zeroed, which is the documented workflow) and a green
	# ring OVER (it must sit on top of the markers and the rim).
	var under := ColorRect.new()
	under.color = Color(1.0, 0.0, 1.0, 1.0)
	under.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.get_node(^"%MapUnder").add_child(under)
	var over := _ring_rect()
	map.get_node(^"%MapOver").add_child(over)
	map.queue_redraw()
	await _frames(4)
	await _crop("03_art_over_under_backing_opaque", map)

	# Now the documented step for a backdrop: zero the ALPHA of the code-drawn backing so %MapUnder shows
	# through. Done on a COPY of the skin so the run cannot dirty the authored .tres on disk.
	var skin: Resource = MenuStyle.hud.duplicate()
	var c: Color = skin.minimap_backing_color
	c.a = 0.0
	skin.minimap_backing_color = c
	MenuStyle.set_hud_skin(skin)
	# NO explicit queue_redraw here on purpose: the map must repaint on the SKIN SWAP by itself
	# (Minimap._skin_changed, the sixth idle-gate term). If shot 04 still shows the old backing, that term
	# is broken and a standing player would never see an artist's edit.
	await _frames(4)
	await _crop("04_art_under_showing_through", map)

	# --- PASS 3: the plan RESTYLED through the skin alone, with no art at all ----------------------
	# Strip the stand-in art back off and show what the wall knobs by themselves can do: a fatter stroke
	# plus the glow pass under it. This is the shot that answers "can the artist change the WALLS", as
	# opposed to "can the artist put a picture behind them".
	under.queue_free()
	over.queue_free()
	skin.minimap_backing_color = MenuStyle.hud.minimap_backing_color  # restore the void colour
	skin.minimap_wall_color = Color(1.0, 0.45, 0.85, 1.0)
	skin.minimap_wall_width = 1.0
	skin.minimap_wall_glow_color = Color(1.0, 0.1, 0.6, 0.5)
	skin.minimap_wall_glow_width = 5.0
	skin.minimap_walkable_color = Color(0.12, 0.02, 0.10, 0.5)
	skin.minimap_caret_px = 8.0                       # the arrow, resized from the skin
	skin.minimap_station_glyph_px = 8.0
	skin.emit_changed()                               # the Remote-inspector path: no queue_redraw here either
	await _frames(4)
	await _crop("05_walls_restyled_from_the_skin", map)

	print("QA_DONE")
	get_tree().quit(0)


## The HUD's minimap, wherever ui.gd parented it (the _weighted carrier or the layer itself).
func _find_minimap() -> Node:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_script() != null and String(n.get_script().resource_path) == "res://scripts/ui/minimap.gd":
			return n
		stack.append_array(n.get_children())
	return null


## A hollow green ring the size of the box — obviously "in front" art that must not hide the plan.
func _ring_rect() -> Control:
	var r := Panel.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(0.2, 1.0, 0.2, 1.0)
	sb.set_border_width_all(3)
	r.add_theme_stylebox_override(&"panel", sb)
	return r


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path)


## The map's own corner, cut out of the frame and nearest-upscaled 4x — at 108 px on a 792-wide canvas the
## widget is a thumbnail in a full screenshot, and the whole point of these shots is to look at it closely.
func _crop(name: String, map: Node) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	# The canvas is upscaled to the window, so the widget's canvas-space rect has to be scaled to pixels.
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
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path, "  src=", cut)
