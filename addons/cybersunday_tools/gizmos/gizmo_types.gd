@tool
extends RefCounted

## Single source of truth for WHICH Node3D types the CYBER SUNDAY gizmo plugin visualizes. The plugin's _has_gizmo
## delegates to is_gizmo_target() here, and a drift test (tests/test_devtools_gizmo_types.gd) pins the membership:
## a new `node is X` case added to the plugin's _redraw that forgets to register X here fails the test instead of
## silently never drawing (the gizmo would never fire for X, so its _redraw branch would be dead).
##
## This lives in a plain RefCounted (NOT the EditorNode3DGizmoPlugin) so the test can preload it and call the static
## headless, without constructing an editor gizmo plugin. GIZMO_CLASS_NAMES is the authoritative list the test pins;
## is_gizmo_target() mirrors it with real `is` checks (a String can't be used as a type in an `is` expression).

const GIZMO_CLASS_NAMES: Array[String] = [
	"TriggerVolume", "AudioZone", "HazardZone", "ShadowVolume", "NavBlocker", "PatrolPath", "PlayerSpawn",
	"EncounterSpawner", "ExplosiveBarrel", "NPC", "InvestigatePoint", "NoiseSource", "WorldMarker",
	"AlarmPanel", "AmbientSound", "Radio", "Door",
]


## True for any Node3D the plugin draws a gizmo for. GuardDuty is deliberately ABSENT: it's a plain Node (no gizmo
## of its own) — its protectee link is drawn from the parent NPC's _redraw via _draw_guard_link.
static func is_gizmo_target(node: Node3D) -> bool:
	return (node is TriggerVolume or node is AudioZone or node is HazardZone or node is ShadowVolume
		or node is NavBlocker or node is PatrolPath or node is PlayerSpawn
		or node is EncounterSpawner or node is ExplosiveBarrel or node is NPC
		or node is InvestigatePoint or node is NoiseSource or node is WorldMarker
		or node is AlarmPanel or node is AmbientSound or node is Radio or node is Door)
