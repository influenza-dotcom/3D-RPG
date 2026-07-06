class_name GoapActionFireUnarmed
extends GoapAction

## ALERTED-state fallback for an NPC that CAN'T fight with a gun — a civilian brawler, or a combatant whose
## ammo was pickpocketed / whose weapon was looted off it (disarmed, or dry with no spare clips: _can_fight_with_gun is broader than
## is_armed). _ensure_armed_from_backpack() runs first, so a just-handed gun is drawn; next tick the sensed
## can_fight_with_gun flips true and the planner switches to FireArmed. Otherwise _act_unarmed scavenges a
## reachable weapon before throwing fists.
##
## Always RUNNING. Serves the Engage goal via the sentinel target_engaged. is_runtime_valid re-checks live
## state + NOT can_fight, so re-arming or a perception change forces the executor to replan the same tick.

func _init() -> void:
	super(&"FireUnarmed", 0.6, {&"state_alerted": true, &"can_fight_with_gun": false}, {&"target_engaged": true})

func act(host, delta: float) -> int:
	host._ensure_armed_from_backpack()
	host._act_unarmed(delta)
	return Status.RUNNING

func is_runtime_valid(host) -> bool:
	# `not is_fleeing()` mirrors GoapActionFlee so a temperament FIGHT->FLEE flip (only fires while ALERTED, so
	# this can be the current action) invalidates this and the executor replans to Survive/Flee the same tick,
	# instead of the flipped coward throwing fists forever.
	return host._perception != null and host._perception.state == Perception.State.ALERTED \
			and not host._can_fight_with_gun() and not host.is_fleeing()
