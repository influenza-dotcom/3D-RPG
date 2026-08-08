shader_type spatial;

// PLANAR "print" projection for the player-DRAWN t-shirt (the character creator's Shirt tab).
// The shipped torso mesh carries a Blender-baked UV ATLAS — dozens of scattered islands — so sampling the
// player's drawing through the mesh UVs shreds it into unreadable scraps. This shader IGNORES the mesh UVs
// and projects the drawing flat onto the torso in MESH-LOCAL space (like a print pressed onto the chest):
// u along the torso's width axis, v down its height. Built + parameterised ONLY by
// BodyModelSwap._planar_shirt_material() (per-mesh AABB + axis picks) — not authored by hand in scenes.
//
// FRONT + BACK: the texture is a COMBINED image, the FRONT drawing stacked ABOVE the BACK drawing (a 1:2
// aspect from ShirtCanvas). Chest-facing fragments sample the TOP half; back-facing fragments sample the
// BOTTOM half with u mirrored (so the player's back drawing reads un-mirrored from behind). A legacy save
// (a square design) is decoded onto both halves, so this reduces to the old symmetric print for old shirts.

// The drawn shirt (ShirtCanvas' NEAREST-upscaled combined front/back texture). filter_nearest keeps pixels crisp.
uniform sampler2D shirt_tex : source_color, filter_nearest;
// Flat tint over the art (WHITE = as-drawn; configure_swap forces WHITE for custom shirts).
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// The mesh's local-space bounding box (Mesh.get_aabb()) — normalises VERTEX into 0..1 per axis.
uniform vec3 aabb_min = vec3(-0.5, -0.5, -0.5);
uniform vec3 aabb_size = vec3(1.0, 1.0, 1.0);
// How front/back-facing a fragment must be (|dot(normal, depth_dir)|) to receive the PRINT. Below this the
// face counts as a SIDE / top / bottom and shows plain fabric instead — a planar projection would otherwise
// stretch the drawing's edge pixels across those faces as smears.
uniform float print_threshold : hint_range(0.0, 1.0) = 0.4;
// One-hot mesh-local axes: width_dir spans shoulder-to-shoulder, depth_dir points chest<->back.
// (Height is always local +Y.) Picked at runtime from the AABB: the wider horizontal axis is the width.
uniform vec3 width_dir = vec3(1.0, 0.0, 0.0);
uniform vec3 depth_dir = vec3(0.0, 0.0, 1.0);
// Which side of depth_dir is the CHEST (+1.0 or -1.0) — flips which faces count as "front".
uniform float front_sign = 1.0;
// DITHERED see-through (0 = solid, 1 = invisible) — BodyModelSwap.body_transparency routes here for the
// player's first-person torso (the Odyssey-style screen-door), because this override REPLACES the
// BaseMaterial3D path that alpha-hash would otherwise handle. Screen-space discard: depth still writes for
// surviving pixels, nothing re-sorts, and the stipple matches the alpha-hash look on plain-skin torsos.
uniform float see_through : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_local;
varying vec3 v_normal;

void vertex() {
	v_local = VERTEX;
	v_normal = NORMAL;
}

// Plain FABRIC colour for a side/top/bottom face: the average of the FRONT or BACK region's four corner texels
// (half-texel inset). Passing which region keeps a red-front / blue-back tee's left-right seams reading the
// nearer side's colour instead of a muddy blend of both.
vec3 region_fabric(bool front) {
	vec2 h = vec2(0.5) / vec2(textureSize(shirt_tex, 0));
	float v0 = front ? 0.0 : 0.5;   // region top edge in combined V
	float v1 = front ? 0.5 : 1.0;   // region bottom edge
	return (texture(shirt_tex, vec2(h.x, v0 + h.y)).rgb
			+ texture(shirt_tex, vec2(1.0 - h.x, v0 + h.y)).rgb
			+ texture(shirt_tex, vec2(h.x, v1 - h.y)).rgb
			+ texture(shirt_tex, vec2(1.0 - h.x, v1 - h.y)).rgb) * 0.25;
}

void fragment() {
	// Interleaved-gradient-noise threshold on FRAGCOORD only — deliberately NO TIME term (a TIME-fed hash
	// strobes; the repo's grain-strobe lesson), so the dither pattern is stable per screen pixel.
	if (see_through > 0.001) {
		float ign = fract(52.9829189 * fract(0.06711056 * FRAGCOORD.x + 0.00583715 * FRAGCOORD.y));
		if (see_through > ign) {
			discard;
		}
	}
	vec3 nrm = normalize(v_normal);
	vec3 rel = clamp((v_local - aabb_min) / max(aabb_size, vec3(0.0001)), vec3(0.0), vec3(1.0));
	vec3 col;
	// The torso's CHEST is the dot(normal, depth)*front_sign < 0 side (the front_sign heuristic labels the axis,
	// not which end is the chest — determined against the actual rig: the chest pairs with the head's face).
	if (abs(dot(nrm, depth_dir)) < print_threshold) {
		// SIDE / top / bottom faces: plain fabric. Pick front vs back region by which half of the torso's DEPTH
		// the fragment sits on, so a side seam near the chest reads the FRONT colour and one near the back reads BACK.
		bool front_half = ((dot(rel, depth_dir) - 0.5) * front_sign) < 0.0;
		col = region_fabric(front_half);
	} else {
		float u = dot(rel, width_dir);
		float v = 1.0 - rel.y;
		if (dot(nrm, depth_dir) * front_sign < 0.0) {
			col = texture(shirt_tex, vec2(1.0 - u, v * 0.5)).rgb;      // CHEST: FRONT drawing (top half), mirror-corrected
		} else {
			col = texture(shirt_tex, vec2(u, 0.5 + v * 0.5)).rgb;     // back: BACK drawing (bottom half)
		}
	}
	ALBEDO = col * tint.rgb;
	METALLIC = 0.0;
	ROUGHNESS = 1.0; // cotton tee — fully rough, like the StandardMaterial the base skin path uses
}
