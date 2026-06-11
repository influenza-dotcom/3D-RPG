class_name PlayerStats
extends Resource

## The player's RPG stat sheet. BASELINE (5) is neutral — every derived multiplier is exactly 1.0 and every
## bonus 0 at 5 — so the default sheet leaves the game's existing balance untouched; builds matter only when
## a stat moves off baseline. Each effect is a pure, clamped formula consumed at ONE seam:
##   strength   -> carry_bonus()                 Player._apply_stats -> carry_capacity
##   endurance  -> max_hp_bonus()                Player._apply_stats (BEFORE hp seeds from max_hp)
##   persuasion -> buy/sell_price_mult()         Merchant.buy_price / sell_price
##   gunplay    -> sway_mult()                   AimSway amplitude (steadier aim wander)
##   streetwise -> rep_gain/loss_mult()          Reputation.add_reputation (gains bigger, losses smaller)
## Dialogue skill checks (DialogueChoice.required_stat / required_value) read get_stat() by name.

const BASELINE := 0

@export var strength: int = BASELINE
@export var persuasion: int = BASELINE
@export var gunplay: int = BASELINE
@export var endurance: int = BASELINE
@export var streetwise: int = BASELINE

## Stat by name — for dialogue skill checks. An unknown name reads BASELINE, so a typo'd check neither
## trivially passes nor hard-fails.
func get_stat(stat: StringName) -> int:
	match stat:
		&"strength": return strength
		&"persuasion": return persuasion
		&"gunplay": return gunplay
		&"endurance": return endurance
		&"streetwise": return streetwise
	return BASELINE

## STRENGTH: ±2.0 carry capacity per point around baseline.
func carry_bonus() -> float:
	return float(strength - BASELINE) * 2.0

## ENDURANCE: ±5 max HP per point around baseline (the consumer clamps so HP never drops below 1).
func max_hp_bonus() -> float:
	return float(endurance - BASELINE) * 5.0

## PERSUASION: buying gets 4% cheaper per point over baseline, floored at half price...
func buy_price_mult() -> float:
	return maxf(0.5, 1.0 - float(persuasion - BASELINE) * 0.04)

## ...and selling earns 4% more per point, capped so haggling can't mint money out of a markdown.
func sell_price_mult() -> float:
	return minf(1.5, 1.0 + float(persuasion - BASELINE) * 0.04)

## GUNPLAY: the aim wander runs 8% steadier per point over baseline, floored so the gun never freezes solid.
func sway_mult() -> float:
	return maxf(0.2, 1.0 - float(gunplay - BASELINE) * 0.08)

## STREETWISE: positive reputation lands 8% bigger per point over baseline...
func rep_gain_mult() -> float:
	return maxf(0.2, 1.0 + float(streetwise - BASELINE) * 0.08)

## ...and negative reputation 8% smaller (floored — a scandal always costs SOMETHING). Below baseline this
## runs past 1.0: a street-naive character's mistakes cost MORE.
func rep_loss_mult() -> float:
	return maxf(0.2, 1.0 - float(streetwise - BASELINE) * 0.08)
