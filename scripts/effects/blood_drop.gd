extends RigidBody3D

const BLOOD_SPLAT_DECAL = preload("uid://dg5ui5is8sakg")

@export var impact_sfx: AudioStreamPlayer3D

const PITCH_MIN: float = 0.7
const PITCH_MAX: float = 1.4

const DECAL_SIZE_MIN: float = 0.4
const DECAL_SIZE_MAX: float = 1.2
const DECAL_GROW_TIME: float = 0.4
const DECAL_FADEOUT_DELAY: float = 4.0
const DECAL_CULL_MASK: int = 2
const NORMAL_PARALLEL_THRESHOLD: float = 0.99
const RAYCAST_BACKOFF: float = 0.1
const RAYCAST_FORWARD: float = 0.4

var silent: bool = false
var _consumed: bool = false

func _on_body_entered(_body) -> void:
	if _consumed:
		return
	_consumed = true
	_spawn_impact_decal()
	if not silent and impact_sfx:
		impact_sfx.reparent(get_tree().root)
		impact_sfx.global_position = global_position
		impact_sfx.pitch_scale = randf_range(PITCH_MIN, PITCH_MAX)
		impact_sfx.play()
		impact_sfx.finished.connect(impact_sfx.queue_free)
	queue_free()

func _spawn_impact_decal() -> void:
	# Raycast in the velocity direction to find the surface we just hit and its
	# normal, so the decal can be aligned to the surface (walls, ramps, etc.).
	var motion_dir := linear_velocity.normalized() if linear_velocity.length() > 0.01 else Vector3.DOWN
	var space_state := get_world_3d().direct_space_state
	var origin := global_position - motion_dir * RAYCAST_BACKOFF
	var target := global_position + motion_dir * RAYCAST_FORWARD
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return

	var decal = BLOOD_SPLAT_DECAL.instantiate()
	# Don't include the per-drop pulsing light — many drops landing at once
	# would stack too many lights. The death splat at the corpse keeps its light.
	var light := decal.get_node_or_null("BloodLight")
	if light:
		light.queue_free()
	var fadeout := decal.get_node_or_null("TimeTilFadeout")
	if fadeout and fadeout is Timer:
		(fadeout as Timer).wait_time = DECAL_FADEOUT_DELAY
	var s := randf_range(DECAL_SIZE_MIN, DECAL_SIZE_MAX)
	decal.target_size = Vector3(s, 0.05, s)
	decal.grow_time = DECAL_GROW_TIME
	decal.cull_mask = DECAL_CULL_MASK
	get_tree().root.add_child(decal)
	decal.global_position = result["position"] + result["normal"] * GameSettings.effects.decal_normal_offset
	_orient_to_normal(decal, result["normal"])

func _orient_to_normal(decal: Decal, normal: Vector3) -> void:
	var up := normal
	var z: Vector3
	if absf(up.dot(Vector3.UP)) > NORMAL_PARALLEL_THRESHOLD:
		z = Vector3.FORWARD.slide(up).normalized()
	else:
		z = Vector3.UP.slide(up).normalized()
	var x := up.cross(z).normalized()
	decal.global_transform.basis = Basis(x, up, z)
