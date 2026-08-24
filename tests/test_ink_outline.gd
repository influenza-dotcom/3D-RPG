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
## material construction, no _process). The scene wiring is asserted against the .tscn TEXT, matching
## how test_smoke.gd already pins camera_rig.tscn — instantiating that rig would drag in the weapon
## scenes, lights and audio players for no added coverage.

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

func test_intensity_scaled_uniforms_are_pushed_at_full_strength() -> void:
	# The two uniforms the player's dial governs must both be in the pushed set, or the Options slider
	# would move a value that never reaches the shader.
	var ink = load(INK_PATH).new()
	var params: Dictionary = ink._params(1.0)
	assert_true(params.has("ink_opacity"), "the live line opacity must be pushed")
	assert_true(params.has("width_px"), "the live line width must be pushed")
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
	assert_eq(InkOutlineScript.ACTOR_INK_MASK_LAYER, 1 << 19,
		"the actor mask layer is render layer 20 — far above the world (1), misc (2) and view-model (3) layers")
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

func test_body_swap_actor_outline_stamps_the_mask_layer_and_the_rim() -> void:
	var swap := BodyModelSwap.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.layers = 1
	swap._body = mi          # stand in for an instanced part, so character_parts() reports it
	swap.add_child(mi)       # (off-tree: _ready never runs, so nothing rebuilds over the top of it)
	swap.actor_outline = true
	assert_true((mi.layers & InkOutlineScript.ACTOR_INK_MASK_LAYER) != 0,
		"actor_outline must register the rig's parts with the ink actor mask")
	assert_true((mi.layers & 1) != 0, "the stamp is an OR — the mesh must keep its original layers")
	assert_not_null(mi.material_overlay,
		"...and it must wear the hull rim in the same operation — a masked mesh with no rim has NO outline at all")
	swap.free()

func test_body_swap_actor_outline_strips_what_it_owns_and_nothing_else() -> void:
	# The @tool half: un-ticking the box in the editor has to visibly remove the rim. It may only clear an
	# overlay it recognises as its own (the bms_actor_rim meta), never one another system put there.
	var swap := BodyModelSwap.new()
	var mine := MeshInstance3D.new()
	mine.mesh = BoxMesh.new()
	swap._body = mine
	swap.add_child(mine)
	swap.actor_outline = true
	swap.actor_outline = false
	assert_eq(mine.layers & InkOutlineScript.ACTOR_INK_MASK_LAYER, 0,
		"turning actor_outline off must give the mask bit back")
	assert_null(mine.material_overlay, "...and clear the rim it stamped")
	var foreign := ShaderMaterial.new()  # somebody else's overlay (a talk highlight, an NPC's combat rim)
	mine.material_overlay = foreign
	swap.actor_outline = false
	assert_eq(mine.material_overlay, foreign,
		"the strip must leave an overlay it does not own alone — it keys on the bms_actor_rim meta, not on the slot")
	swap.free()

func test_body_swap_rim_fades_with_the_part_it_wraps() -> void:
	# ⭐A rim that stays opaque while its geometry dithers out leaves a solid black silhouette of your own chest
	# hanging under the camera through the whole crouch hide and look-down fade — strictly worse than either
	# extreme. The alpha is DRIVEN from the same see-through the part itself takes.
	var swap := BodyModelSwap.new()
	swap.actor_outline = true
	swap.body_transparency = 0.0
	assert_almost_eq(swap._outline_color_for("torso").a, 1.0, 0.0001,
		"a solid chest wears a solid rim")
	swap.body_transparency = 1.0
	assert_almost_eq(swap._outline_color_for("torso").a, 0.0, 0.0001,
		"a fully dissolved chest must take its outline with it")
	assert_almost_eq(swap._outline_color_for("leg_l").a, 1.0, 0.0001,
		"...without touching the legs, which have no fade channel of their own")
	swap.arm_transparency = 1.0
	assert_almost_eq(swap._outline_color_for("arm_l").a, 0.0, 0.0001,
		"the arms follow arm_transparency, their own third curve (they also hide when the view model owns your hands)")
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

func test_hull_rest_rims_are_black_again() -> void:
	# With the mask in place the classic black rims are CORRECT (they cannot double with the ink).
	# History guard: they briefly shipped transparent as a doubling dodge — that regressed the actor
	# look and must not come back. test_npc.gd pins the NPC export; these pin the other two defaults.
	var data = load("res://scripts/npc/npc_data.gd").new()
	assert_eq(data.outline_color, Color.BLACK,
		"NpcData.outline_color stamps over NPC.outline_color at spawn — must stay the classic black rim")
	data = null
	var hidden: Color = load("res://scripts/components/Throwable.gd").OUTLINE_HIDDEN_COLOR
	assert_eq(hidden, Color(0.0, 0.0, 0.0, 1.0),
		"Throwable's at-rest rim is the classic opaque black again (masked out of the ink, so no doubling)")

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
	var full: Vector2i = InkOutlineScript.mask_size(Vector2i(792, 444), 1.0)
	assert_eq(full, Vector2i(792, 444), "at 1.0 the mask matches the frame exactly")
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
	# shader never needs to know how coarse it is; nothing resolution-derived belongs in the pushed set.
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
	var ink = load(INK_PATH).new()
	assert_almost_eq(ink.mask_resolution, 1.0, 0.0001,
		"InkOutline must default to a frame-resolution mask — below it the ink stops short of actors by a visible margin")
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

func test_the_ink_shader_searches_outward_for_the_hull_rims_depth() -> void:
	# ⭐⭐ THE ONE THAT KILLS THE "O SHAPE". outline.gdshader assigns ALPHA inside a branch, and Godot flags
	# a material `uses_alpha` from that assignment EXISTING rather than from the branch being taken — so
	# the rim renders in the TRANSPARENT pass and writes no depth. Measured on 4.7.1: a box wearing the
	# real hull covered 23 px of mask ALPHA but only 19 px of mask DEPTH. That 4 px ring has coverage and
	# nothing to compare, so without a search the ink keeps suppressing it and a hidden actor punches an
	# OUTLINE of itself through the world's lines instead of a solid hole.
	# The search MUST live in the ink shader, not the resolve pass: the resolve pass can only widen the
	# mask's depth by widening its ALPHA, and the mask's alpha is coverage, and coverage is suppressed ink
	# — so repairing the ring there buys a bare halo around every VISIBLE actor instead (measured: a faint
	# doubled line along the top edge of the control actor). Searching here claims no extra pixels.
	var src := _read(SHADER_PATH)
	assert_true(src.contains("float searched_depth("),
		"ink_outline.gdshader must search outward for the rim's depth, or hidden actors keep a ring-shaped halo")
	assert_true(_shader_uniform_names().has("mask_rim_search_px"),
		"the search radius must be a uniform the script pushes, not a baked-in constant")
	# And the resolve pass must NOT have grown its own spreading back.
	var resolve := _read(RESOLVE_SHADER_PATH)
	assert_false(resolve.contains("dilate_px"),
		"actor_mask_resolve.gdshader must not spread depth outward — it can only do so by widening COVERAGE, which is a halo")

func test_rim_search_out_reaches_every_authored_outline_width() -> void:
	# The rim is `outline_width * 2` pixels of the MASK viewport, and the mask renders at half the ink
	# buffer's resolution, so a rim spans `outline_width * 4` pixels of the buffer the search works in.
	# Fall short of the widest authored rim and its outermost ring loses trustworthy depth — it degrades
	# to always-suppress rather than breaking, but the hidden actor's O-shaped halo comes back on it.
	var ink = load(INK_PATH).new()
	var npc_data = load("res://scripts/npc/npc_data.gd").new()
	var npc = load("res://scripts/npc/npc.gd").new()      # off-tree: _ready never runs
	var ragdoll = load("res://scripts/components/ragdoll.gd").new()
	var widest: float = maxf(maxf(float(npc_data.outline_width), float(npc.outline_width)),
		float(ragdoll.outline_width))
	assert_gte(ink.mask_rim_search_px, widest * 4.0,
		"mask_rim_search_px (%.1f) must out-reach the widest authored rim (outline_width %.1f x 4 = %.1f px of the ink buffer)"
			% [ink.mask_rim_search_px, widest, widest * 4.0])
	npc_data = null      # NpcData is a Resource — release by dropping the ref
	ragdoll.free()       # ragdoll.gd extends Node3D, so it needs freeing, not nulling
	npc.free()
	ink.free()

func test_the_view_model_hull_rim_is_a_visible_width() -> void:
	# ⭐⭐ THE VIEW MODEL HAS EXACTLY ONE OUTLINE, AND THIS IS IT. The gun draws on the view-model layer, the
	# mask camera culls that layer, and the ink shader DISCARDS covered pixels — so the world's ink never
	# touches the weapon (correct: rim + ink = the doubled outline this pass exists to prevent). Which
	# means GunVisuals' hull rim is the gun's only line, and it must be a VISIBLE one. It was not: the
	# default sat at 0.02 from 2026-06-03 to 2026-08-18 — a value sized in the OLD outline shader's units
	# (a world-space extrusion in metres) and never retuned when the shader went screen-space, where
	# `outline_width` is ~1 visible pixel per unit at any distance. Measured on the silenced pistol: 5 rim
	# pixels at 0.02, 988 at 2.0. The gun had no other outline to compare against until the ink pass
	# briefly inked it and the mask took the ink off — the day the weapon visibly "lost its outline".
	# Pinned to NPC PARITY, not merely ">0": the rim is a house look shared by every actor, and the fists
	# (FirstPersonBody) are pinned to the same 2.0 beside the gun.
	var visuals = load("res://scripts/effects/gun_visuals.gd").new()   # off-tree: _ready never runs
	var npc = load("res://scripts/npc/npc.gd").new()
	assert_almost_eq(float(visuals.outline_width), float(npc.outline_width), 0.0001,
		"GunVisuals.outline_width (%.3f) must match the NPC rim (%.3f) — the ink is masked off the gun, so a sub-pixel hull rim leaves the weapon with NO outline"
			% [visuals.outline_width, npc.outline_width])
	assert_gte(float(visuals.outline_width), 1.0,
		"the view model's rim must be at least a visible pixel (outline_width 1.0 ≈ 1 px of the 792-wide screen)")
	npc.free()
	visuals.free()

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

func test_the_hull_rim_is_the_same_width_in_both_passes() -> void:
	# ⭐⭐ outline.gdshader runs in TWO viewports — the frame the player sees (the 3D buffer) and InkOutline's
	# actor mask, which renders at HALF that. Sizing the extrusion by VIEWPORT_SIZE therefore drew the rim
	# TWICE as wide in the mask, so the mask claimed a silhouette fatter than the visible one and the ink
	# stopped short of every actor. Measured: suppression reached 4 px past a visible actor whose rim was
	# 2 px; pinning the reference brought it to 2 px, exactly the rim. That 2 px of bare band hugged every
	# actor at every distance and traced each limb of a humanoid — the "scattered around the body" report.
	# Put VIEWPORT_SIZE back in the offset and the band returns, silently.
	var src := _read("res://resources/shaders/outline.gdshader")
	assert_true(src.contains("uniform float rim_reference_width"),
		"outline.gdshader must size its extrusion off a fixed reference width, not the viewport it happens to be drawn in")
	# Plain string work rather than a RegEx: a backslash class in a GDScript literal has to be double-
	# escaped, and getting that wrong is a PARSE error that takes the whole file out of the suite.
	var line := ""
	for raw in src.split("\n"):
		if raw.strip_edges().begins_with("vec2 offset ="):
			line = raw
			break
	assert_ne(line, "", "outline.gdshader must still compute a vec2 offset for the hull extrusion")
	assert_false(line.contains("VIEWPORT_SIZE"),
		"the extrusion must not divide by VIEWPORT_SIZE — that is what made the mask's rim twice the visible one")

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
	# the Settings side degrades to "always full strength" with no error anywhere.
	assert_true(Settings.get(&"ink_outline_intensity") != null,
		"Settings must expose ink_outline_intensity for InkOutline's per-frame poll")
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
	assert_almost_eq(float(params["concave_crease_strength"]), 1.0, 0.0001,
		"concave_crease_strength ships at 1.0 — the authored look is unchanged until a designer dials it")
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
