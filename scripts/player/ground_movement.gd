class_name GroundMovement

## Pure MOVEMENT-SPEED math, lifted verbatim out of Player._physics_process (M13). Stateless statics only — never
## instantiated. `compute_target_speed` folds every per-frame speed modifier (direction, crouch, slow-walk, scope, a
## drawn heavy weapon, crippled legs, encumbrance, the AGILITY stat, and active slow/haste status) into the one
## `target_speed` the ground/air lerp then chases. Kept a static reading the Player (rather than a Player method) so
## the speed curve is testable in isolation and reusable, without adding state to the god-object.
##
## The interleaved jump / bhop / blast-jump / slide / grapple / edge-friction control flow STAYS on Player — this owns
## ONLY the speed multiplier chain (the plan's byte-order-critical beats are not touched).

## The target ground speed for THIS frame, from the player's live state + the pressed input direction. `input_dir` is
## the raw WASD vector (y > 0 = backpedal, x-only = strafe). Reads GameSettings tuning + the player's crouch blend,
## scope, drawn weapon, limb/encumbrance/stat/status multipliers — identical order to the old inline block, so the
## value is byte-for-byte what Player produced before the extraction.
static func compute_target_speed(player: Player, input_dir: Vector2) -> float:
	var target_speed: float = GameSettings.player_movement.max_speed
	if input_dir.y > 0:
		target_speed = GameSettings.player_movement.max_speed * GameSettings.player_movement.backward_mult
	elif abs(input_dir.x) > 0 and input_dir.y == 0:
		target_speed = GameSettings.player_movement.max_speed * GameSettings.player_movement.strafe_mult
	target_speed = lerpf(target_speed, target_speed * GameSettings.player_crouch.speed_mult, player.crouch.crouch_t)
	# Run is opt-in: without the Run modifier, while sprint is locked out, or while aiming down sights (ADS pins you
	# to the walk tier — Player.sprint_blocked_by_scope()), fall back to the walk-speed tier.
	if player.crouch.crouch_t < 0.5 and (not Input.is_action_pressed(InputManager.action_run) or not player.can_sprint() or player.sprint_blocked_by_scope()):
		target_speed *= GameSettings.player_movement.walk_speed_mult
	# ...and ADS then slows that walk tier AGAIN by the scope penalty (the two stack by design).
	if player._is_scoped:
		target_speed *= GameSettings.weapon_general.scope_speed_mult
	# A heavy weapon slows you WHILE IT'S DRAWN (WeaponData.move_speed_multiplier); holstered = full
	# speed, FNV-style — mirrors the NPC's _current_move_speed gating on the same holster state.
	if player.weapon_system and player.weapon_system.attack and not player.weapon_system.attack.holstered and player.weapon_system.equipped_weapon:
		target_speed *= player.weapon_system.equipped_weapon.move_speed_multiplier
	target_speed *= player.limb_move_multiplier()  # crippled legs limp (locational damage)
	target_speed *= player.encumbrance_move_multiplier()  # over carry_capacity -> over-encumbered slog
	target_speed *= player.stats_or_default().move_speed_mult(player.status_stat_modifier(&"agility"))  # AGILITY (+ active buff): faster on foot per point
	target_speed *= player.status_move_multiplier()  # active StatusEffects (slow / haste)
	return target_speed
