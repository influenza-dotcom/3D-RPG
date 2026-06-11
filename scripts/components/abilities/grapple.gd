class_name Grapple
extends Ability

## GRAPPLE ability — drop under a Player to grant the grappling hook (an UpgradePickup grants it at runtime by
## adding this node; it's deliberately NOT a starting ability — you must FIND it).
##
## The grapple's BEHAVIOUR currently lives in the code-built GrappleHook node (scripts/components/grapple_hook.gd,
## created in Player._ready and yanked in the Player's physics step), which self-gates on has_mechanic(&"grapple")
## — so THIS node's presence is what switches it on. Folding the GrappleHook logic into this node (so the rope +
## pull are fully owned here) is the next step; the gate is already node-driven.

func ability_id() -> StringName:
	return &"grapple"
