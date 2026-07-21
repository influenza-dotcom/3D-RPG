@tool
class_name InvestigatePoint
extends Marker3D

## Drop-in "go look here" beacon: call trigger() (e.g. from a TriggerVolume action = "trigger", or a cutscene
## CALL_METHOD) to send an NPC — a specific one (npc_path) or every NPC within `radius` — to investigate THIS
## marker's position. The NPC walks there and searches (its no-target GOAP Investigate); `alerted` shows the "!"
## reaction. Works regardless of the global stealth-sense flags (it's a scripted command, not ambient sensing).

## A specific NPC to send. Empty = every NPC in the &"npc" group within `radius`.
@export var npc_path: NodePath
## When npc_path is empty, send every NPC within this many metres of the marker.
@export var radius: float = 20.0
## true = the NPC reacts with the alerting "!" sting; false = a quiet "come look".
@export var alerted: bool = false

## Send the configured NPC(s) to investigate this marker's position.
func trigger() -> void:
	if not npc_path.is_empty():
		var n := get_node_or_null(npc_path)
		if n != null and n.has_method(&"investigate"):
			n.investigate(global_position, alerted)
		return
	if not is_inside_tree():
		return
	var here := global_position
	for npc in get_tree().get_nodes_in_group(Groups.NPC):
		if npc is Node3D and npc.has_method(&"investigate") and here.distance_to((npc as Node3D).global_position) <= radius:
			npc.investigate(here, alerted)
