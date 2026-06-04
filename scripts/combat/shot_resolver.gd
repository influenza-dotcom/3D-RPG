class_name ShotResolver

## Stateless per-pellet shot math lifted off the Attack coordinator — pure functions that read no
## state of their own, so they're trivially unit-testable and shared without a node. The raycast
## loop in attack.gd still drives the trace (FreezeFrame, take_damage, audio, signal emits); it just
## hands each decision off to here: spread the pellet, work out its damage, scale the hitstop, decide
## whether a crit is allowed, and cap the decals. The hitstop tuning consts live here with the math
## that uses them.

## Hitstop-on-hit scaling — the per-weapon hitstop_duration / hitstop_recovery are the BASE feel; the
## actual freeze gets LONGER for a bigger hit. damage_factor = 1 + dmg / HITSTOP_DAMAGE_REFERENCE, so a
## HITSTOP_DAMAGE_REFERENCE-damage hit roughly doubles the freeze; a headshot multiplies on top by
## HITSTOP_CRIT_MULTIPLIER. The final multiplier is clamped to HITSTOP_MAX_MULTIPLIER so a huge overkill
## or stacked-crit hit punches hard without locking the game up. A sniper bodyshot barely freezes; a
## sniper headshot freezes HARD.
const HITSTOP_DAMAGE_REFERENCE: float = 25.0
const HITSTOP_CRIT_MULTIPLIER: float = 2.0
const HITSTOP_MAX_MULTIPLIER: float = 6.0

## Scatter a single pellet off the aim direction by `spread` radians on each of the aim basis's local
## X (pitch) and Y (yaw) axes. Two independent random rolls in [-spread, spread] — same two rolls, same
## order as the inline loop, so a fixed RNG seed reproduces the exact spread cone.
static func spread_direction(direction: Vector3, aim_basis: Basis, spread: float) -> Vector3:
	var pellet_direction := direction
	pellet_direction = pellet_direction.rotated(aim_basis.x, randf_range(-spread, spread))
	pellet_direction = pellet_direction.rotated(aim_basis.y, randf_range(-spread, spread))
	return pellet_direction

## Damage a single trace segment deals. The FIRST hit (pierce < 0) uses the weapon's full damage scaled
## by the crit (headshot) and sneak (off-guard) multipliers; a penetrating segment (pierce >= 0) carries
## the flat OVERKILL from the previous kill instead, with no re-applied multipliers.
static func resolve_damage(weapon: WeaponData, was_crit: bool, off_guard: bool, pierce: float) -> float:
	if pierce >= 0.0:
		return pierce
	return weapon.damage \
			* (weapon.headshot_multiplier if was_crit else 1.0) \
			* (weapon.sneak_attack_multiplier if off_guard else 1.0)

## The hitstop time multiplier for a hit of `dmg` damage: scales UP with the damage and again on a
## headshot, clamped so a huge overkill / stacked-crit hit can't lock the game up. The caller multiplies
## the weapon's BASE hitstop_duration / hitstop_recovery by this.
static func hitstop_multiplier(dmg: float, was_crit: bool) -> float:
	var mult := 1.0 + dmg / HITSTOP_DAMAGE_REFERENCE
	if was_crit:
		mult *= HITSTOP_CRIT_MULTIPLIER
	return minf(mult, HITSTOP_MAX_MULTIPLIER)

## Whether a crit (headshot) may apply to this collider from this source. The player is immune to
## headshots from NPCs — a one-shot to the head feels cheap — so an AI wielder's hit on the player is
## treated as a body shot. Player shots and NPC-vs-NPC crits are unaffected. The caller ANDs this with
## the actual headshot test, so a non-Character collider never reaches this (short-circuits before).
static func crit_allowed(collider: Object, from_ai: bool) -> bool:
	return not (from_ai and collider is Character and (collider as Character).is_in_group(&"Player"))

## Per-pellet blood decal count, capped so a multi-pellet weapon (shotgun) doesn't spawn dozens at once
## — at least 1, sharing a budget of 5 across the pellets.
static func decals_per_pellet(pellet_count: int) -> int:
	return maxi(1, int(5.0 / pellet_count))
