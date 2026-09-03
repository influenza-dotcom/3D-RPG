class_name FallDamage

const METERS_PER_SECOND_TO_MILES_PER_HOUR: float = 2.2369362920544

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
##
## ⭐ `per_speed` is the SCALED cost — Character.effective_fall_damage_per_speed(), not the raw
## `fall_damage_per_speed` export. See hp_scale() below for why, and note that the warning curve
## (lethal_speed / lethal_fraction) must be handed the SAME scaled number or the screen starts
## lying about a landing it is scoring by a different rule.
static func hp_loss(fall_speed: float, min_speed: float, per_speed: float) -> int:
	if fall_speed <= min_speed:
		return 0
	return int((fall_speed - min_speed) * per_speed)


## The multiplier the whole fall-damage curve rides on: this actor's CURRENT max HP against the max HP the
## curve was AUTHORED for. 1.0 at the reference, 2.0 at double it. `reference_max_hp` <= 0 means "don't scale"
## (1.0), which is also the honest answer for an actor whose baseline was never captured.
##
## ⭐ WHY FALL DAMAGE SCALES WITH MAX HP AT ALL. Without this, `fall_damage_per_speed` is an ABSOLUTE cost in
## whole HP, so every point of max HP you earn (strength, level-ups, perks, an implant) quietly buys fall
## IMMUNITY: the drop that took the shipped 4-HP player from full to dead is a survivable scratch at 20 HP,
## and the game's one universal terrain threat evaporates exactly as the rest of the game gets harder. Scaling
## the cost with max_hp fixes the FRACTION of your health a given drop costs, so height stays as dangerous at
## the end of the game as at the start, and the ledge you cannot jump off is the same ledge all game long.
##
## Note what this deliberately does NOT do: it reads max_hp, so being HURT never makes the ground hit harder.
## The damage is scored against the health bar you own; the health you have left decides whether it kills you
## (that is lethal_speed's job, one screen below).
static func hp_scale(max_hp: float, reference_max_hp: float) -> float:
	if reference_max_hp <= 0.0:
		return 1.0
	return maxf(max_hp, 0.0) / reference_max_hp


## User-facing impact speed for the fall-death card.
static func mph(fall_speed: float) -> int:
	return maxi(0, int(round(fall_speed * METERS_PER_SECOND_TO_MILES_PER_HOUR)))


# =================================================================================================
# The FALL WARNING curve — the screen's grayscale drain while you are still in the air
# =================================================================================================
#
# Cyberpunk 2077 answers one question while you fall, in one channel: "is this going to kill me?" The
# colour drains out of the frame as the answer approaches yes, and at yes the frame is completely grey.
# The three statics below are that question, as arithmetic, so the curve is assertable without a Player
# (the Landing.impact_for / StaminaManager.recovery_rate_for idiom). player.gd `_update_fall_grey` is
# the only caller — it reads the host state, takes the max of the two channels, and eases the release.
#
# They live on FallDamage rather than in a class of their own because the warning IS the damage formula
# read backwards: the same min_speed / per_speed a landing is scored against, asked as a fraction of the
# HP you have left rather than as whole points off it. Splitting them would let the warning drift from
# the damage it warns about, which is the one bug this feature cannot survive.


## Downward speed (m/s) at which a landing would cost `hp` — i.e. the speed that KILLS you right now. INF when
## no speed can ever do it (`per_speed` 0 = fall damage disabled on this actor, or hp already at/below 0), which
## the fraction below reads as "there is nothing to warn about".
##
## ⭐ IT MOVES WITH YOUR HEALTH, and that is the point rather than a side effect: a fall that is a scratch at full
## HP is a lethal fall at one point of it, so the screen has to go fully grey EARLIER when you are hurt. Reading
## `hp` (not `max_hp`) is what makes the full-grey frame mean "this kills YOU, now".
##
## ⭐ `per_speed` MUST be the max-HP-scaled cost (Character.effective_fall_damage_per_speed()), the same number
## hp_loss() is handed. Pass the raw export here and the warning silently drifts: with max HP bought up, the
## screen would promise a survivable landing that the scaled damage then kills you on. The pleasant consequence
## of scaling BOTH is that the speed which kills a healthy actor is a CONSTANT — hp/per_speed is max_hp over
## (per_speed x max_hp/reference), i.e. reference/per_speed, whatever the health bar has grown to.
static func lethal_speed(min_speed: float, per_speed: float, hp: float) -> float:
	if per_speed <= 0.0 or hp <= 0.0:
		return INF
	return min_speed + hp / per_speed


## 0..1: how far a landing at `fall_speed` sits between "starts to hurt" (`min_speed`, 0) and "kills you"
## (lethal_speed, 1). This is the grayscale drain — 0 leaves the frame in full colour, 1 is completely grey.
##
## Deliberately the UN-truncated damage, unlike hp_loss()'s `int()`: the warning is a continuous ramp the eye
## reads over a second or two, and quantising it to whole HP would step the drain in visible bands (with the
## shipped 4 HP / 0.5-per-speed player, four of them). hp_loss stays truncated because it is the actual cost.
##
## Below min_speed the numerator goes negative and the clamp returns 0, so a survivable fall never tints at all
## — a warning that fires on every hop is a warning nobody reads.
static func lethal_fraction(fall_speed: float, min_speed: float, per_speed: float, hp: float) -> float:
	var span := lethal_speed(min_speed, per_speed, hp) - min_speed
	if span <= 0.0 or span == INF:
		return 0.0
	return clampf((fall_speed - min_speed) / span, 0.0, 1.0)


## 0..1 for the OTHER lethal fall: the continuous-fall death (Player._update_continuous_fall_death), which kills
## you after `limit` unbroken seconds of descent no matter how the impact maths would have scored it. `elapsed`
## is the player's banked `_continuous_fall_time`; `lead` is how many of the final seconds the drain is spread
## over. Ramps 0 -> 1 across the LAST `lead` seconds before the limit, so an ordinary hop tints nothing.
##
## ⭐ THIS CHANNEL IS NOT REDUNDANT WITH THE ONE ABOVE, for two reasons. Fall immunity (the FallImmunity ability)
## zeroes the impact channel but does NOT stop the continuous-fall death — an immune player pitched into a void
## still dies, and with only the impact channel their screen would stay in full colour the whole way down. And
## an actor with `fall_damage_per_speed` at 0 has no impact channel at all. `lead` 0 switches it off outright.
static func void_fraction(elapsed: float, limit: float, lead: float) -> float:
	if limit <= 0.0 or lead <= 0.0:
		return 0.0
	var window := minf(lead, limit)  # a lead longer than the whole fall just means "drain across all of it"
	return clampf((elapsed - (limit - window)) / window, 0.0, 1.0)
