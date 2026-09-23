extends SceneTree

## Weapon-hands probe — renders the FIRST-PERSON WEAPON HOLD (your own hands closed on the drawn gun,
## FirstPersonBody.weapon_hands) straight to PNGs, one per weapon, so the framing is judged by SIGHT.
## The sibling of preview_fists_frame.gd and built for the same reason: where hands read well on a gun is a
## framing call per weapon MODEL, and the two things that cannot be nudged blind are how much FOREARM ends up
## behind the near plane (the rig is placed by its HANDS, so a longer arm pushes its own shoulder backwards
## through the camera) and whether the hands land on a part of the weapon that is actually ON SCREEN — most of
## these view models park their true grip behind the lens, in the corner the gun itself disappears into.
##
##   godot --path <absolute project path> -s scripts/tools/probes/preview_weapon_hands_frame.gd
##
## WINDOWED on purpose (the preview_fists_frame.gd idiom): rendering needs a real renderer, so do NOT pass
## --headless — a window flashes for a few seconds, one PNG per CONFIGS row lands in OUT_DIR, then it quits.
## The red cross marks the exact crosshair position.
##
## ⭐WHAT IT MIRRORS, and why it is text-parsed rather than instantiated. `-s` runs before autoloads, and
## first_person_body.gd cannot be load()ed even lazily (its typed `host: Player` pulls in player.gd, which does
## not compile without autoloads) — so every authored value is read as TEXT, exactly as the fists probe does:
## Player.tscn's FirstPersonBody overrides first and the script's @export defaults for whatever the scene does
## not author; the GUN's mount off camera_rig.tscn's GunMesh node (the transform the hands are solved AGAINST);
## and each weapon's own `view_model` + `view_model_grip` off its .tres. Nothing is mirrored by hand, so a
## retune anywhere shows up here on the next run.
##
## The solve in _run() is copied from FirstPersonBody._solve_weapon_hands / _weapon_hands_anchor /
## weapon_hands_position. If that solve changes, change it here too — this probe is a MIRROR, not the source of
## truth, and a drifted mirror is worse than none.

const OUT_DIR := "res://.godot/"  ## PNGs land next to the import cache — throwaway output, never committed
## Draw a small MAGENTA ball at the solved anchor — where WeaponData.view_model_grip actually lands on this
## weapon. Flip it on while re-authoring a grip: the hand ends up there, so seeing the point itself turns
## "nudge the numbers and re-render" into one pass. Off for a clean framing still.
const SHOW_ANCHOR := false
## Render the gun IDLE-LOWERED — GunPose's muzzle-down droop + drop after a few quiet seconds — instead of at its
## authored rest. ⭐ON by default because this is the pose a standing player looks at nearly all the time, and it
## is where the first six passes of grip tuning went wrong: every one of them framed the hands against the
## rest pose, which the player sees only while moving, aiming or right after a shot. The droop pitches the gun
## through the baked 90° yaw (GunPose.apply_idle_lower), so it is applied through that same static, never by
## hand; the hands turn with it exactly as FirstPersonBody._gun_delta_basis does live.
const IDLE_LOWERED := true
## Render the gun in its full SPRINT pose (GunPose's Sprint group: sprint_offset + the pitch / yaw / roll through
## GunPose.apply_sprint_pose) INSTEAD of idle-lowered, since in game the sprint pose replaces the droop. PNGs get a
## `_sprint` suffix so a sprint run sits beside the idle one. Flip it on to tune the Sprint knobs by sight.
const SPRINT_POSE := false
const GUN_POSE_SCRIPT := "res://scripts/effects/gun_pose.gd"

## The authoritative sources (see header). If the FP rig or the gun mount moves homes again, repoint these.
const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const FP_NODE_HEADER := "[node name=\"FirstPersonBody\""
const FP_SCRIPT := "res://scripts/player/first_person_body.gd"
const CAMERA_RIG := "res://scenes/player/camera_rig.tscn"
const GUN_NODE_HEADER := "[node name=\"GunMesh\""
## The camera's rest-FOV chain (what Settings.fov boots from), then user://settings.cfg's saved fov on top.
const CAM_TUNING := "res://resources/tuning/CameraSettings.tres"
const CAM_TUNING_SCRIPT := "res://resources/tuning/CameraSettings.gd"

## Rows: [name, weapon .tres, tilt_deg, scale_mult, spread, stagger_m, grip override, converge_deg, reach, yaw_deg].
## null in any pose slot means "the AUTHORED value" — the FirstPersonBody pose for the first four, and the
## weapon's own view_model_grip for the last — so a row of nulls IS the shipped hold by construction. To
## bracket a retune (a candidate grip for one weapon, a steeper tilt for all), add rows overriding just those.
const CONFIGS := [
	["pistol", "res://resources/weapons/pistol.tres", null, null, null, null, null, null, null, null],
	["smg", "res://resources/weapons/smg.tres", null, null, null, null, null, null, null, null],
	["shotgun", "res://resources/weapons/shotgun.tres", null, null, null, null, null, null, null, null],
	["sniper", "res://resources/weapons/sniper_wep.tres", null, null, null, null, null, null, null, null],
	["melee", "res://resources/weapons/melee.tres", null, null, null, null, null, null, null, null],
	["rock", "res://resources/weapons/rock_weapon.tres", null, null, null, null, null, null, null, null],
	["spray", "res://resources/weapons/spray_paint.tres", null, null, null, null, null, null, null, null],
]

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame  # let the root window report in-tree first (see bake_item_icons.gd)
	if DisplayServer.get_name() == "headless":
		push_error("preview_weapon_hands_frame: needs a renderer — run WITHOUT --headless.")
		quit(1)
		return
	# The shipped baseline, read off the authored sources (see header). A miss means the rig's wiring moved
	# again — fail loud instead of rendering a pose the game no longer uses.
	var overrides := _section_raw(PLAYER_SCENE, FP_NODE_HEADER)
	var pose := {}
	for prop in ["fp_arm_scale", "fp_arm_rotation", "weapon_hands_tilt_deg", "weapon_hands_scale_mult",
			"weapon_hands_spread", "weapon_hands_stagger", "weapon_hands_grip_offset",
			"weapon_hands_converge_deg", "weapon_hands_reach", "weapon_hands_yaw_deg"]:
		var v: Variant = _authored(prop, overrides, FP_SCRIPT)
		if v == null:
			push_error("preview_weapon_hands_frame: no authored '" + prop + "' in " + PLAYER_SCENE + " or "
					+ FP_SCRIPT + " — did the FP rig move homes again? Repoint the consts above.")
			quit(1)
			return
		pose[prop] = v
	# The GUN's authored mount under the camera — the point the hands are solved against.
	var gun_xf: Variant = _authored("transform", _section_raw(CAMERA_RIG, GUN_NODE_HEADER), "")
	if not (gun_xf is Transform3D):
		push_error("preview_weapon_hands_frame: no GunMesh transform in " + CAMERA_RIG)
		quit(1)
		return
	var fov: Variant = _authored("default_fov", _section_raw(CAM_TUNING, "[resource]"), CAM_TUNING_SCRIPT)
	if fov == null:
		push_error("preview_weapon_hands_frame: no authored 'default_fov' in " + CAM_TUNING)
		quit(1)
		return
	# ...overlaid with the player's SAVED fov, exactly like Settings.load_settings — the pose is played at the
	# user's FOV, and framing judged at the default reads clipped.
	var saved := ConfigFile.new()
	if saved.load("user://settings.cfg") == OK:
		fov = saved.get_value("video", "fov", fov)
	var cam := Camera3D.new()
	cam.fov = fov
	root.add_child(cam)
	cam.make_current()
	# Flat ambient fill, roughly the gun pass's view-model environment, so the arms read as shapes.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.91, 0.95)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	# The gun rig: a bare Node3D at the authored GunMesh mount, with the equipped weapon's view_model under it
	# at identity — which is exactly what WeaponModelSwapper.equip() builds at runtime.
	var gun := Node3D.new()
	gun.transform = gun_xf
	var rest_basis: Basis = (gun_xf as Transform3D).basis.orthonormalized()
	if SPRINT_POSE:
		var GunPoseScript = load(GUN_POSE_SCRIPT)
		var knobs := {}
		for prop in ["sprint_offset", "sprint_pitch_deg", "sprint_yaw_deg", "sprint_roll_deg"]:
			knobs[prop] = _authored(prop, {}, GUN_POSE_SCRIPT)
			if knobs[prop] == null:
				push_error("preview_weapon_hands_frame: gun_pose.gd no longer authors " + prop)
				quit(1)
				return
		var rest_deg: Vector3 = rest_basis.get_euler() * (180.0 / PI)
		var sprint_deg: Vector3 = GunPoseScript.apply_sprint_pose(rest_deg, float(knobs["sprint_pitch_deg"]),
				float(knobs["sprint_yaw_deg"]), float(knobs["sprint_roll_deg"]), 1.0)
		gun.transform = Transform3D(Basis.from_euler(sprint_deg * (PI / 180.0)),
				(gun_xf as Transform3D).origin + (knobs["sprint_offset"] as Vector3))
		print("preview_weapon_hands_frame: SPRINT_POSE — ", knobs)
	elif IDLE_LOWERED:
		var GunPoseScript = load(GUN_POSE_SCRIPT)
		var pitch: Variant = _authored("idle_lower_pitch_deg", {}, GUN_POSE_SCRIPT)
		var drop: Variant = _authored("idle_lower_drop", {}, GUN_POSE_SCRIPT)
		if pitch == null or drop == null:
			push_error("preview_weapon_hands_frame: gun_pose.gd no longer authors idle_lower_pitch_deg / idle_lower_drop")
			quit(1)
			return
		var rest_deg: Vector3 = rest_basis.get_euler() * (180.0 / PI)
		var lowered_deg: Vector3 = GunPoseScript.apply_idle_lower(rest_deg, float(pitch), 1.0)
		gun.transform = Transform3D(Basis.from_euler(lowered_deg * (PI / 180.0)),
				(gun_xf as Transform3D).origin - Vector3(0.0, float(drop), 0.0))
		print("preview_weapon_hands_frame: IDLE_LOWERED — gun pitched ", pitch, "° down and dropped ", drop, " m")
	cam.add_child(gun)
	# The hands: the same BodyModelSwap FirstPersonBody._build_first_person_arms builds, on its own mount.
	var mount := Node3D.new()
	cam.add_child(mount)
	var Swap = load("res://scripts/components/body_model_swap.gd")
	var rig = Swap.new()
	rig.casts_shadow = false
	rig.animate_arms = false
	rig.arm_model = load("res://assets/models/arm.blend")
	rig.arm_rotation = pose["fp_arm_rotation"]
	mount.add_child(rig)
	# Crosshair marker at the exact screen centre — the project's stretch makes the ROOT VIEWPORT smaller than
	# the OS window, so centre on the viewport, not the window.
	var cl := CanvasLayer.new()
	root.add_child(cl)
	var sz: Vector2 = (root as Viewport).get_visible_rect().size
	for dim in [Vector2(24, 2), Vector2(2, 24)]:
		var r := ColorRect.new()
		r.color = Color.RED
		r.size = dim
		r.position = sz / 2.0 - dim / 2.0
		cl.add_child(r)
	var anchor_ball: MeshInstance3D = null
	if SHOW_ANCHOR:
		anchor_ball = MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.008
		ball.height = 0.016
		anchor_ball.mesh = ball
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.MAGENTA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		anchor_ball.material_override = mat
		root.add_child(anchor_ball)
	var arm_scale: float = pose["fp_arm_scale"]
	var offset: Vector3 = pose["weapon_hands_grip_offset"]
	var model: Node3D = null
	for cfg in CONFIGS:
		var tilt: float = pose["weapon_hands_tilt_deg"] if cfg[2] == null else cfg[2]
		var scale_mult: float = pose["weapon_hands_scale_mult"] if cfg[3] == null else cfg[3]  # hand_scale folds in below
		var spread: float = pose["weapon_hands_spread"] if cfg[4] == null else cfg[4]
		var stagger: float = pose["weapon_hands_stagger"] if cfg[5] == null else cfg[5]
		var converge: float = pose["weapon_hands_converge_deg"] if cfg.size() < 8 or cfg[7] == null else cfg[7]
		var reach: float = pose["weapon_hands_reach"] if cfg.size() < 9 or cfg[8] == null else cfg[8]
		var yaw: float = pose["weapon_hands_yaw_deg"] if cfg.size() < 10 or cfg[9] == null else cfg[9]
		var section := _section_raw(String(cfg[1]), "[resource]")
		var grip_pt: Vector3 = _resource_grip(section) if cfg[6] == null else cfg[6]
		# ONE-HANDED collapses the pair onto one point as well as hiding the off hand — see
		# FirstPersonBody._solve_weapon_hands for why the two halves are inseparable.
		var one_handed: bool = String(section.get("view_model_one_handed", "")) == "true"
		# ...and the per-weapon hand size scales the pair's geometry together (FirstPersonBody._solve_weapon_hands).
		var hand_scale := 1.0
		var hs_raw: String = section.get("view_model_hand_scale", "")
		if not hs_raw.is_empty():
			hand_scale = float(hs_raw)
		scale_mult *= hand_scale
		spread *= hand_scale
		stagger *= hand_scale
		if one_handed:
			spread = 0.0
			converge = 0.0
			stagger = 0.0
		if is_instance_valid(model):
			model.queue_free()
			model = null
		var scene_path := _resource_view_model(String(cfg[1]))
		if scene_path.is_empty():
			push_error("preview_weapon_hands_frame: " + String(cfg[1]) + " authors no view_model — skipped")
			continue
		var scene: PackedScene = load(scene_path) as PackedScene
		if scene != null:
			model = scene.instantiate() as Node3D
			gun.add_child(model)
		# --- THE SOLVE (mirrors FirstPersonBody._solve_weapon_hands — keep the two in step) ---
		# The hands turn with the gun: (live gun basis x rest⁻¹) x the authored pose — FirstPersonBody._gun_delta_basis.
		var gun_delta: Basis = gun.transform.basis.orthonormalized() * rest_basis.inverse()
		rig.transform.basis = gun_delta * Basis.from_euler(Vector3(deg_to_rad(tilt), deg_to_rad(yaw), 0.0))
		rig.arm_scale = arm_scale * scale_mult
		rig.weapon_grip_reach = reach
		rig.hide_offhand = one_handed
		rig.arm_position = Vector3(spread, 0.0, 0.0)
		rig.arm_converge_deg = converge
		rig.arm_stagger = stagger
		rig.arm_stride_deg = 0.0
		var anchor: Vector3 = gun.global_position \
				+ gun.global_transform.basis.orthonormalized() * (grip_pt + offset)
		if anchor_ball != null:
			anchor_ball.global_position = anchor
		var grip: Variant = rig.weapon_grip_position()
		if grip == null:
			push_error("preview_weapon_hands_frame: the arms rig reported no grip — no arm model instanced?")
			quit(1)
			return
		rig.position = mount.global_transform.affine_inverse() * anchor - rig.transform.basis * (grip as Vector3)
		for i in 6:
			await process_frame
		# The numbers the picture cannot show: how far the shoulders sit BEHIND the lens (positive z is behind
		# it), which is what decides whether you are looking at a forearm or at the inside of one.
		var shoulder: Vector3 = rig.global_position
		print("preview_weapon_hands_frame: ", cfg[0],
				"  model=", scene_path.get_file(),
				"  grip=", grip_pt.snapped(Vector3.ONE * 0.001),
				"  one_handed=", one_handed, "  hand_scale=", hand_scale,
				"  anchor=", anchor.snapped(Vector3.ONE * 0.001),
				"  shoulder_z=", snappedf(shoulder.z, 0.001))
		var img := root.get_texture().get_image()
		var path := OUT_DIR + "weapon_hands_" + String(cfg[0]) + ("_sprint" if SPRINT_POSE else "") + ".png"
		img.save_png(path)
		print("preview_weapon_hands_frame: saved ", ProjectSettings.globalize_path(path))
	quit(0)

## A weapon .tres's `view_model` scene path, resolved through the ext_resource id it names. "" when the weapon
## has no view model (fists) or the row is missing.
static func _resource_view_model(tres: String) -> String:
	var f := FileAccess.open(tres, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	var id := RegEx.create_from_string("(?m)^view_model = ExtResource\\(\"([^\"]+)\"\\)").search(text)
	if id == null:
		return ""
	var line := RegEx.create_from_string(
			"(?m)^\\[ext_resource [^\\]]*path=\"([^\"]+)\"[^\\]]*id=\"" + id.get_string(1) + "\"").search(text)
	return "" if line == null else line.get_string(1)

## A weapon .tres's authored `view_model_grip`, or ZERO when it does not author one (the WeaponData default).
static func _resource_grip(section: Dictionary) -> Vector3:
	var raw: String = section.get("view_model_grip", "")
	if raw.is_empty():
		return Vector3.ZERO
	var v: Variant = str_to_var(raw)
	return v if v is Vector3 else Vector3.ZERO

## key -> raw VariantWriter value text for every `key = value` line of ONE section of a .tscn/.tres, located
## by its header line's PREFIX. Text-parsed on purpose — see the header for why load()ing is impossible here.
static func _section_raw(path: String, header_prefix: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("preview_weapon_hands_frame: can't open " + path)
		return out
	var in_section := false
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("["):
			if in_section:
				break  # the section's props ended at the next header
			in_section = line.begins_with(header_prefix)
			continue
		if not in_section:
			continue
		var eq := line.find("=")
		if eq > 0:
			out[line.substr(0, eq).strip_edges()] = line.substr(eq + 1).strip_edges()
	return out

## The default-value text of a script's `@export var <prop> ... = <default>` line ("" if the prop is gone).
static func _export_default_raw(script_path: String, prop: String) -> String:
	if script_path.is_empty():
		return ""
	var f := FileAccess.open(script_path, FileAccess.READ)
	if f == null:
		push_error("preview_weapon_hands_frame: can't open " + script_path)
		return ""
	var re := RegEx.create_from_string("(?m)^@export[^\\n]*?\\bvar\\s+" + prop + "\\b[^=\\n]*=\\s*(.+)$")
	var m := re.search(f.get_as_text())
	return "" if m == null else m.get_string(1).strip_edges()

## One authored value: the scene/resource override when the section authors the prop, else the script's
## @export default. null = found in neither (or unparseable) — callers treat that as "the wiring moved".
static func _authored(prop: String, overrides: Dictionary, fallback_script: String) -> Variant:
	var raw: String = overrides.get(prop, "")
	if raw.is_empty():
		raw = _export_default_raw(fallback_script, prop)
	return null if raw.is_empty() else str_to_var(raw)
