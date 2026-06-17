extends RefCounted
## The canonical GOAP goal + action NAME lists — the SINGLE source the GoapProfile authoring DROPDOWNS
## (goap_profile.gd / goap_goal_priority.gd / goap_action_cost.gd, via _validate_property) populate from,
## instead of three hand-maintained @export_enum copies that silently drift from npc.gd's real library.
## A drift test (test_npc_goap_library.gd) builds the actual library off a bare NPC and asserts these lists
## match the built goals/actions, so adding or renaming a goal/action fails loudly here until this is updated.
##
## Preloaded as a const where needed (NO class_name on purpose — nothing for the global script class cache to
## miss, matching Factions / AbilityRegistry). Order = the inspector dropdown order (mirrors the build order).

## Goal names registered by npc.gd._build_goap_goals (highest-priority feasible wins; Survive > Engage > … > Idle).
static func goal_names() -> PackedStringArray:
	return PackedStringArray(["Survive", "Engage", "Investigate", "Detect", "Idle"])

## Action names registered by npc.gd._build_goap_actions (each combat goal's action + the Idle floor's Hold).
static func action_names() -> PackedStringArray:
	return PackedStringArray(["Hold", "Detect", "Investigate", "FireArmed", "FireUnarmed", "Flee"])

## Comma-separated goal names for a PROPERTY_HINT_ENUM hint_string.
static func goal_names_csv() -> String:
	return ",".join(goal_names())

## Comma-separated action names for a PROPERTY_HINT_ENUM hint_string.
static func action_names_csv() -> String:
	return ",".join(action_names())
