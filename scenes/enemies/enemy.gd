class_name Enemy
extends Character

func apply_velocity():
	var horizontal := Vector2(velocity.x, velocity.z)
	var speed := horizontal.length()
	if speed > GameTuning.ENEMY_FRICTION_MIN_SPEED:
		var dt := get_physics_process_delta_time()
		var rate := GameTuning.ENEMY_GROUND_FRICTION if is_on_floor() else GameTuning.ENEMY_AIR_FRICTION
		var t := 1.0 - exp(-rate * dt)
		horizontal = horizontal.lerp(Vector2.ZERO, t)
		velocity.x = horizontal.x
		velocity.z = horizontal.y
	velocity += explosion_velocity
	move_and_slide()
	velocity -= explosion_velocity / blast_damp_divisor

func _on_damaged(_current_hp: float, _max_hp: float) -> void:
	FreezeFrame.freeze()

func _on_died() -> void:
	# Slightly more dramatic than the damage hitch: longer hold, slower time
	# scale, slower recovery. Gives the kill a satisfying beat.
	FreezeFrame.freeze(0.03, 0.05, 0.3)
