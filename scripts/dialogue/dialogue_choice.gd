class_name DialogueChoice
extends Resource

## One selectable option on a branching DialogueLine: a button label plus where picking it jumps.
## `target` is an INDEX into the owning DialogueResource.lines -- the same integer space the
## DialogueManager already addresses lines with via its _index cursor. The DEFAULT, DialogueLine.CONTINUE,
## carries the conversation on to the NEXT line (so a freshly-authored choice doesn't dead-end the convo);
## use DialogueLine.END (-1) to FINISH instead, or a line index >= 0 to BRANCH to a specific line.
##
## Authorable as a sub-resource nested in DialogueLine.choices, exactly like DialogueLine nests in
## DialogueResource.lines, so whole branching scripts are still .tres files.

## The button label the player sees and clicks for this option.
@export var text: String = ""
## Where picking this leads. DialogueLine.CONTINUE (-2, the default) advances to the NEXT line; DialogueLine.END
## (-1) finishes the conversation; an INDEX >= 0 jumps to that specific line in DialogueResource.lines.
@export var target: int = -2  # -2 == DialogueLine.CONTINUE (literal to avoid a mutual class_name dep in this default): keep the convo going

## OPTIONAL skill check: when `required_stat` names a CharacterStats stat (e.g. &"persuasion"), this choice is
## selectable only while the player's stat is >= required_value. The button shows the gate on its label
## ("[Persuasion 6] ...") and is DISABLED — visible but locked, FNV-style — when the player falls short
## (see DialogueView.set_choices). Empty = no check, the choice behaves exactly as before.
@export var required_stat: StringName = &""
## The minimum stat value the player needs to pass the check above. Only matters when required_stat is set; higher = a harder gate.
@export var required_value: int = 0
