extends SceneTree

## FP-BODY frame probe — renders your own first-person BODY (legs + torso + the arms that hang off it) at a
## sweep of LOOK-DOWN pitches, straight to PNGs, so body-awareness framing is judged by SIGHT. Sibling of
## preview_fists_frame.gd, which does the same job for the view-model hands under the camera; this one exists
## because the body rig's framing question is fundamentally different — its parts sit at REAL world depth around
## the camera, so most of them are only in frame when you LOOK DOWN, and a pose that reads fine head-on can be
## invisible or clipping at 70 degrees.
##
##   godot --path <absolute project path> -s scripts/tools/preview_fp_body_frame.gd
##
## WINDOWED on purpose (the bake_item_icons.gd idiom): rendering needs a real renderer, so do NOT pass
## --headless. One PNG per CONFIGS row lands in OUT_DIR, then it quits.
##
## Nothing is MIRRORED here — every number is read off the authored sources as TEXT at run time (the same rule,
## and the same two static readers, as preview_fists_frame.gd; -s runs before autoloads, so first_person_body.gd
## can't be load()ed at all — its typed `host: Player` pulls in player.gd). Sources: Player.tscn's
## FirstPersonBody overrides, then that script's @export defaults; the torso's own transform from the appearance
## catalog's default body part; the FOV from user://settings.cfg. A retune shows up on the next run.

const OUT_DIR := "res://.godot/"  ## PNGs land next to the import cache — throwaway output, never committed

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const FP_NODE_HEADER := "[node name=\"FirstPersonBody\""
const FP_SCRIPT := "res://scripts/player/first_person_body.gd"
## The fists probe owns the two generic .tscn/.tres text readers — reused rather than copied, so the parsing
## rules can never drift between the two tools.
const FISTS_PROBE := "res://scripts/tools/preview_fists_frame.gd"
## The default body part the FP torso is stamped from (CharacterAppearanceCatalog.default_body → bodies[0]).
## Its `scale` / `rotation` / `position` are what _configure_fp_torso reads; position defaults to ZERO.
const BODY_PART := "res://resources/parts/bodies/standard.tres"
const TORSO_MODEL := "res://scenes/bodyparts/torso.tscn"
## The appearance catalog — the authoritative ARM MOUNT (arm_scale / arm_position / arm_rotation), the same rows
## configure_swap stamps onto every NPC and that _configure_fp_body_arms now reads instead of authoring its own.
const CATALOG := "res://resources/characters/PlayerAppearanceCatalog.tres"
## The player's own capsule, which is where the FLOOR is: its bottom (collision-shape origin minus half the
## capsule height) is the plane the feet stand on, in Player-local metres. Everything this tool measures is in
## that same Player-local frame, so "does a limb poke through the floor" is a direct subtraction — no camera
## height involved, which is why the measurement is trustworthy even though the render's camera is approximate.
const CAPSULE_SHAPE_HEADER := "[sub_resource type=\"CapsuleShape3D\""
const COLLIDER_NODE_HEADER := "[node name=\"PlayerCollisionShape\""
const CAM_TUNING := "res://resources/tuning/CameraSettings.tres"
const CAM_TUNING_SCRIPT := "res://resources/tuning/CameraSettings.gd"

## The pose knobs read off FirstPersonBody. Legs and torso come along for the ride because the ARMS can only be
## judged against the body they hang off — floating arms and well-seated arms look identical in isolation.
const POSE_PROPS := ["fp_leg_offset", "fp_leg_scale", "fp_torso_offset", "fp_body_arm_offset",
		"fp_body_arm_scale_mult", "fp_body_scale",
		# The ACTOR RIM. Read here (rather than left off as "not a pose") for one reason: --headless NEVER COMPILES
		# A SHADER, so a broken outline.gdshader passes every test in this project and ships dead — twice now. This
		# probe is windowed, so the rim either appears in the PNG or the shader is broken. Judge it here.
		"first_person_body_outline", "fp_body_outline_color", "fp_body_outline_width"]
## ...and the arm mount rows read off the catalog (see CATALOG).
const CATALOG_PROPS := ["arm_scale", "arm_position", "arm_rotation", "leg_scale", "leg_position", "leg_rotation"]

# Candidate rows: [name, pitch_deg, arm_position, arm_rotation, arm_scale] — pitch_deg is how far the camera
# looks DOWN (0 = level, 90 = straight at your feet), and null in any pose slot means "the AUTHORED value".
# An all-null pose row IS the shipped body by construction, so the pitch sweep alone shows the shipped framing.
const CONFIGS := [
	["p30", 30.0, null, null, null],
	["p50", 50.0, null, null, null],
	["p70", 70.0, null, null, null],
	["p90", 90.0, null, null, null],
]

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame  # let the root window report in-tree first (see bake_item_icons.gd)
	if DisplayServer.get_name() == "headless":
		push_error("preview_fp_body_frame: needs a renderer — run WITHOUT --headless.")
		quit(1)
		return
	var Probe = load(FISTS_PROBE)  # the shared text readers (see FISTS_PROBE)
	var overrides: Dictionary = Probe._section_raw(PLAYER_SCENE, FP_NODE_HEADER)
	var pose := {}
	for prop in POSE_PROPS:
		var v: Variant = Probe._authored(prop, overrides, FP_SCRIPT)
		if v == null:
			push_error("preview_fp_body_frame: no authored '" + prop + "' in " + PLAYER_SCENE + " or "
					+ FP_SCRIPT + " — did the FP rig move homes again? Repoint the consts above.")
			quit(1)
			return
		pose[prop] = v
	var cat_raw: Dictionary = Probe._section_raw(CATALOG, "[resource]")
	var mount := {}
	for prop in CATALOG_PROPS:
		var v: Variant = str_to_var(String(cat_raw.get(prop, "")))
		if v == null:
			push_error("preview_fp_body_frame: " + CATALOG + " must author '" + prop + "'")
			quit(1)
			return
		mount[prop] = v
	print("preview_fp_body_frame: catalog arm mount pos=", mount["arm_position"], " rot=", mount["arm_rotation"],
			" scale=", mount["arm_scale"], "  fp offset=", pose["fp_body_arm_offset"])
	# The torso's own authored transform, from the catalog's default body part (position is optional — the
	# shipped `standard` body doesn't author it, and _configure_fp_torso treats a missing one as ZERO).
	var body_raw: Dictionary = Probe._section_raw(BODY_PART, "[resource]")
	var torso_scale: Variant = Probe._authored("scale", body_raw, "")
	var torso_rot: Variant = Probe._authored("rotation", body_raw, "")
	# position is OPTIONAL (the shipped `standard` body doesn't author it, and _configure_fp_torso treats a
	# missing one as ZERO), so it's read straight off the raw section — _authored would go looking for an
	# @export default in a script that doesn't exist here and push a spurious error.
	var torso_pos: Variant = str_to_var(String(body_raw.get("position", "")))
	if torso_scale == null or torso_rot == null:
		push_error("preview_fp_body_frame: " + BODY_PART + " must author scale + rotation")
		quit(1)
		return
	if torso_pos == null:
		torso_pos = Vector3.ZERO
	var torso_tex: Variant = body_raw.get("texture", "")  # ExtResource(..) ref — resolved below by path lookup
	var fov: Variant = Probe._authored("default_fov", Probe._section_raw(CAM_TUNING, "[resource]"), CAM_TUNING_SCRIPT)
	if fov == null:
		push_error("preview_fp_body_frame: no authored 'default_fov' in " + CAM_TUNING)
		quit(1)
		return
	var saved := ConfigFile.new()  # the player's real FOV wins, exactly like Settings.load_settings
	if saved.load("user://settings.cfg") == OK:
		fov = saved.get_value("video", "fov", fov)
	# The camera sits at the PLAYER ORIGIN (Player.tscn's Head is authored at y ~0.014, i.e. on it), which is
	# what makes fp_leg_offset read directly as "how far below your eyes the rig hangs".
	var cam := Camera3D.new()
	cam.fov = fov
	root.add_child(cam)
	cam.make_current()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.91, 0.95)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	# Mirrors _build_first_person_legs + _configure_fp_torso + _configure_fp_body_arms. animate_arms/legs stay
	# OFF so what renders is the authored REST pose (_apply_arm_transform's write) rather than a random frame of
	# the walk swing — the rest is what has to frame correctly; the swing only adds to it.
	var Swap = load("res://scripts/components/body_model_swap.gd")
	var rig = Swap.new()
	rig.casts_shadow = false
	# The actor rim, set BEFORE any model exactly as _build_first_person_legs does. In-game this ALSO registers the
	# body with InkOutline's actor mask (the same switch); there is no ink pass in this harness, so what the PNG
	# proves is the other half — that the inverted-hull shader still compiles and draws.
	rig.actor_outline = pose["first_person_body_outline"]
	rig.actor_outline_color = pose["fp_body_outline_color"]
	rig.actor_outline_width = pose["fp_body_outline_width"]
	rig.animate_arms = false
	rig.animate_legs = false
	rig.breathe = false
	rig.leg_model = load("res://assets/models/leg.blend")
	rig.leg_scale = pose["fp_leg_scale"]
	rig.leg_position = Vector3(0.095, -0.265, -0.02)  # the shipped hip offset (_build_first_person_legs)
	rig.leg_rotation = mount["leg_rotation"]
	rig.leg_color = Color(0.49, 0.18, 0.22)           # catalog default_leg_color
	rig.body_model_scale = torso_scale
	rig.body_model_rotation = (torso_rot as Vector3) + Vector3(0.0, 180.0, 0.0)  # the player faces -Z
	rig.body_model_position = (torso_pos as Vector3) + (pose["fp_torso_offset"] as Vector3)
	# ⭐The torso is deliberately given a FLAT COLOUR instead of its authored texture. torso.tscn's own material
	# renders BLACK in a -s tool run (it wants autoloads this harness doesn't have), and a black chest makes the
	# arm placement — the whole point of the probe — impossible to read. A non-WHITE body_color routes through
	# BodyModelSwap._skin, which stamps a plain material override that always renders. So: trust this tool for
	# arm PLACEMENT, REACH and near-clip, and judge colour/shading in-game. (torso_tex is resolved anyway, below,
	# so switching back is one line if the material path ever works here.)
	rig.body_color = Color(0.75, 0.72, 0.62)  # a skin tone from the catalog's limb_palette
	var tex_path := _ext_resource_path(BODY_PART, String(torso_tex))
	if tex_path.is_empty():
		push_warning("preview_fp_body_frame: couldn't resolve the body part's texture path (cosmetic only)")
	rig.body_model = load(TORSO_MODEL)
	root.add_child(rig)
	rig.position = pose["fp_leg_offset"]
	# The whole-rig scale (_build_first_person_legs writes the same thing). Everything measured below is therefore
	# in Player metres already — the report's floor clearance and hip-vs-chest stack both stay directly comparable.
	rig.scale = Vector3.ONE * (pose["fp_body_scale"] as float)
	# WHERE THE FLOOR IS (Player-local), off the capsule — see CAPSULE_SHAPE_HEADER. Godot's CapsuleShape3D
	# defaults radius 0.5 / height 2.0, and `height` INCLUDES the two hemispherical caps, so the bottom is
	# origin.y - height/2.
	var cap_raw: Dictionary = Probe._section_raw(PLAYER_SCENE, CAPSULE_SHAPE_HEADER)
	var col_raw: Dictionary = Probe._section_raw(PLAYER_SCENE, COLLIDER_NODE_HEADER)
	var cap_h: Variant = str_to_var(String(cap_raw.get("height", "2.0")))
	var col_xform: Variant = str_to_var(String(col_raw.get("transform", "")))
	var floor_y: float = (0.0 if not (col_xform is Transform3D) else (col_xform as Transform3D).origin.y) \
			- float(cap_h if cap_h is float else 2.0) * 0.5
	print("preview_fp_body_frame: floor (capsule bottom) at Player-local y = %.4f" % floor_y)
	# A floor plane exactly there, so the render SHOWS any limb poking through it instead of leaving it to the eye.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6.0, 6.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.22, 0.24, 0.28)
	ground.material_override = gm
	root.add_child(ground)
	ground.position = Vector3(0.0, floor_y, 0.0)
	var arm_model := load("res://assets/models/arm.blend")
	for cfg in CONFIGS:
		cam.rotation_degrees = Vector3(-(cfg[1] as float), 0.0, 0.0)  # negative X = looking DOWN (the Head rule)
		# Mirrors _configure_fp_body_arms exactly: the catalog mount, plus the FP-specific offset on the position.
		rig.arm_position = (mount["arm_position"] as Vector3) + (pose["fp_body_arm_offset"] as Vector3) if cfg[2] == null else cfg[2]
		rig.arm_rotation = mount["arm_rotation"] if cfg[3] == null else cfg[3]
		rig.arm_scale = (mount["arm_scale"] as float) * (pose["fp_body_arm_scale_mult"] as float) if cfg[4] == null else cfg[4]
		rig.arm_color = Color(0.19, 0.33, 0.56)  # catalog default_arm_color
		rig.arm_model = arm_model                # LAST: rebuilds, so the above is already stamped
		for i in 6:
			await process_frame
		_report_extents(rig, floor_y, String(cfg[0]), float(fov))
		var img := root.get_texture().get_image()
		var path := OUT_DIR + "fpbody_" + String(cfg[0]) + ".png"
		img.save_png(path)
		print("preview_fp_body_frame: saved ", ProjectSettings.globalize_path(path))
	quit(0)


## Per-limb REACH report: the vertical SPAN of each part, how far its lowest point sits above (+) or below (-)
## the floor plane, and — the second half, added 2026-08-15 — whether the parts are STACKED in anatomical order.
## This is the numeric half of the probe and the half you should read FIRST: both "the limbs clip into the floor"
## and "the legs are drawn on top of the chest" are measurements, not opinions, and eyeballing a render at one
## pitch can't tell you by how much. Measured at the REST pose (animate_arms/legs are off), which is the worst
## case for depth: both the walk swing and the arm stride rotate a limb about its mount, which RAISES the far end.
##
## ⭐The STACK line exists because the floor-clearance line alone once endorsed a rig whose torso had sunk BELOW
## the leg hips (the legs rendered on top of the chest). Clearance is a one-sided measurement — it only ever looks
## down — so a part that is mounted too LOW passes it silently. Read both lines.
##
## Reaches into the rig's private part handles on purpose — every pair is instanced under the same "ModelPart"
## name, so there is no reliable way to tell an arm from a leg by node name.
func _report_extents(rig: Node, floor_y: float, label: String, fov: float) -> void:
	var spans := {}
	var fronts := {}
	for row in [["torso", rig._body], ["arm L", rig._arm_left], ["arm R", rig._arm_right],
			["leg L", rig._leg_left], ["leg R", rig._leg_right]]:
		var part: Node = row[1]
		if not is_instance_valid(part):
			continue
		var box := _world_aabb(part)
		if box.size == Vector3.ZERO:
			continue
		var span := Vector2(box.position.y, box.position.y + box.size.y)
		spans[row[0]] = span
		fronts[row[0]] = box.position.z
		var clearance := span.x - floor_y
		var verdict := "OK" if clearance >= 0.0 else "CLIPS %.3f m THROUGH THE FLOOR" % -clearance
		# The Z span is the FORWARD reach (the player faces -Z, so a negative front edge is geometry standing in
		# front of the lens). It is the third un-eyeballable number here: a chest whose front edge pokes forward of
		# the camera hides everything below it the moment you look down — you see your own chest and no feet.
		print("  [%s] %-6s y = %+.4f .. %+.4f   clearance = %+.4f   front z = %+.4f   %s"
				% [label, row[0], span.x, span.y, clearance, box.position.z, verdict])
	# THE STACK CHECK: your hips must be inside your chest, not above your head. The leg's TOP is the hip; the
	# torso's span is the chest. A hip above the chest's top means the legs render over the body you look down at.
	if spans.has("leg L") and spans.has("torso"):
		var hip: float = (spans["leg L"] as Vector2).y
		var chest: Vector2 = spans["torso"]
		var overhang := hip - chest.y
		var stack_verdict := "OK (hip inside the chest)" if overhang <= 0.0 \
				else "LEGS ON TOP OF THE TORSO — the hip sits %.3f m ABOVE the chest's top" % overhang
		print("  [%s] STACK  hip top = %+.4f   chest = %+.4f .. %+.4f   %s"
				% [label, hip, chest.x, chest.y, stack_verdict])
	# THE DROP THRESHOLD: how far the camera has to fall before the body appears at LEVEL pitch. The look-down
	# sweep above cannot ask this — it only ever moves the pitch — but a landing dip, a stair step-smooth and a
	# crouch all lower the lens toward a body that has not moved, and that is the "I can see my body without
	# looking down" case. It is pure trigonometry off the numbers already in hand: the part's nearest top-front
	# corner enters the frustum when it rises to the half-FOV.
	#
	# ⭐It is REPORTED, not defended against: FirstPersonBody gates visibility purely on the LOOK now
	# (fp_body_reveal_start_deg), precisely because this figure shrinks with the player's FOV setting and no
	# fixed metre band can survive that. Keep the line — it is how you tell whether a re-scale or a re-mount
	# has quietly put the body back inside the frustum at level pitch, which is the state the gate is hiding.
	if fov > 0.0:
		var half_fov := deg_to_rad(fov) * 0.5
		for key in ["torso", "arm L", "leg L"]:
			if not fronts.has(key):
				continue
			var top: float = (spans[key] as Vector2).y
			var front: float = -float(fronts[key])  # metres FORWARD of the lens (the player faces -Z)
			if front <= 0.0:
				continue  # entirely behind the lens plane — no drop brings it into a forward-facing frustum
			print("  [%s] ENTERS %-6s at level pitch once the camera drops %.3f m (top %+.4f, %.3f m forward, half-FOV %.1f deg)"
					% [label, key, maxf(0.0, -top - front * tan(half_fov)), top, front, rad_to_deg(half_fov)])


## The merged world-space AABB of every visible mesh under `part`, or a zero-size box when it has none. Each
## mesh's local AABB is taken into world space by its own global transform (Transform3D * AABB), so a
## rotated/scaled limb is measured where it actually IS rather than at its model-space extents.
static func _world_aabb(part: Node) -> AABB:
	var merged := AABB()
	var has := false
	var stack: Array[Node] = [part]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		merged = box if not has else merged.merge(box)
		has = true
	return merged

## The res:// path an `ExtResource("id")` reference resolves to, by matching the id back against the file's
## own [ext_resource ...] header lines. Text-parsed for the same reason everything else here is — see the
## header. "" when the reference is empty or its id has no header line.
static func _ext_resource_path(file_path: String, reference: String) -> String:
	var id_start := reference.find("\"")
	if id_start < 0:
		return ""
	var id := reference.substr(id_start + 1, reference.rfind("\"") - id_start - 1)
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return ""
	while not f.eof_reached():
		var line := f.get_line()
		if not line.begins_with("[ext_resource"):
			continue
		if line.contains("id=\"" + id + "\""):
			var p := line.find("path=\"")
			if p < 0:
				return ""
			return line.substr(p + 6, line.find("\"", p + 6) - p - 6)
	return ""
