class_name PlayerAimSettings
extends Resource

## Tuning for the Deus Ex-style aim wander (AimSway): the gun's true aim drifts around the camera centre,
## and STANCE steadies it — moving is loose, standing still tighter, crouching tighter again. The *_deg
## values are the wander's angular amplitude; the crosshair tracks the drifted point (Player._update_crosshair)
## so the reticle never lies about where a shot will land.

@export var sway_moving_deg: float = 1.6     ## wander amplitude at full ground speed
@export var sway_standing_deg: float = 0.55  ## amplitude standing still — accuracy improves when planted
@export_range(0.0, 1.0) var sway_crouch_mult: float = 0.4  ## crouched multiplier on top (0.4 = 60% steadier again)
@export var sway_speed: float = 1.0          ## wander frequency scale (1.0 = the authored drift pace)
