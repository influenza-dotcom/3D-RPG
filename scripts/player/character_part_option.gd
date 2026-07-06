@tool
class_name CharacterPartOption
extends Resource

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")

## ONE selectable appearance part (a HEAD or a BODY/torso) in the player character customizer. Carries the model
## plus the placement (scale / position / rotation) that seats it on the shared rig, so a designer can add a new
## head or body by authoring one of these in a CharacterAppearanceCatalog — no code. The customizer cycles the
## catalog's `heads` / `bodies` arrays and feeds the chosen option straight onto a BodyModelSwap (its own exports,
## NOT via a host `look`), so what the creation preview shows is exactly what any character rig would render.
##
## Placement mirrors the fields on BodyModelSwap / NpcLook so the numbers transfer 1:1 from a tuned NPC — e.g. the
## shipped rig seats headblue.glb at scale 0.205, position (0, 0.615, 0.04), rotation (0, 90, 0) on torso.tscn.
## `whole_body` (bodies only): when true this model IS a complete character (its own head/arms/legs, e.g. Man.glb),
## so the customizer uses it ALONE and skips the separate head/arm/leg parts (and the head picker is disabled).

## Stable id used in saves + catalog lookups. NEVER reuse or renumber an existing id — a save stores it, and a
## changed id silently falls back to the catalog default on load. Empty is invalid (the catalog skips it).
@export var id: StringName = &""
## Human-readable name shown in the customizer's ‹ Head: Chrysalis › cycler.
@export var display_name: String = ""
## The part model: a .glb/.blend PackedScene or a bare Mesh (same contract as BodyModelSwap.body_model).
@export var model: Resource
## Uniform scale of the part on the rig (the shipped torso + head both sit at ~0.205).
@export var scale: float = 1.0
## Local position under the BodyModelSwap. For a HEAD, raise Y onto the neck; a BODY usually sits at origin.
@export var position: Vector3 = Vector3.ZERO
## Rotation (degrees) of the part's rest pose — yaw it to face the rig's forward (+Z).
@export var rotation: Vector3 = Vector3.ZERO
## Optional baked skin for the part (albedo texture). Null = keep the model's own material. The player's chosen
## skin colour tints OVER this, exactly like BodyModelSwap's texture+colour contract.
@export var texture: Texture2D
## BODIES ONLY: this model is a whole character (own head/arms/legs). The customizer renders it alone and hides
## the head/arm/leg parts + the head picker. Leave false for a torso that composes with a separate head.
@export var whole_body: bool = false

func _validate_property(property: Dictionary) -> void:
	if property.name == &"model":
		property.hint = PROPERTY_HINT_RESOURCE_TYPE
		property.hint_string = ModelResourceUtil.HINT

## True when this option can actually render — a non-empty id and a real model resource. The catalog filters on it
## so a half-authored row never reaches the picker.
func is_valid() -> bool:
	return not String(id).is_empty() and ModelResourceUtil.is_model(model)
