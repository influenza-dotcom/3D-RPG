@tool
class_name NpcLook
extends Resource

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")

## A reusable per-NPC APPEARANCE override, authorable as a .tres and SHARED across NPCs. Assign one to an NPC's
## `look` export and it drives that NPC's BodyModelSwap exactly like the NPC root's own inline appearance fields
## would -- the fields here MIRROR those names, so BodyModelSwap reads whichever is in play uniformly via .get().
##
## Assigning a look WINS over and HIDES the NPC's inline fields in the inspector; clear it to fall back to the
## per-instance inline fields (so existing NPCs that never set a look are unaffected). A field left at its default
## (null model / WHITE colour / 1.0 scale) means "no override for this part" -- e.g. a look that only sets
## head_model + colours keeps the NPC's default body. Author a "raider look" / "townsperson look" once in
## resources/ and reuse it across many NPCs instead of re-tuning each instance. BodyModelSwap previews it live.

## Per-NPC BODY swap: set a model asset and this NPC's body becomes it. Null = keep the default body.
@export var body_model: Resource
## Uniform scale of the swapped body (start near the default body's, e.g. ~0.2, if the model imports giant).
@export var body_model_scale: float = 1.0
## Local position of the swapped body under the swap node -- nudge Y so the feet meet the ground.
@export var body_model_position: Vector3 = Vector3.ZERO
## Rotation (degrees) of the swapped body -- yaw to face the NPC's +Z forward.
@export var body_model_rotation: Vector3 = Vector3.ZERO
## Re-SKIN the body WITHOUT swapping the mesh: a texture and/or tint. Texture null + colour WHITE = keep the skin.
@export var body_texture: Texture2D
@export var body_color: Color = Color.WHITE
## Per-NPC HEAD swap (null = keep the default head). The head-look + sniper glint retarget to it.
@export var head_model: Resource
@export var head_model_scale: float = 1.0
@export var head_model_position: Vector3 = Vector3.ZERO
@export var head_model_rotation: Vector3 = Vector3.ZERO
## Re-skin the head: a texture and/or tint. Texture null + colour WHITE = keep its material.
@export var head_texture: Texture2D
@export var head_color: Color = Color.WHITE
## Tint the ARMS / LEGS (WHITE = keep the default tint). Their models aren't swappable here (they swing with the gait).
@export var arm_color: Color = Color.WHITE
@export var leg_color: Color = Color.WHITE

func _validate_property(property: Dictionary) -> void:
	if property.name in [&"body_model", &"head_model"]:
		property.hint = PROPERTY_HINT_RESOURCE_TYPE
		property.hint_string = ModelResourceUtil.HINT
