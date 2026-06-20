@tool
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

## Drives the give_item_id dropdown from the item ids on disk (const-preloaded — see item_ids.gd).
const ItemIds = preload("res://scripts/items/item_ids.gd")

## The button label the player sees and clicks for this option.
@export var text: String = ""
## Where picking this leads. DialogueLine.CONTINUE (-2, the default) advances to the NEXT line; DialogueLine.END
## (-1) finishes the conversation; an INDEX >= 0 jumps to that specific line in DialogueResource.lines.
@export var target: int = -2  # -2 == DialogueLine.CONTINUE (literal to avoid a mutual class_name dep in this default): keep the convo going
## Where a FAILED skill/flag check leads (rank 22): a gated choice stays SELECTABLE (FNV-style), so you can
## attempt it and fail. DialogueLine.END (-1, the default) finishes the conversation; an INDEX >= 0 branches to
## a fail line; DialogueLine.CONTINUE (-2) carries on. Ignored by a choice with no gate. (Literal -1, like `target`.)
@export var target_on_fail: int = -1  # -1 == DialogueLine.END

## OPTIONAL skill check: when `required_stat` names a CharacterStats stat (e.g. &"persuasion"), this choice is
## selectable only while the player's stat is >= required_value. The button shows the gate on its label
## ("[Persuasion 6] ...") and is DISABLED — visible but locked, FNV-style — when the player falls short
## (see DialogueView.set_choices). Empty = no check, the choice behaves exactly as before.
@export var required_stat: StringName = &""
## The minimum stat value the player needs to pass the check above. Only matters when required_stat is set; higher = a harder gate.
@export var required_value: int = 0

## OPTIONAL story-flag gate: when `required_flag` names a GameState flag, this choice is DISABLED (visible but
## locked, like the skill check above) unless `str(GameState.get_flag(required_flag)) == required_flag_value`.
## Empty = no gate. Evaluated at runtime in DialogueView.set_choices (not here — this @tool Resource never
## touches the autoload). Lets a conversation branch on quest/world state, not just stats.
@export var required_flag: StringName = &""
## The flag value (stringified) this choice needs to be selectable — a String so it reads in the inspector (a
## bool flag set via GameState.set_flag stringifies to "true", the default). Only matters when required_flag is set.
@export var required_flag_value: String = "true"

@export_group("Consequences")
## Set this global story flag when this choice is picked (GameState.set_flag). Empty = none.
@export var set_flag: StringName = &""
## The value written for `set_flag`. Default true.
@export var set_flag_value: bool = true
## Start this quest when picked (GameState.start_quest). Null = none.
@export var start_quest_on_choice: Quest
## Complete this quest by id when picked — the turn-in path (GameState.complete_quest). Empty = none.
@export var complete_quest_id: StringName = &""
## Advance objective `advance_objective_id` of quest `advance_quest_id` by one when picked. BOTH are needed.
@export var advance_quest_id: StringName = &""
@export var advance_objective_id: StringName = &""
## Give the player this item (by Item.id), `give_item_count` of it, when picked. Empty = none.
@export var give_item_id: StringName = &""
@export var give_item_count: int = 1
## Add this to the player's wallet when picked — NEGATIVE for a fee/cost. 0 = none.
@export var give_money: float = 0.0

## Self-populate the `required_stat` dropdown from the CharacterStats attribute names, and `give_item_id` from
## the item ids on disk (SUGGESTION hints, so blanks stay valid and custom names are still typable).
func _validate_property(property: Dictionary) -> void:
	if property.name == "required_stat":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = CharacterStats.stat_names_csv()
	elif property.name == "give_item_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ItemIds.ids_csv()
