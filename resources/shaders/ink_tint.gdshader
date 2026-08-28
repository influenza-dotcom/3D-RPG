shader_type spatial;
// THE OUTLINE ID PASS — the flat "team color / ID buffer" every shipped tactical outline is built
// on (L4D2's glow buffer, Deep Rock's Custom Stencil IDs, League's per-champion buffer; see
// docs/CURRENT_ARCHITECTURE.md -> Presentation -> the outline research notes). Worn by the invisible
// duplicate meshes InkOutline.apply_tint parents under EVERY outlined mesh in the game — NPC body parts,
// world props, gibs, corpses, the look-at hover, and the first-person view model — on InkOutline's
// ACTOR_TINT_LAYER, rendered ONLY by InkOutline's tint SubViewport. ink_outline.gdshader ring-dilates
// this buffer in screen space to draw the colored outline — which is why a 6-part Lego body can never
// confetti again: all its parts land in ONE raster silhouette here, and the outline is drawn around
// that silhouette at constant PIXEL width, so no shell geometry exists to out-thicken a limb.
//
// ⭐ THIS IS THE PROJECT'S ONLY OUTLINE TECHNIQUE (2026-08-27). The inverted-hull shell it replaced
// (resources/shaders/outline.gdshader) is DELETED, not deprecated — see InkOutline's class doc for the
// migration and what each consumer stamps.
//
// WHAT IT WRITES (the actor_mask_resolve.gdshader conventions, kept deliberately identical):
//   R + G = this fragment's view distance, log-encoded across sixteen bits (G coarse, R fine) — the ink
//           pass compares it against the scene depth at the ring pixel, so a highlight NEVER shows
//           through a wall (the "pinned dot would turn a floorplan into a radar" rule).
//   B     = disposition_id / ID_SPAN, the per-mesh identity: 1 hostile, 2 friendly, 3 companion,
//           4 neutral, 5 prop, 6 claimed prop, the CONTINUOUS 7..8 engaged-hostile band (7 + lock-on
//           mix; ink_outline.gdshader floors the close-range bloom by the fraction past 7), 9 look-at
//           hover, 10 view model. Set per duplicate via set_instance_shader_parameter so every
//           duplicate SHARES this one material. ⭐ ID_SPAN is 16 and it is the SAME literal in
//           ink_outline.gdshader's decode and in InkOutline.TINT_ID_SPAN — three places, no arithmetic
//           allowed in a uniform default, so they are kept in step by comment and by test.
//   A     = 1 by being drawn at all (coverage; the viewport clears transparent).
//
// ⭐ OPAQUE ON PURPOSE — no ALPHA is ever assigned in this shader. ANY alpha assignment flags the
// material `uses_alpha` and moves it to the transparent pass, which writes no depth (Godot decides that
// from the assignment EXISTING, not from any branch being taken — the trap the retired hull shader
// documented). This pass NEEDS the depth buffer: overlapping actors resolve nearest-wins by plain
// z-test, which is exactly the contested-pixel rule the shipped implementations use.
// ⭐ to_target() pre-compensates the render target's linear->sRGB write (measured in
// actor_mask_resolve.gdshader — read its header before doubting it), so the stored bytes are the values
// meant. 0 and 1 are fixed points of that curve, so A rides through untouched; R, G and B all take the
// treatment. The tint camera's Environment must stay pinned to the LINEAR tonemapper
// (InkOutline._build_mask_environment, shared with the mask camera) or the encoding is re-graded.
render_mode unshaded, cull_back, fog_disabled, shadows_disabled;

// Log-encoding window (metres) — pushed by InkOutline from the SAME consts the mask pair uses, so all
// three encoders (resolve, ink compare, this) can never disagree. Literal defaults only (the project's
// shader test rule: arithmetic in a uniform default fails the whole compile check).
uniform float depth_near = 0.1;
uniform float depth_far = 300.0;

// The ink shader's LUT index (see the header's B-channel table) — or a fractional 7..8 for the
// engaged-hostile band. Per-instance so the one shared material serves every duplicate in the game;
// InkOutline.apply_tint stamps it on each duplicate it builds.
instance uniform float disposition_id = 0.0;

// ⭐ KEEP IDENTICAL to actor_mask_resolve.gdshader / ink_outline.gdshader / InkOutline.encode_actor_depth.
float encode_actor_depth(float d, float near_m, float far_m) {
	float lo = max(near_m, 0.001);
	float hi = max(far_m, lo * 1.001);
	return 1.0 - clamp(log(clamp(d, lo, hi) / lo) / log(hi / lo), 0.0, 1.0);
}

// ⭐ KEEP IDENTICAL to actor_mask_resolve.gdshader — the inverse of the target's sRGB transfer.
float to_target(float v) {
	float c = clamp(v, 0.0, 1.0);
	return (c <= 0.04045) ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4);
}

void fragment() {
	// VERTEX in a spatial fragment shader is the view-space position, so -z IS the view distance in
	// metres — no depth-texture round trip, no resolve quad, each fragment encodes itself.
	float e = encode_actor_depth(-VERTEX.z, depth_near, depth_far);
	float coarse = floor(e * 255.0) / 255.0;
	float fine = fract(e * 255.0);
	// ⭐ THE ID SPAN IS 16 AND THE LITERAL IS LOAD-BEARING IN THREE FILES: this divide, the matching
	// `best_id * 16.0` decode in ink_outline.gdshader, and InkOutline.TINT_ID_SPAN. It was 8 until
	// 2026-08-27, when the hull's retirement needed ids for the look-at hover (9) and the view model
	// (10); widening halves the resolution the 7..8 lock-on band's fractional mix survives at
	// (16/255 = 0.063 per byte step, ~14 steps across the band's 7.0..7.9 smoothstep), which is still
	// finer than the eye can follow across a 0.4 s fade. Anything past 16 clamps.
	ALBEDO = vec3(to_target(fine), to_target(coarse), to_target(clamp(disposition_id, 0.0, 16.0) / 16.0));
}
