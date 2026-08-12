extends GutTest

## FirstPersonBody — the first-person legs/torso/fists component lifted off player.gd (the Landing idiom).
##
## Two things are pinned here, both against the PackedScene's STATE (never instantiated — a real Player._ready
## wants the whole prefab, weapon.tscn, nav and audio, and mutates shared statics):
##   1. The PREFAB WIRING. FirstPersonBody is a scene-wired drop-in (`host = NodePath("..")`, dragged onto the
##      Player's `fp_body` export). Both NodePaths resolve on TREE ENTRY, so a rename/unwire is invisible until
##      you play — exactly the class of bug the project's prefab contract tests exist to catch.
##   2. The AUTHORED POSE moved WITH the node. ⭐Every historic FP-arms bug (the stow mis-anchor, the guard
##      framing) was INVISIBLE at script defaults and only real at Player.tscn's authored overrides — so the
##      extraction is only safe if those overrides landed on the new node byte-exact AND left the root: a MOVE,
##      not a copy (a stale root copy would author dead properties that mislead every future retune).
## Plus one source pin: the process_priority ordering contract — the component must tick BEFORE the arms rig's
## BodyModelSwap._process, or the eased scale/spread/rest writes stomp mid-punch arms (the setter-ordering fix
## the monolith got free from parent-before-child ticking).

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


func test_the_authored_pose_moved_with_the_node() -> void:
	# ⭐The three values every past FP bug hinged on: the guard nudge (the stow mis-anchor was invisible at the
	# script default and only real at (0, -0.705, 1.49)), the carry rest, and the arm scale. They must read off
	# the CHILD byte-exact — and the ROOT must no longer author them, proving the extraction MOVED the
	# overrides rather than copying them (a root leftover would be dead data that misleads the next retune).
	var state := _player_state()
	var idx := _node_index(state, "FirstPersonBody")
	assert_gte(idx, 0, "FirstPersonBody node must exist before its pose can be checked")
	assert_eq(_node_prop(state, idx, "fp_arm_unarmed_nudge"), Vector3(0, -0.705, 1.49),
		"the probe-tuned guard nudge must ride the FirstPersonBody node — the stow anchor bug was only ever real at this value")
	assert_eq(_node_prop(state, idx, "fp_arm_offset"), Vector3(0, -1.125, 0.255),
		"the authored carry rest must ride the FirstPersonBody node")
	assert_eq(_node_prop(state, idx, "fp_arm_scale"), 0.68,
		"the authored arm scale must ride the FirstPersonBody node")
	assert_null(_node_prop(state, 0, "fp_arm_offset"),
		"the Player ROOT must no longer author fp_arm_offset — a move, not a copy")


func test_the_component_ticks_before_the_arms_rig() -> void:
	# The strike-stomp ordering contract: the component's pose ease must run BEFORE BodyModelSwap._process on
	# the arms rig each frame, or the eased arm_scale/spread/rest writes land AFTER the strike re-pose and
	# stomp a mid-punch arm. The monolith got the order free (parents tick before descendants); the component
	# buys it with process_priority (plus being authored before Head, belt and braces).
	var src := FileAccess.get_file_as_string(FP_BODY_SOURCE)
	assert_true(src.contains("process_priority"),
		"first_person_body.gd must set process_priority — the pose ease has to beat the arms rig's strike re-pose")
