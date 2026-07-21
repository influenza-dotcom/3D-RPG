extends Node3D

## Minimal duck-typed HOST for the BodyModelSwap that lives inside the CharacterPreview turntable. BodyModelSwap
## drives its arm/leg pose off its PARENT via duck-typed reads (get_parent().get(&"velocity"),
## host.is_holding_gun(), host.is_on_floor(), …) — that parent is normally a real NPC/Player. In the preview
## there is no real actor, so this stand-in parents the swap and answers just enough of that contract to pose it:
##   • is_holding_gun() -> `holding`   — true makes the swap RAISE the arms into the two-handed weapon hold, so a
##     mounted weapon reads as actually held (see character_preview.gd set_weapon()). False -> arms rest by the side.
##   • velocity = ZERO, is_on_floor() = true  — a standing, grounded actor: no walk-swing, no airborne flail.
## Everything else the swap reads (aim_distance, has_sensed_foe, is_fists_out, is_climbing, hp) is absent on purpose;
## BodyModelSwap's HostMethodHelper.try_call_bool falls back to safe defaults, and the null `hp` reads as ALIVE so
## the idle breathing keeps running. This node also carries the weapon hand anchor (added by the preview) so the
## mounted gun turns with the character on the turntable.
##
## No class_name on purpose — it's a private preview helper, preloaded by path from character_preview.gd, and kept
## off the global class cache (matching the CharacterPreview host chain's other path-preloaded helpers).

## Set by the preview: true while a weapon is mounted, so the swap raises the arms into the hold pose.
var holding: bool = false

## The swap reads velocity to decide walk-swing vs rest; a preview actor never moves.
var velocity: Vector3 = Vector3.ZERO

## Raise the arms to the two-handed hold when a weapon is mounted (BodyModelSwap._animate_limbs reads this via
## HostMethodHelper.try_call_bool). Without it the arms hang and a held gun floats disconnected from the hands.
func is_holding_gun() -> bool:
	return holding

## A standing preview actor is always grounded — keeps the legs at their rest gait (no airborne bicycle flail).
func is_on_floor() -> bool:
	return true
