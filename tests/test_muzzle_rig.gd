extends GutTest

## MuzzleRig (scripts/effects/muzzle_rig.gd) is GunMesh's code-built child that owns the rig MUZZLE anchor: it
## stashes the rig's resting muzzle spot (Sketchfab_Scene/PlayerMuzzle) on _ready, snaps that muzzle (with the
## flash / sparks / shell / whiz FX under it) onto an equipped weapon's own "Muzzle" marker in align_to, restores
## the rest spot for a weapon with no marker, and resolves per-weapon anchor markers (equipped_marker) off the
## swapper's CURRENT view-model for the laser sight. Pinned with a minimal in-tree GunMesh carrying just the rig
## nodes the child reads (global_position needs the tree; GunMesh._ready with those children present is clean),
## a fake view-model with a lower-case "muzzle" child, and a bare off-tree rig for the no-swapper guard.
## GunMesh is loaded by path (the test_effects.gd idiom) to dodge a class_name cache cascade on a headless load.

const GUN_MESH_PATH := "res://scripts/effects/gun_mesh.gd"
const RIG_MUZZLE_REST := Vector3(0.1, 0.2, -0.8)


## A GunMesh with the two rig nodes MuzzleRig reads (Sketchfab_Scene/PlayerMuzzle), added to the tree so
## GunMesh._ready builds + wires its children (the real host/swapper wiring under test).
func _make_host() -> GunMesh:
	var host: GunMesh = load(GUN_MESH_PATH).new()
	var sk := Node3D.new()
	sk.name = "Sketchfab_Scene"
	var rig_muzzle := Marker3D.new()
	rig_muzzle.name = "PlayerMuzzle"
	rig_muzzle.position = RIG_MUZZLE_REST
	sk.add_child(rig_muzzle)
	host.add_child(sk)
	add_child_autofree(host)
	return host


## A fake weapon view-model under `host` (where WeaponModelSwapper parents the real one): a body node at
## `at`, with an optional lower-case "muzzle" marker child and a "LaserOrigin" anchor.
func _make_view_model(host: Node, at: Vector3, with_muzzle: bool) -> Node3D:
	var vm := Node3D.new()
	vm.name = "FakeViewModel"
	vm.position = at
	if with_muzzle:
		var m := Node3D.new()
		m.name = "muzzle"          # lower-case on purpose: the lookup is case-insensitive
		m.position = Vector3(0.0, 0.0, -1.0)
		vm.add_child(m)
	var laser := Node3D.new()
	laser.name = "LaserOrigin"
	vm.add_child(laser)
	host.add_child(vm)
	return vm


func _rig_muzzle(host: Node) -> Node3D:
	return host.get_node("Sketchfab_Scene/PlayerMuzzle") as Node3D


# --- wiring ---------------------------------------------------------------------------------------------------

func test_gun_mesh_builds_and_wires_the_rig_child() -> void:
	var host := _make_host()
	var rig: MuzzleRig = host._muzzle_rig
	assert_not_null(rig, "GunMesh._ready builds a MuzzleRig child")
	if rig == null:
		return
	assert_eq(rig.host, host, "host is set right after .new() (the rig muzzle lives under it)")
	assert_eq(rig.swapper, host._swapper, "swapper is the sibling WeaponModelSwapper (equipped_marker searches its current model)")
	assert_eq(rig.get_parent(), host, "the rig is a code-built child of the GunMesh")


func test_ready_stashes_the_rig_muzzle_rest_position() -> void:
	var host := _make_host()
	var rig: MuzzleRig = host._muzzle_rig
	assert_eq(rig._muzzle_default_pos, RIG_MUZZLE_REST,
		"_ready captures Sketchfab_Scene/PlayerMuzzle's LOCAL rest position before the deferred first equip can move it")


# --- align_to() ---------------------------------------------------------------------------------------------------

func test_align_to_snaps_the_rig_muzzle_onto_the_weapons_muzzle_marker() -> void:
	var host := _make_host()
	var rig: MuzzleRig = host._muzzle_rig
	var vm := _make_view_model(host, Vector3(0.5, 0.0, 0.0), true)
	rig.align_to(vm)
	var marker := vm.get_node("muzzle") as Node3D
	assert_true(_rig_muzzle(host).global_position.is_equal_approx(marker.global_position),
		"the rig muzzle (and the FX under it) moves onto the weapon's own marker in WORLD space; got %s want %s"
		% [str(_rig_muzzle(host).global_position), str(marker.global_position)])
	assert_false(_rig_muzzle(host).position.is_equal_approx(RIG_MUZZLE_REST),
		"the snap actually moved it off the rest spot")


func test_align_to_restores_the_rest_spot_for_a_weapon_without_a_marker() -> void:
	var host := _make_host()
	var rig: MuzzleRig = host._muzzle_rig
	var armed := _make_view_model(host, Vector3(0.5, 0.0, 0.0), true)
	rig.align_to(armed)
	var bare := _make_view_model(host, Vector3(2.0, 0.0, 0.0), false)
	rig.align_to(bare)
	assert_eq(_rig_muzzle(host).position, RIG_MUZZLE_REST,
		"a view-model with no Muzzle marker restores the rig's default muzzle spot (never keeps the previous weapon's)")


func test_align_to_null_restores_the_rest_spot() -> void:
	var host := _make_host()
	var rig: MuzzleRig = host._muzzle_rig
	var armed := _make_view_model(host, Vector3(0.5, 0.0, 0.0), true)
	rig.align_to(armed)
	rig.align_to(null)
	assert_eq(_rig_muzzle(host).position, RIG_MUZZLE_REST,
		"an unarmed / no-view-model equip (align_to(null)) restores the rest spot")


func test_align_to_is_a_no_op_without_a_rig_muzzle() -> void:
	var host: GunMesh = load(GUN_MESH_PATH).new()
	var rig := MuzzleRig.new()
	rig.host = host
	var vm := Node3D.new()
	rig.align_to(vm)
	assert_true(true, "a host with no Sketchfab_Scene/PlayerMuzzle simply returns (no transform touched off-tree, no error)")
	vm.free()
	rig.free()
	host.free()


# --- equipped_marker() ---------------------------------------------------------------------------------------------

func test_equipped_marker_searches_the_current_view_model_case_insensitively() -> void:
	var host := _make_host()
	var rig: MuzzleRig = host._muzzle_rig
	var vm := _make_view_model(host, Vector3.ZERO, true)
	host._swapper._weapon_model = vm
	assert_eq(rig.equipped_marker("laserorigin"), vm.get_node("LaserOrigin"),
		"a marker is found by lower-cased name anywhere under the current view-model")
	assert_eq(rig.equipped_marker("muzzle"), vm.get_node("muzzle"),
		"the muzzle marker is reachable the same way")
	assert_null(rig.equipped_marker("nosuchmarker"), "an unknown name yields null, never a wrong node")
	assert_eq(host.equipped_marker("laserorigin"), vm.get_node("LaserOrigin"),
		"GunMesh.equipped_marker is a facade over the rig child (what the laser sight reads)")


func test_equipped_marker_is_null_with_no_view_model() -> void:
	var host := _make_host()
	var rig: MuzzleRig = host._muzzle_rig
	host._swapper._weapon_model = null
	assert_null(rig.equipped_marker("laserorigin"), "no equipped view-model -> null")


func test_equipped_marker_is_null_without_a_swapper() -> void:
	var rig := MuzzleRig.new()
	assert_null(rig.equipped_marker("muzzle"), "an unwired rig (no swapper) resolves nothing rather than crashing")
	rig.free()
	var bare: GunMesh = load(GUN_MESH_PATH).new()
	assert_null(bare.equipped_marker("muzzle"),
		"an off-tree GunMesh (no _ready, no rig child) returns null from the facade, exactly as the monolith did")
	bare.free()
