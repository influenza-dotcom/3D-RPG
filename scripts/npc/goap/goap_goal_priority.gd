class_name GoapGoalPriority
extends Resource

## One per-archetype GOAP GOAL-priority override, authored as a dropdown ROW -- the replacement for a free-text
## Dictionary key (which also deletes the String-vs-StringName key-hash footgun the old _goap_override worked
## around). Pick the goal from the list; `priority` REPLACES that goal's authored base_priority for this archetype
## (raise Survive -> a coward, lower it -> a fearless fighter). Lives in GoapProfile.goal_priorities. Keep the
## dropdown values in sync with the goals npc.gd _build_goap_goals registers.
@export_enum("Survive", "Engage", "Investigate", "Detect", "Idle") var goal: String = "Survive"
@export var priority: float = 1.0
