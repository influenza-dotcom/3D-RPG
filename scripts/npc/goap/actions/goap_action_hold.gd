class_name GoapActionHold
extends GoapAction

## The GOAP equivalent of the FSM's UNAWARE branch — the always-feasible "nothing to fight" floor that keeps a
## peaceful NPC busy: RAID a nearby container first when it holds a better/first gun (NpcScavenge owns that
## walk), else wander / return to post (NpcLocomotion via host._idle). It also keeps the laser hidden, exactly
## as the UNAWARE state did. No preconditions (always available); satisfies the Idle goal's `idle_done`.
##
## act() never SUCCEEDS — holding is a steady state, so it stays RUNNING and the executor keeps stepping it
## until a higher-priority goal (Engage / Survive / ...) becomes feasible and the planner switches away. The
## body is in-tree (touches host components) so it's manual-playtested; the planner picks it via pure tests.

func _init() -> void:
	super(&"Hold", 0.1, {}, {&"idle_done": true})

func act(host, delta: float) -> int:
	# RAID a nearby container first when it holds a better gun than ours (NpcScavenge owns that walk), else
	# wander (if `wanders`) / return to post — verbatim the FSM UNAWARE default.
	if host._scavenge == null or not host._scavenge.act(delta):
		host._idle(delta, true)
	host._hide_laser()
	return Status.RUNNING
