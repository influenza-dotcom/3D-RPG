class_name CharacterStats
extends Resource

## A character's RPG stat sheet — EVERY Character (player and NPC alike) carries one, set in the inspector
## by a designer. BASELINE (0) is neutral: every derived multiplier is exactly 1.0 and every bonus 0 at
## baseline, so an unsheeted (null) or all-baseline character leaves the game's existing balance untouched;
## builds matter only when a stat moves off baseline. Each effect is a pure, clamped formula consumed at ONE
## seam:
##   strength   -> carry_bonus()                 Character._apply_stats -> carry_capacity
##   endurance  -> max_hp_bonus()                Character._apply_stats (BEFORE hp seeds from max_hp)
##   persuasion -> buy/sell_price_mult()         Merchant.buy_price / sell_price (the trading character)
##   gunplay    -> sway_mult()                   AimSway amplitude (steadier aim wander)
##   streetwise -> rep_gain/loss_mult()          Reputation.add_reputation (gains bigger, losses smaller)
##   agility    -> move_speed_mult() + jump_mult() Player locomotion (faster on foot, higher jump)
## Dialogue skill checks (DialogueChoice.required_stat / required_value) read get_stat() by name.

const BASELINE := 0

@export_group("Attributes")
## STRENGTH. Each point above baseline (0) adds +2.0 carry capacity. 0 = neutral; negative = weaker.
@export var strength: int = BASELINE
## PERSUASION. Each point above baseline makes buying 4% cheaper and selling 4% dearer (clamped). Also gates dialogue checks. 0 = neutral prices.
@export var persuasion: int = BASELINE
## GUNPLAY. Each point above baseline steadies the aim wander by 8% (floored). 0 = neutral; higher = tighter shots.
@export var gunplay: int = BASELINE
## ENDURANCE. Each point above baseline adds +1.5 max HP (stamped at spawn). 0 = neutral; negative = frailer.
@export var endurance: int = BASELINE
## STREETWISE. Each point above baseline makes rep gains 8% bigger and rep losses 8% smaller. 0 = neutral; negative makes mistakes cost more.
@export var streetwise: int = BASELINE
## AGILITY. Each point above baseline makes you move 5% faster. 0 = neutral; negative = slower.
@export var agility: int = BASELINE

## Stat by name — for dialogue skill checks. An unknown name reads BASELINE, so a typo'd check neither
## trivially passes nor hard-fails.
func get_stat(stat: StringName) -> int:
	match stat:
		&"strength": return strength
		&"persuasion": return persuasion
		&"gunplay": return gunplay
		&"endurance": return endurance
		&"streetwise": return streetwise
		&"agility": return agility
	return BASELINE

## STRENGTH: +2.0 carry capacity per point over baseline.
func carry_bonus() -> float:
	return float(strength - BASELINE) * 2.0

## ENDURANCE: +1.5 max HP per point over baseline (the consumer clamps so HP never drops below 1).
func max_hp_bonus() -> float:
	return float(endurance - BASELINE) * 1.5

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

## ...and negative reputation 8% smaller (floored — a scandal always costs SOMETHING). A NEGATIVE streetwise
## runs this past 1.0: a street-naive character's mistakes cost MORE.
func rep_loss_mult() -> float:
	return maxf(0.2, 1.0 - float(streetwise - BASELINE) * 0.08)

## AGILITY: +5% move speed per point over baseline, floored so a deeply negative agility can't freeze you.
func move_speed_mult() -> float:
	return maxf(0.2, 1.0 + float(agility - BASELINE) * 0.05)

## AGILITY (also): +5% jump VELOCITY per point over baseline, floored. Jump HEIGHT scales with velocity squared,
## so a high-agility build springs noticeably higher; a deeply negative agility still hops a little (floor 0.2).
func jump_mult() -> float:
	return maxf(0.2, 1.0 + float(agility - BASELINE) * 0.05)
