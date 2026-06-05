shader_type sky;

// A procedural night sky: a near-black vertical gradient with a sparse, gently twinkling starfield
// above the horizon. Applied at runtime by star_sky.gd (the level's sky is rendered black, so stars pop).

uniform vec3 sky_top : source_color = vec3(0.01, 0.02, 0.05);     // faint blue at the zenith
uniform vec3 sky_horizon : source_color = vec3(0.02, 0.03, 0.07); // a touch lighter near the horizon
uniform float star_density : hint_range(0.0, 0.1) = 0.02;         // fraction of grid cells that hold a star
uniform float star_brightness : hint_range(0.0, 4.0) = 1.8;
uniform float star_grid = 240.0;                                  // higher = smaller, denser-looking stars
uniform float twinkle_speed = 1.5;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	// Faint gradient so the sky isn't a flat void.
	float up = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(sky_horizon, sky_top, up);

	// Stars: hash a quantized view direction into sparse bright points, only above the horizon (fading in
	// off the horizon line so it stays clean), each with a gentle per-star twinkle.
	vec3 cell = floor(dir * star_grid);
	float h = hash13(cell);
	float star = step(1.0 - star_density, h);
	float above = smoothstep(0.0, 0.25, dir.y);
	float tw = 0.6 + 0.4 * sin(TIME * twinkle_speed + h * 6.2831);
	col += vec3(star * above * tw) * star_brightness;

	COLOR = col;
}
