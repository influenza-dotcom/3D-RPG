class_name RandomCoat
extends Node

## Drop-in "give this prop a random coat" component (designer-first: drag onto any prop that has a MeshInstance3D — a
## dog, a cat, a rat, a barrel — and fill the Inspector pools). On spawn it picks ONE albedo tint AND/OR ONE albedo
## texture at random from the authored pools and applies it to the mesh's material, so a litter of otherwise-identical
## dogs comes out in varied coats instead of all-white. Purely cosmetic; rolls once on ready and never again.
##
## Why it DUPLICATES the material: a prop's material is a SHARED resource across every instance of its scene (the dog's
## StandardMaterial3D lives in dog.tscn as a sub-resource, reused by every spawned dog). Tinting it in place would
## recolour ALL dogs at once — and mutate the on-disk resource. So we duplicate the live material per instance, tint the
## copy, and reassign it as material_override — each dog then owns its own coat.
##
## ORDERING (why deferred): a Throwable pushes ThrowableData.material onto the mesh's material_override in ITS _ready,
## and a child's _ready runs BEFORE its parent's. So we apply our coat on a DEFERRED call — which flushes after every
## _ready this frame — reading whatever material_override the host settled on and duplicating THAT. The outline / hit
## flash live on material_OVERLAY (a separate channel, see Throwable._setup_overlay_chain), so recolouring the override
## never disturbs them.
##
## The mesh-resolution + material-duplication rules above are shared with SprayPaintable (the spray-can twin) and live
## in `MeshCoat` (`scripts/components/mesh_coat.gd`); this component owns only the roll-once-at-spawn policy.
##
## Editor-safe: does nothing at edit time (no random coat is ever baked into the saved scene). Not persisted — a
## hand-placed prop re-rolls its coat each load, which is fine for a cosmetic-only, non-saved dynamic prop.

## Albedo TINT pool. Each entry MULTIPLIES the mesh's base albedo, so the texture's pattern/shading is preserved and
## just recoloured (white base texture * brown tint = a brown dog). Include a plain white Color(1,1,1) so some props
## keep their natural colour. Empty => the tint is left untouched.
@export var coat_tints: Array[Color] = []
## Albedo TEXTURE pool. Each entry REPLACES the mesh's albedo texture outright (a full coat swap). Author extra coat
## PNGs and drop them here for spotted / patterned variants. Empty => the base texture is kept (only the tint changes).
@export var coat_albedos: Array[Texture2D] = []
## Optional explicit target. Empty => auto-resolve: the host's `mesh_instance` (a Throwable exposes one) else the first
## MeshInstance3D under the host. Point it at a specific mesh when the prop has several and only one wears the coat.
@export var mesh_path: NodePath
## Master switch. Off => inert (no coat applied). On by default.
@export var enabled: bool = true


func _ready() -> void:
	if Engine.is_editor_hint() or not enabled:
		return
	# Defer so we run AFTER the host Throwable's _ready has pushed ThrowableData.material onto material_override (child
	# _ready runs before parent _ready; a deferred call flushes after all _ready calls this frame). A self-method
	# Callable is dropped safely by the MessageQueue if this node is freed before the flush.
	_apply_coat.call_deferred()


## Pick + apply one coat. Rolls ONCE for the tint and once for the texture so every surface of this prop shares the
## same coat, then for each target mesh duplicates its live material and recolours the copy. Reads whatever material the
## host settled on, so it composes with Throwable's data.material without knowing about it.
func _apply_coat() -> void:
	var meshes := MeshCoat.resolve_meshes(self, mesh_path)
	if meshes.is_empty():
		return
	# null in either channel == "leave this one untouched". Written as explicit if/else, not a ternary: `Color if … else
	# null` mixes a value-type with null (INCOMPATIBLE_TERNARY). A Texture2D is a nullable Object so the tex line wouldn't
	# warn, but keeping both the same reads clearer and stays symmetric.
	var tint: Variant = null
	if not coat_tints.is_empty():
		tint = coat_tints[pick_index(coat_tints.size(), randf())]
	var tex: Variant = null
	if not coat_albedos.is_empty():
		tex = coat_albedos[pick_index(coat_albedos.size(), randf())]
	if tint == null and tex == null:
		return  # nothing authored to apply — leave the natural material untouched
	for m in meshes:
		var mat := MeshCoat.writable_material(m)  # per-instance duplicate; never the shared scene resource
		if tint != null:
			mat.albedo_color = tint
		if tex != null:
			mat.albedo_texture = tex
		m.material_override = mat


## Pure pick: map a [0,1) roll to a valid index in a pool of `count`. Static + tiny so it's unit-testable with literal
## rolls, mirroring PropFollow.should_blink / Pettable.eligible. count<=0 => 0 (caller guards against empty pools).
static func pick_index(count: int, roll: float) -> int:
	if count <= 0:
		return 0
	return clampi(int(roll * count), 0, count - 1)
