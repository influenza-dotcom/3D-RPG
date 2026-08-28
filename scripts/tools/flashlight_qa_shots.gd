extends Node
## Flashlight LOOK QA screenshot harness — boots the REAL game at night, switches the torch on, drops a
## controlled probe (a box between the beam and a wall) in front of the camera, and captures the frame. It
## answers two questions no unit test can: does the beam cast visible SHADOWS, and does its white-core /
## HP-tinted-rim GRADIENT actually render (shots 02b–02d, each with its own control).
##
## WHY: "the flashlight casts no shadows" is a LOOK bug — no unit test can see it, and the scene file already
## says `shadow_enabled = true`, so the question is what the GPU actually draws. This harness answers it by eye
## and prints the live light state (atlas size, cull mask, bias, and — the suspect — the light's offset from the
## camera) alongside each shot.
##
## Run from the project root as a REAL WINDOWED RUN — not --headless, the GPU must render:
##   godot --path . res://scripts/tools/flashlight_qa_shots.tscn -- --shots-dir="C:/some/dir"
## Without --shots-dir it writes to user://qa_shots. Prints one QA_SHOT line per capture and quits.
##
## Driver-copy pattern, copied from minimap_qa_shots.gd: this scene is the boot scene, but the run switches
## current_scene to game.tscn (change_scene_to_file frees the current scene), so _ready re-attaches a COPY of
## this script on a bare Node parented to root, which survives the scene change and drives.

var _dir := "user://qa_shots"
var _probe_wall: MeshInstance3D = null
var _probe_box: MeshInstance3D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "FlashlightQaDriver"
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
	await _frames(150)   # level loads, ps1 applier walks, nav bakes, sky title fades
	_strip_overlays()

	var player: Node3D = Groups.human_player(get_tree())
	if player == null:
		print("QA_FAIL no Player in the tree")
		get_tree().quit(1)
		return
	var torch := player.find_child("FlashLight", true, false) as SpotLight3D
	var cam := player.find_child("Camera3D", true, false) as Camera3D
	if torch == null or cam == null:
		print("QA_FAIL torch=", torch, " cam=", cam)
		get_tree().quit(1)
		return

	# Deep night, so the beam is the only thing lighting the probe.
	WorldClock.set_time_of_day(0.92)
	await _frames(10)

	var vp := get_viewport()
	print("QA_ATLAS size=", vp.positional_shadow_atlas_size,
			" q0=", vp.positional_shadow_atlas_quad_0, " q1=", vp.positional_shadow_atlas_quad_1,
			" 16bit=", vp.positional_shadow_atlas_16_bits)
	print("QA_TORCH shadow_enabled=", torch.shadow_enabled, " layers=", torch.layers,
			" bias=", torch.shadow_bias, " normal_bias=", torch.shadow_normal_bias,
			" blur=", torch.shadow_blur, " opacity=", torch.shadow_opacity,
			" range=", torch.spot_range, " angle=", torch.spot_angle, " energy=", torch.light_energy)
	print("QA_TORCH top_level=", torch.top_level, " authored_offset=", torch.transform.origin)

	# THE SUSPECT, measured: how far is the beam ORIGIN from the eye? A light sitting exactly at the camera
	# hides every shadow it casts behind the caster that casts it — geometrically, not as a bug.
	var probe_dir := -cam.global_transform.basis.z
	var eye := cam.global_position
	_place_probe(player, eye, probe_dir)
	# Pass 4 re-shoots the same staging through the shipped post-process chain, so keep the opening pose.
	var opening_pose := player.global_transform
	await _frames(4)
	print("QA_OFFSET torch_to_eye=", torch.global_position.distance_to(eye),
			" torch_pos=", torch.global_position, " eye=", eye)

	await _shot("01_night_torch_off")

	# Switch the torch on the way the game does — the private toggle, since _process re-derives `visible`.
	torch.set(&"_light_on", true)
	await _frames(20)
	print("QA_ON visible=", torch.visible, " offset_now=", torch.global_position.distance_to(eye))
	await _shot("02_night_torch_on_as_shipped")

	# --- PASS 1b: THE BEAM GRADIENT. The shipped beam is WHITE through the middle and HP-coloured at the rim
	# (flash_light.gd `beam_gradient`), and that shape is a light PROJECTOR — a radial GradientTexture2D the
	# light multiplies itself by. Nothing a unit test can read proves the GPU actually threw it: a projector that
	# failed to reach the decal atlas, or a renderer that ignored it, leaves a plain white cone with every
	# property still correct. So shoot the ramp against the probe wall, then A/B it against the flat beam it
	# replaced — if those two frames match, the projector never rendered.
	var proj: Texture2D = torch.light_projector
	print("QA_GRADIENT projector=", proj, " light_color=", torch.light_color, " size=",
			Vector2i(proj.get_width(), proj.get_height()) if proj != null else Vector2i.ZERO)
	await _shot("02b_beam_gradient_white_core_tinted_rim")

	var glow := player.get_node_or_null("PlayerEmittingLight") as Light3D
	torch.light_projector = null
	torch.light_color = glow.light_color if glow != null else Color(0.003921569, 1.0, 1.0)
	await _frames(10)
	await _shot("02c_control_flat_beam_no_projector")
	torch.light_projector = proj
	torch.light_color = Color.WHITE

	# The rim tracks the player's body glow, which is HP-driven — so drive the glow to the damaged red and the
	# ring must follow within a frame while the core stays white. (Writing the glow directly is the honest test:
	# it is exactly what Player._refresh_health_light_color does off the `damaged` signal.)
	if glow != null:
		var healthy := glow.light_color
		glow.light_color = Color(1.0, 0.05, 0.02)
		await _frames(10)
		print("QA_GRADIENT_HURT glow=", glow.light_color, " beam_core=", torch.light_color)
		await _shot("02d_gradient_rim_reddens_with_hp")
		glow.light_color = healthy
		await _frames(5)

	# CONTROL for the shipped offset: put the origin BACK on the eye and re-shoot. If 03 is the flat,
	# shadowless frame and 02 is not, the separation authored on LightPosition is doing the whole job.
	var marker: Marker3D = torch.get("light_position")
	if marker != null:
		var authored := marker.position
		marker.position = Vector3.ZERO
		await _frames(20)
		print("QA_ON_EYE offset_now=", torch.global_position.distance_to(eye))
		await _shot("03_control_origin_back_on_the_eye")
		marker.position = authored

	# Control: a plain scene-authored spotlight at the same nudged spot, no top_level, no follow script.
	# If THIS one shadows and the torch does not, the fault is in flash_light.gd, not the render config.
	torch.set(&"_light_on", false)
	var ctrl := SpotLight3D.new()
	ctrl.light_energy = torch.light_energy
	ctrl.light_color = torch.light_color
	ctrl.spot_range = torch.spot_range
	ctrl.spot_angle = torch.spot_angle
	ctrl.spot_angle_attenuation = torch.spot_angle_attenuation
	ctrl.shadow_enabled = true
	get_tree().root.add_child(ctrl)
	ctrl.global_transform = cam.global_transform.translated_local(Vector3(0.30, -0.25, 0.0))
	await _frames(10)
	await _shot("04_control_plain_spotlight")
	ctrl.queue_free()

	# --- PASS 2: no probe at all. Real brush level, real props, a real NPC — because the probe meshes are
	# plain StandardMaterial3D and the shipped world is the ps1.gdshader override, which has its own
	# IN_SHADOW_PASS branch. A shadow on MY box proves the light; a shadow on THEIRS proves the game.
	for n in [_probe_wall, _probe_box]:
		if is_instance_valid(n):
			n.queue_free()
	torch.set(&"_light_on", true)
	await _frames(10)
	await _shot("05_real_level_no_probe")

	var npc := _nearest_npc(player)
	if npc == null:
		print("QA_NPC none found")
	else:
		# Stand the player two metres off the NPC and light it, so the actor's own cast shadow is in frame.
		var to_npc := npc.global_position - player.global_position
		var flat := Vector3(to_npc.x, 0.0, to_npc.z)
		if flat.length() > 0.1:
			player.global_position = npc.global_position - flat.normalized() * 2.6 + Vector3(0.0, 0.2, 0.0)
			player.look_at(Vector3(npc.global_position.x, player.global_position.y, npc.global_position.z), Vector3.UP)
		await _frames(20)
		print("QA_NPC ", npc.name, " dist=", player.global_position.distance_to(npc.global_position))
		await _shot("06_real_npc_lit")

	# --- PASS 3: the one real hazard of an off-eye origin. Shove the player's LEFT shoulder — the side the
	# beam origin is offset toward — flat against a wall. The offset (0.27 m) is inside the player's 0.5 m
	# capsule radius, so the origin can never reach the far face; this is the shot that proves it, because the
	# failure mode is unmistakable (the beam vanishes, or lights the room on the other side).
	var space := player.get_world_3d().direct_space_state
	var probe := PhysicsRayQueryParameters3D.create(
			player.global_position, player.global_position - player.global_transform.basis.x * 6.0)
	probe.exclude = [player.get_rid()]
	var hit := space.intersect_ray(probe)
	if hit.is_empty():
		print("QA_WALL no wall found to lean on")
	else:
		# Park the capsule one radius off the surface — as close as the player could ever physically get.
		player.global_position = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.5
		var along := (hit["normal"] as Vector3).cross(Vector3.UP).normalized()
		player.look_at(player.global_position + along, Vector3.UP)
		await _frames(20)
		print("QA_WALL leaning at ", player.global_position, " normal=", hit["normal"],
				" torch=", torch.global_position, " gap_to_wall=",
				(torch.global_position - (hit["position"] as Vector3)).dot(hit["normal"] as Vector3))
		await _shot("07_left_shoulder_against_a_wall")

	# --- PASS 4: THE SHIPPED FRAME. Everything above is a RAW viewport grab — _strip_overlays() hid every
	# CanvasLayer, and ui.tscn's root layer carries the post_process.gdshader the player actually looks
	# through (16-step posterize + Bayer dither + film grain). A hard shadow can survive that and a soft one
	# can be eaten by it, so the evidence is not evidence until it is shot through the real chain. Only the
	# post-process layer comes back — the debug overlay and the event ticker stay hidden, or they cover the
	# wall we are trying to read. The gun is drawn too: the torch's layers = 5 spans the view-model layer
	# specifically so your own beam lights the weapon in your hands, and moving the beam apex left-and-down
	# is exactly what could push the grip out of the 33-degree cone.
	if _restore_post_process():
		print("QA_POST post-process layer restored")
	else:
		print("QA_POST_FAIL no post-process CanvasLayer found — shot 08 is still a raw grab")
	if player.get("weapon_system") != null and player.weapon_system.attack != null:
		player.weapon_system.attack.set_holstered(false)
	# Back to the OPENING pose, not wherever pass 3's wall-lean left us — this shot has to be comparable to
	# shot 02, because the whole question is whether that same shadow survives the posterize + dither + grain.
	player.global_transform = opening_pose
	await _frames(2)
	_place_probe(player, cam.global_position, -cam.global_transform.basis.z)
	await _frames(30)
	await _shot("08_shipped_frame_post_process_on_gun_drawn")

	print("QA_DONE")
	get_tree().quit(0)


## A controlled shadow test: a wall 5 m ahead and a box 2 m ahead, both plain opaque StandardMaterial3D on the
## default visual layer. Parented to the tree root (NOT the level) so the ps1 applier — which already walked the
## level — cannot be blamed for whatever the shot shows.
func _place_probe(player: Node3D, eye: Vector3, fwd: Vector3) -> void:
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	if flat.length() < 0.5:
		flat = Vector3.FORWARD

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.85, 0.85)
	# Two-sided: the probe wall is placed by look_at, and a one-sided plane facing the wrong way is
	# invisible — a blank shot would read as "no shadow" when it is really "no wall".
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var wall := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 6.0)
	plane.orientation = PlaneMesh.FACE_Z
	wall.mesh = plane
	wall.material_override = mat
	get_tree().root.add_child(wall)
	wall.global_position = eye + flat * 5.0 + Vector3(0.0, -0.6, 0.0)
	wall.look_at(eye, Vector3.UP)
	_probe_wall = wall

	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 1.6, 0.7)
	box.mesh = bm
	box.material_override = mat
	get_tree().root.add_child(box)
	box.global_position = eye + flat * 2.2 + Vector3(0.0, -0.6, 0.0)
	_probe_box = box

	# Aim the camera flat down the probe axis so the wall fills the frame.
	player.look_at(player.global_position + flat, Vector3.UP)


## The closest NPC to the player, so shot 06 lights an actor whose meshes the body_model_swap rig owns
## (its own cast_shadow / render-layer stamping is what decides whether an actor shadows at all).
func _nearest_npc(player: Node3D) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is NPC and (n as Node3D).is_inside_tree():
			var d: float = (n as Node3D).global_position.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = n as Node3D
		stack.append_array(n.get_children())
	return best


## Hide everything painted OVER the 3D frame — the boot sky title, the HUD, the debug tickers. The question
## these shots answer is what the renderer draws on the WALL, and a full-screen "CYBERSUNDAY" sits right on it.
## Pass 4 turns the post-process layer back on by itself (_restore_post_process) for the shipped-chain shot.
func _strip_overlays() -> void:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
		elif n.name == "SkyTitle" and n is Node3D:
			(n as Node3D).visible = false
		stack.append_array(n.get_children())


## Turn the POST-PROCESS layer back on and nothing else. ui.tscn's root CanvasLayer holds a full-rect
## CanvasItem whose ShaderMaterial is post_process.gdshader — that is the chain the player looks through, and
## it is the only overlay whose absence would make a shot lie about whether a shadow reads. Found by walking
## for that shader rather than by node name, so renaming the HUD cannot silently turn the check back off.
## Returns false if it is not there, so the shot is labelled honestly instead of quietly reverting to a raw grab.
func _restore_post_process() -> bool:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem:
			var mat := (n as CanvasItem).material as ShaderMaterial
			if mat != null and mat.shader != null and String(mat.shader.resource_path).contains("post_process"):
				var layer: Node = n
				while layer != null and not (layer is CanvasLayer):
					layer = layer.get_parent()
				if layer != null:
					(layer as CanvasLayer).visible = true
					return true
		stack.append_array(n.get_children())
	return false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path)
