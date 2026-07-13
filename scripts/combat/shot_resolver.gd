class_name ShotResolver

## Stateless per-pellet shot math lifted off the Attack coordinator — pure functions that read no
## state of their own, so they're trivially unit-testable and shared without a node. The raycast
## loop in attack.gd still drives the trace (FreezeFrame, take_damage, audio, signal emits); it just
## hands each decision off to here: spread the pellet, work out its damage, scale the hitstop, decide
## whether a crit is allowed, and cap the decals. The hitstop tuning is designer knobs on
## GameSettings.weapon_general (hitstop_damage_reference / hitstop_crit_multiplier /
## hitstop_max_multiplier).

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
## the flat OVERKILL from the previous kill instead, with no re-applied multipliers. The weapon decides which
## STAT scales the hit via its EXPLICIT WeaponData.is_melee flag: a MELEE weapon scales with STRENGTH; a RANGED
## one with GUNPLAY — `strength_mod` / `gunplay_mod` fold in the matching active status buff (0 = none). (is_melee
## is authored, NOT inferred from effective_range — a hitscan melee weapon needs a POSITIVE reach to hit at all.)
static func resolve_damage(weapon: WeaponData, was_crit: bool, off_guard: bool, pierce: float, behind: bool = false, stats: CharacterStats = null, gunplay_mod: float = 0.0, strength_mod: float = 0.0) -> float:
	if pierce >= 0.0:
		return pierce
	return scaled_damage(weapon.damage, weapon.headshot_multiplier, weapon.sneak_attack_multiplier, was_crit, off_guard, weapon.backstab_multiplier, behind, stats, gunplay_mod, weapon.is_melee, strength_mod)

## A first hit's damage scaled by the crit (headshot), sneak (off-guard), and backstab (rear-arc) multipliers —
## the shared math behind BOTH resolve_damage (hitscan, from the WeaponData) and projectile.gd (from the
## projectile's OWN fields), so a pellet and a fired round scale identically instead of being hand-synced. Each
## multiplier applies only when its flag is set; backstab_mult/behind default to inert so old 5-arg calls are
## unchanged (and a default backstab_multiplier of 1.0 is a no-op even when behind).
static func scaled_damage(base: float, crit_mult: float, sneak_mult: float, was_crit: bool, off_guard: bool, backstab_mult: float = 1.0, behind: bool = false, stats: CharacterStats = null, gunplay_mod: float = 0.0, is_melee: bool = false, strength_mod: float = 0.0) -> float:
	var dmg := base \
			* (crit_mult if was_crit else 1.0) \
			* (sneak_mult if off_guard else 1.0) \
			* (backstab_mult if behind else 1.0)
	# PD-1: the SHOOTER's combat stat scales the hit. A MELEE weapon reads STRENGTH (melee_damage_mult); a RANGED
	# one reads GUNPLAY (weapon_damage_mult), with an extra headshot punch on a crit. The `*_mod` args fold in the
	# matching active status buff. DETERMINISTIC (no RNG) so seeded-spread tests are untouched; a null / baseline
	# sheet + no buff = 1.0 no-op either way. Projectiles are always ranged (they carry a projectile_scene), so they
	# call this with the default is_melee = false and get the gunplay path.
	if stats != null:
		if is_melee:
			dmg *= stats.melee_damage_mult(strength_mod)
		else:
			dmg *= stats.weapon_damage_mult(gunplay_mod)
			if was_crit:
				dmg *= stats.headshot_damage_bonus(gunplay_mod)
	return dmg

## The hitstop time multiplier for a hit of `dmg` damage: scales UP with the damage and again on a
## headshot, clamped so a huge overkill / stacked-crit hit can't lock the game up. The caller multiplies
## the weapon's BASE hitstop_duration / hitstop_recovery by this.
static func hitstop_multiplier(dmg: float, was_crit: bool) -> float:
	var mult: float = 1.0 + dmg / GameSettings.weapon_general.hitstop_damage_reference
	if was_crit:
		mult *= GameSettings.weapon_general.hitstop_crit_multiplier
	return minf(mult, GameSettings.weapon_general.hitstop_max_multiplier)

## Whether a crit (headshot) may apply to this collider from this source. The player is immune to
## headshots from NPCs — a one-shot to the head feels cheap — so an AI wielder's hit on the player is
## treated as a body shot. Player shots and NPC-vs-NPC crits are unaffected. The caller ANDs this with
## the actual headshot test, so a non-Character collider never reaches this (short-circuits before).
static func crit_allowed(collider: Object, from_ai: bool) -> bool:
	return not (from_ai and collider is Character and (collider as Character).is_in_group(Groups.PLAYER))

## Per-pellet blood decal count, capped so a multi-pellet weapon (shotgun) doesn't spawn dozens at once
## — at least 1, sharing a budget of 5 across the pellets.
static func decals_per_pellet(pellet_count: int) -> int:
	return maxi(1, int(5.0 / pellet_count))
