shader_type spatial;

// PS1 / Cruelty-Squad warp. Two classic effects:
//   1. Vertex snapping  — clip-space XY is snapped to a coarse grid, so geometry jitters/wobbles
//      the way it did when the PS1 had no sub-pixel vertex precision. UVs stay perspective-correct,
//      so textures ride the wobbling geometry without distorting. This is the shipped look.
//   2. Affine texture mapping — perspective-correct UV interpolation is undone, so textures
//      "swim"/warp across faces (the PS1 GPU couldn't do perspective correction). OPT-IN
//      (affine_amount defaults 0): on this project's huge brush triangles the swim smears
//      textures into an ugly stretch that reads as broken rendering, not retro.
//
// SEAM WARNING (why vertex_snap must stay fine): the func_godot brush mesh is UNWELDED — every
// face owns private vertices, coincident corners are only float-approximately equal, and big
// faces have T-junctions where small ones butt in. floor() amplifies any of that into a tear up
// to ONE FULL GRID CELL wide, and a tear in a hollow backface-culled building shows the SKY.
// Tear width == cell size == wobble amplitude, so the two are one dial: keep the cell at about
// one pixel of the pixelated output (ui.tscn post_process render_scale) and tears read as pixel
// crawl; crank it chunkier and buildings visibly hole open. See vertex_snap below.
//
// SHADOW PASS: never snap there (see the IN_SHADOW_PASS branch in vertex()). The shadow pass
// re-runs this vertex shader with the LIGHT's projection, so snapping quantizes the shadow map
// in light-space (~100m directional frustum / grid = tenth-of-metre world cells) and the grid
// re-phases every frame as the camera moves the frustum -> every lit surface strobes. That was
// the "textures flashing" bug; the map renders unsnapped, only the camera view wobbles.
// OPAQUE + point-filtered. Lighting is left to Godot; ALBEDO comes from each mesh's own texture
// (wired up by ps1_applier). The applier skips transparent/cutout materials, so this stays fully
// opaque — which keeps shadows clean (a forced alpha test would punch holes from stray alpha).

// Grid cells across the screen = 2 * value, so cell width = tear width (see SEAM WARNING above).
// 396 = one cell per texel of the ACTUAL 792-wide screen buffer (396x216 window x viewport-stretch
// scale 0.5 -> 792x444; ui.tscn's post_process render_scale 1584 is FINER than that buffer, so the
// buffer texel is the real pixel size) — the authentic PS1 ratio (their cell was one 320x240 pixel)
// and the chunkiest setting whose seam tears still read as pixel crawl: every snap step is exactly
// one screen texel. LOWER = chunkier wobble but proportionally wider sky-holes.
uniform float vertex_snap = 396.0;
// Far fade: snap eases out over this view-depth window (metres) and distant geometry renders
// UNWARPED. Distant buildings are where the warp only does harm — the map's coplanar flush brush
// faces z-fight, and snap re-randomizes the winner per frame (flashing); seam tears pierce to the
// sky; the camera's 30m far-DOF re-blurs re-jittered geometry every frame (shimmer). Depth-fading
// the snap de-animates all three at range while the wobble stays full-strength up close, where
// PS1 wobble reads best. smoothstep of w is CONTINUOUS, so coincident vertices fade identically —
// the fade itself can never tear a seam open.
uniform float snap_far_fade_start : hint_range(1.0, 200.0) = 20.0;
uniform float snap_far_fade_end : hint_range(1.0, 400.0) = 40.0;
// Near fade: the snap also eases IN over this window, so point-blank walls and the floor underfoot
// hold still. This replaces the old floor-stabilization comfort role WITHOUT its seams — freezing
// whole floor surfaces while adjoining walls warp tore a flickering gap along every stair-step and
// wall-base contact line; a depth-continuous fade can never do that.
uniform float snap_near_fade_start : hint_range(0.05, 20.0) = 0.75;
uniform float snap_near_fade_end : hint_range(0.05, 40.0) = 1.5;
// 0 = normal perspective-correct UVs (default — textures stay glued to the wobbling geometry),
// 1 = full PS1 affine warp. Opt-in per instance; see the header for why it ships off.
uniform float affine_amount : hint_range(0.0, 1.0) = 0.0;
// Depth window (view-space w, ~metres) the affine warp spans. Affine error on a triangle grows with the
// far/near depth RATIO across it — the PS1 kept that ratio tiny because scenes were subdivided into small
// polys, but brush levels run ONE triangle from your boots to the horizon, which smears the texture into
// soup at full affine. Clamping w into [affine_near, affine_far] before the affine mix bounds the ratio
// (≤ far/near): closer than affine_near renders perspective-correct (clean point-blank), the retro swim
// lives in the mid-range, and a face wholly past affine_far is correct again instead of melted.
uniform float affine_near : hint_range(0.01, 100.0) = 1.0;
uniform float affine_far : hint_range(0.01, 500.0) = 6.0;

// Point-filtered so textures stay crunchy (no smoothing) like the real thing — but WITH mipmaps:
// pure filter_nearest minification makes distant textures sparkle/shimmer every frame (reads as
// flashing); the mipmap chain calms the distance while the near field stays hard-pixel.
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
uniform bool use_texture = true;            // false for surfaces that had no texture
uniform vec4 albedo_color : source_color = vec4(1.0);

varying float v_affine_w;

void vertex() {
	// Project to clip space ourselves so we can snap, then write POSITION to override Godot's.
	// PROJECTION_MATRIX is per-pass (the light's in a shadow pass, the camera's otherwise).
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (IN_SHADOW_PASS) {
		// Shadow maps must be geometry-STABLE — see SHADOW PASS in the header. POSITION must
		// still be written HERE: writing it on ANY branch makes the engine use it on EVERY
		// branch, so a branch that skips the write would emit garbage clip positions.
		POSITION = clip;
		v_affine_w = 1.0;
	} else {
		float w = clip.w;
		vec3 ndc = clip.xyz / w;
		// Snap XY to the grid (the wobble); leave depth (z) alone to avoid z-fighting.
		// The near/far fades blend back to the true position at both depth extremes (uniforms above).
		// Misauthoring guard: smoothstep needs end > start or its result is undefined.
		float n_start = max(snap_near_fade_start, 0.0);
		float n_end = max(snap_near_fade_end, n_start + 0.001);
		float f_start = max(snap_far_fade_start, 0.0);
		float f_end = max(snap_far_fade_end, f_start + 0.001);
		float snap_strength = smoothstep(n_start, n_end, w) * (1.0 - smoothstep(f_start, f_end, w));
		vec2 snapped = floor(ndc.xy * vertex_snap) / vertex_snap;
		ndc.xy = mix(ndc.xy, snapped, snap_strength);
		POSITION = vec4(ndc * w, w);

		// Affine setup: pre-multiply UV by (depth-clamped) w. Godot interpolates it perspective-correctly,
		// and the fragment divides by the interpolated w again — the two cancel toward LINEAR (affine) UVs.
		// The clamp bounds how hard one huge near→far triangle can warp (see affine_near / affine_far above).
		// Misauthoring guard: near must stay positive (zero/negative would let interpolated v_affine_w cross
		// zero on near-plane triangles -> division blowup) and far must not sit below near (clamp with
		// min > max is spec-undefined GLSL).
		float a_near = max(affine_near, 0.001);
		float a_far = max(affine_far, a_near);
		v_affine_w = mix(1.0, clamp(w, a_near, a_far), affine_amount);
	}
	UV *= v_affine_w;
}

void fragment() {
	vec2 uv = UV / v_affine_w;
	vec3 col = use_texture ? texture(albedo_tex, uv).rgb : vec3(1.0);
	ALBEDO = col * albedo_color.rgb;
}
