extends Node3D

## Per-actor gore controller — a child of each Character (and of gore gibs). Two
## gore paths with very different cost:
##   • particles() — heavy DEATH burst: a GPUParticles blast + DROP_COUNT physics
##     blood drops that fall and stain. Called from Character.gore() and the ram /
##     thrown-object kill paths. Fires once per death.
##   • splatter_at() — cheap PER-HIT path: raycast-placed decals only, no physics,
##     no SFX. Safe to call every shot (SMG-friendly).
## Also handles a gib's own death gore via _on_gore_gib_destroy (wired to the
## GoreGib `destroy` signal in gore_gib.tscn).

const BLOODY_MESS = preload("uid://yeq88l33gvle")

## Physics blood drops per death burst. High for a visceral splatter; tolerable now
## because BloodDropEmitter dribbles them in DROP_PER_FRAME at a time across several
## frames instead of registering all ~100 RigidBody3Ds with the physics server in a
## single frame, which used to hitch the game on every death. (Per-drop scatter and
## velocity live in BloodDropEmitter so the death rain and gib bursts match.)
const DROP_COUNT: int = 100
const DROP_PER_FRAME: int = 20
## Smaller secondary burst when one flung gib breaks on impact.
const GIB_DESTROY_DROPS: int = 5

## Death gore burst: spawn the blood GPUParticles at this actor's position (+offset)
## and rain DROP_COUNT physics drops. The particle node self-frees on finish.
func particles(_offset: Vector3) -> void:
	var _particles = BLOODY_MESS.instantiate()
	get_tree().root.add_child(_particles)
	_particles.global_position = global_position + _offset
	_particles.emitting = true
	_particles.finished.connect(_particles.queue_free)

	_rain_drops(_particles.global_position)

func _rain_drops(origin: Vector3) -> void:
	# Hand off to a persistent emitter that drips the drops in over several frames.
	# It lives under the scene root, so it keeps spawning after this character (and
	# its BloodyMess child) is freed at the end of this frame.
	var emitter := BloodDropEmitter.new()
	get_tree().root.add_child(emitter)
	emitter.start(origin, DROP_COUNT, DROP_PER_FRAME)

# Per-hit splatter spawns decals DIRECTLY via raycast — no physics drops,
# no collision callbacks, no SFX. Much cheaper than spawning RigidBody3Ds
# that fall and impact, important for high-fire-rate weapons like the SMG.
const BLOOD_SPLAT_DECAL = preload("uid://dg5ui5is8sakg")
const HIT_DECAL_COUNT: int = 5
const HIT_DECAL_SCAN_DISTANCE: float = 3.0
const HIT_DECAL_DIR_SPREAD: float = 0.6
const HIT_DECAL_DOWNWARD_BIAS_MIN: float = 0.3
const HIT_DECAL_DOWNWARD_BIAS_MAX: float = 1.5
const HIT_DECAL_SIZE_MIN: float = 0.3
const HIT_DECAL_SIZE_MAX: float = 0.8
const HIT_DECAL_GROW_TIME: float = 0.3
const HIT_DECAL_FADEOUT_DELAY: float = 4.0
const HIT_DECAL_CULL_MASK: int = 2
const HIT_DECAL_NORMAL_PARALLEL_THRESHOLD: float = 0.99

func splatter_at(world_pos: Vector3, hit_dir: Vector3, count: int = HIT_DECAL_COUNT, _silent: bool = true) -> void:
	# `_silent` kept for backwards-compat with the old physics-drop signature.
	var base_dir := hit_dir.normalized() if hit_dir.length() > 0.01 else Vector3.UP
	var space := get_world_3d().direct_space_state
	for i in count:
		# Scatter direction: bullet's travel direction + heavy downward bias so
		# decals tend to land on the floor below/behind the hit point.
		var dir := (base_dir + Vector3(
			randf_range(-HIT_DECAL_DIR_SPREAD, HIT_DECAL_DIR_SPREAD),
			-randf_range(HIT_DECAL_DOWNWARD_BIAS_MIN, HIT_DECAL_DOWNWARD_BIAS_MAX),
			randf_range(-HIT_DECAL_DIR_SPREAD, HIT_DECAL_DIR_SPREAD)
		)).normalized()
		var ray_end := world_pos + dir * HIT_DECAL_SCAN_DISTANCE
		var query := PhysicsRayQueryParameters3D.create(world_pos, ray_end)
		var result := space.intersect_ray(query)
		if result.is_empty():
			continue
		_spawn_hit_decal(result["position"], result["normal"])

func _spawn_hit_decal(pos: Vector3, normal: Vector3) -> void:
	var decal = BLOOD_SPLAT_DECAL.instantiate()
	var light := decal.get_node_or_null("BloodLight")
	if light:
		light.queue_free()
	var fadeout := decal.get_node_or_null("TimeTilFadeout")
	if fadeout and fadeout is Timer:
		(fadeout as Timer).wait_time = HIT_DECAL_FADEOUT_DELAY
	var s := randf_range(HIT_DECAL_SIZE_MIN, HIT_DECAL_SIZE_MAX)
	decal.target_size = Vector3(s, 0.05, s)
	decal.grow_time = HIT_DECAL_GROW_TIME
	decal.cull_mask = HIT_DECAL_CULL_MASK
	get_tree().root.add_child(decal)
	decal.global_position = pos + normal * GameSettings.effects.decal_normal_offset
	var up := normal
	var z: Vector3
	if absf(up.dot(Vector3.UP)) > HIT_DECAL_NORMAL_PARALLEL_THRESHOLD:
		z = Vector3.FORWARD.slide(up).normalized()
	else:
		z = Vector3.UP.slide(up).normalized()
	var x := up.cross(z).normalized()
	decal.global_transform.basis = Basis(x, up, z)


const GIB_FLOOR_DECAL_SIZE: float = 1.5
const GIB_FLOOR_DECAL_PROBE: float = 2.0
const GIB_FLOOR_DECAL_PARALLEL_THRESHOLD: float = 0.99

## Wired to a gore gib's `destroy` signal: when a flung gib breaks, leave a floor
## blood decal plus a smaller secondary burst (fewer particles + drops than a full
## death) so the scene keeps accumulating gore as gibs are destroyed.
func _on_gore_gib_destroy() -> void:
	_spawn_gib_floor_decal()
	var _particles = BLOODY_MESS.instantiate()
	get_tree().root.add_child(_particles)
	_particles.global_position = global_position
	_particles.emitting = true
	_particles.finished.connect(_particles.queue_free)
	_particles.amount = 50
	
	var emitter := BloodDropEmitter.new()
	get_tree().root.add_child(emitter)
	emitter.start(global_position, GIB_DESTROY_DROPS, GIB_DESTROY_DROPS)

func _spawn_gib_floor_decal() -> void:
	# Raycast down from the gib and drop an oriented blood splat on the floor,
	# the same way Character.spawn_blood_decal does for enemy deaths. The gib's
	# own RigidBody still exists when its `destroy` signal fires (queue_free is
	# deferred), so exclude it or the ray hits the gib itself.
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * GIB_FLOOR_DECAL_PROBE
	)
	var gib_body := get_parent()
	if gib_body is CollisionObject3D:
		query.exclude = [(gib_body as CollisionObject3D).get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return
	var decal = BLOOD_SPLAT_DECAL.instantiate()
	var light := decal.get_node_or_null("BloodLight")
	if light:
		light.queue_free()
	decal.target_size = Vector3(GIB_FLOOR_DECAL_SIZE, 0.15, GIB_FLOOR_DECAL_SIZE)
	decal.cull_mask = 2
	get_tree().root.add_child(decal)
	var normal: Vector3 = result["normal"]
	decal.global_position = result["position"] + normal * GameSettings.effects.decal_normal_offset
	var up := normal
	var z: Vector3
	if absf(up.dot(Vector3.UP)) > GIB_FLOOR_DECAL_PARALLEL_THRESHOLD:
		z = Vector3.FORWARD.slide(up).normalized()
	else:
		z = Vector3.UP.slide(up).normalized()
	var x := up.cross(z).normalized()
	decal.global_transform.basis = Basis(x, up, z)
	
