extends Node
## Muzzle-smoke QA screenshot harness — boots the REAL game, fires the equipped weapon's muzzle-FX signal,
## and photographs the barrel over the life of the trail so the effect can be judged BY EYE.
##
## WHY: "the smoke doesn't look good" is a LOOK bug and no unit test in this suite can see it — --headless
## never compiles a particle shader at all, so every property can round-trip perfectly and still render as
## garbage. This is the only honest verification, and it is what should have been run before shipping v1.
##
## Run from the project root as a REAL WINDOWED RUN — not --headless, the GPU must render:
##   godot --path . res://scripts/tools/muzzle_smoke_qa_shots.tscn -- --shots-dir="C:/some/dir"
## Without --shots-dir it writes to user://muzzle_smoke_qa_shots. Prints one QA_SHOT per capture.
##
## Driver-copy pattern, copied from flashlight_qa_shots.gd: this scene is the boot scene, but the run switches
## current_scene to game.tscn (which frees the current scene), so _ready re-attaches a COPY of this script on
## a bare Node parented to root, which survives the change and drives the run.
##
## (*) NEVER call a Settings.set_* here — those setters call save_settings() and would rewrite the developer's
## real user://settings.cfg. Read the live values, never write them.

## The gun the NPC section puts in an unarmed NPC's hand — the same .tres the player half equips above, so
## both halves of the run photograph the SAME weapon and any difference between them is the RIG, not the gun.
const NPC_PISTOL_PATH := "res://resources/weapons/pistol.tres"

var _dir := "user://muzzle_smoke_qa_shots"
var _smoke: GPUParticles3D = null
var _attack: Node = null
var _eye: Camera3D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "MuzzleSmokeQaDriver"
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
	_smoke = player.find_child("MuzzleSmoke", true, false) as GPUParticles3D
	var cam := player.find_child("Camera3D", true, false) as Camera3D
	_eye = cam
	if _smoke == null or cam == null:
		print("QA_FAIL smoke=", _smoke, " cam=", cam)
		get_tree().quit(1)
		return
	if player.get("weapon_system") != null:
		_attack = player.weapon_system.attack
		_attack.set_holstered(false)
	# The gun begins HOLSTERED and the draw is a tween behind a lock that can refuse — so wait for it and then
	# SAY whether it is actually out. A shot of an empty corner is not evidence that the smoke is broken.
	await _frames(90)
	var gun := player.find_child("GunMesh", true, false) as Node3D
	# ⭐EQUIP A GUN FIRST. The player spawns holding FISTS, whose has_muzzle_flash is false — so the smoke gate
	# correctly refuses and every shot photographs an empty barrel. A QA pass that skips this step is measuring
	# the gate, not the effect.
	var inv = player.weapon_system.inventory if player.get("weapon_system") != null else null
	if inv != null:
		inv.equip(load("res://resources/weapons/pistol.tres"))
		await _wait(1.5)   # the swap dip + re-draw is a tween; shooting mid-swap fires from a stowed muzzle
		# inventory.equip() only fires weapon_changed — the VIEW MODEL is re-instantiated on Attack.swap_finished,
		# which a direct equip never emits, so the rig would still be showing the fists and the muzzle marker
		# would still be the fists'. Ask the gun rig to re-equip its model directly.
		var gm := player.find_child("GunMesh", true, false)
		if gm != null and gm.has_method("_equip_view_model"):
			gm.call("_equip_view_model")
			await _wait(0.6)
	var wd = inv.equipped_weapon if inv != null else null
	print("QA_WEAPON ", (wd.resource_path if wd != null else "NONE"),
			" has_muzzle_flash=", (wd.has_muzzle_flash if wd != null else "?"),
			" muzzle_smoke_scale=", (wd.get("muzzle_smoke_scale") if wd != null else "?"),
			" player_dial=", Settings.muzzle_smoke_scale)
	print("QA_FPS ", Engine.get_frames_per_second())
	print("QA_VIEWMODEL restored=", _restore_view_model(), " main_cull_mask=", cam.cull_mask)
	print("QA_DRAW holstered=", (_attack.holstered if _attack != null else "?"),
			" gun_visible=", (gun.visible if gun != null else "?"),
			" muzzle_on_screen=", cam.unproject_position(_smoke.global_position),
			" in_front=", not cam.is_position_behind(_smoke.global_position))

	# Broad daylight: white smoke against a bright world is the hard case, and the one most likely to read
	# as a flat blob. Shot 09 repeats the best pose at night for the other half of the range.
	WorldClock.set_time_of_day(0.35)
	await _frames(10)
	# ⭐AIM AT THE SKY FOR THE DIAGNOSTIC BURST. Two different runs of this harness photographed two completely
	# different backdrops (a rooftop against open sky, then a fenced yard of dark brick) because the player does
	# not spawn in the same place every run — and white smoke judged against a dark ground reads nothing like the
	# same smoke against a bright sky, so successive tuning passes were not comparable at all. Pitching the look
	# UP puts the muzzle above the eye, which makes the diagnostic lens shoot upward into open sky: one uniform,
	# repeatable, worst-case-bright backdrop, and the SHAPE of the column is legible against it. The shipped-frame
	# and walking shots put the pitch back to level, so the honest first-person read is still photographed.
	_pose(32.0)
	await _frames(10)
	print("QA_POSE player=", player.global_position, " yaw=", rad_to_deg(player.rotation.y),
			" muzzle=", _smoke.global_position, " muzzle_above_eye=", _smoke.global_position.y - cam.global_position.y)

	print("QA_SMOKE path=", player.get_path_to(_smoke), " amount=", _smoke.amount, " life=", _smoke.lifetime,
			" fixed_fps=", _smoke.fixed_fps, " draw_order=", _smoke.draw_order, " local=", _smoke.local_coords)
	print("QA_DIST muzzle_to_eye=", _smoke.global_position.distance_to(cam.global_position),
			" muzzle=", _smoke.global_position, " eye=", cam.global_position)
	var pm := _smoke.process_material as ParticleProcessMaterial
	print("QA_INHERIT inherit_velocity_ratio=", pm.inherit_velocity_ratio, " amount_ratio=", _smoke.amount_ratio)
	print("QA_SHAPE angle=", pm.angle_min, "..", pm.angle_max, " quad=", _smoke.draw_pass_1.size,
			" grav=", pm.gravity, " life=", _smoke.lifetime, " amount=", _smoke.amount)
	print("QA_PROC color=", pm.color, " scale=", pm.scale_min, "..", pm.scale_max, " v=", pm.initial_velocity_min, "..", pm.initial_velocity_max)

	await _shot("01_eye_idle")

	# --- A DIAGNOSTIC camera parked beside the barrel. The first-person framing puts the muzzle in the
	# bottom corner at ~40 cm, which is the shipped read but a terrible one to JUDGE the effect from; this
	# one looks straight at the smoke from 0.75 m so its shape, density and edges are actually legible.
	var side := Camera3D.new()
	get_tree().root.add_child(side)

	# --- The life of one burst, from the eye and from the side.
	# ⭐The first shot is the DELAY check: a few frames after the bang the barrel must still be CLEAN. Smoke in
	# this frame means the delay is not working and the effect will read as part of the muzzle flash again.
	# ⭐The ONSET is what gets judged here, so photograph it densely. Frame 1 must still be clean (the delay),
	# and the frames after it must show the smoke SWELLING rather than a cluster appearing all at once.
	# The ONSET shots keep the OLD tight lens (fov 20, aimed just off the barrel): for the first ~0.15 s the smoke
	# genuinely is a wisp at the muzzle, and that is the frame where the delay and the swell are judged.
	# Everything from 0.30 s on uses the WIDE default framing, because by then the column is climbing out of a
	# tight lens entirely — and the SHAPE of that column is the whole point of this pass.
	# ⭐Each moment is now its OWN burst — see _burst for why photographing six moments of one burst lied.
	await _burst("02a_onset_t0_03", 0.03)
	await _burst("02b_onset_zoom_t0_03", 0.03, side, 20.0, 0.03)
	await _burst("02c_onset_zoom_t0_08", 0.08, side, 20.0, 0.03)
	await _burst("02d_onset_zoom_t0_15", 0.15, side, 20.0, 0.03)
	await _burst("03_eye_t0_30", 0.30)
	await _burst("04_side_t0_30", 0.30, side)
	await _burst("05_eye_t0_60", 0.60)
	await _burst("06_side_t0_60", 0.60, side)
	await _burst("06b_side_t0_90", 0.90, side)
	# ⭐The column is still GROWING at 1.1 s now that the smoke outlives the old 0.75 s lifetime, so the frame
	# that shows the wave at its FULL height is a late one. Without these the tallest, waviest instant of the
	# whole effect never gets photographed and the shape gets tuned from a half-built column.
	await _burst("07_side_t1_10", 1.10, side)
	await _burst("07b_eye_t1_50", 1.50)
	await _burst("07c_side_t1_50", 1.50, side)
	await _burst("07d_side_t2_00", 2.00, side)
	await _shot("08_eye_spent")

	# --- THE TRAIL. Sustained fire while sweeping the aim, which is the whole point of a world-space
	# emitter: the smoke made a moment ago must stay where it was made.
	var swept := 0.0
	while swept < 0.9:
		player.rotate_y(deg_to_rad(-70.0) * get_process_delta_time())
		_fire(1)
		swept += get_process_delta_time()
		await get_tree().process_frame
	await _wait(0.1)
	await _shot("09_eye_trail_turning")
	await _side(side, "10_side_trail_turning")

	# --- WALKING FORWARD while firing. World-space particles are left behind the moment the shooter moves, so
	# "shoot while advancing and you never see it" is the default behaviour, not a bug you can tune away with
	# opacity. inherit_velocity_ratio is what carries the puffs along with the muzzle; this is the shot that
	# says whether it is enough. Position is driven directly rather than through input — the harness is
	# photographing the FX, and a movement key would drag in stamina, bhop and the whole locomotion stack.
	await _wait(2.0)
	_pose(0.0)   # back to a LEVEL look: from here on the shots are the honest first-person read, not a diagnostic
	var walked := 0.0
	while walked < 0.85:
		var d := get_process_delta_time()
		player.global_position += -player.global_transform.basis.z * 3.2 * d
		if walked < 0.40:
			_fire(1)
		walked += d
		if walked > 0.45 and walked - d <= 0.45:
			await _shot("13_walking_forward_t0_45")
		await get_tree().process_frame
	await _shot("14_walking_forward_t0_85")

	# --- Night, so the white reads against a dark world instead of a bright one.
	WorldClock.set_time_of_day(0.95)
	await _frames(20)
	_fire(4)
	await _wait(0.35)
	await _side(side, "11_side_night")

	# --- THE SHIPPED FRAME: back through the real post-process chain (posterize + Bayer dither + grain),
	# which is what the player actually looks through and can eat a soft gradient alive.
	WorldClock.set_time_of_day(0.35)
	if _restore_post_process():
		print("QA_POST post-process layer restored")
	else:
		print("QA_POST_FAIL no post-process CanvasLayer found — shot 11 is still a raw grab")
	await _frames(20)
	_fire(3)
	await _wait(0.45)
	await _shot("12_shipped_frame_post_process")

	# --- CONTROL. Absurdly large and fully opaque. If THIS frame is empty the emitter is not drawing at all
	# and no amount of tuning will ever help; if it is a wall of white, the pipeline is fine and the shipped
	# numbers are simply too faint. Every "it looks wrong" pass needs this shot before it retunes anything.
	var cpm := _smoke.process_material as ParticleProcessMaterial
	cpm.color = Color(1, 1, 1, 1)
	cpm.scale_min = 0.35
	cpm.scale_max = 0.5
	_fire(1)
	await _wait(0.3)
	print("QA_CTRL aabb=", _smoke.get_aabb(), " vis_aabb=", _smoke.visibility_aabb, " visible=", _smoke.visible,
			" layers=", _smoke.layers, " amount_ratio=", _smoke.amount_ratio, " emitting=", _smoke.emitting)
	await _shot("12_control_huge_opaque_eye")
	await _side(side, "13_control_huge_opaque_zoom")

	# --- ⭐THE OTHER BARREL. Every shot above is the PLAYER's rig, whose MuzzleSmoke is an AUTHORED child of
	# view_model.tscn at Sketchfab_Scene/PlayerMuzzle — a Marker3D scaled 999.99994 for the sole purpose of
	# CANCELLING the 0.001 the Sketchfab rig bakes into its root, so that emitter lives at global scale ~1.0.
	# An NPC's smoke is built in CODE (npc.gd _build_muzzle_fx) under the HELD GUN'S OWN "Muzzle" marker, and
	# for a long time nothing cancelled anything on that path. local_coords is TRUE on this emitter, so the
	# node's global scale multiplies the DRAWN puff — while pm.scale_min/max round-trip a perfect 0.026..0.042
	# either way. That is exactly why no test in this suite ever caught it. So this section prints the
	# TRANSFORM beside the material and photographs the result.
	await _npc_smoke_shots(side)

	print("QA_DONE")
	get_tree().quit(0)


## Fire the muzzle-FX signal `n` times, one per frame. Deliberately the SIGNAL and not the trigger: this
## harness is photographing the FX, and going through Attack.attack() would drag in ammo, cadence, the fire
## timer and the draw gate, any of which could silently swallow the shot and make an empty frame read as
## "the smoke is broken".
func _fire(n: int) -> void:
	if _attack == null:
		return
	for i in n:
		_attack.flash_muzzle.emit()


## ⭐⭐ONE PHOTOGRAPH PER BURST, AND THE REASON IS NOT TIDINESS — photographing several moments of a SINGLE
## burst actively lies about the effect. Saving a 1280x720 PNG blocks the main thread for a good fraction of a
## second, and Godot hands that stall straight to the next frame as `delta`. MuzzleSmoke counts its delay, hold
## and taper in `delta` (deliberately, so they pause with the tree), so every screenshot FAST-FORWARDS the
## effect being photographed. Measured: with six captures inside one burst the barrel stopped emitting at a
## wall-clock 0.30 s against an authored 0.85 s hold, so every later frame showed a strand whose base had
## already been cut off and drifted away — a detached fragment the player never actually sees. The earlier
## "wait in REAL SECONDS, not frames" note is the same trap from the other side: here real seconds are honest
## and the GAME's clock is the one being distorted.
##
## So: settle first (spending the previous save's stalled frame while nothing is armed), fire, wait, take
## exactly ONE picture, then let the strand die completely before the next burst.
##  `at`      seconds after the bang to photograph.
##  `side`    pass the diagnostic camera for a zoom/framed shot; null for the plain first-person eye shot.
func _burst(name: String, at: float, side: Camera3D = null, fov: float = 40.0, aim_up: float = 0.10) -> void:
	await _frames(6)
	_fire(3)
	await _wait(at)
	if side != null:
		await _side(side, name, fov, aim_up)
	else:
		await _shot(name)
	await _wait(2.4)   # hold + lifetime + slack, so the next burst starts from a genuinely clean barrel


## ⭐PHOTOGRAPH AN NPC'S BARREL, NOT THE PLAYER'S. The two rigs build their muzzle FX by completely different
## routes — the player's is AUTHORED into view_model.tscn under a marker that deliberately cancels the model's
## baked scale, the NPC's is built in CODE under the held gun's own marker — so a green player shot says
## nothing at all about the NPC. Walks the player up to a level-authored armed NPC, fires that NPC's muzzle-FX
## signal, and shoots the result through the same eye-anchored zoom lens the player half uses.
##
## ⭐Degrades to a printed QA_FAIL_NPC and a plain `return` rather than quit(1): the player shots above are the
## primary evidence and QA_DONE must still print, so a level authored with no armed NPC costs a section, not a run.
func _npc_smoke_shots(side: Camera3D) -> void:
	var player: Node3D = Groups.human_player(get_tree())
	if player == null:
		print("QA_FAIL_NPC no Player — cannot frame an NPC muzzle from the eye")
		return
	var npc: Node3D = _find_armed_npc()
	if npc == null:
		print("QA_FAIL_NPC no NPC in the level has a weapon hub — no NPC smoke shots this run")
		return

	# Make sure it is holding a GUN. A level NPC on melee.tres builds a MuzzleSmoke but has_muzzle_flash is
	# false, so puff_scale() returns 0 and the barrel correctly refuses — photographing that measures the gate,
	# not the effect (the same trap the player half calls out at "⭐EQUIP A GUN FIRST").
	var w = npc.get("_weapon")
	var atk = w.get("attack") if w != null else null
	if atk == null:
		print("QA_FAIL_NPC ", npc.name, " has no Attack — no NPC smoke shots this run")
		return
	var wd: WeaponData = atk.current_weapon
	if wd == null or not wd.has_muzzle_flash:
		if npc.has_method(&"_on_equip_weapon_requested"):
			# The ONE seam that equips AND rebuilds the hand model + its muzzle FX. Unlike the player's
			# Inventory.equip this needs no _equip_view_model() follow-up — _build_weapon_mesh runs inside it
			# and ends in _build_muzzle_fx.
			npc.call(&"_on_equip_weapon_requested", load(NPC_PISTOL_PATH))
			# ⭐WAIT BEFORE LOOKING. _build_weapon_mesh queue_free()s the OLD _weapon_mesh, which is still in the
			# tree this frame — find_child("MuzzleSmoke") right now returns the DEAD emitter off the old model.
			await _frames(3)
			wd = atk.current_weapon
		if wd == null or not wd.has_muzzle_flash:
			print("QA_FAIL_NPC ", npc.name, " could not be given a gun (weapon=",
					(wd.resource_path if wd != null else "NONE"), ") — no NPC smoke shots this run")
			return

	# Walk the PLAYER to the NPC rather than flying a camera to it. ⭐The lens below sits exactly at the
	# player's eye, and a camera parked beside a subject ends up INSIDE geometry — this harness already ate
	# that once ("Parking it 0.75 m to the side photographed a wall"). Approach along the direction we are
	# ALREADY on, so we arrive on the open side the NPC was authored facing.
	var home := player.global_position
	var to_p := home - npc.global_position
	to_p.y = 0.0
	if to_p.length_squared() < 0.01:
		to_p = Vector3.FORWARD
	var stand := npc.global_position + to_p.normalized() * 2.2 + Vector3.UP * 0.1
	player.global_position = stand
	_pose(0.0)          # level look; the lens re-aims itself, and a pitched head only skews the eye position
	await _frames(14)   # physics grounds the player; the NPC notices — the "!" popup over its head is a FEATURE

	# Get the gun OUT. npc.gd holsters at spawn and WeaponStance re-holsters every physics frame once the
	# stand-down timer is spent, so this is re-asserted before every capture below — a one-shot draw here
	# would be undone within two frames and every photograph would be of an empty hand.
	_npc_show_gun(npc)
	await _frames(2)

	var smoke := npc.find_child("MuzzleSmoke", true, false) as GPUParticles3D
	if smoke == null:
		print("QA_FAIL_NPC ", npc.name, " built no MuzzleSmoke (weapon=", wd.resource_path,
				") — no NPC smoke shots this run")
		player.global_position = home
		return

	# ⭐⭐THE NUMBER THAT DECIDES IT. The material is innocent on both rigs; the TRANSFORM is where they
	# diverge, and a still photograph cannot tell "mis-tuned" from "crushed by its parent". Print the emitter's
	# global scale, the anchor it inherited it from, and the player's for a side-by-side ratio. Before the fix
	# this read 0.00175 against the player's 1.0 (ratio 571); it must now read ~1.0 and ratio ~1.
	var anchor := smoke.get_parent() as Node3D
	var g: Vector3 = smoke.global_transform.basis.get_scale()
	var a: Vector3 = anchor.global_transform.basis.get_scale() if anchor != null else Vector3.ONE
	var p: Vector3 = _smoke.global_transform.basis.get_scale() if is_instance_valid(_smoke) else Vector3.ONE
	var npm := smoke.process_material as ParticleProcessMaterial
	print("QA_NPC_SMOKE npc=", npc.name, " weapon=", wd.resource_path,
			" npc_held_display_scale=", wd.npc_held_display_scale, " npc_hold_override=", wd.npc_hold_override)
	print("QA_NPC_SCALE global=", g, " local=", smoke.scale,
			" anchor=", (anchor.name if anchor != null else "NONE"), " anchor_global=", a,
			" player_global=", p, " ratio_player_over_npc=", (p.x / g.x if g.x > 0.0 else INF))
	print("QA_NPC_PROC scale=", npm.scale_min, "..", npm.scale_max,
			" DRAWN_puff_m=", npm.scale_min * g.x, "..", npm.scale_max * g.x,
			" local_coords=", smoke.local_coords, " amount=", smoke.amount, " life=", smoke.lifetime)

	# Fire the SIGNAL, exactly as _fire does for the player: Attack.attack() would drag in ammo, cadence, the
	# fire timer and the holster gate, any of which could swallow the shot and make an empty frame read as
	# "the NPC smoke is broken" when it is really "the NPC never fired".
	# 0.30 s and 0.60 s mirror shots 03..06 so the two rigs are compared at the SAME instant of the burst.
	for moment in [0.30, 0.60, 1.10]:
		# ⭐RE-PLANT THE PHOTOGRAPHER EVERY BURST, for the same reason the gun is re-shown every burst. This NPC
		# is a hostile raider standing 2.2 m away and the waits below are seconds long, so it simply shoots the
		# player — who then respawns across the level. Measured on the first run: the t=1.10 capture was taken
		# from 44 m away and photographed nothing, while the 0.30/0.60 ones (1.8 m / 1.4 m) were fine. Without
		# this the LATE shots of the burst silently become long-range shots of the wrong thing.
		player.global_position = stand
		await _frames(6)
		_npc_show_gun(npc)
		atk.flash_muzzle.emit()
		atk.flash_muzzle.emit()
		atk.flash_muzzle.emit()
		await _wait(moment)
		if not is_instance_valid(smoke):
			print("QA_FAIL_NPC the NPC's MuzzleSmoke was freed mid-burst (re-equip? death?) — section aborted")
			break
		_npc_show_gun(npc)
		var name_t := "20_npc_t%s" % String.num(moment, 2).replace(".", "_")
		# WIDE first (the whole figure, so the gun is provably in frame), then TIGHT on the barrel. Both are
		# needed: at NPC scale a wide frame proves nothing, and a tight frame of nothing proves nothing either.
		await _lens(side, name_t + "_wide", smoke.global_position, 40.0, 0.25)
		await _lens(side, name_t + "_tight", smoke.global_position, 12.0, 0.05)
		var d_eye := smoke.global_position.distance_to(_eye.global_position)
		print("QA_NPC_SHOT t=", moment, " emitting=", smoke.emitting, " amount_ratio=", smoke.amount_ratio,
				" muzzle=", smoke.global_position, " dist_to_eye=", d_eye)
		# ⭐SAY SO WHEN THE SHOT IS WORTHLESS. Re-planting the player at the top of the burst is not always
		# enough: this NPC is hostile and at 2.2 m it can kill the player mid-wait, which respawns them across
		# the level — measured at 44 m for the 1.10 s capture. The lens still aims at the muzzle and still
		# produces a perfectly plausible-looking PNG of a distant figure, so without this line a long-range
		# frame of nothing is indistinguishable from an emitter that failed. Never let the harness imply it
		# photographed something it did not.
		if d_eye > 4.0:
			print("QA_NPC_FARSHOT t=", moment, " taken from ", d_eye,
					" m — the player was killed and respawned mid-wait; this frame is NOT evidence")
		await _wait(2.4)   # let the strand die completely — same reason _burst waits (see its doc)

	# CONTROL, the NPC half of the player's huge-and-opaque shot: if this frame is EMPTY the emitter is not
	# drawing at NPC scale at all; if it is a wall of white the pipeline is fine and the shipped numbers are
	# simply being crushed by the node transform. ⭐Before the fix even THIS stayed empty — at scale_max 0.5 the
	# drawn puff was still only 0.875 mm — which is exactly what distinguishes "crushed" from "not emitting".
	npm.color = Color(1, 1, 1, 1)
	npm.scale_min = 0.35
	npm.scale_max = 0.5
	player.global_position = stand
	await _frames(6)
	_npc_show_gun(npc)
	atk.flash_muzzle.emit()
	await _wait(0.35)
	await _lens(side, "21_npc_control_huge_opaque", smoke.global_position, 40.0, 0.25)

	player.global_position = home   # put the player back exactly where the run left it
	await _frames(6)


## The armed NPC to photograph: PREFER one already holding a gun, else the nearest one with a weapon hub we
## can hand a pistol to. Found by SCRIPT PATH rather than `is NPC` so this tools script never depends on
## npc.gd being in the global class cache when it parses.
func _find_armed_npc() -> Node3D:
	var player: Node3D = Groups.human_player(get_tree())
	var origin: Vector3 = player.global_position if player != null else Vector3.ZERO
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
		print("QA_NPC_PICK ", any.name, " unarmed, d=%.1f — will be handed the pistol" % any_d)
	return any


## Re-assert the held gun VISIBLE. Called before every capture, not once: npc.gd holsters at spawn and
## WeaponStance re-holsters every physics frame while the NPC is not engaged, which hides _weapon_mesh — and
## the muzzle FX are CHILDREN of that mesh, so a hidden gun photographs as a hidden plume regardless of what
## the emitter is doing. Does NOT unholster the Attack: this harness fires the signal directly, so the holster
## gate is irrelevant, and leaving it holstered keeps the NPC from actually shooting the photographer.
func _npc_show_gun(npc: Node3D) -> void:
	if not is_instance_valid(npc):
		return
	var mesh = npc.get("_weapon_mesh")
	if mesh != null and is_instance_valid(mesh):
		mesh.visible = true


## _side()'s point-aimed twin: the same eye-anchored ZOOM LENS, but centred on an ARBITRARY world point
## instead of on the player's own _smoke. Everything in _side's doc applies — most of all that this sits at
## the player's eye rather than beside the subject, because an eye position can never be inside geometry.
##  `at`     the world point to centre on (an NPC's muzzle).
##  `aim_up` metres ABOVE it, in WORLD up, so a rising column is centred rather than its base.
func _lens(cam: Camera3D, name: String, at: Vector3, fov: float, aim_up: float) -> void:
	var eye := _eye_cam()
	if eye == null or cam == null:
		return
	cam.global_position = eye.global_position
	cam.look_at(at + Vector3.UP * aim_up, Vector3.UP)
	cam.fov = fov
	cam.near = 0.02
	var prev := get_viewport().get_camera_3d()
	cam.current = true
	await _frames(2)
	print("QA_LENS ", name, " fov=", fov, " sp=", cam.unproject_position(at),
			" in_front=", not cam.is_position_behind(at))
	await _shot(name)
	if is_instance_valid(prev):
		prev.current = true
	await _frames(1)


## Pin the look PITCH so successive runs are comparable. `Head` owns the camera pitch in this rig (the body owns
## yaw) — see dialogue_controller.gd, which tweens "rotation:x" on the same node. Nothing here touches yaw: once
## the look is pitched up the backdrop is open sky whichever way the player happens to be facing, which is the
## whole point. Degrees, + = up.
func _pose(pitch_deg: float) -> void:
	var player: Node3D = Groups.human_player(get_tree())
	if player == null:
		return
	var head := player.find_child("Head", true, false) as Node3D
	if head == null:
		print("QA_POSE_FAIL no Head node — pitch not pinned, shots are not comparable between runs")
		return
	head.rotation.x = deg_to_rad(pitch_deg)


## Shoot the SAME moment from the diagnostic camera beside the barrel, then hand the viewport straight back
## to the player's eye. Re-aimed on every call because the muzzle moves — the emitter is a child of the gun.
## The PLAYER's camera — cached at the start, because the diagnostic camera steals `current` and
## get_viewport().get_camera_3d() would then return the wrong one.
func _eye_cam() -> Camera3D:
	return _eye


## ⭐THE LENS MUST FRAME THE WHOLE COLUMN, AND AT THIS RANGE THAT IS NOT A TIGHT ZOOM. The muzzle sits only
## ~0.41 m from the eye (see QA_DIST), so angular size is brutal: at fov 20 the frame is just
## 2 * 0.41 * tan(10 deg) = 0.14 m tall. That was fine while the smoke was a 10 cm clump at the barrel, but a
## RISING COLUMN is metres of screen — a 0.20 m column subtends ~26 deg from the eye — and the old lens
## silently cropped everything above the first few centimetres, which photographs as "the smoke is still a
## little ball" no matter what the emitter is actually doing. So the default framing is now wide enough for the
## whole column and AIMED AT ITS MIDDLE rather than at the muzzle; pass a tighter fov/aim for onset detail,
## when the wisp really is still at the barrel.
##  `fov`    vertical FOV in degrees (Godot keeps HEIGHT by default, so this is the vertical angle).
##  `aim_up` metres ABOVE the muzzle to centre on, in WORLD up — the column rises in world up, not along the barrel.
func _side(cam: Camera3D, name: String, fov: float = 40.0, aim_up: float = 0.10) -> void:
	if not is_instance_valid(_smoke):
		return
	var eye := _eye_cam()
	if eye == null:
		return
	var m := _smoke.global_position
	# A ZOOM LENS, not a repositioned camera: sit exactly where the player's eye is (which can never be inside
	# geometry) and narrow the FOV onto the muzzle. Parking it 0.75 m to the side photographed a wall.
	cam.global_position = eye.global_position
	cam.look_at(m + Vector3.UP * aim_up, Vector3.UP)
	cam.fov = fov
	cam.near = 0.02
	var prev := get_viewport().get_camera_3d()
	cam.current = true
	await _frames(2)
	await _shot(name)
	if is_instance_valid(prev):
		prev.current = true
	await _frames(1)


## Wait REAL SECONDS, not frames. The whole point of these shots is to land inside a 0.55 s emission
## window, and a frame count only means what you think it does at a frame rate you have not measured —
## at 20 fps "await _frames(20)" is 1.0 s and lands past the end of the burst, photographing nothing.
func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		left -= get_process_delta_time()
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := _dir.path_join(name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	var live := "?"
	if is_instance_valid(_smoke):
		# ⭐Print the three vectors MuzzleSmoke._drive_wave writes every frame, because a still photograph cannot
		# tell "the curl is mis-tuned" apart from "the script is not driving the material at all". `off` is the
		# swept birth offset that DRAWS the wave (it must be non-zero and changing between shots), and `grav`
		# must point at world up (0,1,0)-ish in LOCAL space however the gun is held — if it reads (0,1,0) while
		# the player is pitched up, the re-aim is not running and the column will lean with the barrel.
		var pm := _smoke.process_material as ParticleProcessMaterial
		live = "emitting=%s alpha=%.3f off=%.4f,%.4f,%.4f grav=%.3f,%.3f,%.3f" % [
				_smoke.emitting, pm.color.a,
				pm.emission_shape_offset.x, pm.emission_shape_offset.y, pm.emission_shape_offset.z,
				pm.gravity.x, pm.gravity.y, pm.gravity.z]
	print("QA_SHOT " if err == OK else "QA_SHOT_FAIL ", path, "  ", live)


## Hide everything painted OVER the 3D frame — the boot sky title, the HUD, the debug tickers — so the shots
## read the barrel and not the reticle sitting on it. The last pass turns the post-process layer back on.
func _strip_overlays() -> void:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
		elif n.name == "SkyTitle" and n is Node3D:
			(n as Node3D).visible = false
		stack.append_array(n.get_children())


## Turn the POST-PROCESS layer back on and nothing else — found by walking for the shader rather than by node
## name, so renaming the HUD cannot silently turn the check off. Copied from flashlight_qa_shots.gd.
## Put the WEAPON back in frame. The main camera's cull_mask has the view-model layer (bit 3) REMOVED, so
## the gun is not drawn by the world pass at all — it is rendered in its own SubViewport and composited by a
## `ViewModelComposite` container living on the HUD CanvasLayer, which _strip_overlays() has just hidden.
## Without this the shots show smoke floating in mid-air beside an invisible gun, which is not the frame the
## player sees. Shows that layer again and hides only its OTHER children, so the reticle and panel stay off.
func _restore_view_model() -> bool:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == "ViewModelComposite":
			var layer: Node = n
			while layer != null and not (layer is CanvasLayer):
				layer = layer.get_parent()
			if layer == null:
				return false
			(layer as CanvasLayer).visible = true
			for c in (layer as CanvasLayer).get_children():
				if c != n and c is CanvasItem:
					(c as CanvasItem).visible = false
			return true
		stack.append_array(n.get_children())
	return false


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
