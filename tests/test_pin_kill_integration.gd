extends GutTest

## END-TO-END for the thrown-weapon PIN kill, driving the REAL classes in the REAL tree: a live Character with a
## stubbed BodyModelSwap, a real StaticBody3D wall, a real Throwable blade, a real pin marker, and the real
## GoreSpawner burst. `tests/test_part_pinner.gd` pins the arithmetic; this pins the thing the arithmetic is FOR.
##
## It exists because the feature shipped once looking correct — every unit test green, every seam wired — and did
## nothing in game. Pure statics cannot catch "the chain never runs"; only driving the chain can.
##
## The base `Character` is safe to build in-tree (unlike NPC / Player — see CLAUDE.md): its _ready stamps stats,
## builds the GoreSpawner / DustSpawner / DamageThud helpers and an inventory, and touches no weapon scene, nav
## agent or audio. `_find_body_swap` is duck-typed on `character_parts()`, which is what lets the stub below stand
## in for the whole rig.

const ThrowableScript := preload("res://scripts/components/Throwable.gd")

## `Character` is @abstract, so the test needs a concrete actor. This adds NOTHING — it is the base class's own
## behaviour under test, deliberately without NPC's weapon hub / nav agent / perception (which CLAUDE.md rules out
## of unit tests) or Player's controller. The gore path is entirely Character's, so the base IS the subject.
class PinTestActor extends Character:
	pass

const WALL_Z := 3.0        ## the wall sits here; the victim stands at the origin
const CONTACT := Vector3(0.0, 1.1, 0.15)  ## chest height, just past the body — where a thrown knife stops
const THROW_DIR := Vector3(0.0, 0.0, 1.0) ## the knife was travelling +Z, into the wall

var _victim: Character
var _blade: Throwable


## A stand-in for BodyModelSwap: the ONE method GoreSpawner duck-types on, over real in-tree part nodes carrying
## real geometry (mount_part measures a visual AABB and rejects a part with none).
class SwapStub extends Node3D:
	var parts: Array = []

	func character_parts() -> Array:
		return parts


func _make_part(key: String, at: Vector3, size: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = key
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	root.add_child(mi)
	root.position = at
	return root


func before_each() -> void:
	_victim = PinTestActor.new()
	add_child_autofree(_victim)
	_victim.global_position = Vector3.ZERO
	_victim.max_hp = 14.0
	_victim.hp = 14.0

	var swap := SwapStub.new()
	_victim.add_child(swap)
	# Roughly the shipped rig's proportions: head high and small, torso at chest height, limbs to the sides.
	var rig := [
		{"key": "torso", "at": Vector3(0.0, 1.1, 0.0), "size": Vector3(0.5, 0.7, 0.3)},
		{"key": "head", "at": Vector3(0.0, 1.65, 0.0), "size": Vector3(0.3, 0.3, 0.3)},
		{"key": "arm_l", "at": Vector3(-0.38, 1.15, 0.0), "size": Vector3(0.14, 0.6, 0.14)},
		{"key": "arm_r", "at": Vector3(0.38, 1.15, 0.0), "size": Vector3(0.14, 0.6, 0.14)},
		{"key": "leg_l", "at": Vector3(-0.16, 0.45, 0.0), "size": Vector3(0.18, 0.8, 0.18)},
		{"key": "leg_r", "at": Vector3(0.16, 0.45, 0.0), "size": Vector3(0.18, 0.8, 0.18)},
	]
	for e in rig:
		var part := _make_part(e["key"], e["at"], e["size"])
		swap.add_child(part)
		swap.parts.append({"key": e["key"], "node": part})

	# The wall the limb should end up on — default collision layer 1, which is what pinned_part_probe_mask reads.
	_wall = StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(8.0, 6.0, 0.4)
	wall_shape.shape = wall_box
	_wall.add_child(wall_shape)
	add_child_autofree(_wall)
	_wall.global_position = Vector3(0.0, 1.5, WALL_Z)

	_blade = _make_blade()
	add_child_autofree(_blade)
	_blade.global_position = CONTACT


func _make_blade() -> Throwable:
	var t := ThrowableScript.new() as Throwable
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.08, 0.1, 0.46)  # melee.tres dropped_collision_size
	cs.shape = box
	t.add_child(cs)
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = box.size
	mi.mesh = m
	t.add_child(mi)
	t.collision_shape = cs
	t.mesh_instance = mi
	t.auto_fit_collider = false  # keep the authored blade extents; the auto-fit would refit to the placeholder mesh
	t.pins_body_part = true
	t.thrown_weapon = load("res://resources/weapons/melee.tres") as WeaponData
	return t


var _wall: StaticBody3D


## The probe result a strike into the wall produces, as DATA. Since the fix, the surface is found at strike time
## (in a physics callback) and carried in the marker, so most tests need no physics frame at all.
func _wall_surface() -> Dictionary:
	return {"point": Vector3(0.0, 1.1, WALL_Z - 0.2), "normal": Vector3(0.0, 0.0, -1.0), "collider": _wall}


## The gibs this death put in the world (the &"gib" group is what begin_gib_lifetime registers them in).
func _live_gibs() -> Array:
	var out: Array = []
	for g in get_tree().get_nodes_in_group(Groups.GIB):
		if is_instance_valid(g):
			out.append(g)
	return out


func _pinned_gib() -> Node:
	for g in _live_gibs():
		if g.has_method(&"is_pin_active") and g.is_pin_active():
			return g
	return null


func _free_gibs() -> void:
	for g in _live_gibs():
		g.free()


func after_each() -> void:
	_free_gibs()


# --- The headline: a marked death actually produces a pin -----------------------------------------------------

func test_a_marked_thrown_kill_pins_one_limb() -> void:
	_victim.mark_pin_hit(CONTACT, THROW_DIR, _blade, _wall_surface())
	_victim.spawn_gibs()
	var pin := _pinned_gib()
	assert_not_null(pin,
		"a death carrying a pin marker, with a wall 3 m along the throw, must hand ONE limb the pin flight")
	if pin == null:
		return
	assert_eq(pin.collision_layer, 0,
		"the pinned limb flies on rails — both collision layers are zeroed for the whole pin")
	assert_almost_eq(pin.gravity_scale, 0.0, 0.0001,
		"...and gravity with them, so it travels the exact ray the probe cleared")
	assert_gt(pin.linear_velocity.length(), 0.1,
		"it is LAUNCHED, not teleported — the flight is the part the player is meant to see")

func test_the_pinned_limb_is_the_one_the_knife_struck() -> void:
	_victim.mark_pin_hit(CONTACT, THROW_DIR, _blade, _wall_surface())
	_victim.spawn_gibs()
	var pin := _pinned_gib()
	assert_not_null(pin, "chest-height strike pins something")
	if pin != null:
		assert_eq(String(pin.display_name), String(PlayerText.body_part("torso")),
			"a chest-height strike pins the TORSO — the part nearest the contact, not a fixed choice")

func test_a_head_strike_pins_the_head() -> void:
	_victim.mark_pin_hit(Vector3(0.0, 1.66, 0.15), THROW_DIR, _blade, _wall_surface())
	_victim.spawn_gibs()
	var pin := _pinned_gib()
	assert_not_null(pin, "a head-height strike pins something")
	if pin != null:
		assert_eq(String(pin.display_name), String(PlayerText.body_part("head")),
			"...and it is the head")

# --- The degrades: every one of these must fall back to an ordinary burst, never to a broken one ---------------

func test_an_unmarked_death_pins_nothing() -> void:
	_victim.spawn_gibs()
	assert_null(_pinned_gib(),
		"an ordinary death — no thrown-weapon marker — bursts exactly as it did before pins existed")

func test_no_wall_means_no_pin() -> void:
	# The strike-time probe found nothing behind them, so the marker carries an empty surface.
	_victim.mark_pin_hit(Vector3(0.0, 1.1, -0.15), Vector3(0.0, 0.0, -1.0), _blade, {})
	_victim.spawn_gibs()
	assert_null(_pinned_gib(),
		"open ground behind the victim is the common outdoor case — it must degrade to a normal burst")

func test_a_limb_outside_the_pinnable_set_does_not_pin() -> void:
	# Arms ship OFF (an arm on a wall reads as a clipping bug at this resolution), so an arm strike must not pin.
	_victim.mark_pin_hit(Vector3(-0.42, 1.15, 0.15), THROW_DIR, _blade, _wall_surface())
	_victim.spawn_gibs()
	assert_null(_pinned_gib(),
		"a strike nearest an ARM does not pin while pinned_part_arms is off — and does not pin something else either")

func test_the_marker_is_spent_by_one_death() -> void:
	_victim.mark_pin_hit(CONTACT, THROW_DIR, _blade, _wall_surface())
	_victim.spawn_gibs()
	_free_gibs()
	_victim.spawn_gibs()
	assert_null(_pinned_gib(),
		"take_pin_hit CONSUMES — a second burst on the same body cannot spend the same marker twice")

func test_a_freed_blade_cancels_the_pin_instead_of_crashing() -> void:
	# The marker holds a hard reference across the death-freeze beat, and the player can pick the knife back up
	# inside that window, which frees the world prop.
	_victim.mark_pin_hit(CONTACT, THROW_DIR, _blade, _wall_surface())
	_blade.free()
	_victim.spawn_gibs()
	assert_null(_pinned_gib(),
		"a blade freed between the strike and the burst degrades to an ordinary burst — a pin with no knife is worse than none")

# --- The probe, and WHERE it is allowed to run ----------------------------------------------------------------
#
# THE REGRESSION THIS FILE EXISTS FOR. The shipped build looked correct everywhere and did nothing, because the
# wall probe was a space-state raycast inside GoreSpawner — and the death burst does NOT run in a physics frame
# (an NPC's gore() fires off the death-freeze SceneTreeTimer, which lands on the idle frame), so it came back
# empty on every kill however solid the wall was. The probe now runs at STRIKE time, inside Throwable's
# body_entered, and its answer rides in the marker.
#
# What guards it: every pinning test above drives spawn_gibs() straight from an idle test frame with a
# pre-resolved surface. Move the raycast back into GoreSpawner and they all go red again.

func test_the_probe_finds_the_wall_from_a_physics_frame() -> void:
	await get_tree().physics_frame  # the wall was added this frame; bodies register with the space on the next step
	await get_tree().physics_frame
	var surface: Dictionary = _blade._probe_pin_surface(CONTACT, THROW_DIR, _victim)
	assert_false(surface.is_empty(),
		"the strike-time probe must find a wall 3 m down the throw — this is the query that silently returned empty when it lived in the death burst")
	if surface.is_empty():
		return
	assert_eq(surface["collider"], _wall, "...and it must name the wall itself, so the pin can watch it")
	var point: Vector3 = surface["point"]
	assert_almost_eq(point.z, WALL_Z - 0.2, 0.05, "the hit lands on the wall's near face")

func test_the_probe_returns_nothing_for_open_air() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var surface: Dictionary = _blade._probe_pin_surface(CONTACT, Vector3(0.0, 0.0, -1.0), _victim)
	assert_true(surface.is_empty(),
		"aimed away from the wall there is nothing to staple to, and no marker is written at all")

func test_the_probe_ignores_the_victim_it_just_struck() -> void:
	# The victim is between the knife and nothing; if the exclude list were wrong the probe would "find" the body
	# it just went through and staple the limb to the corpse it came off.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var surface: Dictionary = _blade._probe_pin_surface(CONTACT, THROW_DIR, _victim)
	if not surface.is_empty():
		assert_ne(surface["collider"], _victim, "the probe never returns the body it just passed through")

func test_surviving_the_hit_clears_the_marker() -> void:
	_victim.mark_pin_hit(CONTACT, THROW_DIR, _blade, _wall_surface())
	_victim.take_damage(1.0)  # non-lethal against 14 hp
	_victim.spawn_gibs()
	assert_null(_pinned_gib(),
		"a knife that stuck in someone who LIVED must not staple a limb when they die of something else later")
