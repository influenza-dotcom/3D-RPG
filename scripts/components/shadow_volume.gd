@tool
class_name ShadowVolume
extends Area3D

## A drop-in SHADOW: paint this Area3D over a dark region and the player inside reads as UNLIT to enemy
## Perception — it writes a low `light_exposure` (shadow_exposure) to each qualifying body while inside and
## restores full light (1.0) on exit. The cheap, designer-painted alternative to live light probing
## (PlayerLightLevel): no Player.tscn edit, just paint shadows. Needs an enemy Perception light curve to bite —
## GameSettings.light_stealth ships one game-wide (ranks 27.4 / 27.2). NOTE: don't overlap two ShadowVolumes on
## the same spot — the one a body exits LAST wins; paint discrete dark areas instead.

## The group a body must belong to for this shadow to dim it. The PLAYER group by default
## (Groups.PLAYER == &"Player" — the human is in &"Player", NOT the dead lowercase "player").
@export var trigger_group: StringName = Groups.PLAYER
## The light_exposure written to a body inside (0 = pitch dark -> slowest detection, 1 = fully lit). 0 = deepest.
@export_range(0.0, 1.0) var shadow_exposure: float = 0.0

var _bodies: Array[Node] = []  ## qualifying bodies currently inside (clean re-entry + is_occupied)

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only the configuration warning runs in-editor; the dimming is runtime-only
	collision_mask = 0xFFFFFFFF  # catch the player on any physics layer (matches TriggerVolume / AudioZone)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group(trigger_group):
		return
	if not _bodies.has(body):
		_bodies.append(body)
	body.set(&"light_exposure", shadow_exposure)  # in shadow -> unlit

func _on_body_exited(body: Node) -> void:
	if body == null or not _bodies.has(body):
		return
	_bodies.erase(body)
	body.set(&"light_exposure", 1.0)  # back into the light

func is_occupied() -> bool:
	return not _bodies.is_empty()

func _get_configuration_warnings() -> PackedStringArray:
	for c in get_children():
		if c is CollisionShape3D or c is CollisionPolygon3D:
			return PackedStringArray()
	return PackedStringArray(["ShadowVolume needs a CollisionShape3D child — the region that darkens the player."])
