class_name Enemy
extends Character

## Enemy actor. NOTE: no AI/navigation here — an enemy has no self-locomotion; it
## moves ONLY when knocked (explosion_velocity from shots / explosions / rams) and
## then drifts to a stop via friction. Hit feedback (freeze-frame) lives here; HP,
## death gore, and the blast system are inherited from Character. _on_damaged /
## _on_died are wired to Character's `damaged` / `died` signals in the enemy scene.

## Overrides Character.apply_velocity to add horizontal friction so knockback decays:
## a blasted enemy slides/flies, then eases to rest (heavier friction grounded than
## airborne). Below a min speed friction is skipped so tiny residual velocities don't
## cost a lerp every frame. Same blast add/damp tail as the base apply_velocity.
func apply_velocity():
	var horizontal := Vector2(velocity.x, velocity.z)
	var speed := horizontal.length()
	if speed > GameSettings.physics_damage.enemy_friction_min_speed:
		var dt := get_physics_process_delta_time()
		var rate := GameSettings.physics_damage.enemy_ground_friction if is_on_floor() else GameSettings.physics_damage.enemy_air_friction
		var t := 1.0 - exp(-rate * dt)
		horizontal = horizontal.lerp(Vector2.ZERO, t)
		velocity.x = horizontal.x
		velocity.z = horizontal.y
	velocity += explosion_velocity
	var pre_move_velocity := velocity
	move_and_slide()
	_push_interactables(pre_move_velocity)
	velocity -= explosion_velocity / blast_damp_divisor

## Hitstop on every damage tick — a tiny global freeze that punches up impact feel.
func _on_damaged(_current_hp: float, _max_hp: float) -> void:
	FreezeFrame.freeze()

func _on_died() -> void:
	# Slightly more dramatic than the damage hitch: longer hold, slower time
	# scale, slower recovery. Gives the kill a satisfying beat.
	FreezeFrame.freeze(0.03, 0.05, 0.3)
