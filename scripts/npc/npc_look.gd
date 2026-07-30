@tool
class_name NpcLook
extends Resource

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")
## Backs the apply_*_part PICK dropdowns below (a folder scan of res://resources/parts/<slot>/). PartLibrary never
## names NpcLook by type -- it reads a look duck-typed -- so this preload closes no parse cycle.
const PartLibrary = preload("res://scripts/components/part_library.gd")

## A reusable per-NPC APPEARANCE override, authorable as a .tres and SHARED across NPCs. Assign one to an NPC's
## `look` export and it drives that NPC's BodyModelSwap exactly like the NPC root's own inline appearance fields
## would -- the fields here MIRROR those names, so BodyModelSwap reads whichever is in play uniformly via .get().
##
## PRECEDENCE -- the NPC root itself carries NO appearance fields any more (the 14 inline ones were folded away;
## tests/test_npc_look.gd pins their absence), so there are only two layers. BodyModelSwap._look_src() hands back
## this resource when the host's `look` holds one, else the host NODE -- and an NPC declares none of the mirrored
## names, so a look-less NPC simply reads the BodyModelSwap child's OWN fields (where the shared default look
## lives). Assigning a look therefore WINS over that child: for any part whose MODEL is set here, this resource's
## model AND its scale / position / rotation replace the child's. Leave a part's model null and the child's own
## keeps rendering. Texture / colour resolve INDEPENDENTLY of the model (see BodyModelSwap._host_part), so you can
## re-skin the default body without swapping its mesh.
##
## A field left at its default (null model / WHITE colour / 1.0 scale) means "no override for this part" -- e.g. a
## look that only sets head_model + colours keeps the child's body. Author a "raider look" / "townsperson look"
## once in resources/ and reuse it across many NPCs instead of re-tuning each instance. BodyModelSwap previews it
## live. NOTE the field-name asymmetry with the child: a head's scale is `head_model_scale` HERE but `head_scale`
## on BodyModelSwap (PartLibrary.fields_for absorbs the difference for the apply_*_part pickers).

## PICK a seated BODY by name from res://resources/parts/bodies/ instead of dragging a model in. A MOMENTARY
## action, not stored state: choosing an id STAMPS that part's model + scale + position + rotation + texture into
## the body_model_* fields below and snaps this row back to empty. Everything stays hand-editable afterwards, the
## id is NOT remembered, and nothing new resolves at runtime -- this .tres keeps the plain model reference it
## always had, so deleting res://resources/parts/ never changes how an already-authored look renders.
## NO UNDO: the previous values are PRINTED to the Output panel before they are overwritten -- copy them back if
## you mis-pick.
@export var apply_body_part: String = "":
	set(value):
		apply_body_part = ""  # momentary: snaps back so re-picking the SAME part re-stamps
		if PartLibrary.stamp(self, PartLibrary.HOST_LOOK, PartLibrary.SLOT_BODIES, value):
			notify_property_list_changed()  # the stamp moved five other rows -- make the inspector re-read them
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
## PICK a seated HEAD by name from res://resources/parts/heads/ -- see apply_body_part above for the full
## contract. The part's seat lands in head_model_scale / _position / _rotation (this resource's field names, which
## differ from the BodyModelSwap child's head_scale / head_position / head_rotation -- PartLibrary.fields_for
## absorbs that). Because a look OVERRIDES the child for any part whose model it sets, picking HERE is the right
## place for an NPC that already carries a look.
@export var apply_head_part: String = "":
	set(value):
		apply_head_part = ""  # momentary: snaps back so re-picking the SAME part re-stamps
		if PartLibrary.stamp(self, PartLibrary.HOST_LOOK, PartLibrary.SLOT_HEADS, value):
			notify_property_list_changed()
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
	# A LIVE folder scan, so a part .tres dropped into res://resources/parts/<slot>/ lists with no editor restart.
	# There are no arm/leg rows here on purpose: a look carries no limb models (they swing with the gait, and stay
	# the BodyModelSwap child's) -- PartLibrary.fields_for returns {} for those slots to match.
	elif property.name == &"apply_body_part":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = PartLibrary.ids_csv(PartLibrary.SLOT_BODIES)
	elif property.name == &"apply_head_part":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = PartLibrary.ids_csv(PartLibrary.SLOT_HEADS)
