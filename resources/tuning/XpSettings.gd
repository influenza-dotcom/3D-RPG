class_name XpSettings
extends Resource

## Global XP / leveling tuning. xp_to_reach(n) = cumulative XP to REACH level n (level 0 = 0 XP). Each level
## CROSSED grants points_per_level skill (perk) points. Read as GameSettings.xp.<field>; authored as
## resources/tuning/XpSettings.tres. A gentle quadratic ramp from two knobs — no Curve resource needed (a Curve's
## 0..1 x-domain doesn't map to arbitrary levels).

## XP for the FIRST level (the linear term). Higher = slower early leveling.
@export var base_xp: float = 100.0
## Added growth per level (the quadratic term): xp_to_reach(n) = base_xp*n + per_level_growth*n*(n-1)/2.
@export var per_level_growth: float = 50.0
## Skill (perk) points granted per level gained. 1 = one pick per level.
@export var points_per_level: int = 1
## XP awarded per NPC kill (a flat bounty). 0 = kills give no XP.
@export var xp_per_kill: float = 25.0

## Cumulative XP required to REACH `level` (level <= 0 -> 0).
func xp_to_reach(level: int) -> float:
	if level <= 0:
		return 0.0
	return base_xp * float(level) + per_level_growth * float(level) * float(level - 1) * 0.5

## The level a given total `xp` corresponds to: the highest L with xp_to_reach(L) <= xp. The `> previous` guard
## makes it terminate even on a degenerate (non-increasing) ramp; the 9999 cap is a second backstop.
func level_for_xp(xp: float) -> int:
	var lvl := 0
	while lvl < 9999 and xp_to_reach(lvl + 1) <= xp and xp_to_reach(lvl + 1) > xp_to_reach(lvl):
		lvl += 1
	return lvl
