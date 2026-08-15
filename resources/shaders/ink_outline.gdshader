shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

// TRIED AND REVERTED 2026-08-13 — do not re-attempt without solving this first. `stencil_mode read,
// compare_not_equal, 1;` here (paired with a stencil write on outline.gdshader) was meant to replace the
// actor mask with an occlusion-correct test. It COMPILES and produces no error, but the suppression simply
// does not happen: every NPC came back double-inked. The quad is `depth_test_disabled`, which drops the
// depth-stencil attachment for this pipeline, so the stencil compare never runs — a silent no-op, which is
// the worst failure mode there is. Removing depth_test_disabled is not an option: this quad sits 1 m from
// the camera and relies on it to draw over the whole scene.
// The occlusion problem that motivated it is SOLVED as of 2026-08-13 — by the depth-compare mask, not by
// stencil. See the Actor exclusion block below and resources/shaders/actor_mask_resolve.gdshader.

// BORDERLANDS-STYLE INK PASS — a screen-space edge detect that draws ONE black line system over the
// WORLD. Actors — NPCs, props, the view model — are deliberately NOT inked: they keep their authored
// inverted-hull rims and are excluded per-pixel via the actor mask (see the Actor exclusion block).
//
// WHY SCREEN-SPACE AND NOT THE INVERTED HULL (resources/shaders/outline.gdshader):
// This project already HAS an inverted-hull outline, and it stays exactly where it is — it is the
// GAMEPLAY highlight (Throwable hover rim, the NPC combat outline, the look-at talk highlight; see
// TalkHelpers.make_outline_material). It is the wrong tool for "ink the whole world":
//   * It needs a second draw call per mesh, and it fights ps1_applier's surface overrides for the
//     material slot on every piece of level geometry.
//   * The func_godot brush mesh is UNWELDED (every face owns private vertices, see ps1.gdshader's
//     SEAM WARNING), so a normal-extruded hull SHATTERS along every hard edge instead of forming a
//     silhouette — the exact geometry this level is built from is its worst case.
//   * Extruding a room's interior walls puts the camera INSIDE the hull, which paints the screen black.
// Borderlands itself did not use hulls for the world either: its ink is a post-process depth/normal
// edge filter. That is what this shader is. One pass, no per-mesh authoring, nothing to keep in sync.
//
// THE DIVISION OF LABOUR (settled in playtest round 2): outline.gdshader's inverted hull owns the
// ACTORS — the clean colour-coded rim NPCs, props and the view model wore before this pass existed —
// and this pass owns the WORLD. They never stack: without the exclusion this pass edge-detects the
// actor's own opaque body and draws a line straddling that silhouette, which lands half on the hull's
// rim ring and half on the world — a smeared second outline hugging the clean one (the doubled-outline
// bug, twice). The hull is NOT what gets edge-detected: it is a transparent-pass material and writes no
// depth at all (measured — see actor_mask_resolve.gdshader; this header used to claim otherwise). The view model rides the same exclusion for free
// via its own render layer (ViewModelCamera.VIEW_MODEL_LAYER, culled by the mask camera).
//
// WHERE IT SITS IN THE FRAME: the quad is a child of the camera, so it draws inside the 3D pass —
// BEFORE ui.tscn's post_process.gdshader. That is deliberate: the lines get posterised, dithered and
// grained WITH the world instead of floating over it as crisp modern vector art. It also means the
// camera's far-DOF blurs distant ink together with the distant geometry it belongs to (we write no
// depth, so DOF reads the geometry's depth at our pixels).
//
// RENDERER REQUIREMENTS (all satisfied by this project, listed so a future change is a knowing one):
//   * Forward+ (project.godot config/features) — NORMAL_ROUGHNESS_TEXTURE is Forward+ only.
//   * The depth prepass must stay enabled (rendering/driver/depth_prepass/enable, engine default
//     true, not overridden here) — it is what fills the normal/roughness buffer. If it is ever
//     disabled the CREASE term degrades silently to nothing (a uniform buffer has no gradient, so
//     it simply stops finding edges) and only the silhouette term survives. No crash, just fewer lines.
//   * MSAA 3D is off, so the depth buffer needs no resolve.

// The depth buffer is the SILHOUETTE source; the normal buffer is the CREASE source. Both are point
// sampled — filtering a depth buffer averages across the very discontinuity we are looking for.
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, repeat_disable, filter_nearest;

// --- Line look -------------------------------------------------------------------------------------
uniform vec4 ink_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Master line alpha. InkOutline multiplies the authored value by the player's Options dial before
// pushing it here, so this uniform is already the LIVE strength — never the authored one.
uniform float ink_opacity : hint_range(0.0, 1.0) = 1.0;
// Line thickness in pixels OF THE 3D BUFFER, which is not the window: 396x216 window x viewport
// stretch 0.5 = 792x444, x rendering/scaling_3d/scale 2.0 = 1584x888 actually rendered. So 2.0 here is
// ~1 pixel of the 792-wide image the player sees, and the shipped 3.0 is ~1.5 — chosen by eye against a
// render probe, because 2.0 reads as a tasteful technical edge and Borderlands' ink is bolder than that.
// Uniform in screen space by construction: a line does not get thinner with distance, which is the
// whole point of the comic-ink look. (Note this is the SHADER's fallback — the value actually used is
// pushed by InkOutline, whose own export is the one to edit.)
uniform float width_px : hint_range(0.0, 8.0) = 3.0;

// --- Silhouette (depth) term -----------------------------------------------------------------------
// A neighbour counts as "a different object" when its depth differs from the reference by more than
// this FRACTION of the reference depth. Relative, not absolute, so a 2 cm step reads as an edge at
// arm's length while the far skyline does not dissolve into black mush.
uniform float depth_threshold : hint_range(0.001, 0.5) = 0.035;
// Floor on the reference depth used for that threshold, in metres. Without it the view model — 20 cm
// from the lens — gets a threshold of half a millimetre and every screw and panel gap on the gun
// turns into a line. Raise to calm the gun down, lower to let it show more internal detail.
// Only the THRESHOLD is clamped; the distance fade below still uses the true depth.
uniform float min_depth_reference : hint_range(0.01, 4.0) = 0.35;
// Grazing-angle relief. A floor seen almost edge-on changes depth enormously from pixel to pixel
// without there being any edge there, which would carpet the ground in false lines. We widen the
// threshold by 1/|N.z| (how much the surface is turned away from the lens) and cap it here.
// N.z is the cheap approximation of N.V — exact at screen centre, off by the pixel's angle from the
// axis at the corners (~1.4x at this 90-degree FOV), which is well inside the tolerance's own slack.
// The floor/wall junction people expect to see is NOT lost to this: two touching surfaces have no
// depth discontinuity at all, so that line is drawn by the crease term below, not this one.
uniform float grazing_tolerance : hint_range(1.0, 32.0) = 8.0;

// --- Crease (normal) term --------------------------------------------------------------------------
// The interior lines: where two surfaces meet at an angle but are flush in depth (wall corners, the
// floor/wall junction, the facets of a prop). 0 = silhouettes only.
uniform float crease_strength : hint_range(0.0, 2.0) = 1.0;
// How sharp a normal change has to be before it becomes a line. Higher = only hard corners.
uniform float crease_threshold : hint_range(0.05, 2.0) = 0.4;

// --- Distance fade ----------------------------------------------------------------------------------
// Ink eases out across this window (metres of view depth) so the far skyline does not become a black
// smear once the post-process pixelation collapses it. Roughly tracks ps1.gdshader's own far fade and
// the camera's 30 m DOF, so the whole far field softens together rather than in three separate steps.
uniform float fade_start : hint_range(0.0, 500.0) = 40.0;
uniform float fade_end : hint_range(0.0, 1000.0) = 90.0;

// --- Fog match ---------------------------------------------------------------------------------------
// Beer-Lambert extinction (per metre) matching the level's fog, pushed live by InkOutline from the
// WorldEnvironment (volumetric_fog_density x its fog_match knob). THE fix for ink glowing through fog:
// this world is lit almost entirely by volumetric fog, so geometry contrast decays as exp(-density*d)
// — but this quad renders fog_disabled at 1 m from the lens, so the engine's own fog can never touch
// the lines (they attenuate by OUR pixel's depth, ~1 m, not the inked geometry's). Without this term a
// crisp black line floats over buildings the fog has already swallowed, advertising geometry the
// player cannot actually see. exp(-sigma*d) makes the ink lose contrast at exactly the rate the world
// does. 0 = no fog anywhere (the shader's own fallback; InkOutline overwrites it every frame).
uniform float fog_extinction : hint_range(0.0, 1.0) = 0.0;

// --- Actor exclusion ---------------------------------------------------------------------------------
// ACTORS ARE NOT INKED. NPCs, props and the view model carry their own authored look — the inverted-hull
// rim (outline.gdshader): a clean uniform shell, colour-coded by disposition, that the user signed off
// long before this pass existed. Ink on top of it reads as a smeared double line: the actor's opaque body
// is a depth discontinuity, so this pass draws a line straddling that silhouette and lands it half on the
// rim ring and half on the world, ringing every rimmed actor in black. So InkOutline renders everything that must stay ink-free (the ACTOR_INK_MASK_LAYER
// render layer + the view-model layer) into a small mask SubViewport sharing the main world, and
// any pixel that mask covers is DISCARDED here before an edge is even computed. use_actor_mask is
// pushed true only once that pass is actually built, so an unbound sampler is never consulted.
// That mask is a SECOND SCENE RENDER, so every viewport frill is stripped off it and it can be rendered
// below this buffer's resolution (InkOutline._strip_mask_viewport / mask_resolution) — only its alpha and
// the resolve pass's two encoded channels are ever read, never its colour as colour. What must NOT follow from that is sizing the suppression below off the mask:
// see the exclusion block in fragment() for the halo that produces.
// filter_LINEAR, not nearest: the mask renders below this buffer's resolution, and point-sampling it
// turns its silhouette into a blocky stencil whose edge lands up to a whole mask texel outside the
// actor. Linear makes it a COVERAGE FIELD instead — alpha crosses 0.5 at the true silhouette with
// sub-texel accuracy, which is what lets the suppression below stay honest at any mask resolution.
uniform sampler2D actor_mask : repeat_disable, filter_linear;
uniform bool use_actor_mask = false;

// --- Occlusion: the SAME texture, read for the depth the resolve pass stamped into it ------------------
// ⭐ THE SOFT-WALLHACK FIX (2026-08-13). The mask pass renders only actors, so nothing in it can occlude
// them: an NPC behind a wall used to stamp its full silhouette into the mask and bite that shape out of
// every ink line it overlapped. Long straight lines — stair nosings, building corners — came away with
// clean circles punched through them wherever somebody stood on the other side, which read as sensing
// people through walls rather than as an outline effect. It was never NPC-specific: every hull-rimmed
// thing on the mask layer did it (thrown and carried props, gibs, ragdolls).
// The fix gives the mask a DEPTH channel — actor_mask_resolve.gdshader, a quad inside the mask viewport
// that reads that viewport's depth buffer and stamps it into the mask's colour — and this pass then asks
// the only honest question available: at this pixel, is the actor the mask claims AT the depth the player
// is actually looking at, or is it behind whatever is? Behind = the mask has no business suppressing ink
// here, and the world's line is drawn straight through.
// Sampled filter_NEAREST from the same texture as actor_mask above (Godot binds one texture per uniform
// with that uniform's own sampler, so the two hints coexist). Nearest is deliberate: linear would blend
// an actor's depth with the empty far value across its own silhouette and invent a "farther" actor at
// every edge, which reads as occluded and puts the ink line straight back onto the rim.
uniform sampler2D actor_mask_data : repeat_disable, filter_nearest;
// Off = the pre-fix behaviour, every masked actor suppresses ink whether or not it can be seen. Kept as a
// switch because this is a LOOK change: it is the one knob that turns the whole occlusion test off.
uniform bool use_mask_occlusion = true;
// ⭐ KEEP IDENTICAL TO actor_mask_resolve.gdshader — one encodes, this one compares against it, and a
// drift between the two makes every comparison nonsense. Both are pushed from InkOutline's own constants
// so they cannot disagree at runtime; these literal defaults exist only so the shader stands alone.
uniform float mask_depth_near = 0.1;
uniform float mask_depth_far = 300.0;
// How much NEARER (in encoded units, so a fixed FRACTION of the depth) the world has to be before the
// actor behind it stops suppressing ink. One 8-bit step of the encoding is ~3% of the depth, so the
// shipped 0.012 is about four steps — comfortably past quantisation and past the half-resolution mask's
// sampling wobble, while still catching anything more than ~4% of its own distance behind a wall.
// LOWER = catches thinner cover, at the risk of an actor at grazing contact with the floor flickering
// back to a doubled line. HIGHER = safer, but leaves a halo around actors tucked close behind cover.
uniform float mask_occlusion_bias = 0.012;
// How far (in pixels OF THIS BUFFER) to look for the body's depth when a covered pixel has none of its
// own — the hull rim, which writes no depth at all. See searched_depth(). Generous is CHEAP here: unlike
// spreading depth in the resolve pass, widening this search cannot widen the mask's coverage, so it
// costs taps and nothing else. Must out-reach the widest rim on screen: the rim is `outline_width * 2`
// pixels of the MASK viewport, which at the shipped half-resolution mask is `outline_width * 4` of this
// one, so the project's widest authored rim (2.0) spans 8 px here.
uniform float mask_rim_search_px = 12.0;

// Stand-in depth for "nothing was drawn here" (sky / cleared far plane). Big enough that any real
// geometry beside it registers as a discontinuity, finite so it can never poison the arithmetic.
const float SKY_DEPTH = 1.0e6;

void vertex() {
	// Write clip space DIRECTLY from the unit QuadMesh's own corners (-0.5..0.5 -> NDC -1..1), so the
	// quad covers exactly the screen no matter what transform, scale, FOV or aspect it is handed. The
	// node's placement is then free to mean something else entirely — InkOutline parks it a metre out
	// purely to control TRANSPARENCY SORT ORDER (see that script). z = 0, w = 1 is inside the valid
	// clip range under both the GL (-w..w) and Vulkan/D3D12 (0..w) conventions, and depth_test_disabled
	// means the value is never compared anyway.
	// (Frustum culling happens BEFORE this runs and uses the node's real AABB, which is why InkOutline
	// also sets a large extra_cull_margin — a quad that gets culled never reaches this line.)
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

// View-space distance in metres for a screen pixel, or SKY_DEPTH where nothing was drawn.
// INV_PROJECTION_MATRIX carries whatever depth convention the driver is using, so this needs no
// reverse-Z special case; the guard is only against a degenerate w (an infinite far plane would
// divide by zero at the far value) and against NaN, which the "not greater than zero" test catches
// where a plain <= 0.0 would not.
float linear_depth(vec2 uv, mat4 inv_proj) {
	float raw = texture(depth_tex, uv).x;
	vec4 view = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	float d = -view.z / view.w;
	if (!(d > 0.0) || d > SKY_DEPTH) {
		return SKY_DEPTH;
	}
	return d;
}

// View-space normal for a screen pixel, decoded from the normal/roughness buffer's 0..1 packing.
// Returns a zero-length vector where the buffer holds no usable normal (sky, or a depth prepass that
// never ran) — callers test the length rather than trusting the direction.
vec3 view_normal(vec2 uv) {
	vec3 n = texture(normal_tex, uv).xyz * 2.0 - 1.0;
	return (dot(n, n) < 0.01) ? vec3(0.0) : n;
}

// ⭐ KEEP IDENTICAL TO actor_mask_resolve.gdshader's copy — that shader writes the value this one reads.
// One 8-bit channel has to cover the whole playable range, so depth is stored LOGARITHMICALLY: every step
// is the same FRACTION of the depth (~3% across this window) rather than the same number of metres, which
// is the right currency for a test that only asks "is the world meaningfully nearer than the actor?".
// Near maps to 1.0 and far to 0.0.
float encode_actor_depth(float d, float near_m, float far_m) {
	float lo = max(near_m, 0.001);
	float hi = max(far_m, lo * 1.001);
	return 1.0 - clamp(log(clamp(d, lo, hi) / lo) / log(hi / lo), 0.0, 1.0);
}

// The mask's encoded depth at `uv` if the resolve pass claimed that pixel, else -1. It writes its marker
// (B) and full alpha only where it had real depth to offer, so this is the "can I trust this?" test.
float claimed_depth(vec2 uv) {
	vec4 m = texture(actor_mask_data, uv);
	return (m.b >= 0.5 && m.a >= 0.99) ? m.g : -1.0;
}

// ⭐⭐ THE RIM RING, and why this search exists. The hull (outline.gdshader) is a TRANSPARENT material —
// it assigns ALPHA in a branch, and Godot flags a material `uses_alpha` from that assignment EXISTING
// rather than from the branch being taken — so it writes NO depth, and neither the depth texture nor the
// screen texture (both PRE-transparent snapshots) can see it. An actor's inflated rim therefore reaches
// the mask's COVERAGE but not its DEPTH: a ring of pixels that say "somebody is here" and cannot say how
// far. Left unresolved those pixels keep their ink suppressed while the body's is released, so a hidden
// actor stops punching a solid hole in the world's lines and starts punching an OUTLINE of itself. The
// user's words, and the whole reason for this function: "it's like an O shape around it."
//
// So when a pixel has no depth of its own, look OUTWARD for the body it belongs to. Doing it here rather
// than in the resolve pass is the point: the resolve pass could only spread depth by ALSO spreading
// COVERAGE — and coverage is suppressed ink, i.e. a halo — whereas this reads a wider neighbourhood and
// changes nothing about how much of the frame the mask claims. The radius can be generous for free.
//
// MAX, not min or nearest-found: the largest encoding is the NEAREST actor, which biases every ambiguous
// pixel toward "still visible, keep suppressing". That is the safe direction — see actor_visibility.
// `r` is the search radius already converted to UV units by the caller — VIEWPORT_SIZE is a fragment()
// built-in and is NOT reachable from a helper function in Godot's shading language (the whole shader
// fails to compile with "Unknown identifier in expression", which headless never notices).
float searched_depth(vec2 uv, vec2 r) {
	float best = claimed_depth(uv);
	if (best >= 0.0) {
		return best;
	}
	// Two rings rather than one: the inner ring catches thin rims, the outer catches the widest authored
	// one, and neither has to know which is in play. Written out longhand — a shading-language slip is
	// invisible to the test suite (headless never compiles a shader), so this file prefers the boring
	// spelling.
	for (int i = 0; i < 2; i++) {
		vec2 s = (i == 0) ? r : r * 0.5;
		vec2 d = s * 0.70710678;
		best = max(best, claimed_depth(uv + vec2(s.x, 0.0)));
		best = max(best, claimed_depth(uv - vec2(s.x, 0.0)));
		best = max(best, claimed_depth(uv + vec2(0.0, s.y)));
		best = max(best, claimed_depth(uv - vec2(0.0, s.y)));
		best = max(best, claimed_depth(uv + vec2(d.x, d.y)));
		best = max(best, claimed_depth(uv + vec2(-d.x, d.y)));
		best = max(best, claimed_depth(uv + vec2(d.x, -d.y)));
		best = max(best, claimed_depth(uv + vec2(-d.x, -d.y)));
	}
	return best;
}

// 1.0 = the mask's actors still suppress ink here; 0.0 = the world in front of them is what the player is
// actually looking at, so the mask has no business speaking for this pixel.
//
// EVERY early return hands back 1.0, i.e. the pre-fix behaviour. That direction is deliberate and
// load-bearing: suppressing ink around a visible actor costs at most a pixel of line, while failing to
// suppress it puts a second black outline around an actor the hull already outlines — the complaint this
// whole system exists to answer. The test only ever REMOVES suppression where it has positive evidence,
// and anything it cannot vouch for is left exactly as it was (a prop faded out through
// GeometryInstance3D.transparency, an actor past the encoding window, a frame before the mask is built).
float actor_visibility(vec2 uv, float world_depth, vec2 search_r) {
	if (!use_mask_occlusion) {
		return 1.0;
	}
	float e_actor = searched_depth(uv, search_r);
	if (e_actor < 0.0) {
		return 1.0;
	}
	// Both sides in encoded space, so the tolerance is a fraction of the distance rather than a fixed
	// number of metres — the mask sits at half this buffer's resolution, and a metre of slack at 40 m is
	// the same sampling wobble as a centimetre at arm's length.
	float e_world = encode_actor_depth(world_depth, mask_depth_near, mask_depth_far);
	return (e_world - e_actor > mask_occlusion_bias) ? 0.0 : 1.0;
}

void fragment() {
	// Roberts cross: the two diagonals of a square centred on this pixel. Four taps (vs Sobel's eight)
	// and the response straddles the edge evenly, so a line lands centred on the boundary rather than
	// biased to one side of it. Half-width offsets, so the drawn line is `width_px` wide overall.
	vec2 o = (max(width_px, 0.0) * 0.5) / VIEWPORT_SIZE;
	vec2 tl = SCREEN_UV + vec2(-o.x, -o.y);
	vec2 tr = SCREEN_UV + vec2(o.x, -o.y);
	vec2 bl = SCREEN_UV + vec2(-o.x, o.y);
	vec2 br = SCREEN_UV + vec2(o.x, o.y);

	// The five depth taps now come FIRST, because the actor exclusion below needs to know what the player
	// is actually looking at before it can decide whether the mask's actor is in front of it or behind.
	// (They used to sit after an early discard. The discard is still here and still skips the expensive
	// half — the four crease taps and all the edge maths — it just no longer skips these five.)
	float d_c = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float d_tl = linear_depth(tl, INV_PROJECTION_MATRIX);
	float d_tr = linear_depth(tr, INV_PROJECTION_MATRIX);
	float d_bl = linear_depth(bl, INV_PROJECTION_MATRIX);
	float d_br = linear_depth(br, INV_PROJECTION_MATRIX);

	// Actor exclusion (see the uniform block above). Two separate questions, and conflating them
	// is what put a visible HALO around every actor:
	//   `here` — is THIS pixel a VISIBLE actor? Then it is never inked, at any opacity (a carried prop
	//     fades to GeometryInstance3D.transparency, so its mask alpha is well under 1 and must still
	//     count). actor_coverage answers the "visible" half by comparing the mask's depth against d_c.
	//   `near` — is a visible actor's edge within HALF A LINE of this pixel? Then the line the edge
	//     detect is about to draw would straddle that actor's silhouette, which is the doubled outline
	//     the hull already owns. Fade it out.
	// The occlusion verdict is computed ONCE, at the centre, and applied to all five taps. They sit within
	// half a line-width of each other — under two pixels — and "is this actor behind the world?" cannot
	// meaningfully change across that, while the outward rim search below is much too expensive to run
	// five times. Evaluating it at the centre works even where the centre has no coverage: the search
	// finds the neighbouring actor and answers for it.
	// `near` is the STRONGEST of the four half-width taps, not their sum, and the offsets are the LINE's
	// half-width `o` — never the mask's texel size. The first version did both of those wrong (summed
	// five taps against a 0.05 threshold, offset by a whole mask texel), which scaled the suppression
	// window off the MASK RESOLUTION instead of off width_px: at a half-resolution mask it erased world
	// ink 3 px out from every actor, so actors sat in a bare halo you could spot people by — including
	// distant ones, where a fixed screen-space window is enormous next to the actor itself. Suppression
	// must always be the width of the line being suppressed.
	float actor_here = 0.0;
	float actor_near = 0.0;
	if (use_actor_mask) {
		float vis = actor_visibility(SCREEN_UV, d_c, max(mask_rim_search_px, 0.0) / VIEWPORT_SIZE);
		actor_here = texture(actor_mask, SCREEN_UV).a * vis;
		actor_near = max(texture(actor_mask, tl).a, texture(actor_mask, tr).a);
		actor_near = max(actor_near, max(texture(actor_mask, bl).a, texture(actor_mask, br).a));
		actor_near = max(actor_near, texture(actor_mask, SCREEN_UV).a) * vis;
		if (actor_here > 0.25 || actor_near >= 0.5) {
			discard;
		}
	}

	// Reference depth = the NEAREST of the five taps, not the centre one. Two reasons, both visible:
	// a sky pixel next to a rooftop would otherwise be thresholded (and faded) as if it were 4 km away
	// and the roofline would only get inked on its inner half; and a near object against a far wall
	// would be judged by the wall's depth instead of its own.
	float d_ref = min(d_c, min(min(d_tl, d_tr), min(d_bl, d_br)));

	// Grazing relief, from the centre normal. A missing normal (sky, or no prepass) means no relief
	// rather than maximum relief — the inverse would suppress every silhouette in the frame.
	vec3 n_c = view_normal(SCREEN_UV);
	float facing = (dot(n_c, n_c) > 0.0) ? abs(n_c.z) : 1.0;
	float slope = clamp(1.0 / max(facing, 0.001), 1.0, max(grazing_tolerance, 1.0));

	// Silhouettes. Both diagonals summed, expressed as a fraction of the reference depth so the test
	// is scale-free, then ramped over [t, 2t] instead of hard-stepped — the soft shoulder is what
	// keeps the line from crawling as the camera moves, and it survives the posterise downstream.
	float depth_diff = abs(d_tl - d_br) + abs(d_tr - d_bl);
	float rel = depth_diff / max(d_ref, min_depth_reference);
	float t = depth_threshold * slope;
	float edge = smoothstep(t, t * 2.0, rel);

	// Creases. Skipped entirely at zero strength so the four extra taps are not paid for when a
	// silhouette-only look is what is wanted.
	if (crease_strength > 0.0) {
		vec3 n_tl = view_normal(tl);
		vec3 n_tr = view_normal(tr);
		vec3 n_bl = view_normal(bl);
		vec3 n_br = view_normal(br);
		float normal_diff = length(n_tl - n_br) + length(n_tr - n_bl);
		float crease = smoothstep(crease_threshold, crease_threshold * 2.0, normal_diff);
		edge = max(edge, crease * crease_strength);
	}

	// Fade on the TRUE reference depth (unclamped), so the near floor under min_depth_reference is
	// unaffected by it. Guard the degenerate window: smoothstep with end <= start is undefined.
	float f_end = max(fade_end, fade_start + 0.001);
	edge *= 1.0 - smoothstep(fade_start, f_end, d_ref);
	// Fog match (see fog_extinction above): the ink dissolves at the same exponential rate the fog
	// swallows the geometry it is drawn on. Multiplies WITH the window fade — in a fogged level the
	// fog term dominates long before the window does; in a fogless one the window is the backstop.
	edge *= exp(-fog_extinction * d_ref);
	// Antialias the actor exclusion's boundary. Everything at coverage >= 0.5 was discarded above, so
	// this only feathers the last sliver up to it — DELIBERATELY a narrow window (0.4..0.5), not a ramp
	// down to zero coverage. A wide ramp is a halo by another name: it fades ink out over most of a mask
	// texel, which at a half-resolution mask is a visible bare band hugging every actor. Keep the
	// suppression's WIDTH pinned to the line (`o`, above) and let this only soften its edge.
	edge *= 1.0 - smoothstep(0.4, 0.5, actor_near);

	ALBEDO = ink_color.rgb;
	ALPHA = clamp(edge, 0.0, 1.0) * ink_color.a * ink_opacity;
}
