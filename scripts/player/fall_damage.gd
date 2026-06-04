class_name FallDamage

## Pure, stateless fall-damage formula — the HP a landing costs. Lifted out of Character so the
## arithmetic lives in one named place that both the player's landing block and the enemy's
## apply_velocity reach through Character._apply_fall_damage(). No state, no nodes: a static
## library, like the resolution helpers elsewhere (TalkHelpers and friends).
##
## Character keeps the fall_damage_min_speed / fall_damage_per_speed @exports (set per-actor in
## the editor) and the thin _apply_fall_damage() facade that calls take_damage; only the
## speed -> HP math moved here so it can't drift between callers.

## HP lost for a landing at `fall_speed` (downward m/s). A landing at or under `min_speed` is
## safe (0). Above it, the excess speed times `per_speed` is truncated to a whole HP — int() so a
## graze that doesn't clear a full point of damage costs nothing, matching the original inline
## `int(...)` in Character._apply_fall_damage. Never returns negative (the <= min_speed guard).
static func hp_loss(fall_speed: float, min_speed: float, per_speed: float) -> int:
	if fall_speed <= min_speed:
		return 0
	return int((fall_speed - min_speed) * per_speed)
