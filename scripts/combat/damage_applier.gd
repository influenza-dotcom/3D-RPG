class_name DamageApplier

## The shared hit-APPLICATION sequence for the two shot paths — the hitscan pellet trace (attack.gd) and the
## flying projectile (projectile.gd) — so the crit rule, the sneak gate, the pre-hit HP capture, and the
## take_damage dispatch are written ONCE instead of hand-synced (review initiative #7, "extract DamageApplier
## first"). Stateless statics in the ShotResolver mold: no nodes, no state, trivially unit-testable. The
## damage NUMBER itself still comes from ShotResolver (resolve_damage / scaled_damage); these decide how a
## computed hit LANDS on a victim. The callers keep their own continuation mechanics (the hitscan's
## seg/exclude pierce walk vs the projectile's un-consume-and-fly-on) and their own feedback/FX.

## Whether this hit lands as a CRIT: a headshot on a Character, allowed for this shooter. The player is
## immune to headshots from NPCs — a one-shot to the head feels cheap — so an AI wielder's hit on the player
## is treated as a body shot; player shots and NPC-vs-NPC crits are unaffected (ShotResolver.crit_allowed
## encodes that rule). Non-Characters (crates, props) never crit.
static func crit_for(collider: Object, hit_position: Vector3, from_ai: bool) -> bool:
	return collider is Character and (collider as Character).is_headshot(hit_position) \
			and ShotResolver.crit_allowed(collider, from_ai)

## Whether the victim is open to the SNEAK-attack multiplier — a Character that hasn't noticed a threat.
## Non-Characters can't be snuck up on.
static func off_guard_for(collider: Object) -> bool:
	return collider is Character and (collider as Character).is_off_guard()

## The victim's HP before the hit lands — the base for the OVERKILL (damage beyond the kill) both paths can
## carry on through whoever is behind. Characters and Throwables have HP; anything else reads 0.
static func hp_before(collider: Object) -> float:
	if collider is Character:
		return (collider as Character).hp
	if collider is Throwable:
		return float((collider as Throwable).hp)
	return 0.0

## Deal the damage. A Character takes the 4-arg form — hit_pos drives its directional damage arc and limb
## hits, with Vector3.INF the "no surface point" sentinel (its own default): the hitscan path passes the ray
## hit, the projectile path passes nothing (a flying round has never carried a surface point — a deliberate,
## preserved asymmetry). Everything else takes the strict 3-arg form: Throwable.take_damage accepts no 4th
## argument, so a uniform 4-arg dynamic call would be a runtime error.
static func apply(collider: Object, dmg: float, was_crit: bool, attacker: Node, hit_pos: Vector3 = Vector3.INF) -> void:
	if collider is Character:
		(collider as Character).take_damage(dmg, was_crit, attacker, hit_pos)
	else:
		collider.take_damage(dmg, was_crit, attacker)
