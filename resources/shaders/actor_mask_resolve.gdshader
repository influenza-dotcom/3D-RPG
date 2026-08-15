shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

// THE ACTOR MASK'S DEPTH RESOLVE — a screen-filling quad that lives INSIDE InkOutline's mask
// SubViewport, reads that viewport's own depth buffer, and stamps the answer into the mask's colour
// so the ink pass can tell a VISIBLE actor from one standing behind a wall.
//
// WHAT IT WRITES, and only where it has something to say:
//     ALPHA = 1 where an actor's OPAQUE geometry is at this pixel, else 0.
//     G     = that actor's distance, log-encoded (see encode_actor_depth).
//     B     = 1, the "this pixel's depth was authored by the resolve pass" marker.
// Where it has no depth it writes ALPHA 0, which under blend_mix leaves the mask completely
// untouched — the actors' own render passes straight through, exactly as before this pass existed.
// So the mask's alpha stays exactly what it always was — a coverage field — and ink_outline.gdshader
// still reads coverage from `.a`. This pass adds information; it never takes a pixel away.
//
// WHY IT EXISTS: the mask pass renders ONLY actors, so nothing in it can occlude them — an NPC
// behind a wall still stamped its full silhouette into the mask and bit that shape out of every ink
// line it overlapped. Long straight lines (stair nosings, building corners) came away with clean
// circles punched through them wherever somebody stood on the other side, which read as sensing
// people through walls. Two earlier attempts at this are recorded in ink_outline.gd (stencil on the
// ink quad: a silent no-op; a CPU raycast cull: it broke the world ink outright). The fix named there
// as the honest one is to give the mask DEPTH and compare it against the depth of what the player can
// actually see. That is this file.
//
// ================================ MEASURED, NOT ASSUMED ==========================================
// Everything below was probed on 4.7.1 against the real driver, because `--headless` runs a dummy
// rasterizer that never compiles a shader at all — nothing here is checkable by the test suite.
//
// ⭐⭐ THE RENDER TARGET APPLIES linear->sRGB. Writing ALBEDO (0.25, 0.5, 0.75) into a transparent
// SubViewport and reading the image back gives (0.5373, 0.7373, 0.8824) in an RGBA8 texture — the
// sRGB transfer to within 8-bit rounding. A number encoded in RGB is therefore mangled on the way in
// unless it is PRE-COMPENSATED, which is what to_target() does; what lands in the texture is then the
// value this shader meant. 0 and 1 are fixed points of that curve, so the B marker and the ALPHA
// coverage ride through untouched and only the depth channel needs the treatment.
// The mask camera's Environment must stay on the LINEAR tonemapper at exposure 1 / white 1 for the
// same reason — InkOutline._build_mask_environment pins that; a filmic curve would eat the encoding.
//
// ⭐⭐ THE HULL WRITES NO DEPTH, WHICH LEAVES ITS RIM WITHOUT ANY.
// outline.gdshader assigns ALPHA inside a branch, which flags the whole material `uses_alpha` (Godot
// decides that from the assignment EXISTING, not from the branch being taken) and puts the rim in the
// TRANSPARENT pass, where it writes neither depth nor normals. Probed: a box wearing the real hull
// covered 23 px of mask ALPHA but only 19 px of mask DEPTH. That 4 px ring had coverage but nothing to
// compare, and a pixel this pass cannot vouch for is one the ink keeps suppressing — so a hidden actor
// stopped punching a solid hole in the world's lines and started punching an OUTLINE of itself. The
// user's words: "it's like an O shape around it."
// THAT RING IS NOT THIS PASS'S TO FIX. Spreading depth outward from here was tried and removed: this
// shader can only widen the mask's DEPTH by also widening its ALPHA, and the mask's alpha is coverage,
// and coverage is suppressed ink — so every pixel of ring it repaired bought a pixel of halo around every
// VISIBLE actor. ink_outline.gdshader searches outward instead (see searched_depth there), which reads a
// wider neighbourhood without claiming one extra pixel of the frame.
// (The same blind spot is why nothing here reads hint_screen_texture for coverage: that copy is taken
// BEFORE the transparent pass too, so it cannot see the rim either.)
//
// ⭐ A CLEARED DEPTH BUFFER IS NOT "FAR AWAY", IT IS NOTHING. Unprojecting an untouched depth texel
// yields the camera's far plane — a perfectly finite 4000 m — so a naive `d < SKY_DEPTH` test called
// the entire empty frame valid geometry. camera_far is pushed here so that pixel reads as EMPTY.

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

// --- Depth encoding window (metres) -----------------------------------------------------------------
// Pushed by InkOutline so this file and ink_outline.gdshader cannot disagree — they MUST encode
// identically or every comparison downstream is nonsense. Literal defaults: Godot does not
// constant-fold a uniform initialiser, and arithmetic here fails the WHOLE shader (test_ink_outline.gd
// pins that for the ink shader; the same rule applies to every shader in this project).
uniform float depth_near = 0.1;
uniform float depth_far = 300.0;
// The mask camera's own far plane, in metres — the distance a pixel nothing was drawn into reports.
// Pushed live because the mask camera mirrors the main camera's far.
uniform float camera_far = 4000.0;

// Stand-in for "nothing was drawn here" — matches ink_outline.gdshader's SKY_DEPTH.
const float SKY_DEPTH = 1.0e6;

// View-space distance in metres for a mask pixel, or SKY_DEPTH where the mask drew nothing.
// INV_PROJECTION_MATRIX carries the driver's depth convention, so this needs no reverse-Z special
// case; the guard catches a degenerate w and (via "not greater than zero") NaN, and the far-plane
// test is what turns an untouched texel into "empty" rather than "geometry 4 km away".
float linear_depth(vec2 uv, mat4 inv_proj, float far_m) {
	float raw = texture(depth_tex, uv).x;
	vec4 view = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	float d = -view.z / view.w;
	if (!(d > 0.0) || d >= far_m) {
		return SKY_DEPTH;
	}
	return d;
}

// ⭐ KEEP IDENTICAL TO ink_outline.gdshader's copy — the two are compared against each other every
// frame. One 8-bit channel has to cover the whole playable range, so depth is stored LOGARITHMICALLY:
// every step is the same FRACTION of the depth (~3% across this window) rather than the same number of
// metres, which is the right currency for a test that only asks "is the world meaningfully nearer than
// the actor?". Near maps to 1.0 and far to 0.0.
float encode_actor_depth(float d, float near_m, float far_m) {
	float lo = max(near_m, 0.001);
	float hi = max(far_m, lo * 1.001);
	return 1.0 - clamp(log(clamp(d, lo, hi) / lo) / log(hi / lo), 0.0, 1.0);
}

// Pre-compensate for the linear->sRGB the render target applies (see the header), so the value that
// ends up STORED is the value passed in. This is sRGB's EOTF — the exact inverse of the transfer
// Godot's tonemap pass writes with.
float to_target(float v) {
	float c = clamp(v, 0.0, 1.0);
	return (c <= 0.04045) ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4);
}

void vertex() {
	// Clip space written straight from the unit QuadMesh's corners — the ink quad's idiom, so the quad
	// covers exactly the viewport whatever transform, FOV or aspect it is handed, which leaves its node
	// placement free to mean sort order and nothing else. z = 0, w = 1 is inside the valid clip range
	// under both the GL (-w..w) and Vulkan/D3D12 (0..w) conventions, and depth_test_disabled means the
	// value is never compared anyway.
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

void fragment() {
	float far_m = max(camera_far, 0.001) * 0.999;  // 0.1% short of the far plane = "nothing was drawn"
	float d = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX, far_m);
	// An actor past the encoding window is left alone rather than encoded as "infinitely far": beyond
	// it the ink has faded out anyway, and a saturated encoding would be indistinguishable from a wall.
	float valid = (d < min(far_m, depth_far)) ? 1.0 : 0.0;

	ALBEDO = vec3(0.0, to_target(encode_actor_depth(d, depth_near, depth_far)), 1.0);
	// THE WHOLE POINT: 0 here means blend_mix leaves this pixel of the mask exactly as the actors
	// rendered it — no depth to offer, no opinion given, and the ink pass falls back to suppressing
	// as it always did. 1 claims the pixel, so G and B above are the resolve pass's own values.
	ALPHA = valid;
}
