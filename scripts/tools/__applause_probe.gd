extends Node
## All-headshot APPLAUSE runtime probe — boots the REAL game, kills REAL enemy.tscn instances and reports
## whether AudioManager.play_applause() actually spawned its player. Spawns its OWN victims so the level's
## roster isn't the limit, and finishes with a GOLD-STANDARD case that fires the player's real weapon so
## `was_crit` is decided by the real damage_trace/DamageApplier path rather than handed in.
##
## Run:  godot --headless --path . res://scripts/tools/__applause_probe.tscn

const APPLAUSE_PATH := "res://assets/audio/sfx/Applause.mp3"
const SPLASH_PATH := "res://assets/audio/sfx/Spplshh.mp3"
const ENEMY := preload("res://scenes/characters/enemy.tscn")

var _seen_applause := {}
var _applause_db: float = 999.0   ## volume_db observed on the last applause player seen
var _live_splash: int = 0         ## splash players still parented under root at the end of a sweep

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "ApplauseProbeDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()


func _run() -> void:
	# The headless DUMMY audio driver never actually starts playback, so `finished` never fires and the
	# leak check cannot be measured there — run this WINDOWED to exercise real audio. Small, decorated and
	# explicitly WINDOWED so it can't land as the no-focus ghost window this project has been bitten by.
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(800, 480))
	print("PROBE_DRIVER audio=", AudioServer.get_driver_name(), " display=", DisplayServer.get_name())
	await _frames(5)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(150)
	var player: Node3D = Groups.human_player(get_tree())
	if player == null:
		print("PROBE_FAIL no Player"); get_tree().quit(1); return
	print("PROBE_ENV allow_timescale=", GameSettings.allow_timescale_changes,
			" death_freeze=", GameSettings.effects.death_freeze_duration,
			" fall_damage_min_speed=", GameSettings.effects.get("fall_damage_min_speed") if GameSettings.effects.get("fall_damage_min_speed") != null else "n/a")

	await _case_real_fire(player)                                   # THE decisive one
	await _case("A_one_lethal_headshot", player, [true], 1.01)
	await _case("B_two_headshots      ", player, [true, true], 0.51)
	await _case("C_body_then_head     ", player, [false, true], 0.51)
	await _case("D_CONTROL_bodyshot   ", player, [false], 1.01)

	# Leak verdict: the level's own NPCs keep dying mid-run, so an instantaneous count is noisy. Settle
	# long past the splash's 1.68 s and count again — with finished->queue_free restored this must reach 0.
	await _poll(900)
	print("PROBE_LEAK_FINAL splash one-shots still parented to root after a long settle=", _live_splash,
			" (must be 0 — anything that stuck is leaked)")
	print("PROBE_DONE")
	get_tree().quit(0)


## Spawn a fresh enemy.tscn near the player and let it settle.
func _spawn(player: Node3D, offset: Vector3) -> Node3D:
	var npc := ENEMY.instantiate()
	get_tree().current_scene.add_child(npc)
	npc.global_position = player.global_position + offset
	await _frames(20)
	return npc as Node3D


func _case(label: String, player: Node3D, crits: Array, frac: float) -> void:
	var npc := await _spawn(player, Vector3(0, 0, 30))
	if not is_instance_valid(npc):
		print("PROBE_CASE ", label, " SKIPPED spawn failed"); return
	var seen := {"emitted": false, "only": null, "took": null, "all": null}
	npc.died.connect(func() -> void:
		seen["emitted"] = true
		seen["took"] = npc.get("_took_any_hit")
		seen["all"] = npc.get("_all_crits")
		seen["only"] = npc.killed_by_only_crits()
	, CONNECT_ONE_SHOT)

	var before := _seen_applause.size()
	var head: Vector3 = npc.to_global(Vector3(0.0, float(npc.get("head_local_y")) + 0.15, 0.0))
	var per: float = npc.hp * frac
	for crit in crits:
		npc.take_damage(per, crit, player, head)
		await _poll(2)
	await _poll(400)
	var n := _seen_applause.size() - before
	print("PROBE_CASE ", label, " shots=", crits, " | died=", seen["emitted"],
			" took_any=", seen["took"], " all_crits=", seen["all"], " only_crits=", seen["only"],
			" | APPLAUSE=", n, " -> ", ("APPLAUDED" if n > 0 else "SILENT"))


## GOLD STANDARD: aim the player's real camera at a frozen enemy's HEAD every frame and fire the real
## weapon, so `was_crit` is decided by the real damage_trace/DamageApplier path rather than handed in.
func _case_real_fire(player: Node3D) -> void:
	var cam: Camera3D = _find(player, "Camera3D") as Camera3D
	var atk: Node = _find(player, "Attack")
	if cam == null or atk == null:
		print("PROBE_FIRE SKIPPED cam=", cam, " attack=", atk); return
	if atk.get("holstered"):
		atk.call("set_holstered", false)
		await _frames(40)

	var fwd: Vector3 = -cam.global_transform.basis.z
	for i in 4:
		await get_tree().physics_frame
	var wq := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + fwd * 40.0)
	wq.collide_with_areas = false
	var wall := cam.get_world_3d().direct_space_state.intersect_ray(wq)
	var clear: float = cam.global_position.distance_to(wall["position"]) if not wall.is_empty() else 40.0
	var dist: float = clampf(clear * 0.5, 1.5, 8.0)

	var npc := await _spawn(player, fwd * dist)
	if not is_instance_valid(npc):
		print("PROBE_FIRE SKIPPED spawn failed"); return
	# Freeze the victim so it cannot walk, fall or shoot back — the ONLY damage it takes is ours.
	# ⭐ DISABLE_MODE_KEEP_ACTIVE first: a disabled CollisionObject3D defaults to REMOVE, which yanks
	# the body out of the physics world entirely — the eye ray would then sail straight through it.
	npc.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	npc.process_mode = Node.PROCESS_MODE_DISABLED
	npc.velocity = Vector3.ZERO
	npc.global_position = cam.global_position + fwd * dist - Vector3(0.0, 0.6, 0.0)
	for i in 8:
		await get_tree().physics_frame
	var head: Vector3 = npc.to_global(Vector3(0.0, float(npc.get("head_local_y")) + 0.25, 0.0))

	var q := PhysicsRayQueryParameters3D.create(cam.global_position, head)
	q.collide_with_areas = false
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	print("PROBE_FIRE los_clear=", snappedf(clear, 0.01), " dist=", snappedf(dist, 0.01),
			" eye->head ray hits=", (hit["collider"] if not hit.is_empty() else "<nothing>"),
			" is_victim=", (not hit.is_empty() and hit["collider"] == npc),
			" crit_for=", (DamageApplier.crit_for(npc, hit["position"], false) if not hit.is_empty() and hit["collider"] == npc else "n/a"),
			" | hp=", npc.hp, " holstered=", atk.get("holstered"))

	var seen := {"emitted": false, "only": null, "all": null, "hits": []}
	npc.died.connect(func() -> void:
		seen["emitted"] = true
		seen["all"] = npc.get("_all_crits")
		seen["only"] = npc.killed_by_only_crits()
	, CONNECT_ONE_SHOT)
	var last_hp: Array = [npc.hp]
	npc.damaged.connect(func(hp: float, _mx: float) -> void:
		(seen["hits"] as Array).append("-%s->%s" % [snappedf(last_hp[0] - hp, 0.01), snappedf(hp, 0.01)])
		last_hp[0] = hp
	)

	var before := _seen_applause.size()
	var shots := 0
	for i in 900:
		if not is_instance_valid(npc) or npc.get("_dead"):
			break
		if atk.call("can_fire"):
			cam.look_at(head, Vector3.UP)   # put the eye on the head THIS frame, then pull the trigger
			atk.call("try_fire")
			shots += 1
		await _poll(1)
	await _poll(400)
	var n := _seen_applause.size() - before
	print("PROBE_LEAK splash_players_still_parented_after_settle=", _live_splash,
			" (expect 0 once the finished->queue_free is restored)")
	print("PROBE_LEVEL applause volume_db=", _applause_db, " (0 = buried under the +6 dB splash)")
	print("PROBE_FIRE shots=", shots, " damage_events=", seen["hits"],
			" died=", seen["emitted"], " all_crits=", seen["all"], " only_crits=", seen["only"],
			" | APPLAUSE=", n, " -> ", ("APPLAUDED" if n > 0 else "SILENT"))


func _poll(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		_live_splash = 0
		var stack: Array[Node] = [get_tree().root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node is AudioStreamPlayer:
				var s: AudioStream = (node as AudioStreamPlayer).stream
				if s != null and s.resource_path == APPLAUSE_PATH:
					if not _seen_applause.has(node.get_instance_id()):
						# FIRST sight only: the fade tween drags volume_db to -40, so a last-sight
						# read reports the tail, not the level the cheer actually starts at.
						_applause_db = (node as AudioStreamPlayer).volume_db
					_seen_applause[node.get_instance_id()] = true
			elif node is AudioStreamPlayer3D:
				var s3: AudioStream = (node as AudioStreamPlayer3D).stream
				if s3 != null and s3.resource_path == SPLASH_PATH and node.get_parent() == get_tree().root:
					_live_splash += 1
			stack.append_array(node.get_children())


func _find(root: Node, cls: String) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_class() == cls or n.name == cls:
			return n
		stack.append_array(n.get_children())
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
