extends GutTest

## BloodyMess (scenes/player/bloody_mess.gd) — the per-actor gore controller. Two contracts are cheap to pin
## headless and load-bearing in play:
##   1. THE OWNERSHIP TAG. `gore_tag` set DIRECTLY (GoreSpawner writes it before the player's death burst) or
##      INHERITED off a PLAYER_GORE gib body it hangs under; _resolved_tag() picks, _tag() stamps the group onto
##      every world node the burst spawns (particles, the BloodDropEmitter + its per-drop tag). The checkpoint
##      revive sweeps Groups.PLAYER_GORE — an untagged emitter keeps raining player blood after the revive; a tag
##      leaking onto an NPC's gore gets an enemy's remains wiped by the player's revive.
##   2. THE CHEAP PER-HIT PATH is decals-only: splatter_at() raycasts and spawns NOTHING when nothing is hit,
##      so an SMG spraying into open air costs no nodes.
## Plus the authored wiring (enemy.tscn `bloody_mess` NodePath, gore_gib.tscn's destroyed -> _on_gore_gib_destroy)
## that a bullet's `_body.bloody_mess.splatter_at` and a popping gib depend on. The particle look is playtested.

const SCRIPT_PATH := "res://scenes/player/bloody_mess.gd"
const ENEMY_SCENE := "res://scenes/characters/enemy.tscn"
const GORE_GIB_SCENE := "res://scenes/effects/gore_gib.tscn"

var _spawned: Array[Node] = []  ## world nodes a burst parked under root — freed in after_each


## Free the burst's world nodes NOW (not at after_each): a BloodDropEmitter left under root through a physics
## frame would start raining RigidBody3D drops into the test tree.
func _free_spawns() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()


func after_each() -> void:
	_free_spawns()


func _mess():
	return load(SCRIPT_PATH).new()


## Run `burst` and return the nodes it added under the scene root (the burst parks everything there).
func _capture_root_spawns(burst: Callable) -> Array[Node]:
	var root := get_tree().root
	var before := {}
	for c in root.get_children():
		before[c.get_instance_id()] = true
	burst.call()
	var added: Array[Node] = []
	for c in root.get_children():
		if not before.has(c.get_instance_id()):
			added.append(c)
			_spawned.append(c)
	return added


# --- the ownership tag ---------------------------------------------------------------------------------------

func test_untagged_off_tree_resolves_to_no_group() -> void:
	var m = _mess()
	assert_eq(m.gore_tag, &"", "a fresh controller ships untagged — NPC gore is the default")
	assert_eq(m._resolved_tag(), &"", "no own tag + no parent = no group (the NPC/default case)")
	m.free()


func test_a_direct_tag_wins() -> void:
	var m = _mess()
	m.gore_tag = Groups.PLAYER_GORE
	assert_eq(m._resolved_tag(), Groups.PLAYER_GORE, "GoreSpawner's direct write is the resolved tag")
	m.free()


func test_a_gib_body_in_player_gore_lends_its_tag() -> void:
	var gib := Node3D.new()
	gib.add_to_group(Groups.PLAYER_GORE)
	add_child_autofree(gib)
	var m = _mess()
	gib.add_child(m)
	assert_eq(m._resolved_tag(), Groups.PLAYER_GORE,
		"a blank controller under a PLAYER_GORE gib inherits the tag — a player gib popping minutes after the revive must still bleed player gore")


func test_an_untagged_parent_lends_nothing() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var m = _mess()
	host.add_child(m)
	assert_eq(m._resolved_tag(), &"", "an ordinary (enemy) host lends no tag — its remains must survive the player's revive sweep")


func test_tag_stamps_the_group_only_when_resolved() -> void:
	var m = _mess()
	var n := Node.new()
	m._tag(n)
	assert_false(n.is_in_group(Groups.PLAYER_GORE), "an untagged controller stamps no group")
	m.gore_tag = Groups.PLAYER_GORE
	m._tag(n)
	assert_true(n.is_in_group(Groups.PLAYER_GORE), "a tagged controller stamps its group onto the spawned node")
	m._tag(null)
	pass_test("_tag(null) is a no-op, never an error")
	n.free()
	m.free()


# --- the death burst parks TAGGED nodes under root -------------------------------------------------------------

func test_death_burst_spawns_particles_and_an_emitter_both_tagged() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var m = _mess()
	host.add_child(m)
	m.gore_tag = Groups.PLAYER_GORE
	var added := _capture_root_spawns(func() -> void: m.particles(Vector3.ZERO))
	var particles: Array = added.filter(func(n: Node) -> bool: return n is GPUParticles3D)
	var emitters: Array = added.filter(func(n: Node) -> bool: return n is BloodDropEmitter)
	assert_eq(particles.size(), 1, "one death burst = one blood GPUParticles3D under root")
	assert_eq(emitters.size(), 1, "one death burst = one BloodDropEmitter under root (the drops dribble in over frames)")
	for n in added:
		assert_true(n.is_in_group(Groups.PLAYER_GORE), "%s must carry the player-gore group so the revive sweep finds it" % n.name)
	if emitters.size() == 1:
		assert_eq(emitters[0].gore_tag, Groups.PLAYER_GORE,
			"the emitter must be HANDED the tag too — it stamps each drop, and the drop stamps the decal it leaves")
	if particles.size() == 1:
		assert_eq(particles[0].amount, 300, "the death burst trims the scene's 960 to 300 — the fill-rate spike on every kill")
		assert_true(particles[0].emitting, "the burst must be emitting (one-shot)")
	_free_spawns()


func test_untagged_death_burst_leaves_root_nodes_out_of_player_gore() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var m = _mess()
	host.add_child(m)
	var added := _capture_root_spawns(func() -> void: m.particles(Vector3.ZERO))
	assert_eq(added.size(), 2, "particles + emitter")
	for n in added:
		assert_false(n.is_in_group(Groups.PLAYER_GORE), "an NPC's %s must NOT join player_gore — the revive would wipe an enemy's remains" % n.name)
	var emitters: Array = added.filter(func(n: Node) -> bool: return n is BloodDropEmitter)
	if emitters.size() == 1:
		assert_eq(emitters[0].gore_tag, &"", "an untagged burst hands the emitter no tag")
	_free_spawns()


func test_death_burst_offsets_the_particles_from_the_actor() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	host.position = Vector3(3.0, 1.0, -2.0)
	var m = _mess()
	host.add_child(m)
	var added := _capture_root_spawns(func() -> void: m.particles(Vector3(0.0, 0.5, 0.0)))
	for n in added:
		if n is GPUParticles3D:
			assert_almost_eq((n as Node3D).global_position, Vector3(3.0, 1.5, -2.0), Vector3.ONE * 0.001,
				"the burst sits at the actor's world position plus the caller's offset (a chest-height burst, not a floor one)")
	_free_spawns()


# --- the cheap per-hit path -----------------------------------------------------------------------------------

func test_splatter_into_empty_space_spawns_nothing() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var m = _mess()
	host.add_child(m)
	var added := _capture_root_spawns(func() -> void: m.splatter_at(Vector3(0.0, 50.0, 0.0), Vector3.FORWARD))
	assert_eq(added.size(), 0, "no surface within HIT_DECAL_SCAN_DISTANCE = no decal, no physics, no node — the SMG-friendly guarantee")
	added = _capture_root_spawns(func() -> void: m.splatter_at(Vector3(0.0, 50.0, 0.0), Vector3.ZERO))
	assert_eq(added.size(), 0, "a zero-length hit direction falls back to UP instead of erroring on normalize")


func test_hit_decal_constants_keep_the_gun_layer_out_of_the_cull_mask() -> void:
	var m = _mess()
	var all_20 := (1 << 20) - 1
	assert_eq(m.HIT_DECAL_CULL_MASK, all_20 & ~(1 << 2),
		"HIT_DECAL_CULL_MASK must be every render layer except layer 3 (the view-model gun), so blood hits walls but never paints the gun")
	assert_gt(m.HIT_DECAL_SIZE_MAX, m.HIT_DECAL_SIZE_MIN, "the decal size range must be ordered for randf_range")
	assert_gt(m.HIT_DECAL_DOWNWARD_BIAS_MAX, m.HIT_DECAL_DOWNWARD_BIAS_MIN, "the downward-bias range must be ordered for randf_range")
	assert_gt(m.HIT_DECAL_SCAN_DISTANCE, 0.0, "the decal scan ray needs a positive reach")
	m.free()


# --- authored wiring ------------------------------------------------------------------------------------------

func test_enemy_scene_wires_its_bloody_mess_child() -> void:
	var ps := load(ENEMY_SCENE) as PackedScene
	assert_not_null(ps, "enemy.tscn must load")
	if ps == null:
		return
	var state := ps.get_state()
	var mess_idx := -1
	var path_ok := false
	for i in state.get_node_count():
		var name := String(state.get_node_name(i))
		if name == "BloodyMess":
			mess_idx = i
		if i == 0:
			for p in state.get_node_property_count(i):
				if state.get_node_property_name(i, p) == &"bloody_mess":
					path_ok = state.get_node_property_value(i, p) == NodePath("BloodyMess")
	assert_ne(mess_idx, -1, "enemy.tscn must carry a BloodyMess child (bullets call _body.bloody_mess.splatter_at)")
	assert_true(path_ok, "enemy.tscn's root must export bloody_mess = NodePath(\"BloodyMess\")")
	if mess_idx != -1:
		var script_ok := false
		for p in state.get_node_property_count(mess_idx):
			if state.get_node_property_name(mess_idx, p) == &"script":
				var s = state.get_node_property_value(mess_idx, p)
				script_ok = s is Script and (s as Script).resource_path == SCRIPT_PATH
		assert_true(script_ok, "the BloodyMess child must run bloody_mess.gd")


func test_gore_gib_scene_pops_into_blood() -> void:
	var ps := load(GORE_GIB_SCENE) as PackedScene
	assert_not_null(ps, "gore_gib.tscn must load")
	if ps == null:
		return
	var root := ps.instantiate()
	var mess := root.get_node_or_null(^"BloodyMess")
	assert_not_null(mess, "gore_gib.tscn needs a BloodyMess child for the secondary burst when a gib breaks")
	if mess != null:
		assert_eq((mess.get_script() as Script).resource_path, SCRIPT_PATH, "the gib's BloodyMess runs bloody_mess.gd")
		assert_true(root.is_connected("destroyed", Callable(mess, "_on_gore_gib_destroy")),
			"`destroyed` must be wired to BloodyMess._on_gore_gib_destroy — otherwise a popping gib leaves no blood or floor decal")
	root.free()
