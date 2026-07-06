extends RefCounted
## The canonical GOAP goal + action NAME lists — the SINGLE source the GoapProfile authoring DROPDOWNS
## (goap_profile.gd / goap_goal_priority.gd / goap_action_cost.gd, via _validate_property) populate from,
## instead of three hand-maintained @export_enum copies that silently drift from npc.gd's real library.
## A drift test (test_npc_goap_library.gd) builds the actual library off a bare NPC and asserts these lists
## match the built goals/actions, so adding or renaming a goal/action fails loudly here until this is updated.
##
## Preloaded as a const where needed (NO class_name on purpose — nothing for the global script class cache to
## miss, matching Factions / AbilityRegistry). Order = the inspector dropdown order (mirrors the build order).

## Goal names built by build_goals() below (highest-priority feasible wins; Survive > Engage > … > Idle).
static func goal_names() -> PackedStringArray:
	return PackedStringArray(["Survive", "Engage", "Investigate", "Detect", "Idle"])

## Action names built by build_actions() below (each combat goal's action + the Idle floor's Hold).
static func action_names() -> PackedStringArray:
	return PackedStringArray(["Hold", "Detect", "Investigate", "FireArmed", "FireUnarmed", "Flee"])

## Comma-separated goal names for a PROPERTY_HINT_ENUM hint_string.
static func goal_names_csv() -> String:
	return ",".join(goal_names())

## Comma-separated action names for a PROPERTY_HINT_ENUM hint_string.
static func action_names_csv() -> String:
	return ",".join(action_names())

# --- Library BUILDERS (moved off npc.gd so the vocabulary + its name registries above live in ONE file and can't
# drift). NPC._build_goap_actions / _build_goap_goals are thin facades onto these, passing their goap_profile. The
# `profile` param is typed Resource (a GoapProfile or null) — deliberately NOT `GoapProfile`, to avoid a
# GoapLibrary <-> GoapProfile class cycle (GoapProfile already preloads this file for its authoring dropdowns); its
# tuning getters are called dynamically, exactly as npc.gd did. The action-class references are function-body only
# (lazy), so preloading GoapLibrary for the dropdowns never eagerly pulls in the action scripts. ---

## The GOAP ACTION library — the planner's vocabulary + the NPC's full combat dispatch, in dropdown/build order.
## Hold = the UNAWARE-at-seam idle/scavenge floor (also covers companion-follow via _idle, so "Escort" needs no
## separate action); Detect / Investigate = the DETECTING / INVESTIGATING states; FireArmed / FireUnarmed = the
## ALERTED state split on _can_fight_with_gun. `profile` (a GoapProfile or null) retunes each action's base_cost via
## cost_for(); null = the actions' authored defaults (designer-first; no code). The executor steps this each frame.
static func build_actions(profile: Resource = null) -> Array:
	var actions: Array = [
		GoapActionHold.new(),
		GoapActionDetect.new(),
		GoapActionSearch.new(),
		GoapActionFireArmed.new(),
		GoapActionFireUnarmed.new(),
		GoapActionFlee.new(),
	]
	if profile != null:
		for a in actions:
			a.base_cost = maxf(profile.cost_for(a.name, a.base_cost), 0.0)
	return actions

## The GOAP GOAL set — highest authored priority among the FEASIBLE goals wins (GoapPlanner.select_goal). Each combat
## goal is feasible only in its perception state (its action's precondition); Survive only while fleeing + a threat
## noticed; Idle is the always-feasible floor. Priority: Survive (3.0, a fleer always runs) > Engage (2.0, ALERTED) >
## Investigate (0.4) > Detect (0.3) > Idle (0.1). "Escort" is deliberately NOT a goal: companion-follow is an idle
## sub-behaviour (NpcLocomotion._idle -> _follow.act), and "a following NPC with a target fights" falls out of Engage
## outranking Idle. `profile` retunes base_priority + the dynamic hp_scale / temperament_scale knobs (0.0 default =>
## priority() == base_priority) and filters to its `goals` allow-list (Idle is ALWAYS kept via pursues() so select_goal
## can't return null and idle the brain); null = authored defaults. Empty allow-list pursues everything (the default).
static func build_goals(profile: Resource = null) -> Array:
	var goals: Array = [
		GoapGoal.new(&"Survive", 3.0, {&"fled": true}),
		GoapGoal.new(&"Engage", 2.0, {&"target_engaged": true}),
		GoapGoal.new(&"Investigate", 0.4, {&"spot_searched": true}),
		GoapGoal.new(&"Detect", 0.3, {&"threat_faced": true}),
		GoapGoal.new(&"Idle", 0.1, {&"idle_done": true}),
	]
	if profile != null:
		for g in goals:
			g.base_priority = profile.priority_for(g.name, g.base_priority)
			# Dynamic-priority knobs (0.0 default => priority() == base_priority, unchanged) until a designer fills them.
			g.hp_scale = profile.hp_scale_for(g.name, 0.0)
			g.temperament_scale = profile.temperament_scale_for(g.name, 0.0)
		# goals[] allow-list: keep only the pursued goals (Idle always survives — see GoapProfile.pursues()). Empty
		# goals[] pursues everything, so this filter is a no-op unless the archetype names a subset.
		goals = goals.filter(func(g): return profile.pursues(g.name))
	return goals
