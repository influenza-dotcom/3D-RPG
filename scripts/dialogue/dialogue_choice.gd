class_name DialogueChoice
extends Resource

## One selectable option on a branching DialogueLine: a button label plus where picking it jumps.
## `target` is an INDEX into the owning DialogueResource.lines -- the same integer space the
## DialogueManager already addresses lines with via its _index cursor. Use DialogueLine.END (-1)
## to finish the conversation instead of jumping to another line.
##
## Authorable as a sub-resource nested in DialogueLine.choices, exactly like DialogueLine nests in
## DialogueResource.lines, so whole branching scripts are still .tres files.

@export var text: String = ""
@export var target: int = -1  # default -1 == DialogueLine.END: an unconfigured choice safely ends the convo

## OPTIONAL skill check: when `required_stat` names a CharacterStats stat (e.g. &"persuasion"), this choice is
## selectable only while the player's stat is >= required_value. The button shows the gate on its label
## ("[Persuasion 6] ...") and is DISABLED — visible but locked, FNV-style — when the player falls short
## (see DialogueView.set_choices). Empty = no check, the choice behaves exactly as before.
@export var required_stat: StringName = &""
@export var required_value: int = 0
