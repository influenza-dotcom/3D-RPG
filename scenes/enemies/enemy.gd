extends Character

func apply_velocity():
	
	var horizontal = Vector2(velocity.x, velocity.z)
	var speed = horizontal.length()
	if speed > 0.01:  # tiny threshold to avoid jitter
		# Higher friction when on ground, gentler in air
		var friction = 0.90 if is_on_floor() else 0.98
		horizontal *= friction
		velocity.x = horizontal.x
		velocity.z = horizontal.y
	
	velocity += explosion_velocity
	move_and_slide()
	velocity -= explosion_velocity / VELOCITY_DAMP_AFTER_BLAST_DIVISOR


func _on_damaged(current_hp: float, max_hp: float) -> void:
	FreezeFrame.freeze()
