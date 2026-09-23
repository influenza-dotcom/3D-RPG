extends GutTest

## Contract tests for the first-person TORSO (look-down body awareness): looking down shows your own chest —
## your chosen body model, your drawn shirt, your skin tint — on the same rig as the FP legs. The rules that
## must hold, because their failures are silent:
##   1. BODY-ONLY: the FP rig must never mount a HEAD — it sits exactly where the camera is.
##   2. A whole_body appearance (one-piece character model) SKIPS the torso — it can't drop its head.
##   3. The customizer's drawn shirt reaches the FP chest (it planar-projects untinted, like the portrait).
##   4. The chest faces the PLAYER's forward (-Z), not the NPC's (+Z) it was authored for.
##   5. Visibility: hidden until you LOOK DOWN, dithered (never alpha-blended), gone while crouched or talking.
##   6. Crouching sinks the torso by the head's own live drop, in PLAYER metres, so chest-to-eye spacing holds.
##
## Everything is DRIVEN, off-tree (the test_fp_body_arms idiom): a bare first_person_body.gd with a bare player.gd
## host (no _ready on either), a real Head / Crouch for the two reads the per-frame update makes, and real
## BodyModelSwap rigs to receive the stamps. An off-tree rig stores every model/transparency write without
## instancing anything, which is exactly the state these rules are about.

const FP_BODY_SOURCE := "res://scripts/player/first_person_body.gd"
const PLAYER_SOURCE := "res://scripts/player/player.gd"
const TORSO_SCENE := "res://scenes/bodyparts/torso.tscn"
const SHIRT_SHADER := "res://resources/shaders/shirt_planar.gdshader"

var _saved_active: DialogueResource = null
var _saved_suspended: bool = false


func before_each() -> void:
	_saved_active = DialogueManager._active
	_saved_suspended = DialogueManager._suspended


func after_each() -> void:
	# The dialogue test fakes an engaged conversation on the autoload; never let it leak into a later file.
	DialogueManager._active = _saved_active
	DialogueManager._suspended = _saved_suspended
	_saved_active = null


## A bare component + host (with a real Head and Crouch) + an off-tree rig. Caller frees via _teardown.
func _build() -> Dictionary:
	var host = load(PLAYER_SOURCE).new()
	var head := Head.new()
	var crouch := Crouch.new()
	host.head = head
	host.crouch = crouch
	var body = load(FP_BODY_SOURCE).new()
	body.host = host
	var rig := BodyModelSwap.new()
	return {"host": host, "head": head, "crouch": crouch, "body": body, "rig": rig}


func _teardown(parts: Dictionary) -> void:
	(parts["rig"] as Node).free()
	(parts["body"] as Node).free()
	(parts["host"] as Node).free()  # frees a rig _build_first_person_legs parented under it, too
	(parts["head"] as Node).free()
	(parts["crouch"] as Node).free()


## A body option the catalog's lookups will actually match (is_valid needs an id AND a real model).
func _option(id: StringName, whole: bool) -> CharacterPartOption:
	var o := CharacterPartOption.new()
	o.id = id
	o.model = load(TORSO_SCENE)
	o.whole_body = whole
	o.scale = 0.37
	o.position = Vector3(0.01, 0.2, -0.03)
	o.rotation = Vector3(5.0, 30.0, 0.0)  # a non-trivial authored facing, so the flip is checked off +Z, not off zero
	o.texture = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	return o


## Stamp the FP torso with the catalog's bodies temporarily replaced by `options`. Restores BEFORE returning,
## so a failing assert afterwards can never leak the stub catalog into later tests.
func _configure_with(parts: Dictionary, options: Array[CharacterPartOption]) -> void:
	var cat := CharacterAppearanceCatalog.get_catalog()
	var saved := cat.bodies.duplicate()
	cat.bodies = options
	parts["body"]._configure_fp_torso(parts["rig"])
	cat.bodies = saved


func test_a_split_look_wears_its_chest_but_never_a_head_or_the_catalog_arms() -> void:
	var parts := _build()
	var body = parts["body"]
	var rig: BodyModelSwap = parts["rig"]
	var split := _option(&"__test_split__", false)
	parts["host"].appearance = {"body": "__test_split__"}
	body.fp_torso_offset = Vector3(0.0, -0.05, 0.02)
	_configure_with(parts, [split] as Array[CharacterPartOption])  # the component's SHIPPED toggles, untouched
	assert_eq(rig.body_model, split.model,
		"the FP torso must default ON and mount the CHOSEN body model — looking down should show your chest")
	assert_null(rig.head_model,
		"the FP torso must NEVER mount a head — it would sit exactly where the camera is")
	assert_null(rig.arm_model,
		"the torso stamp must not mount the catalog arms — the hands are separate rigs")
	assert_almost_eq(rig.body_model_scale, split.scale, 0.0001, "the chest must wear the catalog body's authored scale")
	assert_eq(rig.body_model_position, split.position + Vector3(0.0, -0.05, 0.02),
		"fp_torso_offset must NUDGE the catalog body's authored position, never replace it")
	var off := _build()
	off["body"].first_person_torso = false
	off["host"].appearance = {"body": "__test_split__"}
	_configure_with(off, [split] as Array[CharacterPartOption])
	assert_null(off["rig"].body_model, "first_person_torso = false must mount no chest at all")
	_teardown(off)
	_teardown(parts)


func test_a_whole_body_look_skips_the_fp_torso() -> void:
	# A one-piece character model can't have its head chopped off, so it stays legs-only. The CONTROL is the same
	# rig and the same catalog with a split body — which must mount, or this test proves nothing.
	var whole := _option(&"__test_whole__", true)
	var split := _option(&"__test_split__", false)
	var parts := _build()
	parts["host"].appearance = {"body": "__test_whole__"}
	_configure_with(parts, [whole, split] as Array[CharacterPartOption])
	assert_null(parts["rig"].body_model,
		"a whole_body look must skip the FP torso — mounting it would put its head inside the camera")
	var control := _build()
	control["host"].appearance = {"body": "__test_split__"}
	_configure_with(control, [whole, split] as Array[CharacterPartOption])
	assert_eq(control["rig"].body_model, split.model, "control: a split look in the same catalog DOES mount its chest")
	_teardown(control)
	_teardown(parts)


func test_a_drawn_shirt_reaches_the_fp_chest_untinted_and_planar() -> void:
	var split := _option(&"__test_split__", false)
	var skin := Color(0.42, 0.3, 0.2)
	var shirt := ImageTexture.create_from_image(Image.create(4, 8, false, Image.FORMAT_RGBA8))
	var drawn := _build()
	drawn["host"].appearance = {"body": "__test_split__", "skin": skin, "shirt": shirt}
	_configure_with(drawn, [split] as Array[CharacterPartOption])
	var r: BodyModelSwap = drawn["rig"]
	assert_eq(r.body_texture, shirt, "the player-DRAWN shirt must reach the FP chest, over the body's own texture")
	assert_true(r.body_texture_planar, "a drawn shirt must planar-project — the torso's atlas UVs scatter a drawing into scraps")
	assert_eq(r.body_color, Color.WHITE, "a drawn shirt must stay UNTINTED — the skin colour would dye the player's art")
	var plain := _build()
	plain["host"].appearance = {"body": "__test_split__", "skin": skin}
	_configure_with(plain, [split] as Array[CharacterPartOption])
	var p: BodyModelSwap = plain["rig"]
	assert_eq(p.body_texture, split.texture, "with no drawn shirt the chest keeps the body option's own texture")
	assert_false(p.body_texture_planar, "...on the mesh's own UVs (planar is only for a drawn shirt)")
	assert_eq(p.body_color, skin, "...tinted with the player's chosen skin")
	var bare := _build()
	bare["host"].appearance = {"body": "__test_split__"}
	_configure_with(bare, [split] as Array[CharacterPartOption])
	assert_eq(bare["rig"].body_color, CharacterAppearanceCatalog.get_catalog().default_skin_color,
		"an appearance with no skin falls back to the catalog's default skin, not black or white")
	_teardown(bare)
	_teardown(plain)
	_teardown(drawn)


func test_the_torso_faces_the_players_forward() -> void:
	# Body options are authored facing the NPC's +Z forward; the player faces -Z. So whatever authored rotation
	# made the body face +Z as an NPC must make it face -Z on you — otherwise you wear the torso BACKWARDS (the
	# first-playtest bug). Checked as a direction, off a non-trivial authored rotation.
	var split := _option(&"__test_split__", false)
	var parts := _build()
	parts["host"].appearance = {"body": "__test_split__"}
	_configure_with(parts, [split] as Array[CharacterPartOption])
	var npc_basis := Basis.from_euler(split.rotation * (PI / 180.0))
	var fp_basis := Basis.from_euler((parts["rig"] as BodyModelSwap).body_model_rotation * (PI / 180.0))
	# The model-local direction that faced the NPC's +Z, carried through the FP stamp.
	var faces: Vector3 = fp_basis * (npc_basis.inverse() * Vector3(0.0, 0.0, 1.0))
	assert_almost_eq(faces.x, 0.0, 0.0001, "the FP chest must face straight ahead (x) — got %s" % faces)
	assert_almost_eq(faces.y, 0.0, 0.0001, "the FP chest must not pitch off the authored facing (y) — got %s" % faces)
	assert_almost_eq(faces.z, -1.0, 0.0001,
		"the FP chest must face the player's -Z, i.e. the NPC facing flipped 180 about Y — got %s" % faces)
	_teardown(parts)


func test_the_torso_is_dither_see_through_and_hides_on_crouch() -> void:
	# The rule is LOOK-DOWN reveal: hidden at a level look, easing in across the reveal band, and at rest once
	# revealed the chest wears fp_torso_transparency while the legs go fully solid. Crouching overrides back toward
	# hidden (crouched, the lens sits among your knees), riding the already-eased crouch_t. The arms follow the chest.
	var parts := _build()
	var body = parts["body"]
	var head: Head = parts["head"]
	var crouch: Crouch = parts["crouch"]
	body._build_first_person_legs()  # the real rig: legs + the catalog chest + the catalog arms, off-tree
	var rig: BodyModelSwap = body._fp_legs
	assert_true(rig != null and rig.body_model != null and rig.leg_model != null and rig.arm_model != null,
		"the FP rig must build with a chest, legs and arms for this test to observe all three")
	if rig == null:
		_teardown(parts)
		return
	body.fp_torso_transparency = 0.25
	var dt := 1.0 / 60.0
	head.rotation_degrees.x = 0.0
	body._update_fp_torso(dt)
	assert_eq(rig.body_transparency, 1.0, "looking straight ahead the chest must be fully HIDDEN")
	assert_eq(rig.leg_transparency, 1.0, "...and so must the legs — one gate, every part")
	assert_eq(rig.arm_transparency, 1.0, "...and the body arms")
	var mid_deg: float = (body.fp_body_reveal_start_deg + body.fp_body_reveal_full_deg) * 0.5
	head.rotation_degrees.x = -mid_deg
	body._update_fp_torso(dt)
	var mid_see := rig.body_transparency
	assert_true(mid_see > 0.25 and mid_see < 1.0,
		"mid-band the chest must be part-dithered in (see %s) — no pop between hidden and revealed" % mid_see)
	head.rotation_degrees.x = -85.0
	body._update_fp_torso(dt)
	assert_almost_eq(rig.body_transparency, 0.25, 0.003,
		"looking fully down the chest must rest at fp_torso_transparency (its ghost amount), not solid and not hidden")
	assert_lt(rig.body_transparency, mid_see, "a deeper look must reveal MORE than a shallower one")
	assert_almost_eq(rig.leg_transparency, 0.0, 0.003, "revealed legs are fully solid — the ghost knob is the chest's")
	assert_almost_eq(rig.arm_transparency, 0.25, 0.003, "the body arms dissolve on the chest's own curve")
	crouch.crouch_t = 0.5
	body._update_fp_torso(dt)
	assert_true(rig.body_transparency > 0.25 and rig.body_transparency < 1.0,
		"half-way into a crouch the chest is fading out along crouch_t (see %s)" % rig.body_transparency)
	crouch.crouch_t = 1.0
	body._update_fp_torso(dt)
	assert_almost_eq(rig.body_transparency, 1.0, 0.003, "fully crouched the chest must be completely gone, not a ghost")
	assert_almost_eq(rig.leg_transparency, 1.0, 0.003, "...and the legs with it")
	assert_almost_eq(rig.arm_transparency, 1.0, 0.003, "...and the arms, which must never outlive the chest")
	# The authored knobs have to keep the rule meaningful.
	var shipped = load(FP_BODY_SOURCE).new()
	assert_between(shipped.fp_torso_transparency, 0.0, 0.5,
		"the FP torso rests near-solid ONCE REVEALED — this knob is the ghost amount, not the hide")
	assert_gt(shipped.fp_body_reveal_full_deg, shipped.fp_body_reveal_start_deg,
		"the reveal band must be a real range (full > start), or the ease divides toward a pop")
	assert_gt(shipped.fp_body_reveal_start_deg, 20.0,
		"the reveal must not start at a glance — below ~20 degrees you are looking where you are GOING, not at yourself")
	shipped.free()
	_teardown(parts)


func test_the_see_through_is_a_dither_on_every_material_path() -> void:
	# Smooth alpha would re-sort against the world and break the PS1 read, so the see-through is ALPHA-HASH on the
	# plain path, a per-instance duplicate (other NPCs share the original), and the DRAWN-SHIRT shader gets its
	# own see_through uniform — without that branch a custom-shirt chest would silently stay opaque.
	var rig := BodyModelSwap.new()
	var shared := StandardMaterial3D.new()
	var faded := rig._see_through_variant(shared, 0.4) as BaseMaterial3D
	assert_true(faded != null and faded != shared, "the see-through must go on a per-instance DUPLICATE, never the shared material")
	assert_eq(faded.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_HASH,
		"the body see-through must be alpha-HASH (dithered) — depth-writes stay on, no transparency sorting")
	assert_almost_eq(faded.albedo_color.a, 0.6, 0.0001, "0.4 see-through leaves 0.6 of the surface drawn")
	assert_eq(shared.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "the shared original must stay untouched")
	var solid := rig._see_through_variant(faded, 0.0) as BaseMaterial3D
	assert_eq(solid, faded, "a repeat application must reuse OUR tagged copy rather than stacking duplicates")
	assert_eq(solid.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "and a return to 0 restores solid on it")
	var shirt := ShaderMaterial.new()
	shirt.shader = load(SHIRT_SHADER)
	assert_eq(rig._see_through_variant(shirt, 0.7), shirt, "the drawn-shirt material is already per-mesh — no duplicate")
	assert_almost_eq(float(shirt.get_shader_parameter(&"see_through")), 0.7, 0.0001,
		"the see-through pass must route the planar shirt shader to its see_through dither uniform")
	var foreign := ShaderMaterial.new()
	foreign.shader = Shader.new()
	rig._see_through_variant(foreign, 0.7)
	assert_null(foreign.get_shader_parameter(&"see_through"), "a FOREIGN shader must be left alone")
	rig.free()
	# Shader scan (headless never compiles shaders, so the uniform's existence is only checkable as text).
	var shader_src := FileAccess.get_file_as_string(SHIRT_SHADER)
	assert_true(shader_src.contains("uniform float see_through"),
		"the drawn-shirt shader must declare the see_through dither — a custom-shirt chest must fade like a plain one")


func test_death_gibs_shed_the_torso_see_through() -> void:
	# Dying flings your torso as a body-part gib; the FP see-through must NOT ride along — a crouched death
	# otherwise throws a near-invisible torso that still offers its pickup prompt. Driven on a part carrying the
	# exact materials BodyModelSwap's see-through produces. (The shirt-shader half can't be observed headless:
	# the dummy renderer lists no uniforms, so a duplicated ShaderMaterial carries no parameters to clear.)
	var swap := BodyModelSwap.new()
	var live_override := swap._see_through_variant(StandardMaterial3D.new(), 0.8) as BaseMaterial3D
	var live_surface := swap._see_through_variant(StandardMaterial3D.new(), 0.8) as BaseMaterial3D
	swap.free()
	var part := Node3D.new()
	var chest := MeshInstance3D.new()
	chest.mesh = BoxMesh.new()
	chest.material_override = live_override
	part.add_child(chest)
	var sleeve := MeshInstance3D.new()
	sleeve.mesh = BoxMesh.new()
	sleeve.set_surface_override_material(0, live_surface)
	part.add_child(sleeve)
	var decal := MeshInstance3D.new()
	decal.mesh = BoxMesh.new()
	var authored := StandardMaterial3D.new()  # an untagged per-surface material the part legitimately carries
	decal.set_surface_override_material(0, authored)
	part.add_child(decal)
	var gib = load("res://scripts/effects/body_part_gib.gd").new()
	gib._strip_host_state(part)
	var stripped := chest.material_override as BaseMaterial3D
	assert_true(stripped != null, "the stripped chest must keep a material")
	if stripped != null:
		assert_eq(stripped.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED,
			"the gib strip must turn the tagged see-through override back to SOLID")
		assert_almost_eq(stripped.albedo_color.a, 1.0, 0.0001, "...at full alpha")
	assert_eq(live_override.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_HASH,
		"...on a duplicate — the override is shared by reference with the living rig, which must keep fading")
	assert_null(sleeve.get_surface_override_material(0),
		"a tagged per-surface see-through duplicate must be cleared back to the mesh's baked (solid) material")
	assert_eq(decal.get_surface_override_material(0), authored,
		"control: an UNTAGGED surface material is not see-through state and must survive the strip")
	gib.free()
	part.free()


func test_the_torso_crouch_follow_tracks_the_heads_live_drop() -> void:
	# The clip-safety contract: the torso sinks by exactly the head's current drop below its standing height, so
	# chest-to-eye spacing is constant. The drop is in PLAYER metres but the rig is scaled by fp_body_scale, so
	# the rig-local sink must come out equal to the head's drop once multiplied back through the rig's scale.
	var parts := _build()
	var body = parts["body"]
	var head: Head = parts["head"]
	head.position.y = 0.4  # the standing Head height the build caches
	body._build_first_person_legs()
	var rig: BodyModelSwap = body._fp_legs
	assert_true(rig != null and rig.body_model != null and rig.arm_model != null, "the FP rig must build a chest and arms")
	if rig == null:
		_teardown(parts)
		return
	assert_lt(rig.scale.y, 1.0, "sanity: the shipped rig is SCALED, or this test cannot tell player metres from rig metres")
	var dt := 1.0 / 60.0
	body._update_fp_torso(dt)
	var chest_standing := rig.body_model_position.y
	var arms_standing := rig.arm_position.y
	head.position.y = 0.4 - 0.3  # the camera lowered 0.3 m (a crouch)
	body._update_fp_torso(dt)
	assert_almost_eq((chest_standing - rig.body_model_position.y) * rig.scale.y, 0.3, 0.001,
		"the chest must drop exactly as far as the head did, in PLAYER metres — anything less and it creeps up into the lowered view")
	assert_almost_eq(rig.arm_position.y - arms_standing, rig.body_model_position.y - chest_standing, 0.001,
		"the body arms must sink with the chest, or the shoulders detach as you crouch")
	head.position.y = 0.4 + 0.2  # a head ABOVE its standing height (nothing lifts the body over its own hips)
	body._update_fp_torso(dt)
	assert_almost_eq(rig.body_model_position.y, chest_standing, 0.0001,
		"a head above standing must not raise the chest — the sink only ever follows a DROP")
	_teardown(parts)


func test_a_conversation_hides_the_whole_fp_body() -> void:
	# A talk swings the camera onto the speaker, and that focus pitch is often DOWN — precisely the look that reveals
	# your chest. Three facts are load-bearing and each fails silently:
	#   • it is asked of is_ENGAGED, not is_active: a suspending sub-menu (shop / level-up / ATM) reads inactive so
	#     that menu can open, and the body must stay gone behind it — so this drives the SUSPENDED case.
	#   • it is a HARD SET, not another eased term: the tree is paused for the conversation, so one frame must land
	#     it fully hidden.
	#   • every part takes it — chest, legs and arms.
	var parts := _build()
	var body = parts["body"]
	var head: Head = parts["head"]
	body._build_first_person_legs()
	var rig: BodyModelSwap = body._fp_legs
	if rig == null:
		fail_test("the FP rig must build for this test")
		_teardown(parts)
		return
	head.rotation_degrees.x = -85.0  # looking fully down: the body is revealed
	var dt := 1.0 / 60.0
	body._update_fp_torso(dt)
	assert_lt(rig.body_transparency, 1.0, "control: looking down with no conversation the chest is on screen")
	assert_lt(rig.leg_transparency, 1.0, "control: ...and so are the legs")
	DialogueManager._active = DialogueResource.new()
	DialogueManager._suspended = true  # a shop opened from the conversation: is_active() reads false, is_engaged() true
	body._update_fp_torso(dt)
	var chest := rig.body_transparency
	var legs := rig.leg_transparency
	var arms := rig.arm_transparency
	body.fp_body_hide_in_dialogue = false
	body._update_fp_torso(dt)
	var chest_opted_out := rig.body_transparency
	DialogueManager._active = _saved_active  # restore BEFORE asserting (after_each is the second net)
	DialogueManager._suspended = _saved_suspended
	assert_eq(chest, 1.0, "a conversation (even suspended behind a sub-menu) must hide the chest in ONE frame")
	assert_eq(legs, 1.0, "...and the legs, or a conversation frames a pair of disembodied thighs")
	assert_eq(arms, 1.0, "...and the body arms")
	assert_lt(chest_opted_out, 1.0, "control: fp_body_hide_in_dialogue off leaves the look-down reveal in charge mid-talk")
	_teardown(parts)
