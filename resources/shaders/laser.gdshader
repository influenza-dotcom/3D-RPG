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
	// Put the fade on ALPHA, not just ALBEDO. With blend_add the added light is ALBEDO * ALPHA, so the
	// beam looks IDENTICAL — but the gun renders through the view-model camera's transparent SubViewport,
	// and there an additive beam with no real alpha composites to opaque BLACK where it should be faint
	// (the reported "becomes more black"). A real alpha makes it composite as a clean fade-to-transparent.
	ALPHA = clamp(fade, 0.0, 1.0);
}
