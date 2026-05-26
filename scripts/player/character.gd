class_name Character
extends CharacterBody3D

signal damaged(current_hp: float, max_hp: float)
signal died()

@export var blast_damp_divisor: float = 1.12

@export var max_hp: int = 10
var hp: int
@export var mesh: MeshInstance3D
const BLOOD_SPLAT_DECAL = preload("uid://dg5ui5is8sakg")
const CHARACTER_DUST = preload("uid://um6f8g8g6l7v")

var explosion_velocity: Vector3

var _blast_timer: float = 0.0

func _ready():
	hp = max_hp

func flash_red() -> void:
	if not mesh:
		return

	var mat: StandardMaterial3D = mesh.material_override
	if not mat:
		mat = StandardMaterial3D.new()
		mesh.material_override = mat

	mat.emission_enabled = true
	mat.emission = Color.BLACK
	mat.emission_energy_multiplier = 0.0

	if has_meta("flash_tween"):
		var old_tween: Tween = get_meta("flash_tween")
		if old_tween and old_tween.is_valid():
			old_tween.kill()

	var tween := create_tween()
	set_meta("flash_tween", tween)

	var peak_energy := 2.0
	tween.tween_property(mat, "emission", Color.RED, 0.1)
	tween.parallel().tween_property(mat, "emission_energy_multiplier", peak_energy, 0.1)
	tween.tween_property(mat, "emission", Color.BLACK, 0.15)
	tween.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.15)

func take_damage(_amount: int):
	flash_red()
	hp -= _amount
	damaged.emit(hp, max_hp)
	if hp <= 0:
		gore()
		die()

func die():
	died.emit()
	queue_free()

func heal(_amount: int):
	hp = min(hp + _amount, max_hp)
	damaged.emit(hp, max_hp)

func gravity(delta: float):
	if !is_on_floor():
		velocity += get_gravity() * delta

func apply_velocity():
	velocity += explosion_velocity
	move_and_slide()
	velocity -= explosion_velocity / blast_damp_divisor

func apply_velocity_launch_forward():
	move_and_slide()
	velocity -= explosion_velocity / blast_damp_divisor

func apply_blast():
	if explosion_velocity.length() > GameTuning.BLAST_MIN_MAGNITUDE:
		_blast_timer = GameTuning.BLAST_GRACE_TIMER

	if is_on_floor() and _blast_timer <= 0.0:
		explosion_velocity = Vector3.ZERO
		return

	var dt := get_physics_process_delta_time()
	_blast_timer -= dt
	var blast_t := 1.0 - pow(1.0 - GameTuning.BLAST_DECAY_RATE, dt * GameTuning.SMOOTHING_REFERENCE_FPS)
	explosion_velocity = explosion_velocity.lerp(Vector3.ZERO, blast_t)
	if explosion_velocity.length() < GameTuning.BLAST_MIN_MAGNITUDE:
		explosion_velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	gravity(delta)
	apply_blast()
	apply_velocity()

func spawn_blood_decal() -> void:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * 2.0
	)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)

	if result:
		var decal = BLOOD_SPLAT_DECAL.instantiate()
		get_tree().root.add_child(decal)

		decal.global_position = result.position + result.normal * 0.02

		decal.cull_mask = 2

		var up: Vector3 = result.normal
		var ref := Vector3.FORWARD if abs(up.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
		var right := ref.slide(up).normalized()
		var back := right.cross(up).normalized()
		decal.global_transform.basis = Basis(right, up, back)

@export var bloody_mess: Node3D

func gore() -> void:
	spawn_blood_decal()
	bloody_mess.particles(Vector3.ZERO)
	_notify_nearby_players_of_death()

func _notify_nearby_players_of_death() -> void:
	var players := get_tree().get_nodes_in_group("Player")
	for p in players:
		if p == self:
			continue
		if not p is Node3D:
			continue
		var d := global_position.distance_to(p.global_position)
		if d > GameTuning.BLOOD_SPLATTER_RANGE:
			continue
		var intensity := 1.0 - clampf(d / GameTuning.BLOOD_SPLATTER_RANGE, 0.0, 1.0)
		if p.has_method("on_nearby_death"):
			p.on_nearby_death(intensity)

func spawn_dust(intensity: float = 1.0) -> void:
	if not is_inside_tree():
		return
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * GameTuning.DUST_GROUND_PROBE_DISTANCE
	)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)
	var pos: Vector3 = result.position if result else global_position
	var dust: GPUParticles3D = CHARACTER_DUST.instantiate()
	get_tree().root.add_child(dust)
	dust.global_position = pos + Vector3.UP * GameTuning.DUST_GROUND_OFFSET
	var safe_intensity = max(intensity, 0.05)
	dust.scale = Vector3.ONE * safe_intensity
	dust.amount_ratio = clampf(safe_intensity, GameTuning.DUST_AMOUNT_RATIO_MIN, 1.0)
	dust.emitting = true
	dust.finished.connect(dust.queue_free)
