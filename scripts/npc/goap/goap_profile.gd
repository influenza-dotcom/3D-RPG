@tool
class_name GoapProfile
extends Resource

## Per-archetype GOAP authoring, hung off NpcData (like weapon_data / bark_set already attach): which goals
## this NPC pursues, priority overrides, and per-action cost overrides — all inspector-authored from DROPDOWNS,
## no code. A designer makes a cowardly raider by adding a goal_priorities row {Survive, 5}; a brawler by adding
## an action_cost_overrides row {Flee, low}. The overrides are dropdown ROWS (GoapGoalPriority / GoapActionCost),
## not free-text Dictionary keys -- so the goal/action name is always a real one (no typos) and there's no more
## String-vs-StringName key-hash footgun (which is why npc.gd's _goap_override hack is gone).
##
## validate() still warns on any row whose name isn't a known goal/action (a code-built row, or a renamed
## goal/action) so a stale override surfaces at boot instead of silently no-opping.

## Single source the authoring dropdowns populate from (the names npc.gd's library is drift-tested against).
const GoapLibrary := preload("res://scripts/npc/goap/goap_library.gd")

## Which goals this archetype pursues -- pick each from the dropdown (self-populated from the registered goals).
## NOTE: currently INFORMATIONAL — the planner pursues every registered goal; a subset listed here is NOT
## enforced (dropping a combat goal would idle a fighting NPC, so subset-filtering is deliberately not wired).
## validate() warns when this is set, so the field doesn't silently mislead.
@export var goals: Array[String] = []
## Per-goal priority overrides as dropdown rows (each REPLACES that goal's base_priority for this archetype).
@export var goal_priorities: Array[GoapGoalPriority] = []
## Per-action planner-cost overrides as dropdown rows (each REPLACES that action's base_cost; consumer clamps >= 0).
@export var action_cost_overrides: Array[GoapActionCost] = []
## Per-goal HP coefficients as dropdown rows (mirror goal_priorities' row shape; `priority` IS the hp_scale). Each
## sets that goal's hp_scale, raising its selection priority as the NPC is hurt. UNSET (no row) -> 0.0 -> no effect,
## so the default leaves priority() == base_priority (behaviour unchanged until a designer fills this).
@export var hp_scales: Array[GoapGoalPriority] = []
## Per-goal temperament coefficients as dropdown rows (same row shape; `priority` IS the temperament_scale). Each
## sets that goal's temperament_scale, weighting it by the sensed temperament fact (a coward weights Survive up).
## UNSET -> 0.0 -> no effect, leaving priority() == base_priority by default.
@export var temperament_scales: Array[GoapGoalPriority] = []

## Self-populate the `goals` subset dropdown from the registered goal names (typed-array PROPERTY_HINT_ENUM).
func _validate_property(property: Dictionary) -> void:
	if property.name == "goals":
		property.hint = PROPERTY_HINT_TYPE_STRING
		property.hint_string = "%d/%d:%s" % [TYPE_STRING, PROPERTY_HINT_ENUM, GoapLibrary.goal_names_csv()]

## The priority override for `goal_name` from the authored rows, or `fallback` when no row sets it. A goal repeated
## across rows lets the LAST row win (deterministic). row.goal (String) == goal_name (StringName) compares by VALUE
## in GDScript, so the dropdown string matches the goal's StringName name with no hashing footgun.
func priority_for(goal_name: StringName, fallback: float) -> float:
	var v := fallback
	for row in goal_priorities:
		if row != null and row.goal == goal_name:
			v = row.priority
	return v

## The hp_scale coefficient for `goal_name` from the authored hp_scales rows, or `fallback` when no row sets it.
## Same value-compare + last-row-wins semantics as priority_for; fallback 0.0 leaves the goal's priority unscaled.
func hp_scale_for(goal_name: StringName, fallback: float) -> float:
	var v := fallback
	for row in hp_scales:
		if row != null and row.goal == goal_name:
			v = row.priority
	return v

## The temperament_scale coefficient for `goal_name` from temperament_scales rows, or `fallback` when none set.
## Same semantics as hp_scale_for; fallback 0.0 leaves the goal's priority unscaled by temperament.
func temperament_scale_for(goal_name: StringName, fallback: float) -> float:
	var v := fallback
	for row in temperament_scales:
		if row != null and row.goal == goal_name:
			v = row.priority
	return v

## The cost override for `action_name` from the authored rows, or `fallback` when none. Last duplicate row wins.
func cost_for(action_name: StringName, fallback: float) -> float:
	var v := fallback
	for row in action_cost_overrides:
		if row != null and row.action == action_name:
			v = row.cost
	return v

## Return false (and push_warning per offender) if any row's goal/action isn't in the known name sets. Called
## after load with the registered names so a stale override surfaces at boot instead of failing silently in play.
func validate(known_goals: PackedStringArray, known_actions: PackedStringArray) -> bool:
	var ok := true
	for row in goal_priorities:
		if row != null and not known_goals.has(row.goal):
			push_warning("GoapProfile: goal_priorities row '%s' matches no known goal — override ignored." % row.goal)
			ok = false
	for row in action_cost_overrides:
		if row != null and not known_actions.has(row.action):
			push_warning("GoapProfile: action_cost_overrides row '%s' matches no known action — override ignored." % row.action)
			ok = false
	# `goals` is authored but INERT — surface that (and any typo'd goal name) as a breadcrumb. This never changes
	# the validity result, which stays governed only by the override rows above.
	for g in goals:
		if not known_goals.has(g):
			push_warning("GoapProfile: goals entry '%s' matches no known goal." % g)
	if not goals.is_empty():
		push_warning("GoapProfile: `goals` is informational — the planner pursues all registered goals; a subset listed here is not enforced.")
	return ok
