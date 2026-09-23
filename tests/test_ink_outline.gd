extends GutTest
## Contract tests for the Borderlands-style ink outline (scripts/effects/ink_outline.gd +
## resources/shaders/ink_outline.gdshader).
##
## The whole effect is one screen-space pass whose only failure mode is SILENCE: a uniform renamed on
## one side of the script/shader seam is not an error, it is a set_shader_parameter that goes nowhere
## and a line that stops appearing. This project has already been bitten by exactly that (the outline
## hull's dead `outline_thickness`, see Throwable.gd), so the drift guard here is the important test.
##
## Built OFF-TREE: load(...).new() WITHOUT add_child, so _ready never runs (no Settings lookup, no
## material construction, no _process); _params / _refresh / the static tint API are driven directly. The
## ring's CONSUMERS (GunVisuals, NpcOutline, Throwable, Ragdoll, ExplosionMesh / ExplosionArea, the casing,
## WeaponModelSwapper, Talkable / DialogueNPC) are driven through their own entry points too, off-tree where
## the component allows it and under a throwaway in-tree host where it needs _ready, and every ring check reads
## the id the duplicate is actually PAINTING (_painted_id). Two things stay source-read: the .gdshader files
## (headless runs a dummy rasterizer that never compiles a shader, so their text is the only thing available),
## and the camera_rig.tscn wiring, matching how test_smoke.gd already pins that rig — instantiating it would
## drag in the weapon scenes, lights and audio players for no added coverage.

const INK_PATH := "res://scripts/effects/ink_outline.gd"
## Reached through preload rather than the `InkOutline` global class name on purpose: the class cache is
## only populated by an import, so a checkout that has not been reimported yet would fail these tests
## with "Identifier not declared" instead of telling you anything about the ink pass.
const InkOutlineScript := preload("res://scripts/effects/ink_outline.gd")
const SHADER_PATH := "res://resources/shaders/ink_outline.gdshader"
## The mask viewport's own resolve pass — it ENCODES the depth that ink_outline.gdshader decodes, so the
## two are pinned against each other below.
const RESOLVE_SHADER_PATH := "res://resources/shaders/actor_mask_resolve.gdshader"
const RIG_PATH := "res://scenes/player/camera_rig.tscn"

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text

## The upper bound of an `@export_range` knob, read off the node's property list (the Inspector's own source), so a
## "ships at full strength" requirement is asserted against the authored range rather than a copied literal.
func _export_range_max(obj: Object, prop: String) -> float:
	for p in obj.get_property_list():
		if String(p["name"]) == prop and int(p["hint"]) == PROPERTY_HINT_RANGE:
			return float(String(p["hint_string"]).split(",")[1])
	assert_true(false, "%s is not an @export_range property any more - the range the test reads is gone" % prop)
	return NAN

## Uniform names declared by the shader, read from its SOURCE rather than reflected off the compiled
## program: Shader.get_shader_uniform_list() needs a real rendering driver, and the suite runs headless.
func _shader_uniform_names() -> Dictionary:
	var names := {}
	var re := RegEx.new()
	re.compile("(?m)^\\s*uniform\\s+\\w+\\s+(\\w+)")
	for m in re.search_all(_read(SHADER_PATH)):
		names[m.get_string(1)] = true
	return names

# ---------------------------------------------------------------------------------------------------
# The script -> shader seam
# ---------------------------------------------------------------------------------------------------

func test_every_pushed_parameter_is_a_real_shader_uniform() -> void:
	# THE drift guard. _params() keys ARE the uniform names _refresh pushes, so anything here that the
	# shader does not declare is a silent no-op — the exact bug class that killed `outline_thickness`.
	var uniforms := _shader_uniform_names()
	assert_true(uniforms.size() > 0, "the ink shader must declare uniforms (empty = the source failed to read)")
	var ink = load(INK_PATH).new()  # no add_child -> _ready never runs
	var params: Dictionary = ink._params(1.0)
	for key in params:
		if key == "apply":
			continue  # our own control flag, deliberately not a uniform
		assert_true(uniforms.has(String(key)),
			"_params pushes '%s', which ink_outline.gdshader does not declare — a silent no-op" % key)
	ink.free()

## Shared by the two literal-default guards below — the rule applies to EVERY shader in this pass, not
## just the ink one, because a failed compile is equally silent whichever file causes it.
func _assert_literal_uniform_defaults(path: String) -> void:
	var decl := RegEx.new()
	decl.compile("(?m)^\\s*uniform\\s+\\w+\\s+(\\w+)[^=\\n]*=\\s*([^;]+);")
	# A BINARY operator always follows a digit or a closing paren; a leading `-` (a negative literal)
	# never does, so a signed default is not a false positive.
	var arith := RegEx.new()
	arith.compile("[\\d\\)]\\s*[/*+\\-]")
	var checked := 0
	for m in decl.search_all(_read(path)):
		checked += 1
		assert_null(arith.search(m.get_string(2)),
			"%s: uniform '%s' has arithmetic in its default (`%s`) — Godot will not fold it, and the WHOLE shader fails to compile. Write the literal, note the maths in a comment."
				% [path, m.get_string(1), m.get_string(2).strip_edges()])
	assert_gt(checked, 0, "%s: found no uniform defaults to check — the declaration regex has drifted" % path)

func test_uniform_defaults_are_literal_constants() -> void:
	# THE WHITE-PANEL GUARD, and the nastiest failure mode this file has. Godot's shader compiler does
	# NOT constant-fold a uniform initializer: `uniform vec2 mask_texel = vec2(1.0 / 792.0, 1.0 / 444.0)`
	# is "Expected constant expression after '='" and fails the WHOLE shader. A failed spatial shader
	# draws the ink quad with a fallback material at its REAL 1 m size — a white panel pinned in front of
	# the camera, no ink anywhere in the frame, and the Options slider apparently doing nothing. It
	# shipped exactly like that once.
	#
	# Nothing else in this suite can catch it: `--headless` runs a DUMMY rasterizer that never compiles a
	# shader at all, so a broken .gdshader load()s perfectly clean and every other test here passes. The
	# only headless guard available is reading the source, so this is it — keep uniform defaults literal
	# and put the arithmetic in a trailing comment (see mask_texel).
	_assert_literal_uniform_defaults(SHADER_PATH)

func test_resolve_shader_uniform_defaults_are_literal_constants() -> void:
	# Same white-panel guard, for the mask's resolve pass. A failure here is even quieter than in the ink
	# shader: the resolve quad lives inside a SubViewport nobody ever looks at, so a fallback material
	# there shows up only as actors mysteriously going back to a doubled outline.
	_assert_literal_uniform_defaults(RESOLVE_SHADER_PATH)

func test_the_intensity_dial_reaches_the_pushed_line_uniforms() -> void:
	# The two uniforms the player's dial governs must both MOVE in the pushed set when the dial moves, or the
	# Options slider would change a value that never reaches the shader.
	var ink = load(INK_PATH).new()
	var full: Dictionary = ink._params(1.0)
	var half: Dictionary = ink._params(0.5)
	assert_true(full.has("ink_opacity") and full.has("width_px"), "the live line opacity and width must be pushed")
	assert_lt(float(half["ink_opacity"]), float(full["ink_opacity"]),
		"a lower dial must push a fainter line - the slider has to reach the shader's opacity")
	assert_lt(float(half["width_px"]), float(full["width_px"]),
		"a lower dial must push a thinner line - the slider has to reach the shader's width")
	ink.free()

# ---------------------------------------------------------------------------------------------------
# ink_params — the pure intensity mapping (the ps1_applier.warp_params shape)
# ---------------------------------------------------------------------------------------------------

func test_full_intensity_reproduces_the_authored_look() -> void:
	var p: Dictionary = InkOutlineScript.ink_params(1.0, 2.0, 1.0)
	assert_true(p["apply"], "100% intensity draws")
	assert_almost_eq(float(p["ink_opacity"]), 1.0, 0.0001, "100% must be exactly the authored opacity")
	assert_almost_eq(float(p["width_px"]), 2.0, 0.0001, "100% must be exactly the authored width")

func test_zero_intensity_does_not_draw() -> void:
	var p: Dictionary = InkOutlineScript.ink_params(1.0, 2.0, 0.0)
	assert_false(p["apply"], "0% must report 'do not draw' so _refresh can hide the quad entirely")

func test_partial_intensity_fades_and_thins() -> void:
	# Opacity alone would leave a grey band that the posterise downstream turns muddy; the width taper
	# keeps the half-strength line a thin BLACK line instead. Width tapers to half, never to nothing.
	var p: Dictionary = InkOutlineScript.ink_params(1.0, 2.0, 0.5)
	assert_almost_eq(float(p["ink_opacity"]), 0.5, 0.0001, "opacity scales linearly with the dial")
	assert_almost_eq(float(p["width_px"]), 1.5, 0.0001, "width tapers over [0.5x, 1x], not to zero")
	assert_lt(float(p["width_px"]), 2.0, "a partial dial must be thinner than the authored line")
	assert_gt(float(p["width_px"]), 0.0, "a partial dial must still have a line to fade")

func test_out_of_range_intensity_is_clamped() -> void:
	var over: Dictionary = InkOutlineScript.ink_params(1.0, 2.0, 4.0)
	assert_almost_eq(float(over["ink_opacity"]), 1.0, 0.0001, "intensity above 1 must not overshoot the authored look")
	assert_almost_eq(float(over["width_px"]), 2.0, 0.0001, "intensity above 1 must not fatten the line")
	var under: Dictionary = InkOutlineScript.ink_params(1.0, 2.0, -3.0)
	assert_false(under["apply"], "a negative intensity reads as off, not as an inverted line")

func test_authored_opacity_below_one_is_respected() -> void:
	# The dial SCALES the authored value, it does not replace it: a designer who wants a soft 40% ink
	# must not get a hard line back just because the player's slider is at 100%.
	var p: Dictionary = InkOutlineScript.ink_params(0.4, 2.0, 1.0)
	assert_almost_eq(float(p["ink_opacity"]), 0.4, 0.0001, "the authored opacity is the ceiling the dial scales")

# ---------------------------------------------------------------------------------------------------
# Scene wiring + the cross-system contract the effect rests on
# ---------------------------------------------------------------------------------------------------

func test_camera_rig_carries_the_ink_pass_on_the_camera() -> void:
	# It must hang off the CAMERA, not the rig root: the pass edge-detects the depth/normal buffers of
	# whatever camera renders it, and the mask camera mirrors that camera's pose for the exclusion.
	# (No pin on ViewModelCamera.enabled any more: since the view model is EXCLUDED from the ink via
	# its render layer, that switch no longer affects this pass either way.)
	var rig := _read(RIG_PATH)
	assert_true(rig.contains("res://scripts/effects/ink_outline.gd"),
		"camera_rig.tscn must reference the ink outline script")
	assert_true(rig.contains('[node name="InkOutline" type="MeshInstance3D" parent="ScreenShake/Camera3D"]'),
		"the ink pass must be a child of ScreenShake/Camera3D — the camera whose frame it inks")

func test_fog_extinction_is_pushed_scaled_by_fog_match() -> void:
	# The fog fix: the level's fog density (read off the live WorldEnvironment into _fog_sigma) rides
	# into the shader as fog_extinction, scaled by the designer's fog_match knob. Without this the ink
	# draws crisp black lines on geometry the fog has already swallowed — the shipped-then-reported bug.
	var ink = load(INK_PATH).new()
	ink._fog_sigma = 0.05  # the engine-default volumetric density the levels actually run
	ink.fog_match = 2.0
	var params: Dictionary = ink._params(1.0)
	assert_almost_eq(float(params["fog_extinction"]), 0.1, 0.0001,
		"fog_extinction must be the level's fog density x fog_match")
	ink.free()

func test_fog_sigma_reads_zero_off_tree() -> void:
	# A bare harness (or a scene with no WorldEnvironment) must degrade to UNFOGGED ink, not crash the
	# group lookup — _read_fog_sigma guards is_inside_tree first.
	var ink = load(INK_PATH).new()
	assert_almost_eq(ink._read_fog_sigma(), 0.0, 0.0001, "off-tree there is no environment — no fog term")
	var params: Dictionary = ink._params(1.0)
	assert_almost_eq(float(params["fog_extinction"]), 0.0, 0.0001,
		"with no environment the pushed extinction is 0 (full ink at all depths, window fade still applies)")
	ink.free()

# ---------------------------------------------------------------------------------------------------
# Actor exclusion — the hull owns the actors, the ink owns the world, and the two never stack
# ---------------------------------------------------------------------------------------------------
# Playtest verdict: actors looked right with their hull rim ALONE, and the ink pass double-lined them —
# an actor's opaque BODY is a depth discontinuity like any other, so the edge detect draws a line
# straddling its silhouette, which lands half on the hull's rim ring and half on the world. (The hull
# itself writes no depth at all: it is a transparent-pass material. This comment used to say the
# opposite.) The fix is per-pixel exclusion: everything hull-outlined ALSO renders on
# ACTOR_INK_MASK_LAYER, InkOutline renders that layer into a mask viewport, and the shader discards
# covered pixels. The stamp rides the overlay walks so swaps/rebuilds re-apply it — these tests pin both
# ends of that.

func test_mask_layer_is_reserved_and_disjoint() -> void:
	var bit: int = InkOutlineScript.ACTOR_INK_MASK_LAYER
	assert_true(bit > 0 and (bit & (bit - 1)) == 0,
		"the actor mask must be exactly ONE render bit - it is OR-ed onto actor meshes and culled on by itself")
	assert_eq(bit & 0b11, 0, "the mask bit must not be the world (1) or misc (2) layer every level mesh already carries")
	var default_cam := Camera3D.new()
	assert_true((default_cam.cull_mask & bit) != 0,
		"an ordinary camera's default cull_mask must include the mask bit, so stamping it never changes what the player sees")
	default_cam.free()
	assert_eq(InkOutlineScript.ACTOR_INK_MASK_LAYER & ViewModelCamera.VIEW_MODEL_LAYER, 0,
		"the mask layer must not collide with the view-model layer (the mask camera culls BOTH, as distinct bits)")

func test_shader_declares_the_actor_mask_uniforms() -> void:
	# use_actor_mask is covered by the generic drift guard (it rides _params); the sampler is bound
	# directly (a texture is identity, not a tunable), so its declaration needs an explicit pin.
	var uniforms := _shader_uniform_names()
	assert_true(uniforms.has("actor_mask"), "ink_outline.gdshader must declare the actor_mask sampler")
	assert_true(uniforms.has("use_actor_mask"), "ink_outline.gdshader must declare the use_actor_mask gate")

func test_params_disable_mask_until_the_pass_exists() -> void:
	# Off-tree the deferred mask build never ran — the shader must not consult an unbound sampler.
	var ink = load(INK_PATH).new()
	var params: Dictionary = ink._params(1.0)
	assert_false(bool(params["use_actor_mask"]),
		"use_actor_mask must push false while the mask viewport does not exist")
	ink.free()

func test_character_overlay_walk_stamps_the_mask_layer() -> void:
	# The whole-body seam: every path that dresses a body (outline setup, provoke recolour, rebuild)
	# funnels through _apply_overlay_to_meshes, so stamping there re-covers swapped bodies for free.
	var body := Node3D.new()
	var mi := MeshInstance3D.new()
	body.add_child(mi)
	var ch = load("res://scripts/player/character.gd").new()  # off-tree: _ready never runs
	ch.mesh = body
	ch._apply_overlay_to_meshes(null)
	assert_true((mi.layers & InkOutlineScript.ACTOR_INK_MASK_LAYER) != 0,
		"_apply_overlay_to_meshes must register body meshes with the ink actor mask")
	assert_true((mi.layers & 1) != 0, "the stamp is an OR — the mesh must keep its original layers")
	ch.free()
	body.free()

func test_throwable_overlay_chain_stamps_the_mask_layer() -> void:
	var t = load("res://scripts/components/Throwable.gd").new()  # off-tree: _ready never runs
	var mi := MeshInstance3D.new()
	t.add_child(mi)
	t._setup_overlay_chain()
	assert_true((mi.layers & InkOutlineScript.ACTOR_INK_MASK_LAYER) != 0,
		"_setup_overlay_chain must register prop meshes with the ink actor mask")
	t.free()

# --- The fifth stamper: BodyModelSwap.actor_outline (2026-08-15) ------------------------------------
# Added for the PLAYER'S OWN first-person body, which sat outside this contract entirely: Character's walk
# is scoped to `mesh`, and the Player's `mesh` is the GunMesh, so the legs/torso/body-arms rig — a sibling
# subtree childed straight to the Player — was never reached by any of the four walks above. It wore no
# hull and carried no mask bit, so the ink pass edge-detected the player's own chest like a wall while
# every NPC beside them wore a rim. ⭐The rim and the bit are ONE operation here, which is why this lives
# on the rig instead of in a caller: BodyModelSwap re-instances every part on any model reassignment and
# RESETS their layers, so a stamp applied from outside is silently lost on the next appearance swap.

func test_body_swap_actor_outline_stamps_the_mask_layer_and_the_ring() -> void:
	var swap := BodyModelSwap.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.layers = 1
	swap._body = mi          # stand in for an instanced part, so character_parts() reports it
	swap.add_child(mi)       # (off-tree: _ready never runs, so nothing rebuilds over the top of it)
	swap.actor_outline = true
	assert_true((mi.layers & InkOutlineScript.ACTOR_INK_MASK_LAYER) != 0,
		"actor_outline must register the rig's parts with the ink actor mask")
	assert_true((mi.layers & 1) != 0, "the stamp is an OR - the mesh must keep its original layers")
	var dup := mi.get_node_or_null(InkOutline.TINT_DUP_NAME) as MeshInstance3D
	assert_not_null(dup,
		"...and it must stamp the outline RING in the same operation - a masked mesh with no ring has NO outline at all")
	assert_eq(InkOutline.tint_base_id(mi), InkOutline.TINT_ID_NEUTRAL,
		"a rig at world depth wears the neutral black ring, the same one an NPC bystander wears")
	swap.free()

func test_body_swap_on_the_view_model_layer_wears_the_view_model_id() -> void:
	# The FP carry-hands rig is forced onto ViewModelCamera.VIEW_MODEL_LAYER, so its outline must be the
	# same id the WEAPON in the other hand wears - one LUT slot, one knob, no way for the two halves of a
	# first-person frame to drift apart.
	var swap := BodyModelSwap.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	swap._body = mi
	swap.add_child(mi)
	swap.view_model_layer = ViewModelCamera.VIEW_MODEL_LAYER
	swap.actor_outline = true
	assert_eq(InkOutline.tint_base_id(mi), InkOutline.TINT_ID_VIEW_MODEL,
		"a rig on the view-model layer is first-person gear - it takes TINT_ID_VIEW_MODEL, not the world-depth neutral")
	swap.free()

func test_body_swap_actor_outline_strips_what_it_owns_and_nothing_else() -> void:
	# The @tool half: un-ticking the box has to visibly remove the outline. It may only clear a duplicate
	# whose BASE ID is the one it stamps - the successor to the old bms_actor_rim meta - never one another
	# system owns.
	var swap := BodyModelSwap.new()
	var mine := MeshInstance3D.new()
	mine.mesh = BoxMesh.new()
	swap._body = mine
	swap.add_child(mine)
	swap.actor_outline = true
	swap.actor_outline = false
	assert_eq(mine.layers & InkOutlineScript.ACTOR_INK_MASK_LAYER, 0,
		"turning actor_outline off must give the mask bit back")
	assert_eq(InkOutline.tint_base_id(mine), InkOutline.TINT_ID_NONE,
		"...and drop the ring it stamped")
	# Somebody else's ring (an NPC disposition id, a prop id) must survive the same strip.
	InkOutline.apply_tint_mesh(mine, InkOutline.TINT_ID_HOSTILE)
	swap.actor_outline = false
	assert_eq(InkOutline.tint_base_id(mine), InkOutline.TINT_ID_HOSTILE,
		"the strip must leave an outline it does not own alone - it keys on the base ID, not on the presence of a duplicate")
	swap.free()

func test_body_swap_outline_goes_with_the_part_it_wraps() -> void:
	# An outline that stays while its geometry dithers out leaves a solid black silhouette of your own chest
	# hanging under the camera through the whole crouch hide and look-down fade - strictly worse than either
	# extreme. The hull could FADE with the part (its alpha was a uniform); the ring SWITCHES at the
	# midpoint, because the tint buffer's alpha channel is coverage and there is no per-instance opacity.
	var swap := BodyModelSwap.new()
	swap.actor_outline = true
	swap.body_transparency = 0.0
	assert_almost_eq(swap._outline_solid_for("torso"), 1.0, 0.0001, "a solid chest reads fully solid")
	swap.body_transparency = 1.0
	assert_almost_eq(swap._outline_solid_for("torso"), 0.0, 0.0001,
		"a fully dissolved chest must take its outline with it")
	assert_almost_eq(swap._outline_solid_for("leg_l"), 1.0, 0.0001,
		"...without touching the legs, which have no fade channel of their own")
	swap.arm_transparency = 1.0
	assert_almost_eq(swap._outline_solid_for("arm_l"), 0.0, 0.0001,
		"the arms follow arm_transparency, their own third curve (they also hide when the view model owns your hands)")
	# And the switch actually reaches the duplicate.
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	swap._body = mi
	swap.add_child(mi)
	swap.body_transparency = 0.0
	swap.actor_outline = true
	var dup := mi.get_node_or_null(InkOutline.TINT_DUP_NAME) as MeshInstance3D
	assert_not_null(dup, "the torso must carry a ring to switch off")
	if dup != null:
		assert_true(dup.visible, "a solid chest shows its outline")
		swap.body_transparency = 1.0
		assert_false(dup.visible, "a dissolved chest hides it - InkOutline.set_tint_visible, driven per part")
	swap.free()

# --- The sixth stamper: ExplosionMesh — and the first that is not an actor (2026-08-16) -------------
# The explosion / bullet-impact flash is an OPAQUE emissive sphere: its fallback StandardMaterial3D has
# transparency DISABLED (the alpha pulse only bites on a transparent authored base like bulletmat), so it
# writes depth exactly like a wall and the edge detect ringed every blast and hit spark in black. No walk
# above could ever have reached it — an Explosion is added under the SCENE ROOT, not under any actor's
# `mesh`. ⭐The half-set failure reads DIFFERENTLY here than it does on an actor: a flash that carries the
# bit with no rim is asking for no line at all, and for something meant to read as light that is the right
# answer, not the "masked mesh with no outline" bug the player's own body had.

func test_explosion_flash_stamps_the_mask_layer() -> void:
	# Off-tree, the file's idiom: _ready stamps BEFORE its mesh-less early return and touches no autoload.
	var flash = load("res://scripts/components/explosion_mesh.gd").new()
	flash.layers = 3  # what both explosion_area .tscn files author on the flash node
	flash._ready()
	assert_true((flash.layers & InkOutlineScript.ACTOR_INK_MASK_LAYER) != 0,
		"ExplosionMesh must register the flash with the ink actor mask — a blast is light, not geometry to outline")
	assert_eq(flash.layers & 3, 3, "the stamp is an OR — the flash keeps the layers its scene authored")
	assert_false(flash.has_outline,
		"...and it defaults to no rim, so the mask leaves an explosion with no outline at all (the muzzle flash opts in)")
	flash.free()

func test_rest_outlines_are_black() -> void:
	# The at-rest look is the classic black line, and it now comes from ONE place: the ring's neutral LUT
	# slot. History guard - the NPC rim briefly shipped TRANSPARENT as a doubling dodge, which regressed
	# the actor look and must not come back in the LUT's clothing. Asserted on the PUSHED set (what the shader
	# actually receives) and as relations: rest rings match the world's own ink line, the hover out-reads them.
	var ink = load(INK_PATH).new()
	var p: Dictionary = ink._params(1.0)
	var neutral: Color = p["highlight_neutral"]
	var view_model: Color = p["highlight_view_model"]
	var hover: Color = p["highlight_hover"]
	var ink_line: Color = p["ink_color"]
	assert_gt(neutral.a, 0.0,
		"the neutral ring (ids 4 and 5 - bystanders, props, gibs, corpses) must be OPAQUE - a transparent rest ring is an actor with no outline")
	assert_gt(view_model.a, 0.0, "the view model's ring must be opaque too - it is the gun's only line")
	assert_eq(Color(neutral.r, neutral.g, neutral.b), Color(ink_line.r, ink_line.g, ink_line.b),
		"a bystander's ring must be the same colour as the world's ink line - actors read like the classic black rim")
	assert_eq(Color(view_model.r, view_model.g, view_model.b), Color(neutral.r, neutral.g, neutral.b),
		"and so is the view model's, so your gun reads like everything else")
	assert_gt(hover.get_luminance() - neutral.get_luminance(), 0.5,
		"the look-at hover must out-read the rest ring it replaces on hover by a wide luminance margin")
	ink.free()
	var data = load("res://scripts/npc/npc_data.gd").new()
	var npc = load("res://scripts/npc/npc.gd").new()  # off-tree: no _ready
	var data_rim: Color = data.outline_color
	assert_eq(data_rim, npc.outline_color,
		"NpcData.outline_color stamps NPC.outline_color (which still tints the LASER) - an archetype that leaves it alone must not retint placed NPCs")
	assert_eq(Color(data_rim.r, data_rim.g, data_rim.b), Color(ink_line.r, ink_line.g, ink_line.b),
		"...and it stays the classic black of the ink line")
	npc.free()
	data = null

# ---------------------------------------------------------------------------------------------------
# Mask COST — the exclusion is a second scene render, and it shipped once at full price
# ---------------------------------------------------------------------------------------------------
# The first build of the mask pass rendered every hull-rimmed actor and prop a second time at the
# frame's full internal resolution (a SubViewport inherits rendering/scaling_3d/scale, so it was also
# supersampling 4x) with AA, a shadow atlas and full mesh detail — for a texture whose alpha is all
# anyone reads. On a level's worth of props that roughly doubled the frame. These pin the
# cheap-by-construction contract so the frills cannot drift back in one property at a time — and, since
# the first attempt at that saving traded a visible HALO for it, pin the suppression's independence from
# the mask's resolution too.

func test_mask_renders_below_the_frame_resolution() -> void:
	# mask_size is a PURE mapping over whatever basis the caller hands it — the BASIS, not the function,
	# is presentation-dependent: _main_viewport_size feeds it the logical canvas x native_scale()
	# (792x444 in RETRO, the native window size under HIGH FIDELITY).
	var full: Vector2i = InkOutlineScript.mask_size(Vector2i(792, 444), 1.0)
	assert_eq(full, Vector2i(792, 444), "at 1.0 the mask matches the given basis exactly")
	var native: Vector2i = InkOutlineScript.mask_size(Vector2i(1920, 1080), 1.0)
	assert_eq(native, Vector2i(1920, 1080),
		"the same holds for a HIGH-FIDELITY native basis — the mapping itself carries no 792x444 assumption")
	var half: Vector2i = InkOutlineScript.mask_size(Vector2i(792, 444), 0.5)
	assert_eq(half, Vector2i(396, 222), "the shipped 0.5 renders the mask at a quarter of the pixels")

func test_mask_size_never_degenerates() -> void:
	# A one-frame degenerate window (or a hand-typed resolution) must not ask for a zero-area target.
	var tiny: Vector2i = InkOutlineScript.mask_size(Vector2i(1, 1), 0.125)
	assert_gte(tiny.x, 2, "the mask keeps a floor on width")
	assert_gte(tiny.y, 2, "the mask keeps a floor on height")
	var clamped: Vector2i = InkOutlineScript.mask_size(Vector2i(800, 400), 4.0)
	assert_eq(clamped, Vector2i(800, 400), "a resolution above 1.0 is clamped, never a supersampled mask")

func test_no_mask_resolution_reaches_the_shader() -> void:
	# THE HALO GUARD. The suppression window must be sized off width_px alone. Pushing the mask's
	# resolution into the shader is what let a previous version widen its taps to a whole mask texel:
	# at a half-resolution mask that erased world ink 3 px out from every actor, so each one sat in a
	# bare ring that did NOT shrink with distance — a far-off NPC in a void bigger than itself, and a
	# tell you could spot people by. The mask is sampled as a linear coverage field precisely so the
	# shader never needs to know how coarse it is. ⭐ TWO KINDS of "resolution-derived", and only one is
	# banned: nothing derived from the MASK's resolution or texel size may ever reach the pushed set —
	# that is the halo. The native_scale() factor _params folds into the px-unit uniforms is the OPPOSITE
	# case: it derives from the INK BUFFER (the very buffer VIEWPORT_SIZE measures) and is REQUIRED, or
	# suppression stops being sized off the line under HIGH FIDELITY. This test still passes with it
	# because native_scale is independent of mask_resolution — do not "fix" a failure here by removing
	# that factor; a failure means something mask-derived crept in.
	var ink = load(INK_PATH).new()
	ink.mask_resolution = 0.25
	var lo: Dictionary = ink._params(1.0)
	ink.mask_resolution = 1.0
	var hi: Dictionary = ink._params(1.0)
	assert_eq(lo, hi,
		"the pushed uniform set must be IDENTICAL at every mask resolution — a uniform that tracks it is a halo waiting to happen")
	ink.free()

func test_default_mask_resolution_does_not_halo() -> void:
	# 1.0 is the measured floor: the suppression band is then the ink line's own width (~1 px of the
	# 792-wide buffer) and nothing more. Lower values are a real, authorable perf trade — but a scene
	# that drops the node in untouched must get the LOOK right, because the halo is what the player
	# actually notices. (The pass's expensive part was never this: see _strip_mask_viewport.)
	# Driven through the node's own sizing path: off-tree _main_viewport_size() answers the RETRO canvas basis,
	# and an untouched node must ask the renderer for a mask exactly that size.
	var ink = load(INK_PATH).new()
	assert_eq(ink._mask_size(), ink._main_viewport_size(),
		"an untouched InkOutline must render its mask at the frame's own resolution — below it the ink stops short of actors by a visible margin")
	ink.free()

func test_actor_mask_is_sampled_as_a_coverage_field() -> void:
	# filter_nearest turns the mask into a blocky stencil whose edge lands up to a whole texel outside
	# the actor, which IS the halo at any sub-frame resolution. Linear gives the 0.5 crossing sub-texel
	# accuracy, which is the only reason the suppression can stay pinned to the line's width.
	var src := _read(SHADER_PATH)
	assert_true(src.contains("uniform sampler2D actor_mask : repeat_disable, filter_linear;"),
		"actor_mask must be sampled filter_LINEAR — nearest reintroduces the per-texel halo")

func test_mask_viewport_is_stripped_to_coverage_only() -> void:
	# Every one of these is an engine default that costs real time to render something nobody looks at.
	# The supersample is the expensive one: a SubViewport inherits rendering/scaling_3d/scale (2.0 in
	# this project), so leaving it alone renders the mask at 4x the pixels of the size asked for.
	var ink = load(INK_PATH).new()
	var vp := SubViewport.new()
	ink._strip_mask_viewport(vp)
	assert_almost_eq(vp.scaling_3d_scale, 1.0, 0.0001,
		"the mask must refuse the project's 3D supersample — 4x the pixels for an alpha test")
	assert_eq(vp.msaa_3d, Viewport.MSAA_DISABLED, "no MSAA on a coverage mask")
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED, "no screen-space AA on a coverage mask")
	assert_false(vp.use_taa, "TAA would add a motion-vector pass and a history buffer for an unseen texture")
	assert_false(vp.use_debanding, "debanding smooths gradients the mask does not have")
	assert_false(vp.use_occlusion_culling, "the occluder pass costs CPU to skip draws that are already cheap")
	assert_eq(vp.positional_shadow_atlas_size, 0,
		"shadow atlases are per-viewport; the mask camera's cull_mask cannot even see the level's lights")
	assert_gt(vp.mesh_lod_threshold, 1.0, "the mask only needs a silhouette — let it drop to coarse LODs")
	vp.free()
	ink.free()

# ---------------------------------------------------------------------------------------------------
# Actor OCCLUSION — the mask knows how far away its actors are
# ---------------------------------------------------------------------------------------------------
# The mask camera renders only actors, so nothing in that viewport can occlude them: an NPC behind a wall
# stamped its full silhouette into the mask anyway and bit that shape out of every ink line it overlapped,
# punching person-shaped holes in stair nosings and building corners with nobody visibly there. The fix
# gives the mask a DEPTH channel (actor_mask_resolve.gdshader, a quad inside the mask viewport) and the ink
# pass compares it against the depth of what the main pass actually draws. None of the RENDERING can be
# tested here — headless never compiles a shader — so these pin the contracts either side of it: the two
# shaders' shared encoding, the render layer that keeps the resolve quad off the screen, and the dilation
# that has to out-reach the widest authored rim.

func test_mask_internal_layer_is_out_of_reach_of_an_ordinary_camera() -> void:
	# ⭐ THE ONE THAT MATTERS MOST HERE. The mask SubViewport shares the main World3D, so the resolve quad
	# is registered with the MAIN scenario too — the only thing stopping the main camera drawing a
	# full-screen sheet of raw depth-encoding colour over the game is that it sits on a bit no default
	# cull_mask carries. Camera3D.cull_mask defaults to 0xFFFFF (the twenty layers the editor exposes).
	assert_eq(InkOutlineScript.MASK_INTERNAL_LAYER, 1 << 20,
		"the resolve quad's layer must be bit 21 — one ABOVE the twenty a default cull_mask carries")
	assert_eq(InkOutlineScript.MASK_INTERNAL_LAYER & 0xFFFFF, 0,
		"a default Camera3D.cull_mask (0xFFFFF) must not include the resolve quad's layer, or it paints over the frame")
	assert_eq(InkOutlineScript.MASK_INTERNAL_LAYER & InkOutlineScript.ACTOR_INK_MASK_LAYER, 0,
		"the resolve layer and the actor mask layer must be distinct bits — the mask camera culls both")
	assert_eq(InkOutlineScript.MASK_INTERNAL_LAYER & ViewModelCamera.VIEW_MODEL_LAYER, 0,
		"the resolve layer must not collide with the view-model layer either")

func test_both_shaders_encode_depth_identically() -> void:
	# THE DRIFT GUARD FOR THE ENCODING. One shader writes the value, the other compares against it; if the
	# two copies of encode_actor_depth ever diverge, every comparison silently answers wrongly and actors
	# start flickering between a doubled outline and a halo. Compared as SOURCE TEXT because that is the
	# only thing available headless (see this file's header).
	var fn := RegEx.new()
	fn.compile("(?s)float encode_actor_depth\\(([^)]*)\\)\\s*\\{(.*?)\\n\\}")
	var ink := fn.search(_read(SHADER_PATH))
	var resolve := fn.search(_read(RESOLVE_SHADER_PATH))
	assert_not_null(ink, "ink_outline.gdshader must define encode_actor_depth")
	assert_not_null(resolve, "actor_mask_resolve.gdshader must define encode_actor_depth")
	if ink == null or resolve == null:
		return
	assert_eq(ink.get_string(1).strip_edges(), resolve.get_string(1).strip_edges(),
		"the two encode_actor_depth signatures must match exactly")
	assert_eq(ink.get_string(2).strip_edges(), resolve.get_string(2).strip_edges(),
		"the two encode_actor_depth BODIES must match exactly — one encodes what the other decodes")

func test_the_ink_shader_searches_outward_for_unplaceable_coverage() -> void:
	# ⭐⭐ THE ONE THAT KILLED THE "O SHAPE". Any masked pixel with COVERAGE but no DEPTH falls into the
	# "cannot vouch -> keep suppressing" branch, so a hidden actor punches an OUTLINE of itself through the
	# world's lines instead of a solid hole. The historical source was the inverted hull (a transparent-pass
	# material that wrote no depth: 23 px of mask alpha against 19 px of mask depth on a real box). That
	# shader is deleted and the ring's duplicates are opaque, but the same shape still arises from anything
	# the resolve pass cannot place - a prop faded through GeometryInstance3D.transparency, a coarse-LOD
	# silhouette, an actor at the edge of the encoding window - so the search stays.
	# The search MUST live in the ink shader, not the resolve pass: the resolve pass can only widen the
	# mask's depth by widening its ALPHA, and the mask's alpha is coverage, and coverage is suppressed ink
	# - so repairing the ring there buys a bare halo around every VISIBLE actor instead. Searching here
	# claims no extra pixels.
	var src := _read(SHADER_PATH)
	assert_true(src.contains("float searched_depth("),
		"ink_outline.gdshader must search outward for unplaceable coverage, or hidden actors keep a ring-shaped halo")
	assert_true(_shader_uniform_names().has("mask_rim_search_px"),
		"the search radius must be a uniform the script pushes, not a baked-in constant")
	# And the resolve pass must NOT have grown its own spreading back.
	var resolve := _read(RESOLVE_SHADER_PATH)
	assert_false(resolve.contains("dilate_px"),
		"actor_mask_resolve.gdshader must not spread depth outward - it can only do so by widening COVERAGE, which is a halo")

func test_the_view_model_wears_the_ring_and_only_the_ring() -> void:
	# ⭐⭐ THE VIEW MODEL HAS EXACTLY ONE OUTLINE, AND THIS IS IT. The gun draws on the view-model layer, the
	# mask camera culls that layer, and the ink shader DISCARDS covered pixels - so the world's ink never
	# touches the weapon. Which means the ring GunVisuals stamps is the gun's only line: miss a mesh and it
	# has none at all. That failure has form here - from 2026-06-03 to 2026-08-18 the gun's inverted hull
	# shipped at outline_width 0.02, a metres-era leftover that measured FIVE pixels on a whole pistol, and
	# nobody noticed for two months because there was nothing to compare it against.
	# Driven through GunVisuals.dress on a stand-in gun subtree: a receiver with a nested part, a modelled laser
	# sight (an outline_skip_name_hints match) and the Muzzle subtree whose flash stamps its own ring.
	var visuals = load("res://scripts/effects/gun_visuals.gd").new()   # off-tree: _ready never runs (no rim material)
	var rig := Node3D.new()
	var receiver := _named_box_mesh("Receiver")
	rig.add_child(receiver)
	var slide := _named_box_mesh("Slide")
	receiver.add_child(slide)
	var laser := _named_box_mesh("LaserSight")
	receiver.add_child(laser)
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	rig.add_child(muzzle)
	var muzzle_flash := _named_box_mesh("Flash")
	muzzle.add_child(muzzle_flash)
	visuals.dress(rig)
	assert_eq(InkOutline.tint_base_id(receiver), InkOutline.TINT_ID_VIEW_MODEL,
		"GunVisuals.dress must stamp the view-model outline id on every gun mesh - it is the weapon's only line")
	assert_eq(InkOutline.tint_base_id(slide), InkOutline.TINT_ID_VIEW_MODEL,
		"...nested parts included - a missed submesh is a piece of the gun with no line at all")
	assert_null(receiver.material_overlay,
		"the inverted hull must stay retired on the view model - a second outline would double the line")
	assert_eq(InkOutline.tint_base_id(laser), InkOutline.TINT_ID_NONE,
		"a modelled laser sight (outline_skip_name_hints) must stay un-ringed - it reads as a see-through emitter")
	assert_eq(InkOutline.tint_base_id(muzzle_flash), InkOutline.TINT_ID_NONE,
		"the Muzzle subtree must be skipped - its flash stamps its own ring, and two ids in one silhouette z-fight")
	visuals.dress(rig)  # a re-dress (every model swap runs one) must re-stamp, never stack
	var dups := 0
	for c in receiver.get_children():
		if c.has_meta(InkOutline.TINT_DUP_META):
			dups += 1
	assert_eq(dups, 1, "re-dressing the gun must keep ONE ring per mesh")
	assert_false(&"outline_width" in visuals,
		"GunVisuals must expose no per-weapon width - a ring is a constant PIXEL width set once on InkOutline")
	rig.free()
	visuals.free()

func _named_box_mesh(node_name: String) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = node_name
	m.mesh = BoxMesh.new()
	return m

func test_the_view_model_ring_is_exempt_from_the_occlusion_test() -> void:
	# The main camera does NOT draw the gun (ViewModelCamera strips VIEW_MODEL_LAYER from its cull_mask and
	# composites its own pass over the frame), so the scene depth behind the weapon is whatever is BEHIND
	# it. Walk up to a wall and the ordinary "is this ring's owner occluded?" test would call the gun hidden
	# and blink its outline off while the gun is plainly still drawn on top.
	var src := _read(SHADER_PATH)
	assert_true(src.contains("bool depth_exempt = (id == %d);" % InkOutlineScript.TINT_ID_VIEW_MODEL),
		"the ring's occlusion compare must exempt the view-model id, or the weapon loses its outline against every near wall")
	assert_true(src.contains("if (depth_exempt || !(e_scene - best_e > mask_occlusion_bias))"),
		"...and the exemption must gate the compare itself, not merely exist")

func test_the_view_model_pass_and_the_tint_pass_share_one_projection() -> void:
	# ⭐ The tint camera clones the MAIN camera; ViewModelCamera renders the gun at `main fov + fov_offset`.
	# They line up ONLY while that offset is zero. Anything else draws the weapon at one FOV and its ring at
	# another, and the line slides off the silhouette with no error anywhere.
	# Driven: a default ViewModelCamera syncs its gun camera off a main camera at a non-default FOV, and the gun
	# pass must come out at exactly the FOV the tint camera copies (the main camera's own).
	var main_cam := Camera3D.new()
	main_cam.fov = 63.0
	add_child_autofree(main_cam)
	var gun_cam := Camera3D.new()
	add_child_autofree(gun_cam)
	var vm := ViewModelCamera.new()
	vm._main_camera = main_cam
	vm._gun_camera = gun_cam
	vm._sync_gun_camera()
	assert_almost_eq(gun_cam.fov, main_cam.fov, 0.0001,
		"a default ViewModelCamera must render the gun at the MAIN camera's FOV - the ring pass clones that camera, so any offset slides the weapon's line off its silhouette")
	vm.free()

func test_depth_is_packed_and_unpacked_across_the_same_two_channels() -> void:
	# ⭐⭐ The depth is a 16-bit value split over two 8-bit colour channels — G coarse, R fine — because one
	# channel spends a step every ~3% of the distance, and that alone meant an NPC had to stand a full
	# METRE behind a wall at 6 m before the ink noticed (measured; 0.5 m went undetected). The pack and the
	# unpack live in different files and MUST agree: swap the two channels, or change the 255 on one side
	# only, and every comparison silently answers with a garbage depth. Nothing else can catch that —
	# headless never compiles a shader, and a wrong depth looks like an intermittent halo, not an error.
	var resolve := _read(RESOLVE_SHADER_PATH)
	assert_true(resolve.contains("floor(e * 255.0) / 255.0"),
		"the resolve pass must put the COARSE byte in its own channel, exactly representable so it round-trips whole")
	assert_true(resolve.contains("fract(e * 255.0)"),
		"the resolve pass must put the remainder in the FINE channel")
	assert_true(resolve.contains("ALBEDO = vec3(to_target(fine), to_target(coarse), 1.0)"),
		"the pack order is R = fine, G = coarse — the ink shader's decode assumes exactly this")
	assert_true(_read(SHADER_PATH).contains("(m.g + m.r / 255.0)"),
		"the ink shader must decode G + R/255 — the mirror of the resolve pass's split")

func test_shader_declares_the_occlusion_uniforms() -> void:
	var uniforms := _shader_uniform_names()
	assert_true(uniforms.has("actor_mask_data"),
		"ink_outline.gdshader must declare the second sampler it reads the mask's depth channels through")
	assert_true(uniforms.has("use_mask_occlusion"), "the occlusion test must be gateable from the script")

func test_mask_depth_is_sampled_nearest_not_linear() -> void:
	# The coverage sampler is filter_LINEAR on purpose (it is a coverage field). The DEPTH sampler must not
	# be: linear blends an actor's depth with the empty far value across its own silhouette and invents a
	# "farther" actor at every edge, which reads as occluded and puts the ink line straight back onto the
	# rim — the doubled outline, reintroduced at exactly the pixels that matter most.
	var src := _read(SHADER_PATH)
	assert_true(src.contains("uniform sampler2D actor_mask_data : repeat_disable, filter_nearest;"),
		"actor_mask_data must be sampled filter_NEAREST — linear interpolates depth across silhouettes")

func test_occlusion_is_pushed_and_can_be_switched_off() -> void:
	# The escape hatch: occlusion_aware_mask off must restore the pre-fix behaviour (every masked actor
	# suppresses ink whether or not it can be seen), and the encoding window must ride along so the shader
	# never falls back on its own literal defaults while the resolve pass uses the script's.
	var ink = load(INK_PATH).new()
	var on: Dictionary = ink._params(1.0)
	assert_true(bool(on["use_mask_occlusion"]), "the occlusion test ships ON")
	assert_almost_eq(float(on["mask_depth_near"]), InkOutlineScript.MASK_DEPTH_NEAR, 0.0001,
		"the encoding window must be pushed from the same constant the resolve material gets")
	assert_almost_eq(float(on["mask_depth_far"]), InkOutlineScript.MASK_DEPTH_FAR, 0.0001,
		"the encoding window must be pushed from the same constant the resolve material gets")
	assert_gt(float(on["mask_occlusion_bias"]), 0.0,
		"a zero bias would judge quantisation noise as occlusion and flicker actors' outlines")
	ink.occlusion_aware_mask = false
	var off: Dictionary = ink._params(1.0)
	assert_false(bool(off["use_mask_occlusion"]),
		"occlusion_aware_mask off must reach the shader — it is the A/B and the escape hatch")
	ink.free()

func test_mask_environment_pins_the_linear_tonemapper() -> void:
	# ⭐ The mask's depth channel is a NUMBER encoded into an 8-bit sRGB colour target, and the resolve
	# shader pre-compensates for exactly one transfer curve: LINEAR tonemap at exposure 1 / white 1, then
	# Godot's linear->sRGB target write. A filmic curve, a different exposure, glow or the colour
	# adjustments would re-grade that number, and the failure is silent.
	var ink = load(INK_PATH).new()
	var env: Environment = ink._build_mask_environment()
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_LINEAR,
		"the mask camera must tonemap LINEARLY or the encoded depth is re-graded on the way into the texture")
	assert_almost_eq(env.tonemap_exposure, 1.0, 0.0001, "exposure must be identity for the same reason")
	assert_almost_eq(env.tonemap_white, 1.0, 0.0001, "white must be identity for the same reason")
	assert_false(env.glow_enabled, "glow would smear the encoded channels across neighbouring pixels")
	assert_false(env.adjustment_enabled, "colour adjustments would re-grade the encoded depth")
	assert_eq(env.background_mode, Environment.BG_CLEAR_COLOR,
		"a Sky background still draws under transparent_bg (godot#84930) and would stamp alpha over the whole mask")
	ink.free()

func test_settings_exposes_the_live_intensity_the_pass_polls() -> void:
	# InkOutline reads this by NAME every frame via Settings.get(&"ink_outline_intensity"); a rename on
	# the Settings side degrades to "always full strength" with no error anywhere. Driven through the pass's own
	# poll with the real autoload wired the way _ready wires it; the raw field write (never the setter) keeps the
	# change session-local, because set_ink_outline_intensity() would save to the developer's real settings.cfg.
	var ink = load(INK_PATH).new()
	ink._settings = Settings
	var prev: float = Settings.ink_outline_intensity
	Settings.ink_outline_intensity = 0.25
	assert_almost_eq(ink._intensity(), 0.25, 0.0001,
		"InkOutline must read the player's live ink_outline_intensity - a missed poll pins the line at full strength")
	Settings.ink_outline_intensity = 0.0
	assert_false(bool(ink._params(ink._intensity())["apply"]),
		"a slider at 0% must reach the pass as 'do not draw the world ink'")
	Settings.ink_outline_intensity = prev
	ink.free()
	assert_true(Settings.has_method(&"set_ink_outline_intensity"),
		"Settings must expose the setter the Options row binds to")

# ---------------------------------------------------------------------------------------------------
# Seam merge — level geometry built from several pieces inks as ONE solid, not as its parts
# ---------------------------------------------------------------------------------------------------
# The user's sketch: two boxes side by side should draw the L, not the shared boundary. Flush and
# interpenetrating joins already merged (a screen-space pass cannot see an interior face — measured on a
# synthetic scene and on the shipped map's flush floor/roof brush joins), but a box a couple of
# centimetres out of line leaves a sub-pixel sliver of perpendicular face along the join, and the CREASE
# term inked that sliver as a corner — one surface split by a faint dotted line. The fix is
# `crease_min_feature_px`: the crease is re-measured on two wider crosses and the WEAKER answer, as a
# RATIO of the narrow one, scales the crease down, so a normal change that lives only in a sliver stops
# drawing while every corner wide enough to be a corner keeps its line. `concave_crease_strength` is the
# companion look dial: on a level built from boxes every piece junction is a CONCAVE crease, so it is the
# knob for how much the pieces read as one solid. Headless can never compile the shader, so what these
# pin is the script->shader seam and the rules the shader source must keep, not the pixels.

func test_seam_merge_radius_is_pushed_and_ships_on() -> void:
	var ink = load(INK_PATH).new()
	var params: Dictionary = ink._params(1.0)
	assert_true(params.has("crease_min_feature_px"),
		"crease_min_feature_px must ride _params, or the seam merge is a knob wired to nothing")
	assert_true(_shader_uniform_names().has("crease_min_feature_px"),
		"ink_outline.gdshader must declare crease_min_feature_px — the generic drift guard catches a rename, this catches a removal")
	assert_gt(float(params["crease_min_feature_px"]), 0.0,
		"the seam merge ships ON: with it off, every hand-authored blockout join a few cm out of line grows a crawling seam line")
	# 0 is the documented OFF position and must reach the shader as exactly 0 (the shader gates on > 0.0).
	ink.crease_min_feature_px = 0.0
	assert_almost_eq(float(ink._params(1.0)["crease_min_feature_px"]), 0.0, 0.0001,
		"crease_min_feature_px = 0 must be pushed as 0 — that is the shader's off switch")
	ink.free()

func test_seam_merge_default_clears_the_measured_floor() -> void:
	# Measured on the level: with the confirming taps inside the narrow cross's own footprint (width_px/2
	# either side) the wide pass is only a second sampling of the same edge, and reducing by it thins every
	# real crease line by a pixel — floor/wall junctions came out ragged. The shader floors the reach at
	# width_px for that reason (derivation: each cross keeps a straddling pair for the whole narrow band
	# iff reach * sin 45 >= width_px/2 * sqrt 2); the AUTHORED default must clear it too, so a designer
	# reading the Inspector sees the value that is actually in effect.
	var ink = load(INK_PATH).new()
	assert_gte(ink.crease_min_feature_px, ink.width_px,
		"the shipped crease_min_feature_px must be >= width_px (the measured floor below which it only thins real lines)")
	ink.free()

func test_seam_merge_shader_keeps_its_rules() -> void:
	# Source-text pins, because headless cannot compile the shader and each rule failed by being ALMOST
	# right: (1) ONE wide cross left the seam as a dotted trail wherever the sliver ran along a tap
	# diagonal — it takes two crosses (diagonal + axis) MIN-ed for a sliver at any orientation to be clean
	# to at least one of them; (2) the reach must be floored at width_px (see the test above); (3) the wide
	# result must scale the crease as a RATIO of the narrow one, not pass through a second absolute
	# threshold — the absolute version dimmed every shallow crease (a ramp meeting the floor, a kerb
	# chamfer) to ~22% at axis/diagonal screen angles, because an axis-aligned crease straddles both
	# narrow diagonals but only one pair of the wide axis cross; and it may only ever REMOVE (a multiply
	# by a 0..1 factor), never add.
	var src := _read(SHADER_PATH)
	assert_true(src.contains("min(diag_diff, axis_diff)"),
		"the wide confirmation must take the MIN of the diagonal and axis crosses — one cross alone leaves dotted seams")
	assert_true(src.contains("max(crease_min_feature_px, max(width_px, 0.0))"),
		"the wide reach must be floored at width_px in the shader, or a small value thins every real crease line")
	assert_true(src.contains("crease *= smoothstep(0.15, 0.4, wide_diff / max(normal_diff"),
		"the wide pass must scale the crease by the RATIO wide/narrow (a 0..1 factor) — a second absolute threshold dims shallow creases, and anything but a multiply could add lines")

func test_seam_merge_reach_does_not_follow_the_intensity_dial() -> void:
	# The knob is a screen-space FEATURE SIZE, not a line weight: the Options dial thins the line
	# (width_px x0.5..1) but must not change WHICH lines exist. The only coupling allowed is the shader's
	# floor at width_px, which the default clears (see the floor test).
	var ink = load(INK_PATH).new()
	var full: Dictionary = ink._params(1.0)
	var half: Dictionary = ink._params(0.5)
	assert_lt(float(half["width_px"]), float(full["width_px"]), "sanity: the dial thins the line")
	assert_almost_eq(float(half["crease_min_feature_px"]), float(full["crease_min_feature_px"]), 0.0001,
		"crease_min_feature_px must be pushed unscaled at every dial position — a reach that follows the dial changes which lines exist, not just how heavy they are")
	ink.free()

func test_viewport_size_is_only_read_inside_fragment() -> void:
	# VIEWPORT_SIZE is a fragment() built-in and NOT reachable from a helper function; using it there
	# fails the WHOLE shader with "Unknown identifier", which headless never notices (this project has
	# shipped exactly that once — see gdshader-headless-never-compiles). The wide-reach conversion must
	# stay inside fragment().
	# Comments are stripped first: the shader documents this very trap in a helper's header comment,
	# and a comment is not a read.
	var in_fragment := false
	var uses_before := 0
	var uses_inside := 0
	for raw_line in _read(SHADER_PATH).split("
"):
		var line: String = raw_line
		var slash := line.find("//")
		if slash >= 0:
			line = line.substr(0, slash)
		if line.contains("void fragment()"):
			in_fragment = true
		if line.contains("VIEWPORT_SIZE"):
			if in_fragment:
				uses_inside += 1
			else:
				uses_before += 1
	assert_true(in_fragment, "ink_outline.gdshader must define fragment()")
	assert_gt(uses_inside, 0, "fragment() must read VIEWPORT_SIZE (the tap offsets are pixel sizes converted to UV)")
	assert_eq(uses_before, 0,
		"every VIEWPORT_SIZE read must sit inside fragment() — %d code use(s) found before it, which fails the whole shader" % uses_before)

func test_concave_crease_strength_is_pushed_and_ships_unchanged() -> void:
	# The look dial for piece junctions. It ships at 1.0 = every junction drawn (the resting state the
	# user signed off before this knob existed); anything lower is a deliberate authoring choice.
	var ink = load(INK_PATH).new()
	var params: Dictionary = ink._params(1.0)
	assert_true(params.has("concave_crease_strength"), "concave_crease_strength must ride _params")
	assert_true(_shader_uniform_names().has("concave_crease_strength"),
		"ink_outline.gdshader must declare concave_crease_strength")
	assert_almost_eq(float(params["concave_crease_strength"]), _export_range_max(ink, "concave_crease_strength"), 0.0001,
		"concave_crease_strength ships at the TOP of its authored range (every junction drawn) — the look is unchanged until a designer dials it down")
	assert_almost_eq(float(ink._params(0.5)["concave_crease_strength"]), float(params["concave_crease_strength"]), 0.0001,
		"the junction dial is a look choice, not a line weight - the player's intensity slider must not rescale it")
	ink.concave_crease_strength = 0.0
	assert_almost_eq(float(ink._params(1.0)["concave_crease_strength"]), 0.0, 0.0001,
		"0 (convex edges and silhouettes only) must reach the shader as 0")
	# The convexity test is the standard sign of dot(dN, dP): pin that the shader reads FOLD from the
	# depth taps' positions rather than guessing from normals alone (which cannot tell the two apart).
	var src := _read(SHADER_PATH)
	assert_true(src.contains("float fold = dot(dn, dp)"),
		"concavity must be read from dot(dN, dP) — normals alone cannot separate an inside corner from an outside one")
	ink.free()

# ---------------------------------------------------------------------------------------------------
# Contact merge — the boundary between two pieces that are TOUCHING is not a silhouette
# ---------------------------------------------------------------------------------------------------
# The second half of the user's sketch, and the half the crease knobs could not reach: a flight of
# stairs is a stack of slabs, and every step drew a line, so the flight read as separately outlined
# pieces instead of one stepped solid. Measured on the porch steps: the risers are not even visible
# from a normal eye height (the raycast normal never changes, (0,1,0) both sides) — each step is a PURE
# depth discontinuity between two treads, drawn by the silhouette term, so crease_strength = 0 left
# every line intact. The rule the user gave is "not where the two actually are touching": at an edge
# pixel the two taps that found it land on two surfaces, and the 3D distance between those points is how
# far apart the pieces are along the view ray (a step gives its riser height, the sky gives the far
# plane). Below the threshold they are one solid.

func test_contact_merge_is_pushed_and_ships_on() -> void:
	var ink = load(INK_PATH).new()
	var params: Dictionary = ink._params(1.0)
	assert_true(params.has("contact_merge_m"), "contact_merge_m must ride _params")
	assert_true(_shader_uniform_names().has("contact_merge_m"),
		"ink_outline.gdshader must declare contact_merge_m")
	assert_gt(float(params["contact_merge_m"]), 0.0,
		"the contact merge ships ON: with it off every stair tread and slab-on-slab join draws its own line")
	ink.contact_merge_m = 0.0
	assert_almost_eq(float(ink._params(1.0)["contact_merge_m"]), 0.0, 0.0001,
		"contact_merge_m = 0 must be pushed as 0 — that is the shader's off switch")
	ink.free()

func test_contact_merge_clears_the_levels_authored_module() -> void:
	# The level's module is 0.5 m (stair risers, kerbs, slab thickness). Measured on the porch steps, a
	# 0.5 m riser presents a ~0.95 m gap between the two visible tread points, so the threshold has to
	# clear the module itself with margin or the flight keeps half its lines. Anything at/above 2x the
	# knob is still drawn at full strength (the smoothstep's far end), which is what keeps a real drop.
	var ink = load(INK_PATH).new()
	assert_gte(ink.contact_merge_m, 0.5,
		"contact_merge_m must clear the level's 0.5 m authored module, or stairs keep drawing per-step lines")
	assert_lte(ink.contact_merge_m, 2.0,
		"contact_merge_m past ~2 m starts merging genuinely separate things (a crate against a wall, a doorway into an alcove)")
	ink.free()

func test_contact_merge_shader_keeps_its_rules() -> void:
	# Source pins for the two things that make it safe, both of which are easy to "simplify" away:
	# (1) it must measure the diagonal THAT FOUND THE EDGE — the other diagonal can lie along the edge
	# and measure nothing, which would merge real silhouettes at some orientations; (2) it must MULTIPLY
	# the existing edge (0..1), never replace it, so it can only ever remove.
	var src := _read(SHADER_PATH)
	assert_true(src.contains("(diff_tlbr >= diff_trbl) ? p_tl : p_tr"),
		"the contact test must measure the diagonal that found the edge, not a fixed one")
	assert_true(src.contains("edge *= smoothstep(contact_merge_m, contact_merge_m * 2.0, distance(pa, pb))"),
		"the contact test must scale the existing silhouette edge by the gap (a 0..1 multiply) — it may only ever remove lines")

func test_contact_merge_can_never_erase_a_sky_silhouette() -> void:
	# The fail-safe direction: an undrawn pixel must read as ENORMOUSLY far away, so a rooftop against
	# the sky can never be merged into it. linear_depth/view_pos both answer SKY_DEPTH there, and
	# view_pos must keep that along the pixel's own ray (a zero vector would read as a 0 m gap — i.e.
	# "touching" — and would delete every silhouette against the sky).
	var src := _read(SHADER_PATH)
	assert_true(src.contains("return dir * (SKY_DEPTH / -dir.z);"),
		"view_pos must place a sky sample at SKY_DEPTH along its own ray — a zero/short vector would read as a contact and erase sky silhouettes")
	assert_true(src.contains("const float SKY_DEPTH = 1.0e6;"),
		"SKY_DEPTH must stay far enough that no contact threshold can reach it")


# --- Hull -> ink handoff (2026-08-25): distant actors are inked like world geometry -------------------------
# At a dozen pixels tall the mask renders coarser LODs whose silhouette no longer matches the main pass, so
# the per-pixel occlusion verdict sprays black fragments over distant enemies; the handoff fades suppression
# out between hull_handoff_near_m/far_m while outline.gdshader thins the rim (rim_distance_cap) over the
# same span. These pin the seam both silent-failure directions: a renamed uniform (set_shader_parameter
# drops silently) and a drifted encode mirror (the thresholds would land in the wrong depth band).

func test_hull_handoff_uniforms_exist_and_are_pushed_encoded() -> void:
	var src := _read(SHADER_PATH)
	assert_true(src.contains("uniform float hull_handoff_e_near"),
		"ink_outline.gdshader must declare hull_handoff_e_near - a push to a missing uniform is silently dropped and the handoff dies")
	assert_true(src.contains("uniform float hull_handoff_e_far"),
		"ink_outline.gdshader must declare hull_handoff_e_far")
	var ink = load("res://scripts/effects/ink_outline.gd").new()
	var p: Dictionary = ink._params(1.0)
	assert_true(p.has("hull_handoff_e_near") and p.has("hull_handoff_e_far"),
		"_params must push both handoff thresholds")
	assert_gt(float(p["hull_handoff_e_near"]), float(p["hull_handoff_e_far"]),
		"encoded depth DECREASES with distance, so the near threshold must encode HIGHER than the far one (smoothstep(far, near, e) depends on it)")
	ink.free()

func test_encode_actor_depth_mirror_matches_the_shader_contract() -> void:
	# The GDScript mirror must reproduce the shader's log encoding: near -> 1.0, far -> 0.0, monotonic
	# decreasing. The shader source is pinned to the same formula so the two cannot drift silently.
	var ink_script = load("res://scripts/effects/ink_outline.gd")
	var near: float = ink_script.MASK_DEPTH_NEAR
	var far: float = ink_script.MASK_DEPTH_FAR
	assert_almost_eq(ink_script.encode_actor_depth(near, near, far), 1.0, 0.0001,
		"the near plane must encode to 1.0")
	assert_almost_eq(ink_script.encode_actor_depth(far, near, far), 0.0, 0.0001,
		"the far plane must encode to 0.0")
	assert_gt(ink_script.encode_actor_depth(18.0, near, far), ink_script.encode_actor_depth(32.0, near, far),
		"encoding must decrease with distance (18 m encodes higher than 32 m)")
	var src := _read(SHADER_PATH)
	assert_true(src.contains("return 1.0 - clamp(log(clamp(d, lo, hi) / lo) / log(hi / lo), 0.0, 1.0);"),
		"the shader's encode_actor_depth formula moved - the GDScript mirror in ink_outline.gd must move with it IN THE SAME DIFF")

# --- Disposition tint ring (2026-08-25): the screen-space replacement for the NPC hull rim ------------------
# NPCs paint a flat depth+ID duplicate into InkOutline's tint SubViewport (ink_tint.gdshader) and the ink
# shader ring-dilates it into a constant-pixel-width colored outline. These pin the seam's silent-failure
# directions: dropped uniform pushes, and the THREE-way encode formula drifting apart.

const TINT_SHADER_PATH := "res://resources/shaders/ink_tint.gdshader"

func test_tint_ring_uniforms_exist_and_are_pushed() -> void:
	var src := _read(SHADER_PATH)
	for u in ["uniform sampler2D actor_tint", "uniform bool use_actor_tint", "uniform float highlight_width_px",
			"uniform vec4 highlight_hostile", "uniform vec4 highlight_friendly", "uniform vec4 highlight_companion",
			"uniform vec4 highlight_hover", "uniform vec4 highlight_view_model"]:
		assert_true(src.contains(u), "ink_outline.gdshader must declare '%s' - a push to a missing uniform is silently dropped" % u)
	assert_true(src.contains("filter_nearest") and src.contains("actor_tint : repeat_disable, filter_nearest"),
		"actor_tint must be filter_nearest - interpolated depth bytes or ids blended between two enemies are both meaningless")
	assert_true(src.contains("uniform float highlight_e_color_near") and src.contains("uniform float highlight_e_color_far"),
		"the close-range color-bloom window uniforms must exist (black-at-range, disposition color blooming as the actor closes)")
	var ink = load("res://scripts/effects/ink_outline.gd").new()
	var p: Dictionary = ink._params(1.0)
	for key in ["use_actor_tint", "highlight_width_px", "highlight_hostile", "highlight_friendly", "highlight_companion",
			"highlight_neutral", "highlight_hover", "highlight_view_model", "highlight_e_color_near", "highlight_e_color_far"]:
		assert_true(p.has(key), "_params must push '%s'" % key)
	assert_false(bool(p["use_actor_tint"]),
		"off-tree (no tint viewport) the ring must be gated OFF so the shader never samples an unbound buffer")
	assert_gt(float(p["highlight_e_color_near"]), float(p["highlight_e_color_far"]),
		"the bloom band must encode near HIGHER than far (the 350/400 lesson: values outside the depth window collapse equal and the smoothstep degenerates)")
	ink.free()

func test_the_id_span_is_the_same_literal_in_all_three_files() -> void:
	# ⭐⭐ The tint buffer packs its id into ONE byte as `id / SPAN`, and three files carry that number as a
	# LITERAL because a shader uniform default cannot hold arithmetic (the project's own compile rule). A
	# drift between them does not error - it re-reads every id as a different id, so hostiles paint as props
	# and the engaged band lands on nothing. It was 8 until the hull's retirement needed ids 9 and 10.
	var span: int = InkOutlineScript.TINT_ID_SPAN
	assert_eq(span, 16, "TINT_ID_SPAN is the authority; move all three together if it ever changes")
	assert_true(_read(TINT_SHADER_PATH).contains("clamp(disposition_id, 0.0, %d.0) / %d.0" % [span, span]),
		"ink_tint.gdshader must encode the id against the SAME span")
	assert_true(_read(SHADER_PATH).contains("float idf = best_id * %d.0;" % span),
		"ink_outline.gdshader must decode it against the same span")
	assert_lte(InkOutlineScript.TINT_ID_VIEW_MODEL, span,
		"no id may exceed the span - ink_tint.gdshader clamps there, so an id past it silently reads as the top one")

func test_the_hover_and_view_model_ids_do_not_bloom_or_join_the_band() -> void:
	# Ids 9 and 10 sit ABOVE the 7..8 engaged-hostile band in the same integer space, so both guards matter:
	# they must not be read as "more engaged than full red", and they must paint their LUT slot flat rather
	# than fading toward black with distance (a hover white that dimmed across a street would contradict the
	# prompt beside it, and a gun 30 cm from the lens would never leave the near end anyway).
	var src := _read(SHADER_PATH)
	var band_lo: int = InkOutlineScript.TINT_ID_HOSTILE_ENGAGED
	assert_true(src.contains("if (id >= %d && id <= %d) {" % [band_lo, band_lo + 1]),
		"the engaged band must be bounded ABOVE - an unbounded `id >= 7` swallows the hover and view-model ids")
	assert_lt(band_lo + 1, InkOutlineScript.TINT_ID_HOVER,
		"the script's id table must keep the hover id above the 7..8 band the shader bounds")
	assert_true(src.contains("float closeness = (id >= %d)" % InkOutlineScript.TINT_ID_HOVER),
		"ids 9 and 10 must pin closeness to 1 - they are not dispositions and do not bloom with distance")

func test_tint_shader_encode_matches_the_family() -> void:
	# The encode formula now lives in THREE shaders + one GDScript mirror; all four must stay identical.
	var formula := "return 1.0 - clamp(log(clamp(d, lo, hi) / lo) / log(hi / lo), 0.0, 1.0);"
	for path in [SHADER_PATH, RESOLVE_SHADER_PATH, TINT_SHADER_PATH]:
		assert_true(_read(path).contains(formula),
			"%s must carry the family encode formula verbatim - a drift moves every depth comparison" % path)
	var tint := _read(TINT_SHADER_PATH)
	assert_true(tint.contains("instance uniform float disposition_id"),
		"ink_tint.gdshader must carry the per-instance id - one shared material serves every NPC through it")
	assert_false(tint.contains("ALPHA ="),
		"ink_tint.gdshader must NEVER assign ALPHA: uses_alpha would move it to the transparent pass, dropping the depth writes that resolve overlapping enemies nearest-wins")

## An off-tree NPC (load().new(), no _ready, no add_child - the CLAUDE.md actor seam) wearing ONE BodyModelSwap
## part, with a real NpcOutline child wired the way NPC._build_components wires it and a stand-in flash material
## (NPC.setup only builds the outline once the flash overlay exists). Freeing the returned "npc" frees it all.
func _npc_outline_rig() -> Dictionary:
	var npc = load("res://scripts/npc/npc.gd").new()
	var swap := BodyModelSwap.new()
	var part := MeshInstance3D.new()
	part.mesh = BoxMesh.new()
	swap._body = part        # character_parts() reports it as the torso
	swap.add_child(part)
	npc.add_child(swap)      # _find_body_swap() finds it by duck type
	npc._flash_material = ShaderMaterial.new()
	var outline = load("res://scripts/npc/npc_outline.gd").new()
	outline.host = npc
	npc.add_child(outline)
	npc._outline = outline
	return {"npc": npc, "outline": outline, "part": part}

## The id a mesh's tint duplicate is currently PAINTING - its `disposition_id` instance uniform, the value the
## ring shader actually reads - or -1 when the mesh has no duplicate. Distinct from tint_base_id(), which reads
## the stashed base a hover borrow deliberately leaves alone.
func _painted_id(m: MeshInstance3D) -> float:
	var dup := m.get_node_or_null(InkOutline.TINT_DUP_NAME) as MeshInstance3D
	if dup == null:
		return -1.0
	var v: Variant = dup.get_instance_shader_parameter(&"disposition_id")
	return float(v) if v != null else -1.0

func test_npc_outline_maps_dispositions_to_tint_ids() -> void:
	var rig := _npc_outline_rig()
	var npc = rig["npc"]
	var outline = rig["outline"]
	var part: MeshInstance3D = rig["part"]
	for c in [[Disposition.Kind.HOSTILE, InkOutline.TINT_ID_HOSTILE, "HOSTILE"],
			[Disposition.Kind.FRIENDLY, InkOutline.TINT_ID_FRIENDLY, "FRIENDLY"],
			[Disposition.Kind.NEUTRAL, InkOutline.TINT_ID_NEUTRAL, "NEUTRAL"]]:
		npc.disposition = c[0]  # unaligned (no faction), so the standalone disposition rules
		outline.apply()
		assert_eq(_painted_id(part), float(c[1]),
			"a %s NPC's part must paint tint id %d - NEUTRAL included: with NPCs excluded from the ink, an id-less disposition leaves a bystander with no outline at all" % [c[2], c[1]])
	var leader := Node3D.new()
	npc._leader = leader  # following a leader outranks the disposition
	outline.apply()
	assert_eq(_painted_id(part), float(InkOutline.TINT_ID_COMPANION),
		"a recruited companion must paint the companion id, whatever its disposition")
	npc._leader = null
	leader.free()
	assert_true((part.layers & InkOutline.ACTOR_INK_MASK_LAYER) != 0,
		"NPC part meshes must STAY ON the ink-suppression mask - the world ink never draws on actors (user-affirmed contract); the tint RING is the NPC's only outline")
	var overlay := part.material_overlay as ShaderMaterial
	assert_true(overlay != null and overlay == outline._part_flash.get("torso", null),
		"NpcOutline.apply must dress each part with its OWN flash material - the hull rim is retired for NPCs (the confetti saga)")
	if overlay != null:
		assert_null(overlay.next_pass,
			"nothing may be chained behind the flash - a hull pass there doubles the outline and resurrects the shell confetti")
	npc.free()
	var ink_src := _read(SHADER_PATH)
	assert_true(ink_src.contains("uniform vec4 highlight_neutral"),
		"the ink shader must carry the neutral (id 4) LUT slot")
	assert_true(ink_src.contains("&& ring_a <= 0.0) {"),
		"the actor-exclusion discard must be gated on ring_a - a plain discard in the suppression band erases the only outline an NPC has ('return' is illegal in a fragment processor, so the gate IS the mechanism)")


# --- Generic tint API + the PROP crossfade (2026-08-26) ----------------------------------------------------
# InkOutline.apply_tint/clear_tint is the shared mechanism NpcOutline and Throwable both drive. A prop keeps
# its hull for close range and its ring fades IN as that hull fades OUT, closing the dead zone where a
# dropped weapon past ~16 m had no outline at all (hull faded, world ink suppressed by its mask stamp).

func test_apply_tint_builds_a_shielded_duplicate() -> void:
	var host := MeshInstance3D.new()
	host.mesh = BoxMesh.new()
	InkOutline.apply_tint(host, InkOutline.TINT_ID_PROP_REST)
	var dup := host.get_node_or_null(InkOutline.TINT_DUP_NAME) as MeshInstance3D
	assert_not_null(dup, "apply_tint must parent a tint duplicate under the mesh it mirrors")
	if dup != null:
		assert_true(dup.has_meta(InkOutline.TINT_DUP_META),
			"the duplicate MUST carry the meta - it is the ONLY thing shielding it from a dozen mesh walkers")
		assert_eq(dup.layers, InkOutline.ACTOR_TINT_LAYER,
			"the duplicate must be on the tint layer and NOTHING else, or an ordinary camera draws its raw depth bytes as stripe bands")
		assert_eq(dup.material_override, InkOutline.tint_material(),
			"every duplicate wears the ONE shared material - identity rides the per-instance uniform, never a per-mesh copy")
		assert_eq(dup.mesh, host.mesh, "the duplicate mirrors its host mesh")
	# THE SHIELD: the project's single collected walker must not hand this node to anyone.
	var seen := TalkHelpers.collect_meshes(host, null, true)
	assert_eq(seen.size(), 1, "collect_meshes must return the host mesh only - never its tint duplicate")
	# ...including when the duplicate itself is handed in as the root (the include_root asymmetry).
	assert_eq(TalkHelpers.collect_meshes(dup, null, true).size(), 0,
		"a duplicate passed AS the root must not be collected either")
	host.free()

func test_apply_tint_is_idempotent_and_clear_tint_removes() -> void:
	var host := MeshInstance3D.new()
	host.mesh = BoxMesh.new()
	InkOutline.apply_tint(host, InkOutline.TINT_ID_PROP_REST)
	InkOutline.apply_tint(host, InkOutline.TINT_ID_PROP_CLAIMED)
	var dups := 0
	for c in host.get_children():
		if c.has_meta(InkOutline.TINT_DUP_META):
			dups += 1
	assert_eq(dups, 1, "re-applying must RE-STAMP the one duplicate (get-or-create), never stack a second")
	InkOutline.clear_tint(host)
	assert_eq(host.get_node_or_null(InkOutline.TINT_DUP_NAME), null,
		"clear_tint must drop the duplicate - the removal path a disabled consumer needs (an id-0 apply never reaches it)")
	host.free()

func test_apply_tint_mirrors_skinned_meshes() -> void:
	# ⭐ REVERSED 2026-08-27. Skinned meshes used to be skipped outright ("a skin-bound duplicate needs its
	# own skeleton plumbing"), which was survivable only while the inverted hull covered for them. With the
	# hull deleted, the skinned bodies that had been leaning on it - Ragdoll's corpses, the bare Man.glb
	# fallback, three of the seven weapon view models - would have been left with NO outline at all. The
	# plumbing is two properties: copy `skin`, and re-express `skeleton` as a path from the DUPLICATE (it is
	# a child of the mesh, so the source's own relative path would resolve one level short).
	var skel := Skeleton3D.new()
	var host := MeshInstance3D.new()
	host.mesh = BoxMesh.new()
	host.skin = Skin.new()
	skel.add_child(host)
	host.skeleton = host.get_path_to(skel)
	InkOutline.apply_tint(host, InkOutline.TINT_ID_NEUTRAL)
	var dup := host.get_node_or_null(InkOutline.TINT_DUP_NAME) as MeshInstance3D
	assert_not_null(dup, "a skinned mesh must get a ring - it has no other outline left")
	if dup != null:
		assert_eq(dup.skin, host.skin, "the duplicate must share the source's Skin, or it renders in the rest pose")
		assert_eq(dup.get_node_or_null(dup.skeleton), skel,
			"the duplicate's skeleton path must resolve to the SAME Skeleton3D - copying the source's relative path lands one level short")
	skel.free()

func test_prop_ring_is_unconditional_now_the_hull_is_gone() -> void:
	# ⭐ The prop ring used to be the FAR half of a crossfade: invisible inside 8 m, where an inverted hull
	# owned the look, and fading in as that hull faded out by 16 m. The hull is deleted (2026-08-27), so a
	# distance gate on the prop branch would leave every crate, dropped weapon and claimed dog with NO
	# outline at exactly the range the player inspects it - the mirror image of the dead zone the crossfade
	# was built to close.
	var src := _read(SHADER_PATH)
	assert_true(src.contains("id >= 5 && id <= 6"),
		"the shader must still branch prop ids away from the disposition ids - props take a flat LUT colour, not the distance bloom")
	assert_false(src.contains("highlight_e_prop_near") or src.contains("highlight_e_prop_far"),
		"the prop crossfade window must be GONE - a surviving gate is a prop with no outline up close")
	assert_false(src.contains("far_gate"),
		"...and so must the gate it drove")
	var ink = load("res://scripts/effects/ink_outline.gd").new()
	var p: Dictionary = ink._params(1.0)
	assert_false(p.has("highlight_e_prop_near") or p.has("highlight_e_prop_far"),
		"_params must not push a band the shader no longer declares - a stale push is a silent no-op that reads like a live knob")
	assert_false(&"highlight_prop_near_m" in ink,
		"and the export must go with it, or a designer tunes a dial that does nothing")
	ink.free()

func test_throwable_drives_the_prop_ring_ids() -> void:
	# Driven through the real outline setters PickupRay / Claimable call, on an off-tree prop (the file's idiom).
	var t = load("res://scripts/components/Throwable.gd").new()  # off-tree: _ready never runs
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	t.add_child(mi)
	t._setup_overlay_chain()
	assert_eq(_painted_id(mi), float(InkOutline.TINT_ID_PROP_REST),
		"Throwable must stamp its rest ring - a prop's whole outline since the hull was deleted")
	assert_true((mi.layers & InkOutline.ACTOR_INK_MASK_LAYER) != 0,
		"props must STAY excluded from the world ink - the ring is their outline, ink on top would double it")
	var overlay := mi.material_overlay as ShaderMaterial
	assert_true(overlay != null and overlay.next_pass == null,
		"the overlay slot carries the damage flash alone - no inverted hull chained beside the ring (two lines on one prop is the artefact the ink pass exists to prevent)")
	t.set_outline_visible(true)
	assert_eq(_painted_id(mi), float(InkOutline.TINT_ID_HOVER),
		"hover (white) must outrank at-rest (black) - one id per mesh, so these are alternatives, not layers")
	t.set_persistent_outline(Color(0.15, 0.45, 1.0))
	assert_eq(_painted_id(mi), float(InkOutline.TINT_ID_PROP_CLAIMED),
		"claiming a prop mid-hover must repaint it CLAIMED blue")
	t.set_outline_visible(true)
	assert_eq(_painted_id(mi), float(InkOutline.TINT_ID_PROP_CLAIMED),
		"CLAIMED must outrank hover, so a claimed dog reads as yours whether or not you are aiming at it")
	t.set_outline_visible(false)
	assert_eq(_painted_id(mi), float(InkOutline.TINT_ID_PROP_CLAIMED), "...and looking away must not drop the claim either")
	t.clear_persistent_outline()
	assert_eq(_painted_id(mi), float(InkOutline.TINT_ID_PROP_REST),
		"releasing the claim must put the rest-black ring back")
	assert_false(t.get_script().get_script_constant_map().has("OUTLINE_SHADER"),
		"Throwable must not carry the inverted-hull shader const - that shader is deleted")
	t.free()

# --- The engaged-hostile band, ids 7..8 (2026-08-27) --------------------------------------------------------
# "If an enemy is targeting you, their red outline fades in no matter the distance." A hostile LOCKED ONTO
# the player (is_alerted_on_player()) stamps TINT_ID_HOSTILE_ENGAGED + mix instead of plain hostile, and the
# fraction past 7 FLOORS the close-range bloom in the ink shader — full red at any range while locked on,
# easing back to the distance rule when the lock breaks. The band is the table's one CONTINUOUS span.

func test_engaged_band_floors_the_bloom_in_the_shader() -> void:
	var src := _read(SHADER_PATH)
	assert_true(src.contains("float idf = best_id * %d.0;" % InkOutlineScript.TINT_ID_SPAN),
		"the ring decode must keep the FLOAT id - the 7..8 band is continuous, round() alone would quantise the lock-on fade to a pop (and the span is a literal in three files: see test_the_id_span_is_the_same_literal_in_all_three_files)")
	assert_true(src.contains("closeness = max(closeness, smoothstep(7.0, 7.9, idf));"),
		"the engaged fraction must FLOOR the bloom - max(), never replace (a locked enemy point-blank stays full red mid-fade), and the 7.0..7.9 smoothstep absorbs the buffer's 8-bit quantisation at both rails")
	assert_true(src.contains("(id >= 1 && id <= 4) || id >= 7"),
		"the band must ride the ACTOR ring branch - it is hostile red with a floored bloom, not a new family (props keep 5..6)")
	assert_true(src.contains("(id == 1 || (id >= 7 && id <= 8)) ? highlight_hostile"),
		"both hostile forms must resolve to the SAME LUT slot - retinting highlight_hostile must recolor a locked enemy too - and the band must be bounded ABOVE, or the hover (9) and view-model (10) ids fall into it and paint red")

## The two sides of the lock-on floor, met at their seam without re-implementing the shader: the band values the
## SCRIPT actually stamps (apply_tint_mesh) against the floor's smoothstep edges read out of the SHADER, and the
## bloom window _params actually pushes against the distances the ask names. A windowed frame-diff cannot check
## the rendered result (the post chain's TIME-driven film grain swamps any diff).
func test_the_band_stamps_reach_the_shaders_floor_edges() -> void:
	var re := RegEx.new()
	re.compile("closeness = max\\(closeness, smoothstep\\(([0-9.]+), ([0-9.]+), idf\\)\\);")
	var m := re.search(_read(SHADER_PATH))
	assert_true(m != null, "ink_outline.gdshader must floor the bloom with smoothstep(lo, hi, idf) - see the shader pin above")
	if m == null:
		return
	var lo := float(m.get_string(1))
	var hi := float(m.get_string(2))
	var host := MeshInstance3D.new()
	host.mesh = BoxMesh.new()
	InkOutline.apply_tint_mesh(host, InkOutline.TINT_ID_HOSTILE_ENGAGED, 0.0)
	assert_true(_painted_id(host) <= lo,
		"an unlocked band stamp (%.3f) must sit at/below the floor's lower edge %.3f - mix 0 adds no red at range, exactly like plain hostile" % [_painted_id(host), lo])
	InkOutline.apply_tint_mesh(host, InkOutline.TINT_ID_HOSTILE_ENGAGED, 1.0)
	assert_true(_painted_id(host) >= hi,
		"a fully locked stamp (%.3f) must reach the floor's upper edge %.3f - full red 'no matter the distance'" % [_painted_id(host), hi])
	InkOutline.apply_tint_mesh(host, InkOutline.TINT_ID_HOSTILE_ENGAGED, 0.5)
	var mid := _painted_id(host)
	assert_true(mid > lo and mid < hi,
		"a half-faded lock (%.3f) must land INSIDE the floor's ramp - the lock-on is a fade, not a pop" % mid)
	host.free()
	# The floor only matters because the distance bloom leaves a far hostile black: the pushed window must put
	# the ask's 60 m enemy past the far edge and a point-blank one inside the full-colour end.
	var ink = load(INK_PATH).new()
	var p: Dictionary = ink._params(1.0)
	var e60: float = InkOutlineScript.encode_actor_depth(60.0, InkOutlineScript.MASK_DEPTH_NEAR, InkOutlineScript.MASK_DEPTH_FAR)
	var e3: float = InkOutlineScript.encode_actor_depth(3.0, InkOutlineScript.MASK_DEPTH_NEAR, InkOutlineScript.MASK_DEPTH_FAR)
	assert_lt(e60, float(p["highlight_e_color_far"]),
		"a hostile at 60 m must sit past the pushed bloom's far edge - black without a lock, so the floor is what paints it red")
	assert_gt(e3, float(p["highlight_e_color_near"]),
		"a hostile at 3 m must sit inside the pushed bloom's near edge - full colour up close, lock or no lock")
	ink.free()

func test_apply_tint_blend_stamps_into_the_band_and_clamps() -> void:
	var host := MeshInstance3D.new()
	host.mesh = BoxMesh.new()
	InkOutline.apply_tint(host, InkOutline.TINT_ID_HOSTILE_ENGAGED, 0.5)
	var dup := host.get_node_or_null(InkOutline.TINT_DUP_NAME) as MeshInstance3D
	assert_not_null(dup, "apply_tint must build the duplicate for the engaged id like any other")
	if dup != null:
		assert_eq(dup.get_instance_shader_parameter(&"disposition_id"), 7.5,
			"blend must stamp as the fraction past the id - 7 + 0.5 lands mid-band, half-engaged")
		InkOutline.apply_tint(host, InkOutline.TINT_ID_HOSTILE_ENGAGED, 9.0)
		assert_eq(dup.get_instance_shader_parameter(&"disposition_id"), 8.0,
			"blend must clamp to 1 - past 8.0 ink_tint.gdshader's own clamp folds every value equal and the fade rail is lost")
	host.free()

func test_npc_outline_drives_the_lock_on_promotion() -> void:
	var rig := _npc_outline_rig()
	var npc = rig["npc"]
	var outline = rig["outline"]
	var part: MeshInstance3D = rig["part"]
	npc.disposition = Disposition.Kind.HOSTILE
	outline._engaged_mix = 0.5
	outline._sync_tint_duplicates()
	assert_almost_eq(_painted_id(part), float(InkOutline.TINT_ID_HOSTILE_ENGAGED) + 0.5, 0.0001,
		"a HOSTILE with live mix must ride the engaged band, the mix as the fraction past its base id")
	npc.disposition = Disposition.Kind.FRIENDLY
	outline._sync_tint_duplicates()
	assert_almost_eq(_painted_id(part), float(InkOutline.TINT_ID_FRIENDLY), 0.0001,
		"only a hostile promotes - a friendly alerted on the player keeps its colour until the disposition itself flips")
	# The pool-reuse restamp (review 2026-08-27): zeroing the mix is not enough - the duplicates' instance
	# uniform still holds the dead life's ~8.0 band, which unlike the old plain-id staleness renders full
	# red at ANY distance until AiLod's staggered first think (~0.25 s) reaches the corrective poll.
	npc.disposition = Disposition.Kind.HOSTILE
	outline._engaged_mix = 1.0
	outline._sync_tint_duplicates()
	assert_almost_eq(_painted_id(part), float(InkOutline.TINT_ID_HOSTILE_ENGAGED) + 1.0, 0.0001,
		"setup: the dead life died fully locked on")
	outline.reset_for_reuse()
	assert_eq(outline._engaged_mix, 0.0,
		"reset_for_reuse must zero the per-life mix - a pooled body would otherwise respawn wearing the previous life's full-red ring")
	assert_almost_eq(_painted_id(part), float(InkOutline.TINT_ID_HOSTILE), 0.0001,
		"reset_for_reuse must RESTAMP the duplicates now - the dead life's engaged band is visible at any distance at the spawn point")
	# A life reconfigured with outlines OFF never polls, so the restamp cannot fix it: the ring must go.
	outline._engaged_mix = 1.0
	outline._sync_tint_duplicates()
	npc.has_outline = false
	outline.reset_for_reuse()
	assert_null(part.get_node_or_null(InkOutline.TINT_DUP_NAME),
		"a pooled life with outlines off must not keep wearing the previous life's ring")
	npc.free()

## The lock-on fade consumes the BANKED AiLod think delta, not the raw physics step (review 2026-08-27):
## poll() sits below npc.gd's AI-LOD cadence gate, whose invariant 2 says everything below runs on the
## banked delta so a throttled NPC reacts less OFTEN but never in slow motion. Reading the frame step
## made a >45 m fade-out crawl 15x slow - a lingering false "targeting you" tell at exactly the range
## this feature made legible. Driven through poll() with deltas no physics step ever has (an off-tree node's
## own physics step reads 0), on a hostile whose Perception is ALERTED - the real is_alerted_on_player() path.
func test_engaged_fade_rides_the_banked_think_delta() -> void:
	var rig := _npc_outline_rig()
	var npc = rig["npc"]
	var outline = rig["outline"]
	var part: MeshInstance3D = rig["part"]
	npc.disposition = Disposition.Kind.HOSTILE
	npc.outline_target_fade_s = 0.5
	var perc := Perception.new()
	perc.state = Perception.State.ALERTED
	npc._perception = perc
	var player := Node3D.new()
	add_child_autofree(player)
	player.add_to_group(Groups.PLAYER)
	npc._target = player
	outline.poll(0.25)
	assert_almost_eq(outline._engaged_mix, 0.5, 0.0001,
		"0.25 s of think time into a 0.5 s fade must be half-way - the fade must step by the HANDED delta, never the node's own physics step")
	assert_almost_eq(_painted_id(part), float(InkOutline.TINT_ID_HOSTILE_ENGAGED) + 0.5, 0.0001,
		"each step must restamp the ring so the red actually fades in on screen")
	outline.poll(0.25)
	assert_almost_eq(outline._engaged_mix, 1.0, 0.0001, "a full fade's worth of think time lands exactly on fully locked")
	perc.state = Perception.State.UNAWARE  # the lock breaks
	outline.poll(0.125)
	assert_almost_eq(outline._engaged_mix, 0.75, 0.0001, "a broken lock fades back out at the same authored rate")
	assert_almost_eq(_painted_id(part), float(InkOutline.TINT_ID_HOSTILE_ENGAGED) + 0.75, 0.0001,
		"...and the ring eases back toward plain hostile with it")
	# The lock-on signal is is_alerted_on_player(): an ALERTED lock on somebody ELSE (an NPC-vs-NPC fight, a
	# proximity lock) must not light the ring.
	perc.state = Perception.State.ALERTED
	var bystander := Node3D.new()
	add_child_autofree(bystander)
	npc._target = bystander
	outline._engaged_mix = 0.0
	outline.poll(0.25)
	assert_eq(outline._engaged_mix, 0.0,
		"a lock on a non-player target must not fade the 'targeting you' ring in")
	npc._perception = null
	perc.free()
	npc.free()

## The cutscene branch polls too: a scene that pacifies an engaged enemy must fade its red ring on camera, not
## hold it frozen for the whole scene. ⭐ Still a SOURCE pin, deliberately: the call site lives in
## NPC._physics_process's cutscene branch, and driving that means ticking an NPC's physics (move_and_slide on a
## CharacterBody3D, in-tree), which CLAUDE.md rules out for unit tests. The fade itself is driven above.
func test_the_cutscene_branch_still_polls_the_outline() -> void:
	var npc_src := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
	var cutscene_at := npc_src.find("if _cutscene_control:")
	var decision_at := npc_src.find("AI LEVEL OF DETAIL")
	assert_true(cutscene_at > -1 and decision_at > cutscene_at,
		"the cutscene override branch precedes the AI-LOD gate (layout this pin depends on)")
	var cutscene_poll := npc_src.find("_outline.poll(delta)", cutscene_at)
	assert_true(cutscene_poll > -1 and cutscene_poll < decision_at,
		"the cutscene branch must still poll the outline - an engaged enemy pacified by a scene fades its lock-on ring on camera instead of freezing full red")

## The drive's snap path (outline_target_fade_s 0) off-tree: no perception -> is_alerted_on_player() is
## false -> the mix must fall straight to 0. Uses the sanctioned off-tree actor build (load().new(), no
## _ready, no add_child) — the CLAUDE.md test seam for NPC logic.
func test_engaged_mix_snaps_home_without_a_lock() -> void:
	var outline = load("res://scripts/npc/npc_outline.gd").new()
	var npc = load("res://scripts/npc/npc.gd").new()
	outline.host = npc
	npc.outline_target_fade_s = 0.0
	outline._engaged_mix = 1.0
	outline._drive_engaged_mix(1.0 / 60.0)
	assert_eq(outline._engaged_mix, 0.0,
		"with no lock and fade 0 the mix must SNAP to 0 - the authored-snap path, and the off-tree null-guard proof in one")
	outline._engaged_mix = 0.7
	outline.reset_for_reuse()
	assert_eq(outline._engaged_mix, 0.0, "reset_for_reuse must zero the per-life mix")
	npc.free()
	outline.free()

## The archetype half of the fade knob (review 2026-08-27): every sibling outline field rides the NpcData
## profile stamp, so this one must too or a designer tuning an archetype .tres silently can't reach it.
## The PROFILE_STAMPED_FIELDS <-> _stamp_profile_full set-equality is pinned by tests/test_npc_data.gd;
## this drives both profile paths for the fade specifically, off-tree (_apply_profile is the CLAUDE.md seam).
func test_outline_target_fade_is_profile_authorable() -> void:
	var data = load("res://scripts/npc/npc_data.gd").new()
	var npc = load("res://scripts/npc/npc.gd").new()
	assert_eq(data.outline_target_fade_s, npc.outline_target_fade_s,
		"NpcData's default must stay in lockstep with NPC's - an archetype that doesn't touch the field must not silently retune placed NPCs")
	data.outline_target_fade_s = 1.75
	npc.profile = data
	npc._apply_profile()
	assert_almost_eq(npc.outline_target_fade_s, 1.75, 0.0001,
		"an archetype's outline_target_fade_s must reach the NPC through the authoritative profile stamp")
	var inline_npc = load("res://scripts/npc/npc.gd").new()
	inline_npc.outline_target_fade_s = 0.9  # a per-instance tweak on a placed NPC
	inline_npc.profile = data
	inline_npc.profile_fills_blanks_only = true
	inline_npc._apply_profile()
	assert_almost_eq(inline_npc.outline_target_fade_s, 0.9, 0.0001,
		"under the additive merge an inline fade override must WIN - it only can if the field rides PROFILE_STAMPED_FIELDS")
	inline_npc.free()
	npc.free()
	data = null


# --- Colorblind-Safe Cues x the ring (2026-08-27) -----------------------------------------------------------
# THE GAP THIS SECTION PINS SHUT: _disposition_id() used to map by EXACT-COLOR compare against the NPC
# consts, but the resolver rides CBPalette, which returns orange/cyan with Settings.colorblind_safe_cues
# ON — nothing matched, every hostile/friendly fell to the neutral BLACK ring, and the engaged-band
# promotion gate (id == TINT_ID_HOSTILE) never fired. The ring — the NPC's ONLY outline — lost the entire
# disposition cue for exactly the accessibility users the palette serves. Two halves, tested separately:
# the ID resolution (palette-agnostic) and the LUT push (palette-following).

## Half 1: ids resolve from the DISPOSITION, so the safe palette cannot unmap them. Off-tree actor build
## (load().new(), no _ready, no add_child — the CLAUDE.md seam); the raw field write (never the setter)
## keeps the flip session-local: set_colorblind_safe_cues() would save_settings() to the user's real cfg.
func test_disposition_ids_survive_colorblind_safe_cues() -> void:
	var outline = load("res://scripts/npc/npc_outline.gd").new()
	var npc = load("res://scripts/npc/npc.gd").new()
	outline.host = npc
	var prev: bool = Settings.colorblind_safe_cues
	Settings.colorblind_safe_cues = true
	npc.disposition = Disposition.Kind.HOSTILE  # unaligned (no faction), so the standalone disposition rules
	assert_eq(outline._disposition_id(), InkOutline.TINT_ID_HOSTILE,
		"a HOSTILE must keep tint id 1 with safe cues ON - the black-ring degrade killed the cue AND the lock-on promotion for accessibility users")
	npc.disposition = Disposition.Kind.FRIENDLY
	assert_eq(outline._disposition_id(), InkOutline.TINT_ID_FRIENDLY,
		"a FRIENDLY must keep tint id 2 with safe cues ON")
	npc.disposition = Disposition.Kind.NEUTRAL
	assert_eq(outline._disposition_id(), InkOutline.TINT_ID_NEUTRAL,
		"NEUTRAL stays the deliberate black ring in both palettes")
	Settings.colorblind_safe_cues = false
	npc.disposition = Disposition.Kind.HOSTILE
	assert_eq(outline._disposition_id(), InkOutline.TINT_ID_HOSTILE,
		"and the normal palette resolves identically - the id is palette-agnostic, only the LUT swaps")
	Settings.colorblind_safe_cues = prev
	npc.free()
	outline.free()

## Half 2: with the toggle ON, _params pushes CBPalette's SAFE_* pair over the authored hostile/friendly
## exports (accessibility wins over per-scene tuning — the toggle exists to take red/green out of the
## cues). The engaged 7..8 band resolves to the same highlight_hostile slot in the shader (pinned by
## test_engaged_band_floors_the_bloom_in_the_shader), so the any-distance lock-on glow re-paints orange
## with it. _settings is wired by hand because _ready never runs off-tree — that also proves the read
## rides the instance handle (the hardened .get() idiom), not a bare autoload access.
func test_ring_lut_follows_the_colorblind_safe_palette() -> void:
	var ink = load(INK_PATH).new()
	ink._settings = Settings
	var prev: bool = Settings.colorblind_safe_cues
	Settings.colorblind_safe_cues = false
	var normal: Dictionary = ink._params(1.0)
	assert_eq(normal["highlight_hostile"], ink.highlight_hostile,
		"toggle OFF must push the authored export untouched - the per-scene tuning surface stays real")
	assert_eq(normal["highlight_friendly"], ink.highlight_friendly,
		"toggle OFF must push the authored friendly export untouched")
	Settings.colorblind_safe_cues = true
	var safe: Dictionary = ink._params(1.0)
	assert_eq(safe["highlight_hostile"], CBPalette.SAFE_HOSTILE,
		"toggle ON must push CBPalette.SAFE_HOSTILE (orange) - the ring must swap in lockstep with the laser/name/health-bar cues")
	assert_eq(safe["highlight_friendly"], CBPalette.SAFE_FRIENDLY,
		"toggle ON must push CBPalette.SAFE_FRIENDLY (cyan)")
	assert_eq(safe["highlight_companion"], normal["highlight_companion"],
		"companion blue is fixed in both modes - outside the red/green axis, matching NPC.OUTLINE_FOLLOWING")
	assert_eq(safe["highlight_neutral"], normal["highlight_neutral"],
		"the neutral black ring is fixed in both modes")
	Settings.colorblind_safe_cues = prev
	ink.free()

## The off-tree degrade: with no Settings autoload wired (_settings null - a bare harness), the flag
## reads false and the authored NORMAL palette pushes - the exact pre-override behaviour, so a harness
## frame can never render the safe palette by accident.
func test_ring_lut_defaults_to_the_authored_palette_off_tree() -> void:
	var ink = load(INK_PATH).new()
	var prev: bool = Settings.colorblind_safe_cues
	Settings.colorblind_safe_cues = true  # even with the real toggle ON, an unwired instance must not see it
	var p: Dictionary = ink._params(1.0)
	assert_eq(p["highlight_hostile"], ink.highlight_hostile,
		"off-tree (_settings null) the LUT must stay the authored exports - _cb_safe() degrades to false, never throws")
	Settings.colorblind_safe_cues = prev
	ink.free()



# --- The ring outlives the aesthetic slider (2026-08-27) ---------------------------------------------------
# While the inverted hull existed, Options -> Video -> "Ink Outline" at 0% left every gameplay outline intact
# (the hull rims were not part of this pass). With the hull deleted the ring IS every outline in the game, so
# a slider that scaled it would silently become the master switch for hostile red, the colourblind-safe
# palette, claimed-prop blue, every look-at hover cue and the view model's line.

func test_the_ring_does_not_ride_the_ink_intensity_slider() -> void:
	var src := _read(SHADER_PATH)
	assert_true(src.contains("out_alpha = max(out_alpha, ring_a);"),
		"the ring must compose at full strength - multiplying it by ink_opacity turns a video option into a gameplay and accessibility switch")
	assert_true(src.contains("float out_alpha = clamp(edge, 0.0, 1.0) * ink_color.a * ink_opacity;"),
		"...while the WORLD's ink keeps riding the slider, which is what the slider is for")

func test_zero_intensity_still_pushes_the_full_set_when_the_ring_is_live() -> void:
	# ink_params already zeroes the world ink at t<=0 (ink_opacity 0, width_px 0), so a ring-only frame is
	# the same uniform set with nothing for the edge detect to draw.
	var ink = load(INK_PATH).new()
	# CONTROL - off-tree there is no tint viewport, so the guard must still take the cheap early-out (the
	# pre-migration behaviour, unchanged).
	assert_false(ink.ring_enabled(), "off-tree there is no tint pass, so the ring is not live")
	var bare: Dictionary = ink._params(0.0)
	assert_false(bool(bare["apply"]), "a zeroed slider still means the WORLD ink does not draw")
	assert_false(bare.has("highlight_width_px"),
		"...and with no ring to serve, _params must take the early-out rather than build a set nobody reads")
	# THE CASE THE NAME PROMISES - both passes built, as _build_mask_pass leaves them.
	var mask_vp := SubViewport.new()
	var tint_vp := SubViewport.new()
	ink._mask_viewport = mask_vp
	ink._tint_viewport = tint_vp
	assert_true(ink.ring_enabled(), "with the tint pass built and a ring width, the ring is live")
	var ring_only: Dictionary = ink._params(0.0)
	var full: Dictionary = ink._params(1.0)
	assert_false(bool(ring_only["apply"]), "the slider at 0% still does not draw the WORLD ink")
	assert_almost_eq(float(ring_only["ink_opacity"]), 0.0, 0.0001, "the world line is zeroed on a ring-only frame")
	assert_true(bool(ring_only["use_actor_tint"]),
		"the ring gate must still be pushed ON at 0% - the slider must not switch off hostile red, the safe palette or the hover")
	assert_almost_eq(float(ring_only["highlight_width_px"]), float(full["highlight_width_px"]), 0.0001,
		"the ring must be pushed at its full authored width at every slider position")
	assert_false(bool(ring_only["use_actor_mask"]),
		"a ring-only frame must not sample the (frozen) actor mask - there is no world line to suppress")
	assert_true(bool(full["use_actor_mask"]), "CONTROL: the same built mask IS sampled while the world ink draws")
	ink._mask_viewport = null
	ink._tint_viewport = null
	mask_vp.free()
	tint_vp.free()
	ink.free()

## A stand-in for the Settings autoload exposing only the one field InkOutline polls by name - so _refresh can be
## driven at any slider position without writing the real autoload (every other Settings read degrades cleanly).
class _FakeInkSettings extends Node:
	var ink_outline_intensity: float = 1.0

func test_both_sub_viewports_are_gated_and_the_tint_one_follows_the_ring() -> void:
	# The tint pass is a SECOND full scene render over every ringed thing in the level. It was never gated
	# at all until 2026-08-27 - it kept drawing at 0% intensity and with `enabled` off, for a texture nothing
	# sampled. That was survivable while the ring served NPCs alone; with props, gibs, corpses, the hover and
	# the whole view model on it, an ungated pass is most of the frame drawn a third time for nothing.
	# Driven through _refresh (the per-frame entry) with both viewports built and a stand-in material.
	var ink = load(INK_PATH).new()
	ink._material = ShaderMaterial.new()
	var mask_vp := SubViewport.new()
	var tint_vp := SubViewport.new()
	ink._mask_viewport = mask_vp
	ink._tint_viewport = tint_vp
	var fake := _FakeInkSettings.new()
	ink._settings = fake
	fake.ink_outline_intensity = 1.0
	ink._refresh()
	assert_true(ink.visible, "at full strength the quad draws")
	assert_eq(mask_vp.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "the MASK pass renders while the world ink draws")
	assert_eq(tint_vp.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "the TINT pass renders while the ring draws")
	assert_gt(float(ink._material.get_shader_parameter("width_px")), 0.0,
		"the refreshed uniform set must actually reach the quad's material")
	fake.ink_outline_intensity = 0.0
	ink._refresh()
	assert_true(ink.visible, "at 0% the quad must stay up for the ring alone - it is every outline in the game")
	assert_eq(mask_vp.render_target_update_mode, SubViewport.UPDATE_DISABLED,
		"the MASK viewport must freeze whenever the world ink is not drawing")
	assert_eq(tint_vp.render_target_update_mode, SubViewport.UPDATE_ALWAYS,
		"...while the TINT viewport keeps rendering for the ring")
	ink.highlight_width_px = 0.0
	ink._refresh()
	assert_false(ink.visible, "no world ink and no ring width: nothing draws, so the quad hides")
	assert_eq(tint_vp.render_target_update_mode, SubViewport.UPDATE_DISABLED,
		"the TINT viewport must freeze whenever the ring is not drawing")
	ink.highlight_width_px = 2.0
	fake.ink_outline_intensity = 1.0
	ink._refresh()
	assert_eq(tint_vp.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "setup: both passes live again")
	ink.enabled = false
	ink._refresh()
	assert_false(ink.visible, "`enabled` off hides the whole pass")
	assert_eq(mask_vp.render_target_update_mode, SubViewport.UPDATE_DISABLED, "`enabled` off must freeze the MASK pass")
	assert_eq(tint_vp.render_target_update_mode, SubViewport.UPDATE_DISABLED,
		"`enabled` off must freeze the TINT pass too - the ungated third render this test exists for")
	ink._mask_viewport = null
	ink._tint_viewport = null
	ink._settings = null
	mask_vp.free()
	tint_vp.free()
	fake.free()
	ink.free()

# --- Every consumer the hull's deletion moved (2026-08-27) -------------------------------------------------
# The migration's own regression net: each of these had NO other outline, so a missed call site is an
# invisible thing rather than an error. Each consumer is driven through its own entry point (off-tree where the
# component allows it, a throwaway in-tree host where it needs _ready) and the ring it actually paints is read.

func test_the_inverted_hull_is_gone_from_the_project() -> void:
	assert_false(FileAccess.file_exists("res://resources/shaders/outline.gdshader"),
		"outline.gdshader must be deleted - a surviving copy is a second outline technique waiting to be re-adopted")
	assert_false(FileAccess.file_exists("res://resources/materials/outline_black.tres"),
		"...and so must the shared black hull material that fronted it")
	var helper_methods := []
	for m in (load("res://scripts/dialogue/talk_helpers.gd") as GDScript).get_script_method_list():
		helper_methods.append(String(m["name"]))
	assert_true(helper_methods.has("collect_meshes"), "CONTROL: the reflection sees TalkHelpers' static functions")
	assert_false(helper_methods.has("make_outline_material"),
		"TalkHelpers must not rebuild the hull factory - it was the chokepoint six consumers went through")
	assert_false(helper_methods.has("set_overlay"),
		"...nor the material_overlay stash the look-at highlight rode; the highlight borrows an ID now")

func test_every_migrated_consumer_stamps_a_ring() -> void:
	# The muzzle flash that opts into has_outline (the explosion's default-off half is pinned above).
	var flash = load("res://scripts/components/explosion_mesh.gd").new()
	flash.mesh = SphereMesh.new()
	flash.has_outline = true
	flash._ready()  # off-tree, the file's idiom
	assert_eq(_painted_id(flash), float(InkOutline.TINT_ID_NEUTRAL),
		"a flash that opts into has_outline must wear the neutral ring - the hull it used to build is deleted, so it is the flash's only line")
	var flash_dup := flash.get_node_or_null(InkOutline.TINT_DUP_NAME) as MeshInstance3D
	assert_true(flash_dup != null and flash_dup.mesh == flash.mesh,
		"the flash's ring must mirror the sphere _ready duplicated for it (stamped LAST), not the authored one")
	flash.free()
	# A spent physical casing.
	var casing = load("res://scripts/projectiles/bullet_casing.gd").new()
	var shell := MeshInstance3D.new()
	shell.mesh = BoxMesh.new()
	shell.layers = 1
	casing.add_child(shell)
	casing._ready()  # off-tree: a bare RigidBody3D whose _ready only dresses its meshes
	assert_eq(_painted_id(shell), float(InkOutline.TINT_ID_PROP_REST),
		"a casing must wear the prop rest ring - its authored hull overlay is gone")
	assert_true((shell.layers & InkOutline.ACTOR_INK_MASK_LAYER) != 0,
		"...and carry the mask bit, or the world's ink draws a second line on it")
	assert_true((shell.layers & 1) != 0, "the stamp is an OR - the casing keeps its authored layers")
	casing.free()

func test_the_corpse_takes_the_mask_bit_with_its_ring() -> void:
	# ⭐ Ragdoll never stamped ACTOR_INK_MASK_LAYER, so a corpse quietly wore its hull AND the world's ink
	# for months. That is also why deleting the hull would have DEGRADED it (to world-ink-only) rather than
	# breaking it - the easiest kind of regression to miss. Ring and stamp are one contract.
	var corpse = load("res://scripts/components/ragdoll.gd").new()
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	body.layers = 1
	corpse.add_child(body)
	add_child(corpse)  # _ready -> _apply_outline, then parks on its first physics-frame await
	assert_true((body.layers & InkOutline.ACTOR_INK_MASK_LAYER) != 0,
		"Ragdoll must exclude corpses from the world ink now that it rings them, or a corpse wears two lines")
	assert_eq(_painted_id(body), float(InkOutline.TINT_ID_NEUTRAL),
		"a corpse must wear the neutral ring - with the hull deleted it is the body's only outline")
	corpse._fade_and_free()
	assert_null(body.get_node_or_null(InkOutline.TINT_DUP_NAME),
		"...and drop the ring the moment the corpse starts dissolving, or an outline outlives the body it wraps")
	corpse.free()  # synchronously, before the parked physics-frame await can resume
	# CONTROL: `outline` off leaves the corpse to the world ink - no ring, and a stale mask bit is taken back.
	var plain = load("res://scripts/components/ragdoll.gd").new()
	plain.outline = false
	var plain_body := MeshInstance3D.new()
	plain_body.mesh = BoxMesh.new()
	plain_body.layers = 1 | InkOutline.ACTOR_INK_MASK_LAYER
	plain.add_child(plain_body)
	plain._apply_outline()
	assert_eq(plain_body.layers & InkOutline.ACTOR_INK_MASK_LAYER, 0,
		"an un-ringed corpse must NOT carry the mask bit - masked with no ring is a body with no line at all")
	assert_eq(_painted_id(plain_body), -1.0, "an un-ringed corpse gets no ring")
	plain.free()

func test_the_look_at_hover_borrows_and_gives_back() -> void:
	# The hover paints white over whatever a mesh was already wearing, so it MUST restore. Scenery that had
	# no outline at all gets a duplicate created for the hover and freed again, which is what stops a hover
	# stranding a permanent white ring on a terminal. Every check reads the PAINTED id (the instance uniform
	# the ring shader reads), not only the stashed base, which the hover never writes.
	var owned := MeshInstance3D.new()
	owned.mesh = BoxMesh.new()
	InkOutline.apply_tint_mesh(owned, InkOutline.TINT_ID_HOSTILE)
	var bare := MeshInstance3D.new()
	bare.mesh = BoxMesh.new()
	var meshes: Array[MeshInstance3D] = [owned, bare]
	InkOutline.set_tint_highlight(meshes, true)
	assert_eq(_painted_id(owned), float(InkOutline.TINT_ID_HOVER), "the hover must actually paint the mesh white")
	assert_eq(InkOutline.tint_base_id(owned), InkOutline.TINT_ID_HOSTILE,
		"the borrow must remember the id it took, not overwrite it")
	assert_eq(_painted_id(bare), float(InkOutline.TINT_ID_HOVER), "un-ringed scenery gets a duplicate built for the hover")
	InkOutline.set_tint_highlight(meshes, true)  # idempotent: a second ON must not eat the stash
	InkOutline.set_tint_highlight(meshes, false)
	assert_eq(_painted_id(owned), float(InkOutline.TINT_ID_HOSTILE),
		"look-away must paint the borrowed id back - otherwise looking at an enemy once leaves it white forever")
	assert_null(bare.get_node_or_null(InkOutline.TINT_DUP_NAME),
		"...and free the one it created, so a hover can never strand a white ring on the level")
	# A retint WHILE hovered (an NPC turning friendly under the cursor) updates what comes back, not what shows.
	InkOutline.set_tint_highlight(meshes, true)
	InkOutline.apply_tint_mesh(owned, InkOutline.TINT_ID_FRIENDLY)
	assert_eq(_painted_id(owned), float(InkOutline.TINT_ID_HOVER),
		"a retint under the cursor must not flicker the white off")
	InkOutline.set_tint_highlight(meshes, false)
	assert_eq(_painted_id(owned), float(InkOutline.TINT_ID_FRIENDLY),
		"look-away must restore the STORED base tint - the retint recorded mid-hover, not the stale one and never the hover")
	# The engaged band's fraction survives the round-trip too.
	InkOutline.apply_tint_mesh(owned, InkOutline.TINT_ID_HOSTILE_ENGAGED, 0.25)
	InkOutline.set_tint_highlight(meshes, true)
	InkOutline.set_tint_highlight(meshes, false)
	assert_almost_eq(_painted_id(owned), float(InkOutline.TINT_ID_HOSTILE_ENGAGED) + 0.25, 0.0001,
		"a half-locked enemy must come back from a hover mid-fade, not snapped to a whole id")
	owned.free()
	bare.free()

func test_an_invisible_highlight_never_borrows() -> void:
	# Zeroing highlight_color.a or highlight_width is how a designer says "this one gets no hover outline"
	# (the shipping ATM). Honouring it literally - by never borrowing - is the only reading that cannot take
	# somebody else's line for as long as the player looks at them. Driven on the two look-at consumers beside
	# LookAtInteractable (whose own guard lives in tests/test_look_at_interactable.gd), each with a CONTROL:
	# the same rig with a visible highlight really does borrow.
	for visible_hl in [true, false]:
		var host := Node3D.new()
		add_child_autofree(host)
		var body := MeshInstance3D.new()
		body.mesh = BoxMesh.new()
		InkOutline.apply_tint_mesh(body, InkOutline.TINT_ID_HOSTILE)
		host.add_child(body)
		var talk = load("res://scripts/components/talkable.gd").new()
		talk.highlight_color = Color(1.0, 1.0, 1.0, 1.0 if visible_hl else 0.0)
		host.add_child(talk)  # _ready -> _highlight_on
		talk.set_look_highlight(true)
		assert_eq(_painted_id(body), float(InkOutline.TINT_ID_HOVER if visible_hl else InkOutline.TINT_ID_HOSTILE),
			"Talkable (highlight alpha %s): a visible hover borrows the host's ring, an invisible one must leave it painted" % talk.highlight_color.a)
		talk.set_look_highlight(false)
		assert_eq(_painted_id(body), float(InkOutline.TINT_ID_HOSTILE), "Talkable: look-away leaves the host's own ring")
		var station = load("res://scripts/components/dialogue_npc.gd").new()
		station.highlight_width = 1.0 if visible_hl else 0.0
		var screen := MeshInstance3D.new()
		screen.mesh = BoxMesh.new()
		InkOutline.apply_tint_mesh(screen, InkOutline.TINT_ID_NEUTRAL)
		station.add_child(screen)
		add_child_autofree(station)  # _ready -> _highlight_on + _meshes
		station.set_look_highlight(true)
		assert_eq(_painted_id(screen), float(InkOutline.TINT_ID_HOVER if visible_hl else InkOutline.TINT_ID_NEUTRAL),
			"DialogueNPC (highlight width %s): a visible hover borrows the ring, an invisible one must leave it painted" % station.highlight_width)
		station.set_look_highlight(false)
		assert_eq(_painted_id(screen), float(InkOutline.TINT_ID_NEUTRAL), "DialogueNPC: look-away leaves its own ring")


# --- The duplicate MIRRORS its host's mesh (the ghost-pistol regression, 2026-08-27) -----------------------
# Reported hours after the ring took the view model over: "a permanent ghost outline of the silenced pistol
# perpetually floating in front of the player's right hand". WeaponModelSwapper hides the rig's built-in
# placeholder gun by NULLING each mesh (it cannot use `visible`, because the Muzzle and its FX are parented
# under it), and a tint duplicate SNAPSHOTS `m.mesh` when it is stamped — so the pistol's silhouette stayed
# in the tint buffer forever and the ring pass dutifully drew it around nothing. The inverted hull this
# replaced could not fail that way: it rode `material_overlay` ON the mesh, so a null mesh drew nothing.
# Measured with scripts/tools/probes/__viewmodel_ring_shot.gd (magenta view-model LUT): 127 ring px in the ghost's
# region before the fix, 11 after.

func test_sync_tint_mesh_follows_a_host_that_loses_its_mesh() -> void:
	var host := MeshInstance3D.new()
	host.mesh = BoxMesh.new()
	InkOutline.apply_tint_mesh(host, InkOutline.TINT_ID_VIEW_MODEL)
	var dup := host.get_node_or_null(InkOutline.TINT_DUP_NAME) as MeshInstance3D
	assert_not_null(dup, "the host must be ringed before there is anything to go stale")
	if dup != null:
		assert_eq(dup.mesh, host.mesh, "the duplicate mirrors its host's mesh")
		var stashed := host.mesh
		host.mesh = null                       # exactly how the placeholder pistol is hidden
		InkOutline.sync_tint_mesh(host)
		assert_null(dup.mesh,
			"a host with no mesh must ring NOTHING - this is the ghost pistol, and nothing else in the engine reports it")
		host.mesh = stashed                    # ...and exactly how it is restored
		InkOutline.sync_tint_mesh(host)
		assert_eq(dup.mesh, stashed, "restoring the host's mesh must bring its ring back with it")
	host.free()

func test_sync_tint_mesh_is_safe_where_there_is_no_ring() -> void:
	# It is called from mesh-swap paths that run on plenty of un-ringed meshes (and on props before their
	# ring is stamped), so a missing duplicate must be a no-op rather than a crash.
	var bare := MeshInstance3D.new()
	bare.mesh = BoxMesh.new()
	InkOutline.sync_tint_mesh(bare)
	assert_null(bare.get_node_or_null(InkOutline.TINT_DUP_NAME),
		"sync must never CREATE a ring - it only mirrors one that already exists")
	bare.free()

# ⭐ The contract has no enforcement in the engine: `mesh` is a plain property with no change notification, so a
# swap path that forgets the sync reintroduces a shape hanging in mid-air with no error, no warning and no other
# failing test. The three tests below drive each mesh-reassignment site that exists today and read the RING's mesh.

func test_hiding_the_placeholder_gun_takes_its_ring_with_it() -> void:
	# WeaponModelSwapper hides the rig's built-in pistol by NULLING each mesh (never `visible`, which would take
	# the Muzzle and its FX with it) and restores it from a stash. Driven on a stand-in placeholder subtree.
	var swapper = load("res://scripts/effects/weapon_model_swapper.gd").new()  # off-tree: no host needed for the walk
	var placeholder := Node3D.new()
	placeholder.name = "Sketchfab_Scene"
	var pistol := _named_box_mesh("Pistol")
	placeholder.add_child(pistol)
	var muzzle := Node3D.new()
	muzzle.name = "PlayerMuzzle"
	placeholder.add_child(muzzle)
	var muzzle_fx := _named_box_mesh("MuzzleFlash")
	muzzle.add_child(muzzle_fx)
	InkOutline.apply_tint_mesh(pistol, InkOutline.TINT_ID_VIEW_MODEL)  # the rig is dressed before any swap
	var pistol_mesh := pistol.mesh
	var dup := pistol.get_node(InkOutline.TINT_DUP_NAME) as MeshInstance3D
	swapper._toggle_placeholder_meshes(placeholder, muzzle, true)
	assert_null(pistol.mesh, "setup: the placeholder is hidden the mesh way")
	assert_null(dup.mesh,
		"hiding the placeholder pistol must take its ring with it - otherwise a ghost outline of it floats by the player's hand")
	assert_not_null(muzzle_fx.mesh, "the Muzzle subtree is never touched")
	swapper._toggle_placeholder_meshes(placeholder, muzzle, false)
	assert_eq(pistol.mesh, pistol_mesh, "setup: the placeholder is restored from the stash")
	assert_eq(dup.mesh, pistol_mesh, "restoring the placeholder must bring its ring back with it")
	placeholder.free()
	swapper.free()

func test_a_throwable_model_swap_takes_its_ring_with_it() -> void:
	# All three ThrowableData model branches reassign mesh_instance.mesh AFTER the ring may already be stamped
	# (a `data` reassigned at runtime): a Mesh, clearing back to the authored mesh, and a PackedScene (mounted
	# under mesh_instance, whose own mesh goes null).
	var t = load("res://scripts/components/Throwable.gd").new()  # off-tree: _ready never runs
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	t.add_child(mi)
	t.mesh_instance = mi
	var authored := mi.mesh
	t._setup_overlay_chain()  # the prop is ringed
	var dup := mi.get_node(InkOutline.TINT_DUP_NAME) as MeshInstance3D
	var swapped := SphereMesh.new()
	t._apply_data_model_resource(swapped)
	assert_eq(dup.mesh, swapped, "a Mesh model must re-mirror the ring onto the new mesh, not outline the old one in mid-air")
	t._apply_data_model_resource(null)
	assert_eq(dup.mesh, authored, "clearing the model must bring the ring back to the authored mesh")
	var model := MeshInstance3D.new()
	model.mesh = BoxMesh.new()
	var scene := PackedScene.new()
	scene.pack(model)
	model.free()
	t._apply_data_model_resource(scene)
	assert_null(mi.mesh, "setup: a scene model mounts under mesh_instance and clears its own mesh")
	assert_null(dup.mesh, "...and the ring must clear with it, or the old silhouette hangs around the new model")
	t.free()

func test_a_resized_blast_flash_takes_its_ring_with_it() -> void:
	# ExplosionArea re-sizes the flash sphere AFTER the child ExplosionMesh._ready has stamped its ring (children
	# ready first), so it owes the sync too. Visual-only blast (no damage, no force): its _ready never awaits.
	var flash = load("res://scripts/components/explosion_mesh.gd").new()
	flash.mesh = SphereMesh.new()
	flash.has_outline = true
	flash._ready()  # the child's _ready: stamps the ring against its own sphere
	var dup := flash.get_node(InkOutline.TINT_DUP_NAME) as MeshInstance3D
	var stamped_against: Mesh = flash.mesh
	var area = load("res://scripts/components/explosion_area.gd").new()
	area.deals_damage = false
	area.max_explosion_force = 0.0
	area.explosion_radius = 2.0
	area.mesh_instance = flash
	var light := OmniLight3D.new()
	light.name = "OmniLight3D"  # the scene's own child, which the script's @onready resolves
	area.add_child(light)
	area._ready()
	assert_ne(flash.mesh, stamped_against, "setup: the blast swapped in its own resized sphere")
	assert_eq(dup.mesh, flash.mesh,
		"the flash's ring must follow the resized sphere - otherwise it is drawn at the AUTHORED radius around a different-sized flash")
	area.free()
	flash.free()
