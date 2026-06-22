@tool
extends HBoxContainer

## Play-from-spawn toolbar: a play button that launches the game starting at the selected PlayerSpawn (or the
## editor camera position), so you iterate on a level without walking from the level's default start each time.
## Writes a transient dev-start that GameRoot reads on _ready (the one cooperating hook).
##
## STUB: shows a placeholder. The buttons + dev-start handoff land in the play-from-spawn build step.


func _init() -> void:
	name = "PlayFromSpawn"
	var l := Label.new()
	l.text = "  [▶ from spawn]"
	add_child(l)
