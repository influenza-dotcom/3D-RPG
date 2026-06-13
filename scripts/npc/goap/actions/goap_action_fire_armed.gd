class_name GoapActionFireArmed
extends GoapAction

## ALERTED-state combat for a gun-capable NPC. Mirrors the FSM ALERTED arm (npc.gd:1423-1426): first
## _ensure_armed_from_backpack() (every frame — a disarmed NPC since GIVEN a weapon draws it now; the :483
## guard is just an internal early-out), then the FULL armed-combat body via the existing _act_alerted helper
## (close to engage range, track + dodge, charge the laser, reload-when-dry + bark, incoming beep, fire). We
## DELEGATE to _act_alerted rather than transcribe it so the within-frame interleaving (reload-while-closing,
## dodge-weave, charge-bleed) stays byte-for-byte the FSM — decomposing it into primitives is Phase-5 work.
##
## Always RUNNING. Serves the Engage goal via the sentinel target_engaged. The armed/unarmed split keys on
## _can_fight_with_gun() (ammo OR a spare clip), NOT is_armed — so an armed-but-dry-no-clips NPC falls to
## FireUnarmed (fists), matching the FSM. is_runtime_valid re-checks live state + can_fight so a mid-fight
## disarm/dry-out forces a replan to FireUnarmed, and a perception change replans to Detect/Investigate/Hold.

func _init() -> void:
	super(&"FireArmed", 0.5, {&"state_alerted": true, &"can_fight_with_gun": true}, {&"target_engaged": true})

func act(host, delta: float) -> int:
	host._ensure_armed_from_backpack()
	host._act_alerted(delta)
	return Status.RUNNING

func is_runtime_valid(host) -> bool:
	return host._perception != null and host._perception.state == Perception.State.ALERTED and host._can_fight_with_gun()
