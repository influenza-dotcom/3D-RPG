class_name Character
extends CharacterBody3D

signal damaged(current_hp: float, max_hp: float)
signal died()

const VELOCITY_DAMP_AFTER_BLAST_DIVISOR: float = 1.12

@export var max_hp: int = 10
var hp: int
@export var mesh: MeshInstance3D 

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
	velocity.y -= explosion_velocity.y / VELOCITY_DAMP_AFTER_BLAST_DIVISOR
	velocity.x -= explosion_velocity.x
	velocity.z -= explosion_velocity.z

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

@export var bloody_mess: Node3D 

func gore() -> void:
	bloody_mess.particles(Vector3.ZERO)
