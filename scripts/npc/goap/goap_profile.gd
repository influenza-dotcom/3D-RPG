class_name GoapProfile
extends Resource

## Per-archetype GOAP authoring, hung off NpcData (like weapon_data / bark_set already attach): which goals
## this NPC pursues, priority overrides, and per-action cost overrides — all inspector-authored, no code. A
## designer makes a cowardly raider by raising goal_priorities[&"Survive"]; a brawler by lowering Punch's cost.
##
## validate() warns on any override key that matches no known goal/action — a StringName typo otherwise
## SILENTLY no-ops (the override just never applies), a failure mode the explicit FSM never had.

@export var goals: Array[StringName] = []           ## which goals this archetype pursues
@export var goal_priorities: Dictionary = {}        ## StringName goal -> float priority override
@export var action_cost_overrides: Dictionary = {}  ## StringName action -> float cost override

## Return false (and push_warning per offender) if any override key isn't in the known goal/action name sets.
## Called after load with the registered names so a typo surfaces at boot instead of failing silently in play.
func validate(known_goals: PackedStringArray, known_actions: PackedStringArray) -> bool:
	var ok := true
	for g in goal_priorities:
		if not known_goals.has(String(g)):
			push_warning("GoapProfile: goal_priorities key '%s' matches no known goal — override ignored." % g)
			ok = false
	for a in action_cost_overrides:
		if not known_actions.has(String(a)):
			push_warning("GoapProfile: action_cost_overrides key '%s' matches no known action — override ignored." % a)
			ok = false
	return ok
