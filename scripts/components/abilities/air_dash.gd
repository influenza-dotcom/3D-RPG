class_name AirDash
extends Ability

## AIR DASH ability — drop under a Player to grant the scoped-attack launch (attack while aiming a melee weapon
## to fling yourself, Cruelty-Squad style, one dash per airtime).
##
## The dash's BEHAVIOUR is a WEAPON behaviour and lives in the attack system (scripts/combat/attack.gd:
## _do_launch_attack + the single-air-dash bookkeeping), which gates on the wielder's has_mechanic(&"air_dash")
## — so THIS node's presence is what enables it. Because the logic is owned by the weapon, not the player body,
## this node stays a gate; the launch code is not a player-child concern to re-house.

func ability_id() -> StringName:
	return &"air_dash"
