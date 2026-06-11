class_name LaserSight
extends Ability

## LASER SIGHT ability — drop under a Player to grant the swaying laser DOT that shows where a shot truly lands
## (the fixed crosshair stays at centre; the dot drifts with your aim wander).
##
## The dot's BEHAVIOUR lives on the gun's flash light (scenes/player/flash_light.gd), which gates its visibility
## on the wielder's has_mechanic(&"laser_sight") — so THIS node's presence is what lights it up. The dot is a
## gun-mounted visual, so this node stays a gate rather than re-housing the projection onto the player body.

func ability_id() -> StringName:
	return &"laser_sight"
