extends Node
## FIRST-PERSON WEAPON HANDS across SWAPS + HOLSTER — the probe for the 2026-09-15 report "when you swap to
## different items it messes up where your hands are". Boots the REAL game, draws the weapon, then walks the
## starting loadout weapon by weapon through the real swap path (SwapWeapons.request_equip -> Attack's swap
## down/up -> swap_finished), toggles the holster in between, and after every step — once the swap raise has
## settled — prints the hands rig's whole pose and saves a screenshot. The LAST step returns to the FIRST weapon,
## so the two "pistol" rows must match: any property that differs is state that leaked through the cycle.
##
## WHY A PROBE: the hands rig is three poses on one node whose transitions are signal-driven (holster_changed,
## swap_finished, carry_changed) AND reconciled per frame, so a leak is an ORDERING bug across several frames
## of the real Attack/GunMesh/Inventory machinery. Nothing off-tree reproduces that.
##
## Run WINDOWED from the project root (the screenshots need a renderer; the numbers print either way):
##   godot --path . res://scripts/tools/probes/__weapon_hands_swap_probe.tscn
## PNGs land in user://weapon_hands_swap/. One WHANDS line per step.
##
## Driver-copy pattern (the __respawn_viewmodel_probe.gd idiom): this scene is the boot scene, but the run
## switches current_scene to game.tscn, which frees it — so _ready re-attaches a COPY of this script on a bare
## Node parented to root, which survives the scene change and drives the probe.

const OUT_DIR := "user://weapon_hands_swap"
var _player: Node
var _fp: Node
var _swap: Node
var _attack: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "WeaponHandsSwapProbeDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()


func _run() -> void:
	await _frames(5)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(150)
	_player = Groups.human_player(get_tree())
	if _player == null:
		print("WHANDS_FAIL no Player")
		get_tree().quit(1)
		return
	_fp = _player.get("fp_body")
	var ws: Node = _player.get("weapon_system")
	_attack = ws.get("attack") if ws != null else null
	_swap = ws.get_node_or_null(^"SwapWeapons") if ws != null else null
	if _fp == null or _attack == null or _swap == null:
		print("WHANDS_FAIL fp_body=", _fp, " attack=", _attack, " swap=", _swap)
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var slots: Array = _swap.call(&"effective_slots")
	if slots.is_empty():
		# The shipped game boots unarmed and hands out weapons through the backpack, so the authored loadout is
		# empty — walk the shipped weapon set instead. Same swap path either way (SwapWeapons.request_equip).
		for f in ["pistol", "smg", "shotgun", "sniper_wep", "melee", "rock_weapon", "spray_paint", "fists"]:
			slots.append(load("res://resources/weapons/%s.tres" % f))
	print("WHANDS loadout=", slots.map(func(w): return w.resource_path.get_file()))
	# Draw whatever the player booted with, settle, baseline.
	_attack.call(&"set_holstered", false)
	await _settle()
	_report("00_boot_drawn")
	var step := 1
	for w in slots:
		_swap.call(&"request_equip", w)
		await _settle()
		_report("%02d_swap_%s" % [step, (w as Resource).resource_path.get_file().get_basename()])
		step += 1
	# Holster round-trip on the last weapon, then back to the FIRST weapon — the row that must match 01_.
	_attack.call(&"toggle_holster")
	await _settle()
	_report("%02d_holstered" % step)
	step += 1
	_attack.call(&"toggle_holster")
	await _settle()
	_report("%02d_redrawn" % step)
	step += 1
	if not slots.is_empty():
		_swap.call(&"request_equip", slots[0])
		await _settle()
		_report("%02d_back_to_first" % step)
	print("WHANDS done -> ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)


## Long enough for the swap down + raise (swap_time + swap_raise_duration) and the hands' own draw glide.
func _settle() -> void:
	var t: float = GameSettings.weapon_general.swap_time + GameSettings.weapon_general.swap_raise_duration + 0.6
	await get_tree().create_timer(t).timeout
	await _frames(3)


func _report(tag: String) -> void:
	var arms: Node3D = _fp.get("_fp_arms")
	var wd: Resource = _attack.get("current_weapon")
	var line := "WHANDS %-18s wpn=%-14s weapon_up=%s fists_up=%s holstered=%s" % [
		tag, wd.resource_path.get_file() if wd != null else "null",
		_fp.get("_weapon_hands_up"), _fp.get("_unarmed_hands_up"), _attack.get("holstered")]
	if arms != null:
		line += " | vis=%s pos=%s rot=%s scale=%.3f spread=%.3f conv=%.1f stag=%.3f stride=%.1f offhand_hidden=%s settle=%s" % [
			arms.visible, arms.position.snapped(Vector3.ONE * 0.001), arms.rotation_degrees.snapped(Vector3.ONE * 0.1),
			arms.get("arm_scale"), (arms.get("arm_position") as Vector3).x, arms.get("arm_converge_deg"),
			arms.get("arm_stagger"), arms.get("arm_stride_deg"), arms.get("hide_offhand"),
			(_fp.get("_weapon_hands_settle") as Vector3).snapped(Vector3.ONE * 0.001)]
	# THE number that answers "is the hand ON the weapon": the solved grip point (the hands' own
	# weapon_grip_position, carried to world) against the mounted model's world bounds. 0 = touching.
	var gun: Node3D = _player.get("gun_mesh")
	if arms != null and gun != null and arms.has_method(&"weapon_grip_position"):
		var grip_local: Variant = arms.call(&"weapon_grip_position")
		var swapper: Variant = gun.get("_swapper")
		var model: Node = swapper.call(&"current_model") if swapper != null else null
		if grip_local is Vector3 and is_instance_valid(model):
			var grip_world: Vector3 = arms.global_transform * (grip_local as Vector3)
			var box := _world_aabb(model)
			var nearest := grip_world.clamp(box.position, box.end)
			line += " | grip_world=%s gun_box=%s..%s hand_to_gun=%.3f gun_pitch=%.1f" % [
				grip_world.snapped(Vector3.ONE * 0.001), box.position.snapped(Vector3.ONE * 0.01),
				box.end.snapped(Vector3.ONE * 0.01), grip_world.distance_to(nearest),
				gun.rotation_degrees.x]
	# Framing diagnostics: where the gun rig sits RELATIVE TO THE CAMERA right now (the probe renders it at the
	# authored camera_rig.tscn mount, (0.187, -0.202, 0)), the two FOVs, and the viewport sizes — anything that
	# differs from the framing probe is why the two disagree on screen.
	var cam: Camera3D = _player.get("camera_effects")
	if gun != null and cam != null:
		var rel: Vector3 = cam.global_transform.affine_inverse() * gun.global_position
		var vmc: Node = cam.get_node_or_null(^"../../../UI/ViewModelComposite")
		var gun_cam: Variant = null
		for c in get_tree().root.find_children("*", "Camera3D", true, false):
			if c != cam and (c as Camera3D).current == false and c.get_parent() is SubViewport:
				gun_cam = c
		line += " | gun_rel_cam=%s gun_local=%s recoil_pos=%s main_fov=%.1f gun_cam_fov=%s root_vp=%s gun_vp=%s" % [
			rel.snapped(Vector3.ONE * 0.001), gun.position.snapped(Vector3.ONE * 0.001),
			(gun.get("_recoil_pos") as Vector3).snapped(Vector3.ONE * 0.001), cam.fov,
			("%.1f" % (gun_cam as Camera3D).fov) if gun_cam != null else "?",
			get_viewport().get_visible_rect().size,
			(gun_cam.get_parent() as SubViewport).size if gun_cam != null else "?"]
	print(line)
	if DisplayServer.get_name() != "headless":
		var img := get_viewport().get_texture().get_image()
		img.save_png(OUT_DIR + "/" + tag + ".png")


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## World-space bounds of every mesh under `node` (the mounted view model).
static func _world_aabb(node: Node) -> AABB:
	var out := AABB()
	var seeded := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and not node.has_meta(&"npc_tint_dup"):
		var xf: Transform3D = (node as MeshInstance3D).global_transform
		var local: AABB = (node as MeshInstance3D).get_aabb()
		for i in 8:
			var p: Vector3 = xf * local.get_endpoint(i)
			out = AABB(p, Vector3.ZERO) if not seeded else out.expand(p)
			seeded = true
	for c in node.get_children():
		var sub := _world_aabb(c)
		if sub.size == Vector3.ZERO and sub.position == Vector3.ZERO:
			continue
		out = sub if not seeded else out.merge(sub)
		seeded = true
	return out
