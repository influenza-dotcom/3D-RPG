shader_type canvas_item;

// Scope vignette: transparent at the centre, darkening to near-black toward the edges, for a
// "looking down the rifle scope" tunnel. Drawn over a full-rect ColorRect on the HUD while scoped
// (ui.gd toggles it). Default mix blend so it DARKENS (the lens-flare overlay handles brightening).

uniform float strength : hint_range(0.0, 1.0) = 0.98;  // how dark the very edges get
uniform float inner : hint_range(0.0, 1.5) = 0.2;      // radius where darkening begins (0 = centre)
uniform float outer : hint_range(0.0, 1.5) = 0.8;      // radius that reaches full darkness
uniform vec3 tint : source_color = vec3(0.0, 0.0, 0.0);

void fragment() {
	// Radial distance from screen centre, scaled so the corners sit near 1.0.
	vec2 d = UV - vec2(0.5);
	float dist = length(d) * 1.41421356;
	float v = smoothstep(inner, outer, dist) * strength;
	COLOR = vec4(tint, v);
}
