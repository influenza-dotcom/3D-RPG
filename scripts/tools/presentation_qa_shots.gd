extends Node
## Presentation QA screenshot harness — boots the real game and photographs the SAME view in both presentation
## modes (RETRO and HIGH FIDELITY), so the native-resolution split can be judged by EYE and by the PNG sizes
## themselves: a RETRO shot is the ~792x444 canvas, a HIGH FIDELITY shot is the native window resolution. No
## unit test can see any of this — --headless never compiles a .gdshader and has no real render target — so
## this windowed run is the only honest verification (the muzzle-smoke lesson).
##
## It also prints greppable QA_* structural lines per mode:
##   QA_CANVAS    — get_visible_rect().size: must stay the LOGICAL ~792x444 in BOTH modes (the size-2d
##                  override working is the whole design; if this goes native, every menu breaks).
##   QA_RENDER    — Settings.render_size() + native_scale(): canvas/1.0 in RETRO, window-size/~1.62 (720p)
##                  in HIGH FIDELITY.
##   QA_BUFFERS   — the screen-matching offscreen buffers (HUD-curve viewport, HUD ghost accumulator, world
##                  ghost accumulator, view-model gun viewport, ink mask viewport): each must track
##                  render_size() (x its own fraction), not a stale 792x444.
##
## Run from the project root as a REAL WINDOWED RUN — not --headless, the GPU must render:
##   godot --path . res://scripts/tools/presentation_qa_shots.tscn -- --shots-dir="C:/some/dir"
## Without --shots-dir it writes to user://presentation_qa_shots.
##
## Driver-copy pattern, copied from hud_curve_qa_shots.gd: this scene is the boot scene, but the run switches
## current_scene to game.tscn (which frees the current scene), so _ready re-attaches a COPY of this script on
## a bare Node parented to root, which survives the change and drives the run.
##
## (*) NEVER call a Settings.set_* here: those setters call save_settings() and would rewrite the developer's
## real user://settings.cfg. The plain vars are assigned directly and the two Window properties apply_video
## would touch are written by hand — apply_video itself is avoided because it would also re-assert the SAVED
## window mode (fullscreen on most dev machines) over this harness's windowed placement.

var _dir := "user://presentation_qa_shots"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "PresentationQaDriver"
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
	# 1920x1080 BORDERLESS (the needs_borderless placement rule) to match the user's real presentation:
	# the RETRO canvas is the true 792x444 and HIGH FIDELITY renders the full native 1920x1080, so the
	# measured native_scale is the shipped ~2.42, not a window-sized stand-in.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().borderless = true
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(Vector2i.ZERO)
	await _frames(5)

	# Freeze the cosmetic FOV animation (breathing/kicks) for the whole run: the alignment measurement
	# diffs two frames a few frames apart, and a fov easing between them zooms the entire scene into the
	# diff (measured: n exploded to 4000+ and the centroid bounced run to run). Plain var, never set_*.
	Settings.fov_effects_enabled = false
	Settings.view_bob_enabled = false

	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(120)   # the level settles, the player spawns, the HUD builds, the navmesh bakes

	# --- RETRO first: the control. Everything here must be pixel-for-pixel the pre-feature game. ---
	_pin_mode(Settings.PRESENTATION_RETRO, 2.0)
	await _frames(20)    # every native_scale()/render_size() consumer polls per frame; give the flip a beat
	_report("retro")
	await _shot("01_retro_world_hud")
	await _marker_shot("retro")

	# --- HIGH FIDELITY: the new shipped default. Same scene, native render target. ---
	_pin_mode(Settings.PRESENTATION_HIGH_FIDELITY, 1.0)
	await _frames(20)
	_report("hifi")
	await _shot("02_hifi_world_hud")
	await _marker_shot("hifi")
	await _approach_npc_shots("hifi")
	await _prop_ring_shots("hifi")

	# --- and BACK to retro: proves the mid-session toggle is symmetric (buffers re-shrink, no smear). ---
	_pin_mode(Settings.PRESENTATION_RETRO, 2.0)
	await _frames(20)
	_report("retro2")
	await _shot("03_retro_again_world_hud")

	print("QA_DONE")
	get_tree().quit(0)


## Pin one presentation configuration WITHOUT persisting it (see the header (*) rule): plain vars for the
## consumers that poll Settings, plus the two Window properties apply_video would write for this state.
func _pin_mode(mode: int, scale: float) -> void:
	Settings.presentation = mode
	Settings.render_scale = scale
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if mode == Settings.PRESENTATION_HIGH_FIDELITY else Window.CONTENT_SCALE_MODE_VIEWPORT
	win.scaling_3d_scale = scale


## The structural claims, as greppable lines. Buffer reads are duck-typed and tolerant — a missing field
## prints "-" rather than failing the run, so this harness survives refactors of the effect internals.
func _report(tag: String) -> void:
	print("QA_CANVAS ", tag, " ", get_viewport().get_visible_rect().size)
	print("QA_RENDER ", tag, " size=", Settings.render_size(), " native_scale=%.4f" % Settings.native_scale())
	var ui := _find_by_script("res://scripts/ui/ui.gd")
	var buffers := "curve=%s hud_ghost=%s world_ghost=%s gun=%s ink_mask=%s" % [
		_viewport_size_of(ui, [&"_curve_viewport"]),
		_viewport_size_of(_find_by_script("res://scripts/ui/hud_ghost.gd"), [&"_accum", &"_viewport"]),
		_viewport_size_of(_find_by_script("res://scripts/effects/world_ghost.gd"), [&"_accum", &"_viewport"]),
		_viewport_size_of(_find_by_script("res://scripts/camera/view_model_camera.gd"), [&"_sub_viewport"]),
		_viewport_size_of(_find_by_script("res://scripts/effects/ink_outline.gd"), [&"_mask_viewport", &"_mask_vp"]),
	]
	print("QA_BUFFERS ", tag, " ", buffers)
	# Deep probes for the two buffers with history: WHO world_ghost's host viewport actually is, and the
	# gun container's live geometry (the stretch-off feedback lesson).
	var wg := _find_by_script("res://scripts/effects/world_ghost.gd")
	if wg != null:
		var h: Node = wg.get(&"_host")
		if h != null and h.is_inside_tree():
			var v := h.get_viewport()
			print("QA_WG ", tag, " host=", h.get_path(), " vp=", v.get_class(), ":", v.name,
				" vptex=", v.get_texture().get_size())
	var vm := _find_by_script("res://scripts/camera/view_model_camera.gd")
	if vm != null:
		var c: Control = vm.get(&"_container")
		if c != null and is_instance_valid(c):
			print("QA_GUN ", tag, " stretch=", c.stretch, " anchor_r=", c.anchor_right,
				" size=", c.size, " scale=", c.scale, " gun_cam=", vm.get(&"_gun_camera") != null)
	_report_npcs(tag)


## Every on-screen NPC's distance + logical screen position, so the full-frame shots can be cropped at
## real enemy silhouettes — the surface the actor-outline QA actually cares about.
func _report_npcs(tag: String) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var canvas := get_viewport().get_visible_rect().size
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is Node3D) or n.get_script() == null:
			continue
		if not String(n.get_script().resource_path).ends_with("/npc.gd"):
			continue
		var wp: Vector3 = (n as Node3D).global_position + Vector3.UP * 1.2
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		if sp.x < 0.0 or sp.y < 0.0 or sp.x >= canvas.x or sp.y >= canvas.y:
			continue
		print("QA_NPC ", tag, " ", n.name, " d=%.1f" % cam.global_position.distance_to(wp), " sp=", sp)


## GROUND-TRUTH SCREEN-ANNOTATION ALIGNMENT: park a bright unshaded box ~30 m ahead of the camera
## (slightly off-centre so radial/aspect errors show) and feed a full-charge sniper glint AT ITS CENTRE
## — in the shot the flare must sit ON the box in BOTH modes; any gap IS the unproject-vs-render
## misalignment for every screen-space world annotation (sniper glints, compass markers). no_depth_test
## keeps the box visible through level geometry, so the test works from any spawn view.
func _marker_shot(tag: String) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		print("QA_MARK ", tag, " no-camera")
		return
	# h_offset/v_offset are prime suspects for any constant gap: the renderer applies them to the
	# projection but Camera3D.unproject_position does NOT (it rebuilds a bare perspective from
	# fov + visible-rect aspect) — print everything projection-affecting beside the measurements.
	print("QA_CAM ", tag, " fov=", cam.fov, " keep=", cam.keep_aspect, " h_off=", cam.h_offset,
		" v_off=", cam.v_offset, " proj=", cam.projection, " class=", cam.get_class())
	# TWO measurement points: A near the screen centre, B well off-centre — a radial error source
	# (aspect mismatch, the lens barrel) grows with eccentricity and only B can reveal it. Close and
	# BIG (1 m at 12 m) so the cluster survives fov 120 + the quantise/dither post (a 0.6 m box at
	# 30 m was ~3 px and the strict magenta filter starved).
	var offsets: Array[Vector3] = [Vector3(1.5, 0.8, -12.0), Vector3(6.0, 3.0, -12.0)]
	var names: Array[String] = ["centre", "edge"]
	for i in offsets.size():
		var world_pos: Vector3 = cam.global_position + cam.global_transform.basis * offsets[i]
		var box := MeshInstance3D.new()
		# SPHERE, shadows OFF: a cube's visible side faces + its cast shadow both drag the diff centroid
		# off the projected centre (a measured ~10 px bias); a sphere's silhouette centroid IS the centre.
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.albedo_color = Color(1.0, 0.05, 1.0)
		mesh.material = mat
		box.mesh = mesh
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_tree().current_scene.add_child(box)
		box.global_position = world_pos
		# Measure TWICE: with the player's live lens warp, then with it pinned OFF — the pair attributes
		# how much of any gap is the barrel warp displacing the picture vs a true projection mismatch.
		var lens0: float = Settings.lens_curve
		for lens_off in [false, true]:
			Settings.lens_curve = 0.0 if lens_off else lens0
			box.visible = true
			await _frames(3)
			await RenderingServer.frame_post_draw
			var img_on: Image = get_viewport().get_texture().get_image()
			var canvas := get_viewport().get_visible_rect().size
			var expected_logical := cam.unproject_position(world_pos)
			var rsz := Vector2(Settings.render_size())
			var expected_native := expected_logical * rsz / canvas
			# DIFFERENTIAL detection — the palette defeated colour filters twice (the night world is full
			# of violets AND the scaffold art is hot pink): capture with the box, hide it, capture again;
			# the strongly-changed pixels ARE the box. The window is barely bigger than the sphere itself
			# so a wandering NPC or an animated fog bank a few metres over can't drag the centroid.
			box.visible = false
			await _frames(2)
			await RenderingServer.frame_post_draw
			var img_off: Image = get_viewport().get_texture().get_image()
			var half := int(ceil(30.0 * rsz.x / canvas.x))
			var found := _diff_centroid(img_on, img_off, expected_native, half)
			if not lens_off:
				img_on.save_png(ProjectSettings.globalize_path(_dir.path_join("probe_%s_%s.png" % [tag, names[i]])))
			var lens_tag := "lens0" if lens_off else "lens"
			if found.x >= 0.0:
				var delta_logical := (found - expected_native) * canvas / rsz
				# The annotation fix under test: CameraSettings.lens_display_point must map the raw
				# unprojection onto the box's DISPLAYED position — warp_delta is the residual after the
				# map and must be ~sub-pixel with the lens on (and identical to delta with it off).
				var k: float = GameSettings.camera.lens_barrel_amount * clampf(Settings.lens_curve, 0.0, 1.0)
				var warped_native := CameraSettings.lens_display_point(expected_logical, canvas, rsz.x / rsz.y, k) * rsz / canvas
				var warp_delta := (found - warped_native) * canvas / rsz
				print("QA_MARK ", tag, " ", names[i], " ", lens_tag, " expected_native=", expected_native,
					" box_native=", found, " delta_logical=", delta_logical, " warp_delta=", warp_delta)
			else:
				print("QA_MARK ", tag, " ", names[i], " ", lens_tag, " expected_native=", expected_native,
					" box_native=NOT FOUND")
		Settings.lens_curve = lens0
		box.queue_free()
		await _frames(2)


## Centroid of the pixels that CHANGED strongly between the box-visible and box-hidden captures, within
## +/-`half` px of `around` (render px), or (-1,-1) if none. Colour-blind on purpose: two colour filters
## in a row were defeated by this game's own palette (violet night sky, hot-pink scaffold art) — a diff
## can only be polluted by something that MOVED between the two frames, and the idle camera is static.
func _diff_centroid(img_on: Image, img_off: Image, around: Vector2, half: int) -> Vector2:
	var x0 := maxi(int(around.x) - half, 0)
	var y0 := maxi(int(around.y) - half, 0)
	var x1 := mini(int(around.x) + half, img_on.get_width() - 1)
	var y1 := mini(int(around.y) + half, img_on.get_height() - 1)
	var sum := Vector2.ZERO
	var n := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var a := img_on.get_pixel(x, y)
			var b := img_off.get_pixel(x, y)
			# 0.35 total-channel threshold: the full-bright box against the dark night scene clears it
			# easily; animated fog wisps and dither shimmer stay under it.
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.35:
				sum += Vector2(x, y)
				n += 1
	if n == 0:
		return Vector2(-1.0, -1.0)
	print("QA_MARK_N ", n)  # changed-pixel count — should be roughly the box's on-screen area
	return sum / float(n)


## ENEMY OUTLINE AT COMBAT RANGES: teleport the PLAYER toward a real, level-authored NPC and photograph
## it at a ladder of distances, from hover range out past where the ring's colour bloom has faded to
## black. ⭐ Deliberately NOT a bare
## enemy.tscn spawn line-up: a raw spawn has NO body (the default body was removed — looks come from
## authored NpcData/NpcLook), so its "figure" is nothing but outline shells around invisible meshes and
## reproduces nothing a player ever sees. The player node is put back exactly afterwards.
func _approach_npc_shots(tag: String) -> void:
	var cam := get_viewport().get_camera_3d()
	var player := _find_by_script("res://scripts/player/player.gd") as Node3D
	if cam == null or player == null:
		return
	# The farthest clearly on-screen NPC from the spawn view (the 45 m one in the QA_NPC report).
	var target: Node3D = null
	var best := 0.0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Node3D and n.get_script() != null and String(n.get_script().resource_path).ends_with("/npc.gd"):
			var wp: Vector3 = (n as Node3D).global_position
			if not cam.is_position_behind(wp + Vector3.UP * 1.2):
				var d := cam.global_position.distance_to(wp)
				if d > best and d < 60.0:
					best = d
					target = n as Node3D
	if target == null:
		print("QA_APPROACH ", tag, " no on-screen npc")
		return
	var home := player.global_position
	for dist in [28.0, 20.0, 13.0]:
		# The FIRST stop (28 m) shoots the NPC in its authored NEUTRAL attitude — the id-4 BLACK ring —
		# then the target is flipped HOSTILE (the debug `attitude` command's idiom) for the closer stops
		# so the red ring is on record too. miss_chance 1.0 keeps the angry NPC from killing the probe.
		if dist < 28.0 and int(target.get(&"disposition_overrides_faction")) == 0:
			target.set(&"disposition", Disposition.Kind.HOSTILE)
			target.set(&"disposition_overrides_faction", true)
			target.set(&"miss_chance", 1.0)
			if target.has_method(&"_apply_outline"):
				target.call(&"_apply_outline")
		var to_p := home - target.global_position
		to_p.y = 0.0
		player.global_position = target.global_position + to_p.normalized() * dist + Vector3.UP * 0.1
		await _frames(12)  # physics grounds the player; the NPC may notice — a live pose is fine, this is the real game
		var head := cam.unproject_position(target.global_position + Vector3.UP * 1.4)
		print("QA_APPROACH ", tag, " d=%.1f" % cam.global_position.distance_to(target.global_position),
			" sp=", head)
		await _shot("approach_%s_d%d" % [tag, int(dist)])
	# DISCRIMINATORS at the last (13 m) stop — the range where the solid-red body reproduces:
	#  noink — the ink SLIDER zeroed. ⭐ Since 2026-08-27 this no longer hides the whole pass: the RING is
	#  deliberately independent of the slider (it is the game's only outline now), so what this isolates is
	#  the WORLD's edge detect alone. Red that survives is the ring or the body's own art, not the ink.
	var ink0: float = Settings.ink_outline_intensity
	Settings.ink_outline_intensity = 0.0
	await _frames(4)
	await _shot("approach_%s_noink" % tag)
	Settings.ink_outline_intensity = ink0
	#  noverlay — the NPC's material_overlay chain stashed off. That used to carry the disposition RIM
	#  chained in front of the damage flash; since the hull's deletion it is the flash alone, so this now
	#  isolates the body's own art from the flash rather than from an outline. The outline lives on the
	#  tint DUPLICATE, which this deliberately does not touch — use __viewmodel_ring_shot.gd's magenta-LUT
	#  idiom if you need to isolate the ring itself. Restored afterwards so the level NPC keeps its overlays.
	var stashed: Array = []
	for m in TalkHelpers.collect_meshes(target, null, true):
		stashed.append([m, m.material_overlay])
		m.material_overlay = null
	await _frames(4)
	await _shot("approach_%s_norim" % tag)
	for pair in stashed:
		if is_instance_valid(pair[0]):
			(pair[0] as MeshInstance3D).material_overlay = pair[1]
	#  material dump — the solid-red-body hypothesis: a body mesh in the TRANSPARENT queue writes no depth,
	#  so the cull_front shell's interior is never occluded and the rim paints the whole figure. Print each
	#  mesh's transparency + material class/mode so the queue placement is a fact, not a guess.
	for m in TalkHelpers.collect_meshes(target, null, true):
		var mat := m.get_active_material(0)
		# ⭐Three distinct verdicts, because the first two were once conflated into one misdiagnosis: a
		# MeshInstance3D with NO mesh renders NOTHING (it cannot be the white thing in a shot — the white
		# "cone" over a spotted NPC is the "!" alert popup, NPC.POPUP_EXCLAMATION, a designed cue this
		# harness triggers by teleporting the player into the NPC's face), while a real mesh whose
		# active material is null genuinely paints the engine-default white.
		var desc := "<no mesh: renders nothing>"
		if m.mesh != null:
			desc = "<NULL MATERIAL: engine-default white>"
			if mat is BaseMaterial3D:
				desc = "%s transp=%d" % [mat.get_class(), (mat as BaseMaterial3D).transparency]
			elif mat is ShaderMaterial:
				var sh := (mat as ShaderMaterial).shader
				desc = "ShaderMaterial:" + (sh.resource_path if sh != null else "<inline>")
		print("QA_MAT ", m.name, " gi_transp=%.3f" % m.transparency, " ", desc,
			" overlay=", m.material_overlay != null)
	#  retro control — the same 13 m view under the classic pipeline, for the "was it always like this" question.
	_pin_mode(Settings.PRESENTATION_RETRO, 2.0)
	await _frames(10)
	await _shot("approach_retro_control")
	_pin_mode(Settings.PRESENTATION_HIGH_FIDELITY, 1.0)
	await _frames(6)
	player.global_position = home
	await _frames(4)


## PROP OUTLINE: park a real Throwable at a ladder of distances and photograph it. The contract under test
## is that a prop wears exactly ONE outline at every range — the screen-space tint ring, constant pixel
## width, distance-proof. It used to be a CROSSFADE (an inverted hull close in, the ring fading in past it)
## and the ladder existed to catch a gap or a doubling in the handover band; since the hull was deleted
## (2026-08-27) the ring is unconditional and the ladder is checking something simpler and stricter — that
## the line is THERE and the same weight at 2 m and at 60 m. Getting this wrong is invisible rather than
## loud: a prop's ACTOR_INK_MASK_LAYER stamp suppresses the world ink, so a missing ring is no line at all.
## Prints the live tint id so a silent id-0 (no duplicate) can't read as a pass.
func _prop_ring_shots(tag: String) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var scene := load("res://scenes/throwable/stashable_crate.tscn") as PackedScene
	if scene == null:
		print("QA_PROP ", tag, " crate scene failed to load")
		return
	var prop := scene.instantiate() as Node3D
	if prop == null:
		return
	get_tree().current_scene.add_child(prop)
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# FREEZE it: a RigidBody3D dropped in front of the camera would tumble away between the shots.
	if prop is RigidBody3D:
		(prop as RigidBody3D).freeze = true
	for dist in [30.0, 20.0, 12.0, 3.0]:
		prop.global_position = cam.global_position + fwd * dist + Vector3.DOWN * 0.4
		await _frames(6)
		var dups := 0
		var id := -1.0
		for m in TalkHelpers.collect_meshes(prop, null, true):
			var d := m.get_node_or_null(InkOutline.TINT_DUP_NAME) as MeshInstance3D
			if d != null:
				dups += 1
				var v: Variant = d.get_instance_shader_parameter(&"disposition_id")
				id = float(v) if v != null else -1.0
		# ⭐ NO FRAME-DIFF PROOF HERE, deliberately. The rest ring is BLACK on a night scene, so a diff
		# against a ring-off capture is the only way to SEE it — but this post chain has TIME-driven film
		# grain, so two captures a few frames apart differ across the whole frame and the count is noise
		# (measured: ~16k "changed" pixels even at 3 m, where the ring is provably faded out). The
		# crossfade is pinned deterministically instead, in tests/test_ink_outline.gd, by reproducing the
		# shader's own far_gate from InkOutline.encode_actor_depth. These shots stay the by-eye record
		# that a prop wears ONE line at every range (no doubling at the crossover, no stripe bands).
		print("QA_PROP ", tag, " d=%.0f" % dist, " tint_dups=", dups, " id=%.0f" % id,
			" sp=", cam.unproject_position(prop.global_position))
		await _shot("prop_%s_d%d" % [tag, int(dist)])
	prop.queue_free()
	await _frames(2)


## First SubViewport found under `holder` at one of the candidate field names (or "-").
func _viewport_size_of(holder: Node, fields: Array) -> String:
	if holder == null:
		return "-"
	for f in fields:
		var v: Variant = holder.get(f)
		if is_instance_valid(v) and v is SubViewport:
			return str((v as SubViewport).size)
	return "-"


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


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path, " ", img.get_size())
