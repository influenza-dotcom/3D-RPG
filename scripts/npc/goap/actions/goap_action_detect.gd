class_name GoapActionDetect
extends GoapAction

## DETECTING-state combat action: the NPC has NOTICED a threat but hasn't locked on — turn to face the
## last-known spot, no laser, no fire. Reproduces the FSM DETECTING arm (npc.gd:1420-1422) verbatim by
## delegating to the same host helpers. Always RUNNING (a detection state never "completes").
##
## Serves the Detect goal via the sentinel pairing: precondition {state_detecting:true}, effect
## {threat_faced:true} (a fact _build_world_state never senses, so the goal is reachable-but-never-pre-satisfied).
## is_runtime_valid re-checks the LIVE Perception.State.DETECTING — because Perception.sense() runs BEFORE the
## seam, the frame perception changes this goes false, the executor replans, and the matching arm
## (Engage / Investigate / Hold) is stepped THAT SAME tick (the FSM's per-frame `match` reproduced).

func _init() -> void:
	super(&"Detect", 0.1, {&"state_detecting": true}, {&"threat_faced": true})

func act(host, delta: float) -> int:
	host._face_point(host._perception.last_known_position, delta)
	host._hide_laser()  # detecting only — no laser until actually aiming to shoot (ALERTED)
	return Status.RUNNING

func is_runtime_valid(host) -> bool:
	return host._perception != null and host._perception.state == Perception.State.DETECTING
