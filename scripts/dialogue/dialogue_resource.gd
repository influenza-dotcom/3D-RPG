class_name DialogueResource
extends Resource

## A full conversation — an ordered list of lines. Make these as .tres files and assign one to a
## DialogueNPC; DialogueManager plays it back top to bottom.

@export var lines: Array[DialogueLine] = []
