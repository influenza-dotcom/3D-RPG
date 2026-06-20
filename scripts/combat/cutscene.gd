@tool
class_name Cutscene
extends Resource

## An ordered list of CutsceneActions a CutscenePlayer runs (wait → move the camera → play a line → set a flag → …).
## Author as a .tres, then fire it from a CutscenePlayer (a TriggerVolume action, a dialogue, or auto on entry).

@export var actions: Array[CutsceneAction] = []
