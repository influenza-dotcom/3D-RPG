extends GutTest

## Tests for the `destructible` toggle: throwables are destructible by default, but an instance OR its ThrowableData can
## mark a prop indestructible (dropped weapons/items, the dog) — take_damage then no-ops entirely. Built off-tree
## (no _ready), so the indestructible path (which early-returns before any tree-touching flash/destroy) is unit-safe.
## The destructible path is driven in-tree on the shared prefab: first test (a plain hit breaks it) and the bottom of
## the file (a real strike breaks a real prop and scars the surface it broke on).

const Throwable := preload("res://scripts/components/Throwable.gd")
const ThrowableData := preload("res://scripts/combat/throwable_data.gd")


## Destructible by DEFAULT, driven rather than read: the shared prefab carries no `destructible` and no data, so a
## prop nobody marked is exactly what this is — and it has to lose hp and break (crates/barrels/gibs break). It is
## also the control for the no-op test below: the same kind of hit that an indestructible prop shrugs off lands here.
## In-tree (the prefab, frozen) because the destructible path flashes and breaks, which is tree-bound.
func test_a_prop_nobody_marked_takes_damage_and_breaks() -> void:
	var t := _frozen_prop_at_origin()
	t.hp = 5
	t.take_damage(2)
	assert_eq(t.hp, 3, "a prop left at its defaults loses the hp a hit deals — nothing marked it indestructible")
	assert_false(t._destroyed, "precondition: a hit it survives does not break it")
	t.take_damage(3)
	assert_true(t._destroyed, "...and the hit that empties its hp breaks it")


func test_instance_toggle_makes_indestructible() -> void:
	var t = Throwable.new()
	t.destructible = false
	assert_false(t.is_destructible(), "destructible = false on the instance makes the prop indestructible")
	t.free()


func test_data_toggle_makes_indestructible() -> void:
	# An ITEM resource marked indestructible covers every instance, even one whose own toggle is still on.
	var d = ThrowableData.new()
	d.destructible = false
	var t = Throwable.new()
	t.data = d
	assert_false(t.is_destructible(), "a ThrowableData with destructible = false forces the prop indestructible")
	t.free()
	d = null


func test_take_damage_noops_when_indestructible() -> void:
	# The whole point: an indestructible prop loses NO hp and is never destroyed, regardless of damage dealt.
	var t = Throwable.new()
	t.destructible = false
	t.hp = 5
	t.take_damage(999)
	assert_eq(t.hp, 5, "take_damage on an indestructible prop must not subtract hp")
	assert_false(t._destroyed, "an indestructible prop is never destroyed by damage")
	t.free()


# --- destroy decal surface choice -------------------------------------------------------------------------
# A prop that breaks ON IMPACT scars the surface it hit (a bottle on a wall), not the floor under it. The
# choice of where to probe is a pure static on Throwable so it can be pinned here without a physics world.


func test_destroy_decal_probes_along_travel_first_when_moving() -> void:
	var origin := Vector3(1.0, 2.0, 3.0)
	var travel := Vector3(8.0, 0.0, 0.0)  # flung hard along +X into a wall
	var extents := Vector3(0.6, 0.8, 0.0)  # half-diagonal 0.5
	var ends := Throwable.destroy_decal_probe_ends(origin, travel, extents)
	assert_eq(ends.size(), 2, "a moving prop probes twice: along its travel, then straight down")
	var reach := extents.length() * 0.5 + Throwable.DESTROY_DECAL_IMPACT_MARGIN
	assert_almost_eq(ends[0], origin + Vector3.RIGHT * reach, Vector3.ONE * 0.0001,
		"the first probe runs along the strike, half a collider diagonal plus the margin past the origin")
	assert_almost_eq(ends[1], origin + Vector3.DOWN * Throwable.DESTROY_DECAL_PROBE, Vector3.ONE * 0.0001,
		"the fallback is the original floor probe")


func test_destroy_decal_probes_only_down_when_resting() -> void:
	# A crate smashed where it sits (shot, blast, rammed) has no surface it 'hit' — only the floor under it.
	var origin := Vector3(1.0, 2.0, 3.0)
	var ends := Throwable.destroy_decal_probe_ends(origin, Vector3.ZERO, Vector3.ONE)
	assert_eq(ends.size(), 1, "a resting prop gets the floor probe alone")
	assert_almost_eq(ends[0], origin + Vector3.DOWN * Throwable.DESTROY_DECAL_PROBE, Vector3.ONE * 0.0001)
	var creep := Vector3(0.0, 0.0, Throwable.DESTROY_DECAL_IMPACT_MIN_SPEED * 0.5)
	assert_eq(Throwable.destroy_decal_probe_ends(origin, creep, Vector3.ONE).size(), 1,
		"a barely-creeping prop is 'resting' too: below the min speed the travel probe is noise")


func test_destroy_decal_basis_stands_on_a_wall() -> void:
	var b := Throwable.destroy_decal_basis(Vector3.RIGHT)  # a wall facing +X
	assert_almost_eq(b.y, Vector3.RIGHT, Vector3.ONE * 0.0001, "the decal projects along its -Y, so Y is the surface normal")
	assert_almost_eq(b.z, Vector3.UP, Vector3.ONE * 0.0001, "on a wall the stamp's Z is world UP so it never degenerates")
	assert_almost_eq(b.x.length(), 1.0, 0.0001)
	assert_almost_eq(b.x.dot(b.y), 0.0, 0.0001)
	assert_almost_eq(b.x.dot(b.z), 0.0, 0.0001)


func test_destroy_decal_basis_lies_on_a_floor() -> void:
	var b := Throwable.destroy_decal_basis(Vector3.UP)
	assert_almost_eq(b.y, Vector3.UP, Vector3.ONE * 0.0001)
	assert_almost_eq(b.z, Vector3.FORWARD, Vector3.ONE * 0.0001, "on a floor UP is parallel to the normal, so Z falls back to world FORWARD")
	assert_almost_eq(b.x.length(), 1.0, 0.0001)


# --- live physics: the strike probe really finds the wall ---------------------------------------------------
# The pure tests above pin WHERE we probe; this one proves the probe lands a real Decal on a real StaticBody in a
# physics world (throwable.tscn in-tree, frozen so it neither falls nor collides on its own).

const PREFAB := "res://scenes/components/throwable.tscn"
const DECAL_NODE := "BulletHoleDecal"


## A wall / floor slab shaped like func_godot brush geometry (layer 1, scans nothing).
func _slab(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child_autofree(body)
	body.global_position = at
	return body


func _frozen_prop_at_origin() -> Node:
	var t = load(PREFAB).instantiate()  # untyped: instantiate() returns Variant
	t.freeze = true
	t.gravity_scale = 0.0
	add_child_autofree(t)
	t.global_position = Vector3.ZERO
	return t


func _take_decal() -> Node:
	var decal := get_tree().root.find_child(DECAL_NODE, false, false)
	if decal != null:
		get_tree().root.remove_child(decal)
		decal.free()
	return decal


func test_impact_destroy_decal_lands_on_the_struck_wall_not_the_floor() -> void:
	_slab(Vector3(1.0, 8.0, 8.0), Vector3(1.5, 0.0, 0.0))  # wall: its -X face at x = 1.0
	_slab(Vector3(8.0, 1.0, 8.0), Vector3(0.0, -1.5, 0.0))  # floor under the prop, at y = -1.0
	var t := _frozen_prop_at_origin()
	await wait_physics_frames(2)
	t._impact_travel = Vector3(8.0, 0.0, 0.0)  # flung hard along +X, into the wall
	t._spawn_destroy_decal()
	t._impact_travel = Vector3.ZERO
	var decal = get_tree().root.find_child(DECAL_NODE, false, false)
	assert_true(decal != null, "a prop that breaks on a wall strike must leave a decal")
	if decal == null:
		return
	var offset: float = GameSettings.effects.decal_normal_offset
	assert_almost_eq(decal.global_position.x, 1.0 - offset, 0.01,
		"the decal sits on the WALL face it struck (x = 1.0, lifted off it by decal_normal_offset), not on the floor")
	assert_almost_eq(decal.global_transform.basis.y, Vector3.LEFT, Vector3.ONE * 0.01,
		"the decal projects into the wall: its Y is the wall's normal (facing the prop, -X)")
	_take_decal()


func test_resting_destroy_decal_still_lands_on_the_floor() -> void:
	# The control: no strike armed -> the original floor probe, unchanged for shot/blast destroys.
	_slab(Vector3(1.0, 8.0, 8.0), Vector3(1.5, 0.0, 0.0))
	_slab(Vector3(8.0, 1.0, 8.0), Vector3(0.0, -1.5, 0.0))
	var t := _frozen_prop_at_origin()
	await wait_physics_frames(2)
	t._spawn_destroy_decal()
	var decal = get_tree().root.find_child(DECAL_NODE, false, false)
	assert_true(decal != null, "a resting prop still leaves its floor decal")
	if decal == null:
		return
	var offset: float = GameSettings.effects.decal_normal_offset
	assert_almost_eq(decal.global_position.y, -1.0 + offset, 0.01, "the resting decal lies on the FLOOR at y = -1.0")
	assert_almost_eq(decal.global_transform.basis.y, Vector3.UP, Vector3.ONE * 0.01)
	_take_decal()


# --- live strike: _on_body_entered arms the travel probe for its own break, and only for that break ---------------
# The tests above set `_impact_travel` by hand. These drive the real contact callback instead (the solver's latched
# velocity written to `_pre_step_velocity`, then `_on_body_entered`), so the arm AND the reset are both exercised.

## Fast enough that the prefab's impact self-damage (PhysicsDamageSettings: 5 m/s floor, 0.3 per m/s) is several hp.
const STRIKE_VELOCITY := Vector3(20.0, 0.0, 0.0)  # flung along +X, into the wall


## Read the destroy decal's pose and free it BEFORE asserting, so a failing assert never leaks a decal into the
## next test. Empty when no decal was spawned.
func _pop_decal_pose() -> Dictionary:
	var decal = get_tree().root.find_child(DECAL_NODE, false, false)
	if decal == null:
		return {}
	var pose := {"position": decal.global_position, "normal": decal.global_transform.basis.y}
	_take_decal()
	return pose


func test_a_prop_that_breaks_on_a_wall_strike_scars_the_wall() -> void:
	var wall := _slab(Vector3(1.0, 8.0, 8.0), Vector3(1.5, 0.0, 0.0))  # wall: its -X face at x = 1.0
	_slab(Vector3(8.0, 1.0, 8.0), Vector3(0.0, -1.5, 0.0))  # floor under the prop, at y = -1.0
	var wall_hit := _frozen_prop_at_origin()
	await wait_physics_frames(2)
	wall_hit.hp = 1
	wall_hit._pre_step_velocity = STRIKE_VELOCITY
	wall_hit._on_body_entered(wall)
	assert_true(wall_hit._destroyed, "precondition: a 1 hp prop breaks on a 20 m/s strike")
	var pose := _pop_decal_pose()
	assert_false(pose.is_empty(), "a prop that breaks on a strike must leave a decal")
	if pose.is_empty():
		return
	var offset: float = GameSettings.effects.decal_normal_offset
	assert_almost_eq(float(pose["position"].x), 1.0 - offset, 0.01,
		"a bottle that shatters ON a wall must scar the WALL: the strike has to arm the travel probe before the break")
	assert_almost_eq(pose["normal"], Vector3.LEFT, Vector3.ONE * 0.01, "the scar faces out of the wall it struck")


func test_a_strike_the_prop_survives_leaves_no_stale_travel_for_a_later_shot() -> void:
	# The prop takes a hard wall strike and SURVIVES; a moment later it is shot apart where it rests. That later break
	# has no surface it 'hit', so it must scar the floor — a travel probe left armed from the old strike would put the
	# scorch on the wall instead.
	var wall := _slab(Vector3(1.0, 8.0, 8.0), Vector3(1.5, 0.0, 0.0))
	_slab(Vector3(8.0, 1.0, 8.0), Vector3(0.0, -1.5, 0.0))
	var survivor := _frozen_prop_at_origin()
	await wait_physics_frames(2)
	survivor.hp = 100
	survivor._pre_step_velocity = STRIKE_VELOCITY
	survivor._on_body_entered(wall)
	assert_false(survivor._destroyed, "precondition: a 100 hp prop survives the strike")
	assert_lt(survivor.hp, 100, "precondition: the strike really dealt impact self-damage")
	survivor.take_damage(1000)  # shot apart, at rest
	assert_true(survivor._destroyed, "precondition: the shot breaks it")
	var pose := _pop_decal_pose()
	assert_false(pose.is_empty(), "the shot-apart prop still leaves its decal")
	if pose.is_empty():
		return
	var offset: float = GameSettings.effects.decal_normal_offset
	assert_almost_eq(float(pose["position"].y), -1.0 + offset, 0.01,
		"a break that happens AFTER the strike must take the floor probe — the strike's travel must be cleared when it ends")
	assert_almost_eq(pose["normal"], Vector3.UP, Vector3.ONE * 0.01, "the scar lies on the floor")
