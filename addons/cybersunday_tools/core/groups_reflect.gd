@tool
extends RefCounted

## Reflects the project's Groups registry (scripts/world/groups.gd) into the set of "known-good" group-name
## strings, so the audit panel can flag raw group-literal usages that DON'T match a registered name (a typo, or
## the dead lowercase-"player" group that silently broke kill-XP). Single source of truth = the Groups consts:
## adding a group there auto-extends the allowed set here, no edit needed.

const GroupsScript := preload("res://scripts/world/groups.gd")

## The set of registered group names -- every StringName/String const value on Groups -- as a Dictionary used as
## a set ({ name: true }). Reading the constant map avoids hardcoding (and drifting from) the list.
static func allowed_names() -> Dictionary:
	var out := {}
	var consts: Dictionary = GroupsScript.get_script_constant_map()
	for k in consts:
		var v: Variant = consts[k]
		if v is StringName or v is String:
			out[StringName(v)] = true
	return out
