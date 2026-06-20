@tool
class_name DialogueSelector
extends Resource

## Picks which conversation an NPC says based on world state — the first matching DialogueSelectorRow wins, else
## `default_dialogue`. Assign it to a Talkable / DialogueNPC's `dialogue_selector` to give one NPC different
## lines as flags flip and quests progress (the basic "remembers what you did" RPG expectation).

## Rows checked top-to-bottom; the first whose gates all pass (and that has a dialogue) is used.
@export var rows: Array[DialogueSelectorRow] = []
## Used when no row matches — the baseline greeting (may be null).
@export var default_dialogue: DialogueResource

## The conversation to play right now: the first matching row's dialogue, else default_dialogue.
func pick() -> DialogueResource:
	for row in rows:
		if row != null and row.dialogue != null and row.matches():
			return row.dialogue
	return default_dialogue
