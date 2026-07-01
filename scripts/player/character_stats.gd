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
##   gunplay    -> sway_mult() + weapon_damage_mult() + headshot_damage_bonus()  AimSway + ShotResolver.scaled_damage
##   streetwise -> rep_gain/loss_mult()          Reputation.add_reputation (gains bigger, losses smaller)
##   agility    -> move_speed_mult() + jump_mult() Player locomotion (faster on foot, higher jump)
## Dialogue skill checks (DialogueChoice.required_stat / required_value) read get_stat() by name.
##
## Active StatusEffect.stat_modifiers fold into the MULTIPLIER derived methods below via an optional additive
## `bonus` arg (0.0 = unbuffed, so every existing call is unchanged): each live seam passes
## Character.status_stat_modifier(<stat>). strength/endurance are excluded — they're stamped once into
## carry_capacity/max_hp at spawn (not read live), so their modifiers aren't consumed yet. get_stat() stays RAW
## (the permanent build), so a temporary buff never opens a dialogue check or a stat-gate.

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

## The stat names a designer references by string -- the SINGLE source for the dialogue skill-check dropdown
## (DialogueChoice.required_stat) and the stat-iterating UIs, so the list can't drift from these attributes /
## get_stat. A drift test (test_player_stats.gd) pins that every name round-trips through get_stat.
static func stat_names() -> PackedStringArray:
	return PackedStringArray(["strength", "persuasion", "gunplay", "endurance", "streetwise", "agility"])

## Comma-separated stat names for a PROPERTY_HINT_ENUM_SUGGESTION hint_string.
static func stat_names_csv() -> String:
	return ",".join(stat_names())

## STRENGTH: +2.0 carry capacity per point over baseline.
func carry_bonus() -> float:
	return float(strength - BASELINE) * 2.0

## ENDURANCE: +1.5 max HP per point over baseline (the consumer clamps so HP never drops below 1).
func max_hp_bonus() -> float:
	return float(endurance - BASELINE) * 1.5

## PERSUASION: buying gets 4% cheaper per point over baseline, floored at half price... The optional `bonus`
## folds in an active status-effect persuasion modifier (0 = none, so unbuffed prices are unchanged).
func buy_price_mult(bonus: float = 0.0) -> float:
	return maxf(0.5, 1.0 - float(persuasion - BASELINE + bonus) * 0.04)

## ...and selling earns 4% more per point, capped so haggling can't mint money out of a markdown.
func sell_price_mult(bonus: float = 0.0) -> float:
	return minf(1.5, 1.0 + float(persuasion - BASELINE + bonus) * 0.04)

## GUNPLAY: the aim wander runs 8% steadier per point over baseline, floored so the gun never freezes solid.
func sway_mult(bonus: float = 0.0) -> float:
	return maxf(0.2, 1.0 - float(gunplay - BASELINE + bonus) * 0.08)

## GUNPLAY (PD-1): weapons hit 5% harder per point over baseline — the shooter's damage scale, read in
## ShotResolver.scaled_damage. Floored so a deeply negative gunplay still deals something. 1.0 at baseline, so an
## unsheeted / baseline character's damage is unchanged. This is what makes a "gunner build" do visibly more DPS.
func weapon_damage_mult(bonus: float = 0.0) -> float:
	return maxf(0.2, 1.0 + float(gunplay - BASELINE + bonus) * 0.05)

## GUNPLAY (also, PD-1): headshots land an extra 5% per point over baseline, multiplied ON TOP of the weapon's
## headshot multiplier and applied only on a crit. Floored at 0.5 so a negative gunplay can't erase the headshot.
func headshot_damage_bonus(bonus: float = 0.0) -> float:
	return maxf(0.5, 1.0 + float(gunplay - BASELINE + bonus) * 0.05)

## STREETWISE: positive reputation lands 8% bigger per point over baseline...
func rep_gain_mult(bonus: float = 0.0) -> float:
	return maxf(0.2, 1.0 + float(streetwise - BASELINE + bonus) * 0.08)

## ...and negative reputation 8% smaller (floored — a scandal always costs SOMETHING). A NEGATIVE streetwise
## runs this past 1.0: a street-naive character's mistakes cost MORE.
func rep_loss_mult(bonus: float = 0.0) -> float:
	return maxf(0.2, 1.0 - float(streetwise - BASELINE + bonus) * 0.08)

## AGILITY: +5% move speed per point over baseline, floored so a deeply negative agility can't freeze you.
func move_speed_mult(bonus: float = 0.0) -> float:
	return maxf(0.2, 1.0 + float(agility - BASELINE + bonus) * 0.05)

## AGILITY (also): +5% jump VELOCITY per point over baseline, floored. Jump HEIGHT scales with velocity squared,
## so a high-agility build springs noticeably higher; a deeply negative agility still hops a little (floor 0.2).
func jump_mult(bonus: float = 0.0) -> float:
	return maxf(0.2, 1.0 + float(agility - BASELINE + bonus) * 0.05)
