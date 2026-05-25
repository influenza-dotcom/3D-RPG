class_name Character
extends CharacterBody3D

signal damaged(current_hp: float, max_hp: float)
signal died()

const VELOCITY_DAMP_AFTER_BLAST_DIVISOR: float = 1.12

@export var max_hp: int = 10
var hp: int
@export var mesh: MeshInstance3D 
const BLOOD_SPLAT_DECAL = preload("uid://dg5ui5is8sakg")

var explosion_velocity: Vector3

var _blast_timer: float = 0.0

func _ready():
	hp = max_hp

func flash_red() -> void:
	# Find the main mesh (adjust path if needed)
	if not mesh:
		return

	# Use a material override so we don't destroy the original material
	var mat: StandardMaterial3D = mesh.material_override
	if not mat:
		mat = StandardMaterial3D.new()
		mesh.material_override = mat

	# Ensure emission is enabled
	mat.emission_enabled = true
	mat.emission = Color.BLACK
	mat.emission_energy_multiplier = 0.0

	# Kill any running flash tween to avoid stacking
	if has_meta("flash_tween"):
		var old_tween: Tween = get_meta("flash_tween")
		if old_tween and old_tween.is_valid():
			old_tween.kill()

	var tween = create_tween()
	set_meta("flash_tween", tween)

	# Flash to bright red, then back to black
	var peak_energy = 2.0
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
	velocity -= explosion_velocity / VELOCITY_DAMP_AFTER_BLAST_DIVISOR

func apply_velocity_launch_forward():
	move_and_slide()
	velocity -= explosion_velocity / VELOCITY_DAMP_AFTER_BLAST_DIVISOR

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
	# Raycast downward to find the floor
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * 2.0  # cast 2 units down
	)
	query.exclude = [self]  # ignore the enemy itself
	var result = space_state.intersect_ray(query)

	if result:
		var decal = BLOOD_SPLAT_DECAL.instantiate()
		get_tree().root.add_child(decal)

		decal.global_position = result.position + result.normal * 0.02
		
		decal.cull_mask = 2  # your decal cull mask (adjust if different)

		# Orient to surface normal
		var up = result.normal
		var ref = Vector3.FORWARD if abs(up.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
		var right = ref.cross(up).normalized()
		var forward = up.cross(right).normalized()
		decal.global_transform.basis = Basis(right, up, forward)

@export var bloody_mess: Node3D 

func gore() -> void:
	spawn_blood_decal()
	bloody_mess.particles(Vector3.ZERO)
