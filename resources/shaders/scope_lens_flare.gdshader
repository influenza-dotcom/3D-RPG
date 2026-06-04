shader_type canvas_item;
render_mode blend_add;

// Procedural scope lens flare (asset-free): a horizontal anamorphic streak across the centre plus a
// soft central bloom, ADDED over the view while scoped. Additive so it only ever brightens. ui.gd
// toggles a full-rect ColorRect carrying this shader. Tune intensity for a subtler / blown-out glint.

uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform vec3 streak_color : source_color = vec3(0.55, 0.72, 1.0); // cool anamorphic blue-white
uniform float streak_thickness : hint_range(0.001, 0.2) = 0.014;  // vertical falloff of the streak
uniform float bloom_size : hint_range(0.001, 0.2) = 0.02;         // central glow spread

void fragment() {
	vec2 d = UV - vec2(0.5);
	// Horizontal streak: bright along the centre line (y=0.5), Gaussian falloff vertically, and
	// faded toward the left/right edges so it doesn't hit the frame at full strength.
	float vert = exp(-(d.y * d.y) / (streak_thickness * streak_thickness));
	float horiz = smoothstep(0.5, 0.0, abs(d.x));
	float streak = vert * horiz;
	// Soft round bloom at the optical centre.
	float bloom = exp(-dot(d, d) / bloom_size);
	float a = clamp((streak + bloom * 0.6) * intensity, 0.0, 1.0);
	// blend_add adds streak_color * a to the framebuffer.
	COLOR = vec4(streak_color, a);
}
