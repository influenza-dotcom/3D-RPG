extends Node3D

const BLOODY_MESS = preload("uid://yeq88l33gvle")
const BLOOD_DROP = preload("res://scenes/effects/blood_drop.tscn")

const DROP_COUNT: int = 100
const DROP_SCATTER: float = 1.8
const DROP_VEL_MIN: float = 3.0
const DROP_VEL_MAX: float = 9.0

func particles(_offset: Vector3) -> void:
	var _particles = BLOODY_MESS.instantiate()
	get_tree().root.add_child(_particles)
	_particles.global_position = global_position + _offset
	_particles.emitting = true
	_particles.finished.connect(_particles.queue_free)

	_rain_drops(_particles.global_position)

func _rain_drops(origin: Vector3) -> void:
	for i in DROP_COUNT:
		var drop := BLOOD_DROP.instantiate()
		get_tree().root.add_child(drop)
		drop.global_position = origin + Vector3(
			randf_range(-DROP_SCATTER, DROP_SCATTER),
			randf_range(0.0, DROP_SCATTER),
			randf_range(-DROP_SCATTER, DROP_SCATTER)
		)
		var dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.6, 1.5),
			randf_range(-1.0, 1.0)
		).normalized()
		drop.linear_velocity = dir * randf_range(DROP_VEL_MIN, DROP_VEL_MAX)

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
