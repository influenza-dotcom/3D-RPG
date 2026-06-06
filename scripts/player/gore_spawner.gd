class_name GoreSpawner
extends Node3D

## Everything an actor flings OUTWARD when it dies — the on-death gore burst. Lifted wholesale out
## of Character: the floor blood decal, the gib rigid bodies, the rigged-skeleton ragdoll corpse,
## and the "tell nearby players someone died" ping (drives their on-camera blood splatter + shake).
## Character keeps thin gore()/spawn_blood_decal() facades that delegate here.
##
## Code-built child of Character (added in its _ready). It reads the host for everything: its
## transform (decal/gib spawn point, corpse pose), its velocity + explosion_velocity (the launch the
## ragdoll inherits), its bloody_mess node, and the BLOOD_SPLAT_DECAL / GIB_* consts and
## gib_scene / ragdoll_scene @exports — all of which stay on the root so the editor/.tscn keep
## setting them per-actor. Nothing here holds state; it's a pure spawner driven off the host.

## The actor we belong to — set right after .new(), before add_child. Source of the spawn transform,
## the death launch (velocity + explosion_velocity), the bloody_mess node, and the gore consts/scenes.
var _host: Character

## Fire the full on-death gore sequence in the monolith's exact order: floor decal, the bloody_mess
## particle burst (if the actor has one), notify nearby players (camera splatter + shake), the gib
## rigid bodies, then the ragdoll corpse. Order is preserved — Character.gore() delegates straight here.
func run() -> void:
	spawn_blood_decal()
	if _host.bloody_mess:
		_host.bloody_mess.particles(Vector3.ZERO)
	_notify_nearby_players_of_death()
	spawn_gibs()
	_spawn_ragdoll()

## Spawn a flat blood splat decal on the floor beneath the host (on death). Raycasts straight down,
## orients the decal to the hit surface normal, and uses cull_mask = 2 (the world's decal render
## layer) so it lands on level geometry but not on view-model/gun meshes (which live on the gun
## layer). The gib floor-decal logic in bloody_mess.gd mirrors this.
func spawn_blood_decal() -> void:
	if not _host.is_inside_tree():
		return
	var space_state := _host.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		_host.global_position,
		_host.global_position + Vector3.DOWN * 2.0
	)
	query.exclude = [_host]
	var result := space_state.intersect_ray(query)

	if result:
		var decal = Character.BLOOD_SPLAT_DECAL.instantiate()
		_host.get_tree().root.add_child(decal)

		decal.global_position = result.position + result.normal * 0.02

		decal.cull_mask = 2

		var up: Vector3 = result.normal
		var z: Vector3
		if absf(up.dot(Vector3.UP)) > 0.99:
			z = Vector3.FORWARD.slide(up).normalized()
		else:
			z = Vector3.UP.slide(up).normalized()
		var x := up.cross(z).normalized()
		decal.global_transform.basis = Basis(x, up, z)

## Spawn the rigged-skeleton ragdoll corpse at the host's spot, launched the way it was knocked/blasted
## (the killing blow), if a ragdoll_scene is assigned. The model goes limp via its own script.
func _spawn_ragdoll() -> void:
	if _host.ragdoll_scene == null:
		return
	var corpse := _host.ragdoll_scene.instantiate()
	_sanitize_ragdoll_shapes(corpse)  # fix degenerate (0-size) bone capsules BEFORE they hit the physics server
	corpse.set(&"launch", _host.velocity + _host.explosion_velocity)  # match the death to how we died
	_attach_loot(corpse)  # make the skeleton itself lootable; the ragdoll lingers until emptied
	if corpse is Node3D:
		var c3d := corpse as Node3D
		c3d.position = _host.global_position  # added under root, so local == world
		c3d.rotation.y = _host.global_rotation.y  # face the way we were facing when we died
	_host.get_tree().root.add_child(corpse)

## If the dying actor carries items, attach a LootableCorpse (its look-at talk hitbox + a COPY of the
## backpack) as a child of the ragdoll, and hand the ragdoll the reference so it lingers until looted
## empty (see ragdoll.gd). The copy is independent, so freeing the dead actor can't drain the loot.
func _attach_loot(corpse: Node) -> void:
	var inv: CharacterInventory = _host.inventory
	if inv == null or inv.is_empty():
		return
	var who_v: Variant = _host.get(&"display_name")
	var who: String = who_v if who_v is String else ""
	var loot := LootableCorpse.new()
	loot.setup(inv, who)
	corpse.add_child(loot)
	corpse.set(&"loot", loot)

## Some rigged skeletons import a bone (often the root joint) with a zero-size collision capsule.
## Jolt refuses to build a 0 radius/height shape and spams an error the instant the corpse enters the
## tree. Walk the (not-yet-added) corpse and give any degenerate capsule/sphere a tiny valid size — on
## a DUPLICATED shape so we never resize a resource other bones might share.
func _sanitize_ragdoll_shapes(root: Node) -> void:
	for cs in root.find_children("*", "CollisionShape3D", true, false):
		var shape: Shape3D = (cs as CollisionShape3D).shape
		if shape is CapsuleShape3D:
			var cap := shape as CapsuleShape3D
			if cap.radius <= 0.0 or cap.height <= 0.0:
				var fixed := cap.duplicate() as CapsuleShape3D
				fixed.radius = maxf(fixed.radius, 0.03)
				fixed.height = maxf(fixed.height, fixed.radius * 2.0 + 0.02)
				(cs as CollisionShape3D).shape = fixed
		elif shape is SphereShape3D and (shape as SphereShape3D).radius <= 0.0:
			var fixed_sphere := shape.duplicate() as SphereShape3D
			fixed_sphere.radius = 0.03
			(cs as CollisionShape3D).shape = fixed_sphere

func spawn_gibs() -> void:
	if _host.gib_scene == null:
		return
	# Keep concurrent gibs under the cap — cull the oldest so a long fight doesn't leave hundreds around.
	_enforce_gib_cap(Character.GIB_COUNT)
	var spawned: Array[RigidBody3D] = []
	for i in Character.GIB_COUNT:
		var gib = _host.gib_scene.instantiate()
		_host.get_tree().root.add_child(gib)
		gib.begin_gib_lifetime(Character.GIB_LIFETIME, Character.GIB_FADE_TIME)  # &"gib" group + timed fade-out
		# Per-spawn fragility roll. Override hp after add_child so _ready (which
		# sets hp from data.max_hp) has already run. Some gibs survive impact,
		# others break on first contact.
		var random_hp := randi_range(Character.GIB_HP_MIN, Character.GIB_HP_MAX)
		gib.max_hp = random_hp
		gib.hp = random_hp
		gib.global_position = _host.global_position + Vector3(
			randf_range(-Character.GIB_SPAWN_OFFSET_XZ, Character.GIB_SPAWN_OFFSET_XZ),
			randf_range(Character.GIB_SPAWN_OFFSET_Y_MIN, Character.GIB_SPAWN_OFFSET_Y_MAX),
			randf_range(-Character.GIB_SPAWN_OFFSET_XZ, Character.GIB_SPAWN_OFFSET_XZ)
		)
		var dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(Character.GIB_UP_BIAS_MIN, Character.GIB_UP_BIAS_MAX),
			randf_range(-1.0, 1.0)
		).normalized()
		gib.linear_velocity = dir * randf_range(Character.GIB_VEL_MIN, Character.GIB_VEL_MAX)
		gib.angular_velocity = Vector3(
			randf_range(-Character.GIB_ANGULAR_RANGE, Character.GIB_ANGULAR_RANGE),
			randf_range(-Character.GIB_ANGULAR_RANGE, Character.GIB_ANGULAR_RANGE),
			randf_range(-Character.GIB_ANGULAR_RANGE, Character.GIB_ANGULAR_RANGE),
		)
		spawned.append(gib)
	# Mutual collision exceptions so gibs from this death don't collide with
	# each other on spawn — they'd otherwise overlap and the physics engine
	# would shove them apart at high speed, triggering self-damage instantly.
	for i in spawned.size():
		for j in range(i + 1, spawned.size()):
			spawned[i].add_collision_exception_with(spawned[j])

## Cull the oldest gibs so that spawning `incoming` more keeps the total at/under Character.GIB_MAX_ACTIVE.
## Gibs register in the &"gib" group (begin_gib_lifetime); the group is roughly insertion-ordered, so the
## front entries are the oldest — free those first.
func _enforce_gib_cap(incoming: int) -> void:
	var gibs := _host.get_tree().get_nodes_in_group(&"gib")
	var over: int = gibs.size() + incoming - Character.GIB_MAX_ACTIVE
	var i := 0
	while i < over and i < gibs.size():
		if is_instance_valid(gibs[i]):
			gibs[i].queue_free()
		i += 1

func _notify_nearby_players_of_death() -> void:
	var range_max := maxf(GameSettings.effects.blood_splatter_range, GameSettings.screen_shake.death_shake_range)
	var players := _host.get_tree().get_nodes_in_group("Player")
	for p in players:
		if p == _host:
			continue
		if not p is Node3D:
			continue
		var d := _host.global_position.distance_to(p.global_position)
		if d > range_max:
			continue
		if p.has_method("on_nearby_death"):
			p.on_nearby_death(d)
