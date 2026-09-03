extends Ability

## LASER SIGHT ability — drop under a Player (or install resources/items/chip_laser_sight.tres) and the gun gets
## the red DOT that shows where a shot truly lands: the fixed crosshair stays at screen centre while the dot
## drifts with your aim wander, so the sway you have always FELT becomes something you can read.
##
## Like BioScanner and ChessVisualizer this has no behaviour hooks — its presence plus the `enabled` flag IS the
## grant. The dot's behaviour lives on the camera rig's LaserSight node (scenes/player/laser_sight_rig.gd), which
## gates every frame on the wielder's has_mechanic(&"laser_sight"); this node is purely what answers that.
## The visual is gun-mounted, so it stays on the rig rather than being re-housed onto the player body.
##
## ⭐NO KEY, NO TOGGLE: own the chip and the sight is on. The sight was RETIRED once already precisely because it
## shared the flashlight's key and lost it when the torch claimed it, so it deliberately owns no binding now —
## the Implants tab's per-implant on/off switch (the `enabled` export the base class documents) is the only
## switch, and has_mechanic already reads it.
##
## ⭐NO `class_name`, matching the two newest abilities (bio_scanner / deep_scanner). Nothing references this
## type by name — AbilityRegistry finds it by the snake_case filename convention alone (LaserSight.tscn -> id
## laser_sight -> laser_sight.gd) — so a global class registration would buy nothing and cost a class-cache
## entry that has to exist before anything can parse.

func ability_id() -> StringName:
	return &"laser_sight"
