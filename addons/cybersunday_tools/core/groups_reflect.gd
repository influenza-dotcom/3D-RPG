@tool
extends RefCounted

## Reflects the project's Groups registry (scripts/world/groups.gd) into the set of "known-good" group-name
## strings, so the audit panel can flag raw group-literal usages that DON'T match a registered name (a typo, or
## the dead lowercase-"player" group that silently broke kill-XP). Single source of truth = the Groups consts:
## adding a group there auto-extends the allowed set here, no edit needed.

const GROUPS_PATH := "res://scripts/world/groups.gd"

## The set of registered group names -- every StringName/String const value on Groups -- as a Dictionary used as
## a set ({ name: true }). Reading the constant map avoids hardcoding (and drifting from) the list.
##
## NB: get_script_constant_map() is a NON-static Script method, so it must be called on a loaded Script OBJECT
## (a Variant from load()), NOT on a preloaded class-name const -- the latter parses as a static-on-class call
## and fails to compile ("Cannot call non-static function ... on the class").
static func allowed_names() -> Dictionary:
	var out := {}
	var script: Variant = load(GROUPS_PATH)
	if script == null:
		return out
	var consts: Dictionary = script.get_script_constant_map()
	for k in consts:
		var v: Variant = consts[k]
		if v is StringName or v is String:
			out[StringName(v)] = true
	return out
