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

void vertex() {
	vec4 clip_position = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 clip_normal = mat3(PROJECTION_MATRIX) * (mat3(MODELVIEW_MATRIX) * NORMAL);
	
	vec2 offset = normalize(clip_normal.xy) / VIEWPORT_SIZE * clip_position.w * outline_width * 4.0;
	
	clip_position.xy += offset;
	
	POSITION = clip_position;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	if (outline_color.a < 1.0) {
		ALPHA = outline_color.a;
	}
}