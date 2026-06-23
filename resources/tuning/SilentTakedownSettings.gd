class_name SilentTakedownSettings
extends Resource

## Slice 6b global tuning for the silent-takedown verb (GameSettings.takedown). It's a core player verb (not
## per-instance authored), so it lives as ONE GameSettings .tres like the other tuning groups. See SilentTakedown.

## Master switch. On by default (it's a shipped player ability) — flip off to disable the takedown verb entirely.
@export var enabled: bool = true
## Seconds the Takedown key must be HELD over an eligible target to commit (a short beat, not a tap).
@export_range(0.0, 3.0, 0.05) var hold_time: float = 0.55
## Max reach (m) from the camera to the target — melee range; the target must be under the crosshair within this.
@export_range(0.5, 6.0, 0.1) var max_range: float = 2.2
## Rear arc (degrees, FULL width) the attacker must be within behind the target — matches DamageApplier.is_behind.
@export_range(0.0, 360.0, 5.0) var behind_arc_degrees: float = 120.0
## Require the attacker to be BEHIND the target (within behind_arc_degrees). Off = a takedown from any angle.
@export var require_behind: bool = true
## Require the player to be CROUCHED to take down. Off by default — being unseen + behind is enough.
@export var require_crouch: bool = false
