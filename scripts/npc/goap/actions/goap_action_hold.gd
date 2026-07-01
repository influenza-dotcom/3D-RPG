class_name GoapActionHold
extends GoapAction

## The always-feasible "nothing to fight" floor that keeps a peaceful NPC busy: RAID a nearby container first
## when it holds a better/first gun (NpcScavenge owns that walk), else wander / return to post (NpcLocomotion
## via host._idle). It also keeps the laser hidden. No preconditions (always available); satisfies the Idle
## goal's `idle_done`.
##
## act() never SUCCEEDS — holding is a steady state, so it stays RUNNING. The executor only replans when the
## current action goes invalid, so is_runtime_valid is what makes the floor YIELD: it returns false the moment
## perception escalates (DETECTING/ALERTED/INVESTIGATING), forcing a replan to the matching combat arm. Without
## it the floor would stick and the NPC would idle while a fight starts. The body is in-tree (touches host
## components) so it's manual-playtested; the planner picks it via pure tests.

func _init() -> void:
	super(&"Hold", 0.1, {}, {&"idle_done": true})

func act(host, delta: float) -> int:
	# RAID a nearby container first when it holds a better gun than ours (NpcScavenge owns that walk), else
	# wander (if `wanders`) / return to post.
	if host._scavenge == null or not host._scavenge.act(delta):
		host._idle(delta, true)
	host._hide_laser()
	return Status.RUNNING

func is_runtime_valid(host) -> bool:
	# Valid only while there's nothing to fight (perception UNAWARE, or no perception child at all). Any combat
	# state invalidates Hold so the executor replans to Detect/Engage/Investigate this tick.
	return host._perception == null or host._perception.state == Perception.State.UNAWARE
