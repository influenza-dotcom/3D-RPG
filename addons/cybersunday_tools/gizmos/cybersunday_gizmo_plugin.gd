@tool
extends EditorNode3DGizmoPlugin

## Viewport gizmos for the game's spatial authoring components -- draws the currently-invisible extents/ranges/
## routes/facing of TriggerVolume, AudioZone, HazardZone, ShadowVolume, NavBlocker, PatrolPath, PlayerSpawn,
## EncounterSpawner, ExplosiveBarrel and NPC perception, so a designer places by eye instead of guessing numbers.
##
## STUB: registers the gizmo plugin but draws nothing yet. The per-class draw dispatch + materials land in the
## gizmo build step (the real _has_gizmo / _redraw / gizmo_shapes.gd helpers).


func _get_gizmo_name() -> String:
	return "CyberSundayTools"


func _has_gizmo(_node: Node3D) -> bool:
	return false  # stub: no classes matched yet


func _redraw(_gizmo: EditorNode3DGizmo) -> void:
	pass  # stub: drawing added in the gizmo build step
