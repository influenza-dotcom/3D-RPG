class_name GoapActionFlee
extends GoapAction

## SURVIVE: run from any noticed threat instead of fighting — the GOAP form of the FSM FLEE pre-seam
## (npc.gd:1404-1408): _act_flee (head flee_distance away each step, never fire) + hide the laser. Covers both
## the FLEE archetype and a FIGHT NPC that flipped to FLEE via temperament (_on_damaged_by, npc.gd:747). Always
## RUNNING; serves the Survive goal (sentinel `fled`) at a priority above every combat goal, so a fleer never
## fights while it has noticed a threat.
##
## is_runtime_valid keeps it valid across DETECTING/ALERTED/INVESTIGATING and yields on UNAWARE (the fleer lost
## the threat -> the executor replans to the Idle floor, matching the pre-seam falling through to idle). The
## COMBAT actions carry the mirror gate (`and not host.is_fleeing()`) so a mid-fight flip invalidates the
## running FireArmed/FireUnarmed and the executor switches to Flee the same tick.

func _init() -> void:
	super(&"Flee", 0.3, {&"is_fleeing": true, &"threat_noticed": true}, {&"fled": true})

func act(host, delta: float) -> int:
	host._act_flee(delta)
	host._hide_laser()
	return Status.RUNNING

func is_runtime_valid(host) -> bool:
	return host.is_fleeing() and host._perception != null and host._perception.state != Perception.State.UNAWARE
