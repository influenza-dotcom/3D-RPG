extends Node
## VIEW-MODEL vs ITS OUTLINE across a death + respawn — the probe for the 2026-09-02 report
## "when you die and respawn, sometimes the outline for your view model is visible when the view model
## itself is not."
##
## WHY A PROBE AND NOT A UNIT TEST: the two things that have to disagree live on opposite sides of the
## renderer. The view model is composited by ViewModelCamera's SubViewportContainer ("ViewModelComposite")
## parented to the HUD CanvasLayer; its OUTLINE is an InkOutline tint duplicate on ACTOR_TINT_LAYER in the
## 3D world, rasterised by the tint camera. Nothing off-tree can put those two facts in the same frame.
##
## HEADLESS-SAFE on purpose: every quantity read here is NODE STATE (visible / visible_in_tree / mesh /
## layers), never a pixel — --headless never compiles a .gdshader, so a screenshot would prove nothing
## anyway (see the gdshader-headless-never-compiles note).
##
## THE MEASUREMENT: each frame, count the id-10 tint duplicates that are actually rasterising
## (visible_in_tree + a non-null mesh + on ACTOR_TINT_LAYER) and compare that with whether the view model
## is being composited at all. Every frame where duplicates draw while the composite is hidden is a GHOST
## FRAME — an outline with no view model inside it. The probe reports the ghost window in seconds on both
## sides of the death: the keel-over and the respawn fade-up.
##
## Run from the project root:
##   godot --headless --path . res://scripts/tools/__respawn_viewmodel_probe.tscn
##
## Driver-copy pattern (the __death_skip_probe.gd idiom): this scene is the boot scene, but the run
## switches current_scene to game.tscn, which frees it — so _ready re-attaches a COPY of this script on a
## bare Node parented to root, which survives the scene change and drives the probe.

var _player: Node3D
var _ui: CanvasLayer
var _composite: CanvasItem

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "RespawnViewModelProbeDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()


func _run() -> void:
	await _frames(5)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(150)

	_player = Groups.human_player(get_tree()) as Node3D
	if _player == null:
		print("PROBE_FAIL no Player")
		get_tree().quit(1)
		return
	_ui = _player.get("ui") as CanvasLayer
	if _ui == null:
		print("PROBE_FAIL no UI CanvasLayer")
		get_tree().quit(1)
		return
	_composite = _ui.get_node_or_null(^"ViewModelComposite") as CanvasItem
	if _composite == null:
		print("PROBE_FAIL no ViewModelComposite — the view-model pass never built")
		get_tree().quit(1)
		return
	print("PROBE_OK ViewModelComposite parent=", _composite.get_parent().name,
			" — a direct CanvasItem child of the UI CanvasLayer that hide_hud_for_death() walks")

	# Draw the weapon so the gun's own id-10 duplicates are on screen too (the player boots holstered).
	var attack := _find_child_by_script(_player, "res://scripts/combat/attack.gd")
	if attack != null and attack.has_method(&"set_holstered"):
		attack.call(&"set_holstered", false)
	await _frames(90)

	var alive := _census()
	print("PROBE_BASELINE composite.visible=", _composite.visible,
			" id10_dups_drawing=", alive["drawing"], "/", alive["total"],
			" sources_drawing=", alive["src_drawing"])
	for line in alive["roster"]:
		print("PROBE_DUP ", line)
	if int(alive["drawing"]) == 0:
		print("PROBE_FAIL no id-10 tint duplicates draw before the death — nothing could ghost")
		get_tree().quit(1)
		return

	var fb: PlayerFeedbackSettings = GameSettings.player_feedback
	print("PROBE_KNOB death_mode=", fb.death_mode, " respawn_hud_delay=", fb.respawn_hud_delay,
			" spawn_fade_in_time=", fb.spawn_fade_in_time)

	# --- die, and watch the keel-over -----------------------------------------------------------------
	var t0 := Time.get_ticks_msec()
	_player.call(&"die")
	var keel := await _watch(2.0, t0)
	_report("KEEL", keel)

	# --- ride the rest of the cinematic through the revive ---------------------------------------------
	var unskipped: float = fb.death_sequence_time + fb.death_card_delay + fb.death_card_fade_time * 2.0 \
			+ fb.death_card_gap + _player._death_mix.card_hold_seconds()
	# Wait for the REVIVE INSTANT, not a fixed overshoot: the ghost window on this side is bounded by
	# respawn_hud_delay (1.0s), so sleeping past it measures nothing.
	var give_up := Time.get_ticks_msec() + int((unskipped + 3.0) * 1000.0)
	while _player._dying and Time.get_ticks_msec() < give_up:
		await get_tree().process_frame
	if _player._dying:
		print("PROBE_FAIL still dying %.2fs after death" % (unskipped + 3.0))
		get_tree().quit(1)
		return
	var t1 := Time.get_ticks_msec()
	# The fresh life revives HOLSTERED by design, so nothing of the view model is on screen to ghost until
	# the player takes their weapon back out — which a fire-click does on the revive's first frame, INSIDE
	# the respawn_hud_delay quiet window that is still holding the composite hidden. Draw it, as a player would.
	print("PROBE_OK revived; drawing the weapon inside the quiet window, as a fire-click would")
	if attack != null and attack.has_method(&"set_holstered"):
		attack.call(&"set_holstered", false)

	var post := await _watch(maxf(fb.spawn_fade_in_time, fb.respawn_hud_delay) + 1.0, t1)
	_report("RESPAWN", post)

	var settled := _census()
	print("PROBE_SETTLED composite.visible=", _composite.visible,
			" id10_dups_drawing=", settled["drawing"], "/", settled["total"],
			" sources_drawing=", settled["src_drawing"])

	if int(keel["frames"]) == 0 and int(post["frames"]) == 0:
		print("PROBE_PASS the view model and its outline never disagreed")
		get_tree().quit(0)
		return
	print("PROBE_BUG the outline outlived the view model: %.2fs on the keel-over + %.2fs on the fade-up"
			% [keel["span"], post["span"]])
	print("PROBE_BUG cause: ViewModelComposite is a direct CanvasItem child of the UI CanvasLayer, so")
	print("PROBE_BUG UI.hide_hud_for_death() hides the entire view-model pass, while the id-10 tint")
	print("PROBE_BUG duplicates keep rasterising in the MAIN world on ACTOR_TINT_LAYER.")
	get_tree().quit(2)


func _report(tag: String, w: Dictionary) -> void:
	print("PROBE_%s ghost frames=%d spanning %.2fs (first +%.2fs, last +%.2fs), peak dups drawing while hidden=%d"
			% [tag, w["frames"], w["span"], w["first"], w["last"], w["max_dups"]])


## Poll every frame for `secs`, counting frames where id-10 duplicates rasterise with the composite hidden.
func _watch(secs: float, t_zero: int) -> Dictionary:
	var out := {"frames": 0, "first": -1.0, "last": -1.0, "span": 0.0, "max_dups": 0}
	var deadline := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not is_instance_valid(_composite) or not is_instance_valid(_player):
			break
		var c := _census()
		if int(c["drawing"]) > 0 and not _composited_now():
			var at := (Time.get_ticks_msec() - t_zero) / 1000.0
			out["frames"] = int(out["frames"]) + 1
			if float(out["first"]) < 0.0:
				out["first"] = at
			out["last"] = at
			out["max_dups"] = maxi(int(out["max_dups"]), int(c["drawing"]))
	if float(out["first"]) >= 0.0:
		out["span"] = float(out["last"]) - float(out["first"])
	return out


## Is the view model actually reaching the screen? The pass draws into its own SubViewport and ONLY the
## composite container puts it on the frame, so a hidden container means the weapon and arms are gone even
## while every 3D node under GunMesh is still `visible`.
func _composited_now() -> bool:
	return is_instance_valid(_composite) and _composite.is_visible_in_tree()


## Count the id-10 tint duplicates in the tree and how many genuinely rasterise, plus how many of their
## SOURCE meshes still do (so a legitimate hide — legs down, gun holstered — reads as such).
func _census() -> Dictionary:
	var total := 0
	var drawing := 0
	var src_drawing := 0
	var roster: Array[String] = []
	for dup in _collect_dups(get_tree().root):
		var src := dup.get_parent() as MeshInstance3D
		if src == null:
			continue
		if InkOutline.tint_base_id(src) != InkOutline.TINT_ID_VIEW_MODEL:
			continue
		total += 1
		var dup_on: bool = dup.is_visible_in_tree() and dup.mesh != null \
				and (dup.layers & InkOutline.ACTOR_TINT_LAYER) != 0
		var src_on: bool = src.is_visible_in_tree() and src.mesh != null
		if dup_on:
			drawing += 1
		if src_on:
			src_drawing += 1
		roster.append("%s ring=%s src=%s" % [src.name, dup_on, src_on])
	return {"total": total, "drawing": drawing, "src_drawing": src_drawing, "roster": roster}


func _collect_dups(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and node.has_meta(&"npc_tint_dup"):
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_collect_dups(c))
	return out


func _find_child_by_script(root: Node, path: String) -> Node:
	if root.get_script() != null and (root.get_script() as Script).resource_path == path:
		return root
	for c in root.get_children():
		var hit := _find_child_by_script(c, path)
		if hit != null:
			return hit
	return null


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _wait(secs: float) -> void:
	var deadline := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
