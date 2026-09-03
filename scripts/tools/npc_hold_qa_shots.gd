extends Node
## NPC HELD-WEAPON QA screenshot harness — boots the REAL game, stands an armed NPC in the open, hands it
## each weapon in turn, and photographs how it HOLDS the thing from the side and the front, at three target
## elevations. The only honest way to judge the three things this harness exists for:
##
##   1. SIZE     — is the gun the right size next to a ~1.85 m body, or a toy / a cannon?
##   2. PLACEMENT — is it IN THE HANDS, or floating at the belly while the arms reach past it?
##   3. AIM      — does the barrel actually point at the player when the player is above / below / level?
##
## WHY a screenshot harness: all three are LOOK bugs. Every number involved (npc_held_display_scale, the hand
## anchor offset, an aim pitch) round-trips perfectly in a unit test while the frame reads as garbage, and
## --headless never renders at all. So this prints the measured geometry BESIDE each photograph — hand
## positions, gun AABB, barrel direction vs. the true line to the target — and a reviewer judges both together.
##
## Run from the project root as a REAL WINDOWED RUN (the GPU must render — NOT --headless):
##   godot --path . res://scripts/tools/npc_hold_qa_shots.tscn -- --shots-dir="C:/some/dir"
## Without --shots-dir it writes to user://npc_hold_qa_shots. Prints one QA_SHOT line per capture.
##
## Driver-copy pattern, copied from muzzle_smoke_qa_shots.gd: this scene is the boot scene, but the run
## switches current_scene to game.tscn (which frees the current scene), so _ready re-attaches a COPY of this
## script on a bare Node parented to root, which survives the change and drives the run.
##
## (*) NEVER call a Settings.set_* here — those setters call save_settings() and would rewrite the developer's
## real user://settings.cfg. Read the live values, never write them.

## The weapons photographed, in order. Each is handed to the SAME NPC through the one seam that equips AND
## rebuilds the hand model (`_on_equip_weapon_requested`), so every frame differs only by the weapon.
const WEAPONS := [
	"res://resources/weapons/pistol.tres",
	"res://resources/weapons/smg.tres",
	"res://resources/weapons/shotgun.tres",
	"res://resources/weapons/sniper_wep.tres",
	"res://resources/weapons/melee.tres",
	"res://resources/weapons/spray_paint.tres",
	"res://resources/weapons/rock_weapon.tres",
]

## How far the photographer stands from the NPC, and how high the "aim up / aim down" poses sit. The
## elevation poses are what prove (or disprove) that the barrel tracks the target vertically.
const STAND_DIST := 3.2
const HIGH_UP := 4.0
const LOW_DOWN := -2.2

var _dir := "user://npc_hold_qa_shots"
var _eye: Camera3D = null
var _cam: Camera3D = null          ## the diagnostic camera (a free-flying side/front lens)
var _npc: Node3D = null
var _player: Node3D = null
var _pin := Vector3.ZERO           ## where the player is held this beat (re-asserted every frame; see _hold)
var _pin_active := false
var _npc_home := Vector3.ZERO    ## where the subject is frozen (see _process)
var _side_dir := Vector3.RIGHT   ## the clear flank the profile lens shoots from (picked once, in _run)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "NpcHoldQaDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()


## The pin runs on BOTH clocks. `_process` alone is not enough: the subject's own `_physics_process` re-acquires
## a target on a timer (it will happily pick a nearby hostile NPC over the photographer) and then turns toward it
## with `_face_point`, so a render-frame-only pin gets overwritten between captures — measured as up to 30 deg of
## yaw wander between weapon sections, which then showed up as "aim error" that was nothing of the kind.
func _physics_process(_delta: float) -> void:
	_apply_pin()


func _process(_delta: float) -> void:
	_apply_pin()


func _apply_pin() -> void:
	# Pin the photographer. The NPC we are photographing is a live hostile standing 3 m away: left alone it
	# shoots the player, who respawns across the level, and every later frame silently becomes a long-range
	# shot of the wrong thing (the exact failure muzzle_smoke_qa_shots.gd documents). Re-asserting the
	# position AND zeroing velocity every frame also lets the "player is 4 m up" pose exist at all — there is
	# no platform up there, so without this the pose is a 2-frame fall.
	if not _pin_active:
		return
	if is_instance_valid(_player):
		_player.global_position = _pin
		if _player.get("velocity") != null:
			_player.set("velocity", Vector3.ZERO)
	# ⭐PIN THE SUBJECT TOO. This harness photographs the HOLD, not the AI: left to itself the NPC charges,
	# strafes and dodges, so every frame is taken from a different range and angle and the before/after pair
	# cannot be compared at all (measured: the subject ended 4 m from where it was placed, facing 150 deg off).
	# Freezing the body and pointing its yaw at the photographer makes the pose the ONLY variable. The arms,
	# the stance and the gun mount all still run normally — only the root transform is held.
	if is_instance_valid(_npc):
		_npc.global_position = _npc_home
		if _npc.get("velocity") != null:
			_npc.set("velocity", Vector3.ZERO)
		# ⭐AIM THE YAW FROM WHERE THE BODY ACTUALLY IS, not from where we asked it to be. A CharacterBody3D
		# placed with a wall inside its capsule is DEPENETRATED by the next move_and_slide, so `_npc_home` and
		# the real position diverge — and a yaw computed from the stale one points the subject tens of degrees
		# off the photographer while every QA_AIM number blames the feature. (Measured: 65 deg of "aim error"
		# that was entirely this.)
		var to: Vector3 = _pin - _npc.global_position
		to.y = 0.0
		if to.length() > 0.01:
			_npc.rotation.y = atan2(to.x, to.z)   # this rig's front is +Z (see NPC._face_point)
	_force_engage()


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
	# ⭐PROCESS LAST. change_scene_to_file adds the LEVEL to root AFTER this driver, so in tree order every NPC's
	# _physics_process runs after ours — and the subject's own `_face_point` then overwrites the yaw we just
	# pinned, intermittently, which reads as the gun wandering off target. Moving to the end puts our pin last.
	get_tree().root.move_child(self, -1)
	_strip_overlays()

	_player = Groups.human_player(get_tree())
	if _player == null:
		print("QA_FAIL no Player in the tree")
		get_tree().quit(1)
		return
	_eye = _player.find_child("Camera3D", true, false) as Camera3D
	if _eye == null:
		print("QA_FAIL no player Camera3D")
		get_tree().quit(1)
		return
	_npc = _find_armed_npc()
	if _npc == null:
		print("QA_FAIL no NPC in the level has a weapon hub — nothing to photograph")
		get_tree().quit(1)
		return

	# Broad daylight and a level look: the silhouette of a held gun is what is being judged, and a night
	# frame or a pitched head only makes successive runs incomparable.
	WorldClock.set_time_of_day(0.5)   # NOON: a held gun is judged by its silhouette, and a night frame hides it
	_cam = Camera3D.new()
	get_tree().root.add_child(_cam)

	# ⭐PICK AN OPEN LANE BEFORE PLACING ANYTHING. The level's authored NPC may be indoors, behind a fence or
	# in an alley, and both lenses then photograph a wall — which is indistinguishable from "the gun is not
	# being drawn". Sweep 16 headings from the player and keep the one with the most clear air, so the subject
	# stands in the open and the PROFILE lens (perpendicular to it) has room to back off.
	var home: Vector3 = _player.global_position
	var fwd := _clearest_heading(home + Vector3.UP * 0.3)
	_npc_home = home + fwd * STAND_DIST
	_npc.global_position = _npc_home
	_side_dir = Vector3(-fwd.z, 0.0, fwd.x)   # perpendicular to the player->NPC line: a true profile
	if _clearance(_npc_home + Vector3.UP * 0.3, _side_dir) < _clearance(_npc_home + Vector3.UP * 0.3, -_side_dir):
		_side_dir = -_side_dir
	_add_key_light()
	_pin = home
	_pin_active = true
	await _hold(1.2)   # let it settle onto the ground, turn, and draw

	print("QA_NPC ", _npc.name, " at ", _npc.global_position, " player ", home)
	_print_rig()

	for path in WEAPONS:
		await _weapon_section(path, home, fwd)

	await _through_wall_section(home)

	print("QA_DONE")
	get_tree().quit(0)


## Photograph ONE weapon: three elevations (level / player high / player low), each from the side (the pose
## and the barrel angle are legible only in profile) and from the front (what the player actually sees).
func _weapon_section(weapon_path: String, home: Vector3, fwd: Vector3) -> void:
	var wd: WeaponData = load(weapon_path)
	if wd == null:
		print("QA_FAIL_WEAPON missing ", weapon_path)
		return
	if not _npc.has_method(&"_on_equip_weapon_requested"):
		print("QA_FAIL_WEAPON NPC has no _on_equip_weapon_requested seam")
		return
	_npc.call(&"_on_equip_weapon_requested", wd)
	# ⭐WAIT BEFORE LOOKING. _build_weapon_mesh queue_free()s the OLD _weapon_mesh, which is still in the tree
	# this frame — reading `_weapon_mesh` right now can hand back the dead node off the previous model.
	await _frames(4)
	var tag := weapon_path.get_file().get_basename()

	for pose in [["level", 0.0], ["high", HIGH_UP], ["low", LOW_DOWN]]:
		var label: String = pose[0]
		var dy: float = pose[1]
		_pin = home + Vector3.UP * dy
		_pin_active = true
		# REAL SECONDS, not frames: the NPC has to turn (turn_speed 8), the stance has to draw, and the arms
		# ease to the hold pose over ~0.3 s on top of that. A frame count only means what you think it does at
		# a frame rate you have not measured.
		await _hold(1.6)
		_show_gun()
		await _frames(2)
		_print_geometry("%s/%s" % [tag, label])
		await _side_shot("%s_%s_side" % [tag, label])
		await _front_shot("%s_%s_front" % [tag, label])
	_pin_active = false


## ⭐THE THROUGH-WALL SHOT. A first-person `view_model` is authored to draw on ViewModelCamera.VIEW_MODEL_LAYER
## with no-depth materials, which is what keeps the PLAYER's gun from clipping into geometry — and what makes an
## NPC's copy of the same mesh composite OVER the level instead of behind it. `QA_LAYERS` catches it in numbers;
## this catches it in the frame, which is where it was actually reported from.
##
## Puts the subject on the FAR side of a real wall and photographs from the player's eye. A correct build shows
## bare wall; a broken one shows a rifle floating on it. Degrades to a printed line rather than failing the run:
## the level may simply have no wall at a usable distance from where the player spawned.
func _through_wall_section(home: Vector3) -> void:
	var eye: Vector3 = home + Vector3.UP * 0.3
	var space := _npc.get_world_3d().direct_space_state
	var best_dir := Vector3.ZERO
	var best_hit := Vector3.ZERO
	var best_d := INF
	for i in 24:
		var a := TAU * float(i) / 24.0
		var d := Vector3(sin(a), 0.0, cos(a))
		var q := PhysicsRayQueryParameters3D.create(eye, eye + d * 6.0)
		q.exclude = [_npc.get_rid(), _player.get_rid()] if _player is CollisionObject3D else [_npc.get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			continue
		var dist: float = eye.distance_to(hit["position"])
		# Near enough to frame, far enough that the NPC lands clear of the wall rather than inside it.
		if dist >= 1.6 and dist < best_d:
			best_d = dist
			best_dir = d
			best_hit = hit["position"]
	if best_dir == Vector3.ZERO:
		print("QA_WALL_SKIP no wall 1.6-6 m from the player — no through-wall shot this run")
		return
	# Stand the subject a clear body-depth beyond the wall, facing back through it.
	_npc_home = best_hit + best_dir * 1.4
	_npc.global_position = _npc_home
	_pin = home
	_pin_active = true
	await _hold(1.6)
	_show_gun()
	await _frames(2)
	var mesh := _npc.get("_weapon_mesh") as Node3D
	print("QA_WALL npc=", _npc_home, " wall_hit=", best_hit, " wall_dist=%.2f m" % best_d,
			" gun_visible_flag=", (mesh.visible if is_instance_valid(mesh) else "none"),
			" — the frame must show WALL, not a gun")
	await _lens("30_through_wall_front", _eye.global_position, _npc_home + Vector3.UP * 0.2, 45.0)
	_pin_active = false


# --- measurement -----------------------------------------------------------------------------------------

## The NPC's body rig, printed once: the numbers a reviewer needs to judge whether a gun is "the right size"
## at all. Everything is in metres, in the NPC's own local frame (its origin sits at the capsule centre).
func _print_rig() -> void:
	var swap := _swap()
	if swap == null:
		print("QA_RIG no BodyModelSwap child — this NPC has no swapped body to measure against")
		return
	var arm_l := swap.get("_arm_left") as Node3D
	var arm_r := swap.get("_arm_right") as Node3D
	print("QA_RIG arm_position=", swap.get("arm_position"), " arm_scale=", swap.get("arm_scale"),
			" arm_rotation=", swap.get("arm_rotation"), " arm_hold_pitch=", swap.get("arm_hold_pitch"),
			" arms_hold_when_drawn=", swap.get("arms_hold_when_drawn"))
	if arm_l != null:
		print("QA_RIG arm_left_global=", arm_l.global_position, " arm_right_global=",
				(arm_r.global_position if arm_r != null else Vector3.ZERO))
	print("QA_RIG npc_muzzle_offset=", _npc.get("muzzle_offset"),
			" weapon_mesh_rotation=", _npc.get("weapon_mesh_rotation"))


## The numbers that decide all three questions, printed beside every photograph.
##  * GUN LENGTH   — the rendered world AABB of the held model, so "too small / too big" stops being a vibe.
##  * HAND GAP     — distance from the gun's grip end to each hand tip: ~0 means it IS in the hands.
##  * AIM ERROR    — the angle between the barrel's world direction and the true line to the target. This is
##                   the one that catches "the bullets pitch but the model does not": it stays ~0 in the
##                   `level` pose and blows up in `high` / `low` when the model is not tracking.
func _print_geometry(tag: String) -> void:
	var mesh := _npc.get("_weapon_mesh") as Node3D
	if mesh == null or not is_instance_valid(mesh):
		print("QA_GEOM ", tag, " NO HELD MODEL (weapon has no held_view_model, or it was just freed)")
		return
	var acc: Array = []
	_world_aabb(mesh, acc)
	var size := Vector3.ZERO
	var centre := Vector3.ZERO
	if not acc.is_empty():
		size = acc[1] - acc[0]
		centre = (acc[0] + acc[1]) * 0.5
	var hands := _hand_points()
	var grip: Vector3 = mesh.global_position   # the model root sits at the grip on every rig here
	var gap_l := grip.distance_to(hands[0]) if hands.size() > 0 else -1.0
	var gap_r := grip.distance_to(hands[1]) if hands.size() > 1 else -1.0
	# ⭐THE FIST GAP. npc_held_display_scale multiplies the model's baked FORWARD OFFSET along with its size,
	# so an enlarged gun slides ahead of the hand. This is the number WeaponData.npc_hold_trim exists to
	# cancel: it is the model's bounds centre measured along the NPC's own forward, from the grip.
	var fwd_axis: Vector3 = _npc.global_transform.basis.z
	var gap: float = (centre - grip).dot(fwd_axis)
	# ⭐AND THE ONE THE TRIM IS ACTUALLY SET FROM. The AABB above is BIND-POSE for the three SKINNED models
	# (silenced, sniper_rifle, grenade_launcher) — their `centre` is fiction. The centroid of the model's mesh
	# NODE origins is skin-independent, and expressed in the HAND ANCHOR's own frame it is exactly the vector
	# WeaponData.npc_hold_trim cancels: +Z is where the barrel points, +Y is up. Read this, negate most of it,
	# author that. (Leave a little +Z: a gun's body does sit slightly forward of the fist.)
	# ⭐DOES THE HELD GUN DRAW THROUGH WALLS? These view-models are FIRST-PERSON rigs: authored on
	# ViewModelCamera.VIEW_MODEL_LAYER (4) with no-depth materials so the PLAYER's gun composites over the world
	# from its own SubViewport. Hung on an NPC unfixed, the same mesh is picked up by that same pass and drawn
	# over the level with no depth relationship to it. Every visible mesh must read layers=1 / no_depth=false.
	var bad_layer := 0
	var bad_depth := 0
	var mesh_list: Array = []
	_mesh_nodes(mesh, mesh_list)
	for n in mesh_list:
		var m := n as MeshInstance3D
		if m.has_meta(&"npc_tint_dup"):
			continue  # InkOutline's tint duplicate keeps its own layer on purpose
		if m.layers != 1:
			bad_layer += 1
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).no_depth_test:
				bad_depth += 1
	print("QA_LAYERS ", tag, " meshes=", mesh_list.size(), " off_world_layer=", bad_layer,
			" no_depth_surfaces=", bad_depth,
			("  <-- DRAWS THROUGH WALLS" if (bad_layer > 0 or bad_depth > 0) else "  ok"))
	var anchor := _npc.get("_muzzle") as Node3D
	if anchor != null and is_instance_valid(anchor):
		var nodes: Array = []
		_mesh_nodes(mesh, nodes)
		if not nodes.is_empty():
			var sum := Vector3.ZERO
			for n in nodes:
				sum += (n as Node3D).global_position
			print("QA_TRIM ", tag, " model_offset_in_anchor_frame=", anchor.to_local(sum / float(nodes.size())),
					" (negate to author npc_hold_trim)")
	print("QA_POSE ", tag, " npc=", _npc.global_position, " asked=", _npc_home,
			" drift=%.3f m" % _npc.global_position.distance_to(_npc_home),
			" yaw=%.1f deg" % rad_to_deg(_npc.rotation.y))
	print("QA_GEOM ", tag, " gun_size=", size, " longest=%.3f m" % maxf(size.x, maxf(size.y, size.z)),
			" grip=", grip, " centre=", centre, " fist_gap=%.3f m" % gap)
	# grip_to_* is hand -> the anchor, which is their own MIDPOINT, so it can never be zero for a two-handed
	# hold — it is half the span between the fists. `hand_to_gun` is the honest one: the shortest distance from
	# each hand to the weapon's rendered bounds, i.e. "is this hand actually touching the thing it is holding".
	var to_gun_l := _point_to_aabb(hands[0], acc) if (hands.size() > 0 and not acc.is_empty()) else -1.0
	var to_gun_r := _point_to_aabb(hands[1], acc) if (hands.size() > 1 and not acc.is_empty()) else -1.0
	print("QA_HANDS ", tag, " left=", (hands[0] if hands.size() > 0 else Vector3.ZERO),
			" right=", (hands[1] if hands.size() > 1 else Vector3.ZERO),
			" hand_span=%.3f m" % (hands[0].distance_to(hands[1]) if hands.size() > 1 else 0.0),
			" grip_to_left=%.3f m grip_to_right=%.3f m" % [gap_l, gap_r],
			" hand_to_gun=%.3f / %.3f m" % [to_gun_l, to_gun_r])
	# Barrel direction vs. the true line to the target. The barrel's world direction is taken from the gun's
	# own Muzzle marker when it has one (marker minus grip), else the model's forward.
	var barrel := _barrel_dir(mesh)
	var target := _aim_target()
	var origin := _muzzle_world(mesh)
	var want := (target - origin)
	var err := INF
	if want.length() > 0.01 and barrel.length() > 0.01:
		err = rad_to_deg(barrel.normalized().angle_to(want.normalized()))
	# ⭐A weapon with no "Muzzle" marker (the knife) has no measurable barrel: the fallback reads the model's own
	# -Z, which its npc_hold_rotation deliberately does not align with the aim. Print the angle but LABEL it
	# unmeasurable, so nobody reads a melee weapon's 90 deg as an aim regression.
	var has_marker := _find_named(mesh, "muzzle") != null
	# ⭐TWO ERRORS, AND THEY ANSWER DIFFERENT QUESTIONS. The aim pitch is computed at the GRIP (a stable pivot —
	# rotating the anchor cannot move its own origin), so `grip_err` is the one that grades the feature. The
	# muzzle-relative one carries the PARALLAX of a metre of barrel at this 3 m test range, which is real but
	# shrinks to a couple of degrees at the ranges NPCs actually engage at. Judge the feature on grip_err.
	var want_grip := target - grip
	var grip_err := INF
	if want_grip.length() > 0.01 and barrel.length() > 0.01:
		grip_err = rad_to_deg(barrel.normalized().angle_to(want_grip.normalized()))
	print("QA_AIM ", tag, " barrel_dir=", barrel.normalized(), " want_dir=", want.normalized(),
			" grip_err=%.1f deg muzzle_err=%.1f deg" % [grip_err, err], (" (NO Muzzle marker — not a valid aim measurement)" if not has_marker else ""),
			" muzzle=", origin, " target=", target,
			" target_dy=%.2f m" % (target.y - origin.y))


## Shortest distance from `p` to the axis-aligned box `acc` ([min, max]); 0 inside it. The honest "is the hand
## touching the weapon" measure — the bounds are the rendered model, not a marker.
func _point_to_aabb(p: Vector3, acc: Array) -> float:
	var mn: Vector3 = acc[0]
	var mx: Vector3 = acc[1]
	var d := Vector3(
			maxf(maxf(mn.x - p.x, 0.0), p.x - mx.x),
			maxf(maxf(mn.y - p.y, 0.0), p.y - mx.y),
			maxf(maxf(mn.z - p.z, 0.0), p.z - mx.z))
	return d.length()


## Every MeshInstance3D under `node`, collected into `out`. Their NODE positions are skin-independent, unlike
## the bind-pose AABBs, which is what makes them the honest input for the fist trim.
func _mesh_nodes(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		_mesh_nodes(c, out)


## World-space AABB corners of every MeshInstance3D under `node`, accumulated into `acc` as [min, max].
func _world_aabb(node: Node, acc: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var a: AABB = mi.get_aabb()
		var xf := mi.global_transform
		for i in 8:
			var p: Vector3 = xf * a.get_endpoint(i)
			if acc.is_empty():
				acc.append(p)
				acc.append(p)
			else:
				acc[0] = Vector3(minf(acc[0].x, p.x), minf(acc[0].y, p.y), minf(acc[0].z, p.z))
				acc[1] = Vector3(maxf(acc[1].x, p.x), maxf(acc[1].y, p.y), maxf(acc[1].z, p.z))
	for c in node.get_children():
		_world_aabb(c, acc)


## World positions of the NPC's two hand tips, derived the same way BodyModelSwap measures arm reach: the arm
## model pivots at its own origin (the shoulder) and its hand lies down local +Z, so the tip is the arm
## transform applied to (0, 0, reach). Returns [] when this NPC has no swapped arms.
func _hand_points() -> Array:
	var swap := _swap()
	if swap == null:
		return []
	var arm_l := swap.get("_arm_left") as Node3D
	var arm_r := swap.get("_arm_right") as Node3D
	if arm_l == null or not is_instance_valid(arm_l):
		return []
	var reach := 0.0
	if swap.has_method(&"_arm_reach_measured"):
		reach = float(swap.call(&"_arm_reach_measured"))
	var out: Array = [arm_l.global_transform * Vector3(0.0, 0.0, reach)]
	if arm_r != null and is_instance_valid(arm_r):
		out.append(arm_r.global_transform * Vector3(0.0, 0.0, reach))
	return out


## The held gun's barrel direction in world space: from the model root (the grip) to its own "Muzzle" marker
## when one exists, else the model's own forward axis. Matching what a player actually reads as "where it points".
func _barrel_dir(mesh: Node3D) -> Vector3:
	var m := _find_named(mesh, "muzzle")
	if m != null:
		var d := m.global_position - mesh.global_position
		if d.length() > 0.01:
			return d
	return -mesh.global_transform.basis.z


func _muzzle_world(mesh: Node3D) -> Vector3:
	var m := _find_named(mesh, "muzzle")
	return m.global_position if m != null else mesh.global_position


## Where the NPC believes it is aiming — its own _aim_point() when it has a target, else the player's chest.
func _aim_target() -> Vector3:
	if _npc.has_method(&"_aim_point"):
		var t = _npc.get("_target")
		if t != null and is_instance_valid(t):
			return _npc.call(&"_aim_point")
	return _eye.global_position if is_instance_valid(_eye) else Vector3.ZERO


func _swap() -> Node:
	if not is_instance_valid(_npc):
		return null
	for c in _npc.get_children():
		if c.has_method(&"character_parts"):
			return c
	return null


func _find_named(node: Node, needle: String) -> Node3D:
	if node.name.to_lower().contains(needle):
		return node as Node3D
	for c in node.get_children():
		var r := _find_named(c, needle)
		if r != null:
			return r
	return null


# --- cameras ---------------------------------------------------------------------------------------------

## PROFILE shot. The hold pose and the barrel angle only read from the side — head-on, a gun pointing 30
## degrees down looks exactly like one pointing straight at you. Picks whichever flank is not against
## geometry (a raycast from the NPC's chest), so this never photographs a wall.
func _side_shot(name: String) -> void:
	var chest: Vector3 = _npc.global_position + Vector3.UP * 0.3
	var back: float = minf(3.0, maxf(1.6, _clearance(chest, _side_dir) - 0.4))
	await _lens(name, chest + _side_dir * back + Vector3.UP * 0.25, chest, 30.0 * 3.0 / back)


## FRONT shot, from the player's own eye — the read the player actually gets in play. A zoom LENS parked at
## the eye rather than a camera moved next to the subject: an eye position can never be inside geometry.
func _front_shot(name: String) -> void:
	var chest: Vector3 = _npc.global_position + Vector3.UP * 0.2
	await _lens(name, _eye.global_position, chest, 35.0)


func _lens(name: String, from: Vector3, at: Vector3, fov: float = 32.0) -> void:
	if not is_instance_valid(_cam):
		return
	_cam.global_position = from
	if from.distance_to(at) < 0.05:
		return
	_cam.look_at(at, Vector3.UP)
	_cam.fov = fov
	_cam.near = 0.02
	var prev := get_viewport().get_camera_3d()
	_cam.current = true
	await _frames(2)
	await _shot(name)
	if is_instance_valid(prev):
		prev.current = true
	await _frames(1)


# --- plumbing (copied from muzzle_smoke_qa_shots.gd) ------------------------------------------------------

## ⭐HOLD THE NPC IN THE ENGAGED STATE, EVERY FRAME. Measured on the first run of this harness: waiting for
## the AI to notice the player produced a subject standing in PROFILE with its arms hanging (perception was
## still UNAWARE / the GOAP plan had not reached the alerted branch), and every "does the barrel point at
## you" number was therefore measuring a bystander, not an aiming enemy. Pin the target + the ALERTED state
## so the pose being photographed is the combat pose. The NPC still drives its own body — only the FACTS its
## brain reads are pinned. `state` is Perception.State.ALERTED (2); spelled numerically because this tools
## script must parse without Perception being in the global class cache.
func _force_engage() -> void:
	if not is_instance_valid(_npc) or not is_instance_valid(_player):
		return
	_npc.set("_target", _player)
	_npc.set("_target_body", _player)
	var perc = _npc.get("_perception")
	if perc != null and is_instance_valid(perc):
		perc.set("state", 2)   # Perception.State.ALERTED


## Re-assert the held gun VISIBLE. npc.gd holsters at spawn and WeaponStance re-holsters every physics frame
## while the NPC is not engaged, which hides _weapon_mesh — so a one-shot draw would be undone within two
## frames and every photograph would be of an empty hand.
func _show_gun() -> void:
	if not is_instance_valid(_npc):
		return
	var mesh = _npc.get("_weapon_mesh")
	if mesh != null and is_instance_valid(mesh):
		mesh.visible = true
	var stance = _npc.get("_stance")
	if stance != null and is_instance_valid(stance) and stance.has_method(&"_show_weapon"):
		stance.call(&"_show_weapon")


## The armed NPC to photograph: PREFER one already holding a gun, else the nearest one with a weapon hub we
## can hand a weapon to. Found by SCRIPT PATH rather than `is NPC` so this tools script never depends on
## npc.gd being in the global class cache when it parses.
func _find_armed_npc() -> Node3D:
	var origin: Vector3 = _player.global_position if _player != null else Vector3.ZERO
	var armed: Node3D = null
	var armed_d := INF
	var any: Node3D = null
	var any_d := INF
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is Node3D) or n.get_script() == null:
			continue
		if not String(n.get_script().resource_path).ends_with("/npc.gd"):
			continue
		var w = n.get("_weapon")
		if w == null:
			continue   # a civilian (weapon_data null) has no weapon hub at all — it can never hold a gun
		var d := origin.distance_to((n as Node3D).global_position)
		if d < any_d:
			any_d = d
			any = n as Node3D
		var atk = w.get("attack")
		var cw: WeaponData = atk.current_weapon if atk != null else null
		if cw != null and cw.has_muzzle_flash and d < armed_d:
			armed_d = d
			armed = n as Node3D
	if armed != null:
		print("QA_NPC_PICK ", armed.name, " already armed, d=%.1f" % armed_d)
		return armed
	if any != null:
		print("QA_NPC_PICK ", any.name, " unarmed, d=%.1f — will be handed a weapon" % any_d)
	return any


## Metres of clear air from `from` along `dir` (capped at 8 m). The subject and the player are excluded so
## the two actors never count as an obstruction.
func _clearance(from: Vector3, dir: Vector3) -> float:
	var space := _npc.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * 8.0)
	q.exclude = [_npc.get_rid(), _player.get_rid()] if _player is CollisionObject3D else [_npc.get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	return 8.0 if hit.is_empty() else from.distance_to(hit["position"])


## The horizontal heading from `from` with the most clear air — where the subject can stand in the open.
func _clearest_heading(from: Vector3) -> Vector3:
	var best := Vector3.FORWARD
	var best_d := -1.0
	for i in 16:
		var a := TAU * float(i) / 16.0
		var d := Vector3(sin(a), 0.0, cos(a))
		var c := _clearance(from, d)
		if c > best_d:
			best_d = c
			best = d
	print("QA_LANE heading=", best, " clearance=%.1f m" % best_d)
	return best


## A neutral key light on the subject. The shipped levels are lit for mood and a held gun's SILHOUETTE is
## exactly what these shots have to read; without this the before/after pair is two dark blue blobs. It is a
## harness-only node (never saved to any scene) and it is aimed, not ambient, so the frame still looks like
## the game rather than a flat unlit render.
func _add_key_light() -> void:
	var key := DirectionalLight3D.new()
	get_tree().root.add_child(key)
	key.global_position = _npc_home + Vector3.UP * 4.0
	key.look_at_from_position(_npc_home + Vector3.UP * 4.0 + _side_dir * 3.0 + Vector3.FORWARD * 2.0, _npc_home, Vector3.UP)
	key.light_energy = 1.6
	key.shadow_enabled = false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Wait REAL SECONDS while re-asserting the drawn gun every frame. Frames are the wrong unit here (a frame
## count only means what you think it does at a frame rate you have not measured), and the gun has to be
## re-shown continuously: WeaponStance re-holsters every physics frame the NPC is not engaged, which hides
## _weapon_mesh, so a one-shot draw is undone within two frames and every photograph is of an empty hand.
func _hold(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		left -= get_process_delta_time()
		_show_gun()
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path)


## Hide everything painted OVER the 3D frame — the boot sky title, the HUD, the debug tickers — so the shots
## read the NPC and not the reticle sitting on it.
func _strip_overlays() -> void:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
		elif n.name == "SkyTitle" and n is Node3D:
			(n as Node3D).visible = false
		stack.append_array(n.get_children())
