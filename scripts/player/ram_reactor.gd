class_name RamReactor
extends Node

## Body-impact reactions read off the player's per-frame motion: a body-CHECK that damages enemies you
## ram into at speed, a loud air THUMP when you slam into something mid-air, and a pinball BOUNCE that
## reflects you off a fast-rammed surface. Built in code under the Player and given a host ref right
## after .new(); the Player keeps the ram/thump/bounce @export tuning + RAM_BOUNCE_FLOOR_DOT (a unit
## test reads them off a bare instance) and a thin _check_bounce wrapper, while the cooldown counters
## live here as private state.
##
## Driven once per physics frame from Player._physics_process via tick(delta, pre_velocity) AFTER
## apply_velocity() — pre_velocity is the pre-move velocity, since the slide response has already bled
## off `velocity` by the time these run (checking `velocity` would almost always fail).

var host: Player

var _ram_cooldown: float = 0.0
var _thump_cooldown: float = 0.0
var _bounce_cooldown: float = 0.0

## Run all three impact checks for this frame, in the same order the monolith did.
func tick(delta: float, pre_velocity: Vector3) -> void:
	_check_ram_damage(delta, pre_velocity)
	_check_air_thump(delta, pre_velocity)
	_check_bounce(delta, pre_velocity)

func _check_air_thump(delta: float, pre_velocity: Vector3) -> void:
	# Loud thump when slamming into something mid-air at speed. Triggered by a
	# sudden frame-over-frame speed drop (a real impact) rather than mere contact,
	# so sliding along a wall doesn't machine-gun the sound.
	if _thump_cooldown > 0.0:
		_thump_cooldown -= delta
		return
	if host.is_on_floor():
		return
	if host.get_slide_collision_count() == 0:
		return
	var speed_lost := pre_velocity.length() - host.velocity.length()
	if speed_lost < host.thump_min_speed_lost:
		return
	if host.thump_sound:
		AudioManager.play_2d_sfx(host.thump_sound, host.thump_volume_db, randf_range(0.9, 1.05))
	_thump_cooldown = host.thump_cooldown

func _check_bounce(delta: float, pre_velocity: Vector3) -> void:
	# Pinball-style rebound: ramming a wall / object / enemy at speed reflects you
	# back off the surface. Routed through the decaying blast impulse so the
	# rebound carries you off the wall instead of being killed by the move lerp.
	if _bounce_cooldown > 0.0:
		_bounce_cooldown -= delta
		return
	if pre_velocity.length() < host.ram_bounce_min_speed:
		return
	for i in host.get_slide_collision_count():
		var col := host.get_slide_collision(i)
		var normal := col.get_normal()
		if normal.y > Player.RAM_BOUNCE_FLOOR_DOT:
			continue  # ignore the floor so fast landings don't pop you upward
		var into_speed := -pre_velocity.dot(normal)
		if into_speed < host.ram_bounce_min_speed:
			continue
		host.explosion_velocity += normal * into_speed * host.ram_bounce_factor
		if host.screen_shake:
			host.screen_shake.shake(host.ram_bounce_shake)
		if host.ram_bounce_sound:
			AudioManager.play_2d_sfx(host.ram_bounce_sound, 0.0, randf_range(0.95, 1.1))
		_bounce_cooldown = host.ram_bounce_cooldown
		break

func _check_ram_damage(delta: float, pre_velocity: Vector3) -> void:
	# Body-check: if moving fast enough, damage enemies we slid into this frame.
	# Use pre_velocity — the collision response already bled off `velocity` by
	# the time this runs, so checking `velocity` here would almost always fail.
	if _ram_cooldown > 0.0:
		_ram_cooldown -= delta
		return
	if pre_velocity.length() < GameSettings.physics_damage.ram_min_speed:
		return
	for i in host.get_slide_collision_count():
		var collider := host.get_slide_collision(i).get_collider()
		if collider is NPC:
			var enemy := collider as Character
			if enemy.hp <= 0:
				continue  # already dying — don't ram a corpse
			# Allies are immune to body-ram: a recruited companion (following us) or any non-hostile
			# (friendly/neutral) NPC takes no damage or knockback — you just barge past them. The pinball
			# bounce (separate _check_bounce path) still rebounds you off their body for the feel.
			var npc := collider as NPC
			if npc.is_following() or not npc.is_hostile():
				continue
			var dmg := maxi(1, int(round(pre_velocity.length() * GameSettings.physics_damage.ram_damage_per_speed)))
			EffectFactory.spawn_blood_particle(enemy.global_position)
			if enemy.bloody_mess:
				enemy.bloody_mess.splatter_at(enemy.global_position, pre_velocity)
			enemy.take_damage(dmg, false, host)  # attribute the ram to the player (bounty + fall credit)
			# Bowling-strike sfx ONLY on a ram kill; a non-lethal ram gets a heavy thud.
			if enemy.hp <= 0:
				host.bowling_sfx.play()
			elif host.ram_thud_sound:
				AudioManager.play_sfx(enemy.global_position, host.ram_thud_sound, 0.0, randf_range(0.95, 1.05))

			enemy.explosion_velocity += pre_velocity.normalized() * GameSettings.physics_damage.ram_knockback
			_ram_cooldown = GameSettings.physics_damage.ram_cooldown
			host.white_flash.visible = true
			await get_tree().create_timer(0.085).timeout
			host.white_flash.visible = false
			break
