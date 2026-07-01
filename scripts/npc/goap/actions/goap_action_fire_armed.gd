class_name GoapActionFireArmed
extends GoapAction

## ALERTED-state combat for a gun-capable NPC. First _ensure_armed_from_backpack() runs every frame, so a
## disarmed NPC since GIVEN a weapon draws it now; the helper's guard is just an internal early-out. Then the
## FULL armed-combat body runs via the existing _act_alerted helper
## (close to engage range, track + dodge, charge the laser, reload-when-dry + bark, incoming beep, fire). We
## DELEGATE to _act_alerted rather than transcribe it so the within-frame interleaving (reload-while-closing,
## dodge-weave, charge-bleed) stays byte-for-byte. Decomposing it into smaller primitives can happen behind
## the same GoapAction contract later.
##
## Always RUNNING. Serves the Engage goal via the sentinel target_engaged. The armed/unarmed split keys on
## _can_fight_with_gun() (ammo OR a spare clip), NOT is_armed — so an armed-but-dry-no-clips NPC falls to
## FireUnarmed (fists). is_runtime_valid re-checks live state + can_fight so a mid-fight
## disarm/dry-out forces a replan to FireUnarmed, and a perception change replans to Detect/Investigate/Hold.

func _init() -> void:
	super(&"FireArmed", 0.5, {&"state_alerted": true, &"can_fight_with_gun": true}, {&"target_engaged": true})

func act(host, delta: float) -> int:
	host._ensure_armed_from_backpack()
	host._act_alerted(delta)
	return Status.RUNNING

func is_runtime_valid(host) -> bool:
	# `not is_fleeing()` is the mirror of GoapActionFlee: a temperament FIGHT->FLEE flip happens only while
	# ALERTED (so this is the current action), and it does NOT change perception state or ammo — without this
	# gate is_runtime_valid would stay true, the executor would never replan, and the flipped coward would keep
	# firing instead of bolting. The flip invalidates this -> replan -> Survive/Flee, same tick.
	return host._perception != null and host._perception.state == Perception.State.ALERTED \
			and host._can_fight_with_gun() and not host.is_fleeing()
