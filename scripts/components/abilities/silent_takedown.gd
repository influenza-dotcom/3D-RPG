class_name SilentTakedownAbility
extends Ability

## SILENT-TAKEDOWN ability — install the Takedown Chip (resources/items/chip_takedown.tres) at a ChipInstaller to
## grant the quiet-kill verb. A fresh game ships with ZERO abilities (Player.starting_unlocks is empty), so the
## stealth kill must now be EARNED like every other upgrade (grapple / air-dash / laser-sight / …).
##
## Like AirDash, this node is a pure GATE: the verb's BEHAVIOUR lives in the always-present SilentTakedown player
## component (scripts/player/silent_takedown.gd), which runs its own _physics_process but stays INERT until its
## wielder has_mechanic(&"silent_takedown") — i.e. until THIS node is present + enabled under the Player. Because the
## takedown logic already lives in its own drop-in component (not a branch in a big script), this node is just the
## presence flag; there is nothing to re-house here, exactly as air_dash's launch code stays in attack.gd.
##
## The class is SilentTakedownAbility (not SilentTakedown) so it doesn't collide with the behaviour component's
## class_name; the AbilityRegistry keys off the FILENAME (silent_takedown.gd -> id silent_takedown), not the class.

func ability_id() -> StringName:
	return &"silent_takedown"
