shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, blend_add;

uniform vec3 laser_color : source_color = vec3(1.0, 0.0, 0.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.2;
uniform float fade_power : hint_range(0.1, 8.0) = 6.0;
uniform bool invert_fade = false;

void fragment() {
	float t = invert_fade ? (1.0 - UV.y) : UV.y;
	float fade = pow(1.0 - t, fade_power);
	ALBEDO = laser_color * intensity;
	// Put the fade on ALPHA so the beam composites through the view-model camera's transparent_bg
	// SubViewport as a clean fade-to-transparent instead of opaque BLACK (an additive beam with no real
	// alpha resolves to black there). Scale the alpha by `intensity` so the bright core stays clearly
	// VISIBLE — a plain `fade` alpha, with the steep fade_power, collapsed to near-transparent.
	ALPHA = clamp(intensity * fade, 0.0, 1.0);
}
