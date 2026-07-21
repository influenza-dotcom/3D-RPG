shader_type spatial;

// PLANAR "print" projection for the player-DRAWN t-shirt (the character creator's Shirt tab).
// The shipped torso mesh carries a Blender-baked UV ATLAS — dozens of scattered islands — so sampling the
// player's drawing through the mesh UVs shreds it into unreadable scraps. This shader IGNORES the mesh UVs
// and projects the drawing flat onto the torso in MESH-LOCAL space (like a print pressed onto the chest):
// u along the torso's width axis, v down its height. Back-facing fragments mirror u, so the design reads
// un-mirrored from behind too (printed on both sides). Built + parameterised ONLY by
// BodyModelSwap._planar_shirt_material() (per-mesh AABB + axis picks) — not authored by hand in scenes.

// The drawn shirt (ShirtCanvas' NEAREST-upscaled applied texture). filter_nearest keeps the pixels crisp.
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

varying vec3 v_local;
varying vec3 v_normal;

void vertex() {
	v_local = VERTEX;
	v_normal = NORMAL;
}

void fragment() {
	vec3 nrm = normalize(v_normal);
	vec3 col;
	if (abs(dot(nrm, depth_dir)) < print_threshold) {
		// SIDE / top / bottom faces: plain FABRIC, not a smear of the print's edge pixels. The fabric colour is
		// the average of the drawing's four corner texels (half-texel inset), sampled LIVE — so a bucket-filled
		// red tee gets red sides, and it keeps tracking the in-place texture updates as the player paints.
		vec2 h = vec2(0.5) / vec2(textureSize(shirt_tex, 0));
		col = (texture(shirt_tex, h).rgb
				+ texture(shirt_tex, vec2(1.0 - h.x, h.y)).rgb
				+ texture(shirt_tex, vec2(h.x, 1.0 - h.y)).rgb
				+ texture(shirt_tex, vec2(1.0 - h.x, 1.0 - h.y)).rgb) * 0.25;
	} else {
		vec3 rel = clamp((v_local - aabb_min) / max(aabb_size, vec3(0.0001)), vec3(0.0), vec3(1.0));
		float u = dot(rel, width_dir);
		float v = 1.0 - rel.y;
		if (dot(nrm, depth_dir) * front_sign < 0.0) {
			u = 1.0 - u; // back faces: mirror-correct so the print reads right from behind
		}
		col = texture(shirt_tex, vec2(u, v)).rgb;
	}
	ALBEDO = col * tint.rgb;
	METALLIC = 0.0;
	ROUGHNESS = 1.0; // cotton tee — fully rough, like the StandardMaterial the base skin path uses
}
