extends GutTest

## Contract tests for the BODY-PART GIB burst — the thing that makes a dying character come apart into its
## own head / torso / arms / legs instead of only spraying meat chunks.
##
## Two halves, both cheap and off-tree:
##   1. The PURE seams. BodyPartGib.mount_placement / local_visual_aabb and BodyPartGibs.wants_part /
##      resolve_meat_count are `static` precisely so the risky maths and the designer toggles can be pinned
##      with no scene, no physics and no _ready (the BodyModelSwap.seated_pitch_to_clear idiom). The transform
##      split is where this feature can silently go wrong — a mirrored basis on a RigidBody3D is the known
##      "negative-scale GLB renders black" failure, and a scaled one is ignored by the physics server — so
##      every assertion about determinant and diagonality below is load-bearing, not decoration.
##   2. The SCENE contract for scenes/effects/body_part_gib.tscn. Off-tree instantiate() does NOT run
##      Throwable._ready (no collider auto-fit, no overlay chain, no physics) — safe per the no-_ready rule,
##      and node-path exports are still resolved by instantiate(), which is exactly what we assert.

const PART_GIB_SCENE := "res://scenes/effects/body_part_gib.tscn"
const BodyPartGibScript := preload("res://scripts/effects/body_part_gib.gd")
const BodyPartGibsScript := preload("res://scripts/components/body_part_gibs.gd")

## BodyModelSwap._reflect(): the det = -1 mirror premultiplied onto the RIGHT arm and leg.
const MIRROR := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0))


# --- mount_placement: the part must not move, and the body must be physics-safe --------------------------

func test_mount_placement_reproduces_the_parts_world_transform() -> void:
	# The whole promise of the feature: body(basis, origin) * child_local == the part's live world transform,
	# so for the frame the burst starts the character is still visually whole.
	var world := Transform3D(
		Basis.from_euler(Vector3(0.3, -1.2, 0.4)).scaled(Vector3.ONE * 0.35), Vector3(2.0, 1.1, -3.0))
	var m := BodyPartGibScript.mount_placement(world, Vector3(0.0, -0.4, 0.05))
	var rebuilt := Transform3D(m["basis"], m["origin"]) * (m["local"] as Transform3D)
	assert_true(rebuilt.is_equal_approx(world),
		"body transform * mounted-part local transform must reproduce the part's world transform exactly, or the limb jumps the instant it becomes a gib (got %s, want %s)" % [rebuilt, world])


func test_mount_placement_body_basis_is_an_unscaled_rotation() -> void:
	# A RigidBody3D must not carry scale — Godot/Jolt ignore it on a physics body, so a scaled one desyncs
	# its collider from its visual.
	var world := Transform3D(Basis.from_euler(Vector3(0.1, 2.0, -0.7)).scaled(Vector3.ONE * 0.205), Vector3(1, 2, 3))
	var m := BodyPartGibScript.mount_placement(world, Vector3(0.0, 0.2, 0.0))
	var b: Basis = m["basis"]
	assert_almost_eq(b.determinant(), 1.0, 0.0001,
		"the rigid body's basis must be a proper rotation (det +1) — scale and mirror belong on the mounted child")
	assert_true(b.get_scale().is_equal_approx(Vector3.ONE),
		"the rigid body's basis must be unscaled; the part's scale rides the mounted child (got %s)" % b.get_scale())


func test_mount_placement_splits_the_right_limb_mirror_onto_the_child() -> void:
	# BodyModelSwap builds the RIGHT arm/leg by premultiplying a det = -1 reflection. Handing that basis to a
	# rigid body is the "negative-scale GLB renders black" failure; it has to come off the body and land on
	# the child, where it renders exactly as it did on the living character.
	var world := Transform3D(MIRROR * Basis.from_euler(Vector3(0.2, 1.0, 0.0)).scaled(Vector3.ONE * 0.44),
		Vector3(-0.27, 0.15, 0.0))
	assert_lt(world.basis.determinant(), 0.0, "test premise: the mirrored right-limb basis is negative-determinant")
	var m := BodyPartGibScript.mount_placement(world, Vector3(0.0, -0.3, 0.0))
	assert_almost_eq((m["basis"] as Basis).determinant(), 1.0, 0.0001,
		"the mirror must be stripped off the rigid body — a reflected basis on a physics body renders the limb with inverted normals (black)")
	assert_lt((m["local"] as Transform3D).basis.determinant(), 0.0,
		"...and must survive on the mounted child, or the right arm/leg comes out as a second LEFT one")
	var rebuilt := Transform3D(m["basis"], m["origin"]) * (m["local"] as Transform3D)
	assert_true(rebuilt.is_equal_approx(world),
		"the mirrored limb must still round-trip to its exact world pose (got %s, want %s)" % [rebuilt, world])


func test_mount_placement_child_basis_is_axis_aligned() -> void:
	# The rotation lives on the BODY, so the child carries only scale (times the mirror) — a diagonal basis.
	# That is what keeps Throwable's collider auto-fit tight: it boxes the mesh in the mesh's own frame
	# instead of the fatter diagonal box that encloses a rotated limb.
	for basis in [Basis.from_euler(Vector3(0.5, 1.4, -0.9)).scaled(Vector3.ONE * 0.35),
			MIRROR * Basis.from_euler(Vector3(-0.2, 0.8, 0.1)).scaled(Vector3.ONE * 0.44)]:
		var m := BodyPartGibScript.mount_placement(Transform3D(basis, Vector3(1, 1, 1)), Vector3(0, -0.2, 0))
		var lb: Basis = (m["local"] as Transform3D).basis
		for i in 3:
			for j in 3:
				if i == j:
					continue
				assert_almost_eq(lb[i][j], 0.0, 0.0001,
					"the mounted child's basis must be diagonal (scale, times the mirror) — off-diagonal [%d][%d] means the limb rotation leaked onto the child and will inflate its collider" % [i, j])


func test_mount_placement_parks_the_body_on_the_parts_visual_centre() -> void:
	# A limb model pivots at its shoulder/hip. The gib must tumble about the MIDDLE of the limb instead, and
	# the collider (a box centred on the body origin) has to agree.
	var world := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 2.0), Vector3(5.0, 0.0, 0.0))
	var m := BodyPartGibScript.mount_placement(world, Vector3(0.0, -0.5, 0.0))
	assert_true((m["origin"] as Vector3).is_equal_approx(Vector3(5.0, -1.0, 0.0)),
		"the body must sit at the part's visual centre in WORLD space (centre_local run through the part's own transform, scale included) — got %s" % [m["origin"]])


func test_mount_placement_survives_a_degenerate_basis() -> void:
	# A part scaled to nothing can't be decomposed; it must degrade to an unrotated body, never NaN.
	var m := BodyPartGibScript.mount_placement(Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO), Vector3.ZERO)
	assert_true((m["basis"] as Basis).is_equal_approx(Basis.IDENTITY),
		"a zero-scale part must fall back to an identity body basis instead of producing NaN")


# --- local_visual_aabb: what the collider gets sized from -------------------------------------------------

func test_local_visual_aabb_excludes_the_roots_own_transform_and_accumulates_children() -> void:
	# The root's transform is deliberately ignored (mount_part overwrites it); child transforms are not.
	var root := MeshInstance3D.new()
	root.position = Vector3(100.0, 100.0, 100.0)  # must be ignored
	var kid := MeshInstance3D.new()
	kid.mesh = BoxMesh.new()  # 1x1x1 centred on its origin
	kid.position = Vector3(0.0, 2.0, 0.0)         # must NOT be ignored
	root.add_child(kid)
	var box := BodyPartGibScript.local_visual_aabb(root)
	assert_true(bool(box["has"]), "a subtree with one real mesh must report a visual AABB")
	assert_true((box["aabb"] as AABB).get_center().is_equal_approx(Vector3(0.0, 2.0, 0.0)),
		"the child's offset must accumulate and the ROOT's own position must be excluded — got centre %s" % [(box["aabb"] as AABB).get_center()])
	root.free()


func test_local_visual_aabb_skips_hidden_meshes() -> void:
	# The only hidden mesh on a live body part is BodyModelSwap's talking-mouth billboard: a widget, not
	# anatomy. Counting it would push the limb's collider out toward the face.
	var root := MeshInstance3D.new()
	root.mesh = BoxMesh.new()
	var mouth := MeshInstance3D.new()
	mouth.mesh = BoxMesh.new()
	mouth.position = Vector3(0.0, 0.0, 50.0)
	mouth.visible = false
	root.add_child(mouth)
	var box := BodyPartGibScript.local_visual_aabb(root)
	assert_almost_eq((box["aabb"] as AABB).size.z, 1.0, 0.001,
		"a hidden mesh must not inflate the part's AABB (the talking mouth quad would otherwise stretch it 50 m)")
	root.free()


func test_local_visual_aabb_reports_nothing_for_a_mesh_less_subtree() -> void:
	# The signal GoreSpawner uses to throw a chassis away instead of flinging an invisible gib.
	var root := Node3D.new()
	root.add_child(Node3D.new())
	assert_false(bool(BodyPartGibScript.local_visual_aabb(root)["has"]),
		"a part with no visible mesh must report has=false so the spawner discards it")
	root.free()


# --- BodyPartGibs: the per-actor designer toggles ---------------------------------------------------------

func test_wants_part_maps_every_body_model_swap_key() -> void:
	# Keys come from BodyModelSwap.character_parts(); arms and legs are PAIRS behind one toggle each.
	assert_true(BodyPartGibsScript.wants_part("head", true, false, false, false), "head key follows the head toggle")
	assert_true(BodyPartGibsScript.wants_part("torso", false, true, false, false), "torso key follows the torso toggle")
	assert_true(BodyPartGibsScript.wants_part("arm_l", false, false, true, false), "arm_l follows the arms toggle")
	assert_true(BodyPartGibsScript.wants_part("arm_r", false, false, true, false), "arm_r follows the SAME arms toggle — arms are one pair")
	assert_true(BodyPartGibsScript.wants_part("leg_l", false, false, false, true), "leg_l follows the legs toggle")
	assert_true(BodyPartGibsScript.wants_part("leg_r", false, false, false, true), "leg_r follows the SAME legs toggle")


func test_wants_part_respects_an_unticked_toggle_and_an_unknown_key() -> void:
	assert_false(BodyPartGibsScript.wants_part("head", false, true, true, true), "an unticked part must not fly")
	assert_false(BodyPartGibsScript.wants_part("tail", true, true, true, true),
		"an unrecognised part key must NOT be flung by default — a part with no designer toggle is not silently gibbed")


func test_resolve_meat_count_inherits_on_negative_and_honours_zero() -> void:
	assert_eq(BodyPartGibsScript.resolve_meat_count(-1, 3), 3, "-1 means 'inherit the global body_part_gib_meat_count'")
	assert_eq(BodyPartGibsScript.resolve_meat_count(0, 3), 0,
		"0 is a REAL choice (parts only, no loose gore) and must not be mistaken for 'unset'")
	assert_eq(BodyPartGibsScript.resolve_meat_count(9, 3), 9, "a non-negative per-actor count overrides the global one")


func test_component_config_dictionary_carries_every_field_the_spawner_reads() -> void:
	# GoreSpawner reads this component duck-typed, as a plain Dictionary, so a renamed key would fail
	# silently at runtime (the spawner would just use its defaults). Pin the key set here instead.
	var c = BodyPartGibsScript.new()
	var cfg: Dictionary = c.body_part_gib_config()
	for key in ["enabled", "scene", "meat_gib_count", "speed_scale", "head", "torso", "arms", "legs"]:
		assert_true(cfg.has(key), "body_part_gib_config() must carry '%s' — GoreSpawner reads it by that exact name" % key)
	assert_true(bool(cfg["enabled"]), "a freshly dropped-in BodyPartGibs must be enabled: you add it to opt an actor IN as often as out")
	assert_true(cfg["scene"] is PackedScene, "with no per-actor override the config must resolve the shipped chassis scene")
	c.free()


# --- PlayerText: the hover prompt on a flying limb --------------------------------------------------------

func test_body_part_nouns_resolve_and_never_double_the_placeholder_marker() -> void:
	assert_eq(PlayerText.body_part("head"), PlayerText.BODY_PART_HEAD, "the head key resolves its noun")
	assert_eq(PlayerText.body_part("arm_r"), PlayerText.BODY_PART_ARM, "left and right share one noun — a severed limb has no side")
	assert_eq(PlayerText.body_part("nope"), "", "an unknown key degrades to blank, which pick_up() turns into the plain prompt")
	var prompt := PlayerText.pick_up(PlayerText.body_part("head"))
	assert_eq(prompt.count(PlayerText.PH_PREFIX), 1,
		"the part noun must be BARE — pick_up()'s template already carries exactly one '[PH] ' marker and doubling it is a pinned failure (got %s)" % prompt)


# --- The chassis scene ------------------------------------------------------------------------------------

func test_body_part_gib_scene_wires_the_mount_point_collider_and_gib_data() -> void:
	# Off-tree instantiate() does NOT run Throwable._ready — safe per the no-_ready rule. Node-path exports
	# ARE resolved by instantiate(), which is what makes this assertable at all.
	var ps := load(PART_GIB_SCENE) as PackedScene
	assert_not_null(ps, "body_part_gib.tscn (the flying-limb chassis) must load")
	var root := ps.instantiate()
	assert_true(root is RigidBody3D, "the chassis must be a RigidBody3D so a limb actually tumbles")
	var mount: MeshInstance3D = root.get(&"mesh_instance")
	assert_not_null(mount,
		"`mesh_instance` must be wired — it is the mount point the body part hangs under, and what Throwable's collider auto-fit measures")
	assert_null(mount.mesh if mount != null else null,
		"the mount point must hold NO mesh of its own, or that mesh flies alongside the body part")
	assert_not_null(root.get(&"collision_shape"),
		"`collision_shape` must be wired or the limb gets no collider auto-fitted to its real size")
	var data = root.get(&"data")
	assert_not_null(data, "the chassis needs a ThrowableData — it is what marks these as gibs")
	assert_true(bool(data.get(&"is_gib")), "data.is_gib must be true so a flying limb is confetti-trick-shot eligible like any gib")
	assert_false(bool(data.get(&"damages_player")), "data.damages_player must be false — being pelted by your own kill's limbs must not chip your HP")
	assert_null(data.get(&"mesh"),
		"the ThrowableData must set NO mesh: Throwable pushes it over the mount point at _ready and would replace the body part")
	assert_null(data.get(&"material"),
		"the ThrowableData must set NO material: Throwable pushes it onto every mesh under the mount and would wipe the character's own skin off the limb")
	assert_eq(root.call(&"_get_configuration_warnings").size(), 0, "the shipped chassis must raise no editor configuration warnings")
	root.free()


func test_body_part_gib_scene_bleeds_when_shot_apart() -> void:
	var ps := load(PART_GIB_SCENE) as PackedScene
	var root := ps.instantiate()
	var mess := root.get_node_or_null(^"BloodyMess")
	assert_not_null(mess, "the chassis needs a BloodyMess child so a limb shot out of the air still bursts into blood")
	assert_true(root.is_connected("destroyed", Callable(mess, "_on_gore_gib_destroy")),
		"`destroyed` must be wired to BloodyMess._on_gore_gib_destroy — otherwise popping a limb leaves no blood or floor decal")
	assert_not_null(root.get(&"impact_sfx"), "`impact_sfx` must be wired so a landing limb thuds")
	root.free()
