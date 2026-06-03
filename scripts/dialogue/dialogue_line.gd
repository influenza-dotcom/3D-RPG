class_name DialogueLine
extends Resource

## One line in a conversation: who speaks and what they say, plus optional branching choices.
## A line with an empty `choices` array plays linearly (DialogueManager advances to the next line
## on input). A line WITH choices is a branch point: the manager shows one Button per choice and
## jumps to the chosen DialogueChoice.target (an index into DialogueResource.lines, or END to finish).

const END: int = -1  # choice target sentinel: a choice whose target == END finishes the conversation

@export var speaker: String = ""
@export_multiline var text: String = ""
@export var choices: Array[DialogueChoice] = []

## True when this line presents choices (a branch point) rather than continuing linearly.
## Pure (no tree / side effects) so DialogueManager and the tests can share it.
func has_choices() -> bool:
	return not choices.is_empty()
