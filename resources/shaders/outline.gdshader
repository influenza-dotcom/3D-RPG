shader_type spatial;
// ⭐⭐ TRIED AND REVERTED 2026-08-14 — `depth_prepass_alpha` here. This shader assigns ALPHA in the branch
// below, which flags the whole material `uses_alpha` (Godot decides that from the assignment EXISTING,
// not from the branch being taken), so the rim renders in the TRANSPARENT pass and writes NO depth. That
// leaves the inflated rim ring with coverage but no depth in InkOutline's actor mask — the "O shape"
// artefact, where a hidden actor punches an outline of itself through the world's ink instead of a solid
// hole. depth_prepass_alpha genuinely fixes that (measured: mask coverage AND depth both reach +23 px on
// a 2.0-width rim, against 19 px without it) — but it also puts the rim into the MAIN pass's depth, which
// gives the ink's edge detect a second silhouette to find, and a faint doubled line appeared along the
// top edge of VISIBLE actors (37 px in the probe frame, detached from the rim). A doubled outline is the
// exact thing this whole system exists to prevent, so the trade is not worth it.
// The ring is fixed on the INK side instead: ink_outline.gdshader searches outward for the body's depth
// when a covered pixel has none of its own, which costs nothing in coverage. Do not re-add this here
// without re-checking the visible actor's silhouette.
render_mode cull_front, unshaded;

uniform vec4 outline_color : source_color;
uniform float outline_width = 1.0;
// ⭐⭐ THE RIM MUST BE THE SAME WIDTH IN EVERY VIEWPORT THAT DRAWS IT, and dividing by VIEWPORT_SIZE is
// not that. This shader runs in TWO passes: the frame the player sees (the 3D buffer, 1584x888 here) and
// InkOutline's actor mask, which renders at HALF that (792x444) because a coverage mask has no business
// costing four times the pixels. Same `outline_width`, half the viewport, DOUBLE the rim — so the mask
// claimed a silhouette twice as fat as the one on screen, and the ink pass dutifully stopped short of it.
// Measured against a reference frame: suppression reached 4 px past a visible actor where its rim was
// only 2 px. That 2 px of bare band hugged every actor at every distance, and on a humanoid it traces
// each limb and the gaps between them — subtle, scattered, and impossible to screenshot.
// Referencing a FIXED width instead makes the extrusion a constant fraction of the SCREEN, which is the
// same in both passes by construction. VIEWPORT_SIZE still supplies the ASPECT, so the rim stays even on
// x and y at any window shape; only its scale is pinned. At this project's 1584-wide 3D buffer the frame
// the player sees is unchanged to the pixel — this only shrinks the mask's copy to the truth.
// Consequence worth knowing: the rim is now a constant fraction of the image rather than a constant
// number of buffer pixels, so Options -> Video -> Render Scale no longer changes its apparent thickness.
uniform float rim_reference_width = 1584.0;

void vertex() {
	vec4 clip_position = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 clip_normal = mat3(PROJECTION_MATRIX) * (mat3(MODELVIEW_MATRIX) * NORMAL);

	vec2 reference = VIEWPORT_SIZE * (max(rim_reference_width, 1.0) / max(VIEWPORT_SIZE.x, 1.0));
	vec2 offset = normalize(clip_normal.xy) / reference * clip_position.w * outline_width * 4.0;

	clip_position.xy += offset;

	POSITION = clip_position;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	if (outline_color.a < 1.0) {
		ALPHA = outline_color.a;
	}
}