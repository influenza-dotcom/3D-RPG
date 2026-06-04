class_name NoiseEmitter
extends Node

## Computes how far the player's noise currently carries and writes it back to the host each frame —
## the stealth signal enemies hear. A decaying gunfire spike OR ground-speed footstep noise, whichever
## is louder; crouch-walking and being airborne are silent. Built in code under the Player and given a
## host ref right after .new().
##
## noise_radius (the value enemy Perception.can_hear() reads via player.get("noise_radius")) and the
## noise_* tuning exports stay ON THE PLAYER — this component only WRITES host.noise_radius from
## tick(delta). The gunfire spike is registered through gunfire() (from Player.on_weapon_fired).

var host: Player

var _gunfire_noise: float = 0.0

## Register a gunshot — the loud spike that nearby enemies hear, which then decays back to silence.
func gunfire() -> void:
	_gunfire_noise = host.noise_gunfire_radius

## One frame of noise: decay the gunfire spike, take the louder of it and the ground-speed footstep
## noise, and write the result back to host.noise_radius (0 = silent).
func tick(delta: float) -> void:
	_gunfire_noise = maxf(0.0, _gunfire_noise - host.noise_gunfire_decay * delta)
	var move_noise := 0.0
	if host.is_on_floor():
		var ground_speed := Vector2(host.velocity.x, host.velocity.z).length()
		move_noise = ground_speed * host.noise_move_per_speed * (1.0 - host.crouch.crouch_t)
	host.noise_radius = maxf(move_noise, _gunfire_noise)
