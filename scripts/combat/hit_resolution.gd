class_name HitResolution

## The shared post-`take_damage` per-victim payout for a Character hit. A hitscan pellet (DamageTrace.run_pellet) and
## a fired round (Projectile._on_body_entered) both, AFTER landing the damage and re-reading the real post-mitigation
## HP loss, run the SAME collateral-bounty rule. This was two near-identical inline copies (damage_trace.gd /
## projectile.gd); it now lives in ONE place so the bounty amounts + the "kill that follows a kill" gate can't drift
## apart. Stateless static in the DamageApplier / ShotResolver mold (never instantiated; the bare-Attack/-projectile
## unit tests can reach it off-tree).
##
## DELIBERATELY NARROW — this owns ONLY the collateral payout + the kill report. What it does NOT own, and why:
##  * landing the damage (`DamageApplier.apply` + the pre/post-mitigation HP read) — that's ALREADY the shared seam,
##    and it also serves the non-Character take_damage path (Throwables), so it stays inline in each caller. The
##    projectile applies with hit_pos = Vector3.INF (a flying round carries no surface point — a deliberate,
##    position-agnostic asymmetry vs the raycast path); leaving apply in the caller preserves that by construction.
##  * hitstop — HITSCAN-ONLY (a projectile has no WeaponData / FreezeFrame call), so it's not duplicated; it stays
##    inline in damage_trace at its original beat (moving it here would reorder the per-victim feedback sequence).
##  * damage SCALING (the pierce models differ), knockback, impact audio, hitmarkers, sneak toast, and the overkill
##    pierce control flow — all path-specific, all stay in their callers.

## Pay the COLLATERAL bounty for this hit and report whether it was a lethal blow on a LIVING Character.
## `loss` is the REAL post-mitigation HP lost (hp_before - hp_after) — the caller measures it because armour / DR can
## drop it below the dealt damage, and the kill / pierce / collateral checks must all run off the real loss (a
## pre-mitigation value would count an armoured SURVIVOR as killed). `prior_kill` is the caller's latch that a
## Character already died to this same pellet / round; when a kill lands with that set, the shooter earns an extra
## bounty (the headshot variant on a crit). `attacker` may be null (an unattributed projectile whose shooter died
## mid-flight) — no payout then. Returns true when this was a lethal blow on a living victim (hp_before > 0 and
## loss >= hp_before), so the caller can set ITS OWN latch for whoever dies BEHIND this victim.
static func award_collateral_kill(loss: float, hp_before: float, was_crit: bool, attacker: Character, prior_kill: bool) -> bool:
	if hp_before <= 0.0 or loss < hp_before:
		return false  # not a lethal blow on a living victim — a pierce through an already-dead body, or a survivor
	if prior_kill and attacker != null:
		# Sizes are designer knobs — resources/tuning/EconomySettings.tres.
		var collateral_pay: float = GameSettings.economy.collateral_headshot_bounty if was_crit \
				else GameSettings.economy.collateral_bounty
		attacker.reward_kill(collateral_pay)
		if attacker.has_method(&"notify_toast"):
			attacker.notify_toast("[PH] Collateral kill!  +%s zm" % Zorkmids.fmt(collateral_pay), Color(1.0, 0.86, 0.3))
	return true
