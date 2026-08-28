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
// Line thickness in pixels of WHATEVER BUFFER THIS PASS RENDERS IN (VIEWPORT_SIZE — never the window).
// Under RETRO that buffer is 396x216 window x viewport stretch 0.5 = 792x444, x
// rendering/scaling_3d/scale 2.0 = 1584x888 actually rendered, so 2.0 here is ~1 pixel of the 792-wide
// image the player sees, and the shipped 3.0 is ~1.5 — chosen by eye against a render probe, because
// 2.0 reads as a tasteful technical edge and Borderlands' ink is bolder than that. Under HIGH FIDELITY
// the buffer is native-sized and the value arrives pushed native_scale()-compensated by InkOutline, so
// the on-screen thickness matches RETRO's. Uniform in screen space by construction: a line does not get
// thinner with distance, which is the whole point of the comic-ink look. (Note this is the SHADER's
// fallback — a RETRO-unit literal, kept a literal per the white-panel guard; the value actually used is
// pushed by InkOutline every visible frame, whose own export is the one to edit.)
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
// ⭐⭐ CONTACT MERGE — how far apart (METRES) two surfaces have to be at an edge before that edge counts
// as a real silhouette rather than a JOIN between two pieces that are touching. 0 = off, i.e. the
// pre-2026-08-18 behaviour where every depth step draws a line no matter what is behind it.
//
// THE ASK, in the user's own words: ink the outside of a solid, "not where the two actually are
// touching". A level built from boxes is full of pieces that meet — a step on a step, a slab on a wall,
// a kerb against the road — and the silhouette term drew the boundary at every one of them, so a flight
// of stairs read as a stack of separately outlined slabs instead of one stepped solid. That is the NOW
// half of the sketch; the WANT half is the union.
//
// THE TEST, and why it is in metres rather than pixels: at an edge pixel the two Roberts taps land on
// two different surfaces, and the 3D distance between those two points IS how far apart the two pieces
// are along the view ray. A step's far surface starts at the foot of its riser, so the gap is the riser
// height (~0.5 m here) however grazing the view; a box standing on the floor gives its own height; a
// building against a building 10 m behind gives 10 m; anything against the SKY gives the far plane. So
// "are they touching?" is one distance, measured from the depth buffer, with no extra pass and nothing
// to author per object. Surfaces closer than this merge into one solid, and the shoulder runs to 2x so
// a piece near the threshold fades rather than pops as the camera moves.
//
// ⭐ This is a LOOK knob with teeth: raise it and genuinely separate things start reading as one mass
// (a crate a metre in front of a wall loses the line between them). The default merges this level's
// authored 0.5 m module — its stairs, kerbs and slab-on-slab joins — and keeps everything past ~2 m.
// It only ever REMOVES lines, and only from the DEPTH term; creases are the concave dial's business.
uniform float contact_merge_m : hint_range(0.0, 8.0) = 1.0;

// --- Crease (normal) term --------------------------------------------------------------------------
// The interior lines: where two surfaces meet at an angle but are flush in depth (wall corners, the
// floor/wall junction, the facets of a prop). 0 = silhouettes only.
uniform float crease_strength : hint_range(0.0, 2.0) = 1.0;
// How sharp a normal change has to be before it becomes a line. Higher = only hard corners.
uniform float crease_threshold : hint_range(0.05, 2.0) = 0.4;
// ⭐⭐ SEAM MERGE — the narrowest feature, in pixels OF THIS BUFFER (pushed native_scale()-compensated
// by InkOutline, like width_px, so the authored knob keeps its RETRO-buffer unit), that still earns a
// crease line: the confirming taps sit exactly this far either side of the pixel, so a face narrower
// than this cannot hold one and its creases merge into the surface around it. 0 = off, i.e. the
// pre-2026-08-18 behaviour where ANY normal change draws a line.
//
// THE PROBLEM IT SOLVES, in the user's own picture: a solid built from several boxes should be inked as
// ONE solid, not as its parts. Flush and interpenetrating boxes already are — an interior face is behind
// the union's surface, so a screen-space pass cannot see it, and a perfect butt-join has no depth step
// and no normal change either (measured: two L-arms sharing a face come out as one clean silhouette).
// What breaks it is a box a couple of CENTIMETRES out of line. That misalignment leaves a sliver of
// perpendicular face along the join — sub-pixel wide, invisible in the art, and a FULL 90-degree normal
// change to the crease term, which had no notion of how big a feature is. One continuous surface came
// away split by a faint dotted line that crawls as the camera moves. On the shipped map that is the
// authored 6 cm plank trims seen edge-on and a 4 mm decal-plate brush; on hand-placed blockout it is
// every join.
//
// THE TEST: a genuine corner has different normals on both sides of it NO MATTER HOW FAR OUT YOU LOOK —
// walk a few pixels either way from a building corner and you are still on the two walls. A misalignment
// sliver has the SAME surface on both sides a few pixels out; the only place the normals differ is the
// sliver itself. So the crease is re-measured on wider crosses and may only ever be REDUCED by what they
// find: the narrow pass decides where the line sits (so it stays width_px wide, centred on the edge), the
// wide pass decides whether the change PERSISTS. Nothing here is world-scale, deliberately — a 4 cm kerb
// underfoot spans plenty of pixels and keeps its line, the same kerb at 40 m does not, and that is the
// right answer twice: at 40 m it was a crawling artefact, not a detail. The documented collateral: a
// reveal, trim or stair tread narrower than this on screen loses its interior lines (silhouettes stay).
//
// ⭐ THIS TERM ONLY EVER REMOVES LINES, which is the opposite of the fail-safe direction the actor mask
// is built around — so it is a knob with an off position, and the default is the smallest reach that
// clears the artefact rather than the biggest that looks tidy. Costs 8 extra normal taps, and only on
// pixels the narrow pass already called a crease.
uniform float crease_min_feature_px : hint_range(0.0, 16.0) = 4.0;
// ⭐ CONCAVE vs CONVEX. A crease is CONVEX where the two surfaces fold AWAY from the viewer (a building's
// outside corner, the nosing of a step, the top edge of a wall) and CONCAVE where they fold TOWARD it
// (the floor/wall junction, the inside corner of an L, the line where a slab sits on a wall). Both are
// 90-degree normal changes and the crease term cannot tell them apart by normals alone. On a level built
// from boxes every "junction between two pieces" is a concave crease, so this is the dial for how much
// the pieces read as ONE solid: 1.0 draws every junction (the shipped look), 0.0 draws only the convex
// edges and the silhouettes, so a slab on a wall or a step against a riser shows no line where they meet.
// Convexity is read from the same taps the crease uses: the pair whose normals differ most is the crease's
// own, and the sign of dot(dN, dP) — do the normals diverge along the offset (convex) or converge
// (concave) — is the standard test; see the crease block. Soft, not a switch, so a pixel that sits right
// on the ambiguity does not pop.
uniform float concave_crease_strength : hint_range(0.0, 1.0) = 1.0;

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
// actor behind it stops suppressing ink. This used to be the thing that limited the whole test: at one
// 8-bit channel a step was ~3% of the distance, the bias had to clear a few of them, and an NPC needed
// to stand a FULL METRE behind a wall at 6 m before anything happened — which is why hidden NPCs still
// showed faintly indoors. The depth is now packed across two channels (~0.01% precision) and the tight
// gather in searched_depth() cancels the sampling noise, so what is left for this to cover is real
// geometry. Measured with a gap sweep at 0.003: an actor is recognised as hidden with as little as 2 cm
// of clear air behind cover, at 6 m out.
// LOWER buys nothing measurable now — the sweep is flat below this. HIGHER goes back to letting actors
// tucked close behind cover keep their halo.
uniform float mask_occlusion_bias = 0.003;
// How far (in pixels OF THIS BUFFER) to look for the body's depth when a covered pixel has none of its
// own — the hull rim, which writes no depth at all. See searched_depth(). Generous is CHEAP here: unlike
// spreading depth in the resolve pass, widening this search cannot widen the mask's coverage, so it
// costs taps and nothing else. Must out-reach the widest rim on screen: the rim is a constant FRACTION
// of the image (outline.gdshader's fixed rim_reference_width), so in this buffer it spans
// `outline_width * 2 * (buffer width / mask width)` = `outline_width * 2 * render_scale` px — x4 at the
// RETRO render_scale 2.0, so the project's widest authored rim (2.0) spans 8 px here. The extra factor
// the buffer gains under HIGH FIDELITY is supplied by InkOutline, which pushes this value
// native_scale()-compensated (and sizes the mask viewport by the same factor, keeping the ratio above).
uniform float mask_rim_search_px = 12.0;

// HULL -> INK HANDOFF window, PRE-ENCODED into the mask's log depth space by InkOutline (from its
// hull_handoff_near_m / hull_handoff_far_m exports through the same encode_actor_depth below, so the
// comparison against searched_depth() is apples to apples). Encoded depth DECREASES with distance, so
// e_near > e_far. Nearer than near_m the hull rim owns the actor and this pass suppresses its ink over
// them (the pre-handoff behaviour, verbatim); farther than far_m the actor is inked exactly like world
// geometry — at a dozen pixels tall the mask's per-pixel verdicts degrade (it renders COARSER LODs whose
// silhouette no longer matches the main pass, spraying suppression holes as black fragments) while the
// screen-space edge detect stays clean at any range, and outline.gdshader's rim_distance_cap thins the
// hull away over the same span. The literal defaults (full window) keep an un-driven material sensible;
// the script always overwrites them.
uniform float hull_handoff_e_near = 1.0;
uniform float hull_handoff_e_far = 0.0;

// ⭐⭐ THE OUTLINE RING — the screen-space pass that replaced the inverted-hull rim EVERYWHERE (the shell
// out-thickened the Lego limbs past a few metres and shattered into confetti; the ring is constant
// PIXEL width at any distance by construction, the property no shell geometry can deliver). Retired for
// NPCs 2026-08-25 and for every remaining consumer — props, gibs, corpses, the look-at hover, the
// first-person view model — on 2026-08-27, when resources/shaders/outline.gdshader was DELETED.
// The tint buffer is InkOutline's second SubViewport: invisible flat duplicates encode per-fragment
// R+G = log depth (the actor_mask_resolve two-byte pack), B = id / 16, A = coverage — see
// resources/shaders/ink_tint.gdshader. filter_nearest is load-bearing: interpolated depth bytes or ids
// blended between two adjacent actors are both meaningless.
uniform sampler2D actor_tint : repeat_disable, filter_nearest;
uniform bool use_actor_tint = false;
// Ring width in pixels OF THIS BUFFER (the width_px unit; InkOutline pushes it px-unit-compensated).
uniform float highlight_width_px = 2.0;
// The id -> color LUT. Alpha scales the ring's strength. Neutral is BLACK: everything wearing a ring is
// excluded from the world ink, so the ring is its ONLY outline and a bystander (or a crate, or your own
// gun) should read exactly like the classic black rim did.
//   1 hostile   2 friendly   3 companion   4 neutral (actor black)
//   5 prop (reuses neutral)  6 claimed prop (reuses companion blue — the blue Claimable authors)
//   7..8 the CONTINUOUS ENGAGED-HOSTILE band (see the ring branch): hostile color, with the fraction
//        past 7 flooring the close-range bloom so a locked-on enemy reads full red at any distance
//   9 look-at / pickup HOVER  10 view model
uniform vec4 highlight_hostile : source_color = vec4(0.9, 0.1, 0.1, 1.0);
uniform vec4 highlight_friendly : source_color = vec4(0.1, 0.8, 0.2, 1.0);
uniform vec4 highlight_companion : source_color = vec4(0.15, 0.45, 1.0, 1.0);
uniform vec4 highlight_neutral : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// ⭐ The HOVER white (id 9) — "you are looking at this and Interact will do something". It replaced the
// per-component `highlight_color` the hull carried on Talkable / DialogueNPC / LookAtInteractable /
// Throwable: the ring resolves ONE id to ONE LUT slot, so the hover colour is now global and tuned here.
// Those components keep their `highlight_color`/`highlight_width` exports as the VISIBILITY switch they
// already doubled as (alpha 0 or width 0 = this one gets no hover outline — the shipping ATM).
uniform vec4 highlight_hover : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// ⭐ The VIEW MODEL (id 10) — your own weapon and first-person body, drawn on ViewModelCamera's layer.
// A slot of its own rather than reusing neutral so the gun's line stays tunable against the world's
// without touching combat colours (GunVisuals.outline_color used to own this and no longer exists).
uniform vec4 highlight_view_model : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// CLOSE-RANGE COLOR BLOOM window (InkOutline.highlight_color_near_m/far_m, pushed PRE-ENCODED): the
// ring is the neutral black at range and blends to the disposition color as the ACTOR closes — full
// color nearer than the near threshold, pure black past the far one. Encoded depth decreases with
// distance, so e_near > e_far and closeness = smoothstep(e_far, e_near, e). Neutral (id 4) is a fixed
// point of the mix, so bystanders stay black at every distance with no special case.
// ⭐ ONLY the DISPOSITION ids bloom (1..4 and the 7..8 band). A prop, a hover and the view model are not
// dispositions — they paint their LUT colour flat at every range, which is also what makes the hover
// white read the same whether you are looking at a pistol on the floor or a car across the street.
uniform float highlight_e_color_near = 1.0;
uniform float highlight_e_color_far = 0.0;

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

// View-space POSITION for a screen pixel (metres, camera at the origin, -Z forward), or a point at
// SKY_DEPTH straight down the pixel's ray where nothing was drawn. INV_PROJECTION_MATRIX carries whatever
// depth convention the driver is using, so this needs no reverse-Z special case; the guard is only
// against a degenerate w (an infinite far plane would divide by zero at the far value) and against NaN,
// which the "not greater than zero" test catches where a plain <= 0.0 would not.
vec3 view_pos(vec2 uv, mat4 inv_proj) {
	float raw = texture(depth_tex, uv).x;
	vec4 view = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	float d = -view.z / view.w;
	if (!(d > 0.0) || d > SKY_DEPTH) {
		// Keep the ray's DIRECTION so the convexity test below still has a sane offset to compare against
		// when one tap is sky, and scale it so -z is EXACTLY SKY_DEPTH (linear_depth's contract; two sky
		// pixels must read as the same depth, not as a slope).
		vec3 dir = (abs(view.w) > 1.0e-12) ? view.xyz / view.w : vec3(0.0, 0.0, -1.0);
		if (!(dir.z < -1.0e-6)) {
			dir = vec3(0.0, 0.0, -1.0);
		}
		return dir * (SKY_DEPTH / -dir.z);
	}
	return view.xyz / view.w;
}

// View-space distance in metres for a screen pixel, or SKY_DEPTH where nothing was drawn.
float linear_depth(vec2 uv, mat4 inv_proj) {
	return min(-view_pos(uv, inv_proj).z, SKY_DEPTH);
}

// View-space normal for a screen pixel, decoded from the normal/roughness buffer's 0..1 packing.
// ⭐ SKY IS NOT ZERO-LENGTH — measured 2026-08-18 by a probe reading this buffer the way this function
// does: the target is cleared to 0 and the engine's decode normalises (-1,-1,-1), so an undrawn pixel
// comes back as the unit junk normal (-0.577, -0.577, -0.577), and the zero-length branch below is dead
// on this driver. It is kept as a guard against a buffer that really is empty (no depth prepass), which
// is the one case it was written for. Two consequences worth knowing: sky reads as a DIFFERENT surface
// from anything real, so a crease that runs up to a silhouette keeps its line (good), and the seam merge
// cannot clean a sliver within a tap's reach of a silhouette (a wide tap on sky votes "corner").
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
// ⭐ The depth is packed across TWO bytes — G coarse, R fine — because one byte spends a step every ~3%
// of the distance, and that alone kept an NPC standing less than a metre behind a wall from registering
// as hidden. KEEP THIS DECODE IN STEP WITH actor_mask_resolve.gdshader's split.
float claimed_depth(vec2 uv) {
	vec4 m = texture(actor_mask_data, uv);
	return (m.b >= 0.5 && m.a >= 0.99) ? (m.g + m.r / 255.0) : -1.0;
}

// Nearest claimed depth on a ring of 8 taps at `s` around `uv`, or -1 if none of them is claimed.
float ring_max(vec2 uv, vec2 s) {
	vec2 d = s * 0.70710678;
	float best = max(claimed_depth(uv + vec2(s.x, 0.0)), claimed_depth(uv - vec2(s.x, 0.0)));
	best = max(best, max(claimed_depth(uv + vec2(0.0, s.y)), claimed_depth(uv - vec2(0.0, s.y))));
	best = max(best, max(claimed_depth(uv + vec2(d.x, d.y)), claimed_depth(uv + vec2(-d.x, d.y))));
	best = max(best, max(claimed_depth(uv + vec2(d.x, -d.y)), claimed_depth(uv + vec2(-d.x, -d.y))));
	return best;
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
float searched_depth(vec2 uv, vec2 px) {
	// ⭐ THE TIGHT GATHER, and it is what lets the tolerance below be small. The mask renders at
	// 1/render_scale of this buffer's resolution (half, at the RETRO default 2.0 — InkOutline sizes the
	// mask native_scale()-compensated, so the ratio holds in both presentations) and its depth is
	// point-sampled, so the texel covering a pixel can describe a
	// spot a little further round a shoulder or an arm than the pixel itself — and reading an actor as
	// slightly FARTHER than it is looks exactly like being occluded, which would put a second outline
	// back on a plainly visible actor. Taking the NEAREST claimed depth within a couple of pixels removes
	// that failure direction entirely, so what remains for the tolerance to cover is real geometry, not
	// sampling noise.
	float best = max(claimed_depth(uv), ring_max(uv, px * 2.0));
	if (best >= 0.0) {
		return best;
	}
	// Nothing claimed nearby: this is the hull RIM, which writes no depth at all (see above). Look
	// further out for the body it wraps. Two rings — the inner catches thin rims, the outer the widest
	// authored one — and neither has to know which is in play.
	vec2 r = px * max(mask_rim_search_px, 0.0);
	best = max(best, ring_max(uv, r));
	best = max(best, ring_max(uv, r * 0.5));
	return best;
}

// (The old actor_visibility() helper lives INLINE in fragment() now — the handoff below needs the same
// searched_depth() result the occlusion verdict uses, and running that search twice per pixel would
// double the most expensive taps in the pass.)

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
	// The four corner taps keep their full view-space POSITIONS (not just depth): the crease block below
	// needs them to tell a concave junction from a convex edge, and it costs nothing extra — the depth is
	// -z of the same unprojection.
	float d_c = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec3 p_tl = view_pos(tl, INV_PROJECTION_MATRIX);
	vec3 p_tr = view_pos(tr, INV_PROJECTION_MATRIX);
	vec3 p_bl = view_pos(bl, INV_PROJECTION_MATRIX);
	vec3 p_br = view_pos(br, INV_PROJECTION_MATRIX);
	float d_tl = min(-p_tl.z, SKY_DEPTH);
	float d_tr = min(-p_tr.z, SKY_DEPTH);
	float d_bl = min(-p_bl.z, SKY_DEPTH);
	float d_br = min(-p_br.z, SKY_DEPTH);

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
	// must always be the width of the line being suppressed. (width_px arrives native_scale()-compensated
	// from InkOutline — a factor derived from THIS buffer, never from the mask — so the window stays
	// pinned to the line in both presentations.)
	// THE OUTLINE RING (see the uniform block), computed FIRST because it must SURVIVE the actor
	// exclusion below: the ring lives exactly in the suppression band hugging every masked actor, and a
	// plain discard there would erase the ONLY outline that thing has — since 2026-08-27 everything
	// masked out of the world ink (NPCs, props, gibs, corpses, the view model) is outlined by this pass
	// and nothing else. Drawn only OUTSIDE every tinted silhouette; the NEAREST covered tap wins (max
	// encoded depth — overlapping actors already resolved nearest-wins by their duplicates' own z-test);
	// depth-compared against the scene at THIS pixel with the same encoded-space bias the occlusion
	// verdict uses, so an enemy behind a wall paints nothing (the no-radar rule) — with one deliberate
	// exemption for the view model, documented at the test itself.
	vec3 ring_rgb = vec3(0.0);
	float ring_a = 0.0;
	if (use_actor_tint && highlight_width_px > 0.25) {
		if (texture(actor_tint, SCREEN_UV).a < 0.5) {
			vec2 hw = max(highlight_width_px, 0.5) / VIEWPORT_SIZE;
			vec2 hd = hw * 0.70710678;
			vec2 taps[12] = vec2[12](
				vec2(hw.x, 0.0), vec2(-hw.x, 0.0), vec2(0.0, hw.y), vec2(0.0, -hw.y),
				vec2(hd.x, hd.y), vec2(-hd.x, hd.y), vec2(hd.x, -hd.y), vec2(-hd.x, -hd.y),
				vec2(hw.x * 0.5, 0.0), vec2(-hw.x * 0.5, 0.0), vec2(0.0, hw.y * 0.5), vec2(0.0, -hw.y * 0.5)
			);
			float best_e = -1.0;
			float best_id = 0.0;
			for (int i = 0; i < 12; i++) {
				vec4 t = texture(actor_tint, SCREEN_UV + taps[i]);
				if (t.a > 0.5) {
					float e = t.g + t.r / 255.0;  // the resolve pack's decode — keep in step
					if (e > best_e) {
						best_e = e;
						best_id = t.b;
					}
				}
			}
			if (best_e >= 0.0) {
				// ⭐ KEEP THE 16.0 IN STEP with ink_tint.gdshader's divide and InkOutline.TINT_ID_SPAN.
				float idf = best_id * 16.0;
				int id = int(round(idf));
				float e_scene = encode_actor_depth(d_c, mask_depth_near, mask_depth_far);
				// ⭐⭐ THE VIEW MODEL IS EXEMPT FROM THE OCCLUSION TEST, and it has to be. Everything else
				// here obeys the no-radar rule: a ring whose owner is behind the world paints nothing. But
				// the view model is composited OVER the world by ViewModelCamera's own SubViewport (its own
				// cleared depth — that is the whole point of the pass), and the main camera does not draw
				// the gun at all, so the depth this test reads at a ring pixel is whatever is BEHIND the
				// weapon. Walk up to a wall and that wall is nearer than the gun's duplicate: the test
				// would call the gun occluded and blink its outline off while the gun itself is still
				// plainly drawn on top. Exempting id 10 restores the hull's old behaviour exactly — the
				// gun's rim was drawn in the gun's own pass and never depth-tested against the world
				// either. Safe because nothing on VIEW_MODEL_LAYER is ever a thing in the world to be
				// hidden behind.
				bool depth_exempt = (id == 10);
				if (depth_exempt || !(e_scene - best_e > mask_occlusion_bias)) {
					if ((id >= 1 && id <= 4) || id >= 7) {
						// DISPOSITION IDS: the ring is the actor's ONLY outline, so it draws at every
						// range, and its colour blooms as the actor closes.
						vec4 hcol = (id == 1 || (id >= 7 && id <= 8)) ? highlight_hostile
							: ((id == 2) ? highlight_friendly
							: ((id == 3) ? highlight_companion
							: ((id == 9) ? highlight_hover
							: ((id == 10) ? highlight_view_model : highlight_neutral))));
						// The close-range color bloom (see the uniform block): black at range, the
						// disposition color fading in as THIS actor's encoded depth crosses the band.
						// A hover / view-model id is not a disposition and does not bloom — it paints its
						// LUT slot flat, so `closeness` is pinned to 1 for those.
						float closeness = (id >= 9)
							? 1.0
							: smoothstep(highlight_e_color_far, highlight_e_color_near, best_e);
						// THE ENGAGED-HOSTILE BAND (7..8, continuous): a hostile LOCKED ONTO THE PLAYER
						// stamps 7 + mix (NpcOutline drives mix 0..1 over NPC.outline_target_fade_s), and
						// the mix FLOORS the bloom — full red at any distance once locked on, easing back
						// to the distance rule when the lock breaks. max(), not replace: a locked enemy
						// point-blank must stay full red even mid-fade. smoothstep instead of a bare
						// (idf - 7.0) eases the temporal fade and absorbs the buffer's 8-bit quantisation
						// at both rails (a stamped 7.0 must read exactly not-engaged, an 8.0 fully so).
						// ⭐ id <= 8 guards the band against the ids ABOVE it: 9 and 10 are ordinary
						// discrete slots, not "more engaged than full red".
						if (id >= 7 && id <= 8) {
							closeness = max(closeness, smoothstep(7.0, 7.9, idf));
						}
						ring_rgb = mix(highlight_neutral.rgb, hcol.rgb, closeness);
						ring_a = mix(highlight_neutral.a, hcol.a, closeness);
					} else if (id >= 5 && id <= 6) {
						// WORLD PROPS: unconditional at every range since the hull was deleted
						// (2026-08-27). It used to be the FAR half of a crossfade — invisible inside the
						// hull's rim_fade band — which left a claimed dog readable at 30 m but outlined by
						// a shell up close; now one line owns the whole distance. Rest black reuses the
						// neutral slot and claimed reuses the companion blue, which is the same blue
						// Claimable authors, so props need no LUT colours of their own.
						vec4 pcol = (id == 5) ? highlight_neutral : highlight_companion;
						ring_rgb = pcol.rgb;
						ring_a = pcol.a;
					}
				}
			}
		}
	}

	float actor_here = 0.0;
	float actor_near = 0.0;
	if (use_actor_mask) {
		// Coverage first, and cheaply — five linear taps. The occlusion test below costs a small search,
		// and on a frame that is mostly world there is nothing for it to answer about, so it runs only
		// where the mask actually claims something.
		float c_here = texture(actor_mask, SCREEN_UV).a;
		float c_near = max(texture(actor_mask, tl).a, texture(actor_mask, tr).a);
		c_near = max(c_near, max(texture(actor_mask, bl).a, texture(actor_mask, br).a));
		c_near = max(c_near, c_here);
		if (c_near > 0.0) {
			// OCCLUSION: 1.0 = the mask's actor still suppresses ink here; 0.0 = the world in front of it
			// is what the player is actually looking at. Every fall-through keeps 1.0, i.e. suppression:
			// that direction is deliberate and load-bearing — suppressing ink around a visible actor costs
			// at most a pixel of line, while failing to suppress puts a second black outline around an
			// actor the hull already outlines. The verdict only ever REMOVES suppression on positive
			// evidence; anything it cannot vouch for (a prop faded through GeometryInstance3D.transparency,
			// an actor past the encoding window, a frame before the mask is built) is left as it was.
			// Both sides compare in encoded space, so the tolerance is a fraction of the distance rather
			// than metres — a metre of slack at 40 m is the same sampling wobble as a centimetre close up.
			float e_actor = searched_depth(SCREEN_UV, 1.0 / VIEWPORT_SIZE);
			float vis = 1.0;
			if (use_mask_occlusion && e_actor >= 0.0) {
				float e_world = encode_actor_depth(d_c, mask_depth_near, mask_depth_far);
				vis = (e_world - e_actor > mask_occlusion_bias) ? 0.0 : 1.0;
			}
			// HULL -> INK HANDOFF (see the uniform block): `owned` is the hull's claim on this actor —
			// 1 nearer than the near threshold (suppress, the rim owns the outline: pre-handoff behaviour
			// verbatim), 0 past the far one (no suppression at all — the actor is edge-detected like world
			// geometry, which stays clean at ranges where the mask's coarse-LOD silhouette falls apart).
			// Encoded depth DECREASES with distance, hence smoothstep(far, near, e). An unclaimable pixel
			// (e_actor < 0: the searched ring found no body) keeps owned = 1.0 — the same safe
			// suppress-by-default direction as the occlusion verdict above.
			float owned = (e_actor >= 0.0) ? smoothstep(hull_handoff_e_far, hull_handoff_e_near, e_actor) : 1.0;
			actor_here = c_here * vis * owned;
			actor_near = c_near * vis * owned;
			// The ring outranks the suppression: a suppressed pixel carrying ring coverage falls THROUGH
			// instead of discarding ('return' is illegal in a fragment processor, so no early-out exists)
			// — the edge math below runs wastefully for those few pixels, the actor_near fade at the tail
			// zeroes any ink they would draw, and the ring composes at the end. Only a ring-less
			// suppressed pixel truly discards.
			if ((actor_here > 0.25 || actor_near >= 0.5) && ring_a <= 0.0) {
				discard;
			}
		}
	}

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

	// CONTACT MERGE (see contact_merge_m): the silhouette term has found a depth step — is it the outside
	// of a solid, or the join between two pieces that are touching? Measure the 3D distance between the
	// two surface points the edge sits between: at a stair nosing or a slab on a wall that is the height
	// of the step (they are in contact), against the sky or a far facade it is metres. Take the DIAGONAL
	// THAT FOUND THE EDGE (the one with the larger depth difference) — the other one may lie along the
	// edge and measure nothing. Sky taps sit at SKY_DEPTH along their own ray, so a silhouette against the
	// sky can never be merged, which is the direction to fail in.
	if (edge > 0.0 && contact_merge_m > 0.0) {
		float diff_tlbr = abs(d_tl - d_br);
		float diff_trbl = abs(d_tr - d_bl);
		vec3 pa = (diff_tlbr >= diff_trbl) ? p_tl : p_tr;
		vec3 pb = (diff_tlbr >= diff_trbl) ? p_br : p_bl;
		edge *= smoothstep(contact_merge_m, contact_merge_m * 2.0, distance(pa, pb));
	}

	// Creases. Skipped entirely at zero strength so the four extra taps are not paid for when a
	// silhouette-only look is what is wanted.
	if (crease_strength > 0.0) {
		vec3 n_tl = view_normal(tl);
		vec3 n_tr = view_normal(tr);
		vec3 n_bl = view_normal(bl);
		vec3 n_br = view_normal(br);
		float diff_a = length(n_tl - n_br);
		float diff_b = length(n_tr - n_bl);
		float normal_diff = diff_a + diff_b;
		float crease = smoothstep(crease_threshold, crease_threshold * 2.0, normal_diff);

		// CONCAVE OR CONVEX (see concave_crease_strength). Take the diagonal pair whose normals differ
		// most — that pair straddles the crease — and ask which way the surfaces fold: dot(dN, dP) > 0
		// means the normals DIVERGE along the offset between the taps (an outside corner, convex),
		// < 0 means they converge (an inside corner, concave). Normalised so the shoulder is an angle,
		// not a distance: +-0.15 of a unit dot is a few degrees of ambiguity around a pixel that sits
		// dead on the crease, softened rather than snapped so it cannot pop as the camera moves.
		if (crease > 0.0 && concave_crease_strength < 1.0) {
			vec3 dn = (diff_a >= diff_b) ? (n_tl - n_br) : (n_tr - n_bl);
			vec3 dp = (diff_a >= diff_b) ? (p_tl - p_br) : (p_tr - p_bl);
			float fold = dot(dn, dp) / max(length(dn) * length(dp), 1.0e-6);
			float convex = smoothstep(-0.15, 0.15, fold);
			crease *= mix(concave_crease_strength, 1.0, convex);
		}

		// SEAM MERGE (see crease_min_feature_px): re-measure the same question further out and let the
		// answer only ever REDUCE the crease, so a normal change that exists only in a sub-pixel sliver —
		// the join between two blockout boxes a centimetre out of line — stops drawing a line, while every
		// corner wide enough to be a corner keeps one. Guarded on `crease > 0.0` so the taps are paid for
		// only where there is something to confirm, which on a normal frame is a thin minority of it.
		//
		// ⭐ TWO CROSSES, AND THE MINIMUM OF THEM — not one, and this is the whole difference between the
		// artefact fading and the artefact going. A single wide cross fails wherever the sliver happens to
		// run ALONG one of its diagonals: a tap then lands ON the sliver, reads its perpendicular normal,
		// and votes to keep a line the sliver does not deserve. Measured, that left the seam as a sparse
		// dotted trail rather than a clean surface — and a dotted line is the version that crawls.
		// So the wide question is asked twice, once on the diagonals and once on the axes, and a sliver at
		// ANY orientation is clean to at least one of them. Within a cross the two pairs are SUMMED (that
		// is what makes a single cross orientation-robust for real corners); only BETWEEN the crosses is
		// the minimum taken, so one contaminated cross can no longer force a line on its own.
		//
		// ⭐ A RATIO AGAINST THE NARROW CROSS, NOT A SECOND ABSOLUTE THRESHOLD. The first version ran the
		// wide result through the same smoothstep(threshold, 2*threshold) as the narrow one, and that
		// quietly dimmed every SHALLOW crease: an axis-aligned crease straddles BOTH diagonals of the narrow
		// cross (sum = 2|dN|) but only ONE pair of the axis cross (sum = |dN|), so a 30-degree chamfer that
		// the narrow pass drew at full strength (2*0.52 = 1.03) came back at 22% (0.52 -> smoothstep 0.22)
		// wherever it ran along a screen axis or diagonal — a ramp meeting the floor, a kerb chamfer. The
		// question the wide pass is actually asking is "does the change PERSIST out here?", and the honest
		// measure of that is the wide change RELATIVE to the narrow one. For a straight crease of ANY
		// dihedral at ANY screen angle the weaker wide cross keeps at least HALF the narrow sum (each cross
		// has >= 1 straddling pair once the reach clears the line width — see the floor below), so 0.5 is a
		// hard floor for real geometry; a sliver leaves ~0. The shoulder 0.15..0.4 sits well under that.
		if (crease > 0.0 && crease_min_feature_px > 0.0) {
			// Reach floored at ONE line width. Measured on the level: with the taps inside the narrow
			// cross's own footprint (`o` = width_px/2 either side) the wide pass is just a second, slightly
			// different sampling of the SAME edge, and reducing by it thins every real crease line by a
			// pixel along one side — floor/wall junctions came out ragged. Below one line width the knob
			// cannot merge anything the narrow cross did not already straddle, so it has no upside there,
			// only that artefact. (Derivation: each cross keeps a straddling pair for the whole narrow band
			// iff reach * sin(45deg) >= o * sqrt(2), i.e. reach >= width_px.)
			vec2 w = max(crease_min_feature_px, max(width_px, 0.0)) / VIEWPORT_SIZE;
			vec3 m_tl = view_normal(SCREEN_UV + vec2(-w.x, -w.y));
			vec3 m_tr = view_normal(SCREEN_UV + vec2(w.x, -w.y));
			vec3 m_bl = view_normal(SCREEN_UV + vec2(-w.x, w.y));
			vec3 m_br = view_normal(SCREEN_UV + vec2(w.x, w.y));
			float diag_diff = length(m_tl - m_br) + length(m_tr - m_bl);
			vec3 a_l = view_normal(SCREEN_UV - vec2(w.x, 0.0));
			vec3 a_r = view_normal(SCREEN_UV + vec2(w.x, 0.0));
			vec3 a_u = view_normal(SCREEN_UV - vec2(0.0, w.y));
			vec3 a_d = view_normal(SCREEN_UV + vec2(0.0, w.y));
			float axis_diff = length(a_l - a_r) + length(a_u - a_d);
			float wide_diff = min(diag_diff, axis_diff);
			crease *= smoothstep(0.15, 0.4, wide_diff / max(normal_diff, 1.0e-4));
		}
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

	vec3 out_rgb = ink_color.rgb;
	float out_alpha = clamp(edge, 0.0, 1.0) * ink_color.a * ink_opacity;
	// The precomputed outline ring (see the block ABOVE the actor exclusion — it lives there so the
	// suppression discard cannot erase it) composes OVER the ink: team color is never buried under the
	// aesthetic line work.
	// ⭐⭐ AND IT DOES NOT RIDE ink_opacity (changed 2026-08-27). It used to, back when the ring was one
	// more flourish on an aesthetic pass and every actor, prop and weapon ALSO wore an inverted-hull rim
	// that the Options -> Video "Ink Outline" slider could not touch. With the hull deleted the ring is
	// the only outline in the game, and scaling it by that slider would have made a video option the
	// master switch for hostile red, the colourblind-safe palette, the claimed-prop blue, every look-at
	// hover cue and the view model's line at once — a gameplay and accessibility regression hiding in a
	// brightness dial. The slider still owns the WORLD's ink (out_alpha above, and InkOutline hides this
	// whole quad at 0% unless the ring needs it); the ring is now independent of it, exactly as the hull
	// rims it replaced always were.
	if (ring_a > 0.0) {
		out_rgb = ring_rgb;
		out_alpha = max(out_alpha, ring_a);
	}

	ALBEDO = out_rgb;
	ALPHA = out_alpha;
}
