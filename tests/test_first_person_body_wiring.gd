extends GutTest

## FirstPersonBody — the first-person legs/torso/fists component lifted off player.gd (the Landing idiom).
##
## Three things are pinned here:
##   1. The PREFAB WIRING, read off the PackedScene's STATE (never instantiated — a real Player._ready wants the
##      whole prefab, weapon.tscn, nav and audio, and mutates shared statics). FirstPersonBody is a scene-wired
##      drop-in (`host = NodePath("..")`, dragged onto the Player's `fp_body` export). Both NodePaths resolve on
##      TREE ENTRY, so a rename/unwire is invisible until you play — the class of bug prefab contract tests exist for.
##   2. The AUTHORED POSE. ⭐Every historic FP-arms bug (the stow mis-anchor, the guard framing) was INVISIBLE at
##      script defaults and only real at Player.tscn's authored overrides, so the overrides must (a) land on
##      properties the component still declares — a renamed export silently orphans its .tscn row and the pose
##      falls back to the defaults — (b) not be duplicated on the root, and (c) still frame a GUARD at those
##      authored numbers, not only at the script defaults test_fists_view_model.gd checks.
##   3. The TICK ORDER: the component must process BEFORE the arms rig's BodyModelSwap._process, or the eased
##      scale/spread/rest writes stomp mid-punch arms (the setter-ordering fix the monolith got free from
##      parent-before-child ticking). Pinned as a relation between the two live priorities.

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const FP_BODY_SOURCE := "res://scripts/player/first_person_body.gd"


func _player_state() -> SceneState:
	var ps := load(PLAYER_SCENE) as PackedScene
	assert_not_null(ps, "Player.tscn must load")
	return ps.get_state()


## Find a node by name in a SceneState; -1 when absent.
func _node_index(state: SceneState, node_name: String) -> int:
	for i in range(state.get_node_count()):
		if state.get_node_name(i) == node_name:
			return i
	return -1


## Read a property off a SceneState node by name; null when the node doesn't author it.
func _node_prop(state: SceneState, idx: int, prop: String) -> Variant:
	for p in range(state.get_node_property_count(idx)):
		if state.get_node_property_name(idx, p) == prop:
			return state.get_node_property_value(idx, p)
	return null


## Every property the node authors, name -> value (the script row included).
func _authored(state: SceneState, idx: int) -> Dictionary:
	var out := {}
	for p in range(state.get_node_property_count(idx)):
		out[String(state.get_node_property_name(idx, p))] = state.get_node_property_value(idx, p)
	return out


func test_player_scene_has_first_person_body_child() -> void:
	var state := _player_state()
	assert_gte(_node_index(state, "FirstPersonBody"), 0,
		"Player.tscn must contain a FirstPersonBody child — without it the player has no FP legs, torso, carry hands or fists")


func test_component_points_host_at_the_player_root() -> void:
	var state := _player_state()
	var idx := _node_index(state, "FirstPersonBody")
	assert_gte(idx, 0, "FirstPersonBody node must exist before its host can be checked")
	assert_eq(_node_prop(state, idx, "host"), NodePath(".."),
		"FirstPersonBody.host must be wired to the Player root (..) — a null host makes every entry point a no-op")


func test_player_root_wires_the_fp_body_export() -> void:
	var state := _player_state()
	# The root is node 0; its `fp_body` export must name the child by NodePath, or player.gd's null guards
	# silently skip the build, the carry relay's cosmetic half, the punch, and the death/revive beats.
	assert_eq(_node_prop(state, 0, "fp_body"), NodePath("FirstPersonBody"),
		"Player.tscn root must wire fp_body = NodePath(\"FirstPersonBody\")")


func test_the_authored_pose_lands_on_live_exports_and_still_frames_a_guard() -> void:
	var state := _player_state()
	var idx := _node_index(state, "FirstPersonBody")
	assert_gte(idx, 0, "FirstPersonBody node must exist before its pose can be checked")
	if idx < 0:
		return
	var authored := _authored(state, idx)
	var body = load(FP_BODY_SOURCE).new()
	var root := _authored(state, 0)
	var pose_rows := 0
	for prop in authored.keys():
		if prop == "script" or prop == "host":
			continue  # the script row and the NodePath export are the wiring tests' business
		pose_rows += 1
		# (a) A renamed/removed export orphans this row: Godot drops it on load and the rig silently runs at the
		# script default — exactly where every historic FP bug was invisible.
		assert_true(prop in body,
			"Player.tscn's FirstPersonBody authors '%s', but first_person_body.gd no longer declares it — the authored value is silently dropped" % prop)
		# (b) A move, not a copy: the root must not author the same row as dead data that misleads the next retune.
		assert_false(root.has(prop),
			"the Player ROOT still authors '%s' — the FP pose lives on FirstPersonBody, a root copy is dead data" % prop)
		if prop in body:
			body.set(prop, authored[prop])
	assert_gt(pose_rows, 0, "FirstPersonBody must author its probe-tuned pose on the node, not ride the script defaults")
	# (c) At the AUTHORED numbers the guard must still read as a guard against the carry hold it is nudged from.
	var carry: Vector3 = body._fp_arm_rest()
	var carry_scale: float = body._fp_arm_rest_scale()
	var carry_spread: float = body._fp_arm_rest_spread()
	body._unarmed_hands_up = true
	var guard: Vector3 = body._fp_arm_rest()
	assert_gt(guard.z, carry.z,
		"at the authored pose the fists' guard must sit NEARER the lens (+Z) than the carry hold (guard %s, carry %s)" % [guard, carry])
	assert_gt(body._fp_arm_rest_scale(), carry_scale,
		"at the authored pose the guard must scale the fists UP from the carry hands")
	assert_gt(body._fp_arm_rest_spread(), carry_spread,
		"at the authored pose the guard must spread the fists WIDER than the carry hold so the crosshair shows between them")
	assert_gt(body._fp_arm_rest_tilt(), 10.0,
		"the authored guard tilt must stay steeper than the ~10 degrees fp_arm_unarmed_tilt_deg documents as reading like a reach")
	body.free()


func test_the_component_ticks_before_the_arms_rig() -> void:
	# The strike-stomp ordering contract: the component's pose ease must run BEFORE BodyModelSwap._process on the
	# arms rig each frame, or the eased arm_scale/spread/rest writes land AFTER the strike re-pose and stomp a
	# mid-punch arm. The rig enters the tree FIRST here, so tree order alone would tick it first — only the
	# priorities (read after both _readys ran, the way the live game sees them) can put the component ahead.
	var rig := BodyModelSwap.new()
	add_child_autofree(rig)
	var body = load(FP_BODY_SOURCE).new()  # bare: no host, so every per-frame entry point is a no-op
	add_child_autofree(body)
	assert_lt(body.process_priority, rig.process_priority,
		"FirstPersonBody must tick BEFORE the arms rig (priority %d vs %d) — the pose ease has to land before the strike re-pose" % [body.process_priority, rig.process_priority])
