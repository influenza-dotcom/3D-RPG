@tool
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
##
## RE-DROP FIDELITY: a prop that becomes an inventory item and is later dropped is REBUILT from its scene, which would
## normally re-roll a NEW random coat (the "my dog changed colour when I dropped it" bug). So a picked-up dog STASHES
## its live coat onto its Item (DogPickup, via read_applied_tint → COAT_META) and the drop RESTORES it (WorldItem sets
## preset_tint from COAT_META). When preset_tint is set the roll is SKIPPED and that exact colour is applied instead —
## so a dropped dog keeps the coat it had, whether that came from this roller or from a spray-paint recolour.
##
## COAT-BASED PRICING: a coat can also be worth more money. The optional `coat_value_mults` pool assigns each coat in
## `coat_tints` a VALUE multiplier (index-for-index) — a rare black or ginger dog fetches more zorkmids than a plain
## white one. Only DogPickup reads it (via `effective_value_mult`, folded into `DogPickup.build_item_for_size`); a
## RandomCoat on a prop with no size-priced pickup simply ignores it. Empty pool => every coat prices the same, so this
## is fully backwards-compatible. The multiplier follows the coat through the re-drop round-trip above: the restored
## `preset_tint` maps back to the same pool entry, so a re-dropped rare dog keeps both its colour AND its price.

## Item metadata key: the captured live coat tint (a Color) a re-dropped prop is restored to. Written by
## DogPickup on stash, read by WorldItem.build on drop into preset_tint. See the RE-DROP FIDELITY note above.
const COAT_META := &"random_coat_tint"

## How close two coat tints must be (per RGB channel) to count as "the same coat" for pricing. Far tighter than the
## gap between any two authored coats, so a rolled/preset colour matches its own pool entry exactly while an arbitrary
## spray-paint colour matches none (and prices at the neutral 1.0). Alpha is ignored — coats are opaque; alpha is the
## preset-unset sentinel, not part of the colour.
const TINT_MATCH_EPS := 0.02

## Albedo TINT pool. Each entry MULTIPLIES the mesh's base albedo, so the texture's pattern/shading is preserved and
## just recoloured (white base texture * brown tint = a brown dog). Include a plain white Color(1,1,1) so some props
## keep their natural colour. Empty => the tint is left untouched.
@export var coat_tints: Array[Color] = []:
	set(value):
		coat_tints = value
		update_configuration_warnings()
## Per-coat VALUE multiplier, index-aligned to `coat_tints`: a prop wearing coat_tints[i] is worth coat_value_mults[i] ×
## its base trade value, so rarer / prettier coats sell for more. Leave EMPTY to price every coat the same (the default —
## fully backwards-compatible); a missing or out-of-range entry falls back to 1.0. Author it in the SAME order as
## coat_tints. Only DogPickup reads it (see effective_value_mult); harmless on a prop without a size-priced pickup.
@export var coat_value_mults: Array[float] = []:
	set(value):
		coat_value_mults = value
		update_configuration_warnings()
## FIXED coat tint that OVERRIDES the random roll — when set, this exact colour is applied and no roll happens. The
## sentinel for "unset" is a fully-transparent colour (alpha 0.0): a real coat tint always has alpha 1.0, so any
## alpha > 0 counts as "preset". Not usually hand-authored — it's how WorldItem restores a re-dropped prop's stashed
## coat (see COAT_META) so it doesn't re-roll a different colour.
@export var preset_tint: Color = Color(0.0, 0.0, 0.0, 0.0)
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
	# A preset_tint (alpha > 0) WINS over the pool roll: a re-dropped prop is restored to its stashed colour instead of
	# rolling a fresh one (see the RE-DROP FIDELITY note). A hand-placed prop leaves preset_tint unset and rolls normally.
	var tint: Variant = null
	if preset_tint.a > 0.0:
		tint = preset_tint
	elif not coat_tints.is_empty():
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


## Read the coat tint CURRENTLY applied to `host` — its `mesh_instance`'s material_override albedo (a Throwable/dog
## exposes its visual root there), else the first MeshInstance3D's. Returns the alpha-0 "unset" sentinel when there's
## no readable StandardMaterial3D, so the result round-trips straight into preset_tint. Captures whatever colour the
## mesh is wearing — this roller's roll OR a spray-paint recolour — so DogPickup can stash it onto the dog's Item and
## a re-dropped dog keeps its exact coat.
static func read_applied_tint(host: Node) -> Color:
	if host == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	var mesh: MeshInstance3D = null
	var mi: Variant = host.get(&"mesh_instance")
	if mi is MeshInstance3D:
		mesh = mi as MeshInstance3D
	else:
		mesh = MeshCoat.first_mesh(host)
	if mesh == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	var mat := mesh.material_override
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).albedo_color
	return Color(0.0, 0.0, 0.0, 0.0)


## The value multiplier for a given coat tint — the coat_value_mults entry aligned to the coat_tints entry this colour
## matches (see TINT_MATCH_EPS). A rolled or re-dropped (preset) coat is an EXACT pool colour, so it matches its own
## entry; a spray-paint recolour is an arbitrary colour off no entry and matches nothing -> the neutral 1.0 (defacing a
## prize coat drops it to base value — acceptable, and it stops arbitrary paints from mispricing). No multipliers
## authored, or no match, => 1.0. Used by DogPickup to fold the coat into a dog's trade value.
func value_mult_for_tint(tint: Color) -> float:
	if coat_value_mults.is_empty():
		return 1.0
	for i in coat_tints.size():
		if _tint_matches(coat_tints[i], tint):
			if i < coat_value_mults.size():
				return maxf(coat_value_mults[i], 0.0)
			return 1.0  # this coat has no authored multiplier (short pool) -> neutral
	return 1.0


## The value multiplier for the coat this instance is (or will be) wearing. Prefers the preset colour when one is set
## (a re-dropped dog, priced from its restored colour the instant it spawns — the roll is skipped for it), else the
## colour currently on the host's mesh. Reads the SAME tint DogPickup captures (read_applied_tint), so what's priced,
## captured, and restored on re-drop all agree. Before the deferred roll has run the mesh still wears its natural
## albedo, which prices as its matching coat or the neutral 1.0 — corrected the moment the coat rolls (DogPickup
## recomputes on hover / pickup). Off-tree with no preset (get_parent() == null) it safely reads the unset sentinel -> 1.0.
func effective_value_mult() -> float:
	if preset_tint.a > 0.0:
		return value_mult_for_tint(preset_tint)
	return value_mult_for_tint(read_applied_tint(get_parent()))


## True when two coat tints are the same coat within TINT_MATCH_EPS on every RGB channel (alpha ignored). Static + pure
## so the pricing lookup is unit-testable with literal colours.
static func _tint_matches(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= TINT_MATCH_EPS and absf(a.g - b.g) <= TINT_MATCH_EPS and absf(a.b - b.b) <= TINT_MATCH_EPS


## @tool guard-rail: coat_value_mults is priced index-for-index against coat_tints, so a length mismatch silently
## prices the extra/missing coats at ×1.0. Warn the designer to keep them aligned (or clear the multipliers to price
## every coat the same). Empty multipliers = "price all coats equally" and is NOT a mismatch.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not coat_value_mults.is_empty() and coat_value_mults.size() != coat_tints.size():
		warnings.append("coat_value_mults has %d entr%s but coat_tints has %d — they're priced index-for-index, so unmatched coats fall back to ×1.0. Match their lengths, or clear coat_value_mults to price every coat the same." % [coat_value_mults.size(), "y" if coat_value_mults.size() == 1 else "ies", coat_tints.size()])
	return warnings
