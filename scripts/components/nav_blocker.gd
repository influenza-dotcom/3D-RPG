@tool
class_name NavBlocker
extends NavigationObstacle3D

## Drop-in NAVIGATION BLOCKER: makes NPCs path AROUND a prop instead of onto or through it. Two modes:
##
## - CARVE (static): cuts the prop's footprint OUT of the baked navmesh, so no walkable surface forms on top
##   (NPCs can't climb a car / dumpster / container) AND they route around its base. Use for SOLID, immovable
##   props. You must RE-BAKE the level's NavigationRegion3D after adding/moving one (it only changes the bake).
## - AVOID (dynamic): the prop becomes an RVO obstacle that avoidance-enabled NPCs steer around at RUNTIME — for
##   MOVABLE props (a thrown crate). Feeds its parent RigidBody/CharacterBody velocity to the avoidance sim so
##   agents predict its motion. NPCs ship with NavigationAgent3D avoidance ON, so this works with no extra setup.
##
## SETUP: drop it under the prop ROOT, next to the prop's CollisionShape3D. It auto-sizes its footprint from the
## parent's first CollisionShape3D (Box / Sphere / Capsule / Cylinder). Set `size_override` (XZ half-extents +
## half-height) to size it by hand for an odd shape or an off-centre collider.

enum Mode {
	CARVE,  ## static: carve the footprint out of the navmesh bake (re-bake after). For solid props.
	AVOID,  ## dynamic: an RVO obstacle agents steer around at runtime. For movable props (thrown crates).
}

## How this prop blocks navigation — CARVE (static, re-bake) for solid props, AVOID (dynamic) for movable ones.
@export var mode: Mode = Mode.CARVE:
	set(value):
		mode = value
		_apply()
## Manual footprint: XZ half-extents + half-height (Y). Leave ZERO to auto-size from the parent's CollisionShape3D.
@export var size_override: Vector3 = Vector3.ZERO:
	set(value):
		size_override = value
		_apply()

func _ready() -> void:
	_apply()  # authoritative pass once the parent + its collider exist (after .tscn load)
	# Only a dynamic (AVOID) obstacle needs to report its velocity each frame; a static carve doesn't move.
	set_physics_process(mode == Mode.AVOID and not Engine.is_editor_hint())

## Configure the underlying NavigationObstacle3D for the chosen mode + footprint. Safe off-tree (null parent ->
## fallback box), so the setters can call it live in the editor and _ready re-runs it after load.
func _apply() -> void:
	var e := _footprint()
	height = maxf(0.1, e.y * 2.0)
	if mode == Mode.CARVE:
		# Discard the prop's source geometry inside this shape during bake (no walkable roof) AND carve the
		# footprint hole so paths route around it. Static -> no runtime avoidance.
		affect_navigation_mesh = true
		carve_navigation_mesh = true
		avoidance_enabled = false
		radius = 0.0
		vertices = PackedVector3Array([
			Vector3(-e.x, 0.0, -e.z), Vector3(e.x, 0.0, -e.z),
			Vector3(e.x, 0.0, e.z), Vector3(-e.x, 0.0, e.z)])
	else:
		# Runtime RVO obstacle: a cylinder of `radius` agents steer around. Not part of the bake.
		affect_navigation_mesh = false
		carve_navigation_mesh = false
		avoidance_enabled = true
		vertices = PackedVector3Array()
		radius = maxf(0.1, maxf(e.x, e.z))

## A movable AVOID obstacle reports its parent body's velocity so the avoidance sim predicts where it's heading.
func _physics_process(_delta: float) -> void:
	var host := get_parent()
	if host is RigidBody3D:
		velocity = (host as RigidBody3D).linear_velocity
	elif host is CharacterBody3D:
		velocity = (host as CharacterBody3D).velocity

## The footprint half-extents (in OUR local space): the manual override when set, else read from the parent's
## first CollisionShape3D — SCALED by the collider's world scale relative to ours, so a prop authored as a giant
## shape shrunk by a node scale (e.g. the dumpster's 100×71×69 box) carves at its true size, not the raw shape.
func _footprint() -> Vector3:
	if size_override != Vector3.ZERO:
		return size_override
	var host := get_parent()
	if host != null:
		var cs := _find_shape(host)
		if cs != null and cs.shape != null:
			var ext := _extents(cs.shape)
			if cs.is_inside_tree() and is_inside_tree():
				var cs_s := cs.global_transform.basis.get_scale().abs()
				var my_s := global_transform.basis.get_scale().abs()
				ext *= Vector3(cs_s.x / maxf(my_s.x, 0.0001), cs_s.y / maxf(my_s.y, 0.0001), cs_s.z / maxf(my_s.z, 0.0001))
			return ext
	return Vector3(0.5, 0.5, 0.5)  # ~1 m box fallback (no collider found / off-tree)

## First CollisionShape3D with a shape under `node`, depth-first (skips self). Mirrors npc.gd's _find_skeleton idiom.
func _find_shape(node: Node) -> CollisionShape3D:
	for c in node.get_children():
		if c == self:
			continue
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			return c as CollisionShape3D
		var deeper := _find_shape(c)
		if deeper != null:
			return deeper
	return null

## Half-extents of a primitive shape (Box / Sphere / Capsule / Cylinder); a ~0.5 m fallback for anything else.
func _extents(shape: Shape3D) -> Vector3:
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size * 0.5
	if shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		return Vector3(r, r, r)
	if shape is CapsuleShape3D:
		var cp := shape as CapsuleShape3D
		return Vector3(cp.radius, cp.height * 0.5, cp.radius)
	if shape is CylinderShape3D:
		var cy := shape as CylinderShape3D
		return Vector3(cy.radius, cy.height * 0.5, cy.radius)
	return Vector3(0.5, 0.5, 0.5)

## EDITOR: warn when there's nothing to size from — neither a manual size nor a parent collider.
func _get_configuration_warnings() -> PackedStringArray:
	if size_override == Vector3.ZERO and _find_shape(get_parent()) == null:
		return PackedStringArray(["NavBlocker can't auto-size: no CollisionShape3D on the parent. Set size_override, or place it under a prop that has a collider."])
	return PackedStringArray()
