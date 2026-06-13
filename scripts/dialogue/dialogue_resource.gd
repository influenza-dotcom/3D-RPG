class_name DialogueResource
extends Resource

## A full conversation — an ordered list of lines. Make these as .tres files and assign one to a
## DialogueNPC; DialogueManager plays it back top to bottom.

## The conversation's lines, played top to bottom. Choices jump by INDEX into this array, so order is the addressing.
@export var lines: Array[DialogueLine] = []
