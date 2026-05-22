extends Character

const SPEED = 5.0
const SPEED_LERPF_RATIO = .135

const JUMP_VELOCITY = 4.5


func _physics_process(delta: float) -> void:
	gravity(delta)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	
	if is_on_floor():
		velocity.x = lerpf(velocity.x, direction.x * SPEED, SPEED_LERPF_RATIO)
		velocity.z = lerpf(velocity.z, direction.z * SPEED, SPEED_LERPF_RATIO)
	else:
		velocity.x = lerpf(velocity.x, direction.x * SPEED, SPEED_LERPF_RATIO/10.0)
		velocity.z = lerpf(velocity.z, direction.z * SPEED, SPEED_LERPF_RATIO/10.0)

	apply_blast()
	apply_velocity()

func _on_mouse_input_rotate(_amt: Vector2) -> void:
	rotate_y(_amt.y)
