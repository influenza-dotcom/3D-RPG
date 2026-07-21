shader_type spatial;

// PS1 / Cruelty-Squad warp. Two classic effects:
//   1. Vertex snapping  — clip-space XY is snapped to a coarse grid, so geometry jitters/wobbles
//      the way it did when the PS1 had no sub-pixel vertex precision.
//   2. Affine texture mapping — perspective-correct UV interpolation is undone, so textures
//      "swim"/warp across faces (the PS1 GPU couldn't do perspective correction).
// OPAQUE + point-filtered. Lighting is left to Godot; ALBEDO comes from each mesh's own texture
// (wired up by ps1_applier). The applier skips transparent/cutout materials, so this stays fully
// opaque — which keeps shadows clean (a forced alpha test would punch holes from stray alpha).

// LOWER = chunkier wobble. ~48 heavy, ~96 moderate, ~200 subtle. (2 * value = grid cells across.)
uniform float vertex_snap = 96.0;
// 0 = normal perspective-correct UVs, 1 = full PS1 affine warp.
uniform float affine_amount : hint_range(0.0, 1.0) = 1.0;
// Depth window (view-space w, ~metres) the affine warp spans. Affine error on a triangle grows with the
// far/near depth RATIO across it — the PS1 kept that ratio tiny because scenes were subdivided into small
// polys, but brush levels run ONE triangle from your boots to the horizon, which smears the texture into
// soup at full affine. Clamping w into [affine_near, affine_far] before the affine mix bounds the ratio
// (≤ far/near): closer than affine_near renders perspective-correct (clean point-blank), the retro swim
// lives in the mid-range, and a face wholly past affine_far is correct again instead of melted.
uniform float affine_near : hint_range(0.01, 100.0) = 1.0;
uniform float affine_far : hint_range(0.01, 500.0) = 6.0;

// Point-filtered so textures stay crunchy (no smoothing) like the real thing.
uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform bool use_texture = true;            // false for surfaces that had no texture
uniform vec4 albedo_color : source_color = vec4(1.0);

varying float v_affine_w;

void vertex() {
	// Project to clip space ourselves so we can snap, then write POSITION to override Godot's.
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	float w = clip.w;
	vec3 ndc = clip.xyz / w;
	// Snap XY to the grid (the wobble); leave depth (z) alone to avoid z-fighting.
	ndc.xy = floor(ndc.xy * vertex_snap) / vertex_snap;
	POSITION = vec4(ndc * w, w);

	// Affine setup: pre-multiply UV by (depth-clamped) w. Godot interpolates it perspective-correctly, and
	// the fragment divides by the interpolated w again — the two cancel toward LINEAR (affine) UVs. The
	// clamp bounds how hard one huge near→far triangle can warp (see affine_near / affine_far above).
	// Misauthoring guard: near must stay positive (zero/negative would let interpolated v_affine_w cross
	// zero on near-plane triangles -> division blowup) and far must not sit below near (clamp with
	// min > max is spec-undefined GLSL).
	float a_near = max(affine_near, 0.001);
	float a_far = max(affine_far, a_near);
	v_affine_w = mix(1.0, clamp(w, a_near, a_far), affine_amount);
	UV *= v_affine_w;
}

void fragment() {
	vec2 uv = UV / v_affine_w;
	vec3 col = use_texture ? texture(albedo_tex, uv).rgb : vec3(1.0);
	ALBEDO = col * albedo_color.rgb;
}
