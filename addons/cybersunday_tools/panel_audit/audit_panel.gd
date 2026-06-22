@tool
extends VBoxContainer

## Project audit bottom panel: aggregates every node's get_configuration_warnings() across the edited scene
## PLUS a project-wide res:// scan -- group-name typos / the dead lowercase-"player" group, broken ext_resource
## refs, null/dead LootTable entries, out-of-range DialogueResource targets, unbaked navmeshes -- each row
## click-to-jump to the offending node or resource. Catches the silent stuff config-warnings alone never surface.
##
## STUB: shows a placeholder. The scene scan + disk scan + severity tree land in the audit build step.


func _init() -> void:
	name = "Audit"
	var l := Label.new()
	l.text = "Project Audit — coming soon"
	add_child(l)
