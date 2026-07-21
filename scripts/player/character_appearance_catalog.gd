@tool
class_name CharacterAppearanceCatalog
extends Resource

## The single, designer-editable SOURCE OF TRUTH for what the player character customizer can pick: the list of
## selectable HEADS and BODIES (each a CharacterPartOption), plus the SHARED arm/leg models + placements every
## composed character rig uses, and the limb colour palette the arm/leg swatch pickers offer. Add a head or a body
## by dropping one more CharacterPartOption into `heads` / `bodies` in the inspector — no code.
##
## Two ways it's consumed, both via configure_swap() feeding a BodyModelSwap's OWN exports (never a host `look`,
## which would leak a head/body into the player's first-person legs rig):
##   • the creation-screen + Stats-screen live 3D preview (CharacterPreview),
##   • (future) any real third-person player body.
##
## The shipped default is built IN CODE (default(), via preload — always-correct uids). A project can override it
## by authoring `res://resources/characters/PlayerAppearanceCatalog.tres`; get_catalog() prefers that when present.
## Uncustomised state is the EMPTY appearance dict (a fresh/older save) — configure_swap then uses every default
## below, so a never-customised character still renders the shipped look.

## Where a project's authored override lives. get_catalog() loads it when present, else falls back to default().
const OVERRIDE_PATH := "res://resources/characters/PlayerAppearanceCatalog.tres"

## Pickable HEAD models (composed onto a torso body). Order = cycler order; the first VALID one is the default.
@export var heads: Array[CharacterPartOption] = []
## Pickable BODY models. A `whole_body` body renders alone (its own head/arms/legs); a torso composes with a head.
@export var bodies: Array[CharacterPartOption] = []

# --- Shared arms + legs (every COMPOSED rig uses these; only their COLOUR is player-chosen) --------------------
@export var arm_model: Resource
@export var arm_scale: float = 1.0
@export var arm_position: Vector3 = Vector3.ZERO
@export var arm_rotation: Vector3 = Vector3.ZERO
@export var leg_model: Resource
@export var leg_scale: float = 1.0
@export var leg_position: Vector3 = Vector3.ZERO
@export var leg_rotation: Vector3 = Vector3.ZERO

# --- Default colours (used for the EMPTY / never-customised appearance, and as the customizer's starting pick) --
## FIXED skin tint over the head + body (WHITE = show the model/texture as-authored, no tint). The character
## creator no longer offers a skin-colour picker, so every character uses this one tint — edit it here to reskin
## the shipped look for everyone.
@export var default_skin_color: Color = Color.WHITE
@export var default_arm_color: Color = Color(0.19, 0.33, 0.56, 1.0)
@export var default_leg_color: Color = Color(0.49, 0.18, 0.22, 1.0)

# --- Swatch palette offered by the arm/leg colour pickers (designer-editable) ---------------------------------
# WHITE is the "no tint" sentinel everywhere downstream (BodyModelSwap._skin shows the model's own material for a
# WHITE colour). The LIMB palette deliberately ships NO pure white (arms/legs have no baked texture to reveal, so a
# white pick would just clear the tint to the raw model material). Keep pure WHITE out of limb_palette unless you
# want that behaviour.
@export var limb_palette: PackedColorArray = PackedColorArray()
## Brush palette offered by the "Shirt" creation tab, where the player PAINTS their own torso texture (a blank tee
## they decorate). Designer-editable like limb_palette; the paint canvas forces every pick OPAQUE (a drawn shirt
## replaces the albedo, so a translucent brush would punch holes, not reveal a base). Empty -> the tab still works,
## defaulting to a black brush.
@export var shirt_palette: PackedColorArray = PackedColorArray()

func _validate_property(property: Dictionary) -> void:
	if property.name in [&"arm_model", &"leg_model"]:
		property.hint = PROPERTY_HINT_RESOURCE_TYPE
		property.hint_string = ModelResource.HINT

# --- Lookups --------------------------------------------------------------------------------------------------

## The head option with this id (empty/unknown -> null). Only VALID options are matched.
func head_option(part_id: String) -> CharacterPartOption:
	return _find(heads, part_id)

## The body option with this id (empty/unknown -> null).
func body_option(part_id: String) -> CharacterPartOption:
	return _find(bodies, part_id)

## First valid head (the default pick) — null only if the catalog ships no usable head.
func default_head() -> CharacterPartOption:
	return _first_valid(heads)

## First valid body (the default pick) — null only if the catalog ships no usable body.
func default_body() -> CharacterPartOption:
	return _first_valid(bodies)

func default_head_id() -> StringName:
	var h := default_head()
	return h.id if h != null else &""

func default_body_id() -> StringName:
	var b := default_body()
	return b.id if b != null else &""

## Every VALID head/body option, in catalog order — what the cycler steps through.
func valid_heads() -> Array[CharacterPartOption]:
	return _valid(heads)

func valid_bodies() -> Array[CharacterPartOption]:
	return _valid(bodies)

static func _find(list: Array[CharacterPartOption], part_id: String) -> CharacterPartOption:
	if part_id.is_empty():
		return null
	for o in list:
		if o != null and o.is_valid() and String(o.id) == part_id:
			return o
	return null

static func _first_valid(list: Array[CharacterPartOption]) -> CharacterPartOption:
	for o in list:
		if o != null and o.is_valid():
			return o
	return null

static func _valid(list: Array[CharacterPartOption]) -> Array[CharacterPartOption]:
	var out: Array[CharacterPartOption] = []
	for o in list:
		if o != null and o.is_valid():
			out.append(o)
	return out

# --- Apply an appearance to a BodyModelSwap -------------------------------------------------------------------

## Configure `swap` (a BodyModelSwap) to render the character described by `appearance`, resolving every part from
## this catalog. `appearance` keys (all optional — an EMPTY dict yields the full shipped default look):
##   "body": String body id · "head": String head id · "skin"/"arm"/"leg": Color tints ·
##   "shirt": a player-DRAWN torso texture (a live Texture2D during creation, PNG bytes once saved) — see shirt_texture().
## A `whole_body` body renders alone (head/arm/leg models cleared). Sets the swap's OWN exports directly, so the
## parent needs no `look` — matching how the creation/Stats preview drives it.
func configure_swap(swap: BodyModelSwap, appearance: Dictionary) -> void:
	if swap == null:
		return
	var body := body_option(String(appearance.get("body", "")))
	if body == null:
		body = default_body()
	var skin: Color = appearance.get("skin", default_skin_color)
	var arm: Color = appearance.get("arm", default_arm_color)
	var leg: Color = appearance.get("leg", default_leg_color)
	# A custom drawn shirt (null when the player never painted one). Only a TORSO-style body wears it — on a
	# whole_body model the "body" is the entire character, and projecting a tee across its face/limbs is wrong.
	var shirt := shirt_texture(appearance)
	if body != null and body.whole_body:
		shirt = null

	# Body (torso, or a whole-character model). A custom drawn SHIRT (if any) replaces the body's own texture and
	# shows UNTINTED (body_color forced WHITE) so the player's art reads true; otherwise skin tints the body. A
	# null-model catalog leaves the swap body-less (the shirt then has nothing to skin).
	swap.body_model = body.model if body != null else null
	if body != null:
		swap.body_model_scale = body.scale
		swap.body_model_position = body.position
		swap.body_model_rotation = body.rotation
		# A DRAWN shirt is a flat picture, not an atlas texture — flag the swap to project it planar onto the
		# chest (the torso's own UV unwrap would scatter it into scraps). Set BEFORE body_texture so the texture
		# setter's apply already sees the right mode.
		swap.body_texture_planar = shirt != null
		swap.body_texture = shirt if shirt != null else body.texture
	swap.body_color = Color.WHITE if shirt != null else skin

	if body != null and body.whole_body:
		# A complete character model brings its own head/arms/legs — render it ALONE.
		swap.head_model = null
		swap.arm_model = null
		swap.leg_model = null
		return

	# Head (composed onto the torso). Falls back to the default head when the stored id is gone.
	var head := head_option(String(appearance.get("head", "")))
	if head == null:
		head = default_head()
	swap.head_model = head.model if head != null else null
	if head != null:
		swap.head_scale = head.scale
		swap.head_position = head.position
		swap.head_rotation = head.rotation
		swap.head_texture = head.texture
	swap.head_color = skin

	# Shared arms + legs (models fixed by the catalog; only the colour is player-chosen).
	swap.arm_model = arm_model
	swap.arm_scale = arm_scale
	swap.arm_position = arm_position
	swap.arm_rotation = arm_rotation
	swap.arm_color = arm
	swap.leg_model = leg_model
	swap.leg_scale = leg_scale
	swap.leg_position = leg_position
	swap.leg_rotation = leg_rotation
	swap.leg_color = leg

## Resolution the drawn shirt is NEAREST-upscaled to before it skins the torso (matches ShirtCanvas.apply_res), so
## the chunky pixels stay crisp through the 3D material's linear filter — used only on the decode-from-bytes path.
const SHIRT_APPLY_RES := 128

## Resolve a stored shirt (appearance["shirt"]) to a Texture2D for the torso albedo, or null when there's no custom
## shirt (-> the body option's own texture is used). Accepts either the LIVE ImageTexture the creator paints (passed
## straight through, so per-stroke in-place updates keep showing) or the SAVED PNG bytes (decoded + NEAREST-upscaled).
## Static so save/load + the Stats portrait can call it without a catalog instance.
static func shirt_texture(appearance: Dictionary) -> Texture2D:
	var v: Variant = appearance.get("shirt")
	if v is Texture2D:
		return v
	if v is Image:
		return ImageTexture.create_from_image(v)
	if v is PackedByteArray:
		var bytes := v as PackedByteArray
		if bytes.is_empty():
			return null
		var img := Image.new()
		if img.load_png_from_buffer(bytes) != OK:
			return null
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() < SHIRT_APPLY_RES:
			img.resize(SHIRT_APPLY_RES, SHIRT_APPLY_RES, Image.INTERPOLATE_NEAREST)
		return ImageTexture.create_from_image(img)
	return null

# --- The shipped default catalog (built in code so its resource uids are always valid) ------------------------

static var _cached: CharacterAppearanceCatalog = null

## The catalog to use everywhere: the authored override .tres when present, else the code-built default(). Cached
## after the first resolve (runtime). Call reset_cache() if an editor tool rewrites the override.
static func get_catalog() -> CharacterAppearanceCatalog:
	if _cached != null:
		return _cached
	if ResourceLoader.exists(OVERRIDE_PATH):
		var res: Resource = load(OVERRIDE_PATH)
		if res is CharacterAppearanceCatalog:
			_cached = res
			return _cached
	_cached = default()
	return _cached

static func reset_cache() -> void:
	_cached = null

## Build the shipped catalog from the real project assets — the CODE FALLBACK used only if the authored
## resources/characters/PlayerAppearanceCatalog.tres is missing (get_catalog() prefers the .tres). Head/body
## PLACEMENTS come from the tuned NPC rig (scenes/enemies/enemy.tscn): torso.tscn + headblue.glb both seat at
## scale 0.205, the head at (0, 0.615, 0.04) rot (0, 90, 0). The three EXTRA heads reuse that seat as a starting
## point — they need per-head fine-tuning (open scenes/character_customizer_setup.tscn, dial it in on the torso like
## an NPC, copy the numbers into the .tres). Only the standard torso body ships; whole_body bodies aren't seeded here.
static func default() -> CharacterAppearanceCatalog:
	var c := CharacterAppearanceCatalog.new()

	# Each head model has its OWN native facing / origin / native size, so each needs its OWN scale + position +
	# rotation to sit forward on the neck — they do NOT share one seat. Face axis -> the yaw that faces the rig's +Z
	# front: headblue + spiky's femalehead face -X (yaw 90); head + chrysalis face +X (yaw -90). scale/position are
	# fitted to headblue's seat (height-normalised to it, then each head's AABB re-centred onto the same neck point).
	# Keep in sync with the authored resources/characters/PlayerAppearanceCatalog.tres (the runtime source; this
	# default() is only the fallback when that .tres is missing). "spiky" uses femalehead.blend — the CLEAN source of
	# the spiky-haired head; the female_head.glb export is off-origin + lopsided (renders off-centre even when fitted).
	var head_tex: Texture2D = load("res://assets/models/headblue_Material Base Color.png")
	c.heads = [
		_opt(&"headblue", "Blue", load("res://assets/models/headblue.glb"), 0.205, Vector3(0.0, 0.615, 0.04), Vector3(0.0, 90.0, 0.0), head_tex),
		_opt(&"head", "Classic", load("res://assets/models/head.glb"), 0.4183, Vector3(0.0, 0.4062, -0.0877), Vector3(0.0, -90.0, 0.0), null),
		_opt(&"spiky", "Spiky", load("res://assets/models/femalehead.blend"), 0.1199, Vector3(0.0, 0.3342, -0.0456), Vector3(0.0, 90.0, 0.0), null),
		_opt(&"chrysalis", "[PH] Chrysalis", load("res://assets/models/head_chrysalis.glb"), 0.2436, Vector3(0.0, 0.468, 0.1173), Vector3(0.0, -90.0, 0.0), null),
	]

	var body_tex: Texture2D = load("res://scenes/stupidbody_Material Base Color.png")
	# One shipped body: the standard torso (composes with the chosen head + shared arms/legs). whole_body bodies
	# (a complete-character model that renders alone) are still SUPPORTED — add a CharacterPartOption with
	# whole_body = true to an authored catalog — just not shipped by default.
	c.bodies = [
		_opt(&"standard", "Standard", load("res://scenes/torso.tscn"), 0.205, Vector3.ZERO, Vector3(0.0, -90.0, 0.0), body_tex),
	]

	c.arm_model = load("res://assets/models/arm.blend")
	c.arm_scale = 0.35
	c.arm_position = Vector3(-0.27, 0.155, -0.05)
	c.arm_rotation = Vector3(90.0, 0.0, 0.0)
	c.leg_model = load("res://leg.blend")
	c.leg_scale = 0.44
	c.leg_position = Vector3(0.095, -0.265, -0.02)
	c.leg_rotation = Vector3(0.0, -90.0, 0.0)

	c.default_skin_color = Color.WHITE
	c.default_arm_color = Color(0.19, 0.33, 0.56, 1.0)
	c.default_leg_color = Color(0.49, 0.18, 0.22, 1.0)
	c.limb_palette = PackedColorArray([
		Color(0.19, 0.33, 0.56), Color(0.49, 0.18, 0.22), Color(0.20, 0.20, 0.22),
		Color(0.75, 0.72, 0.62), Color(0.30, 0.42, 0.30), Color(0.55, 0.40, 0.22),
		Color(0.82, 0.62, 0.20), Color(0.85, 0.85, 0.88),
	])
	# A broad, opaque brush spread for the "Shirt" paint tab — darks + whites + a saturated rainbow, so a player can
	# draw a recognisable design. Unlike limb_palette, pure BLACK/WHITE are welcome here (they're real shirt colours,
	# not the "no tint" sentinel — the drawn texture replaces the albedo outright).
	c.shirt_palette = PackedColorArray([
		Color(0.09, 0.09, 0.11), Color(0.5, 0.5, 0.52), Color(0.95, 0.95, 0.95),
		Color(0.85, 0.16, 0.16), Color(0.95, 0.52, 0.12), Color(0.96, 0.83, 0.18),
		Color(0.28, 0.66, 0.28), Color(0.16, 0.5, 0.85), Color(0.36, 0.26, 0.7),
		Color(0.85, 0.32, 0.62), Color(0.55, 0.36, 0.22), Color(0.96, 0.78, 0.6),
	])
	return c

static func _opt(part_id: StringName, part_name: String, model: Resource, scale: float, pos: Vector3, rot: Vector3, tex: Texture2D) -> CharacterPartOption:
	var o := CharacterPartOption.new()
	o.id = part_id
	o.display_name = part_name
	o.model = model
	o.scale = scale
	o.position = pos
	o.rotation = rot
	o.texture = tex
	return o
